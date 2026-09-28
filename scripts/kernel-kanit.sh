#!/usr/bin/env bash
# Yayinlanan ZIP'in ICINDEKI boot.img cekirdeginde binder portunun bulundugunu
# kanitlar.
#
# Neden ayri bir script: `strings zImage | grep hwbinder` YANLIS NEGATIF verir.
# Bu cihazin boot.img'sinde cekirdek sikistirilmis bir zImage'dir; gercek
# `binder,hwbinder,vndbinder` dizesi zImage'in icindeki gzip akisinin icindedir.
# zImage'in ham baytlarina bakmak dizeyi gormez.
#
# Yol: zip -> boot.img -> ANDROID! basligi -> cekirdek dilimi -> ic gzip -> grep
#
# Kullanim: kernel-kanit.sh [zip]
set -u

TOP="${TOP:-/home/void0x14/j106f/build/android}"
P="$TOP/out/target/product/j1minivelte"
Z="${1:-$(ls "$P"/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip 2>/dev/null | head -1)}"

if [ -z "${Z:-}" ] || [ ! -f "$Z" ]; then
  echo "ZIP bulunamadi: $P/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip" >&2
  exit 2
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

unzip -o -q "$Z" boot.img -d "$T" || { echo "zip icinde boot.img yok" >&2; exit 2; }

python3 - "$T/boot.img" <<'PY'
import re, struct, sys, zlib

yol = sys.argv[1]
d = open(yol, "rb").read()

# Android boot image basligi: ANDROID! + 9 adet uint32
if d[:8] != b"ANDROID!":
    print("HATA: ANDROID! imzasi yok"); sys.exit(2)
ks, ka, rs, ra, ss, sa, tags, page, dt = struct.unpack("<9I", d[8:44])
kernel = d[page:page + ks]

# zImage icindeki gzip akisini ara. Ilk gecerli olani al.
for m in re.finditer(b"\x1f\x8b\x08", kernel):
    try:
        coz = zlib.decompress(kernel[m.start():], 16 + zlib.MAX_WBITS)
    except Exception:
        continue
    n = coz.count(b"binder,hwbinder,vndbinder")
    surum = re.search(rb"Linux version [^\x00]{0,80}", coz)
    print("boot.img cekirdek :", ks, "bayt")
    print("ic gzip ofset     :", hex(m.start()))
    print("cozulen boyut     :", len(coz), "bayt")
    print("binder aygitlari  :", n)
    if surum:
        print("cekirdek surumu   :", surum.group(0).decode("latin1"))
    sys.exit(0 if n else 1)

print("HATA: cekirdekte gzip akisi bulunamadi (yeni bir sikistirma bicimi?)")
sys.exit(2)
PY
