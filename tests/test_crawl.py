from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
import responses as resp_lib

from scrape_byLLM.crawl import _extract_links, _find_next_page, crawl
from scrape_byLLM.guard_fetch import SSRFError

_SSRF_OFF = {"ssrf_protection": False, "respect_robots": False}

EMAIL_PAGE = "Contact: user@example.com"
LINK_PAGE = '<a href="/page2">Page 2</a><a href="/page3">Page 3</a>'

class TestExtractLinks:
    def test_extracts_absolute_href(self):
        html = '<a href="https://example.com/foo">link</a>'
        links = _extract_links(html, "https://example.com")
        assert "https://example.com/foo" in links

    def test_resolves_relative_href(self):
        html = '<a href="/bar">link</a>'
        links = _extract_links(html, "https://example.com")
        assert "https://example.com/bar" in links

    def test_skips_mailto(self):
        html = '<a href="mailto:test@example.com">mail</a>'
        links = _extract_links(html, "https://example.com")
        assert not any(l.startswith("mailto:") for l in links)

    def test_empty_html_returns_empty(self):
        assert _extract_links("", "https://example.com") == []

    def test_multiple_links(self):
        html = (
            '<a href="/a">A</a>'
            '<a href="/b">B</a>'
            '<a href="https://other.com/c">C</a>'
        )
        links = _extract_links(html, "https://example.com")
        assert len(links) == 3

class TestFindNextPage:
    def test_link_rel_next(self):
        html = '<link rel="next" href="/page2">'
        result = _find_next_page(html, "https://example.com/page1")
        assert result == "https://example.com/page2"

    def test_a_rel_next(self):
        html = '<a rel="next" href="/p2">Next</a>'
        result = _find_next_page(html, "https://example.com/")
        assert result == "https://example.com/p2"

    def test_aria_label_next(self):
        html = '<a aria-label="Next" href="/p3">→</a>'
        result = _find_next_page(html, "https://example.com/")
        assert result == "https://example.com/p3"

    def test_class_next(self):
        html = '<a class="next" href="/p4">Next</a>'
        result = _find_next_page(html, "https://example.com/")
        assert result == "https://example.com/p4"

    def test_no_next_returns_empty(self):
        result = _find_next_page("<html><body>nothing</body></html>", "https://example.com")
        assert result == ""

