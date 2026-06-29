import from scrape_byLLM.fetch { fetch_one, normalize_source, quit_driver }
import from scrape_byLLM.executor { extract, dedup }
import from scrape_byLLM.planner { get_plan, preset_plan, choose_pattern, guarded_synthesize_results }
import from scrape_byLLM.presets { preset_table }
import from scrape_byLLM.output { write_output }


def spawn_scrape(pattern: str, source: any, query: str, opts: dict) -> dict {
    sources: list[dict] = normalize_source(source);
    plan: any = preset_plan(pattern);
    results: list = [];

    window: int = int(opts.get("window", 200));
    html_sample_size: int = int(opts.get("html_sample_size", 6000));

    if sources {
        first_src: any = sources[0];
        try {
            first_html: str = _get_html(first_src, opts);
            if query {
                plan = get_plan(pattern, query, first_html, html_sample_size, opts);
            }
            first_snippets: list[str] = extract(plan, first_html, window);
            if bool(opts.get("dedup", True)) {
                first_snippets = dedup(first_snippets);
            }
            results.append({"source": _source_label(first_src), "snippets": first_snippets});
        } except Exception as e {
            results.append({"source": _source_label(first_src), "snippets": [], "error": str(e)});
        }

        for src in sources[1:] {
            src_any: any = src;
            try {
                html: str = _get_html(src_any, opts);
                snippets: list[str] = extract(plan, html, window);
                if bool(opts.get("dedup", True)) {
                    snippets = dedup(snippets);
                }
                results.append({"source": _source_label(src_any), "snippets": snippets});
            } except Exception as e {
                results.append({"source": _source_label(src_any), "snippets": [], "error": str(e)});
            }
        }
    }

    out: dict = {
        "pattern":      pattern,
        "query":        query,
        "strategy":     plan.strategy,
        "on":           plan.on,
        "patterns":     plan.patterns,
        "page_count":   len(sources),
        "llm_calls":    int(opts.get("_llm_calls", 0)),
        "fetch_hits":   int(opts.get("fetch_hits", 0)),
        "fetch_misses": int(opts.get("fetch_misses", 0)),
        "blocked_urls": int(opts.get("blocked_urls", 0)),
        "pages_crawled": int(opts.get("_pages_crawled", 0)),
        "results":      results
    };

    if bool(opts.get("synthesize", False)) {
        flat: str = _collect_snippets(out);
        synthesis: any = guarded_synthesize_results(query, pattern, flat, opts);
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
    respect_robots: bool = bool(opts.get("respect_robots", True));
    user_agent: str = str(opts.get("user_agent", "scrape-byLLM"));
    extra_headers: dict = dict(opts.get("extra_headers", {}));
    rate_limit_raw: any = opts.get("rate_limit", 0.0);
    rate_limit: float = float(str(rate_limit_raw));
    url: str = str(src.get("url", ""));
    return fetch_one(url, render, timeout, max_chars, respect_robots, user_agent, extra_headers, rate_limit, opts);
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


obj ScrapeByLLM {
    has _env: dict = {};

    def postinit() {
        self._env = {
            "window":             200,
            "max_chars":          200000,
            "timeout":            20,
            "render":             False,
            "dedup":              True,
            "synthesize":         False,
            "output":             None,
            "html_sample_size":   6000,
            "respect_robots":     True,
            "user_agent":         "scrape-byLLM",
            "extra_headers":      {},
            "rate_limit":         0.0,
            "ssrf_protection":    True,
            "allow_private_ips":  False,
            "allowed_hosts":      [],
            "blocked_hosts":      [],
            "cache":              "off",
            "cache_dir":          ".scrape_cache",
            "cache_ttl":          0,
            "cache_llm":          True,
            "proxies":            [],
            "proxy_rotation":     "round_robin",
            "proxy_max_failures": 3,
            "injection_guard":    True,
            "regex_timeout":      1.0,
        };
    }

    def set(key: str, val: any) {
        self._env[key] = val;
    }

    def get(key: str) -> any {
        return self._env.get(key);
    }

    def get_all(source: any, query: str) -> dict {
        pattern: any = choose_pattern(query, list(preset_table().keys()));
        return spawn_scrape(pattern=str(pattern), source=source, query=query, opts=self._env);
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
sem ScrapeByLLM._env = "Runtime configuration. Keys: window, max_chars, timeout, render, dedup, synthesize, output, html_sample_size, respect_robots, user_agent, extra_headers, rate_limit, ssrf_protection, allow_private_ips, allowed_hosts, blocked_hosts, cache, cache_dir, cache_ttl, cache_llm, proxies, proxy_rotation, proxy_max_failures, injection_guard, regex_timeout.";


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
