#!/usr/bin/env bash
# Yayinlanan ZIP'in sistem yukunun, dogrulanmis system.img ile AYNI oldugunu
# kanitlar.
#
# Neden gerekli: Android 8.1 blok-OTA kullanir; zip icinde system.img yoktur,
# system.new.dat.br + system.transfer.list vardir. "zip icinde system var"
# demek yetmez — icerigin gercekten derlenen sistem oldugunu gostermek gerekir.
#
# Yol: zip -> system.new.dat.br (brotli) + system.transfer.list -> ham ext4
#      -> debugfs rdump -> hedef agac ile dosya dosya sha256 karsilastirmasi
#
# Kullanim: ota-sistem-kanit.sh [zip] [target_files system.img]
set -u

TOP="${TOP:-/home/void0x14/j106f/build/android}"
P="$TOP/out/target/product/j1minivelte"
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Z="${1:-$(ls "$P"/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip 2>/dev/null | head -1)}"
TF="${2:-$(ls "$P"/obj/PACKAGING/target_files_intermediates/*/IMAGES/system.img 2>/dev/null | tail -1)}"

[ -f "${Z:-}" ] || { echo "ZIP bulunamadi" >&2; exit 2; }
[ -f "${TF:-}" ] || { echo "target_files system.img bulunamadi" >&2; exit 2; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"

echo "zip  : $Z"
echo "hedef: $TF"

unzip -o -q "$Z" system.new.dat.br system.transfer.list || exit 2

python3 "$S/ota-sistem-coz.py" system.new.dat.br system.transfer.list system.raw.img || exit 2
simg2img "$TF" tf.raw.img || exit 2

mkdir tz tt
debugfs -R "rdump / tz" system.raw.img >/dev/null 2>&1
debugfs -R "rdump / tt" tf.raw.img     >/dev/null 2>&1

# Tur + boyut + isim listesi (sembolik baglar dahil)
( cd tz && find . \( -type f -o -type l \) -printf '%y %s %p\n' | sort ) > a.list
( cd tt && find . \( -type f -o -type l \) -printf '%y %s %p\n' | sort ) > b.list

if ! diff -q a.list b.list >/dev/null; then
  echo "FARK: dosya listesi uyusmuyor" >&2
  diff a.list b.list | head -20 >&2
  exit 1
fi
echo "yapi: $(wc -l < a.list) girdi, birebir ayni"

# Normal dosyalarin icerigi (fs_config_* 0000 modlu, okunamaz — disarida)
( cd tz && find . -type f -perm -u+r -print0 | xargs -0 sha256sum | sort -k2 ) > a.sha
( cd tt && find . -type f -perm -u+r -print0 | xargs -0 sha256sum | sort -k2 ) > b.sha

if ! diff -q a.sha b.sha >/dev/null; then
  echo "FARK: dosya icerigi uyusmuyor" >&2
  diff a.sha b.sha | head -20 >&2
  exit 1
fi
echo "icerik: $(wc -l < a.sha) dosya, sha256 birebir ayni"
echo "SONUC: zip icindeki sistem, dogrulanmis system.img ile ayni"
