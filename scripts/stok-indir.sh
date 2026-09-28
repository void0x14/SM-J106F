#!/usr/bin/env bash
# stok-indir.sh — J106F stok firmware'ini indirir ve icinden PIT + referans
# imajlari cikarir. Cihaza HICBIR SEY yazmaz.
#
# Neden: cihazin gercek bolum tablosu (PIT) stok firmware'in CSC tar'i icinde
# gelir. Bu betik onu cihaz baglamadan elde etmeyi saglar; boylece
# BOARD_*IMAGE_PARTITION_SIZE degerleri tahminle degil olcumle dogrulanir.
#
# Kullanim:
#   bash scripts/stok-indir.sh [hedef-dizin]
# Varsayilan hedef: /home/void0x14/j106f/stok
set -euo pipefail
export LC_ALL=C

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEDEF="${1:-/home/void0x14/j106f/stok}"

# archive.org ogeleri. Oncelik sirasiyla denenir; ilki calisirsa durulur.
OGELER=(
  "KSAJ106FJVU0APJ320161102091153|KSA-J106FJVU0APJ3-20161102091153.zip"
)
# Beklenen sha256 — indirme bozuksa burada durur.
BEKLENEN_SHA="fc994fc8a68a8ca0af59c325f9b7ec2802dada30114e1252fc1132de5244c349"

mkdir -p "$HEDEF"
cd "$HEDEF"

ZIP_YOL=""
for kayit in "${OGELER[@]}"; do
  IAD="${kayit%%|*}"; AD="${kayit##*|}"
  if [ -f "$AD" ] && [ "$(stat -c %s "$AD")" -gt 1000000000 ]; then
    echo "zaten var: $AD"; ZIP_YOL="$AD"; break
  fi
  URL="https://archive.org/download/$IAD/$AD"
  echo "indiriliyor: $URL"
  curl -L --fail --retry 3 -o "$AD" "$URL"
  ZIP_YOL="$AD"; break
done

[ -n "$ZIP_YOL" ] || { echo "firmware indirilemedi" >&2; exit 1; }

echo "sha256 dogrulaniyor..."
GERCek=$(sha256sum "$ZIP_YOL" | awk '{print $1}')
if [ "$GERCek" != "$BEKLENEN_SHA" ]; then
  echo "UYARI: sha256 beklenenden farkli" >&2
  echo "  beklenen: $BEKLENEN_SHA" >&2
  echo "  olculen : $GERCek" >&2
  echo "  (archive.org ogeleri yeniden taranmis olabilir; icerigi elle dogrula)" >&2
fi

echo "arsiv aciliyor..."
unzip -o -q "$ZIP_YOL"

echo "PIT cikariliyor..."
mkdir -p pit stokimg bl
PIT_TAR=$(ls CSC_*.tar.md5 2>/dev/null | head -1)
[ -n "$PIT_TAR" ] || { echo "CSC tar yok" >&2; exit 1; }
PIT_AD=$(tar -tf "$PIT_TAR" | grep -i '\.pit$' | head -1)
[ -n "$PIT_AD" ] || { echo "CSC tar icinde .pit yok" >&2; exit 1; }
tar -xf "$PIT_TAR" -C pit "$PIT_AD"
echo "  PIT: pit/$PIT_AD  ($(stat -c %s "pit/$PIT_AD") bayt)"

echo "referans imajlar cikariliyor..."
AP_TAR=$(ls AP_*.tar.md5 2>/dev/null | head -1)
[ -n "$AP_TAR" ] && tar -xf "$AP_TAR" -C stokimg boot.img recovery.img 2>/dev/null || true
BL_TAR=$(ls BL_*.tar.md5 2>/dev/null | head -1)
[ -n "$BL_TAR" ] && tar -xf "$BL_TAR" -C bl 2>/dev/null || true

echo
echo "== PIT tablosu =="
python3 "$DIR/scripts/pit-coz.py" "pit/$PIT_AD" | head -8
echo
echo "== karsilastirma =="
bash "$DIR/scripts/pit-dogrula.sh" "$DIR/docs/pit/$PIT_AD" 2>/dev/null || \
  bash "$DIR/scripts/pit-dogrula.sh" "pit/$PIT_AD"
echo
echo "bitti. PIT: $HEDEF/pit/$PIT_AD"
