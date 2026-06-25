"""Selenium abstraction library for scrape-byllm.

Every public function is deterministic — no LLM. Each reuses the shared
singleton driver from scraper.jac (via get_driver()), navigates to a URL,
locates elements, and returns plain strings or lists of strings.

One-browser rule: never instantiates its own webdriver.Chrome. Driver
lifecycle is owned exclusively by scraper.quit_driver() so the same live
handle remains available for future write/click/inject operations.

The # comment directly above each public function is load-bearing: the
byLLM router in main.jac reads function names, signatures, and those
comments to decide which abstraction to call for a given query. Write them
as crisp descriptions of *what data the function yields*, not how it works.
"""

import from selenium.webdriver.common.by { By }
import from lib.scraper { get_driver }


# ── private helpers ────────────────────────────────────────────────────────────

# Skip driver.get() when the browser is already showing the target URL.
def _ensure_on(driver: any, url: str) {
    if driver.current_url != url {
        driver.get(url);
    }
}

# Return stripped, non-empty .text strings for every element matched by (by, value).
def _texts_for(driver: any, locator: any, value: str, max_items: int) -> list[str] {
    # opt out of static type checking until jac supports selenium types
    els: any = driver.find_elements(locator, value);
    result: list[str] = [];
    for el in els[:max_items] {
        t: str = str(el.text).strip();
        if t {
            result.append(t);
        }
    }
    return result;
}

# Return a specific attribute value for every element matched by (by, value).
def _attrs_for(driver: any, locator: any, value: str, attr: str, max_items: int) -> list[str] {
    # opt out of static type checking until jac supports selenium types
    els: any = driver.find_elements(locator, value);
    result: list[str] = [];
    for el in els[:max_items] {
        v: any = el.get_attribute(attr);
        if v and str(v).strip() {
            result.append(str(v).strip());
        }
    }
    return result;
}


# ── strategy-based getters ─────────────────────────────────────────────────────

# Text of the single element whose id attribute equals id_val; empty string if not found.
def get_by_id(url: str, id_val: str) -> str {
    driver: any = get_driver();
    _ensure_on(driver, url);
    # opt out of static type checking until jac supports selenium types
    els: any = driver.find_elements(By.ID, id_val);
    if els {
        return str(els[0].text).strip();
    }
    return "";
}

# Text of every element whose name attribute matches name_val (By.NAME).
def get_by_name(url: str, name_val: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.NAME, name_val, 200);
}

# Text of every element matching the XPath expression (By.XPATH).
def get_by_xpath(url: str, xpath: str, max_items: int = 200) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.XPATH, xpath, max_items);
}

# href values of anchor elements whose full visible text exactly matches text_val (By.LINK_TEXT).
def get_by_link_text(url: str, text_val: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _attrs_for(driver, By.LINK_TEXT, text_val, "href", 200);
}

# href values of anchor elements whose visible text contains text_val as a substring (By.PARTIAL_LINK_TEXT).
def get_by_partial_link_text(url: str, text_val: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _attrs_for(driver, By.PARTIAL_LINK_TEXT, text_val, "href", 200);
}

# Text of every element with the given HTML tag name (By.TAG_NAME).
def get_by_tag(url: str, tag: str, max_items: int = 200) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.TAG_NAME, tag, max_items);
}

# Text of every element that carries the given CSS class name (By.CLASS_NAME).
def get_by_class(url: str, class_val: str, max_items: int = 200) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.CLASS_NAME, class_val, max_items);
}

# Text of every element matching the CSS selector (By.CSS_SELECTOR).
def get_by_css(url: str, selector: str, max_items: int = 200) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.CSS_SELECTOR, selector, max_items);
}


# ── tag-convenience getters ────────────────────────────────────────────────────

# Every hyperlink href on the page; use when the user wants URLs or links.
def get_links(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _attrs_for(driver, By.CSS_SELECTOR, "a[href]", "href", 200);
}

