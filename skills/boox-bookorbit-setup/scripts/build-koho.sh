#!/usr/bin/env bash
# Build the koho launcher APK (Home -> KOReader).
#
# Usage: build-koho.sh [koho_src_dir] [out_dir]
#   koho_src_dir  default: ../assets/koho next to this script
#   out_dir       default: ~/.cache/koho-build ; receives koho.apk (nothing else is touched there)
#
# Environment:
#   KOHO_SDK_DIR    toolchain cache (default ~/.cache/koho-sdk)
#   KOHO_KEYSTORE   signing keystore (default ~/.config/koho/koho.jks). Keep it and back it up:
#                   a different key makes `adb install -r` fail with a signature mismatch.
#   JAVA_HOME       JDK 11+ (javac, keytool). Detected when unset.
#
# Downloads Android build-tools r34 and platform-30 from dl.google.com and verifies them against
# ../checksums.sha256 before use. Supported hosts: macOS (x86_64 or arm64 with Rosetta) and
# Linux x86_64. On Windows use WSL.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SELF_DIR/.." && pwd)"
CHECKSUMS="$SKILL_DIR/checksums.sha256"
BASE_URL="https://dl.google.com/android/repository"

die() { echo "error: $*" >&2; exit 1; }

# --- resolve arguments to absolute paths before any cd ---
SRC_ARG="${1:-$SKILL_DIR/assets/koho}"
[ -d "$SRC_ARG" ] || die "source dir not found: $SRC_ARG"
SRC="$(cd "$SRC_ARG" && pwd)"
[ -f "$SRC/AndroidManifest.xml" ] || die "no AndroidManifest.xml in $SRC"
[ -n "$(find "$SRC/src" -name '*.java' -print -quit 2>/dev/null)" ] || die "no .java sources under $SRC/src"
OUT_ARG="${2:-$HOME/.cache/koho-build}"
mkdir -p "$OUT_ARG"
OUT="$(cd "$OUT_ARG" && pwd)"

# --- host detection ---
case "$(uname -s)-$(uname -m)" in
  Darwin-*)           BT_ZIP="build-tools_r34-macosx.zip" ;;
  Linux-x86_64)       BT_ZIP="build-tools_r34-linux.zip" ;;
  *) die "unsupported host $(uname -s)-$(uname -m); use macOS or Linux x86_64 (WSL on Windows)" ;;
esac
PLAT_ZIP="platform-30_r03.zip"

# --- JDK detection: first candidate with javac, keytool and major version >= 11 ---
jdk_major() { "$1/bin/javac" -version 2>&1 | sed -E 's/^javac (1\.)?([0-9]+).*/\2/'; }
jdk_ok() {
  [ -n "$1" ] && [ -x "$1/bin/javac" ] && [ -x "$1/bin/keytool" ] || return 1
  local major; major="$(jdk_major "$1")"
  [ "${major:-0}" -ge 11 ] 2>/dev/null
}
CANDIDATES=()
[ -n "${JAVA_HOME:-}" ] && CANDIDATES+=("$JAVA_HOME")
if [ -x /usr/libexec/java_home ]; then CANDIDATES+=("$(/usr/libexec/java_home -v 11+ 2>/dev/null || true)"); fi
CANDIDATES+=(/opt/homebrew/opt/openjdk /usr/local/opt/openjdk /usr/lib/jvm/default-java)
if command -v javac >/dev/null 2>&1; then
  CANDIDATES+=("$(cd "$(dirname "$(command -v javac)")/.." && pwd -P)")
fi
FOUND_JDK=""
for c in "${CANDIDATES[@]}"; do
  if jdk_ok "$c"; then FOUND_JDK="$c"; break; fi
done
[ -n "$FOUND_JDK" ] || die "no JDK 11+ with javac and keytool found; install one (e.g. brew install openjdk) and set JAVA_HOME"
export JAVA_HOME="$FOUND_JDK" PATH="$FOUND_JDK/bin:$PATH"

# --- checksum helpers ---
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
expected_sha() { awk -v f="$1" '$1 !~ /^#/ && $2 == f { print $1 }' "$CHECKSUMS"; }

# --- toolchain cache: staged, verified, promoted atomically ---
SDK="${KOHO_SDK_DIR:-$HOME/.cache/koho-sdk}"
mkdir -p "$SDK"

