#!/usr/bin/env python3
"""Fingerprint implementation inputs, excluding validation results and private settings."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
digest = hashlib.sha256()
paths = [root / "Package.swift"]
for folder in ("App", "Config", "Sources", "Tests", "Tools", "Scripts", "Transcriber.xcodeproj", ".github"):
    paths += [p for p in (root / folder).rglob("*") if p.is_file() and not any(x in p.parts for x in ("xcuserdata", "__pycache__")) and p.name != "Local.xcconfig"]
for path in sorted(paths):
    digest.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes() + b"\0")
print(digest.hexdigest())
