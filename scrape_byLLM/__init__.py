from __future__ import annotations

import sys
from typing import Any

__version__ = "0.1.0"
__all__ = ["ScrapeByLLM"]


def _bootstrap_jaclang() -> None:
    """Register jaclang's meta-path importer if it isn't already present."""
    try:
        from jaclang.meta_importer import JacMetaImporter
    except ImportError as exc:
        raise ImportError(
            "jaclang is required — install it with: pip install jaclang"
        ) from exc
    if any(isinstance(f, JacMetaImporter) for f in sys.meta_path):
        return
    sys.meta_path.insert(0, JacMetaImporter())


_bootstrap_jaclang()

from scrape_byLLM.scraper import ScrapeByLLM as _JacScrapeByLLM  # noqa: E402,I001
from scrape_byLLM.crawl import crawl as _jac_crawl  # noqa: E402


class ScrapeByLLM:
    """
    One LLM call compiles a reusable extraction plan for a given
    ``(pattern, query)`` pair. Use the ``get_all_*()`` methods to extract data
    from one or more pages. Or specify a custom query to generate a regex plan
    by LLM.

    Can be used as a context manager; ``quit()`` is called automatically on
    exit to release the headless-browser driver (only relevant when
    ``render=True``).

    Args:
        window: Context characters captured on each side of a regex match.
        max_chars: Maximum page characters forwarded to the LLM.
        timeout: Per-request HTTP timeout in seconds.
        render: Use headless Chrome instead of ``requests`` (for JS pages).
        dedup: Drop duplicate snippets within each page.
        synthesize: Run an extra LLM pass that returns a structured summary.
        output: Write the result dict as JSON to this path (side-effect only).
        html_sample_size: Characters of raw HTML sampled for plan compilation.
        respect_robots: Honour ``robots.txt`` — disallowed URLs are skipped.
        user_agent: HTTP ``User-Agent`` header value.
        extra_headers: Additional HTTP headers merged into every request.
        rate_limit: Minimum seconds between consecutive HTTP requests.
        ssrf_protection: Block requests to private/loopback IP ranges.
        allow_private_ips: Allow requests to private IPs (overrides ssrf_protection).
        allowed_hosts: Hostnames that bypass the IP check entirely.
        blocked_hosts: Hostnames that are always blocked.
        cache: Cache mode — ``off`` | ``readwrite`` | ``readonly`` | ``refresh``.
        cache_dir: Directory for on-disk HTTP and LLM response cache.
        cache_ttl: Cache time-to-live in seconds (0 = no expiry).
        cache_llm: Also cache LLM responses (plan + synthesis).
        proxies: Proxy URL or list of proxy URLs.
        proxy_rotation: Proxy selection strategy — ``round_robin`` | ``random`` | ``sticky``.
        proxy_max_failures: Drop a proxy after this many consecutive failures.
        injection_guard: Enable prompt-injection detection and regex validation.
        regex_timeout: Max seconds to test a regex against adversarial input.
    """

    def __init__(
        self,
        *,
        window: int = 200,
        max_chars: int = 200_000,
        timeout: int = 20,
        render: bool = False,
        dedup: bool = True,
        synthesize: bool = False,
        output: str | None = None,
        html_sample_size: int = 6_000,
        respect_robots: bool = True,
        user_agent: str = "scrape-byLLM",
        extra_headers: dict[str, str] | None = None,
        rate_limit: float = 0.0,
        # Phase 1 — SSRF
        ssrf_protection: bool = True,
        allow_private_ips: bool = False,
        allowed_hosts: list[str] | None = None,
        blocked_hosts: list[str] | None = None,
        # Phase 2 — Cache
        cache: str = "off",
        cache_dir: str = ".scrape_cache",
        cache_ttl: int = 0,
        cache_llm: bool = True,
        # Phase 3 — Proxy
        proxies: str | list[str] | None = None,
        proxy_rotation: str = "round_robin",
        proxy_max_failures: int = 3,
        # Phase 4 — Injection guard
        injection_guard: bool = True,
        regex_timeout: float = 1.0,
    ) -> None:
        self._impl = _JacScrapeByLLM()
        _cfg: dict[str, Any] = {
            "window": window,
            "max_chars": max_chars,
            "timeout": timeout,
            "render": render,
            "dedup": dedup,
            "synthesize": synthesize,
            "output": output,
            "html_sample_size": html_sample_size,
            "respect_robots": respect_robots,
            "user_agent": user_agent,
            "extra_headers": extra_headers or {},
            "rate_limit": rate_limit,
            "ssrf_protection": ssrf_protection,
            "allow_private_ips": allow_private_ips,
            "allowed_hosts": allowed_hosts or [],
            "blocked_hosts": blocked_hosts or [],
            "cache": cache,
            "cache_dir": cache_dir,
            "cache_ttl": cache_ttl,
            "cache_llm": cache_llm,
            "proxies": ([proxies] if isinstance(proxies, str) else proxies) or [],
            "proxy_rotation": proxy_rotation,
            "proxy_max_failures": proxy_max_failures,
            "injection_guard": injection_guard,
            "regex_timeout": regex_timeout,
        }
        for key, val in _cfg.items():
            self._impl.set(key, val)

    def __enter__(self) -> ScrapeByLLM:
        return self

    def __exit__(self, *_: Any) -> None:
        self.quit()

    def set(self, key: str, val: Any) -> None:
        self._impl.set(key, val)

    def get(self, key: str) -> Any:
        return self._impl.get(key)

    def _get_opts(self) -> dict[str, Any]:
        """Return a copy of the current configuration for passing to crawl()."""
        keys = [
            "window", "max_chars", "timeout", "render", "dedup", "synthesize",
            "output", "html_sample_size", "respect_robots", "user_agent",
            "extra_headers", "rate_limit", "ssrf_protection", "allow_private_ips",
            "allowed_hosts", "blocked_hosts", "cache", "cache_dir", "cache_ttl",
            "cache_llm", "proxies", "proxy_rotation", "proxy_max_failures",
            "injection_guard", "regex_timeout",
        ]
        return {k: self._impl.get(k) for k in keys}

    def get_all(
        self,
        source: str | list[str],
        query: str = "",
    ) -> dict[str, Any]:
        """For general queries, will generate a pattern by LLM and extract all matches.
        Use the following methods for more specific queries, as they are optimized for those tasks:
        - get_all_links
        - get_all_images
        - get_all_prices
        - get_all_emails
        - get_all_phones
        - get_all_tables
        - get_all_headings
        - get_all_text
        - get_all_charts
        - get_all_code
        """
        return dict(self._impl.get_all(source=source, query=query))

    def get_all_links(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<a href>`` URLs."""
        return dict(self._impl.get_all_links(source=source, query=query))

    def get_all_images(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<img src>`` URLs."""
        return dict(self._impl.get_all_images(source=source, query=query))

    def get_all_prices(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract price strings (``$``, ``€``, ``£``, ``¥``)."""
        return dict(self._impl.get_all_prices(source=source, query=query))

    def get_all_emails(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract e-mail addresses."""
        return dict(self._impl.get_all_emails(source=source, query=query))

    def get_all_phones(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract phone numbers."""
        return dict(self._impl.get_all_phones(source=source, query=query))

    def get_all_tables(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<table>`` blocks."""
        return dict(self._impl.get_all_tables(source=source, query=query))

    def get_all_headings(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<h1>``–``<h6>`` headings."""
        return dict(self._impl.get_all_headings(source=source, query=query))

    def get_all_text(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Return the full visible text of each page."""
        return dict(self._impl.get_all_text(source=source, query=query))

    def get_all_charts(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<canvas>`` and ``<svg>`` blocks."""
        return dict(self._impl.get_all_charts(source=source, query=query))

    def get_all_code(
        self, source: str | list[str], query: str = ""
    ) -> dict[str, Any]:
        """Extract ``<code>`` and ``<pre>`` blocks."""
        return dict(self._impl.get_all_code(source=source, query=query))

    def crawl(
        self,
        seed: str,
        query: str = "",
        pattern: str = "links",
        max_depth: int = 2,
        max_pages: int = 20,
        same_domain: bool = True,
        allowed_domains: list[str] | None = None,
        follow_pattern: str = "",
        exclude_pattern: str = "",
        paginate: bool = False,
    ) -> dict[str, Any]:
        """
        BFS crawl from *seed*, extracting data from every visited page.

        Returns the same result-dict shape as ``get_all_*()`` extended with
        ``pages_crawled`` and per-page ``depth`` on each result entry.
        """
        opts = self._get_opts()
        return dict(_jac_crawl(
            seed=seed,
            query=query,
            pattern=pattern,
            max_depth=max_depth,
            max_pages=max_pages,
            same_domain=same_domain,
            allowed_domains=allowed_domains or [],
            follow_pattern=follow_pattern,
            exclude_pattern=exclude_pattern,
            paginate=paginate,
            opts=opts,
        ))

    def quit(self) -> None:
        self._impl.quit()
