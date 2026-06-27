"""scrape-byllm: LLM-planned, regex-executed web scraper.

Cost amortization guarantee:
  The LLM is called ONCE per (thing, query) pair to compile a RegexPlan.
  That plan is cached and applied deterministically to every subsequent page.
  Scraping N pages = 1 LLM call + (N-1) pure-regex executions.

compile_query_to_plan returns a custom obj (RegexPlan) and therefore must be defined in the entry module. Everything else is imported from lib/.
"""

import from byllm.lib { Model }
import from dotenv { load_dotenv }
import from lib.regexes { preset_table }
import from lib.executor { extract, dedup }
import from lib.fetch { fetch_one, normalize_source }
import from lib.scraper { quit_driver }
import from sys { argv }
import from os { makedirs }
import from json { dumps }

glob llm = Model(model_name="anthropic/claude-sonnet-4-6");

glob _PLAN_CACHE: dict = {};


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


"""
Decide how to extract the requested query from html.

Prefer selecting and lightly parameterizing a pattern from `available_regexes`.
If the target is a semantic content category that HTML structure cannot reliably
"""
def compile_query_to_plan(
    thing: str,
    query: str,
    sample_html: str,
    available_regexes: dict[str, str]
) -> RegexPlan by llm(temperature=0.0);


def get_plan(thing: str, query: str, sample_html: str) -> any {
    key = thing + "::" + query;
    if key not in _PLAN_CACHE {
        plan: RegexPlan = compile_query_to_plan(
            thing, query, sample_html[:6000], preset_table()
        );
        _PLAN_CACHE[key] = plan;
    }
    return _PLAN_CACHE[key];
}

def preset_plan(thing: str) -> any {
    regexes: dict[str, str] = preset_table();
    pat: str = str(regexes.get(thing, ""));
    pats: list[str] = [];
    if pat {
        pats = [pat];
    }
    surface: str = "text";
    if thing != "text" {
        surface = "html";
    }
    return RegexPlan(
        strategy="preset",
        patterns=pats,
        on=surface,
        notes="direct preset, no query"
    );
}



"""Fetch this url or urls; return html snippets as a json dict.

Contract: receives a source (URL, list of URLs, raw HTML, or plain text),
fetches pages deterministically using a RegexPlan compiled from a single LLM call,
and returns structured JSON with one snippet list per source.
LLM is called at most once regardless of page count.
"""
def spawn_scrape(thing: str, source: any, query: str, opts: dict) -> dict {
    sources: list[dict] = normalize_source(source);
    llm_calls: int = 0;
    plan: any = preset_plan(thing);
    results: list = [];

    if sources {
        first_src: any = sources[0];
        first_html: str = _get_html(first_src, opts);

        if query {
            plan = get_plan(thing, query, first_html);
            llm_calls = 1;
        }
        # TODO: E1053 any should satisfy all parameter types
        first_snippets: list[str] = extract(plan, first_html);
        if bool(opts.get("dedup", True)) {
            first_snippets = dedup(first_snippets);
        }
        results.append({"source": _source_label(first_src), "snippets": first_snippets});

        for src in sources[1:] {
            src_any: any = src;
            html: str = _get_html(src_any, opts);
            snippets: list[str] = extract(plan, html);
            if bool(opts.get("dedup", True)) {
                snippets = dedup(snippets);
            }
            results.append({"source": _source_label(src_any), "snippets": snippets});
        }
    }

    return {
        "thing":      thing,
        "query":      query,
        "strategy":   plan.strategy,
        "on":         plan.on,
        "patterns":   plan.patterns,
        "page_count": len(sources),
        "llm_calls":  llm_calls,
        "results":    results
    };
}

def _get_html(src: any, opts: dict) -> str {
    cached: any = src.get("html");
    if cached {
        return str(cached);
    }
    render: bool = bool(opts.get("render", False));
    timeout: int = int(opts.get("timeout", 20));
    url: str = str(src.get("url", ""));
    return fetch_one(url, render, timeout);
}

def _source_label(src: any) -> str {
    url: any = src.get("url");
    if url {
        return str(url);
    }
    return "<inline>";
}


def get_all(thing: str, source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing=thing, source=source, query=query, opts=opts);
}

def get_all_links(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="links", source=source, query=query, opts=opts);
}

def get_all_images(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="images", source=source, query=query, opts=opts);
}

def get_all_prices(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="prices", source=source, query=query, opts=opts);
}

def get_all_emails(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="emails", source=source, query=query, opts=opts);
}

def get_all_phones(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="phones", source=source, query=query, opts=opts);
}

def get_all_tables(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="tables", source=source, query=query, opts=opts);
}

def get_all_headings(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="headings", source=source, query=query, opts=opts);
}

def get_all_text(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="text", source=source, query=query, opts=opts);
}

def get_all_charts(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="charts", source=source, query=query, opts=opts);
}

def get_all_code(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(thing="code", source=source, query=query, opts=opts);
}


def _resolve_output_path(args: list[str]) -> str {
    makedirs("data", exist_ok=True);
    i: int = 0;
    while i < len(args) {
        if args[i] in ["--output", "-o"] and i + 1 < len(args) {
            return str(args[i + 1]);
        }
        i += 1;
    }
    return "data/out.json";
}

with entry {
    load_dotenv();

    out = get_all_prices(
        source="https://docs.oracle.com/javase/8/docs/api/javax/crypto/package-summary.html",
        query="get all crypto modules exposed by this library"
    );

    out_path: str = _resolve_output_path(argv);
    with open(out_path, "w") as f {
        f.write(dumps(out, indent=2));
    }
    print("wrote", len(str(out)), "chars to", out_path);

    quit_driver();
}
