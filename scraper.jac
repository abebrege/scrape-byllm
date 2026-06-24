"""scrape-byllm fetch layer (deterministic, no LLM).

This module is the half of the library that should never burn tokens or
hallucinate: it just downloads a page and strips noise. It is safely importable
and testable without any model or API key.

The `by llm()` extraction layer lives in main.jac instead of here. byLLM 0.6.17
only builds the output schema for a custom-obj return type when the `by llm()`
function is compiled in the *entry* module; defined in an imported module the
return-type field info degrades to a bare string and the schema builder raises
"'str' object has no attribute 'fields'". So the typed extractors stay in the
entry module and import this deterministic helper.
"""

import requests;
import from bs4 { BeautifulSoup }

# Cap HTML handed to the model so a huge page can't blow up token usage.
glob MAX_CHARS: int = 40000;


"""Download a URL and return cleaned HTML with scripts/styles stripped."""
def fetch_page(url: str) -> str {
    resp = requests.get(url, headers={"User-Agent": "scrape-byllm/0.1"}, timeout=30);
    resp.raise_for_status();
    soup = BeautifulSoup(resp.text, "html.parser");
    # opt out of static type checking until jac supports bs4 types
    noise: any = soup(["script", "style", "noscript"]);
    for tag in noise {
        tag.decompose();
    }
    html = str(soup);
    if len(html) > MAX_CHARS {
        return html[:MAX_CHARS];
    }
    return html;
}
