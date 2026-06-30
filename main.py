import re
import json
import requests
import anthropic
from types import SimpleNamespace
from dotenv import load_dotenv
from scrape_byLLM import ScrapeByLLM

load_dotenv()

URL = "https://en.wikipedia.org/wiki/Population_density"
QUERY = "return the population of each country from the tables on this page"
MODEL = "claude-sonnet-4-6"
OUTPUT_FILE = "data/comparison_out.json"

_client = anthropic.Anthropic()


def _llm_json(prompt: str, max_tokens: int = 1024) -> dict:
    response = _client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
    )
    text = response.content[0].text.strip()
    m = re.search(r"\{[\s\S]*\}", text)
    return json.loads(m.group()) if m else {}


def via_anthropic_direct() -> str:
    response = _client.messages.create(
        model=MODEL,
        max_tokens=4096,
        thinking={"type": "adaptive"},
        messages=[
            {
                "role": "user",
                "content": (
                    f"Please fetch and analyse this webpage: {URL}\n\n"
                    f"Task: {QUERY}"
                ),
            }
        ],
        tools=[{"type": "web_fetch_20260209", "name": "web_fetch"}],
    )
    parts = []
    for block in response.content:
        if block.type == "text":
            parts.append(block.text)
    return "\n".join(parts)


def via_byllm() -> dict:
    with ScrapeByLLM(synthesize=True) as scraper:
        return scraper.get_all(source=URL, query=QUERY)


def via_direct_pipeline() -> dict:
    from scrape_byLLM.executor import extract, dedup  # type: ignore[import]
    from scrape_byLLM.presets import preset_table  # type: ignore[import]

    presets = preset_table()
    pattern_names = list(presets.keys())

    pattern = _client.messages.create(
        model=MODEL,
        max_tokens=20,
        messages=[{
            "role": "user",
            "content": (
                "Return the single pattern name from this list that best matches "
                "what the user wants to extract. Return exactly one name — "
                "no explanation, no punctuation.\n\n"
                f"Available patterns: {pattern_names}\n\nQuery: {QUERY}"
            ),
        }],
    ).content[0].text.strip()
    if pattern not in presets:
        pattern = "text"

    html = requests.get(URL, headers={"User-Agent": "scrape-byLLM"}, timeout=20).text
    plan_data = _llm_json(
        f"Decide how to extract the requested query from HTML.\n"
        f"Prefer selecting and lightly parameterising a pattern from available_regexes.\n"
        f"Return ONLY a JSON object with these fields:\n"
        f"  strategy: 'preset' or 'custom'\n"
        f"  patterns: list of Python re-compatible regex strings\n"
        f"  on: 'html' or 'text'\n"
        f"  window: int (characters of context each side of a match)\n"
        f"  notes: string (brief rationale, empty if none)\n\n"
        f"pattern: {pattern}\n"
        f"query: {QUERY}\n"
        f"available_regexes: {json.dumps(presets)}\n"
        f"sample_html:\n{html[:6000]}",
        max_tokens=1024,
    )
    plan = SimpleNamespace(
        strategy=plan_data.get("strategy", "custom"),
        patterns=plan_data.get("patterns", [presets.get(pattern, "")]),
        on=plan_data.get("on", "html"),
        window=int(plan_data.get("window", 200)),
        notes=plan_data.get("notes", ""),
    )

    snippets = dedup(extract(plan, html, plan.window))

    flat = "\n".join(f"[{URL}] {s}" for s in snippets)
    synthesis_data = _llm_json(
        f"Read the flat snippet text from every scraped page and extract the information "
        f"the user is after. Infer intent from the original query. Return a clean, structured "
        f"synthesis without fabricating facts not present in the snippets.\n"
        f"Return ONLY a JSON object with: summary (string), items (list of strings), notes (string).\n\n"
        f"query: {QUERY}\npattern: {pattern}\nsnippets:\n{flat[:20000]}",
        max_tokens=2048,
    )

    return {
        "pattern": pattern,
        "query": QUERY,
        "strategy": plan.strategy,
        "on": plan.on,
        "patterns": plan.patterns,
        "page_count": 1,
        "llm_calls": 3,
        "results": [{"source": URL, "snippets": snippets}],
        "synthesis": {
            "summary": synthesis_data.get("summary", ""),
            "items": synthesis_data.get("items", []),
            "notes": synthesis_data.get("notes", ""),
        },
    }


if __name__ == "__main__":
    print("Running direct Anthropic API call...")
    direct_result = via_anthropic_direct()

    print("Running byLLM call...")
    byllm_result = via_byllm()

    print("Running direct pipeline call...")
    pipeline_result = via_direct_pipeline()

    output = {
        "url": URL,
        "query": QUERY,
        "model": MODEL,
        "direct_anthropic": direct_result,
        "byllm": byllm_result,
        "direct_pipeline": pipeline_result,
    }

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\n--- Direct Anthropic output ---\n{direct_result}\n")
    print(f"--- byLLM output ---\n{json.dumps(byllm_result, indent=2)}\n")
    print(f"--- Direct pipeline output ---\n{json.dumps(pipeline_result, indent=2)}\n")
    print(f"Results written to {OUTPUT_FILE}")
