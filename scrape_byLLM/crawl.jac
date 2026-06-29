import from bs4 { BeautifulSoup }
import from urllib.parse { urljoin, urlparse }
import from re { compile as re_compile, IGNORECASE as RE_IGNORECASE }
import from scrape_byLLM.fetch { fetch_one }
import from scrape_byLLM.executor { extract, dedup }
import from scrape_byLLM.planner { preset_plan, get_plan, guarded_synthesize_results }
import from scrape_byLLM.presets { preset_table }
import from scrape_byLLM.output { write_output }
import from scrape_byLLM.guard_fetch { SSRFError, validate_url_ssrf, canonicalize_url }

def _extract_links(html: str, base_url: str) -> list[str] {
    links: list[str] = [];
    soup: any = BeautifulSoup(html, "lxml");
    for tag in soup.find_all("a", href=True) {
        href: str = str(tag["href"]);
        absolute: str = str(urljoin(base_url, href));
        if absolute.startswith("http://") or absolute.startswith("https://") {
            links.append(absolute);
        }
    }
    return links;
}

def _find_next_page(html: str, current_url: str) -> str {
    soup: any = BeautifulSoup(html, "lxml");

    link_next: any = soup.find("link", rel="next");
    if link_next and link_next.get("href") {
        return str(urljoin(current_url, str(link_next["href"])));
    }

    a_next: any = soup.find("a", rel="next");
    if a_next and a_next.get("href") {
        return str(urljoin(current_url, str(a_next["href"])));
    }

    aria_next: any = soup.find("a", attrs={"aria-label": "Next"});
    if aria_next and aria_next.get("href") {
        return str(urljoin(current_url, str(aria_next["href"])));
    }

    cls_next: any = soup.find("a", class_="next");
    if cls_next and cls_next.get("href") {
        return str(urljoin(current_url, str(cls_next["href"])));
    }

    return "";
}

def _same_domain(url: str, seed: str) -> bool {
    seed_host: str = str(urlparse(seed).hostname or "");
    url_host: str = str(urlparse(url).hostname or "");
    return url_host == seed_host;
}

def _allowed_domain(url: str, allowed_domains: list[str]) -> bool {
    if not allowed_domains {
        return True;
    }
    url_host: str = str(urlparse(url).hostname or "");
    for domain in allowed_domains {
        if url_host == domain or url_host.endswith("." + domain) {
            return True;
        }
    }
    return False;
}

def crawl(
    seed: str,
    query: str,
    pattern: str,
    max_depth: int = 2,
    max_pages: int = 20,
    same_domain: bool = True,
    allowed_domains: list[str] = [],
    follow_pattern: str = "",
    exclude_pattern: str = "",
    paginate: bool = False,
    opts: any = None
) -> dict {
    effective_opts: dict = {};
    if isinstance(opts, dict) {
        effective_opts = opts;
    }

    follow_rx: any = None;
    if follow_pattern {
        try {
            follow_rx = re_compile(follow_pattern, RE_IGNORECASE);
        } except Exception {
            follow_rx = None;
        }
    }

    exclude_rx: any = None;
    if exclude_pattern {
        try {
            exclude_rx = re_compile(exclude_pattern, RE_IGNORECASE);
        } except Exception {
            exclude_rx = None;
        }
    }

    frontier: list = [[seed, 0]];
    visited: set = set();
    pages_crawled: int = 0;
    all_results: list = [];

    scrape_plan: any = preset_plan(pattern);
    window: int = int(effective_opts.get("window", 200));
    html_sample_size: int = int(effective_opts.get("html_sample_size", 6000));

    while frontier and pages_crawled < max_pages {
        item: list = frontier.pop(0);
        current_url: str = str(item[0]);
        depth: int = int(item[1]);

        canon: str = canonicalize_url(current_url);
        if canon in visited {
            continue;
        }

        try {
            validate_url_ssrf(current_url, effective_opts);
        } except Exception {
            effective_opts["blocked_urls"] = int(effective_opts.get("blocked_urls", 0)) + 1;
            continue;
        }

        visited.add(canon);

        html: str = "";
        try {
            html = fetch_one(
                current_url,
                bool(effective_opts.get("render", False)),
                int(effective_opts.get("timeout", 20)),
                int(effective_opts.get("max_chars", 40000)),
                bool(effective_opts.get("respect_robots", True)),
                str(effective_opts.get("user_agent", "scrape-byLLM")),
                dict(effective_opts.get("extra_headers", {})),
                float(str(effective_opts.get("rate_limit", 0.0))),
                effective_opts
            );
        } except Exception as e {
            all_results.append({"source": current_url, "depth": depth, "snippets": [], "error": str(e)});
            continue;
        }

        pages_crawled = pages_crawled + 1;

        if query and pages_crawled == 1 {
            scrape_plan = get_plan(pattern, query, html, html_sample_size, effective_opts);
        }

        snippets: list[str] = extract(scrape_plan, html, window);
        if bool(effective_opts.get("dedup", True)) {
            snippets = dedup(snippets);
        }
        all_results.append({"source": current_url, "depth": depth, "snippets": snippets});

        if depth < max_depth {
            new_links: list[str] = _extract_links(html, current_url);

            if paginate {
                next_url: str = _find_next_page(html, current_url);
                if next_url {
                    next_canon: str = canonicalize_url(next_url);
                    if next_canon not in visited {
                        frontier.insert(0, [next_url, depth]);
                    }
                }
            }

            for link in new_links {
                link_canon: str = canonicalize_url(link);
                if link_canon in visited {
                    continue;
                }
                if same_domain and not _same_domain(link, seed) {
                    continue;
                }
                if not _allowed_domain(link, allowed_domains) {
                    continue;
                }
                if follow_rx is not None and not follow_rx.search(link) {
                    continue;
                }
                if exclude_rx is not None and exclude_rx.search(link) {
                    continue;
                }
                try {
                    validate_url_ssrf(link, effective_opts);
                    frontier.append([link, depth + 1]);
                } except Exception {
                    effective_opts["blocked_urls"] = int(effective_opts.get("blocked_urls", 0)) + 1;
                }
            }
        }
    }

    effective_opts["_pages_crawled"] = pages_crawled;

    out: dict = {
        "pattern":      pattern,
        "query":        query,
        "strategy":     scrape_plan.strategy,
        "on":           scrape_plan.on,
        "patterns":     scrape_plan.patterns,
        "page_count":   pages_crawled,
        "pages_crawled": pages_crawled,
        "llm_calls":    int(effective_opts.get("_llm_calls", 0)),
        "fetch_hits":   int(effective_opts.get("fetch_hits", 0)),
        "fetch_misses": int(effective_opts.get("fetch_misses", 0)),
        "blocked_urls": int(effective_opts.get("blocked_urls", 0)),
        "results":      all_results
    };

    if bool(effective_opts.get("synthesize", False)) and query {
        flat_parts: list[str] = [];
        for r in all_results {
            r_any: any = r;
            for sn in list(r_any.get("snippets", [])) {
                flat_parts.append("[" + str(r_any.get("source", "")) + "] " + str(sn));
            }
        }
        flat: str = "\n".join(flat_parts);
        synthesis: any = guarded_synthesize_results(query, pattern, flat, effective_opts);
        out["synthesis"] = {
            "summary": synthesis.summary,
            "items":   synthesis.items,
            "notes":   synthesis.notes
        };
        out["llm_calls"] = int(out["llm_calls"]) + 1;
    }

    return write_output(out, effective_opts.get("output"));
}
