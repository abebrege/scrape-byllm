import from scrape_byLLM.fetch { fetch_one, normalize_source, quit_driver }
import from scrape_byLLM.executor { extract, dedup }
import from scrape_byLLM.planner { get_plan, preset_plan, synthesize_results }
import from scrape_byLLM.output { write_output }


def spawn_scrape(pattern: str, source: any, query: str, opts: dict) -> dict {
    sources: list[dict] = normalize_source(source);
    llm_calls: int = 0;
    plan: any = preset_plan(pattern);
    results: list = [];

    window: int = int(opts.get("window", 200));
    html_sample_size: int = int(opts.get("html_sample_size", 6000));

    if sources {
        first_src: any = sources[0];
        first_html: str = _get_html(first_src, opts);

        if query {
            plan = get_plan(pattern, query, first_html, html_sample_size);
            llm_calls = 1;
        }
        first_snippets: list[str] = extract(plan, first_html, window);
        if bool(opts.get("dedup", True)) {
            first_snippets = dedup(first_snippets);
        }
        results.append({"source": _source_label(first_src), "snippets": first_snippets});

        for src in sources[1:] {
            src_any: any = src;
            html: str = _get_html(src_any, opts);
            snippets: list[str] = extract(plan, html, window);
            if bool(opts.get("dedup", True)) {
                snippets = dedup(snippets);
            }
            results.append({"source": _source_label(src_any), "snippets": snippets});
        }
    }

    out: dict = {
        "pattern":      pattern,
        "query":        query,
        "strategy":     plan.strategy,
        "on":           plan.on,
        "patterns":     plan.patterns,
        "page_count":   len(sources),
        "llm_calls":    llm_calls,
        "results":      results
    };

    if bool(opts.get("synthesize", False)) {
        flat: str = _collect_snippets(out);
        synthesis: any = synthesize_results(query, pattern, flat);
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
    max_chars: int = int(opts.get("max_chars", 40000));
    url: str = str(src.get("url", ""));
    return fetch_one(url, render, timeout, max_chars);
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


class ScrapeByLLM {
    has _env: dict = {};

    def postinit() {
        self._env = {
            "window":           200,
            "max_chars":        40000,
            "timeout":          20,
            "render":           False,
            "dedup":            True,
            "synthesize":       False,
            "output":           None,
            "html_sample_size": 6000
        };
    }

    def set(key: str, val: any) {
        self._env[key] = val;
    }

    def get(key: str) -> any {
        return self._env.get(key);
    }

    def get_all(pattern: str, source: any, query: str = "") -> dict {
        return spawn_scrape(pattern=pattern, source=source, query=query, opts=self._env);
    }

    def get_all_links(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="links", source=source, query=query, opts=self._env);
    }

    def get_all_images(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="images", source=source, query=query, opts=self._env);
    }

    def get_all_prices(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="prices", source=source, query=query, opts=self._env);
    }

    def get_all_emails(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="emails", source=source, query=query, opts=self._env);
    }

    def get_all_phones(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="phones", source=source, query=query, opts=self._env);
    }

    def get_all_tables(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="tables", source=source, query=query, opts=self._env);
    }

    def get_all_headings(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="headings", source=source, query=query, opts=self._env);
    }

    def get_all_text(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="text", source=source, query=query, opts=self._env);
    }

    def get_all_charts(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="charts", source=source, query=query, opts=self._env);
    }

    def get_all_code(source: any, query: str = "") -> dict {
        return spawn_scrape(pattern="code", source=source, query=query, opts=self._env);
    }

    def quit() {
        quit_driver();
    }
}

sem ScrapeByLLM = "Stateful scraper instance. Configure once with .set(), then call .get_all_*() for each target — the compiled plan is reused across pages.";
sem ScrapeByLLM._env = "Runtime configuration. Keys: window (int, default 200), max_chars (int, default 40000), timeout (int, default 20), render (bool, default False), dedup (bool, default True), synthesize (bool, default False), output (str|None, default None), html_sample_size (int, default 6000).";


def get_all(pattern: str, source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern=pattern, source=source, query=query, opts=opts);
}

def get_all_links(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="links", source=source, query=query, opts=opts);
}

def get_all_images(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="images", source=source, query=query, opts=opts);
}

def get_all_prices(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="prices", source=source, query=query, opts=opts);
}

def get_all_emails(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="emails", source=source, query=query, opts=opts);
}

def get_all_phones(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="phones", source=source, query=query, opts=opts);
}

def get_all_tables(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="tables", source=source, query=query, opts=opts);
}

def get_all_headings(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="headings", source=source, query=query, opts=opts);
}

def get_all_text(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="text", source=source, query=query, opts=opts);
}

def get_all_charts(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="charts", source=source, query=query, opts=opts);
}

def get_all_code(source: any, query: str = "", opts: dict = {}) -> dict {
    return spawn_scrape(pattern="code", source=source, query=query, opts=opts);
}
