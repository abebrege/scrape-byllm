"""scrape-byllm: webscraping + data-processing built on byLLM.

Entry point and the LLM "process layer". Each public function fetches a page
deterministically and then uses `by llm()` to turn the raw HTML or raw element
lists into clean, typed structured data. The function name + signature +
return type ARE the prompt (Meaning-Typed Programming); the typed return value
is enforced as the model's output schema.

Why by-llm functions with custom obj/enum return types live here and not in
imported modules: byLLM 0.6.17 only builds the output schema for a custom-obj
or enum return type when the function is compiled in the entry module. This
applies to: extract_tables (-> list[Table]), extract_body (-> Article),
choose_target (-> Target), and grab_by_query itself. Primitive-returning
by-llm functions (str, bool, list[str]) are safe to factor into ml/.

Model is Claude Sonnet 4.6 (also set as default_model in jac.toml).
Run with:  jac run main.jac
"""

import json;
import from byllm.lib { Model }
import from dotenv { load_dotenv }
import from lib.scraper { fetch_page, quit_driver }
import from lib.selenium_abs {
    get_links, get_link_texts, get_paragraphs, get_headings,
    get_list_items, get_table_rows, get_images, get_buttons,
    get_title, get_body_text, get_by_css, get_by_xpath
}
import from ml.selectors { css_for, xpath_for, expects_list }
import from ml.process { filter_items, pick_one }

glob llm = Model(model_name="anthropic/claude-sonnet-4-6");


# `sem` annotations steer the model's output to be accurate and consistent with the intended meaning of the type.

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


"""Given raw HTML and an instruction, return only the requested information as clean text."""
def extract(html: str, instruction: str) -> str by llm(temperature=0.0);

"""Extract every data table on the page as structured rows and headers."""
def extract_tables(html: str) -> list[Table] by llm(temperature=0.0);

"""Extract each bulleted or numbered list on the page as a list of item strings."""
def extract_lists(html: str) -> list[list[str]] by llm(temperature=0.0);

"""Return the main readable article/body content, stripped of nav, ads, and boilerplate."""
def extract_body(html: str) -> Article by llm(temperature=0.0);

# Public interface: infers the right extraction strategy from the query via
# byLLM, then delegates to the appropriate lib helper and returns clean text.
def scrape(url: str, query: str) -> str {
    target = choose_target(query);

    # Full-page HTML → LLM extraction for content best read as prose or code.
    if target == Target.CODE_SNIPPETS or target == Target.BODY_TEXT {
        return extract(fetch_page(url), query);
    }

    # Structured table extraction → formatted text.
    if target == Target.TABLE_ROWS {
        tables: list[Table] = extract_tables(fetch_page(url));
        lines: list[str] = [];
        for t in tables {
            lines.append(" | ".join(t.headers));
            for row in t.rows {
                lines.append(" | ".join(row));
            }
            lines.append("");
        }
        return "\n".join(lines);
    }

    # Selenium element extraction + LLM filtering for everything else.
    raw: list[str] = dispatch(target, url, query);
    capped: list[str] = [];
    for s in raw[:300] {
        if len(s) > 500 {
            capped.append(s[:500]);
        } else {
            capped.append(s);
        }
    }

    if target == Target.TITLE or not expects_list(query) {
        return pick_one(query, capped);
    }
    return "\n".join(filter_items(query, capped));
}

def get_tables(url: str) -> list[Table] {
    return extract_tables(fetch_page(url));
}

def get_lists(url: str) -> list[list[str]] {
    return extract_lists(fetch_page(url));
}

def get_body(url: str) -> Article {
    return extract_body(fetch_page(url));
}


# ── grab_by_query: natural-language query → JSON ──────────────────────────────
# Target enum and choose_target must live in the entry module because byLLM
# 0.6.17 only builds a correct output schema for enum return types here.

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


"""Pick the single best page-extraction target for the user's natural-language query."""
def choose_target(query: str) -> Target by llm(temperature=0.0);


# Deterministic dispatch: maps each Target variant to the correct selenium_abs call.
# TABLE_ROWS are flattened to list[str] (cells joined with " | ") so all downstream
# processing sees one uniform shape.
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


# Given a URL and a natural-language query, infer the right scraper, scrape the
# page, filter the raw results, and return a JSON-serializable list of {"result": ...}
# objects — one element for a single answer, N elements for a list answer.
def grab_by_query(url: str, query: str) -> list[any] {
    target = choose_target(query);
    raw: list[str] = dispatch(target, url, query);

    # Token safety: cap the raw list before handing to the LLM processing step
    # so large pages don't blow out the model's context window.
    capped: list[str] = [];
    for s in raw[:300] {
        if len(s) > 500 {
            capped.append(s[:500]);
        } else {
            capped.append(s);
        }
    }

    singular_targets: list[any] = [Target.TITLE, Target.BODY_TEXT];
    wants_list: bool = (target not in singular_targets) and expects_list(query);

    result: list[any] = [];
    if wants_list {
        items: list[str] = filter_items(query, capped);
        result = [{"result": it} for it in items];
    } else {
        one: str = pick_one(query, capped);
        result = [{"result": one}];
    }
    return result;
}


with entry {
    load_dotenv();

    url = "https://doc.rust-lang.org/book/ch03-01-variables-and-mutability.html";

    print(scrape(url, "the code snippets from this page, as clean text"));

    # print("\n=== get_lists ===");
    # lists = get_lists("https://en.wikipedia.org/wiki/Web_scraping");
    # print(f"found {len(lists)} list(s)");
    # if lists {
    #     print("first list (up to 5 items):", lists[0][:5]);
    # }

    # print("\n=== get_body ===");
    # article = get_body("https://example.com");
    # print("title:", article.title);
    # print("text:", article.text);

    # print("\n=== grab_by_query (single) ===");
    # print(json.dumps(grab_by_query("https://example.com", "what is the title of this page?"), indent=2));

    # print("\n=== grab_by_query (list) ===");
    # print(json.dumps(grab_by_query(wiki, "all the external links on this page"), indent=2));

    quit_driver();
}
