# scrape-byllm

An LLM-planned, regex-executed web scraper, written in [Jac](https://jaseci.org)
with [byLLM](https://pypi.org/project/byllm/).

The model is called **once** per `(thing, query)` pair to compile a reusable
extraction plan. That plan is then applied deterministically to every page with
plain regex. Scraping N pages costs **1 LLM call + (N-1) pure-regex passes** —
the cost does not grow with the number of pages.

```
fetch ──▶ planner (1 LLM call) ──▶ executor (regex × N) ──▶ [synthesize] ──▶ [write]
```

## Install

Requires Python ≥ 3.11 and Google Chrome (only for `render=True` pages).

```bash
# with uv
uv pip install -e .

# or with pip
pip install -e .
```

This installs the `scrape_byllm` package and its dependencies (jaclang, byllm,
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
import from scrape_byllm.scraper { get_all_prices, quit_driver }

with entry {
    load_dotenv();
    out = get_all_prices(
        source="https://example.com",
        query="get all crypto modules exposed by this library",
        opts={"output": "data/out.json", "synthesize": True}
    );
    print(out);
    quit_driver();
}
```

### The API

Import any `get_all_*` helper from `scrape_byllm.scraper` (or directly from
`scrape_byllm`):

```
get_all(thing, source, query="", opts={})   # generic
get_all_links / get_all_images / get_all_prices / get_all_emails /
get_all_phones / get_all_tables / get_all_headings / get_all_text /
get_all_charts / get_all_code                # one preset per "thing"
```

- **source** — a URL, a list of URLs, raw HTML, or plain text (mixed lists are fine).
- **query** — optional natural-language description. When given, the LLM compiles
  a custom plan; when omitted, the built-in preset regex for that `thing` is used
  (no LLM call).

### Options (`opts`)

| key          | type        | default | effect                                                     |
|--------------|-------------|---------|------------------------------------------------------------|
| `render`     | bool        | `False` | Fetch via headless Chrome instead of `requests` (JS pages).|
| `timeout`    | int         | `20`    | Per-request timeout in seconds (static fetch).             |
| `dedup`      | bool        | `True`  | Drop duplicate snippets per page.                          |
| `synthesize` | bool        | `False` | Run one extra LLM pass; adds a structured `synthesis` block.|
| `output`     | str \| bool | —       | Also write the result as JSON. `True` → `data/out.json`; a string → that path. |

### Output

Every call **returns a dict** and writes nothing by default. Writing is an opt-in
side effect via `opts["output"]` — the returned value is identical either way:

```jac
out = get_all_links(source="https://example.com");                    # returns only
out = get_all_links(source="...", opts={"output": True});             # + data/out.json
out = get_all_links(source="...", opts={"output": "out/links.json"}); # + custom path
```

Result shape:

```json
{
  "thing": "prices",
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

## Package layout

| module                    | responsibility                                          |
|---------------------------|---------------------------------------------------------|
| `scrape_byllm/presets`    | Built-in regex table, keyed by `thing` (pure data).     |
| `scrape_byllm/fetch`      | Page acquisition: HTTP + headless browser + normalize.  |
| `scrape_byllm/executor`   | Deterministic regex execution (the per-page work).      |
| `scrape_byllm/planner`    | The LLM brain: plan compilation + optional synthesis.   |
| `scrape_byllm/output`     | The write-to-disk hook.                                 |
| `scrape_byllm/scraper`    | Orchestration + the public `get_all_*` API.             |
