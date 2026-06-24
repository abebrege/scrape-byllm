import requests;
import from bs4 { BeautifulSoup }

glob MAX_CHARS: int = 40000;

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