class TestCrawl:
    @resp_lib.activate
    def test_single_page_extracts_emails(self):
        resp_lib.add(resp_lib.GET, "https://example.com/",
                     body=EMAIL_PAGE, status=200)
        result = crawl(
            seed="https://example.com/",
            query="",
            pattern="emails",
            max_depth=0,
            max_pages=1,
            opts=dict(_SSRF_OFF),
        )
        assert result["pages_crawled"] == 1
        snippets = [sn for r in result["results"] for sn in r.get("snippets", [])]
        assert any("user@example.com" in s for s in snippets)

    @resp_lib.activate
    def test_same_domain_filter_excludes_external(self):
        resp_lib.add(
            resp_lib.GET, "https://example.com/",
            body='<a href="https://other.com/x">ext</a><a href="/internal">int</a>',
            status=200,
        )
        resp_lib.add(
            resp_lib.GET, "https://example.com/internal",
            body=EMAIL_PAGE, status=200,
        )
        result = crawl(
            seed="https://example.com/",
            query="",
            pattern="emails",
            max_depth=1,
            max_pages=5,
            same_domain=True,
            opts=dict(_SSRF_OFF),
        )
        sources = [r["source"] for r in result["results"]]
        assert not any("other.com" in s for s in sources)
        assert any("example.com" in s for s in sources)

    def test_max_pages_respected(self):
        fetch_count = [0]

        def fake_fetch(url, *args, **kwargs):
            fetch_count[0] += 1
            return f'<a href="/p{fetch_count[0]}a">a</a><a href="/p{fetch_count[0]}b">b</a>'

        with patch("scrape_byLLM.crawl.fetch_one", side_effect=fake_fetch), \
             patch("scrape_byLLM.crawl.validate_url_ssrf"):
            result = crawl(
                seed="https://example.com/",
                query="",
                pattern="links",
                max_depth=5,
                max_pages=3,
                same_domain=False,
                opts=dict(_SSRF_OFF),
            )
        assert result["pages_crawled"] <= 3

    def test_no_revisit_of_same_url(self):
        fetched: list[str] = []

        def fake_fetch(url, *args, **kwargs):
            fetched.append(url)
            return '<a href="/">home</a>'

        with patch("scrape_byLLM.crawl.fetch_one", side_effect=fake_fetch), \
             patch("scrape_byLLM.crawl.validate_url_ssrf"):
            crawl(
                seed="https://example.com/",
                query="",
                pattern="links",
                max_depth=3,
                max_pages=10,
                same_domain=True,
                opts=dict(_SSRF_OFF),
            )
        # The seed should be fetched exactly once
        assert fetched.count("https://example.com/") == 1

    def test_result_has_expected_keys(self):
        with patch("scrape_byLLM.crawl.fetch_one", return_value=EMAIL_PAGE), \
             patch("scrape_byLLM.crawl.validate_url_ssrf"):
            result = crawl(
                seed="https://example.com/",
                query="",
                pattern="emails",
                max_depth=0,
                max_pages=1,
                opts=dict(_SSRF_OFF),
            )
        for key in ("pattern", "query", "page_count", "pages_crawled",
                    "results", "fetch_hits", "fetch_misses", "blocked_urls"):
            assert key in result, f"missing key: {key}"

    def test_ssrf_blocked_link_not_enqueued(self):
        def fake_fetch(url, *args, **kwargs):
            return '<a href="http://192.168.1.1/evil">evil</a><a href="/safe">safe</a>'

        def fake_ssrf(url, ctx):
            if "192.168" in url:
                ctx["blocked_urls"] = ctx.get("blocked_urls", 0) + 1
                raise SSRFError("blocked")

        opts = dict(_SSRF_OFF)
        opts["ssrf_protection"] = True

        with patch("scrape_byLLM.crawl.fetch_one", side_effect=fake_fetch), \
             patch("scrape_byLLM.crawl.validate_url_ssrf", side_effect=fake_ssrf):
            result = crawl(
                seed="https://example.com/",
                query="",
                pattern="links",
                max_depth=1,
                max_pages=5,
                same_domain=False,
                opts=opts,
            )
        assert result["blocked_urls"] >= 1

    @resp_lib.activate
    def test_paginate_follows_next_link(self):
        resp_lib.add(
            resp_lib.GET, "https://example.com/p1",
            body='<p>item1</p><a rel="next" href="/p2">Next</a>',
            status=200,
        )
        resp_lib.add(
            resp_lib.GET, "https://example.com/p2",
            body="<p>item2</p>",
            status=200,
        )
        result = crawl(
            seed="https://example.com/p1",
            query="",
            pattern="text",
            max_depth=1,
            max_pages=5,
            paginate=True,
            same_domain=True,
            opts=dict(_SSRF_OFF),
        )
        sources = [r["source"] for r in result["results"]]
        assert any("p1" in s for s in sources)
        assert any("p2" in s for s in sources)

    @resp_lib.activate
    def test_follow_pattern_filter(self):
        resp_lib.add(
            resp_lib.GET, "https://example.com/",
            body='<a href="/blog/post">blog</a><a href="/shop/item">shop</a>',
            status=200,
        )
        resp_lib.add(
            resp_lib.GET, "https://example.com/blog/post",
            body="blog content", status=200,
        )
        result = crawl(
            seed="https://example.com/",
            query="",
            pattern="text",
            max_depth=1,
            max_pages=5,
            follow_pattern=r"/blog/",
            same_domain=True,
            opts=dict(_SSRF_OFF),
        )
        sources = [r["source"] for r in result["results"]]
        assert not any("/shop/" in s for s in sources)

    @resp_lib.activate
    def test_exclude_pattern_filter(self):
        resp_lib.add(
            resp_lib.GET, "https://example.com/",
            body='<a href="/keep">keep</a><a href="/skip/this">skip</a>',
            status=200,
        )
        resp_lib.add(
            resp_lib.GET, "https://example.com/keep",
            body="kept page", status=200,
        )
        result = crawl(
            seed="https://example.com/",
            query="",
            pattern="text",
            max_depth=1,
            max_pages=5,
            exclude_pattern=r"/skip/",
            same_domain=True,
            opts=dict(_SSRF_OFF),
        )
        sources = [r["source"] for r in result["results"]]
        assert not any("/skip/" in s for s in sources)
