#!/usr/bin/env bash
# J106F blob duzeltmeleri.
#
# Neden gerekli: cihazin kendi stok blob seti (ve elimizdeki tek referans kopyasi)
# bazi kutuphaneleri hic icermiyor. Bu kutuphaneler BIND_NOW (eager) baglanan
# ikililer tarafindan DT_NEEDED ile isteniyor; eksikse bionic yukleyici
# dosyayi hic acmaz ve servis sessizce olur. Hicbir hata mesaji cikmaz.
#
#  1. libbt-iopdb_mod.so     u_foldCase_55 -> u_foldCase_58
#     Blob ICU 55'e karsi derlenmis, agacta ICU 58 var (U_ICU_VERSION_SUFFIX _58).
#     Ayni imza: UChar32 u_foldCase(UChar32, uint32_t).
#     Dize uzunlugu esit oldugu icin yerinde yamanir, .dynstr bozulmaz.
#
#  2. libedmnativehelper.so (YENI DOSYA, shim)
#     vendor/lib/hw/bluetooth.default.so tam olarak bir sembol istiyor:
#     c_isBTOutgoingCallEnabled(). Iki cagri yeri de `cbz r0` ile dallanir,
#     yani 0 dondurmek normal yolu secer. Shim AYNI ADLA derlenir; boylece
#     bluetooth.default.so'ya hic dokunmak gerekmez.
#     Kaynak: device/samsung/j1minivelte/libshims/edmnativehelper_shim.c
#
# Kullanim: blob-fixup.sh [<proprietary-dizini>]
#           blob-fixup.sh --dogrula [<proprietary-dizini>]
set -u

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="${2:-$S/../vendor/samsung/j1minivelte/proprietary}"
[ "$1" = "--dogrula" ] || [ "${1:-}" = "" ] || P="$1"
[ -d "$P" ] || { echo "proprietary dizini yok: $P" >&2; exit 2; }

IOPDB="$P/lib/libbt-iopdb_mod.so"
BT="$P/lib/hw/bluetooth.default.so"

komut="${1:-}"

# --------------------------------------------------------------------------
dogrula() {
  local hata=0
  echo "== 1. libbt-iopdb_mod.so ICU sembolu =="
  if readelf -sW "$IOPDB" 2>/dev/null | grep -q 'u_foldCase_58'; then
    echo "   OK  u_foldCase_58"
  else
    echo "   X   u_foldCase_58 yok"; hata=1
  fi
  if readelf -sW "$IOPDB" 2>/dev/null | grep -q 'u_foldCase_55'; then
    echo "   X   u_foldCase_55 hala var"; hata=1
  fi

  echo "== 2. bluetooth.default.so EDM bagi =="
  if readelf -dW "$BT" 2>/dev/null | grep -q 'libedmnativehelper.so'; then
    echo "   OK  libedmnativehelper.so bagi duruyor (shim karsilar)"
  else
    echo "   X   libedmnativehelper.so bagi yok"; hata=1
  fi
  if [ -f "$P/lib/libedmnativehelper.so" ]; then
    echo "   OK  shim dosyasi yerinde"
  else
    echo "   .   shim derleme sirasinda uretilir (PRODUCT_PACKAGES)"
  fi

  [ $hata -eq 0 ] && echo "SONUC: duzeltmeler uygulanmis" || echo "SONUC: EKSIK DUZELTME"
  return $hata
}

[ "$komut" = "--dogrula" ] && { dogrula; exit $?; }

# --------------------------------------------------------------------------
echo "proprietary: $P"

# 1. ICU sembolu: yerinde, esit uzunlukta
python3 - "$IOPDB" <<'PYEOF' || exit 1
import sys
p = sys.argv[1]
b = open(p, "rb").read()
eski, yeni = b"u_foldCase_55\0", b"u_foldCase_58\0"
assert len(eski) == len(yeni)
n = b.count(eski)
if n == 0:
    if b.count(yeni):
        print("   .  ICU zaten yamali"); sys.exit(0)
    print("   X  u_foldCase_55 bulunamadi", file=sys.stderr); sys.exit(1)
if n != 1:
    print(f"   X  {n} gecis var, konum belirsiz", file=sys.stderr); sys.exit(1)
open(p, "wb").write(b.replace(eski, yeni))
print("   OK  u_foldCase_55 -> u_foldCase_58")
PYEOF

# 2. EDM bagi: bluetooth.default.so'ya DOKUNMA; shim ayni adla derlenir
echo "   .  libedmnativehelper.so bagi oldugu gibi kalir (shim ayni adla derlenir)"

echo
dogrula
