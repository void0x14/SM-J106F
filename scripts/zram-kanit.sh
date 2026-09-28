#!/usr/bin/env bash
# ROM zip'i icindeki boot.img ramdisk'inde "service zram" + tetikleyicinin
# gercekten var oldugunu kanitlar. Grep'ten farkli olarak ramdisk'i acar.
#
# Neden gerekli: zram.sh diski /system'de olabilir ama servisi baslatan rc
# satiri ramdisk'te olmazsa hicbir sey calismaz (bu tam olarak yasanan hataydi).
#
# Kullanim: zram-kanit.sh <rom-zip>
set -eu

Z="$1"
[ -f "$Z" ] || { echo "zip yok: $Z" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unzip -o -q "$Z" boot.img -d "$TMP"

python3 - "$TMP/boot.img" <<'PY'
import struct, gzip, sys

d = open(sys.argv[1], 'rb').read()
ksize, = struct.unpack('<I', d[8:12])
rsize, = struct.unpack('<I', d[16:20])
page,  = struct.unpack('<I', d[36:40])

def pad(n, p):
    return (n + p - 1) // p * p

roff = page + pad(ksize, page)
rd = d[roff:roff + rsize]

# cpio arsivi gzip'li olabilir
if rd[:2] == b'\x1f\x8b':
    rd = gzip.decompress(rd)

# init.sc8830.rc ramdisk icinde; cpio basliklari arasinda ara
needle = b'ro.config.zram.support=true'
svc = b'service zram /system/xbin/zram.sh'
hit_trigger = needle in rd
hit_service = svc in rd

if hit_trigger and hit_service:
    print("ramdisk: zram tetikleyici + servis var")
    sys.exit(0)
print("ramdisk: tetikleyici=%s servis=%s" % (hit_trigger, hit_service), file=sys.stderr)
sys.exit(1)
PY
