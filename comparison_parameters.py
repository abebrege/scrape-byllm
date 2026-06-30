from dataclasses import dataclass
from typing import Literal


@dataclass
class ComparisonParams:
    name: str
    url: str
    query: str
    items_format: str
    category: int
    failure_type: Literal["structural", "semantic", "both"]
    description: str = ""

    @property
    def output_file(self) -> str:
        return f"data/comparison_{self.name}.json"


COMPARISONS: dict[str, ComparisonParams] = {
    # --- Baseline -----------------------------------------------------------------
    "population_density": ComparisonParams(
        name="population_density",
        url="https://en.wikipedia.org/wiki/Population_density",
        query="return the population of each country from the tables on this page",
        items_format="one per country in 'Country: population' format",
        category=4,
        failure_type="both",
        description=(
            "Baseline dispersed-extraction case: multiple tables spread across a long page. "
            "Structural failure is a partial list that looks complete."
        ),
    ),
    # --- Category 1: Disambiguation among near-identical candidates ---------------
    # books.toscrape product pages carry both "Price (excl. tax)" and "Price (incl. tax)"
    # rows in the Product Information table. "What is the price?" forces a which-field choice;
    # both values are valid price strings so the schema never flags the wrong pick.
    "price_disambiguation": ComparisonParams(
        name="price_disambiguation",
        url="https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html",
        query="what is the price of this book?",
        items_format="one per price field in 'Field name: price value' format (e.g. 'Price (excl. tax): £51.77')",
        category=1,
        failure_type="semantic",
        description=(
            "Product Information table has two price rows (excl. and incl. tax). "
            "Both are valid price strings; only context determines which the user wants. "
            "Sandbox page — stable, legal, no auth required."
        ),
    ),
    # --- Category 2: Values that must be computed, not lifted ---------------------
    # Concorde's speed is given in km/h and Mach; mph requires a conversion not on the page.
    # Regex-plan can extract the raw km/h figure but cannot derive the mph answer.
    "computed_value": ComparisonParams(
        name="computed_value",
        url="https://en.wikipedia.org/wiki/Concorde",
        query="what was Concorde's maximum speed in miles per hour?",
        items_format="one entry: 'Maximum speed: <value> mph (converted from <original value and unit>)'",
        category=2,
        failure_type="semantic",
        description=(
            "Speed is given in km/h and Mach; the answer in mph requires a unit conversion "
            "not present on the page. Regex-plan can extract the raw number but cannot derive mph."
        ),
    ),
    # --- Category 3: Tables with merged cells / multi-level headers ---------------
    # Wikipedia GDP table uses multi-level column headers (source organisation × projection year)
    # with colspan. Markdown flattening destroys the cell-to-header mapping.
    "merged_table_headers": ComparisonParams(
        name="merged_table_headers",
        url="https://en.wikipedia.org/wiki/List_of_countries_by_GDP_(nominal)",
        query="what is the GDP of Germany, France, and Japan according to the IMF?",
        items_format="one per country in 'Country: GDP in USD millions (IMF, year)' format",
        category=3,
        failure_type="semantic",
        description=(
            "GDP table uses multi-level column headers (source × year) with colspan. "
            "Markdown flattening destroys cell-to-header mapping; model returns a value "
            "from roughly the right region of the table."
        ),
    ),
    # --- Category 4: Dispersed / extract-all on long pages ------------------------
    # books.toscrape has 1,000 books across 50 pages of 20. Asking for all titles+prices
    # on the root page tests whether the model truncates and returns a plausible partial list.
    "dispersed_extract_all": ComparisonParams(
        name="dispersed_extract_all",
        url="https://books.toscrape.com/",
        query="return all book titles and their prices from this catalogue page",
        items_format="one per book in 'Title: price' format",
        category=4,
        failure_type="both",
        description=(
            "1,000 books across 50 paginated pages. Single-page fetch returns 20 items; "
            "correct answer acknowledges pagination. Classic truncation failure: model returns "
            "the first ~20 as if the list were complete."
        ),
    ),
    # --- Category 5: Absent data the page doesn't contain ------------------------
    # books.toscrape Product Information table has UPC, Product Type, two prices, Tax,
    # Availability, and Number of reviews — but no ISBN field (verified). Correct answer is
    # NOT FOUND. Failure mode is fabricating a plausible-looking number string.
    "absent_data": ComparisonParams(
        name="absent_data",
        url="https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html",
        query="what is the ISBN of this book?",
        items_format="one per requested field in 'Field: value' format, or 'Field: NOT FOUND' if absent",
        category=5,
        failure_type="semantic",
        description=(
            "Product Information table has UPC but no ISBN field. Correct answer is NOT FOUND. "
            "Failure is fabricating a plausible numeric string — structurally valid, semantically catastrophic. "
            "Cleanest demonstration of the structural/semantic gap."
        ),
    ),
    # --- Category 6: Implicit / relational data -----------------------------------
    # Same books.toscrape product page: "author" is not a labeled field in the table but
    # appears in the prose description ('...from Shel Silverstein...'). Tests inference
    # from running text rather than field lookup.
    "implicit_relational": ComparisonParams(
        name="implicit_relational",
        url="https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html",
        query="who is the author of this book?",
        items_format="one entry: 'Author: <full name>'",
        category=6,
        failure_type="semantic",
        description=(
            "Author is not a labeled field in the Product Information table but is named in "
            "the prose description. Tests inference from running text; regex-plan cannot resolve this."
        ),
    ),
    # --- Category 7: Visually / positionally encoded data -------------------------
    # books.toscrape renders star ratings as a CSS class (e.g. 'star-rating Three') with no
    # numeric text in the DOM at all. Text/markdown extraction has nothing to grab; the raw
    # HTML requires knowing that 'Three' → 3.
    "visual_encoding": ComparisonParams(
        name="visual_encoding",
        url="https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html",
        query="what is the star rating of this book?",
        items_format="one entry: 'Star rating: <numeric value> out of 5'",
        category=7,
        failure_type="semantic",
        description=(
            "Star rating is encoded as a CSS class ('star-rating Three') with no numeric text in the DOM. "
            "Markdown/text extraction returns nothing; raw HTML requires resolving the word-to-digit mapping."
        ),
    ),
    # --- Category 8: Internationalisation and format ambiguity -------------------
    # German Wikipedia uses European number formatting: period as thousands separator,
    # comma as decimal (e.g. '293.628' = 293,628 not 293.628). A US-compiled regex or
    # naive model normalisation silently mis-parses the value.
    "format_ambiguity": ComparisonParams(
        name="format_ambiguity",
        url="https://de.wikipedia.org/wiki/Volkswagen",
        query="what is Volkswagen's annual revenue in euros for the most recent reported year?",
        items_format="one entry: 'Revenue: <full normalized integer, e.g. 293628000000> EUR (year: <year>, raw: <original string from page>)'",
        category=8,
        failure_type="semantic",
        description=(
            "German Wikipedia uses European number formatting (period as thousands separator, "
            "comma as decimal). A value like '293.628' means 293,628 — not 293.628. "
            "Tests whether the model normalizes or silently mis-parses the locale."
        ),
    ),
    # --- Category 9: Distractor contamination ------------------------------------
    # Wikipedia 2020 election page contains dozens of vote percentages: state-level results,
    # Electoral College tallies, third-party candidates. Model must return the top-line
    # national popular vote share, not a state figure or an opponent's number.
    "distractor_contamination": ComparisonParams(
        name="distractor_contamination",
        url="https://en.wikipedia.org/wiki/2020_United_States_presidential_election",
        query="what percentage of the popular vote did Joe Biden receive in the 2020 presidential election?",
        items_format="one entry: 'Biden national popular vote share: <exact percentage>' citing the specific table or section",
        category=9,
        failure_type="semantic",
        description=(
            "Page contains dozens of vote percentages (state results, third-party candidates, "
            "Electoral College tallies). Model must return the top-line national popular vote share, "
            "not a state result or an opponent figure."
        ),
    ),
}

DEFAULT_COMPARISON = "population_density"
