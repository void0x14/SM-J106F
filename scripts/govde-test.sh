#!/usr/bin/env bash
# govde-test.sh — gövde korumasının ret VE kabul matrisini sınar.
#
# Cihaz GEREKTİRMEZ. Hiçbir şey yazmaz: tüm çağrılar ya inceleme ya da red
# yolundan döner. Amaç, korumanın sessizce gevşemesini engellemek.
#
# Iki yon de sinanir:
#   ret   — yanlis cihaz / yasak bolum / kotu uzanti / TTY kapisi reddedilmeli
#   kabul — cihazin KENDI imajlari kabul edilmeli
# Kabul yolu sart: yalnizca reddi sinamak, korumanin dogru imaji da
# reddettigini gizler (olculdu: bir surum stok boot.img'yi reddediyordu).
#
# PIT ve politika sabit metinle degil, cihazin GERCEK PIT'inden (docs/pit/)
# calisma aninda uretilir ve karsilastirilir.
#
# Kullanim: bash scripts/govde-test.sh [recovery.tar]
set -u

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="${GOVDE:-$HOME/.config/opencode/govde/j106f-flash.mjs}"
POLICY="${POLICY:-$HOME/.config/opencode/govde/policy.json}"
PIT_COZ="$KOK/scripts/pit-coz.py"
PIT_RAW=$(ls "$KOK"/docs/pit/*.pit 2>/dev/null | head -1)
P="${1:-/home/void0x14/j106f/build/android/out/target/product/j1minivelte/recovery.tar}"
B="${B:-/home/void0x14/j106f/build/android/out/target/product/j1minivelte}"
S="${S:-/home/void0x14/j106f/stok/stokimg}"

[ -f "$G" ] || { echo "koruma bulunamadi: $G" >&2; exit 1; }
[ -f "$P" ] || { echo "ornek imaj bulunamadi: $P" >&2; exit 1; }
[ -f "$PIT_RAW" ] || { echo "gercek PIT bulunamadi: $KOK/docs/pit/*.pit" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"
cp "$P" dogru.tar
cp "$P" twrp-j3xlte-recovery.tar
cp "$P" imza.tar.bak
# OTA zip'i: ham imaj degil, TWRP'den kurulur. Reddedilmeli.
Z=$(ls /home/void0x14/j106f/build/android/out/target/product/j1minivelte/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip 2>/dev/null | head -1)
[ -n "$Z" ] && cp "$Z" rom.zip

say=0; ok=0
# red <aciklama> <beklenen parca> <argv...>
red() {
  aciklama="$1"; beklenen="$2"; shift 2
  say=$((say+1))
  cikti=$(node "$G" "$@" 2>&1)
  # grep -e: desen '--' ile baslayabilir (or. "--bolum belirtilmedi")
  if printf '%s' "$cikti" | grep -q 'REDDEDİLDİ' && printf '%s' "$cikti" | grep -q -e "$beklenen"; then
    ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$aciklama"
  else
    printf '  \033[31m✘\033[0m %s\n' "$aciklama"
    printf '%s\n' "$cikti" | sed 's/^/      /' | head -4
  fi
}

echo "== red matrisi =="
red "yanlis cihaz (dosya adi j3xlte)"  "YANLIŞ CİHAZ İMAJI"  incele twrp-j3xlte-recovery.tar --bolum recovery
red "yasak bolum (efs)"                "Bölüm yasak"          incele dogru.tar --bolum efs
red "izinli olmayan uzanti"            "Uzantı izinli değil"  incele imza.tar.bak --bolum recovery
red "bolum belirtilmedi"               "--bolum belirtilmedi" incele dogru.tar
red "TTY kapisi"                       "gerçek bir terminal"  flash dogru.tar --bolum recovery
[ -f rom.zip ] && red "OTA zip ham imaj degil" "OTA zip"      flash rom.zip --bolum system

# Bos/cop dosya "bos arsiv" sayilmamali. Olculdu: sifir dolu bir dosyada
# `tar -tf` exit 0 verip hicbir ad basmaz; koruma bunu arsiv sanip ham
# icerigi hic taramaz ve boyut kapisi da atlanir. Icerik taramasi yapilmali.
BOS="$T/bos.img"
head -c 23068672 /dev/zero > "$BOS"
printf 'ro.product.device=j1minivelte\nsamsung/j1miniveltejv/j1minivelte:6.0.1/x\n' >> "$BOS"
red "bos dosya arsiv sanilmiyor (boyut kapisi calisiyor)" "Boyut bölüm sınırını aşıyor" incele "$BOS" --bolum recovery

echo
echo "== kabul matrisi =="
# kabul <aciklama> <argv...>
kabul() {
  aciklama="$1"; shift
  say=$((say+1))
  cikti=$(node "$G" "$@" 2>&1)
  if printf '%s' "$cikti" | grep -q 'İnceleme tamam' && ! printf '%s' "$cikti" | grep -q 'REDDEDİLDİ'; then
    ok=$((ok+1)); printf '  \033[32m✔\033[0m %s\n' "$aciklama"
  else
    printf '  \033[31m✘\033[0m %s\n' "$aciklama"
    printf '%s\n' "$cikti" | sed 's/^/      /' | head -4
  fi
}
[ -f "$B/recovery.tar" ] && kabul "kendi recovery.tar kabul edildi"      incele "$B/recovery.tar" --bolum recovery
[ -f "$B/boot.img" ]     && kabul "kendi boot.img kabul edildi"          incele "$B/boot.img" --bolum boot
# Stok imaj: boot.img ramdisk'inde yalniz melfas/j1minilte.fw gecer, kimlik
# izi yoktur. Koruma bunu 'j1minilte' icerik kaniti sayip reddediyordu.
[ -f "$S/boot.img" ]     && kabul "stok boot.img kabul edildi"           incele "$S/boot.img" --bolum boot
[ -f "$S/recovery.img" ] && kabul "stok recovery.img kabul edildi"       incele "$S/recovery.img" --bolum recovery

echo
echo "== PIT ayristirici (gercek PIT: $PIT_RAW) =="
# Girdi SABIT METIN DEGIL: cihazin gercek PIT'i heimdall 'print-pit' bicimine
# cevrilir. Boylece korumanin ayristiricisi gercek 32 girdili tabloyla bulusur.
python3 "$PIT_COZ" "$PIT_RAW" --print-pit > pit.txt || { echo "print-pit uretilemedi" >&2; exit 1; }

say=$((say+1))
if node -e '
const fs=require("fs"), vm=require("vm")
const src=fs.readFileSync(process.argv[1],"utf8")
const m=src.match(/function pitBolumBoyu[\s\S]*?\n}\n/)
const fn=vm.runInNewContext(m[0]+"; pitBolumBoyu")
const pit=fs.readFileSync(process.argv[2],"utf8")
const b=[["KERNEL",20971520],["RECOVERY",20971520],["SYSTEM",2902458368],["l_modem",16777216],["MODEM",null]]
for (const [ad,be] of b) if (fn(pit,ad)!==be) { console.error(ad,fn(pit,ad),"beklenen",be); process.exit(1) }
' "$G" pit.txt; then
  ok=$((ok+1)); printf '  \033[32m✔\033[0m PIT alan sirasi + MMC/UFS blok boyutu (32 girdi)\n'
else
  printf '  \033[31m✘\033[0m PIT ayristirici\n'
fi

echo
echo "== politika <-> gercek PIT =="
# Politikadaki her mantiksal bolum adi ve boyut ust siniri cihazin GERCEK
# tablosuyla karsilastirilir. Olculen bir uyusmazlik: modem bolumunun adi
# 'MODEM' degil 'l_modem'dir.
say=$((say+1))
if python3 - "$POLICY" "$PIT_COZ" "$PIT_RAW" <<'PY'
import json, subprocess, sys
policy, coz, pit = sys.argv[1], sys.argv[2], sys.argv[3]
p = json.load(open(policy))
tsv = subprocess.run([sys.executable, coz, pit, "--tsv"], capture_output=True, text=True, check=True).stdout
boyut = {}
for satir in tsv.splitlines():
    ad, b = satir.split("\t")
    boyut[ad] = int(b)
hata = []
for mantiksal, pitadi in p.get("pit_bolum_adi", {}).items():
    if pitadi not in boyut:
        hata.append(f"pit_bolum_adi.{mantiksal} -> '{pitadi}' gercek PIT'te YOK")
for mantiksal, mb in p.get("bolum_boyut_ust_siniri_mb", {}).items():
    pitadi = p["pit_bolum_adi"].get(mantiksal)
    if pitadi not in boyut:
        continue
    gercek = boyut[pitadi] / 1048576
    # Kritik yon: ust sinir bolumden KUCUK olursa bolume SIGAN dogru imaj
    # incelemede reddedilir (olculdu: system 2048 MiB < bolum 2768 MiB).
    # Buyuk olmasi guvenlik sorunu degil; asil kapi flash'ta PIT ile konur.
    if mb < gercek - 1e-6:
        hata.append(f"bolum_boyut_ust_siniri_mb.{mantiksal} = {mb} MiB < gercek {pitadi} "
                    f"{gercek:.1f} MiB -> sigdigi halde incelemede reddedilir")
for h in hata:
    print("  UYUSMAZLIK:", h, file=sys.stderr)
sys.exit(1 if hata else 0)
PY
then
  ok=$((ok+1)); printf '  \033[32m✔\033[0m politika adlari/boyutlari gercek PIT ile tutarli\n'
else
  printf '  \033[31m✘\033[0m politika gercek PIT ile celisiyor\n'
fi

echo
echo "  $ok/$say gecti"
[ "$ok" -eq "$say" ]
