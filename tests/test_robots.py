"""Tests for scrape_byLLM.robots — robots.txt fetching and enforcement."""

import pytest
import responses as resp_lib
from scrape_byLLM.robots import _robots_cache, get_crawl_delay, is_allowed


@pytest.fixture(autouse=True)
def clear_cache() -> None:
    """Wipe the domain cache before every test."""
    _robots_cache.clear()
    yield
    _robots_cache.clear()


class TestIsAllowed:
    def test_non_http_always_allowed(self) -> None:
        assert is_allowed("<inline>") is True
        assert is_allowed("plain text") is True

    def test_respect_robots_false_always_allowed(self) -> None:
        assert is_allowed("http://example.com/secret", respect_robots=False) is True

    @resp_lib.activate
    def test_disallowed_path_blocked(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nDisallow: /private/\n",
            status=200,
        )
        assert is_allowed("http://example.com/private/page") is False

    @resp_lib.activate
    def test_allowed_path_passes(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nDisallow: /private/\n",
            status=200,
        )
        assert is_allowed("http://example.com/public/page") is True

    @resp_lib.activate
    def test_robots_txt_missing_fails_open(self) -> None:
        resp_lib.add(resp_lib.GET, "http://example.com/robots.txt", body="Not Found", status=404)
        assert is_allowed("http://example.com/any/path") is True

    @resp_lib.activate
    def test_robots_txt_cached(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nDisallow: /\n",
            status=200,
        )
        is_allowed("http://example.com/a")
        is_allowed("http://example.com/b")
        # robots.txt should only have been fetched once
        robots_calls = [c for c in resp_lib.calls if "robots.txt" in c.request.url]
        assert len(robots_calls) == 1

    @resp_lib.activate
    def test_allow_all_robots(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nAllow: /\n",
            status=200,
        )
        assert is_allowed("http://example.com/anything") is True

    @resp_lib.activate
    def test_disallow_all_robots(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nDisallow: /\n",
            status=200,
        )
        assert is_allowed("http://example.com/") is False


class TestGetCrawlDelay:
    def test_non_http_returns_zero(self) -> None:
        assert get_crawl_delay("<inline>") == 0.0

    @resp_lib.activate
    def test_crawl_delay_present(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nCrawl-delay: 2\n",
            status=200,
        )
        delay = get_crawl_delay("http://example.com/page")
        assert delay == 2.0

    @resp_lib.activate
    def test_crawl_delay_absent_returns_zero(self) -> None:
        resp_lib.add(
            resp_lib.GET, "http://example.com/robots.txt",
            body="User-agent: *\nDisallow: /private/\n",
            status=200,
        )
        delay = get_crawl_delay("http://example.com/page")
        assert delay == 0.0


class TestPerSourceIsolation:
    """Integration-level: bad URL in a batch should not kill the rest."""

    def test_failed_source_gets_error_key(self) -> None:
        from scrape_byLLM.scraper import spawn_scrape

        result = spawn_scrape(
            pattern="emails",
            source=["https://this-host-does-not-exist-xyz.invalid/", "email@example.com here"],
            query="",
            opts={"respect_robots": False, "timeout": 3},
        )
        assert result["page_count"] == 2
        bad = result["results"][0]
        good = result["results"][1]
        assert "error" in bad
        assert "error" not in good

    def test_successful_sources_return_snippets(self) -> None:
        from scrape_byLLM.scraper import spawn_scrape

        result = spawn_scrape(
            pattern="emails",
            source=["first@a.com inline", "second@b.org inline"],
            query="",
            opts={"respect_robots": False},
        )
        assert all("error" not in r for r in result["results"])
        assert any("first@a.com" in sn for sn in result["results"][0]["snippets"])
        assert any("second@b.org" in sn for sn in result["results"][1]["snippets"])
