# Comparison Results

From the first run of comparison tests, raw results can be found at `/results`

## Price Disambiguation
**Category 1 — semantic**  
**Query:** what is the price of this book?  
**Description:** Product Information table has two price rows (excl. and incl. tax). Both are valid price strings; only context determines which the user wants. Sandbox page — stable, legal, no auth required.

### Direct Anthropic API
```
Price (excl. tax): £51.77
Price (incl. tax): £51.77
Tax: £0.00
```

### byLLM
```
(no items returned)
```

### Direct byLLM
```
A Light in the Attic - Price (excl. tax): £51.77
A Light in the Attic - Price (incl. tax): £51.77
A Light in the Attic - Tax: £0.00
```

### Direct Pipeline
```
Price (excl. tax): £51.77
Price (incl. tax): £51.77
Tax: £0.00
```

## Computed Value
**Category 2 — semantic**  
**Query:** what was Concorde's maximum speed in miles per hour?  
**Description:** Speed is given in km/h and Mach; the answer in mph requires a unit conversion not present on the page. Regex-plan can extract the raw number but cannot derive mph.

### Direct Anthropic API
```
Maximum speed: 1,354 mph (converted from Mach 2.04 / 2,179 km/h)
```

### byLLM
```
Mach 2.02
~2,154 km/h
~1,338 mph (maximum/optimum cruising speed)
Average cruise speed: Mach 2.02 (2,150 km/h; 1,330 mph)
```

### Direct byLLM
```
Concorde cruise speed: Mach 2.02 (~1,338 mph / 2,154 km/h)
Concorde average transatlantic cruise speed: Mach 2.02 (1,330 mph / 2,150 km/h)
Concorde Mach 2 speed reference: 1,320 mph (2,120 km/h)
Concorde maximum cruising altitude: 60,000 ft (18,000 m)
Concorde normal landing speed: 170 mph (274 km/h)
```

### Direct Pipeline
```
Maximum speed: 1,338 mph (converted from Mach 2.02 / 2,154 km/h)
```

## Merged Table Headers
**Category 3 — semantic**  
**Query:** what is the GDP of Germany, France, and Japan according to the IMF?  
**Description:** GDP table uses multi-level column headers (source × year) with colspan. Markdown flattening destroys cell-to-header mapping; model returns a value from roughly the right region of the table.

### Direct Anthropic API
```
Germany: 5,452,858 USD millions (IMF, 2026)
Japan: 4,379,253 USD millions (IMF, 2026)
France: 3,596,094 USD millions (IMF, 2026)
```

### byLLM
```
(no items returned)
```

### Direct byLLM
```
Germany: $5,452,858 million USD (IMF 2026 projection)
Japan: $4,379,253 million USD (IMF 2026 projection)
France: $3,596,094 million USD (IMF 2026 projection)
```

### Direct Pipeline
```
Germany: GDP figure not found in snippets (IMF, 2026 projection referenced but not extracted)
France: GDP figure not found in snippets (IMF, 2026 projection referenced but not extracted)
Japan: GDP figure not found in snippets (IMF, 2026 projection referenced but not extracted)
```

## Dispersed Extract All
**Category 4 — both**  
**Query:** return all book titles and their prices from this catalogue page  
**Description:** 1,000 books across 50 paginated pages. Single-page fetch returns 20 items; correct answer acknowledges pagination. Classic truncation failure: model returns the first ~20 as if the list were complete.

### Direct Anthropic API
```
A Light in the Attic: £51.77
Tipping the Velvet: £53.74
Soumission: £50.10
Sharp Objects: £47.82
Sapiens: A Brief History of Humankind: £54.23
The Requiem Red: £22.65
The Dirty Little Secrets of Getting Your Dream Job: £33.34
The Coming Woman: A Novel Based on the Life of the Infamous Feminist, Victoria Woodhull: £17.93
The Boys in the Boat: Nine Americans and Their Epic Quest for Gold at the 1936 Berlin Olympics: £22.60
The Black Maria: £52.15
Starving Hearts (Triangular Trade Trilogy, #1): £13.99
Shakespeare's Sonnets: £20.66
Set Me Free: £17.46
Scott Pilgrim's Precious Little Life (Scott Pilgrim #1): £52.29
Rip it Up and Start Again: £35.02
Our Band Could Be Your Life: Scenes from the American Indie Underground, 1981-1991: £57.25
Olio: £23.88
Mesaerion: The Best Science Fiction Stories 1800-1849: £37.59
Libertarianism for Beginners: £51.33
It's Only the Himalayas: £45.17
```

