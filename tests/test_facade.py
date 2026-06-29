"""Tests for the Python facade (scrape_byLLM/__init__.py)."""

from scrape_byLLM import ScrapeByLLM


class TestInstantiation:
    def test_default_kwargs(self) -> None:
        s = ScrapeByLLM()
        assert s.get("window") == 200
        assert s.get("max_chars") == 40_000
        assert s.get("timeout") == 20
        assert s.get("render") is False
        assert s.get("dedup") is True
        assert s.get("synthesize") is False
        assert s.get("output") is None
        assert s.get("html_sample_size") == 6_000
        assert s.get("respect_robots") is True
        assert s.get("user_agent") == "scrape-byLLM"
        assert s.get("extra_headers") == {}
        assert s.get("rate_limit") == 0.0
        # Phase 1 — SSRF
        assert s.get("ssrf_protection") is True
        assert s.get("allow_private_ips") is False
        assert s.get("allowed_hosts") == []
        assert s.get("blocked_hosts") == []
        # Phase 2 — Cache
        assert s.get("cache") == "off"
        assert s.get("cache_dir") == ".scrape_cache"
        assert s.get("cache_ttl") == 0
        assert s.get("cache_llm") is True
        # Phase 3 — Proxy
        assert s.get("proxies") == []
        assert s.get("proxy_rotation") == "round_robin"
        assert s.get("proxy_max_failures") == 3
        # Phase 4 — Injection guard
        assert s.get("injection_guard") is True
        assert s.get("regex_timeout") == 1.0

    def test_custom_kwargs(self) -> None:
        s = ScrapeByLLM(window=100, timeout=30, user_agent="my-bot")
        assert s.get("window") == 100
        assert s.get("timeout") == 30
        assert s.get("user_agent") == "my-bot"

    def test_boolean_kwargs(self) -> None:
        s = ScrapeByLLM(render=True, dedup=False, synthesize=True, respect_robots=False)
        assert s.get("render") is True
        assert s.get("dedup") is False
        assert s.get("synthesize") is True
        assert s.get("respect_robots") is False

    def test_extra_headers(self) -> None:
        s = ScrapeByLLM(extra_headers={"X-Custom": "value"})
        assert s.get("extra_headers") == {"X-Custom": "value"}

    def test_extra_headers_default_is_empty_dict(self) -> None:
        s = ScrapeByLLM()
        assert s.get("extra_headers") == {}

    def test_rate_limit(self) -> None:
        s = ScrapeByLLM(rate_limit=1.5)
        assert s.get("rate_limit") == 1.5


class TestGetSet:
    def test_set_then_get(self) -> None:
        s = ScrapeByLLM()
        s.set("window", 500)
        assert s.get("window") == 500

    def test_set_overrides_constructor(self) -> None:
        s = ScrapeByLLM(timeout=10)
        s.set("timeout", 60)
        assert s.get("timeout") == 60

    def test_set_custom_key(self) -> None:
        s = ScrapeByLLM()
        s.set("custom_key", "custom_value")
        assert s.get("custom_key") == "custom_value"

    def test_get_missing_key_returns_none(self) -> None:
        s = ScrapeByLLM()
        assert s.get("nonexistent_key") is None


class TestContextManager:
    def test_enter_returns_self(self) -> None:
        s = ScrapeByLLM()
        assert s.__enter__() is s

    def test_with_block(self) -> None:
        with ScrapeByLLM(window=50) as s:
            assert s.get("window") == 50

    def test_with_block_kwargs(self) -> None:
        with ScrapeByLLM(user_agent="ctx-bot", respect_robots=False) as s:
            assert s.get("user_agent") == "ctx-bot"
            assert s.get("respect_robots") is False


class TestPresetScraping:
    """Tests that run the full scrape pipeline with inline HTML (no network)."""

    def test_get_all_emails_inline(self) -> None:
        s = ScrapeByLLM(respect_robots=False)
        result = s.get_all_emails(source="Contact: hello@example.com or info@test.org")
        assert result["pattern"] == "emails"
        assert result["strategy"] == "preset"
        assert result["page_count"] == 1
        snippets = result["results"][0]["snippets"]
        assert any("hello@example.com" in sn for sn in snippets)

    def test_get_all_links_inline(self) -> None:
        s = ScrapeByLLM(respect_robots=False)
        html = '<a href="https://example.com">link</a>'
        result = s.get_all_links(source=html)
        assert result["pattern"] == "links"
        snippets = result["results"][0]["snippets"]
        assert any("example.com" in sn for sn in snippets)

    def test_multi_source_inline(self) -> None:
        s = ScrapeByLLM(respect_robots=False)
        result = s.get_all_emails(
            source=[
                "first@example.com",
                "second@example.com",
            ]
        )
        assert result["page_count"] == 2
        assert len(result["results"]) == 2

    def test_result_shape(self) -> None:
        s = ScrapeByLLM(respect_robots=False, ssrf_protection=False)
        result = s.get_all_emails(source="test@x.com")
        expected_keys = (
            "pattern", "query", "strategy", "on",
            "patterns", "page_count", "llm_calls", "results",
            "fetch_hits", "fetch_misses", "blocked_urls", "pages_crawled",
        )
        for key in expected_keys:
            assert key in result, f"missing key: {key}"
