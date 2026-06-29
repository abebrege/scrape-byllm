# scrape-byLLM

A Python library for LLM-assisted web scraping. One LLM call compiles a reusable extraction plan for a `(pattern, query)` pair.

```
fetch -> planner -> extract (regex) -> [synthesize by LLM] -> [write]
```

**Features:** preset patterns · custom LLM-compiled plans · BFS crawling · SSRF protection · HTTP + LLM response caching · proxy rotation · prompt-injection mitigation

## Install

Requires Python ≥ 3.11. Google Chrome is only needed for `render=True` pages.

```bash
pip install -e .
# or
uv pip install -e .
```

Dependencies: jaclang, byllm, selenium, requests, beautifulsoup4, lxml, python-dotenv.

## Setup

The planner calls Claude via [byLLM](https://pypi.org/project/byllm/). The model is configured in `jac.toml` (`anthropic/claude-sonnet-4-6`). Put an Anthropic API key in a `.env` file at the project root:

```
ANTHROPIC_API_KEY=
```

`main.jac` calls `load_dotenv()`, so the key is picked up automatically.

## Quick start

```python
from scrape_byLLM import ScrapeByLLM

# Preset pattern — no LLM call, instant
scraper = ScrapeByLLM()
result = scraper.get_all_emails(source="https://example.com/contact")
print(result["results"][0]["snippets"])

# Custom query — one LLM call to compile the plan, reused across pages
scraper = ScrapeByLLM(synthesize=True, output="out.json")
result = scraper.get_all(
    source="https://en.wikipedia.org/wiki/Population_density",
    query="return the population of each country from the tables on this page",
)
print(result["synthesis"])
scraper.quit()
```

**Source** can be a URL, a list of URLs, raw HTML, plain text, or a mixed list.

## Preset patterns

| method | pattern |
|---|---|
| `get_all_links` | `<a href>` URLs |
| `get_all_images` | `<img src>` URLs |
| `get_all_emails` | e-mail addresses |
| `get_all_phones` | phone numbers |
| `get_all_prices` | price strings ($, €, £, ¥) |
| `get_all_tables` | `<table>` blocks |
| `get_all_headings` | `<h1>`–`<h6>` text |
| `get_all_text` | full visible text |
| `get_all_charts` | `<canvas>` / `<svg>` blocks |
| `get_all_code` | `<code>` / `<pre>` blocks |

Pass `query=` to any method to override with a custom LLM-compiled plan.

## BFS crawl

```python
result = scraper.crawl(
    seed="https://example.com/blog",
    query="product announcements",
    pattern="text",
    max_depth=2,
    max_pages=40,
    same_domain=True,
    follow_pattern=r"/blog/",
    exclude_pattern=r"/tag/",
    paginate=True,           # follow rel="next" pagination links
)
print(result["pages_crawled"])
```

Every URL is SSRF-validated before it is fetched or enqueued.

## Result shape

```json
{
  "pattern":       "emails",
  "query":         "",
  "strategy":      "preset",
  "on":            "text",
  "patterns":      ["[\\w.+-]+@[\\w-]+\\.[\\w.]+"],
  "page_count":    1,
  "llm_calls":     0,
  "fetch_hits":    0,
  "fetch_misses":  1,
  "blocked_urls":  0,
  "pages_crawled": 0,
  "results": [
    { "source": "https://…", "snippets": ["user@example.com"] }
  ]
}
```

`synthesis` (`{ summary, items, notes }`) is added when `synthesize=True`.

## Key options

```python
ScrapeByLLM(
    # fetching
    render=False,           # headless Chrome for JS pages
    timeout=20,             # per-request timeout (seconds)
    respect_robots=True,    # honour robots.txt
    rate_limit=1.0,         # min seconds between requests
    # security
    ssrf_protection=True,   # block private/loopback IPs
    injection_guard=True,   # detect prompt-injection in scraped HTML
    # caching
    cache="readwrite",      # off | readwrite | readonly | refresh
    cache_dir=".scrape_cache",
    cache_ttl=3600,
    cache_llm=True,         # also cache LLM plan + synthesis responses
    # proxies
    proxies=["http://p1:8080", "http://p2:8080"],
    proxy_rotation="round_robin",  # round_robin | random | sticky
)
```

See [DOCS.md](DOCS.md) for the full reference.

## Context manager

```python
with ScrapeByLLM(render=True) as scraper:
    result = scraper.get_all_links("https://example.com")
# browser driver released automatically
```

## Jac entrypoint

The repo ships a minimal `main.jac` for running the library directly:

```bash
jac run main.jac
```
