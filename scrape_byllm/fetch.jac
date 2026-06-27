"""Page acquisition for scrape-byLLM.

One module owns every way a page can enter the pipeline, plus the browser
lifecycle (previously split across fetch.jac + scraper.jac):

  - Static  (render=False): requests.get — fast, no browser, server-rendered pages.
  - Rendered (render=True): a headless-Chrome singleton — JS-heavy / dynamic pages.

normalize_source() collapses any supported source form (URL, list of URLs, raw
HTML, or plain text) into a uniform list of source dicts:
  {"url": str, "html": str}   — html is "" when a URL must be fetched,
                                 url is "" when html is provided inline.
"""

import from requests { get }
import from selenium { webdriver }
import from selenium.webdriver.chrome.options { Options }

glob MAX_CHARS: int = 40000;

glob _driver_holder: list[any] = [];


def _get_driver() -> any {
    if not _driver_holder {
        opts = Options();
        opts.add_argument("--headless=new");
        opts.add_argument("--no-sandbox");
        opts.add_argument("--disable-dev-shm-usage");
        opts.add_argument("--disable-gpu");
        opts.add_argument("--window-size=1920,1080");
        opts.add_argument("--user-agent=scrape-byLLM/0.1");
        driver: any = webdriver.Chrome(options=opts);
        driver.set_page_load_timeout(30);
        _driver_holder.append(driver);
    }
    return _driver_holder[0];
}


def _fetch_rendered(url: str) -> str {
    driver: any = _get_driver();
    driver.get(url);
    clean_js = "for (const el of document.querySelectorAll('script, style, noscript')) { el.remove(); } return document.documentElement.outerHTML;";
    html: str = str(driver.execute_script(clean_js));
    if len(html) > MAX_CHARS {
        return html[:MAX_CHARS];
    }
    return html;
}


def _http_get(url: str, timeout: int) -> str {
    resp: any = get(
        url,
        timeout=timeout,
        headers={"User-Agent": "scrape-byLLM/0.2"}
    );
    return str(resp.text);
}


def quit_driver() {
    if _driver_holder {
        _driver_holder[0].quit();
        _driver_holder.clear();
    }
}


def fetch_one(url: str, render: bool = False, timeout: int = 20) -> str {
    if render {
        return _fetch_rendered(url);
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
