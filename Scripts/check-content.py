#!/usr/bin/env python3
"""Validate owned text and shipped text resources without inspecting private media."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OMIT = {".git", "build", ".build", ".swiftpm", "xcuserdata", "__pycache__"}
SUFFIXES = {".swift", ".md", ".txt", ".json", ".plist", ".entitlements", ".xcconfig", ".pbxproj", ".xcscheme", ".sh", ".py", ".yml", ".yaml", ".strings"}
TOOLS = "(?:chat" + "gpt|open" + "ai|co" + "dex)"
ATTRIBUTION = re.compile(r"(?:built|made|generated|created|powered)\s+(?:by|with|using)\s+" + TOOLS, re.I)
errors = []

def check(path, text):
    if chr(0x2014) in text:
        errors.append(f"Disallowed punctuation: {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path.name}")
    if ATTRIBUTION.search(text):
        errors.append(f"Disallowed attribution: {path.name}")

for path in ROOT.rglob("*"):
    if any(part in OMIT for part in path.relative_to(ROOT).parts) or not path.is_file():
        continue
    if path.suffix in SUFFIXES or path.name == ".gitignore":
        check(path, path.read_text())
for argument in sys.argv[1:]:
    supplied = Path(argument)
    paths = supplied.rglob("*") if supplied.is_dir() else [supplied]
    for path in paths:
        if not path.is_file():
            continue
        if path.suffix == ".plist":
            check(path, subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", str(path)]).decode())
        elif path.suffix in SUFFIXES:
            check(path, path.read_text())
        elif path.name == "Transcriber":
            check(path, subprocess.check_output(["strings", "-a", str(path)]).decode(errors="replace"))
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Content checks passed")
