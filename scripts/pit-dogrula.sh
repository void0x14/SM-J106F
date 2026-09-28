#!/usr/bin/env bash
# pit-dogrula.sh — cihazin GERCEK PIT tablosunu derleme yapilandirmasiyla karsilastirir.
#
# Neden gerekli: BOARD_*IMAGE_PARTITION_SIZE degerleri sharkls-common'dan (J3 2016
# ailesi) miras gelir. J106F'in gercek bolum tablosu farkli olabilir. Yanlis boyut
# varsayimi -> imaj bolume sigmaz -> yazma basarisiz, kotu durumda tugla.
#
# Kullanim:
#   heimdall print-pit --no-reboot > pit.txt      (cihaz download mode'da, YAZMA YOK)
#   bash scripts/pit-dogrula.sh pit.txt
set -uo pipefail
TOP="${TOP:-/home/void0x14/j106f/build/android}"
PIT="${1:-}"
CFG="$TOP/device/samsung/sharkls-common/BoardConfigCommon.mk"

[ -n "$PIT" ] && [ -f "$PIT" ] || { echo "kullanim: $0 <pit-dosyasi>"; exit 1; }
[ -f "$CFG" ] || { echo "BoardConfigCommon.mk yok: $CFG"; exit 1; }

# PIT blok boyutu 512 bayt (Samsung/SPRD standart).
BLOK=512

# PIT bolum adi -> BoardConfig makro adi. PIT'te boot bolumunun adi KERNEL'dir.
declare -A MAKRO=(
  [KERNEL]=BOOT
  [RECOVERY]=RECOVERY
  [SYSTEM]=SYSTEM
  [CACHE]=CACHE
  [USERDATA]=USERDATA
  [HIDDEN]=HIDDEN
  [PERSDATA]=PERSIST
)

# --- derleme tarafindaki beklenen boyutlar (PIT adiyla anahtarlanir) ---
declare -A BEKLENEN
for pitadi in "${!MAKRO[@]}"; do
  v=$(grep -m1 "^BOARD_${MAKRO[$pitadi]}IMAGE_PARTITION_SIZE" "$CFG" | grep -oE '[0-9]+' | head -1)
  [ -n "$v" ] && BEKLENEN[$pitadi]=$v
done

echo "== derleme yapilandirmasi (sharkls-common'dan miras) =="
for k in $(printf '%s\n' "${!BEKLENEN[@]}" | sort); do
  printf '  %-10s %s bayt  (BOARD_%sIMAGE_PARTITION_SIZE)\n' "$k" "${BEKLENEN[$k]}" "${MAKRO[$k]}"
done

# --- PIT'i ayristir ---
echo
echo "== cihaz PIT tablosu =="
declare -A PITBOY PITBLOK
ad=""
while IFS= read -r satir; do
  satir="${satir%$'\r'}"
  case "$satir" in
    "Partition Name: "*) ad="${satir#Partition Name: }" ;;
    "Partition Block Count: "*)
      n="${satir#Partition Block Count: }"
      if [ -n "$ad" ]; then PITBLOK[$ad]=$n; PITBOY[$ad]=$(( n * BLOK )); fi ;;
  esac
done < "$PIT"

if [ "${#PITBOY[@]}" -eq 0 ]; then
  echo "  PIT ayristirilamadi — 'Partition Name:' / 'Partition Block Count:' satirlari yok."
  echo "  Dosyanin gercek 'heimdall print-pit' ciktisi oldugunu dogrula."
  exit 1
fi

for k in $(printf '%s\n' "${!PITBOY[@]}" | sort); do
  printf '  %-14s %12s bayt  (%s blok)\n' "$k" "${PITBOY[$k]}" "${PITBLOK[$k]}"
done

# --- karsilastir ---
echo
echo "== karsilastirma =="
say=0; uyum=0
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
  else
    fark=$(( b - p ))
    printf '  \033[31m✘\033[0m %-10s derleme %s, cihaz %s (fark %s bayt)\n' "$k" "$b" "$p" "$fark"
    if [ "$fark" -gt 0 ]; then
      printf '      \033[31mderleme boyutu cihazdan BUYUK — imaj bolume SIGMAZ\033[0m\n'
      printf '      duzelt: %s icine BOARD_%sIMAGE_PARTITION_SIZE := %s\n' "$CFG" "${MAKRO[$k]}" "$p"
    else
      printf '      \033[33mderleme boyutu cihazdan kucuk — imaj sigar ama yer israfi\033[0m\n'
    fi
  fi
done

echo
echo "  $uyum/$say boyut eslesti"
[ "$uyum" -eq "$say" ]
