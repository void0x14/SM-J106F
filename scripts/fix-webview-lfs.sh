#!/usr/bin/env bash
# repo sync, Git LFS nesnelerini indirmez. external/chromium-webview prebuilt APK'lari
# LFS pointer (133 bayt) olarak kalir; signapk "error in opening zip file" ile patlar.
set -euo pipefail
TOP="${TOP:-/home/void0x14/j106f/build/android}"
for a in arm arm64 x86 x86_64; do
  d="$TOP/external/chromium-webview/prebuilt/$a"
  [ -d "$d" ] || continue
  ( cd "$d" && git lfs install --local >/dev/null && git lfs pull )
  f="$d/webview.apk"
  sz=$(stat -c %s "$f")
  [ "$sz" -gt 1000000 ] || { echo "HALA POINTER: $f ($sz bayt)"; exit 1; }
  echo "$a: $sz bayt"
done
