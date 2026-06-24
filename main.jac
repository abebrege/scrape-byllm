"""Selenium web scraping from Jac.

Jac is a superset of Python, so any PyPI package works. Import syntax differs
slightly from Python:
  Python:  from selenium import webdriver
  Jac:     import from selenium { webdriver }
  Python:  import time
  Jac:     import time;   (plain imports are identical, just end with ;)
"""

import from selenium { webdriver }
import from selenium.webdriver.chrome.options { Options }
import from selenium.webdriver.common.by { By }


"""Build a headless Chrome driver. Selenium Manager auto-fetches the driver."""
def make_driver -> any {
    opts = Options();
    opts.add_argument("--headless=new");
    opts.add_argument("--disable-gpu");
    opts.add_argument("--no-sandbox");
    return webdriver.Chrome(options=opts);
}


"""Open a URL, return its title and visible body text."""
def scrape(url: str) -> dict[str, str] {
    driver = make_driver();
    try {
        driver.get(url);
        title = driver.title;
        body = driver.find_element(By.TAG_NAME, "body").text;
        return {"url": url, "title": title, "text": body};
    } finally {
        driver.quit();
    }
}


with entry {
    result = scrape("https://example.com");
    print(f"Title: {result['title']}");
    print(f"Text:\n{result['text']}");
}
