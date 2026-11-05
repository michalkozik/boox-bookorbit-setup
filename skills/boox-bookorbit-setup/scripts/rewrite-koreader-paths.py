#!/usr/bin/env python3
"""Rewrite book paths in KOReader state files after books were moved.

Safe-by-default replacement for blind search and replace:

* Works only on COPIES of the files pulled from the device (never on the device itself).
* Only touches an allowlist of files: settings.reader.lua, history.lua,
  bookorbit_sync_state.lua, collection.lua, bookshortcuts.lua and
  <book>.sdr/metadata.<ext>.lua.
* Only rewrites Lua string literals that are a path equal to OLD or below it
  (value == OLD or value starts with OLD + "/"), never plain substrings.
  "/old" does not touch "/older/x.epub". Comment lines are skipped.
* Mappings are applied once, longest OLD first, so --map /a /b --map /b /c
  does not turn /a/x into /c/x.
* New values are escaped as Lua string content, so quotes and backslashes stay valid.
* It refuses symlinks, missing or empty arguments, non-UTF-8 files and table-key
  collisions (two different keys ending up identical). It never deduplicates.
* Dry-run is the default. With --apply it first backs every changed file up to
  WORKDIR/.rewrite-backup-<timestamp>/, writes sibling temp files, verifies them, then
  replaces the originals, and restores the backups if anything fails.

Usage:
  rewrite-koreader-paths.py WORKDIR --map OLD NEW [--map OLD NEW ...] [--apply]

Run it only while KOReader is force-stopped on the device, then push the files back.
"""
import argparse
import os
import re
import shutil
import sys
import time

ALLOWED_NAMES = {
    "settings.reader.lua",
    "history.lua",
    "bookorbit_sync_state.lua",
    "collection.lua",
    "bookshortcuts.lua",
}
SDR_META = re.compile(r"^metadata\..+\.lua$")
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
KEY = re.compile(r'\[\s*"((?:[^"\\\n]|\\.)*)"\s*\]\s*=')


class RewriteError(Exception):
    pass


def lua_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def parse_mappings(pairs):
    mappings = []
    for old, new in pairs:
        if not old or not new:
            raise RewriteError("empty mapping argument")
        if not old.startswith("/") or not new.startswith("/"):
            raise RewriteError("mappings must be absolute paths: %r -> %r" % (old, new))
        old = old.rstrip("/") or "/"
        new = new.rstrip("/") or "/"
        if old == "/":
            raise RewriteError("refusing to map the root path")
        if old == new:
            raise RewriteError("old and new are identical: %r" % old)
        mappings.append((lua_escape(old), lua_escape(new)))
    # longest prefix first, so the most specific mapping wins
    mappings.sort(key=lambda m: len(m[0]), reverse=True)
    return mappings


def map_value(raw, mappings):
    """Return the rewritten raw string content, or None when it does not match."""
    for old, new in mappings:
        if raw == old:
            return new
        if raw.startswith(old + "/"):
            return new + raw[len(old):]
    return None


def rewrite_text(text, mappings):
    """Rewrite matching string literals. Returns (new_text, [(old, new), ...])."""
    changes = []

    def sub(match):
        raw = match.group(1)
        mapped = map_value(raw, mappings)
        if mapped is None:
            return match.group(0)
        changes.append((raw, mapped))
        return '"' + mapped + '"'

    out = []
    for line in text.split("\n"):
        if line.lstrip().startswith("--"):
            out.append(line)
        else:
            out.append(STRING.sub(sub, line))
    return "\n".join(out), changes


def check_key_collisions(old_text, new_text, name):
    old_keys = KEY.findall(old_text)
    new_keys = KEY.findall(new_text)
    if len(old_keys) != len(new_keys):
        raise RewriteError("%s: key count changed during rewrite" % name)
    existing = set(old_keys)
    seen = {}
    for old_k, new_k in zip(old_keys, new_keys):
        if new_k in seen and seen[new_k] != old_k:
            raise RewriteError(
                "%s: collision, keys %r and %r would both become %r" % (name, seen[new_k], old_k, new_k)
            )
        if new_k != old_k and new_k in existing:
            raise RewriteError(
                "%s: key %r would become %r, which already exists" % (name, old_k, new_k)
            )
        seen.setdefault(new_k, old_k)


