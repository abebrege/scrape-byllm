"""Tests for scrape_byLLM.guard_fetch — SSRF, cache, proxy."""
from __future__ import annotations

import os
import time
from pathlib import Path
from unittest.mock import patch

import pytest
import responses as resp_lib

from scrape_byLLM.guard_fetch import (
    SSRFError,
    _http_cache_key,
    _is_private_ip,
    _resolve_to_ips,
    cache_get_http,
    cache_put_http,
    canonicalize_url,
    get_proxy,
    guarded_http_get,
    record_proxy_failure,
    reset_proxy_state,
    validate_url_ssrf,
)

class TestIsPrivateIp:
    def test_loopback_v4(self):
        assert _is_private_ip("127.0.0.1") is True

    def test_loopback_v6(self):
        assert _is_private_ip("::1") is True

    def test_rfc1918_10(self):
        assert _is_private_ip("10.0.0.1") is True

    def test_rfc1918_172(self):
        assert _is_private_ip("172.16.0.1") is True

    def test_rfc1918_192(self):
        assert _is_private_ip("192.168.1.1") is True

    def test_link_local(self):
        assert _is_private_ip("169.254.169.254") is True

    def test_cgn(self):
        assert _is_private_ip("100.64.0.1") is True

    def test_ula_v6(self):
        assert _is_private_ip("fd00::1") is True

    def test_link_local_v6(self):
        assert _is_private_ip("fe80::1") is True

    def test_public_v4(self):
        assert _is_private_ip("8.8.8.8") is False

    def test_public_v4_example(self):
        assert _is_private_ip("93.184.216.34") is False

    def test_public_v6(self):
        assert _is_private_ip("2001:db8::1") is False

    def test_unparseable_blocked(self):
        assert _is_private_ip("not-an-ip") is True

class TestValidateUrlSsrf:
    def test_ssrf_disabled_passthrough(self):
        validate_url_ssrf("http://192.168.1.1/admin", {"ssrf_protection": False})

    def test_file_scheme_blocked(self):
        with pytest.raises(SSRFError, match="Scheme not allowed"):
            validate_url_ssrf("file:///etc/passwd", {})

    def test_ftp_scheme_blocked(self):
        with pytest.raises(SSRFError, match="Scheme not allowed"):
            validate_url_ssrf("ftp://example.com", {})

    def test_data_scheme_blocked(self):
        with pytest.raises(SSRFError, match="Scheme not allowed"):
            validate_url_ssrf("data:text/html,<h1>hi</h1>", {})

    def test_blocked_host(self):
        ctx = {"blocked_hosts": ["evil.internal"]}
        with pytest.raises(SSRFError, match="explicitly blocked"):
            validate_url_ssrf("http://evil.internal/data", ctx)

    def test_allowed_host_skips_ip_check(self):
        ctx = {"allowed_hosts": ["intranet.corp"]}
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips") as mock_gai:
            validate_url_ssrf("http://intranet.corp/api", ctx)
            mock_gai.assert_not_called()

    def test_private_ip_url_blocked(self):
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["192.168.1.100"]):
            with pytest.raises(SSRFError, match="private"):
                validate_url_ssrf("http://some-host.local/", {})

    def test_loopback_blocked(self):
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["127.0.0.1"]):
            with pytest.raises(SSRFError):
                validate_url_ssrf("http://localhost/", {})

    def test_metadata_endpoint_blocked(self):
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["169.254.169.254"]):
            with pytest.raises(SSRFError):
                validate_url_ssrf("http://metadata.google.internal/", {})

    def test_allow_private_ips_flag(self):
        ctx = {"allow_private_ips": True}
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["192.168.1.100"]):
            validate_url_ssrf("http://internal.example.com/", ctx)  # no raise

    def test_unresolvable_host_blocked(self):
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips", return_value=[]):
            with pytest.raises(SSRFError, match="Could not resolve"):
                validate_url_ssrf("http://no-such-host.invalid/", {})

    def test_blocked_url_increments_counter(self):
        ctx: dict = {}
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["127.0.0.1"]):
            with pytest.raises(SSRFError):
                validate_url_ssrf("http://localhost/", ctx)
        assert ctx.get("blocked_urls", 0) == 1

    def test_public_host_passes(self):
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["93.184.216.34"]):
            validate_url_ssrf("http://example.com/", {})  # no raise

