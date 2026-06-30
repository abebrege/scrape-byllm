# Goal
This repository tests the accuracy, cost efficiency, and usability of Meaning-Typed Programming (byLLM) vs manual LLM querying in web scraping. 

Output is analyzed from each of the following methods:
- Direct LLM query
- Direct byLLM query
- Scraper abstractions (regex filtering, pagination handling, crawling, backoffs, injection attacks, etc.) for:
  - LLM query
  - byLLM query

The scraper abstractions build a pipeline for the LLMs to leverage potentially yielding better results. The assistance this pipeline gives, if any, is another question this project will answer.

# Library

## scrape-byLLM

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

The repo ships a minimal `example.jac` for running the library directly:

```bash
jac run example.jac
```
