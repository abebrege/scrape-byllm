"""Fetch layer for scrape-byLLM.

Two paths:
  - Static (render=False): requests.get — fast, no browser overhead, works for
    server-rendered pages.
  - Rendered (render=True): reuses the existing headless-Chrome singleton from
    lib/scraper.jac — needed for JS-heavy or dynamic pages.

normalize_source() converts any supported source form into a list of source dicts
so the orchestrator always sees a uniform shape:
  {"url": str, "html": str}   — html is "" when a URL needs fetching
                                 url is "" when html is already provided inline
"""

import from requests { get }
import from lib.scraper { fetch_page }


def _http_get(url: str, timeout: int) -> str {
    resp: any = get(
        url,
        timeout=timeout,
        headers={"User-Agent": "scrape-byLLM/0.2"}
    );
    return str(resp.text);
}


def fetch_one(url: str, render: bool = False, timeout: int = 20) -> str {
    if render {
        return fetch_page(url);
    }
    return _http_get(url, timeout);
}


def fetch_many(urls: list[str], render: bool = False, timeout: int = 20) -> list[dict] {
    results: list[dict] = [];
    for url in urls {
        html: str = fetch_one(url, render, timeout);
        results.append({"url": url, "html": html});
    }
    return results;
}


def normalize_source(source: any) -> list[dict] {
    if isinstance(source, list) {
        items: list[dict] = [];
        for s in source {
            items = items + normalize_source(s);
        }
        return items;
    }
    if isinstance(source, str) {
        if source.startswith("http://") or source.startswith("https://") {
            return [{"url": source, "html": ""}];
        }
        return [{"url": "", "html": source}];
    }
    return [];
}
