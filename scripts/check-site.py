#!/usr/bin/env python3
"""Validate the deployable static site without a package manager or network calls."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
PRODUCTION = "https://viniciuslidington.github.io/MacSnap/"
DOWNLOAD = "https://github.com/viniciuslidington/MacSnap/releases/latest/download/MacSnap.app.zip"


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.references = []
        self.metadata = {}
        self.h1s = 0
        self.downloads = 0
        self.language = None
        self.install_command = []
        self.in_install_code = False
        self.alternates = {}
        self.language_links = []
        self.runtime = []
        self.in_runtime = False

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "html":
            self.language = attrs.get("lang")
        if tag == "h1":
            self.h1s += 1
        if tag == "code" and attrs.get("id") == "install-command":
            self.in_install_code = True
        if tag == "script" and attrs.get("id") == "site-copy":
            self.in_runtime = True
        if tag == "meta":
            self.metadata[attrs.get("property", attrs.get("name"))] = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.metadata["canonical"] = attrs.get("href")
        if tag == "link" and attrs.get("rel") == "alternate":
            self.alternates[attrs.get("hreflang")] = attrs.get("href")
        if tag == "a" and "data-language-link" in attrs:
            self.language_links.append(attrs)
        if tag == "img":
            assert "alt" in attrs, "Image without alt attribute"
            assert attrs.get("width") and attrs.get("height"), "Image without explicit dimensions"
        for attribute in ("href", "src"):
            if attribute in attrs:
                self.references.append(attrs[attribute])
                if attrs[attribute] == DOWNLOAD:
                    self.downloads += 1

    def handle_data(self, data):
        if self.in_install_code:
            self.install_command.append(data)
        if self.in_runtime:
            self.runtime.append(data)

    def handle_endtag(self, tag):
        if tag == "code":
            self.in_install_code = False
        if tag == "script":
            self.in_runtime = False


def local_file(reference, base=SITE):
    target = (base / unquote(urlsplit(reference).path)).resolve()
    assert target.is_relative_to(SITE.resolve()), f"Asset escapes site/: {reference}"
    if target.is_dir():
        target = target / "index.html"
    assert target.is_file(), f"Missing asset: {reference}"
    return target


def check_page(path, language, canonical, social_name):
    import json
    page = Page()
    page.feed(path.read_text(encoding="utf-8"))
    assert page.language == language
    assert page.h1s == 1, "Expected one primary heading"
    assert page.downloads >= 3, "Missing primary release download links"
    expected_command = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/viniciuslidington/MacSnap/main/install.sh)"'
    assert "".join(page.install_command) == expected_command, "Keep the copyable install command intact on one line"
    for reference in page.references:
        url = urlsplit(reference)
        if url.scheme:
            assert url.scheme == "https", f"Unsupported external scheme: {reference}"
            continue
        assert not reference.startswith("/"), f"Root path breaks /MacSnap/: {reference}"
        if url.path:
            local_file(reference, path.parent)
        elif url.fragment:
            assert unquote(url.fragment) in page.ids, f"Broken anchor: {reference}"

    assert page.metadata.get("canonical") == canonical
    assert page.metadata.get("og:url") == canonical
    assert page.metadata.get("og:locale") == ("en_US" if language == "en" else "pt_BR")
    assert page.alternates == {"en": PRODUCTION, "pt-BR": PRODUCTION + "pt/", "x-default": PRODUCTION}
    assert len(page.language_links) == 2
    assert {link["hreflang"] for link in page.language_links} == {"en", "pt-BR"}
    current = [link for link in page.language_links if link.get("aria-current") == "page"]
    assert len(current) == 1 and current[0]["hreflang"] == language
    for link in page.language_links:
        expected = SITE / ("pt/index.html" if link["hreflang"] == "pt-BR" else "index.html")
        assert local_file(link["href"], path.parent) == expected.resolve()
    runtime = json.loads("".join(page.runtime))
    assert all(runtime.get(key) for key in ("copySuccess", "copyFailure", "copied", "showLayouts", "hideLayouts", "layoutSelected", "splitValue"))
    assert page.metadata.get("og:type") == "website"
    assert page.metadata.get("twitter:card") == "summary_large_image"
    assert page.metadata.get("description"), "Missing search description"
    assert page.metadata.get("og:description"), "Missing social description"
    for key in ("og:image", "twitter:image"):
        assert page.metadata.get(key) == PRODUCTION + "assets/" + social_name
    social = SITE / "assets" / social_name
    data = social.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "Social preview must be a PNG"
    assert struct.unpack(">II", data[16:24]) == (1200, 630), "Social preview must be 1200 x 630"
    # Initial transfer excludes share cards and documentation.
    initial = [path, SITE / "styles.css", SITE / "script.js",
               SITE / "assets/icon-128.png", SITE / "assets/menu-native.png"]
    initial += list((SITE / "assets/fonts").glob("*.woff2"))
    initial_bytes = sum(path.stat().st_size for path in initial)
    assert initial_bytes <= 500_000, f"Initial asset budget exceeded: {initial_bytes:,} bytes"
    print(f"PASS: {language} HTML, links, language switch, runtime copy and share image; initial budget {initial_bytes:,}/500,000 bytes.")
    return page.ids


def main():
    subprocess.run([sys.executable, str(ROOT / "scripts/build-site-locales.py"), "--check"], check=True)
    english_ids = check_page(SITE / "index.html", "en", PRODUCTION, "social-preview.png")
    portuguese_ids = check_page(SITE / "pt/index.html", "pt-BR", PRODUCTION + "pt/", "social-preview-pt.png")
    assert english_ids == portuguese_ids, "Keep section anchors consistent when switching languages"
    for css in SITE.glob("*.css"):
        for reference in re.findall(r"url\(['\"]?([^)'\"]+)", css.read_text()):
            local_file(reference)
    sitemap = ET.parse(SITE / "sitemap.xml")
    assert {node.text for node in sitemap.findall(".//{*}loc")} == {PRODUCTION, PRODUCTION + "pt/"}
    assert list((SITE / "assets/fonts").glob("*OFL*")), "Keep font license notices"
    print("PASS: shared anchors, CSS assets, font licenses and bilingual sitemap.")


if __name__ == "__main__":
    main()
