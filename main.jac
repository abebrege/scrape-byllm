import from dotenv { load_dotenv }
import from scrape_byLLM.scraper { ScrapeByLLM }


with entry {
    load_dotenv();

    scraper: ScrapeByLLM = ScrapeByLLM();
    scraper.set("window", 300);
    scraper.set("synthesize", True);
    scraper.set("output", "data/out.json");

    out: dict = scraper.get_all_prices(
        source="https://docs.oracle.com/javase/8/docs/api/javax/crypto/package-summary.html",
        query="get all crypto modules exposed by this library"
    );
    print(out);

    scraper.quit();
}
