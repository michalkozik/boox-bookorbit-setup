#!/usr/bin/env bash
# Rebuild the koho launcher APK (Home -> KOReader). Needs JDK (openjdk) and downloads
# Android build-tools r34 + platform-30 from dl.google.com on first run.
# Usage: build-koho.sh [koho_src_dir] [out_dir]
set -euo pipefail

SRC="${1:-$(cd "$(dirname "$0")/../assets/koho" && pwd)}"
OUT="${2:-$HOME/.local/dl/koho-build}"
SDK="$HOME/.local/dl/sdk"
JH="${JAVA_HOME:-/opt/homebrew/opt/openjdk}"
[ -x "$JH/bin/javac" ] || JH="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"

mkdir -p "$SDK" "$OUT"
if [ ! -d "$SDK/android-14" ]; then
  curl -fsSL -o "$SDK/bt.zip" https://dl.google.com/android/repository/build-tools_r34-macosx.zip
  unzip -q -o "$SDK/bt.zip" -d "$SDK"
fi
if [ ! -f "$SDK/android-11/android.jar" ]; then
  curl -fsSL -o "$SDK/plat.zip" https://dl.google.com/android/repository/platform-30_r03.zip
  unzip -q -o "$SDK/plat.zip" -d "$SDK"
fi
BT="$SDK/android-14"; AJ="$SDK/android-11/android.jar"

cd "$OUT"; rm -rf cls out; mkdir -p cls out
"$BT/aapt2" link -o out/base.apk -I "$AJ" --manifest "$SRC/AndroidManifest.xml" \
  --min-sdk-version 24 --target-sdk-version 30
"$JH/bin/javac" -source 8 -target 8 -bootclasspath "$AJ" -d cls "$SRC"/src/io/github/michalkozik/koho/*.java
JAVA_HOME="$JH" PATH="$JH/bin:$PATH" "$BT/d8" --lib "$AJ" --output out cls/io/github/michalkozik/koho/*.class
( cd out && "$BT/aapt" add base.apk classes.dex >/dev/null )
"$BT/zipalign" -f 4 out/base.apk out/aligned.apk
# New throwaway signing key per build machine; never commit it.
[ -f koho.jks ] || "$JH/bin/keytool" -genkeypair -keystore koho.jks -storepass changeit -keypass changeit \
  -alias koho -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=koho" >/dev/null 2>&1
JAVA_HOME="$JH" PATH="$JH/bin:$PATH" "$BT/apksigner" sign --ks koho.jks --ks-pass pass:changeit \
  --key-pass pass:changeit --out koho.apk out/aligned.apk
echo "built: $OUT/koho.apk"
