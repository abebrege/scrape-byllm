def preset_table() -> dict[str, str] {
    return {
        "links":      "<a\\b[^>]*?href=[\"']([^\"']+)[\"']",
        "images":     "<img\\b[^>]*?src=[\"']([^\"']+)[\"']",
        "emails":     "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}",
        "prices":     "[$€£¥]\\s?\\d[\\d,]*(?:\\.\\d{1,2})?",
        "phones":     "\\+?\\d[\\d().\\-\\s]{7,}\\d",
        "tables":     "<table\\b[\\s\\S]*?</table>",
        "headings":   "<h([1-6])\\b[^>]*>([\\s\\S]*?)</h\\1>",
        "jsonld":     "<script\\b[^>]*application/ld\\+json[^>]*>([\\s\\S]*?)</script>",
        "iframes":    "<iframe\\b[^>]*?src=[\"']([^\"']+)[\"']",
        "charts":     "<(?:canvas|svg)\\b[\\s\\S]*?</(?:canvas|svg)>",
        "buttons":    "<button\\b[^>]*>([\\s\\S]*?)</button>|<input\\b[^>]*?type=[\"'](?:submit|button)[\"'][^>]*>",
        "code":       "<(?:code|pre)\\b[^>]*>([\\s\\S]*?)</(?:code|pre)>",
        "links_text": "<a\\b[^>]*?>([\\s\\S]*?)</a>",
        "text":       ""
    };
}
