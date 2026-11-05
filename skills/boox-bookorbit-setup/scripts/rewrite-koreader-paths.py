#!/usr/bin/env python3
"""Rewrite book paths in pulled KOReader state files after books were moved.

Usage: rewrite-koreader-paths.py WORKDIR OLD_PREFIX=NEW_PREFIX [OLD=NEW ...]
WORKDIR holds copies of settings.reader.lua, history.lua, settings/bookorbit_sync_state.lua,
settings/collection.lua and any *.sdr/metadata.*.lua. Run it ONLY while KOReader is force-stopped
and only on copies pulled with adb; push the files back afterwards. Keep the originals as backup.
Also drops duplicate keys in the "files" table of bookorbit_sync_state.lua.
"""
import os
import sys

workdir = sys.argv[1]
pairs = [a.split("=", 1) for a in sys.argv[2:]]
if not pairs:
    sys.exit(__doc__)

for root, _, files in os.walk(workdir):
    for name in files:
        if not name.endswith(".lua"):
            continue
        path = os.path.join(root, name)
        text = open(path, encoding="utf-8").read()
        new = text
        for old, rep in pairs:
            new = new.replace(old, rep)
        if name == "bookorbit_sync_state.lua":
            seen, out = set(), []
            for line in new.split("\n"):
                key = line.strip()
                if key.startswith('["/') and key in seen:
                    continue
                if key.startswith('["/'):
                    seen.add(key)
                out.append(line)
            new = "\n".join(out)
        if new != text:
            open(path, "w", encoding="utf-8").write(new)
            print("changed", path)
