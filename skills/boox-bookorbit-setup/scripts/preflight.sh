#!/usr/bin/env bash
# Read-only device preflight for the Boox/KOReader/BookOrbit setup. Changes nothing on the device.
#
# Usage: preflight.sh [-s SERIAL] [--expect-fingerprint FINGERPRINT]
#   -s SERIAL                      adb serial (required when more than one device is attached)
#   --expect-fingerprint FP        fail unless ro.build.fingerprint matches; use before every
#                                  mutating step to prove you are still talking to the same device
# Environment: ADB (path to adb, default: adb from PATH, then ~/.local/platform-tools/adb)
#
# Prints an IDENTITY line (serial, model, fingerprint) and a PASS/WARN/FAIL checklist.
# Exit code: 0 no FAIL, 1 at least one FAIL, 2 usage/connection problem.
set -uo pipefail

ADB_BIN="${ADB:-}"
if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/platform-tools/adb" ]; then ADB_BIN="$HOME/.local/platform-tools/adb"
  else echo "error: adb not found (set ADB=/path/to/adb)" >&2; exit 2; fi
fi

SERIAL=""; EXPECT_FP=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL="${2:-}"; shift 2 ;;
    --expect-fingerprint) EXPECT_FP="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "error: unknown argument $1" >&2; exit 2 ;;
  esac
done

DEVICES="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device" {print $1}')"
UNAUTH="$("$ADB_BIN" devices | awk 'NR>1 && $2!="device" && NF>=2 {print $1" ("$2")"}')"
COUNT="$(printf '%s\n' "$DEVICES" | grep -c . || true)"
if [ -z "$SERIAL" ]; then
  if [ "$COUNT" -eq 1 ]; then SERIAL="$DEVICES"
  elif [ "$COUNT" -eq 0 ]; then
    echo "error: no authorized device. Unauthorized/offline: ${UNAUTH:-none}" >&2; exit 2
  else echo "error: several devices attached, pass -s SERIAL. Found:" >&2; printf '%s\n' "$DEVICES" >&2; exit 2; fi
fi
printf '%s\n' "$DEVICES" | grep -qx "$SERIAL" || { echo "error: device $SERIAL not authorized/attached" >&2; exit 2; }

sh_() { "$ADB_BIN" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'; }
FAILS=0
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS+1)); }

MODEL="$(sh_ getprop ro.product.model)"
FP="$(sh_ getprop ro.build.fingerprint)"
ANDROID="$(sh_ getprop ro.build.version.release)"
SDK="$(sh_ getprop ro.build.version.sdk)"
ABIS="$(sh_ getprop ro.product.cpu.abilist)"
echo "IDENTITY serial=$SERIAL model=$MODEL fingerprint=$FP"
echo "android=$ANDROID sdk=$SDK abilist=$ABIS display=$(sh_ wm size | tr '\n' ' ')"

if [ -n "$EXPECT_FP" ]; then
  if [ "$FP" = "$EXPECT_FP" ]; then pass "fingerprint matches expected device"
  else fail "fingerprint differs from expected (wrong device?)"; fi
fi
if [ "${SDK:-0}" -ge 24 ] 2>/dev/null; then pass "Android API $SDK >= 24 (koho minSdk)"
else fail "Android API ${SDK:-unknown} < 24: koho cannot be installed"; fi
case "$ABIS" in
  *arm64-v8a*) pass "ABI arm64-v8a available" ;;
  *armeabi-v7a*) warn "no arm64 ABI; pick a matching KOReader armeabi-v7a APK" ;;
  *) warn "unknown ABI list '$ABIS'; check which KOReader APK matches" ;;
esac

echo "users: $(sh_ pm list users | tr '\n' ' ')"
echo "storage: $(sh_ df -h /sdcard | tail -1)"

PKGS="$(sh_ pm list packages)"
has() { printf '%s\n' "$PKGS" | grep -q "^package:$1\$"; }
if has com.onyx.android.note; then pass "Boox Notes app present (com.onyx.android.note): BACK IT UP IN-APP BEFORE ANY CHANGE"
else warn "Boox Notes app package not found; check for notes manually"; fi
for p in org.koreader.launcher org.koreader.launcher.fdroid io.github.michalkozik.koho app.olauncher; do
  has "$p" && echo "      installed: $p (enabled state: $(sh_ dumpsys package "$p" | grep -m1 -o 'enabled=[0-9]'))"
done
echo "HOME activity: $(sh_ cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 name)"
echo "Books dir: $(sh_ ls /sdcard/Books 2>/dev/null | wc -l | tr -d ' ') entries; notes dir: $(sh_ ls /sdcard/note 2>/dev/null | tr '\n' ' ')"
echo "Note: notes live in the Notes app's private DB, adb cannot read it. Verify an in-app backup with verify-notes-backup.sh."
echo "Note: Boox auto-freeze can disable KOReader/koho (enabled=3). It must be turned off in Apps -> App Management."

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
