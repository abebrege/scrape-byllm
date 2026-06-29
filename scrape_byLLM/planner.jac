import from byllm.lib { Model }
import from scrape_byLLM.presets { preset_table }
import from scrape_byLLM.guard_llm { check_injection, validate_regex_plan, validate_synthesis, llm_cache_key, cache_get_llm, cache_put_llm }

glob llm = Model(model_name="anthropic/claude-sonnet-4-6");

glob _PLAN_CACHE: dict[str, RegexPlan] = {};


"""A compiled, reusable extraction plan. Produced once by the LLM, cached and
reused deterministically across every subsequent page."""
obj RegexPlan {
    has strategy: str;
    has patterns: list[str];
    has on: str;
    has window: int = 200;
    has notes: str = "";
}

sem RegexPlan = "A compiled regex extraction plan produced once and applied to every page without further LLM calls.";
sem RegexPlan.strategy = "How the plan was produced: 'preset' (selected from known HTML patterns) or 'custom' (LLM-generated regex for semantic content such as crypto tickers or person names).";
sem RegexPlan.patterns = "Python re-compatible regex strings to run against the page. Capture groups are optional; the executor captures the full match plus window chars of context either side.";
sem RegexPlan.on = "Surface to run patterns against: 'html' for structural targets (links, images, tables) or 'text' for semantic targets where visible text is more reliable than markup.";
sem RegexPlan.window = "Characters of surrounding context to capture on each side of a match (the ±N window). Default 200.";
sem RegexPlan.notes = "Planner rationale or debug notes; empty string if the planner provided none.";


"""Structured synthesis of raw scrape snippets, produced by a single LLM call."""
obj Synthesis {
    has summary: str;
    has items: list[str];
    has notes: str = "";
}

sem Synthesis = "A structured synthesis of raw scrape results produced by a single LLM call after scraping.";
sem Synthesis.summary = "Concise paragraph summarising what was found relative to the original query.";
sem Synthesis.items = "Discrete extracted items inferred from the query — e.g. names, prices, module names, URLs. Empty list if nopattern relevant was found.";
sem Synthesis.notes = "Any caveats, ambiguities, or follow-up suggestions from the model. Empty string if none.";


"""Return the single pattern name from available_patterns that best matches
what the user wants to extract. Return exactly one name from the list — no
explanation, no punctuation."""
def choose_pattern(query: str, available_patterns: list[str]) -> str by llm(temperature=0.0);


"""
Decide how to extract the requested query from html.

Prefer selecting and lightly parameterizing a pattern from `available_regexes`.
If the target is a semantic content category that HTML structure cannot reliably
"""
def compile_query_to_plan(
    pattern: str,
    query: str,
    sample_html: str,
    available_regexes: dict[str, str]
) -> RegexPlan by llm(temperature=0.0);


"""Read the flat snippet text from every scraped page and extract the
information the user is after, inferring intent from the original query.
Return a clean, structured synthesis without fabricating facts not present
in the snippets."""
def synthesize_results(
    query: str,
    pattern: str,
    snippets: str
) -> Synthesis by llm(temperature=0.2);


def get_plan(pattern: str, query: str, sample_html: str, html_sample_size: int = 6000, ctx: any = None) -> RegexPlan {
    effective_ctx: dict = {};
    if isinstance(ctx, dict) {
        effective_ctx = ctx;
    }
    key: str = pattern + "::" + query;
    if key not in _PLAN_CACHE {
        plan: RegexPlan = guarded_compile_query_to_plan(
            pattern, query, sample_html[:html_sample_size], preset_table(), effective_ctx
        );
        _PLAN_CACHE[key] = plan;
        effective_ctx["_llm_calls"] = int(effective_ctx.get("_llm_calls", 0)) + 1;
    }
    return _PLAN_CACHE[key];
}


def preset_plan(pattern: str) -> RegexPlan {
    regexes: dict[str, str] = preset_table();
    pat: str = str(regexes.get(pattern, ""));
    pats: list[str] = [];
    if pat {
        pats = [pat];
    }
    surface: str = "text";
    if pattern != "text" {
        surface = "html";
    }
    return RegexPlan(
        strategy="preset",
        patterns=pats,
        on=surface,
        notes="direct preset, no query"
    );
}


def guarded_compile_query_to_plan(
    pattern: str,
    query: str,
    sample_html: str,
    available_regexes: dict[str, str],
    ctx: any = None
) -> RegexPlan {
    effective_ctx: dict = {};
    if isinstance(ctx, dict) {
        effective_ctx = ctx;
    }

    check_injection(sample_html, effective_ctx);

    ck: str = llm_cache_key("anthropic/claude-sonnet-4-6", "plan", query, pattern, sample_html);
    cached: any = cache_get_llm(ck, effective_ctx);
    if cached is not None {
        safe_pats: list[str] = validate_regex_plan(list(cached.get("patterns", [])), effective_ctx);
        return RegexPlan(
            strategy=str(cached.get("strategy", "custom")),
            patterns=safe_pats,
            on=str(cached.get("on", "html")),
            window=int(cached.get("window", 200)),
            notes=str(cached.get("notes", ""))
        );
    }

    mode: str = str(effective_ctx.get("cache", "off"));
    if mode == "readonly" {
        raise RuntimeError("LLM cache miss in readonly mode for plan compilation");
    }

    plan: RegexPlan = compile_query_to_plan(pattern, query, sample_html, available_regexes);

    safe_patterns: list[str] = validate_regex_plan(list(plan.patterns), effective_ctx);

    plan_dict: dict = {
        "strategy": plan.strategy,
        "patterns": safe_patterns,
        "on":       plan.on,
        "window":   plan.window,
        "notes":    plan.notes
    };
    cache_put_llm(ck, plan_dict, effective_ctx);

    return RegexPlan(
        strategy=plan.strategy,
        patterns=safe_patterns,
        on=plan.on,
        window=plan.window,
        notes=plan.notes
    );
}


def guarded_synthesize_results(
    query: str,
    pattern: str,
    snippets: str,
    ctx: any = None
) -> Synthesis {
    effective_ctx: dict = {};
    if isinstance(ctx, dict) {
        effective_ctx = ctx;
    }

    check_injection(snippets, effective_ctx);

    ck: str = llm_cache_key("anthropic/claude-sonnet-4-6", "synthesize", query, pattern, snippets);
    cached: any = cache_get_llm(ck, effective_ctx);
    if cached is not None {
        cleaned: dict = validate_synthesis(dict(cached), effective_ctx);
        return Synthesis(
            summary=str(cleaned.get("summary", "")),
            items=list(cleaned.get("items", [])),
            notes=str(cleaned.get("notes", ""))
        );
    }

    mode: str = str(effective_ctx.get("cache", "off"));
    if mode == "readonly" {
        raise RuntimeError("LLM cache miss in readonly mode for synthesis");
    }

    synthesis: Synthesis = synthesize_results(query, pattern, snippets);
    effective_ctx["_llm_calls"] = int(effective_ctx.get("_llm_calls", 0)) + 1;

    raw: dict = {
        "summary": synthesis.summary,
        "items":   synthesis.items,
        "notes":   synthesis.notes
    };
    validated: dict = validate_synthesis(raw, effective_ctx);
    cache_put_llm(ck, validated, effective_ctx);

    return Synthesis(
        summary=str(validated.get("summary", "")),
        items=list(validated.get("items", [])),
        notes=str(validated.get("notes", ""))
    );
}
