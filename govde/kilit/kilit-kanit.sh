#!/bin/bash
# KILIT KANITI — libusb_reset_device gercekten engelleniyor mu?
#
# Iki kanit turu:
#   A) Shim devrede mi (constructor mesaji) — cihaz GEREKMEZ
#   B) Gercek reset kernel sayacini artiriyor mu — cihaz VARSA
#
# Cihaza YAZMA YOK. Yalnizca reset cagrisi denenir.

SO=/usr/local/lib/libusb-reset-kilit.so
T=/home/void0x14/j106f/build/kilit-test
say=0; ok=0
kapi() {
  say=$((say+1))
  if bash -c "$2" >/dev/null 2>&1; then ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$1"
  else printf '  \033[31m✘\033[0m %s\n' "$1"; fi
}

echo "== A) Shim devrede mi (cihaz gerekmez) =="
kapi "kutuphane var"          "[ -f $SO ]"
kapi "sembol export edilmis"  "nm -D $SO | grep -q 'T libusb_reset_device'"
kapi "yuklenince 'aktif' der" "LD_PRELOAD=$SO /bin/true 2>&1 | grep -q 'aktif'"
kapi "shimsiz sessiz"         "! ($T 2>&1 | grep -q 'libusb-reset-kilit')"

echo "== B) heimdall sarmalayicisi kilidi uyguluyor mu =="
kapi "kapi script"            "grep -q 'LD_PRELOAD' /usr/bin/heimdall"
kapi "kilit yolu dogru"       "grep -q '/usr/local/lib/libusb-reset-kilit.so' /usr/bin/heimdall"
kapi "gercek ikili yerinde"   "sudo -n test -x /usr/libexec/heimdall/heimdall.elf"
kapi "okuma eylemi serbest"   "grep -q 'detect|print-pit' /usr/bin/heimdall"

echo "== C) Gercek reset engeli (cihaz varsa) =="
if lsusb -d 04e8: >/dev/null 2>&1; then
  B=$(journalctl -k --no-pager --since "5 minutes ago" 2>/dev/null | grep -c "reset high-speed USB device")
  LD_PRELOAD=$SO $T >/dev/null 2>&1
  sleep 3
  A=$(journalctl -k --no-pager --since "5 minutes ago" 2>/dev/null | grep -c "reset high-speed USB device")
  kapi "kilitli reset kernel sayacini artirmadi ($B -> $A)" "[ $A -eq $B ]"
else
  printf '  \033[33m-\033[0m cihaz yok, C turu atlandi\n'
fi

echo
printf '  %d/%d kapı geçti\n' "$ok" "$say"
[ "$ok" -eq "$say" ]
