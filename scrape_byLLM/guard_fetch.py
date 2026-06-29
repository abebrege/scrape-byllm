from __future__ import annotations

import hashlib
import ipaddress
import json
import logging
import random
import socket
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse, urlunparse, urljoin

import requests
from requests.exceptions import RequestException

log = logging.getLogger(__name__)

_PRIVATE_NETS_V4 = [
    ipaddress.IPv4Network("127.0.0.0/8"),
    ipaddress.IPv4Network("10.0.0.0/8"),
    ipaddress.IPv4Network("172.16.0.0/12"),
    ipaddress.IPv4Network("192.168.0.0/16"),
    ipaddress.IPv4Network("169.254.0.0/16"),
    ipaddress.IPv4Network("100.64.0.0/10"),    # (RFC 6598)
    ipaddress.IPv4Network("0.0.0.0/8"),
]

_PRIVATE_NETS_V6 = [
    ipaddress.IPv6Network("::1/128"),           # loopback
    ipaddress.IPv6Network("fe80::/10"),         # link-local
    ipaddress.IPv6Network("fc00::/7"),          # unique-local (ULA)
]

_ALLOWED_SCHEMES = frozenset({"http", "https"})
_RETRYABLE = frozenset({429, 502, 503, 504})

class SSRFError(Exception):
    """Raised when a URL is blocked by SSRF protection."""

def _is_private_ip(ip_str: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip_str)
    except ValueError:
        return True  # unparseable → block
    if isinstance(addr, ipaddress.IPv4Address):
        return any(addr in net for net in _PRIVATE_NETS_V4)
    return any(addr in net for net in _PRIVATE_NETS_V6)

def _resolve_to_ips(hostname: str) -> list[str]:
    try:
        infos = socket.getaddrinfo(hostname, None, proto=socket.IPPROTO_TCP)
        return [info[4][0] for info in infos]
    except socket.gaierror:
        return []

def canonicalize_url(url: str) -> str:
    """
    Normalize for visited-set dedup:
    - lowercase scheme + host
    - strip default ports (80/http, 443/https)
    - drop fragment
    Conservative: preserves query string (params can be significant).
    """
    try:
        p = urlparse(url)
        scheme = p.scheme.lower()
        host = (p.hostname or "").lower()
        port = p.port
        if (scheme == "http" and port == 80) or (scheme == "https" and port == 443):
            netloc = host
        elif port:
            netloc = f"{host}:{port}"
        else:
            netloc = host
        path = p.path or "/"
        return urlunparse((scheme, netloc, path, p.params, p.query, ""))
    except Exception:
        return url

def validate_url_ssrf(url: str, ctx: dict[str, Any]) -> None:
    """
    Validate url against SSRF rules. Raises SSRFError on violation.
    Increments ctx["blocked_urls"] before raising.

    ctx keys:
      ssrf_protection  bool  default True
      allow_private_ips bool default False
      allowed_hosts    list[str] bypass IP check for these hosts
      blocked_hosts    list[str] always block these hosts
    """
    if not ctx.get("ssrf_protection", True):
        return

    parsed = urlparse(url)

    if parsed.scheme not in _ALLOWED_SCHEMES:
        _bump(ctx, "blocked_urls")
        raise SSRFError(f"Scheme not allowed: {parsed.scheme!r} in {url!r}")

    hostname = parsed.hostname or ""
    if not hostname:
        _bump(ctx, "blocked_urls")
        raise SSRFError(f"Missing hostname in {url!r}")

    blocked = ctx.get("blocked_hosts") or []
    if hostname in blocked:
        _bump(ctx, "blocked_urls")
        raise SSRFError(f"Host explicitly blocked: {hostname!r}")

    allowed = ctx.get("allowed_hosts") or []
    if hostname in allowed:
        return

    allow_private = ctx.get("allow_private_ips", False)
    if allow_private:
        return

    ips = _resolve_to_ips(hostname)
    if not ips:
        _bump(ctx, "blocked_urls")
        raise SSRFError(f"Could not resolve hostname: {hostname!r}")

    for ip in ips:
        if _is_private_ip(ip):
            _bump(ctx, "blocked_urls")
            raise SSRFError(
                f"URL {url!r} resolves to private/internal IP {ip!r}"
            )

