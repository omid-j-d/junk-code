#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
collect_sites_inline.py
Collects domain lists from multiple online sources (plain text or HTML),
deduplicates, normalizes, and exports multiple blocking formats.

Outputs:
  - domains.txt        -> clean list of domains
  - hosts-block.txt    -> hosts-style entries (127.0.0.1 domain)
  - adblock.txt        -> adblock filter rules (||domain^)

Requirements:
    pip install requests beautifulsoup4 tldextract
"""

import re
import sys
import time
from typing import List, Set
from urllib.parse import urlparse
import requests

# Optional modules
try:
    import tldextract
    HAVE_TLDEX = True
except Exception:
    HAVE_TLDEX = False

try:
    from bs4 import BeautifulSoup
    HAVE_BS4 = True
except Exception:
    HAVE_BS4 = False

# -------------------------------
# ✏️ Add your source list here:
DEFAULT_SOURCES = [
    # Example sources (replace or extend these):
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
    "https://big.oisd.nl",
    "https://blocklistproject.github.io/Lists/ads.txt",
    "https://blocklistproject.github.io/Lists/malware.txt",
    "https://blocklistproject.github.io/Lists/ransomware.txt",
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt",
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt"
    # Add more URLs below:
    # "https://example.com/list1.txt",
    # "https://another-source.net/domains.html",
]
# -------------------------------

HEADERS = {"User-Agent": "site-collector/1.0 (+https://example)"}
TIMEOUT = 20

URL_REGEX = re.compile(r'(https?://[^\s"<>\]\)]+)', re.IGNORECASE)
DOMAIN_LIKE_REGEX = re.compile(
    r'\b(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\b', re.IGNORECASE
)
HOSTS_LINE_RE = re.compile(r'^(?:\d{1,3}(?:\.\d{1,3}){3}|\[::1\])\s+([^\s#]+)', re.IGNORECASE)
ADBLOCK_DOMAIN_RE = re.compile(r'^\|\|([^\^\/\s]+)\^?')

def fetch_text(url: str, tries: int = 2) -> str:
    last_exc = None
    for attempt in range(1, tries + 1):
        try:
            r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
            r.raise_for_status()
            r.encoding = r.apparent_encoding or 'utf-8'
            return r.text
        except Exception as e:
            last_exc = e
            time.sleep(1)
    print(f"[!] Failed to fetch {url}: {last_exc}", file=sys.stderr)
    return ""

def looks_like_ip(s: str) -> bool:
    import ipaddress
    try:
        ipaddress.ip_address(s)
        return True
    except Exception:
        return False

def normalize_domain(domain: str) -> str:
    domain = domain.strip().lower().strip('.')
    if HAVE_TLDEX:
        ext = tldextract.extract(domain)
        if ext.suffix == "":
            return domain
        return domain
    return domain

def extract_domains_from_text(text: str) -> Set[str]:
    results: Set[str] = set()
    for m in HOSTS_LINE_RE.finditer(text):
        d = m.group(1).strip()
        if d:
            results.add(normalize_domain(d))
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("!") or line.startswith("#"):
            continue
        m = ADBLOCK_DOMAIN_RE.match(line)
        if m:
            results.add(normalize_domain(m.group(1)))
            continue
        if re.fullmatch(r"[A-Za-z0-9\.\-]+\.[A-Za-z]{2,63}", line):
            results.add(normalize_domain(line))
    for m in URL_REGEX.finditer(text):
        url = m.group(1)
        try:
            host = urlparse(url).hostname
            if host:
                results.add(normalize_domain(host))
        except Exception:
            pass
    for m in DOMAIN_LIKE_REGEX.finditer(text):
        d = m.group(0)
        results.add(normalize_domain(d))
    return {d for d in results if not looks_like_ip(d)}

def collect_from_sources(sources: List[str]) -> Set[str]:
    all_domains: Set[str] = set()
    for src in sources:
        print(f"[+] Fetching: {src}")
        txt = fetch_text(src)
        if not txt:
            print("    -> Failed or empty.", file=sys.stderr)
            continue
        domains: Set[str] = set()
        if HAVE_BS4 and ('<html' in txt.lower() or '<a ' in txt.lower()):
            try:
                soup = BeautifulSoup(txt, "html.parser")
                for a in soup.find_all('a', href=True):
                    href = a['href'].strip()
                    if href.startswith('http'):
                        host = urlparse(href).hostname
                        if host:
                            domains.add(normalize_domain(host))
                domains.update(extract_domains_from_text(soup.get_text(separator="\n")))
            except Exception:
                domains.update(extract_domains_from_text(txt))
        else:
            domains.update(extract_domains_from_text(txt))
        print(f"    -> Extracted {len(domains)} domains")
        all_domains.update(domains)
    return all_domains

def write_outputs(domains: Set[str], prefix="adblock"):
    domains_sorted = sorted(domains)
    with open(f"{prefix}_domains.txt", "w", encoding="utf-8") as f1, \
         open(f"{prefix}_hosts_block.txt", "w", encoding="utf-8") as f2, \
         open(f"{prefix}_adblock.txt", "w", encoding="utf-8") as f3:
        for d in domains_sorted:
            f1.write(d + "\n")
            f2.write(f"127.0.0.1 {d}\n")
            f3.write(f"||{d}^\n")
    print(f"[+] Wrote {len(domains_sorted)} domains to {prefix}_domains.txt")
    print(f"[+] Wrote hosts-format file {prefix}_hosts_block.txt")
    print(f"[+] Wrote adblock list {prefix}_adblock.txt")

def main():
    if not DEFAULT_SOURCES:
        print("[!] No sources configured. Edit DEFAULT_SOURCES list in script.", file=sys.stderr)
        sys.exit(1)

    print("[*] Collecting domain lists...")
    domains = collect_from_sources(DEFAULT_SOURCES)
    if not domains:
        print("[!] No domains extracted.", file=sys.stderr)
        sys.exit(1)
    write_outputs(domains)
    print("[*] Done.")

if __name__ == "__main__":
    main()
