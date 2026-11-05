#!/usr/bin/env bash
# Pull and verify the Boox Notes in-app backup (Notes -> menu -> Options -> Backup and Restore).
# Read-only on the device. Proves the files copied intact (device and host SHA-256 match); it
# cannot prove the backup is restorable, so also keep per-note .note exports of irreplaceable notes.
#
# Usage: verify-notes-backup.sh -s SERIAL DEST_DIR [--max-age-hours N] [--device-dir DIR]
#   DEST_DIR            must be outside any git checkout; created with private permissions
#   --max-age-hours N   fail if the newest backup file is older (default 24)
#   --device-dir DIR    default /sdcard/note/backup/local
# Writes DEST_DIR/MANIFEST.txt (timestamp, names, sizes, sha256).
set -uo pipefail

ADB_BIN="${ADB:-}"
if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/platform-tools/adb" ]; then ADB_BIN="$HOME/.local/platform-tools/adb"
  else echo "error: adb not found (set ADB=...)" >&2; exit 2; fi
fi
SERIAL=""; DEST=""; MAX_AGE=24; DEVDIR="/sdcard/note/backup/local"
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL="${2:-}"; shift 2 ;;
    --max-age-hours) MAX_AGE="${2:-}"; shift 2 ;;
    --device-dir) DEVDIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; exit 2 ;;
    *) DEST="$1"; shift ;;
  esac
done
[ -n "$SERIAL" ] && [ -n "$DEST" ] || { echo "usage: $0 -s SERIAL DEST_DIR" >&2; exit 2; }
case "$MAX_AGE" in ''|*[!0-9]*) echo "error: --max-age-hours must be a number" >&2; exit 2 ;; esac

mkdir -p "$DEST" && DEST="$(cd "$DEST" && pwd)" || exit 2
if git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $DEST is inside a git checkout; choose a private directory outside it" >&2; exit 2
fi
chmod 700 "$DEST"

sh_() { "$ADB_BIN" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'; }
host_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

FILES="$(sh_ "find '$DEVDIR' -type f")"
[ -n "$FILES" ] || { echo "FAIL no backup files in $DEVDIR. Make an in-app backup first." >&2; exit 1; }

NOW="$(sh_ date +%s)"; NEWEST=0; BAD=0; COUNT=0
MANIFEST="$DEST/MANIFEST.txt"
{ echo "# Boox Notes backup manifest"; echo "created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "device_serial: $SERIAL"; echo "source: $DEVDIR"; } > "$MANIFEST"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *"'"*) echo "FAIL file name contains a single quote, cannot verify safely: $f" >&2; BAD=$((BAD+1)); continue ;; esac
  rel="${f#"$DEVDIR"/}"
  mkdir -p "$DEST/$(dirname "$rel")"
  "$ADB_BIN" -s "$SERIAL" pull "$f" "$DEST/$rel" >/dev/null 2>&1 || { echo "FAIL pull failed: $f" >&2; BAD=$((BAD+1)); continue; }
  dev_hash="$(sh_ "sha256sum '$f'" | cut -d' ' -f1)"
  loc_hash="$(host_sha "$DEST/$rel")"
  size="$(wc -c < "$DEST/$rel" | tr -d ' ')"
  mt="$(sh_ "stat -c %Y '$f'")"
  [ "${mt:-0}" -gt "$NEWEST" ] 2>/dev/null && NEWEST="$mt"
  if [ -n "$dev_hash" ] && [ "$dev_hash" = "$loc_hash" ]; then
    echo "$loc_hash  $size  $rel" >> "$MANIFEST"; COUNT=$((COUNT+1))
  else
    echo "FAIL hash mismatch or device hash unavailable: $f" >&2; BAD=$((BAD+1))
  fi
done <<< "$FILES"

AGE_H=$(( (NOW - NEWEST) / 3600 ))
echo "files verified: $COUNT, failed: $BAD, newest backup age: ${AGE_H}h, manifest: $MANIFEST"
[ "$BAD" -eq 0 ] || exit 1
[ "$COUNT" -gt 0 ] || { echo "FAIL nothing verified" >&2; exit 1; }
if [ "$NEWEST" -eq 0 ] || [ "$AGE_H" -gt "$MAX_AGE" ]; then
  echo "FAIL newest backup is older than ${MAX_AGE}h (or age unknown): make a fresh in-app backup" >&2; exit 1
fi
echo "OK (copy intact). Still keep .note exports of irreplaceable notes; restore was not tested."