def _http_cache_key(url: str, render: bool, headers: dict[str, str]) -> str:
    sig_headers = {
        k.lower(): v
        for k, v in headers.items()
        if k.lower() in {"accept", "accept-language", "accept-encoding"}
    }
    payload = json.dumps(
        {"url": canonicalize_url(url), "render": render, "headers": sig_headers},
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def _cache_path(key: str, cache_dir: str, sub: str) -> Path:
    return Path(cache_dir) / sub / key[:2] / key

def cache_get_http(url: str, render: bool, headers: dict[str, str],
                   ctx: dict[str, Any]) -> str | None:
    mode = ctx.get("cache", "off")
    if mode not in ("readwrite", "readonly"):
        return None
    cache_dir = str(ctx.get("cache_dir", ".scrape_cache"))
    key = _http_cache_key(url, render, headers)
    path = _cache_path(key, cache_dir, "http")
    if not path.exists():
        return None
    ttl = ctx.get("cache_ttl") or 0
    if ttl and (time.time() - path.stat().st_mtime) > ttl:
        return None
    try:
        body = path.read_text(encoding="utf-8")
        _bump(ctx, "fetch_hits")
        return body
    except Exception:
        return None

def cache_put_http(url: str, render: bool, headers: dict[str, str],
                   body: str, ctx: dict[str, Any]) -> None:
    mode = ctx.get("cache", "off")
    if mode not in ("readwrite", "refresh"):
        return
    cache_dir = str(ctx.get("cache_dir", ".scrape_cache"))
    key = _http_cache_key(url, render, headers)
    path = _cache_path(key, cache_dir, "http")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
    except Exception as exc:
        log.warning("cache_put_http failed: %s", exc)

# Module-level mutable state uses list wrappers (mirrors fetch.jac pattern)
_proxy_failures: dict[str, int] = {}
_proxy_rr_index: list[int] = [0]

def reset_proxy_state() -> None:
    """Reset proxy failure counts and round-robin index. Call between tests."""
    _proxy_failures.clear()
    _proxy_rr_index[0] = 0

def record_proxy_failure(proxy: str, ctx: dict[str, Any]) -> None:
    _proxy_failures[proxy] = _proxy_failures.get(proxy, 0) + 1
    max_f = int(ctx.get("proxy_max_failures", 3))
    if _proxy_failures[proxy] >= max_f:
        log.warning("Proxy dropped after %d failures: %s", max_f, proxy)

def _active_proxies(ctx: dict[str, Any]) -> list[str]:
    raw = ctx.get("proxies") or []
    proxies: list[str] = [raw] if isinstance(raw, str) else list(raw)
    max_f = int(ctx.get("proxy_max_failures", 3))
    return [p for p in proxies if _proxy_failures.get(p, 0) < max_f]

def get_proxy(url: str, ctx: dict[str, Any]) -> str | None:
    active = _active_proxies(ctx)
    if not active:
        return None
    rotation = ctx.get("proxy_rotation", "round_robin")
    if rotation == "random":
        return random.choice(active)
    if rotation == "sticky":
        domain = urlparse(url).hostname or url
        return active[abs(hash(domain)) % len(active)]
    # round_robin
    idx = _proxy_rr_index[0] % len(active)
    _proxy_rr_index[0] += 1
    return active[idx]

def _proxy_dict(proxy_url: str | None) -> dict[str, str] | None:
    return {"http": proxy_url, "https": proxy_url} if proxy_url else None

def guarded_http_get(
    url: str,
    ctx: dict[str, Any],
    headers: dict[str, str],
    timeout: int,
    max_retries: int = 3,
) -> str:
    """
    Full pipeline: SSRF validate → cache read → proxy select → fetch with
    manual redirect-following (each hop re-validated) → cache write.

    Raises: SSRFError, RequestException, RuntimeError (readonly cache miss).
    """
    cached = cache_get_http(url, False, headers, ctx)
    if cached is not None:
        log.debug("HTTP cache hit: %s", url)
        return cached

    _bump(ctx, "fetch_misses")

    validate_url_ssrf(url, ctx)

    mode = ctx.get("cache", "off")
    if mode == "readonly":
        raise RuntimeError(f"Cache miss in readonly mode for {url!r}")

    proxy = get_proxy(url, ctx)
    delay = 1.0
    last_exc: RequestException | None = None

    for attempt in range(max_retries):
        try:
            proxy_dict = _proxy_dict(proxy)
            resp = requests.get(
                url,
                timeout=timeout,
                headers=headers,
                allow_redirects=False,
                proxies=proxy_dict,
            )

            hops = 0
            while resp.is_redirect and hops < 10:
                location = resp.headers.get("Location", "")
                if not location:
                    break
                next_url = urljoin(url, location)
                validate_url_ssrf(next_url, ctx)
                resp = requests.get(
                    next_url,
                    timeout=timeout,
                    headers=headers,
                    allow_redirects=False,
                    proxies=proxy_dict,
                )
                url = next_url
                hops += 1

            if resp.status_code in _RETRYABLE and attempt < max_retries - 1:
                time.sleep(delay)
                delay *= 2.0
                continue

            resp.raise_for_status()
            body = resp.text
            cache_put_http(url, False, headers, body, ctx)
            return body

        except SSRFError:
            raise

        except RequestException as exc:
            last_exc = exc
            if proxy:
                record_proxy_failure(proxy, ctx)
                new_proxy = get_proxy(url, ctx)
                if new_proxy and new_proxy != proxy:
                    proxy = new_proxy
            if attempt < max_retries - 1:
                time.sleep(delay)
                delay *= 2.0

    if last_exc is not None:
        raise last_exc
    return ""


def guarded_selenium_get(
    url: str,
    driver: Any,
    ctx: dict[str, Any],
    max_chars: int,
) -> str:
    """SSRF-validated, cached Selenium page load."""
    cached = cache_get_http(url, True, {}, ctx)
    if cached is not None:
        log.debug("Selenium cache hit: %s", url)
        return cached

    _bump(ctx, "fetch_misses")
    validate_url_ssrf(url, ctx)

    mode = ctx.get("cache", "off")
    if mode == "readonly":
        raise RuntimeError(f"Cache miss in readonly mode (render=True) for {url!r}")

    driver.get(url)
    clean_js = (
        "for (const el of document.querySelectorAll('script, style, noscript')) "
        "{ el.remove(); } return document.documentElement.outerHTML;"
    )
    html = str(driver.execute_script(clean_js))
    if len(html) > max_chars:
        html = html[:max_chars]

    cache_put_http(url, True, {}, html, ctx)
    return html

def _bump(ctx: dict[str, Any], key: str) -> None:
    ctx[key] = int(ctx.get(key, 0)) + 1
