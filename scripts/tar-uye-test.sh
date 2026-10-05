#!/usr/bin/env bash
# Tar üye seçimi testi — YANLIŞ İMAJ YAZILMASINI engelleyen kapı.
#
# Neden var: j106f-flash bir zamanlar tar içinden "ilk .img" dosyasını alıyordu.
# Ölçüldü: AP tar üyeleri sırayla boot.img, recovery.img, system.img gelir.
# Yani `--bolum recovery` verilince RECOVERY bölümüne boot.img yazılıyordu.
# Bu betik o hatanın geri gelmediğini her koşuda kanıtlar.
#
# Hiçbir şey yazmaz; yalnızca sarmalayıcının üye SEÇİM mantığını sınar.

set -u
SARMALAYICI="${SARMALAYICI:-$HOME/.config/opencode/govde/j106f-flash.mjs}"
POLICY="${POLICY:-$HOME/.config/opencode/govde/policy.json}"

say=0; ok=0
kapi() {
  say=$((say+1))
  if bash -c "$2" >/dev/null 2>&1; then ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$1"
  else printf '  \033[31m✘\033[0m %s\n' "$1"; fi
}

echo "== politika: tar uye eslemesi =="
for B in recovery boot system modem; do
  kapi "tar_uye_adi.$B tanimli" \
    "python3 -c \"import json,sys; p=json.load(open('$POLICY')); sys.exit(0 if p.get('tar_uye_adi',{}).get('$B') else 1)\""
done

echo "== politika: esleme GERCEK tar uyeleriyle tutuyor mu =="
# Gercek tar varsa uye adini birebir dogrula; yoksa atlanir.
STOK="${STOK:-/home/void0x14/j106f/stok-dogru}"
if [ -f "$STOK/AP_J106FJVU0ARH1_CL14293734_QB19570544_REV00_user_low_ship.tar.md5" ]; then
  AP="$STOK/AP_J106FJVU0ARH1_CL14293734_QB19570544_REV00_user_low_ship.tar.md5"
  for B in recovery boot system; do
    UYE=$(python3 -c "import json;print(json.load(open('$POLICY'))['tar_uye_adi']['$B'])")
    kapi "AP tar'da '$UYE' var ($B)" "tar -tf '$AP' 2>/dev/null | grep -qx '$UYE'"
  done
  # Asil hata: 'ilk .img' boot.img'dir ve recovery icin YANLIS olurdu.
  ILK=$(tar -tf "$AP" 2>/dev/null | grep '\.img$' | head -1)
  kapi "ilk .img != recovery.img (hata boyle dogmustu)" "[ '$ILK' != 'recovery.img' ]"
else
  echo "  \033[33m-\033[0m gercek AP tar yok, atlandı"
fi

if [ -f "$STOK/CP_J106FJVU0ARB3_CL13092899_QB17019159_REV00_user_low_ship.tar.md5" ]; then
  CP="$STOK/CP_J106FJVU0ARB3_CL13092899_QB17019159_REV00_user_low_ship.tar.md5"
  UYE=$(python3 -c "import json;print(json.load(open('$POLICY'))['tar_uye_adi']['modem'])")
  kapi "CP tar'da '$UYE' var (modem)" "tar -tf '$CP' 2>/dev/null | grep -qx '$UYE'"
else
  echo "  \033[33m-\033[0m gercek CP tar yok, atlandı"
fi

echo "== sarmalayici kodu: 'ilk .img' mantigi KALMAMIS olmali =="
# Yorumlari ayikla: aciklamada gecen '.img' metni kod sanilmasin.
KOD=$(grep -v '^\s*//' "$SARMALAYICI")
kapi "calisan kodda .find(endsWith .img) yok" "! printf '%s' \"\$KOD\" | grep -q 'endsWith(\".img\")'"
kapi "tar_uye_adi kullaniliyor"     "grep -q 'tar_uye_adi' '$SARMALAYICI'"
kapi "birebir ad eslesmesi var"     "grep -q 'path.basename(s).toLowerCase() === beklenen' '$SARMALAYICI'"
kapi "eslesmezse reddediliyor"      "grep -q 'bu tar .* bolumu icin degil' '$SARMALAYICI'"

echo
printf '  %d/%d kapı geçti\n' "$ok" "$say"
[ "$ok" -eq "$say" ]
