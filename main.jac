"""scrape-byllm: webscraping + data-processing built on byLLM.

Entry point AND the LLM "process layer". Each public function fetches a page
deterministically (via scraper.fetch_page) and then uses `by llm()` to turn the
raw HTML into clean, typed structured data. The function name + signature +
return type ARE the prompt (Meaning-Typed Programming); the typed return value
is enforced as the model's output schema.

Why the by-llm functions live here and not in scraper.jac: byLLM 0.6.17 only
builds the output schema for a custom-obj return type when the function is
compiled in the entry module. See scraper.jac for the full note.

Model is Claude Sonnet 4.6 (also set as default_model in jac.toml).
Run with:  jac run main.jac
"""

import from byllm.lib { Model }
import from scraper { fetch_page }

glob llm = Model(model_name="anthropic/claude-sonnet-4-6");


# ---------------------------------------------------------------------------
# Return types -- double as enforced output schemas. The `sem` annotations are
# the main quality lever for steering extraction.
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Process layer (byLLM). No bodies -- name + types + sem are the spec.
# temperature=0.0 keeps extraction deterministic.
# ---------------------------------------------------------------------------

"""Given raw HTML and an instruction, return only the requested information as clean text."""
def extract(html: str, instruction: str) -> str by llm(temperature=0.0);

"""Extract every data table on the page as structured rows and headers."""
def extract_tables(html: str) -> list[Table] by llm(temperature=0.0);

"""Extract each bulleted or numbered list on the page as a list of item strings."""
def extract_lists(html: str) -> list[list[str]] by llm(temperature=0.0);

"""Return the main readable article/body content, stripped of nav, ads, and boilerplate."""
def extract_body(html: str) -> Article by llm(temperature=0.0);


# ---------------------------------------------------------------------------
# Public API: fetch (deterministic) -> process (LLM). Composed primitives.
# ---------------------------------------------------------------------------

"""Fetch a page and extract whatever the natural-language instruction asks for."""
def scrape(url: str, instruction: str) -> str {
    return extract(fetch_page(url), instruction);
}

"""Fetch a page and extract all of its data tables as structured Table objects."""
def get_tables(url: str) -> list[Table] {
    return extract_tables(fetch_page(url));
}

"""Fetch a page and extract all of its bulleted/numbered lists."""
def get_lists(url: str) -> list[list[str]] {
    return extract_lists(fetch_page(url));
}

"""Fetch a page and extract its main article body as a structured Article."""
def get_body(url: str) -> Article {
    return extract_body(fetch_page(url));
}


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------

with entry {
    wiki = "https://en.wikipedia.org/wiki/List_of_countries_and_dependencies_by_population";

    print("=== scrape (free-form instruction) ===");
    print(scrape(wiki, "the title of the page"));

    print("\n=== get_tables ===");
    tables = get_tables(wiki);
    print(f"found {len(tables)} table(s)");
    if tables {
        print("headers:", tables[0].headers);
        print("first row:", tables[0].rows[0] if tables[0].rows else "(none)");
    }

    print("\n=== get_lists ===");
    lists = get_lists("https://en.wikipedia.org/wiki/Web_scraping");
    print(f"found {len(lists)} list(s)");
    if lists {
        print("first list (up to 5 items):", lists[0][:5]);
    }

    print("\n=== get_body ===");
    article = get_body("https://example.com");
    print("title:", article.title);
    print("text:", article.text);
}
