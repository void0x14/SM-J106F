#!/usr/bin/env bash
# system.img icindeki SELinux etiketlerini olcer.
#
# Neden gerekli: derleme her zaman gecer. file_contexts kurallari imaja
# uygulanmazsa hata cikmaz; hata yalnizca cihazda, init servisleri sessizce
# olurken gorunur (system/core/init/service.cpp:730
# ComputeContextFromExecutable -> "does not have a SELinux domain defined").
#
# init-denetle.py kurali METINDEN tahmin eder (ramdisk'teki
# plat_/nonplat_file_contexts). Bu betik ondan BAGIMSIZ ikinci olcumdur:
# imaji baglar ve init'in servis yolu olarak kullanacagi her dosyanin
# GERCEK security.selinux xattr'ini okur. Ikisi ayni sonucu vermeli.
#
# Olculen asil degismez: rc'de `service <ad> <yol>` diye gecen yolun etiketi
# GENEL OLMAMALIDIR (vendor_file / system_file) ve xattr hic olmamalidir.
# Genel etiketle init, servis ikilisinden domain turetmez; Start() false
# doner ve HICBIR UYARI BASILMAZ.
#
# Sabit etiket listesi YOKTUR; servis yollari imajdaki rc dosyalarindan
# okunur. Boylece kurulu olmayan ikililer icin yanlis alarm uretilmez ve
# listede unutulan bir yol (or. /vendor/bin/rild) gozden kacmaz.
#
# Yol eslemesi: imaj koku /system'dir. init.rc:56
# `symlink /system/vendor /vendor` -> /vendor = /system/vendor = kok/vendor.
#
# Kullanim:
#   etiket-sayim.sh <system.img>
set -euo pipefail

IMG="${1:?kullanim: etiket-sayim.sh <system.img>}"
IMG="$(readlink -f "$IMG")"
MNT="$(mktemp -d /tmp/etiket-mnt.XXXXXX)"

temizle() {
    mountpoint -q "$MNT" && sudo umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap temizle EXIT

sudo mount -o loop,ro "$IMG" "$MNT"
echo "img     : $IMG"
echo "baglama : $MNT"

# getfattr, xattr'i OLMAYAN dosyalarda 1 doner; pipefail acikken bu boru
# hattini basarisiz gosterip set -e ile betigi oldurur. Cikis kodu yutulur.
etiket_oku() {
    sudo getfattr -d -m - --absolute-names "$1" 2>/dev/null \
      | grep -o 'security\.selinux="[^"]*"' | sed 's/.*="//;s/"$//' || true
}

# ---------------------------------------------------------------- tam sayim
echo
echo "=== imajdaki butun etiketler (en kalabalik 40) ==="
{ sudo find "$MNT" -exec getfattr -d -m - --absolute-names {} + 2>/dev/null \
    | grep -o 'security\.selinux="[^"]*"' | sed 's/.*="//;s/"$//' || true; } \
  | sort | uniq -c | sort -rn | sed -n '1,40p'

# ------------------------------------------------- servis yollari (tek sefer)
# Imaj koku /system oldugu icin "/system/X" -> "$MNT/X". /vendor ayri agac.
YOLLAR="$(sudo grep -hoE '^service[[:space:]]+[^[:space:]]+[[:space:]]+/[^[:space:]]+' \
              "$MNT/etc/init"/*.rc "$MNT/vendor/etc/init"/*.rc 2>/dev/null \
          | awk '{print $3}' | sort -u || true)"

GENEL='u:object_r:(vendor_file|system_file):s0'
sayi=0
sorunlu=0

echo
echo "=== rc dosyalarindaki servis yollarindaki GERCEK etiket ==="
while IFS= read -r yol; do
    [ -n "$yol" ] || continue
    sayi=$((sayi + 1))
    case "$yol" in
        /system/*) gercek="$MNT${yol#/system}" ;;
        *)         gercek="$MNT$yol" ;;
    esac
    if [ ! -e "$gercek" ]; then
        printf '  X  %-46s YOK\n' "$yol"
        sorunlu=$((sorunlu + 1))
        continue
    fi
    et="$(etiket_oku "$gercek")"
    et="${et:-<xattr yok>}"
    if printf '%s' "$et" | grep -Eq "$GENEL|<xattr yok>"; then
        printf '  X  %-46s %s\n' "$yol" "$et"
        sorunlu=$((sorunlu + 1))
    fi
done <<< "$YOLLAR"

echo
echo "tekil servis yolu          : $sayi"
echo "genel etiketli / etiketsiz : $sorunlu"
[ "$sorunlu" -eq 0 ] \
  && echo "SONUC: her servis yolu ozel etiketli" \
  || echo "SONUC: $sorunlu servis yolu genel etiketli -> init ENFORCING'de baslatamaz"
[ "$sorunlu" -eq 0 ]
