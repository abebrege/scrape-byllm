import from re { compile, IGNORECASE, sub }
import from bs4 { BeautifulSoup }


def strip_to_text(html: str) -> str {
    soup: any = BeautifulSoup(html, "lxml");
    for el in soup(["script", "style", "noscript"]) {
        el.decompose();
    }
    raw: str = str(soup.get_text(separator=" "));
    return sub("\\s+", " ", raw).strip();
}


def dedup(items: list[str]) -> list[str] {
    seen: set = set();
    result: list[str] = [];
    for item in items {
        if item not in seen {
            seen.add(item);
            result.append(item);
        }
    }
    return result;
}


def extract(plan: any, html: str) -> list[str] {
    haystack: str = "";
    if plan.on == "text" {
        haystack = strip_to_text(html);
    } else {
        haystack = html;
    }

    hay_len: int = len(haystack);
    radius: int = int(plan.window);
    out: list[str] = [];

    for pat in plan.patterns {
        if not pat {
            continue;
        }
        rx: any = compile(pat, IGNORECASE);
        it: any = rx.finditer(haystack);
        for m in it {
            ms: any = m.start();
            me: any = m.end();
            si: int = int(ms);
            ei: int = int(me);
            start: int = si - radius;
            if start < 0 {
                start = 0;
            }
            end: int = ei + radius;
            if end > hay_len {
                end = hay_len;
            }
            out.append(haystack[start:end]);
        }
    }

    if plan.on == "text" and not plan.patterns {
        out = [haystack];
    }

    return out;
}
