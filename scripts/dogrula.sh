#!/usr/bin/env bash
# Derleme cikti dogrulamasi. Cikan ZIP'in gercekten j1minivelte icin oldugunu ve
# kernel'de binder portunun bulundugunu kanitlar.
#
# NOT: `set -o pipefail` + `grep -q` birlikte kullanilmaz — grep -q erken cikinca
# yukari akisa SIGPIPE gider ve pipeline 141 dondurur (yanlis negatif).
set -u
TOP="${TOP:-/home/void0x14/j106f/build/android}"
P="$TOP/out/target/product/j1minivelte"
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say=0; ok=0
chk() {
  say=$((say+1))
  if bash -c "$2" >/dev/null 2>&1; then
    ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$1"
  else
    printf '  \033[31m✘\033[0m %s\n' "$1"
  fi
}

echo "== ciktilar =="
ls -la "$P"/*.zip "$P"/boot.img "$P"/recovery.img "$P"/system.img "$P"/dt.img 2>/dev/null

echo "== kernel =="
K="$P/obj/KERNEL_OBJ/arch/arm/boot/zImage"
chk "zImage var"                     "[ -f '$K' ]"
chk "zImage boot bolumune sigar (<=10978320)" \
                                     "[ \$(stat -c %s '$K' 2>/dev/null || echo 99999999) -le 10978320 ]"
chk "hwbinder vmlinux'da"            "strings '$P/obj/KERNEL_OBJ/vmlinux' | grep -c 'binder,hwbinder,vndbinder'"
chk "CONFIG_ANDROID_BINDER_DEVICES"  "grep -c 'CONFIG_ANDROID_BINDER_DEVICES=\"binder,hwbinder,vndbinder\"' '$P/obj/KERNEL_OBJ/.config'"
chk "CONFIG_ANDROID_BINDER_IPC_32BIT" "grep -c '^CONFIG_ANDROID_BINDER_IPC_32BIT=y' '$P/obj/KERNEL_OBJ/.config'"

echo "== recovery.img =="
chk "recovery.img var"               "[ -f '$P/recovery.img' ]"
chk "recovery.img bolume sigar (<=26214400)" \
                                     "[ \$(stat -c %s '$P/recovery.img' 2>/dev/null || echo 99999999) -le 26214400 ]"
chk "recovery.tar (Odin) var"        "[ -f '$P/recovery.tar' ]"

echo "== zip =="
Z=$(ls "$P"/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip 2>/dev/null | head -1)
chk "zip var"                        "[ -n '$Z' ]"

echo "== ekran =="
# sharkls-common J3 2016'dan miras 320 dpi yazar; cihaza ozel system.prop onu
# ezmeli. Init'te ro.* write-once oldugu icin build.prop'ta ILK satir kazanir.
chk "lcd_density 240 yazilmis"       "unzip -p '$Z' system/build.prop | head -70 | grep -c 'ro.sf.lcd_density=240'"
chk "lcd_density 240 once geliyor"   "[ \$(unzip -p '$Z' system/build.prop | grep -n 'ro.sf.lcd_density=240' | head -1 | cut -d: -f1) -lt \$(unzip -p '$Z' system/build.prop | grep -n 'ro.sf.lcd_density=320' | head -1 | cut -d: -f1) ]"
chk "lcd_width/height 56/94"         "unzip -p '$Z' system/build.prop | head -70 | grep -c 'ro.sf.lcd_height=94'"

echo "== root =="
# WITH_SU, product makefile'inda ilk inherit'ten ONCE verilmeli; BoardConfig'te
# verilirse common.mk testi sirasinda deger bos olur ve su paketlenmez.
chk "su derlendi (intermediates)"    "[ -d '$P/obj/EXECUTABLES/su_intermediates' ]"

if [ -n "$Z" ]; then
  chk "zip icinde boot.img"          "unzip -l '$Z' | grep -c 'boot.img'"
  # vmlinux'ta gormek yetmez: cihaza giden sey zip icindeki boot.img'dir.
  # boot.img cekirdegi sikistirilmis zImage'dir; binder dizesi ic gzip akisinin
  # icindedir, ham zImage baytlarinda gorunmez (yanlis negatif tuzagi).
  chk "zip boot.img cekirdeginde binder" "bash '$S/kernel-kanit.sh' '$Z'"
  # Android 8.1 blok-OTA kullanir: system.img yerine system.new.dat.br +
  # system.transfer.list gelir. Ikisinden biri varsa system imaji tamamdir.
  chk "zip icinde system imaji"      "unzip -l '$Z' | grep -cE 'system\.(new\.dat|transfer\.list|img)'"
  chk "zip icinde update-binary"     "unzip -l '$Z' | grep -c 'META-INF/com/google/android/update-binary'"
  chk "zip icinde META-INF/com/android/metadata" \
                                     "unzip -l '$Z' | grep -c 'META-INF/com/android/metadata'"
fi

echo
echo "  $ok/$say gecti"
[ "$ok" -eq "$say" ]