def brace_balance(text):
    """Count { and } outside string literals and comment lines."""
    depth = 0
    for line in text.split("\n"):
        if line.lstrip().startswith("--"):
            continue
        stripped = STRING.sub('""', line)
        depth += stripped.count("{") - stripped.count("}")
    return depth


def candidate_files(workdir):
    found = []
    for root, dirs, files in os.walk(workdir):
        dirs[:] = [d for d in dirs if not d.startswith(".rewrite-backup")]
        for d in dirs:
            if os.path.islink(os.path.join(root, d)):
                raise RewriteError("refusing symlinked directory: %s" % os.path.join(root, d))
        in_sdr = os.path.basename(root).endswith(".sdr")
        for name in files:
            path = os.path.join(root, name)
            if name in ALLOWED_NAMES or (in_sdr and SDR_META.match(name)):
                if os.path.islink(path):
                    raise RewriteError("refusing symlink: %s" % path)
                found.append(path)
    return sorted(found)


def plan(workdir, mappings):
    results = []
    for path in candidate_files(workdir):
        with open(path, "rb") as handle:
            data = handle.read()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise RewriteError("%s is not valid UTF-8: %s" % (path, exc))
        new_text, changes = rewrite_text(text, mappings)
        if not changes:
            continue
        name = os.path.relpath(path, workdir)
        check_key_collisions(text, new_text, name)
        if brace_balance(text) != brace_balance(new_text):
            raise RewriteError("%s: brace balance changed, aborting" % name)
        results.append((path, new_text, changes))
    return results


def apply_plan(workdir, results):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup_root = os.path.join(workdir, ".rewrite-backup-" + stamp)
    done = []
    try:
        for path, _, _ in results:
            dest = os.path.join(backup_root, os.path.relpath(path, workdir))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(path, dest)
        for path, new_text, _ in results:
            tmp = path + ".rewrite-tmp"
            with open(tmp, "w", encoding="utf-8", newline="") as handle:
                handle.write(new_text)
            with open(tmp, "rb") as handle:
                if handle.read() != new_text.encode("utf-8"):
                    raise RewriteError("verification failed for " + path)
            os.replace(tmp, path)
            done.append(path)
    except Exception:
        for path in done:
            shutil.copy2(os.path.join(backup_root, os.path.relpath(path, workdir)), path)
        for path, _, _ in results:
            tmp = path + ".rewrite-tmp"
            if os.path.exists(tmp):
                os.remove(tmp)
        raise
    return backup_root


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("workdir")
    parser.add_argument("--map", nargs=2, action="append", metavar=("OLD", "NEW"), required=True,
                        help="absolute path prefix to rewrite and its replacement (repeatable)")
    parser.add_argument("--apply", action="store_true", help="write changes (default is dry-run)")
    args = parser.parse_args(argv)

    try:
        if not os.path.isdir(args.workdir):
            raise RewriteError("workdir does not exist: %s" % args.workdir)
        if os.path.islink(args.workdir.rstrip("/")):
            raise RewriteError("workdir is a symlink: %s" % args.workdir)
        workdir = os.path.realpath(args.workdir)
        mappings = parse_mappings(args.map)
        results = plan(workdir, mappings)
        for path, _, changes in results:
            print("%s: %d string(s)" % (os.path.relpath(path, workdir), len(changes)))
            for old, new in changes[:20]:
                print("  %s -> %s" % (old, new))
            if len(changes) > 20:
                print("  ... %d more" % (len(changes) - 20))
        if not results:
            print("nothing to change")
            return 0
        if not args.apply:
            print("dry-run only; add --apply to write (backup is created first)")
            return 0
        backup = apply_plan(workdir, results)
        print("applied to %d file(s); backup in %s" % (len(results), backup))
        return 0
    except RewriteError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
