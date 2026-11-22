#!/usr/bin/env python3
"""Checks that every string used with L("…") has a German translation in the string catalog.

Usage: scripts/check-l10n.py [--list]
Exits with status 1 if a key is missing or the catalog contains keys that are no longer used.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
sources = root / "KimaiTimer"
catalog_path = sources / "Localizable.xcstrings"
pattern = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')


def unescape(text):
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


used = set()
for path in sorted(sources.rglob("*.swift")):
    used.update(unescape(match) for match in pattern.findall(path.read_text(encoding="utf-8")))

if "--list" in sys.argv:
    print("\n".join(sorted(used)))
    sys.exit(0)

catalog = json.loads(catalog_path.read_text(encoding="utf-8"))["strings"]
translated = {
    key for key, entry in catalog.items()
    if entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value")
}
missing = sorted(used - translated)
unused = sorted(set(catalog) - used)
for key in missing:
    print(f"missing German translation: {key!r}")
for key in unused:
    print(f"unused catalog entry: {key!r}")
print(f"{len(used)} strings in code, {len(translated)} translated, {len(missing)} missing, {len(unused)} unused")
sys.exit(1 if missing or unused else 0)
