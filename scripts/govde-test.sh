#!/usr/bin/env bash
# govde-test.sh — gövde korumasının ret matrisini ve PIT ayrıştırıcısını sınar.
#
# Cihaz GEREKTİRMEZ. Hiçbir şey yazmaz: tüm çağrılar ya inceleme ya da red
# yolundan döner. Amaç, korumanın sessizce gevşemesini engellemek.
#
# Kullanim: bash scripts/govde-test.sh [recovery.tar]
set -u

G="${GOVDE:-$HOME/.config/opencode/govde/j106f-flash.mjs}"
P="${1:-/home/void0x14/j106f/build/android/out/target/product/j1minivelte/recovery.tar}"

[ -f "$G" ] || { echo "koruma bulunamadi: $G" >&2; exit 1; }
[ -f "$P" ] || { echo "ornek imaj bulunamadi: $P" >&2; exit 1; }

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

echo
echo "== PIT ayristirici =="
cat > pit.txt <<'PIT'
--- PIT Header ---
Entry Count: 3

--- Entry #0 ---
Binary Type: 0 (AP)
Device Type: 2 (MMC)
Identifier: 1
Partition Block Size/Offset: 0
Partition Block Count: 40960
Partition Name: KERNEL
Flash Filename: boot.img

--- Entry #1 ---
Binary Type: 0 (AP)
Device Type: 2 (MMC)
Identifier: 2
Partition Block Size/Offset: 40960
Partition Block Count: 40960
Partition Name: RECOVERY
Flash Filename: recovery.img

--- Entry #2 ---
Binary Type: 0 (AP)
Device Type: 2 (UFS)
Identifier: 3
Partition Block Size/Offset: 81920
Partition Block Count: 1000
Partition Name: SYSTEM
Flash Filename: system.img
PIT

say=$((say+1))
if node -e '
const fs=require("fs"), vm=require("vm")
const src=fs.readFileSync(process.argv[1],"utf8")
const m=src.match(/function pitBolumBoyu[\s\S]*?\n}\n/)
const fn=vm.runInNewContext(m[0]+"; pitBolumBoyu")
const pit=fs.readFileSync(process.argv[2],"utf8")
const b=[["KERNEL",20971520],["RECOVERY",20971520],["SYSTEM",4096000],["MODEM",null]]
for (const [ad,be] of b) if (fn(pit,ad)!==be) { console.error(ad,fn(pit,ad),"beklenen",be); process.exit(1) }
' "$G" pit.txt; then
  ok=$((ok+1)); printf '  \033[32m✔\033[0m PIT alan sirasi + MMC/UFS blok boyutu\n'
else
  printf '  \033[31m✘\033[0m PIT ayristirici\n'
fi

echo
echo "  $ok/$say gecti"
[ "$ok" -eq "$say" ]
