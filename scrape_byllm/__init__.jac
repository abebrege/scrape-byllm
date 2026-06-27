"""scrape-byLLM: LLM-planned, regex-executed web scraper.

The LLM is called once per (thing, query) pair to compile a reusable RegexPlan;
that plan is then applied deterministically to every page. Scraping N pages =
1 LLM call + (N-1) pure-regex executions.

Public API (import straight from `scrape_byLLM`):
    get_all, get_all_links, get_all_images, get_all_prices, get_all_emails,
    get_all_phones, get_all_tables, get_all_headings, get_all_text,
    get_all_charts, get_all_code   — scrape one `thing` from a source
    quit_driver                    — shut down the headless browser (if used)

Every get_all_* accepts opts={"render", "timeout", "dedup", "synthesize",
"output"}; by default it returns a result dict and writes nothing.
"""

import from scrape_byLLM.scraper {
    get_all, get_all_links, get_all_images, get_all_prices, get_all_emails,
    get_all_phones, get_all_tables, get_all_headings, get_all_text,
    get_all_charts, get_all_code
}
import from scrape_byLLM.fetch { quit_driver }
