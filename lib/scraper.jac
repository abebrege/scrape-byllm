import from selenium { webdriver }
import from selenium.webdriver.chrome.options { Options }

glob MAX_CHARS: int = 40000;

glob _driver_holder: list[any] = [];


def get_driver() -> any {
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


def fetch_page(url: str) -> str {
    driver: any = get_driver();
    driver.get(url);
    clean_js = "for (const el of document.querySelectorAll('script, style, noscript')) { el.remove(); } return document.documentElement.outerHTML;";
    html: str = str(driver.execute_script(clean_js));
    if len(html) > MAX_CHARS {
        return html[:MAX_CHARS];
    }
    return html;
}


def quit_driver() {
    if _driver_holder {
        _driver_holder[0].quit();
        _driver_holder.clear();
    }
}
