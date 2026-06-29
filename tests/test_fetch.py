"""Tests for scrape_byLLM.fetch — HTTP fetching, retries, rate limiting."""

from unittest.mock import patch

import pytest
import responses as resp_lib
from scrape_byLLM.fetch import _http_get, fetch_one, normalize_source


class TestNormalizeSource:
    def test_http_url(self) -> None:
        result = normalize_source("http://example.com")
        assert result == [{"url": "http://example.com", "html": ""}]

    def test_https_url(self) -> None:
        result = normalize_source("https://example.com/path")
        assert result == [{"url": "https://example.com/path", "html": ""}]

    def test_inline_html(self) -> None:
        result = normalize_source("<html>hi</html>")
        assert result == [{"url": "", "html": "<html>hi</html>"}]

    def test_list_of_urls(self) -> None:
        result = normalize_source(["http://a.com", "http://b.com"])
        assert len(result) == 2
        assert result[0]["url"] == "http://a.com"
        assert result[1]["url"] == "http://b.com"

    def test_mixed_list(self) -> None:
        result = normalize_source(["http://a.com", "inline text"])
        assert result[0]["url"] == "http://a.com"
        assert result[1]["html"] == "inline text"

    def test_empty_list(self) -> None:
        assert normalize_source([]) == []


class TestHttpGet:
    @resp_lib.activate
    def test_successful_get(self) -> None:
        resp_lib.add(resp_lib.GET, "http://example.com", body="<html>OK</html>", status=200)
        result = _http_get("http://example.com", timeout=5, headers={})
        assert "OK" in result

    @resp_lib.activate
    def test_retries_on_429(self) -> None:
        resp_lib.add(resp_lib.GET, "http://example.com", body="rate limited", status=429)
        resp_lib.add(resp_lib.GET, "http://example.com", body="<html>OK</html>", status=200)
        with patch("time.sleep"):
            result = _http_get("http://example.com", timeout=5, headers={}, max_retries=2)
        assert "OK" in result

    @resp_lib.activate
    def test_retries_on_503(self) -> None:
        resp_lib.add(resp_lib.GET, "http://example.com", body="unavailable", status=503)
        resp_lib.add(resp_lib.GET, "http://example.com", body="<html>back</html>", status=200)
        with patch("time.sleep"):
            result = _http_get("http://example.com", timeout=5, headers={}, max_retries=2)
        assert "back" in result

    @resp_lib.activate
    def test_raises_after_max_retries(self) -> None:
        for _ in range(3):
            resp_lib.add(resp_lib.GET, "http://example.com", body="fail", status=429)
        with patch("time.sleep"):
            with pytest.raises(Exception):
                _http_get("http://example.com", timeout=5, headers={}, max_retries=3)

    @resp_lib.activate
    def test_custom_headers_sent(self) -> None:
        resp_lib.add(resp_lib.GET, "http://example.com", body="OK", status=200)
        _http_get("http://example.com", timeout=5, headers={"X-Custom": "test"})
        assert resp_lib.calls[0].request.headers["X-Custom"] == "test"

    @resp_lib.activate
    def test_connection_error_retries(self) -> None:
        import requests
        resp_lib.add(
            resp_lib.GET, "http://example.com",
            body=requests.exceptions.ConnectionError("connection refused"),
        )
        resp_lib.add(resp_lib.GET, "http://example.com", body="<html>OK</html>", status=200)
        with patch("time.sleep"):
            result = _http_get("http://example.com", timeout=5, headers={}, max_retries=2)
        assert "OK" in result


class TestFetchOne:
    @resp_lib.activate
    def test_fetch_static_page(self) -> None:
        resp_lib.add(
            resp_lib.GET, "https://example.com/robots.txt",
            body="User-agent: *\nAllow: /\n", status=200,
        )
        resp_lib.add(resp_lib.GET, "https://example.com", body="<html>hello</html>", status=200)
        result = fetch_one("https://example.com", respect_robots=True,
                           _ctx={"ssrf_protection": False})
        assert "hello" in result

    @resp_lib.activate
    def test_robots_blocked_raises(self) -> None:
        from scrape_byLLM.robots import _robots_cache
        _robots_cache.clear()
        resp_lib.add(
            resp_lib.GET, "https://blocked.test/robots.txt",
            body="User-agent: *\nDisallow: /\n", status=200,
        )
        with pytest.raises(ValueError, match="robots.txt"):
            fetch_one("https://blocked.test/page", respect_robots=True)

    @resp_lib.activate
    def test_respect_robots_false_skips_check(self) -> None:
        # No robots.txt response registered — would fail if fetched.
        resp_lib.add(resp_lib.GET, "https://example.com", body="<html>data</html>", status=200)
        result = fetch_one("https://example.com", respect_robots=False,
                           _ctx={"ssrf_protection": False})
        assert "data" in result

    @resp_lib.activate
    def test_max_chars_truncates(self) -> None:
        resp_lib.add(resp_lib.GET, "https://example.com", body="A" * 1000, status=200)
        result = fetch_one("https://example.com", respect_robots=False, max_chars=100,
                           _ctx={"ssrf_protection": False})
        assert len(result) == 100

    def test_rate_limiting_sleeps(self) -> None:
        import time

        import scrape_byLLM.fetch as fetch_mod
        from scrape_byLLM.fetch import _last_request_time

        # Record "just now" so elapsed will be nearly 0 and sleep will fire.
        _last_request_time[0] = time.time()

        with resp_lib.RequestsMock() as rsps:
            rsps.add(rsps.GET, "https://example.com", body="OK", status=200)
            # Patch sleep in the Jac fetch module's namespace.
            with patch.object(fetch_mod, "sleep") as mock_sleep:
                fetch_one(
                    "https://example.com",
                    respect_robots=False,
                    rate_limit=1.0,
                    _ctx={"ssrf_protection": False},
                )
        mock_sleep.assert_called_once()
        delay_arg = mock_sleep.call_args[0][0]
        assert 0 < delay_arg <= 1.0
