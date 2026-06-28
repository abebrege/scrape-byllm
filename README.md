# scrape-byLLM

A library for web scraping, written in [Jac](https://jaseci.org)
with [byLLM](https://pypi.org/project/byllm/).

```
fetch -> planner -> executor (determine regex byLLM) -> [synthesize byLLM] -> [write]
```

## Install

Requires Python ≥ 3.11 and Google Chrome (only for `render=True` pages).
```bash

uv pip install -e .
```
or
```bash
pip install -e .
```

This installs the `scrape_byLLM` package and its dependencies (jaclang, byllm,
selenium, requests, beautifulsoup4, lxml, python-dotenv).

## Setup

byLLM needs an API key for the configured model (`anthropic/claude-sonnet-4-6`,
set in `jac.toml`). Put it in a `.env` file at the project root:

```
ANTHROPIC_API_KEY=sk-ant-...
```

`main.jac` calls `load_dotenv()`, so the key is picked up automatically.

## Basic use

Run the example entrypoint:

```bash
jac run main.jac
```

`main.jac` is intentionally tiny — it just calls the library:

```jac
import from dotenv { load_dotenv }
import from scrape_byLLM.scraper { ScrapeByLLM }

with entry {
    load_dotenv();

    scraper: ScrapeByLLM = ScrapeByLLM();
    scraper.set("synthesize", True);
    scraper.set("output", "data/out.json");

    out: dict = scraper.get_all_prices(
        source="https://en.wikipedia.org/wiki/Population_density",
        query="return the population of each country from the tables on this page"
    );
    print(out);

    scraper.quit();
}
```

### The API

Import `ScrapeByLLM` from `scrape_byLLM.scraper`, create an instance, configure
it once with `.set()`, then call `.get_all_*()` for each target. The compiled
plan is reused across pages without further LLM calls.

```
scraper.get_all(pattern, source, query="")   # generic
scraper.get_all_links / get_all_images / get_all_prices / get_all_emails /
scraper.get_all_phones / get_all_tables / get_all_headings / get_all_text /
scraper.get_all_charts / get_all_code        # one preset per "pattern"
```

- **source** — a URL, a list of URLs, raw HTML, or plain text (mixed lists are fine).
- **query** — optional natural-language description. When given, the LLM compiles
  a custom plan. When omitted, the built-in preset regex for that `pattern` is used
  (no LLM call).

Call `scraper.quit()` when done to release the browser driver (only matters when
`render=True`).

### Configuration (`.set()` / `.get()`)

| key              | type        | default | effect                                                      |
|------------------|-------------|---------|-------------------------------------------------------------|
| `window`         | int         | `200`   | Character window around each regex match.                   |
| `max_chars`      | int         | `40000` | Max characters of page text passed to the LLM.             |
| `render`         | bool        | `False` | Fetch via headless Chrome instead of `requests` (JS pages). |
| `timeout`        | int         | `20`    | Per-request timeout in seconds (static fetch).              |
| `dedup`          | bool        | `True`  | Drop duplicate snippets per page.                           |
| `synthesize`     | bool        | `False` | Run one extra LLM pass; adds a structured `synthesis` block.|
| `output`         | str \| None | `None`  | Also write the result as JSON to this path.                 |
| `html_sample_size` | int       | `6000`  | Characters of raw HTML sampled for plan compilation.        |

```jac
scraper.set("render", True);
scraper.set("output", "data/out.json");
val = scraper.get("window");  # read a value back
```

### Output

Every call **returns a dict**. Writing to disk is an opt-in side effect via
`scraper.set("output", path)` — the returned value is identical either way:

```jac
out = scraper.get_all_links(source="https://example.com");           # returns only
scraper.set("output", "out/links.json");
out = scraper.get_all_links(source="https://example.com");           # + custom path
```

Result shape:

```json
{
  "pattern": "prices",
  "query": "...",
  "strategy": "preset | custom",
  "on": "html | text",
  "patterns": ["..."],
  "page_count": 1,
  "llm_calls": 2,
  "results": [{ "source": "...", "snippets": ["..."] }],
  "synthesis": { "summary": "...", "items": ["..."], "notes": "..." }
}
```