# Visible text of every anchor tag; use when the user wants what links say, not where they go.
def get_link_texts(url: str) -> list[str] {
    return get_by_tag(url, "a");
}

# Text of every paragraph element; use for main prose or article body content.
def get_paragraphs(url: str) -> list[str] {
    return get_by_tag(url, "p");
}

# Text of every heading element h1-h6 in document order; use for page outline, section titles, or structure.
def get_headings(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.CSS_SELECTOR, "h1, h2, h3, h4, h5, h6", 200);
}

# Text of every list item (li) regardless of list type; use for any bulleted or numbered list content.
def get_list_items(url: str) -> list[str] {
    return get_by_tag(url, "li");
}

# Text of every unordered list item (ul > li); use specifically for bulleted lists.
def get_unordered_items(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.CSS_SELECTOR, "ul > li", 200);
}

# Text of every ordered list item (ol > li); use specifically for numbered or ranked lists.
def get_ordered_items(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    return _texts_for(driver, By.CSS_SELECTOR, "ol > li", 200);
}

# Every table row as a list of its cell strings (th and td); use for tabular or grid data.
def get_table_rows(url: str) -> list[list[str]] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    rows: list[list[str]] = [];
    # opt out of static type checking until jac supports selenium types
    row_els: any = driver.find_elements(By.TAG_NAME, "tr");
    for row in row_els {
        cell_els: any = row.find_elements(By.XPATH, ".//th | .//td");
        cell_texts: list[str] = [];
        for cell in cell_els {
            cell_texts.append(str(cell.text).strip());
        }
        if cell_texts {
            rows.append(cell_texts);
        }
    }
    return rows;
}

# src URL (or alt text when src absent) of every image; use when the user wants images or media URLs.
def get_images(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    # opt out of static type checking until jac supports selenium types
    els: any = driver.find_elements(By.TAG_NAME, "img");
    result: list[str] = [];
    for el in els[:200] {
        src: any = el.get_attribute("src");
        if src and str(src).strip() {
            result.append(str(src).strip());
        } else {
            alt: any = el.get_attribute("alt");
            if alt and str(alt).strip() {
                result.append(str(alt).strip());
            }
        }
    }
    return result;
}

# Visible text or value of every button and submit input; use for interactive controls or calls-to-action.
def get_buttons(url: str) -> list[str] {
    driver: any = get_driver();
    _ensure_on(driver, url);
    result: list[str] = [];
    # opt out of static type checking until jac supports selenium types
    btn_els: any = driver.find_elements(By.TAG_NAME, "button");
    for el in btn_els[:100] {
        t: str = str(el.text).strip();
        if t {
            result.append(t);
        }
    }
    input_els: any = driver.find_elements(By.CSS_SELECTOR, "input[type=submit], input[type=button]");
    for el in input_els[:100] {
        v: any = el.get_attribute("value");
        if v and str(v).strip() {
            result.append(str(v).strip());
        }
    }
    return result;
}

# Text of every span element; use when the user wants inline-level text chunks or labeled values.
def get_spans(url: str) -> list[str] {
    return get_by_tag(url, "span");
}

# Text of every div element; coarse and noisy — prefer a more specific getter when possible.
def get_divs(url: str) -> list[str] {
    return get_by_tag(url, "div");
}

# Full visible body text as one string; use as a broad fallback for open-ended content questions.
def get_body_text(url: str) -> str {
    driver: any = get_driver();
    _ensure_on(driver, url);
    # opt out of static type checking until jac supports selenium types
    els: any = driver.find_elements(By.TAG_NAME, "body");
    if els {
        return str(els[0].text).strip();
    }
    return "";
}

# The page title text; use when the user asks for the page's title or name.
def get_title(url: str) -> str {
    driver: any = get_driver();
    _ensure_on(driver, url);
    t: any = driver.title;
    return str(t).strip();
}
