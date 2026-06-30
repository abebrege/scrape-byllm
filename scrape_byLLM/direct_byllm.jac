import from requests { get }
import from byllm.lib { Model }

glob llm = Model(model_name="anthropic/claude-sonnet-4-6");


"""One page of extracted snippets, matching the shared output format."""
obj PageResult {
    has source: str;
    has snippets: list[str];
}

sem PageResult.source = "URL of the fetched page.";
sem PageResult.snippets = "Extracted text snippets, one string per row or item found.";


"""Structured synthesis of all extracted snippets."""
obj SynthesisResult {
    has summary: str;
    has items: list[str];
    has notes: str = "";
}

sem SynthesisResult.summary = "Concise paragraph summarising what was found relative to the original query.";
sem SynthesisResult.items = "Discrete extracted items inferred from the query, e.g. 'Country: population'. One string per entry.";
sem SynthesisResult.notes = "Any caveats or ambiguities. Empty string if none.";


"""Full extraction result matching the shared comparison output format."""
obj ScrapeResult {
    has pattern: str;
    has query: str;
    has strategy: str;
    has on: str;
    has patterns: list[str];
    has results: list[PageResult];
    has synthesis: SynthesisResult;
}

sem ScrapeResult.pattern = "The extraction pattern used, e.g. 'tables'.";
sem ScrapeResult.query = "The original query verbatim.";
sem ScrapeResult.strategy = "'preset' if a known HTML pattern was used, 'custom' otherwise.";
sem ScrapeResult.on = "'html' for structural extraction or 'text' for semantic extraction.";
sem ScrapeResult.patterns = "Python re-compatible regex strings applied. Empty list if none.";
sem ScrapeResult.results = "One PageResult per fetched page.";
sem ScrapeResult.synthesis = "Structured synthesis of all extracted snippets.";


"""Read the provided HTML content from the given URL and extract every item
matching the query. Populate one PageResult per page and a SynthesisResult
with a summary, a list of items in 'Country: population' format, and notes."""
def extract_from_html(url: str, html: str, query: str) -> ScrapeResult by llm(temperature=0.0);


def fetch_and_extract(url: str, query: str, max_chars: int = 200000) -> dict {
    resp: any = get(url, headers={"User-Agent": "scrape-byLLM"}, timeout=20);
    html: str = resp.text;
    if len(html) > max_chars {
        html = html[:max_chars];
    }

    result: ScrapeResult = extract_from_html(url, html, query);

    result_list: list[dict] = [];
    for r in result.results {
        result_list.append({"source": r.source, "snippets": r.snippets});
    }

    return {
        "pattern":   result.pattern,
        "query":     result.query,
        "strategy":  result.strategy,
        "on":        result.on,
        "patterns":  result.patterns,
        "results":   result_list,
        "synthesis": {
            "summary": result.synthesis.summary,
            "items":   result.synthesis.items,
            "notes":   result.synthesis.notes,
        },
    };
}
