"""Run/test entrypoint. The library does the work; this just makes the call.

    jac run main.jac

Swap the source/query below, or set opts={"output": "data/out.json"} to also
persist the result, and opts={"synthesize": True} for an extra LLM pass.
"""

import from dotenv { load_dotenv }
import from scrape_byLLM.scraper { get_all_prices, quit_driver }


with entry {
    load_dotenv();

    out = get_all_prices(
        source="https://docs.oracle.com/javase/8/docs/api/javax/crypto/package-summary.html",
        query="get all crypto modules exposed by this library",
        opts={"output": "data/out.json", "synthesize": True}
    );
    print(out);

    quit_driver();
}
