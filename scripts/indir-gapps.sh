#!/usr/bin/env bash
# MindTheGapps 8.1.0 arm indir + dogrula.
#
# Neden bu paket:
#   - ROM (LineageOS 15.1) Google servissiz gelir; Play Store icin GApps sart.
#   - Cihaz 32-bit ARM (Cortex-A7) -> arm paketi.
#   - Android 8.1 -> 8.1.0 paketi.
#   - 1 GB RAM + 8 GB depolama -> MindTheGapps (OpenGApps 'stock' degil),
#     sadece Play Store + Play Hizmetleri cekirdegi + gerekli cerceveler.
#
# GitHub tek dosya limiti 100 MB oldugu icin bu paket (106 MB) repoya
# gomulemez; bu script indirir ve sha256'sini dogrular.

set -euo pipefail

SURUM="MindTheGapps-8.1.0-arm-20180808_153837"
DOSYA="${SURUM}.zip"
URL="https://github.com/MindTheGapps/8.1.0-arm/releases/download/${SURUM}/${DOSYA}"
HEDEF_DIZIN="${1:-/home/void0x14/j106f/dist}"

mkdir -p "$HEDEF_DIZIN"
cd "$HEDEF_DIZIN"

if [[ -f "$DOSYA" ]]; then
  echo "zaten var: $HEDEF_DIZIN/$DOSYA"
else
  echo "indiriliyor: $URL"
  curl -sSL --retry 3 -o "$DOSYA" "$URL"
fi

BOYUT=$(stat -c '%s' "$DOSYA")
echo "boyut    : $BOYUT bayt"
if (( BOYUT < 90000000 )); then
  echo "HATA: paket cok kucuk, indirme yarim kalmis olabilir." >&2
  exit 1
fi

echo "sha256   : $(sha256sum "$DOSYA" | cut -d' ' -f1)"

# Paketin gercekten 8.1 / arm oldugunu iceriginden dogrula.
echo "icerik   :"
unzip -l "$DOSYA" | grep -E 'update-binary|updater-script' | sed 's/^/    /'
if unzip -p "$DOSYA" META-INF/com/google/android/updater-script 2>/dev/null | grep -q '8\.1\.0'; then
  echo "    ✔ updater-script 8.1.0 diyor"
else
  echo "    ⚠ updater-script'te 8.1.0 gecmiyor — surumu elle teyit et"
fi

cat <<EOF

Hazir: $HEDEF_DIZIN/$DOSYA

Kurulum sirasi (TWRP):
  1) lineage-15.1-*-j1minivelte.zip
  2) $(basename "$DOSYA")
  3) yeniden baslat

GApps'i ROM'dan ONCE degil SONRA kur. Wipe data/factory reset GApps'tan
sonra yapilirsa Play Hizmetleri bozulur.
EOF
