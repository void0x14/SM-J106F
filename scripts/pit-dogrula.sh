#!/usr/bin/env bash
# pit-dogrula.sh — cihazin GERCEK bolum tablosunu derleme yapilandirmasiyla
# ve derlenen imajlarla karsilastirir. Cihaz GEREKTIRMEZ.
#
# Neden gerekli: BOARD_*IMAGE_PARTITION_SIZE degerleri sharkls-common'dan
# (J3 2016 ailesi) miras gelir. J106F'in gercek tablosu farkli olabilir.
# Yanlis boyut varsayimi -> imaj bolume sigmaz -> yazma basarisiz, kotu durumda
# tugla.
#
# Iki girdi bicimi de kabul edilir (scripts/pit-coz.py ikisini de okur):
#   - ham .pit ikilisi (stok firmware'in CSC tar'i icinde gelir; cihaz gerekmez)
#   - `heimdall print-pit --no-reboot` metin ciktisi (cihaz download mode'da)
#
# Kullanim:
#   bash scripts/pit-dogrula.sh <pit-dosyasi|pit.txt> [urun-dizini]
set -uo pipefail
# Ondalik ayirici nokta olsun: bazi yerellerde printf "%.2f" virgul uretir ve
# "invalid number" hatasi verir.
export LC_ALL=C

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="${TOP:-/home/void0x14/j106f/build/android}"
PIT="${1:-}"
URUN="${2:-$TOP/out/target/product/j1minivelte}"
CFG="$TOP/device/samsung/sharkls-common/BoardConfigCommon.mk"

[ -n "$PIT" ] && [ -f "$PIT" ] || { echo "kullanim: $0 <pit-dosyasi|pit.txt> [urun-dizini]"; exit 1; }
[ -f "$CFG" ] || { echo "BoardConfigCommon.mk yok: $CFG"; exit 1; }
command -v python3 >/dev/null || { echo "python3 yok"; exit 1; }

# PIT bolum adi -> BoardConfig makro adi.
# KERNEL -> BOOT: cihazda boot bolumunun PIT adi KERNEL'dir.
declare -A MAKRO=(
  [KERNEL]=BOOT
  [RECOVERY]=RECOVERY
  [SYSTEM]=SYSTEM
  [CACHE]=CACHE
  [HIDDEN]=HIDDEN
)

# Bu cihazda AOSP'nin 'persist' bolumu YOK: fstab'da /persist yok, derleme
# persist.img uretmez. Cihazda PERSDATA adli AYRI bir bolum var (TWRP onu
# /persdata olarak baglar). BOARD_PERSISTIMAGE_PARTITION_SIZE bu yuzden olu
# yapilandirmadir; PERSDATA ile eslestirmek yanlis olur — asagida yalnizca
# bilgi olarak listelenir.

# --- derleme tarafindaki beklenen boyutlar ---
declare -A BEKLENEN
for pitadi in "${!MAKRO[@]}"; do
  v=$(grep -m1 "^BOARD_${MAKRO[$pitadi]}IMAGE_PARTITION_SIZE" "$CFG" | grep -oE '[0-9]+' | head -1)
  [ -n "$v" ] && BEKLENEN[$pitadi]=$v
done

echo "== derleme yapilandirmasi (sharkls-common'dan miras) =="
for k in $(printf '%s\n' "${!BEKLENEN[@]}" | sort); do
  printf '  %-10s %s bayt  (BOARD_%sIMAGE_PARTITION_SIZE)\n' "$k" "${BEKLENEN[$k]}" "${MAKRO[$k]}"
done

# --- PIT'i ayristir (pit-coz.py iki bicimi de okur) ---
echo
echo "== cihaz PIT tablosu =="
TSV=$(python3 "$S/pit-coz.py" "$PIT" --tsv 2>&1)
if [ $? -ne 0 ] || [ -z "$TSV" ]; then
  echo "  PIT ayristirilamadi: $PIT"
  echo "$TSV" | sed 's/^/  /'
  echo "  Gecerli girdi: ham .pit ikilisi veya 'heimdall print-pit' metin ciktisi."
  exit 1
fi

declare -A PITBOY
while IFS=$'\t' read -r ad boy; do
  [ -n "$ad" ] && PITBOY[$ad]=$boy