fetch_and_unpack() {  # <zip name> <resulting dir> <required file>
  local zip="$1" dir="$2" need="$3"
  if [ -f "$SDK/$dir/.koho-complete" ] && [ -e "$SDK/$dir/$need" ]; then return; fi
  local want; want="$(expected_sha "$zip")"
  [ -n "$want" ] || die "no pinned checksum for $zip in $CHECKSUMS"
  local stage; stage="$(mktemp -d "$SDK/.stage.XXXXXX")"
  echo "downloading $zip ..."
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
       --retry 3 --connect-timeout 20 --max-time 900 -o "$stage/$zip" "$BASE_URL/$zip" \
    || { rm -rf "$stage"; die "download failed: $zip"; }
  local got; got="$(sha256_of "$stage/$zip")"
  [ "$got" = "$want" ] || { rm -rf "$stage"; die "checksum mismatch for $zip (expected $want, got $got)"; }
  unzip -q "$stage/$zip" -d "$stage/x" || { rm -rf "$stage"; die "unzip failed: $zip"; }
  [ -e "$stage/x/$dir/$need" ] || { rm -rf "$stage"; die "unexpected archive layout in $zip"; }
  touch "$stage/x/$dir/.koho-complete"
  rm -rf "${SDK:?}/$dir"
  mv "$stage/x/$dir" "$SDK/$dir"
  rm -rf "$stage"
}
fetch_and_unpack "$BT_ZIP" android-14 aapt2
fetch_and_unpack "$PLAT_ZIP" android-11 android.jar
BT="$SDK/android-14"; AJ="$SDK/android-11/android.jar"

# --- signing key: stable, private, outside the build output ---
KEYSTORE="${KOHO_KEYSTORE:-$HOME/.config/koho/koho.jks}"
PASSFILE="${KEYSTORE%.jks}.pass"
if [ ! -f "$KEYSTORE" ]; then
  echo "creating signing key at $KEYSTORE (back it up; losing it breaks 'adb install -r' updates)"
  ( umask 077
    mkdir -p "$(dirname "$KEYSTORE")"
    { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; echo; } > "$PASSFILE"
    keytool -genkeypair -keystore "$KEYSTORE" -storepass:file "$PASSFILE" -keypass:file "$PASSFILE" \
      -alias koho -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=koho" )
fi
[ -f "$PASSFILE" ] || die "password file missing: $PASSFILE (keystore exists without its password file)"

# --- build in a private temp dir, never in out_dir ---
WORK="$(mktemp -d "${TMPDIR:-/tmp}/koho-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cls" "$WORK/out"

"$BT/aapt2" link -o "$WORK/out/base.apk" -I "$AJ" --manifest "$SRC/AndroidManifest.xml" \
  --min-sdk-version 24 --target-sdk-version 30
JAVA_SRCS=(); while IFS= read -r f; do JAVA_SRCS+=("$f"); done < <(find "$SRC/src" -name '*.java')
javac -source 8 -target 8 -Xlint:-options -bootclasspath "$AJ" -d "$WORK/cls" "${JAVA_SRCS[@]}"
CLASSES=(); while IFS= read -r f; do CLASSES+=("$f"); done < <(find "$WORK/cls" -name '*.class')
"$BT/d8" --lib "$AJ" --output "$WORK/out" "${CLASSES[@]}"
( cd "$WORK/out" && "$BT/aapt" add base.apk classes.dex >/dev/null )
"$BT/zipalign" -f 4 "$WORK/out/base.apk" "$WORK/out/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "file:$PASSFILE" \
  --out "$WORK/out/koho.apk" "$WORK/out/aligned.apk"
"$BT/apksigner" verify --print-certs "$WORK/out/koho.apk" | grep -E 'SHA-256 digest|Verifies' || true

cp "$WORK/out/koho.apk" "$OUT/koho.apk.tmp" && mv "$OUT/koho.apk.tmp" "$OUT/koho.apk"
echo "built: $OUT/koho.apk"
echo "If 'adb install -r' reports a signature mismatch, do NOT uninstall koho while it is the default"
echo "home app: first run 'adb shell pm set-home-activity com.onyx/.StartupActivity', then use the original key."
