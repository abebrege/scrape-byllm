import json
import anthropic
from dotenv import load_dotenv
from scrape_byLLM import ScrapeByLLM

load_dotenv()

URL = "https://en.wikipedia.org/wiki/Population_density"
QUERY = "return the population of each country from the tables on this page"
MODEL = "claude-sonnet-4-6"
OUTPUT_FILE = "data/comparison_out.json"


def via_anthropic_direct() -> str:
    client = anthropic.Anthropic()
    response = client.messages.create(
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


if __name__ == "__main__":
    print("Running direct Anthropic API call...")
    direct_result = via_anthropic_direct()

    print("Running byLLM call...")
    byllm_result = via_byllm()

    output = {
        "url": URL,
        "query": QUERY,
        "model": MODEL,
        "direct_anthropic": direct_result,
        "byllm": byllm_result,
    }

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\n--- Direct Anthropic output ---\n{direct_result}\n")
    print(f"--- byLLM output ---\n{json.dumps(byllm_result, indent=2)}\n")
    print(f"Results written to {OUTPUT_FILE}")
