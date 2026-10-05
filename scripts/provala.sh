#!/usr/bin/env bash
# Deterministik flash provası — HİÇBİR ŞEY YAZMAZ.
#
# Amaç: telefona dokunmadan, tüm adımların sırasını ve kararlarını VM'de
# defalarca koşturmak. Her adım ya OKUR ya SIMÜLE eder. Yazma adımları
# `--gercek` verilmedikçe sadece EKRANA yazılır.
#
# Kullanım:
#   provala.sh              → tam prova (heimdall yoksa simülasyon)
#   provala.sh --gercek     → gerçek yazma (kullanıcı TTY + onay ister)
#
# Çıkış kodu: 0 = tüm kapılar geçti, 1 = kapı düştü.

set -u
GERCEK=0
[ "${1:-}" = "--gercek" ] && GERCEK=1

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIT="$KOK/../docs/pit/J1MINIVELTE_MEA_JV.pit"
URUN="${URUN:-/home/void0x14/j106f/build/android/out/target/product/j1minivelte}"

say=0; ok=0; atlanan=0
kapi() { # kapi <ad> <komut>
  say=$((say+1))
  if bash -c "$2" >/dev/null 2>&1; then
    ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$1"
  else
    printf '  \033[31m✘\033[0m %s\n' "$1"
  fi
}
bilgi() { printf '  \033[36m·\033[0m %s\n' "$1"; }
atla() { atlanan=$((atlanan+1)); printf '  \033[33m-\033[0m %s (atlandı)\n' "$1"; }

echo "== KAPI 0: ön koşullar =="
kapi "PIT dosyası var"           "[ -f '$PIT' ]"
kapi "recovery.tar var"          "[ -f '$URUN/recovery.tar' ]"
kapi "ROM zip var"               "ls '$URUN'/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip"

# PIT boyutlarını CİHAZIN KENDİ PIT'inden oku — sabit yazma.
PIT_RECOVERY=$(python3 "$KOK/pit-coz.py" "$PIT" --tsv 2>/dev/null | awk -F'\t' '$1=="RECOVERY"{print $2}')
PIT_KERNEL=$(python3   "$KOK/pit-coz.py" "$PIT" --tsv 2>/dev/null | awk -F'\t' '$1=="KERNEL"{print $2}')
bilgi "PIT RECOVERY = $PIT_RECOVERY bayt, KERNEL = $PIT_KERNEL bayt"

echo "== KAPI 1: imaj boyutları bölüme sığar =="
REC_IMG=$(stat -c %s "$URUN/recovery.img" 2>/dev/null || echo 999999999)
kapi "recovery.img ($REC_IMG) <= RECOVERY ($PIT_RECOVERY)" "[ $REC_IMG -le ${PIT_RECOVERY:-0} ]"

echo "== KAPI 2: heimdall yazma komutu kurulacak =="
# Yazma komutunu KUR, ÇALIŞTIRMA. Sadece diziyi göster.
YAZ_CMD=(heimdall flash "--RECOVERY" "$URUN/recovery.img" --no-reboot)
bilgi "komut: ${YAZ_CMD[*]}"
kapi "komut yalnızca --RECOVERY içeriyor" \
  "printf '%s\n' '${YAZ_CMD[*]}' | grep -q -- '--RECOVERY' && ! printf '%s\n' '${YAZ_CMD[*]}' | grep -qE -- '--(KERNEL|SYSTEM|l_modem|uboot|PIT)'"

echo "== KAPI 3: yazma sınıfı engeli (gövde koruması) =="
if [ -x "$HOME/.grok/hooks/govde-koruma.sh" ]; then
  for kotu in "heimdall flash --KERNEL x.img" "dd if=x of=/dev/block/mmcblk0p1" \
              "heimdall write-pit x.pit" "fastboot flash recovery x.img"; do
    kapi "engellenir: $kotu" \
      "printf '%s' '{\"toolName\":\"run_terminal_command\",\"toolInput\":{\"command\":\"$kotu\"}}' | bash '$HOME/.grok/hooks/govde-koruma.sh' | grep -q '\"deny\"'"
  done
  kapi "izin verilir: heimdall print-pit" \
    "printf '%s' '{\"toolName\":\"run_terminal_command\",\"toolInput\":{\"command\":\"heimdall print-pit\"}}' | bash '$HOME/.grok/hooks/govde-koruma.sh' | grep -q '\"allow\"'"
else
  atla "gövde koruması betiği"
fi

echo "== KAPI 4: cihaz bağlı mı =="
if heimdall detect >/dev/null 2>&1; then
  kapi "heimdall cihazı gördü" "heimdall detect"
  bilgi "GERÇEK YAZMA MÜMKÜN"
else
  atla "heimdall detect (cihaz yok — prova simülasyon modunda)"
fi

echo "== KAPI 5: yazma adımı =="
if [ "$GERCEK" -eq 0 ]; then
  bilgi "SİMÜLASYON: yazma yapılmadı. Gerçek için: provala.sh --gercek"
else
  if [ ! -t 0 ]; then
    printf '  \033[31m✘\033[0m --gercek bir TTY ister (boru hattından çalıştırılamaz)\n'
    say=$((say+1))
  else
    printf '  \033[31m!\033[0m Yazılacak: %s\n' "${YAZ_CMD[*]}"
    printf '  Onaylamak için bölümün PIT adını yaz (RECOVERY): '
    read -r ONAY
    if [ "$ONAY" = "RECOVERY" ]; then
      say=$((say+1)); ok=$((ok+1))
      printf '  \033[32m✔\033[0m onay alındı (bu provada yine de yazılmadı)\n'
    else
      say=$((say+1))
      printf '  \033[31m✘\033[0m onay reddedildi\n'
    fi
  fi
fi

echo
printf '  %d/%d kapı geçti, %d atlandı\n' "$ok" "$say" "$atlanan"
[ "$ok" -eq "$say" ]