done <<< "$TSV"

for k in $(printf '%s\n' "${!PITBOY[@]}" | sort); do
  printf '  %-14s %12s bayt  (%.2f MiB)\n' "$k" "${PITBOY[$k]}" \
    "$(awk -v b="${PITBOY[$k]}" 'BEGIN{printf "%.2f", b/1048576}')"
done

# --- karsilastir ---
echo
echo "== karsilastirma: derleme boyutu vs cihaz =="
say=0; uyum=0; kotu=0
for k in $(printf '%s\n' "${!BEKLENEN[@]}" | sort); do
  say=$((say+1))
  b="${BEKLENEN[$k]}"
  p="${PITBOY[$k]:-}"
  if [ -z "$p" ]; then
    printf '  \033[33m?\033[0m %-10s derlemede %s bayt, PIT tablosunda bolum yok\n' "$k" "$b"
    continue
  fi
  if [ "$b" -eq "$p" ]; then
    uyum=$((uyum+1)); printf '  \033[32m✔\033[0m %-10s %s bayt — esit\n' "$k" "$b"
  elif [ "$b" -lt "$p" ]; then
    uyum=$((uyum+1))
    printf '  \033[32m✔\033[0m %-10s derleme %s, cihaz %s — imaj sigar (derleme kucuk)\n' "$k" "$b" "$p"
  else
    kotu=$((kotu+1))
    printf '  \033[31m✘\033[0m %-10s derleme %s, cihaz %s (fark %s bayt)\n' "$k" "$b" "$p" "$(( b - p ))"
    printf '      \033[31mderleme boyutu cihazdan BUYUK — imaj bolume SIGMAZ\033[0m\n'
    printf '      duzelt: %s icine BOARD_%sIMAGE_PARTITION_SIZE := %s\n' "$CFG" "${MAKRO[$k]}" "$p"
  fi
done

# --- derlenen imajlar cihazin bolumune sigiyor mu ---
echo
echo "== derlenen imajlar =="
declare -A IMGBOLUM=( [boot.img]=KERNEL [recovery.img]=RECOVERY )
img_kotu=0
for img in "${!IMGBOLUM[@]}"; do
  f="$URUN/$img"
  if [ ! -f "$f" ]; then
    printf '  \033[33m?\033[0m %-14s yok (derleme yapilmamis)\n' "$img"
    continue
  fi
  boy=$(stat -c %s "$f")
  bol="${IMGBOLUM[$img]}"
  pit="${PITBOY[$bol]:-}"
  if [ -z "$pit" ]; then
    printf '  \033[33m?\033[0m %-14s %s bayt, PIT te %s yok\n' "$img" "$boy" "$bol"
    continue
  fi
  if [ "$boy" -le "$pit" ]; then
    printf '  \033[32m✔\033[0m %-14s %s bayt <= %s %s bayt (sigar)\n' "$img" "$boy" "$bol" "$pit"
  else
    img_kotu=$((img_kotu+1))
    printf '  \033[31m✘\033[0m %-14s %s bayt > %s %s bayt — SIGMAZ\n' "$img" "$boy" "$bol" "$pit"
  fi
done
[ -f "$URUN/dt.img" ] && printf '  \033[32m✔\033[0m %-14s %s bayt (KERNEL/RECOVERY icine gomulur)\n' "dt.img" "$(stat -c %s "$URUN/dt.img")"

# --- stok firmware ile karsilastirma icin yedek boyutlari ---
echo
echo "== yedeklenecek bolumlerin GERCEK boyutlari (dd icin) =="
for ad in efs l_modem l_fixnv2 prodnv PERSDATA PARAM; do
  [ -n "${PITBOY[$ad]:-}" ] && printf '  %-10s %12s bayt  (%.2f MiB)\n' "$ad" "${PITBOY[$ad]}" \
    "$(awk -v b="${PITBOY[$ad]}" 'BEGIN{printf "%.2f", b/1048576}')"
done

echo
if [ "$kotu" -eq 0 ] && [ "$img_kotu" -eq 0 ]; then
  echo "  $uyum/$say boyut uyumlu; derlenen imajlar sigiyor."
  exit 0
fi
echo "  UYUSMAZLIK: $kotu yapilandirma, $img_kotu imaj."
exit 1
