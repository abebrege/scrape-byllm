"""Deterministic page-fetch layer for scrape-byllm.

Uses Selenium (headless Chrome) instead of requests+BeautifulSoup so the
fetcher drives a real browser: JS-rendered pages work out of the box, and the
same live driver can later be reused for write/injection operations (filling
forms, clicking, executing scripts) as the project scales.

The driver is a lazily-created singleton held in `_driver_holder` and reused
across calls, so we pay browser-startup cost once. Call `quit_driver()` to tear
it down (the entry point in main.jac does this on exit).
"""

import from selenium { webdriver }
import from selenium.webdriver.chrome.options { Options }

glob MAX_CHARS: int = 40000;

# Single-element holder for the singleton driver. We mutate it in place rather
# than rebinding a glob so no `global` declaration is needed inside functions.
glob _driver_holder: list[any] = [];


# Return the shared headless-Chrome driver, creating it on first use.
def get_driver() -> any {
    if not _driver_holder {
        opts = Options();
        opts.add_argument("--headless=new");
        opts.add_argument("--no-sandbox");
        opts.add_argument("--disable-dev-shm-usage");
        opts.add_argument("--disable-gpu");
        opts.add_argument("--window-size=1920,1080");
        opts.add_argument("--user-agent=scrape-byllm/0.1");
        driver: any = webdriver.Chrome(options=opts);
        driver.set_page_load_timeout(30);
        _driver_holder.append(driver);
    }
    return _driver_holder[0];
}


def fetch_page(url: str) -> str {
    driver: any = get_driver();
    driver.get(url);
    # Strip noise in-browser and read the JS-rendered DOM back out.
    clean_js = "for (const el of document.querySelectorAll('script, style, noscript')) { el.remove(); } return document.documentElement.outerHTML;";
    html: str = str(driver.execute_script(clean_js));
    if len(html) > MAX_CHARS {
        return html[:MAX_CHARS];
    }
    return html;
}


# Shut down the shared driver and release the holder.
def quit_driver() {
    if _driver_holder {
        _driver_holder[0].quit();
        _driver_holder.clear();
    }
}