class TestCanonicalizeUrl:
    def test_lowercases_scheme_and_host(self):
        result = canonicalize_url("HTTP://Example.COM/Path")
        assert result.startswith("http://example.com")

    def test_strips_fragment(self):
        assert "#section" not in canonicalize_url("https://example.com/page#section")

    def test_strips_default_http_port(self):
        assert ":80" not in canonicalize_url("http://example.com:80/path")

    def test_strips_default_https_port(self):
        assert ":443" not in canonicalize_url("https://example.com:443/path")

    def test_preserves_nondefault_port(self):
        assert "8080" in canonicalize_url("http://example.com:8080/path")

    def test_preserves_query(self):
        result = canonicalize_url("https://example.com/search?q=test&page=2")
        assert "q=test" in result

    def test_bare_host_gets_slash(self):
        result = canonicalize_url("http://example.com")
        assert result.endswith("/")

class TestHttpCache:
    def test_miss_when_off(self):
        ctx = {"cache": "off"}
        assert cache_get_http("http://x.com", False, {}, ctx) is None

    def test_readwrite_roundtrip(self, tmp_path):
        ctx = {"cache": "readwrite", "cache_dir": str(tmp_path)}
        cache_put_http("http://example.com/p", False, {}, "<html>hi</html>", ctx)
        result = cache_get_http("http://example.com/p", False, {}, ctx)
        assert result == "<html>hi</html>"

    def test_hit_increments_counter(self, tmp_path):
        ctx = {"cache": "readwrite", "cache_dir": str(tmp_path)}
        cache_put_http("http://example.com/cnt", False, {}, "body", ctx)
        cache_get_http("http://example.com/cnt", False, {}, ctx)
        assert ctx.get("fetch_hits", 0) == 1

    def test_readonly_reads_but_no_write(self, tmp_path):
        ctx_rw = {"cache": "readwrite", "cache_dir": str(tmp_path)}
        cache_put_http("http://ro.test/", False, {}, "original", ctx_rw)

        ctx_ro = {"cache": "readonly", "cache_dir": str(tmp_path)}
        assert cache_get_http("http://ro.test/", False, {}, ctx_ro) == "original"

        cache_put_http("http://ro.test/", False, {}, "overwrite", ctx_ro)
        assert cache_get_http("http://ro.test/", False, {}, ctx_ro) == "original"

    def test_refresh_ignores_existing(self, tmp_path):
        ctx_rw = {"cache": "readwrite", "cache_dir": str(tmp_path)}
        cache_put_http("http://example.com/rf", False, {}, "old", ctx_rw)

        ctx_rf = {"cache": "refresh", "cache_dir": str(tmp_path)}
        assert cache_get_http("http://example.com/rf", False, {}, ctx_rf) is None

    def test_ttl_expiry(self, tmp_path):
        ctx = {"cache": "readwrite", "cache_dir": str(tmp_path), "cache_ttl": 1}
        cache_put_http("http://example.com/ttl", False, {}, "data", ctx)

        # Backdate the cache file
        key = _http_cache_key("http://example.com/ttl", False, {})
        cache_file = tmp_path / "http" / key[:2] / key
        old = time.time() - 10
        os.utime(cache_file, (old, old))

        assert cache_get_http("http://example.com/ttl", False, {}, ctx) is None

    def test_render_flag_different_key(self, tmp_path):
        ctx = {"cache": "readwrite", "cache_dir": str(tmp_path)}
        cache_put_http("http://example.com/", False, {}, "static", ctx)
        assert cache_get_http("http://example.com/", True, {}, ctx) is None

