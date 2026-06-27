"""Orchestration and public API for scrape-byLLM.

spawn_scrape is the one engine: it normalizes the source, compiles a RegexPlan
from a single LLM call (only when a query is given), then applies that plan
deterministically to every page. Two opt-in hooks ride on the same call:

  opts["synthesize"]: bool        -> run one extra LLM pass over the snippets,
                                     attaching a structured "synthesis" block.
  opts["output"]: str | bool      -> also write the result dict to disk as JSON
                                     (see output.write_output). Default: no write.

Other opts: render (selenium), timeout (seconds), dedup (default True).

The get_all_* family are thin presets over spawn_scrape, one per `thing`.
"""

import from scrape_byLLM.fetch { fetch_one, normalize_source, quit_driver }
import from scrape_byLLM.executor { extract, dedup }
import from scrape_byLLM.planner { get_plan, preset_plan, synthesize_results }
import from scrape_byLLM.output { write_output }


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

    out: dict = {
        "thing":      thing,
        "query":      query,
        "strategy":   plan.strategy,
        "on":         plan.on,
        "patterns":   plan.patterns,
        "page_count": len(sources),
        "llm_calls":  llm_calls,
        "results":    results
    };

    if bool(opts.get("synthesize", False)) {
        flat: str = _collect_snippets(out);
        synthesis: any = synthesize_results(query, thing, flat);
        out["synthesis"] = {
            "summary": synthesis.summary,
            "items":   synthesis.items,
            "notes":   synthesis.notes
        };
        out["llm_calls"] = int(out["llm_calls"]) + 1;
    }

    return write_output(out, opts.get("output"));
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


def _collect_snippets(out: dict[str, any]) -> str {
    parts: list[str] = [];
    results: list[any] = list(out.get("results", []));
    for result in results {
        result_any: any = result;
        src: str = str(result_any.get("source", ""));
        snippets: list[any] = list(result_any.get("snippets", []));
        for snippet in snippets {
            parts.append("[" + src + "] " + str(snippet));
        }
    }
    return "\n".join(parts);
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
