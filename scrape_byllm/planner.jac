"""The LLM brain of scrape-byLLM.

Everything that talks to the model lives here:
  - compile_query_to_plan: turns a natural-language query into a reusable RegexPlan
    (called ONCE per (thing, query) pair, then cached).
  - synthesize_results: optional second pass that reads the raw snippets and
    extracts the information the user actually asked for.

Cost guarantee: scraping N pages = 1 planning call + (N-1) pure-regex
executions. Synthesis, when enabled, adds at most 1 further call.
"""

import from byllm.lib { Model }
import from scrape_byLLM.presets { preset_table }

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


"""Structured synthesis of raw scrape snippets, produced by a single LLM call."""
obj Synthesis {
    has summary: str;
    has items: list[str];
    has notes: str = "";
}

sem Synthesis = "A structured synthesis of raw scrape results produced by a single LLM call after scraping.";
sem Synthesis.summary = "Concise paragraph summarising what was found relative to the original query.";
sem Synthesis.items = "Discrete extracted items inferred from the query — e.g. names, prices, module names, URLs. Empty list if nothing relevant was found.";
sem Synthesis.notes = "Any caveats, ambiguities, or follow-up suggestions from the model. Empty string if none.";


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


"""Read the flat snippet text from every scraped page and extract the
information the user is after, inferring intent from the original query.
Return a clean, structured synthesis without fabricating facts not present
in the snippets."""
def synthesize_results(
    query: str,
    thing: str,
    snippets: str
) -> Synthesis by llm(temperature=0.2);


def get_plan(thing: str, query: str, sample_html: str) -> RegexPlan {
    key = thing + "::" + query;
    if key not in _PLAN_CACHE {
        plan: RegexPlan = compile_query_to_plan(
            thing, query, sample_html[:6000], preset_table()
        );
        _PLAN_CACHE[key] = plan;
    }
    return _PLAN_CACHE[key];
}


def preset_plan(thing: str) -> RegexPlan {
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
