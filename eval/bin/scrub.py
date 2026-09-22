#!/usr/bin/env python3
"""Redact operator identity from committed eval artifacts.

Two entry points, one implementation: analyze.py imports redact() for the
strings it embeds in result.json, and run-eval.sh runs this as a CLI over the
captured workdir once analysis has finished.

Three things leak. The home directory and the hostname arrive via
cf-agent --show-evaluated-vars, which dumps every sys.* variable. The operator's
email arrives a stranger way: Claude Code injects a userEmail block into the
context of every run, and the model volunteers it as a contact address in
generated policy. That one is not hypothetical -- it happened.

Email handling is deliberately narrow. A blanket "replace every address" rule
also destroys the fictional examples the skill teaches with (help@acme.com,
ops@globex.com), which corrupts the artifact it was meant to protect. So an
address is kept when it appears in the inputs the model was given (allowlist
files) or sits at a domain reserved for documentation. Anything else is an
address the model produced from its own context, which is where the operator's
identity lives -- those are replaced, and every replacement is logged.
"""

import os
import re
import socket
import sys
from pathlib import Path

_HOME = os.path.expanduser("~")
_HOST = socket.gethostname().split(".")[0]

_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
# RFC 2606/6761 reserve these, plus the stock fictional companies.
_SAFE_DOMAINS = ("example.com", "example.org", "example.net", "example.edu",
                 "acme.com", "globex.com", "localhost", ".invalid", ".test",
                 ".local", ".localhost")
_PLACEHOLDER = "admin@example.com"

_ALLOWED = set()
_REDACTED = set()


def allow_from(*paths):
    """Harvest addresses out of the model's inputs; those are example content."""
    for p in paths:
        p = Path(p)
        if not p.is_file():
            continue
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        _ALLOWED.update(m.group(0).lower() for m in _EMAIL_RE.finditer(text))
    return _ALLOWED


def _one_email(m):
    addr = m.group(0)
    low = addr.lower()
    if low in _ALLOWED or low.rsplit("@", 1)[1].endswith(_SAFE_DOMAINS):
        return addr
    _REDACTED.add(low)
    return _PLACEHOLDER


def redact(text):
    if not text:
        return text
    if _HOME and _HOME != "/":
        text = text.replace(_HOME, "~")
    if _HOST and len(_HOST) > 3:
        text = text.replace(_HOST, "<host>")
    return _EMAIL_RE.sub(_one_email, text)


def scrub_file(path):
    """Rewrite path in place if redaction changes it. Returns True if changed."""
    try:
        raw = path.read_bytes()
    except OSError:
        return False
    if b"\0" in raw:  # binary
        return False
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    cleaned = redact(text)
    if cleaned == text:
        return False
    path.write_text(cleaned, encoding="utf-8")
    return True


def scrub_tree(root):
    root = Path(root)
    if not root.exists():
        return []
    files = [root] if root.is_file() else sorted(p for p in root.rglob("*") if p.is_file())
    return [p for p in files if scrub_file(p)]


if __name__ == "__main__":
    args = sys.argv[1:]
    allow, targets = [], []
    while args:
        a = args.pop(0)
        if a == "--allow-from":
            if not args:
                sys.exit("scrub.py: --allow-from needs a path")
            allow.append(args.pop(0))
        else:
            targets.append(a)
    if not targets:
        sys.exit("usage: scrub.py [--allow-from FILE]... <path> [<path>...]")
    allow_from(*allow)
    changed = []
    for t in targets:
        changed += scrub_tree(t)
    for p in changed:
        print("scrub: redacted %s" % p, file=sys.stderr)
    if _REDACTED:
        print("scrub: addresses replaced with %s: %s"
              % (_PLACEHOLDER, ", ".join(sorted(_REDACTED))), file=sys.stderr)
