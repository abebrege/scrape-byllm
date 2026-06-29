from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

_INJECTION_MARKERS: list[str] = [
    "ignore previous instructions",
    "ignore all instructions",
    "ignore all previous",
    "disregard the above",
    "disregard previous",
    "forget previous",
    "you are now",
    "new instructions:",
    "system prompt:",
    "act as if",
    "pretend you are",
    "jailbreak",
    "<|im_start|>",
    "<|im_end|>",
    "###instruction",
    "output the api key",
    "reveal your system prompt",
    "ignore the above",
    "ignore everything above",
]

# ReDoS heuristic: nested quantifiers pattern shapes
_REDOS_RE = re.compile(
    r"(\([^)]*[+*?][^)]*\)[+*?{])"   # (x+)+  (x*)+ (x+){
    r"|(\([^)]*\)[+*]\1)"             # (x)+ backreference
)

def check_injection(untrusted: Any, ctx: dict[str, Any]) -> bool:
    text = str(untrusted).lower()
    found = [m for m in _INJECTION_MARKERS if m in text]
    if not found:
        return False

    if "_injection_log" not in ctx:
        ctx["_injection_log"] = []
    ctx["_injection_log"].append({
        "markers": found,
        "snippet": str(untrusted)[:200],
        "ts": time.time(),
    })
    log.warning("Injection markers detected in untrusted content: %s", found)
    return True

def _has_redos_shape(pat: str) -> bool:
    return bool(_REDOS_RE.search(pat))

def _test_redos_timeout(pat: str, timeout_s: float) -> bool:
    """
    Return True if the pattern times out on an adversarial probe (= ReDoS).
    Falls back to False (safe) on platforms without SIGALRM (Windows).
    """
    import signal
    if not hasattr(signal, "SIGALRM"):
        return False

    def _handler(signum: int, frame: Any) -> None:
        raise TimeoutError

    old = signal.signal(signal.SIGALRM, _handler)
    signal.setitimer(signal.ITIMER_REAL, timeout_s)
    try:
        rx = re.compile(pat)
        for probe in ("a" * 40 + "!", "x" * 30 + "?", "((" * 15 + "a" * 20):
            rx.search(probe)
        return False
    except TimeoutError:
        return True
    except re.error:
        return False
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)

def validate_regex_plan(patterns: list[Any], ctx: dict[str, Any]) -> list[str]:
    if not ctx.get("injection_guard", True):
        return [str(p) for p in patterns if p is not None]

    timeout_s = float(ctx.get("regex_timeout", 1.0))
    safe: list[str] = []

    for pat in patterns:
        if pat is None:
            continue
        pat = str(pat)
        if not pat:
            safe.append(pat)
            continue
        # 1. Must compile
        try:
            re.compile(pat)
        except re.error as exc:
            log.warning("Dropping invalid regex %r: %s", pat, exc)
            continue
        # 2. Heuristic: nested quantifiers
        if _has_redos_shape(pat):
            log.warning("Dropping potential ReDoS regex (nested quantifiers): %r", pat)
            continue
        # 3. Signal-based timeout on adversarial probe
        if _test_redos_timeout(pat, timeout_s):
            log.warning("Dropping regex that timed out on adversarial probe: %r", pat)
            continue
        safe.append(pat)

    return safe

def validate_synthesis(data: dict[str, Any], ctx: dict[str, Any]) -> dict[str, Any]:
    """
    Enforce expected shape: {summary: str, items: list[str], notes: str}.
    Fills missing / wrong-typed keys with safe defaults.
    """
    summary = data.get("summary")
    items = data.get("items")
    notes = data.get("notes")

    if not isinstance(items, list):
        log.warning("validate_synthesis: 'items' was not a list, coercing to []")
        items = []

    return {
        "summary": str(summary) if summary is not None else "",
        "items": [str(i) for i in items],
        "notes": str(notes) if notes is not None else "",
    }

def llm_cache_key(
    model: str,
    call_type: str,
    query: str,
    pattern: str,
    html_sample: str,
) -> str:
    payload = json.dumps({
        "model": model,
        "type": call_type,
        "query": query,
        "pattern": pattern,
        "html_sample": html_sample[:500],
    }, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()

def _llm_cache_path(key: str, cache_dir: str) -> Path:
    return Path(cache_dir) / "llm" / key[:2] / key

def cache_get_llm(key: str, ctx: dict[str, Any]) -> dict[str, Any] | None:
    if not ctx.get("cache_llm", True):
        return None
    mode = ctx.get("cache", "off")
    if mode not in ("readwrite", "readonly"):
        return None
    cache_dir = str(ctx.get("cache_dir", ".scrape_cache"))
    path = _llm_cache_path(key, cache_dir)
    if not path.exists():
        return None
    ttl = ctx.get("cache_ttl") or 0
    if ttl and (time.time() - path.stat().st_mtime) > ttl:
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

def cache_put_llm(key: str, data: dict[str, Any], ctx: dict[str, Any]) -> None:
    if not ctx.get("cache_llm", True):
        return
    mode = ctx.get("cache", "off")
    if mode not in ("readwrite", "refresh"):
        return
    cache_dir = str(ctx.get("cache_dir", ".scrape_cache"))
    path = _llm_cache_path(key, cache_dir)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
    except Exception as exc:
        log.warning("cache_put_llm failed: %s", exc)