class TestProxy:
    def setup_method(self):
        reset_proxy_state()

    def test_no_proxies_returns_none(self):
        assert get_proxy("http://x.com", {}) is None

    def test_single_proxy_string(self):
        ctx = {"proxies": "http://proxy:8080"}
        assert get_proxy("http://x.com", ctx) == "http://proxy:8080"

    def test_round_robin_cycles(self):
        ctx = {
            "proxies": ["http://p1:8080", "http://p2:8080"],
            "proxy_rotation": "round_robin",
        }
        first = get_proxy("http://x.com", ctx)
        second = get_proxy("http://x.com", ctx)
        assert first != second

    def test_sticky_same_domain_same_proxy(self):
        ctx = {
            "proxies": ["http://p1:8080", "http://p2:8080", "http://p3:8080"],
            "proxy_rotation": "sticky",
        }
        a = get_proxy("http://example.com/page1", ctx)
        b = get_proxy("http://example.com/page2", ctx)
        assert a == b

    def test_dead_proxy_dropped(self):
        ctx = {
            "proxies": ["http://dead:8080", "http://alive:8080"],
            "proxy_rotation": "round_robin",
            "proxy_max_failures": 2,
        }
        record_proxy_failure("http://dead:8080", ctx)
        record_proxy_failure("http://dead:8080", ctx)
        results = {get_proxy("http://x.com", ctx) for _ in range(6)}
        assert "http://dead:8080" not in results

    def test_all_dead_returns_none(self):
        ctx = {"proxies": ["http://dead:8080"], "proxy_max_failures": 1}
        record_proxy_failure("http://dead:8080", ctx)
        assert get_proxy("http://x.com", ctx) is None

class TestGuardedHttpGet:
    def test_ssrf_blocks_private_ip(self):
        ctx: dict = {}
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   return_value=["10.0.0.1"]):
            with pytest.raises(SSRFError):
                guarded_http_get("http://internal.example.com/", ctx, {}, 5)

    @resp_lib.activate
    def test_cache_hit_avoids_network(self, tmp_path):
        ctx = {
            "cache": "readwrite",
            "cache_dir": str(tmp_path),
            "ssrf_protection": False,
        }
        cache_put_http("http://example.com/", False, {}, "from cache", ctx)
        # No response registered — would raise ConnectionError if fetched
        result = guarded_http_get("http://example.com/", ctx, {}, 5)
        assert result == "from cache"

    @resp_lib.activate
    def test_successful_get_stored_in_cache(self, tmp_path):
        resp_lib.add(resp_lib.GET, "http://example.com/page",
                     body="<html>OK</html>", status=200)
        ctx = {
            "cache": "readwrite",
            "cache_dir": str(tmp_path),
            "ssrf_protection": False,
        }
        result = guarded_http_get("http://example.com/page", ctx, {}, 5)
        assert "OK" in result
        # Second call should hit cache
        assert cache_get_http("http://example.com/page", False, {}, ctx) is not None

    @resp_lib.activate
    @pytest.mark.parametrize("status", [429, 503])
    def test_retries_on_retriable_status(self, status):
        resp_lib.add(resp_lib.GET, "http://example.com/retry",
                     body="wait", status=status)
        resp_lib.add(resp_lib.GET, "http://example.com/retry",
                     body="OK", status=200)
        ctx = {"ssrf_protection": False}
        with patch("time.sleep"):
            result = guarded_http_get("http://example.com/retry", ctx, {}, 5, max_retries=2)
        assert result == "OK"

    @resp_lib.activate
    def test_redirect_to_private_ip_blocked(self):
        resp_lib.add(
            resp_lib.GET, "http://example.com/redir",
            status=302,
            headers={"Location": "http://192.168.1.1/secret"},
        )
        ctx: dict = {}
        with patch("scrape_byLLM.guard_fetch._resolve_to_ips",
                   side_effect=lambda h: ["192.168.1.1"] if h == "192.168.1.1" else ["93.184.216.34"]):
            with pytest.raises(SSRFError):
                guarded_http_get("http://example.com/redir", ctx, {}, 5)

    @resp_lib.activate
    def test_fetch_misses_counter_incremented(self, tmp_path):
        resp_lib.add(resp_lib.GET, "http://example.com/counter",
                     body="data", status=200)
        ctx = {
            "ssrf_protection": False,
            "cache": "readwrite",
            "cache_dir": str(tmp_path),
        }
        guarded_http_get("http://example.com/counter", ctx, {}, 5)
        assert ctx.get("fetch_misses", 0) == 1