### byLLM
```
A Light in the Attic — £51.77
Tipping the Velvet — £53.74
Soumission — £50.10
Sharp Objects — £47.82
Sapiens: A Brief History of Humankind — £54.23
The Requiem Red — £22.65
The Dirty Little Secrets of Getting Your Dream Job — £33.34
The Coming Woman: A Novel Based on the Life of the Infamous Feminist, Victoria Woodhull — £17.93
The Boys in the Boat: Nine Americans and Their Epic Quest for Gold at the 1936 Berlin Olympics — £22.60
The Black Maria — £52.15
Starving Hearts (Triangular Trade Trilogy, #1) — £13.99
Shakespeare's Sonnets — £20.66
Set Me Free — £17.46
Scott Pilgrim's Precious Little Life (Scott Pilgrim #1) — £52.29
Rip it Up and Start Again — £35.02
Our Band Could Be Your Life: Scenes from the American Indie Underground, 1981-1991 — £57.25
Olio — £23.88
Mesaerion: The Best Science Fiction Stories 1800-1849 — £37.59
Libertarianism for Beginners — £51.33
It's Only the Himalayas — £45.17
```

### Direct byLLM
```
A Light in the Attic: £51.77
Tipping the Velvet: £53.74
Soumission: £50.10
Sharp Objects: £47.82
Sapiens: A Brief History of Humankind: £54.23
The Requiem Red: £22.65
The Dirty Little Secrets of Getting Your Dream Job: £33.34
The Coming Woman: A Novel Based on the Life of the Infamous Feminist, Victoria Woodhull: £17.93
The Boys in the Boat: Nine Americans and Their Epic Quest for Gold at the 1936 Berlin Olympics: £22.60
The Black Maria: £52.15
Starving Hearts (Triangular Trade Trilogy, #1): £13.99
Shakespeare's Sonnets: £20.66
Set Me Free: £17.46
Scott Pilgrim's Precious Little Life (Scott Pilgrim #1): £52.29
Rip it Up and Start Again: £35.02
Our Band Could Be Your Life: Scenes from the American Indie Underground, 1981-1991: £57.25
Olio: £23.88
Mesaerion: The Best Science Fiction Stories 1800-1849: £37.59
Libertarianism for Beginners: £51.33
It's Only the Himalayas: £45.17
```

### Direct Pipeline
```
A Light in the Attic: £51.77
Tipping the Velvet: £53.74
Soumission: £50.10
Sharp Objects: £47.82
Sapiens: A Brief History of Humankind: £54.23
The Requiem Red: £22.65
The Dirty Little Secrets of Getting Your Dream Job: £33.34
The Coming Woman: A Novel Based on the Life of the Infamous Feminist, Victoria Woodhull: £17.93
The Boys in the Boat: Nine Americans and Their Epic Quest for Gold at the 1936 Berlin Olympics: £22.60
The Black Maria: £52.15
Starving Hearts (Triangular Trade Trilogy, #1): £13.99
Shakespeare's Sonnets: £20.66
Set Me Free: £17.46
Scott Pilgrim's Precious Little Life (Scott Pilgrim #1): £52.29
Rip it Up and Start Again: £35.02
Our Band Could Be Your Life: Scenes from the American Indie Underground, 1981-1991: £57.25
Olio: £23.88
Mesaerion: The Best Science Fiction Stories 1800-1849: £37.59
Libertarianism for Beginners: £51.33
It's Only the Himalayas: £45.17
```

## Population Density
**Category 4 — both**  
**Query:** return the population of each country from the tables on this page  
**Description:** Baseline dispersed-extraction case: multiple tables spread across a long page. Structural failure is a partial list that looks complete.

### Direct Anthropic API
```
Macau (China): 650,834
Monaco: 37,550
Singapore: 6,036,900
Hong Kong (China): 7,409,800
Gaza Strip (Palestine): 2,098,389
Gibraltar (UK): 33,140
Bahrain: 1,451,200
Vatican City: 800
Malta: 475,701
Maldives: 378,114
Bangladesh: 170,329,768
Taiwan: 23,539,588
Rwanda: 13,246,394
Netherlands: 17,943,243
South Korea: 51,439,038
Burundi: 12,574,571
India: 1,374,547,140
Haiti: 11,743,017
Belgium: 11,554,449
Philippines: 109,961,895
```

### byLLM
```
Macau (China): 650,834
Monaco: 37,550
Singapore: 6,036,900
Hong Kong (China): 7,409,800
Gaza Strip (Palestine): 2,098,389
Gibraltar (UK): 33,140
Bahrain: 1,451,200
Vatican City: 800
Malta: 475,701
Maldives: 378,114
Bangladesh: 170,329,768
Taiwan: 23,539,588
Rwanda: 13,246,394
Netherlands: 17,943,243
South Korea: 51,439,038
Burundi: 12,574,571
India: 1,374,547,140
Haiti: 11,743,017
Belgium: 11,554,449
Philippines: 109,961,895
```

### Direct byLLM
```
Macau (China): 650,834
Monaco: 37,550
Singapore: 6,036,900
Hong Kong (China): 7,409,800
Gaza Strip (Palestine): 2,098,389
Gibraltar (UK): 33,140
Bahrain: 1,451,200
Vatican City: 800
Malta: 475,701
Maldives: 378,114
Bangladesh: 170,329,768
Taiwan: 23,539,588
Rwanda: 13,246,394
Netherlands: 17,943,243
South Korea: 51,439,038
Burundi: 12,574,571
India: 1,374,547,140
Haiti: 11,743,017
Belgium: 11,554,449
Philippines: 109,961,895
```

