"""Shared data types, sem annotations, and deterministic dispatch for scrape-byLLM.

Houses everything that is pure data or deterministic logic:
  - Table / Article / Target type definitions
  - sem annotations (steering byLLM output in main.jac)
  - dispatch(): maps a Target to the correct selenium_abs call
  - format_tables(): renders list[Table] as pipe-delimited text

byLLM functions that *return* these types (choose_target, extract_tables,
extract_body) must remain in main.jac due to the entry-module schema constraint.
"""

import from lib.selenium_abs {
    get_links, get_link_texts, get_paragraphs, get_headings,
    get_list_items, get_table_rows, get_images, get_buttons,
    get_title, get_body_text, get_by_css, get_by_xpath
}
import from ml.selectors { css_for, xpath_for }


obj Table {
    has headers: list[str];
    has rows: list[list[str]];
    has caption: str = "";
}

sem Table = "A single data table extracted from a web page.";
sem Table.headers = "Column header cells, left to right.";
sem Table.rows = "Data rows; each row is a list of cell strings aligned to headers.";
sem Table.caption = "The table's title or caption; empty string if none.";

obj Article {
    has text: str;
    has title: str = "";
}

sem Article = "The main readable article extracted from a web page.";
sem Article.text = "The main body text, stripped of nav, ads, and boilerplate.";
sem Article.title = "The article or page title.";


enum Target {
    LINKS,
    LINK_TEXTS,
    PARAGRAPHS,
    HEADINGS,
    LIST_ITEMS,
    TABLE_ROWS,
    IMAGES,
    BUTTONS,
    TITLE,
    BODY_TEXT,
    BY_CSS,
    BY_XPATH,
    CODE_SNIPPETS
}

sem Target.LINKS = "All hyperlink URLs (href) on the page. Use when the user wants links or URLs.";
sem Target.LINK_TEXTS = "Visible text of every anchor tag. Use when the user wants what links say, not where they go.";
sem Target.PARAGRAPHS = "Text of every paragraph element. Use for article or prose body content.";
sem Target.HEADINGS = "Text of every heading element h1-h6 in document order. Use for page outline, section titles, or structure.";
sem Target.LIST_ITEMS = "Text of every list item (li). Use for bulleted or numbered list content.";
sem Target.TABLE_ROWS = "Every table row as a list of cell strings. Use for tabular or grid data.";
sem Target.IMAGES = "src URL (or alt text) of every image. Use when the user wants images or media.";
sem Target.BUTTONS = "Visible text or value of every button and submit input. Use for interactive controls or calls-to-action.";
sem Target.TITLE = "The single page title string. Use when the user wants the page title or name.";
sem Target.BODY_TEXT = "The entire visible page text as one string. Use as a broad fallback for open-ended content questions.";
sem Target.BY_CSS = "Generic CSS-selector fetch. Use when the user names a specific element, class, or selector not covered by other options.";
sem Target.BY_XPATH = "Generic XPath fetch. Use when the query requires structural or positional element selection.";
sem Target.CODE_SNIPPETS = "Code examples, code blocks, or programming snippets on the page. Use when the user wants code, samples, or technical demos.";


# Maps each Target variant to the correct selenium_abs call.
# TABLE_ROWS are flattened to list[str] (cells joined with " | ") so all
# downstream processing sees one uniform shape.
def dispatch(target: Target, url: str, query: str) -> list[str] {
    if target == Target.LINKS {
        return get_links(url);
    } elif target == Target.LINK_TEXTS {
        return get_link_texts(url);
    } elif target == Target.PARAGRAPHS {
        return get_paragraphs(url);
    } elif target == Target.HEADINGS {
        return get_headings(url);
    } elif target == Target.LIST_ITEMS {
        return get_list_items(url);
    } elif target == Target.TABLE_ROWS {
        rows: list[list[str]] = get_table_rows(url);
        flat: list[str] = [];
        for row in rows {
            flat.append(" | ".join(row));
        }
        return flat;
    } elif target == Target.IMAGES {
        return get_images(url);
    } elif target == Target.BUTTONS {
        return get_buttons(url);
    } elif target == Target.TITLE {
        return [get_title(url)];
    } elif target == Target.BODY_TEXT {
        return [get_body_text(url)];
    } elif target == Target.BY_CSS {
        sel: str = css_for(query);
        return get_by_css(url, sel);
    } elif target == Target.BY_XPATH {
        xp: str = xpath_for(query);
        return get_by_xpath(url, xp);
    }
    return [];
}


def format_tables(tables: list[Table]) -> str {
    lines: list[str] = [];
    for t in tables {
        if t.caption {
            lines.append(t.caption);
        }
        lines.append(" | ".join(t.headers));
        for row in t.rows {
            lines.append(" | ".join(row));
        }
        lines.append("");
    }
    return "\n".join(lines);
}