### Direct Pipeline
```
Macau (China): 650,834
Monaco: 37,550
Singapore: 6,036,900
Hong Kong (China): 7,409,800
Gaza Strip (Palestine): 2,098,389
Gibraltar (UK): 33,140
Bahrain: 1,451,200
Vatican City: 800
Malta: 475,701
Maldives: 378,114
Bangladesh: 170,329,768
Taiwan: 23,539,588
Rwanda: 13,246,394
Netherlands: 17,943,243
South Korea: 51,439,038
Burundi: 12,574,571
India: 1,374,547,140
Haiti: 11,743,017
Belgium: 11,554,449
Philippines: 109,961,895
```

## Absent Data
**Category 5 — semantic**  
**Query:** what is the ISBN of this book?  
**Description:** Product Information table has UPC but no ISBN field. Correct answer is NOT FOUND. Failure is fabricating a plausible numeric string — structurally valid, semantically catastrophic. Cleanest demonstration of the structural/semantic gap.

### Direct Anthropic API
```
ISBN: NOT FOUND
UPC (closest equivalent identifier on this site): a897fe39b1053632
```

### byLLM
```
UPC: a897fe39b1053632
```

### Direct byLLM
```
UPC (used as book identifier): a897fe39b1053632
```

### Direct Pipeline
```
ISBN: NOT FOUND
```

## Implicit Relational
**Category 6 — semantic**  
**Query:** who is the author of this book?  
**Description:** Author is not a labeled field in the Product Information table but is named in the prose description. Tests inference from running text; regex-plan cannot resolve this.

### Direct Anthropic API
```
Author: Shel Silverstein
```

### byLLM
```
Shel Silverstein
```

### Direct byLLM
```
Author: Shel Silverstein
```

### Direct Pipeline
```
Author: Shel Silverstein
```

## Visual Encoding
**Category 7 — semantic**  
**Query:** what is the star rating of this book?  
**Description:** Star rating is encoded as a CSS class ('star-rating Three') with no numeric text in the DOM. Markdown/text extraction returns nothing; raw HTML requires resolving the word-to-digit mapping.

### Direct Anthropic API
```
Star rating: 3 out of 5
```

### byLLM
```
Star Rating: Three (3/5)
```

### Direct byLLM
```
A Light in the Attic: 3 out of 5 stars
```

### Direct Pipeline
```
Star rating: 3 out of 5
```

## Format Ambiguity
**Category 8 — semantic**  
**Query:** what is Volkswagen's annual revenue in euros for the most recent reported year?  
**Description:** German Wikipedia uses European number formatting (period as thousands separator, comma as decimal). A value like '293.628' means 293,628 — not 293.628. Tests whether the model normalizes or silently mis-parses the locale.

### Direct Anthropic API
```
Revenue: 322300000000 EUR (year: 2023, raw: not explicitly stated on the fetched page — sourced from Volkswagen AG annual report 2023 as referenced by the page's claim of world-leading Umsatz in 2023)
```

### byLLM
```
(no items returned)
```

### Direct byLLM
```
Annual revenue (EUR): Not available on this page — no specific revenue figure in euros is reported
Note: 2023 global VW Group registrations: 9.2 million vehicles
Note: 2023 VW brand registrations: 4.87 million vehicles
Note: Article states VW AG was the largest automaker by revenue (Umsatz) in 2023, but gives no euro amount
```

### Direct Pipeline
```
(no items returned)
```

## Distractor Contamination
**Category 9 — semantic**  
**Query:** what percentage of the popular vote did Joe Biden receive in the 2020 presidential election?  
**Description:** Page contains dozens of vote percentages (state results, third-party candidates, Electoral College tallies). Model must return the top-line national popular vote share, not a state result or an opponent figure.

### Direct Anthropic API
```
Biden national popular vote share: 51.31% (cited in the article's popular vote results table and the election narrative section: 'Biden won 306 Electoral College votes and 51.3% of the popular vote')
```

### byLLM
```
Joe Biden popular vote percentage: 51.3%
Joe Biden total popular votes: 81,283,501
Donald Trump popular vote percentage: 46.8%
Donald Trump total popular votes: 74,223,975
```

### Direct byLLM
```
Joe Biden popular vote percentage: 51.3%
Joe Biden popular vote total: 81,283,501
Donald Trump popular vote percentage: 46.8%
Donald Trump popular vote total: 74,223,975
Voter turnout: 66.6% (up 6.5 percentage points from 2016)
```

### Direct Pipeline
```
Biden national popular vote share: 51.3% (81,283,501 votes) — sourced from the 2020 United States Presidential Election infobox table and results summary on Wikipedia (https://en.wikipedia.org/wiki/2020_United_States_presidential_election)
```
