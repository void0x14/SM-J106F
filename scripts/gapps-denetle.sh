#!/usr/bin/env bash
# GApps paketini bir sistem agacinin KOPYASINA uygular ve sessiz-hata
# kapilarini kosar. Cihaza hicbir sey yazmaz.
#
# Neden: GApps TWRP'de ROM'dan SONRA kurulur. Paketin bu cihaza uyup
# uymadigi (mimari, DT_NEEDED kapanisi, dosya cakismasi, yer) yalnizca
# cihazda ortaya cikarsa boot kaybedilir ve sebep gorunmez:
#   - eksik DT_NEEDED / cozulemeyen sembol -> bionic yukleyici .so'yu hic
#     acmaz, tek satir log cikmaz (bkz. docs/YUKLEYICI-BULGU.md)
#   - genel SELinux etiketi -> init servisi sessizce olur
# Bu betik ayni sorulari host'ta, gercek imaj agacinin kopyasi uzerinde
# yanitlar.
#
# Kullanim:
#   gapps-denetle.sh <gapps.zip> <system-agaci> [ramdisk-dizini] [system.img]
#
# system-agaci: cihazin system bolumunun icerigi (or. debugfs rdump ciktisi
#               ya da out/target/product/<cihaz>/system).
# ramdisk-dizini: plat_/nonplat_file_contexts + sepolicy iceren dizin
#               (out/target/product/<cihaz>/root). Verilmezse agacin
#               kardesi olarak aranir; bulunamazsa o kapi atlanir.
# system.img:  ham ext4 imaj; verilirse bolum bos alani gercekten olculur.
#
# Cikis: her kapi kendi sonucunu basar; hepsi gecerse 0, aksi halde 1.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZIP="${1:?kullanim: gapps-denetle.sh <gapps.zip> <system-agaci> [ramdisk-dizini] [system.img]}"
AGAC="${2:?kullanim: gapps-denetle.sh <gapps.zip> <system-agaci> [ramdisk-dizini] [system.img]}"
RAMDISK="${3:-}"
IMG="${4:-}"

ZIP="$(readlink -f "$ZIP")"
AGAC="$(readlink -f "$AGAC")"
[ -f "$ZIP" ]  || { echo "yok: $ZIP" >&2;  exit 2; }
[ -d "$AGAC" ] || { echo "yok: $AGAC" >&2; exit 2; }

# ramdisk verilmediyse agacin kardesi olan 'root' dizinini ara.
if [ -z "$RAMDISK" ]; then
    for ADAY in "$(dirname "$AGAC")/root" "$AGAC/../root"; do
        if [ -f "$ADAY/plat_file_contexts" ] || [ -f "$ADAY/sepolicy" ]; then
            RAMDISK="$(readlink -f "$ADAY")"; break
        fi
    done
fi

TMP="$(mktemp -d /tmp/gapps-denetle.XXXXXX)"
temizle() { rm -rf "$TMP"; }
trap temizle EXIT

echo "gapps   : $ZIP"
echo "agac    : $AGAC"
echo "ramdisk : ${RAMDISK:-<yok>}"
echo

# ------------------------------------------------------------------ 1. paket
# Paket yuku META-INF disindaki her seydir; kurucu mantigi
# META-INF/com/google/android/update-binary icindedir, yuk degildir.
unzip -q -o "$ZIP" -x 'META-INF/*' -d "$TMP/yuk"

if [ -f "$TMP/yuk/system/build.prop" ]; then
    echo "uyari: yuk kendi build.prop'unu tasiyor; kurucu bunu bir kopya katmani" >&2
fi

YUK_DOSYA=$(find "$TMP/yuk" -type f | wc -l)
YUK_SO=$(find "$TMP/yuk" -name '*.so' -type f | wc -l)
echo "=== 1. paket yuku ==="
echo "dosya          : $YUK_DOSYA"
echo "yerel .so      : $YUK_SO"

# Mimari: yukteki her ELF'in e_machine'i ayni olmali. Sabit mimari adi
# gomulmez; cihaz agacindaki bir ELF'ten referans alinir.
if [ "$YUK_SO" -gt 0 ]; then
    mimari_oku() {
        python3 - "$1" <<'PY'
import struct, sys
p = sys.argv[1]
try:
    with open(p, 'rb') as f:
        d = f.read(20)
    if d[:4] != b'\x7fELF':
        print('ELF-degil'); raise SystemExit
    le = '<' if d[5] == 1 else '>'
    print(struct.unpack(le + 'H', d[18:20])[0])
except Exception:
    print('okunamadi')
PY
    }
    # Referans: agacta bulunan ilk ELF (varsa).
    REF_ELF="$(find "$AGAC" -type f -name '*.so' 2>/dev/null | head -1 || true)"
    YUK_MIM="$(find "$TMP/yuk" -name '*.so' -type f -exec python3 "$DIR/mimari.py" {} + \
               | sort -u | tr '\n' ',')"
    YUK_MIM="${YUK_MIM%,}"
    if [ -n "$REF_ELF" ]; then
        AGAC_MIM="$(python3 "$DIR/mimari.py" "$REF_ELF")"
        echo "yuk e_machine  : $YUK_MIM   (agac referansi: $AGAC_MIM)"
        case ",$YUK_MIM," in
            *",$AGAC_MIM,"*) echo "  OK  mimari agacla ayni" ;;
            *) echo "  X   mimari FARKLI -> cihaz bu .so'lari yukleyemez" >&2
               SONUC_MIM=1 ;;
        esac
    else
        echo "yuk e_machine  : $YUK_MIM   (agacta referans ELF yok)"
    fi
fi

# --------------------------------------------------------------- 2. cakisma
echo
echo "=== 2. dosya cakismasi (yuk vs agac) ==="
CAKISMA=0
while IFS= read -r REL; do
    [ -n "$REL" ] || continue
    if [ -e "$AGAC/${REL#system/}" ]; then
        echo "  X  ${REL#system/}" >&2
        CAKISMA=$((CAKISMA + 1))
    fi
done < <(cd "$TMP/yuk" && find system -type f | sed 's|^\./||')
echo "cakisan dosya  : $CAKISMA"

# ------------------------------------------------------- 3. hedef dizinler
echo
echo "=== 3. hedef dizinler ==="
EKSIK_DIZIN=0
while IFS= read -r D; do
    [ -n "$D" ] || continue
    if [ ! -d "$AGAC/${D#system/}" ]; then
        echo "  -  ${D#system/}  (kurucu olusturur)"
        EKSIK_DIZIN=$((EKSIK_DIZIN + 1))
    fi
done < <(cd "$TMP/yuk" && find system -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||')
echo "agacta olmayan : $EKSIK_DIZIN"

# ------------------------------------------------------------------ 4. yer
# Agac bir dizindir; bolumun gercek bos alani ancak ham imajdan okunur.
# 4. arguman verilirse (raw ext4 system.img) tune2fs ile olculur; yoksa
# yalnizca icerik boyutlari basilir, "yer var" iddiasi kurulmaz.
echo
echo "=== 4. yer ==="
YUK_KB=$(du -sk "$TMP/yuk" | awk '{print $1}')
AGAC_KB=$(du -sk "$AGAC" | awk '{print $1}')
echo "yuk            : $YUK_KB KB"
echo "agac icerik    : $AGAC_KB KB"
if [ -n "${IMG:-}" ] && [ -f "$IMG" ]; then
    # tune2fs cikti dili degisebilir; anahtar sozcuk yerine alan adi
    # 'Block count' / 'Free blocks' kullanilir ve sayilar ayiklanir.
    BLK=$(tune2fs -l "$IMG" 2>/dev/null | awk -F: '/^Block count/{gsub(/ /,"",$2);print $2}')
    BOS=$(tune2fs -l "$IMG" 2>/dev/null | awk -F: '/^Free blocks/{gsub(/ /,"",$2);print $2}')
    BOY=$(tune2fs -l "$IMG" 2>/dev/null | awk -F: '/^Block size/{gsub(/ /,"",$2);print $2}')
    if [ -n "$BLK" ] && [ -n "$BOS" ] && [ -n "$BOY" ]; then
        TOPLAM_MB=$(( BLK * BOY / 1048576 ))
        BOS_MB=$(( BOS * BOY / 1048576 ))
        echo "bolum          : ${TOPLAM_MB} MB, bos ${BOS_MB} MB"
        if [ "$YUK_KB" -gt $(( BOS_MB * 1024 )) ]; then
            echo "  X   yuk bolume sigmiyor" >&2
            SONUC_YER=1
        else
            echo "  OK  yuk bolume sigiyor"
        fi
    fi
else
    echo "bolum          : olculmedi (4. arguman olarak ham system.img ver)"
fi

# --------------------------------------------------------- 5. uygulanmis agac
echo
echo "=== 5. sessiz-hata kapilari (kopya uzerinde) ==="
# Imaj agacinda 0444 olmayan (or. 0000) fs_config dosyalari olabilir;
# sade kopya izin hatasi verir. Once sade dene, olmazsa sudo'ya dus.
if ! cp -a "$AGAC" "$TMP/agac" 2>/dev/null; then
    rm -rf "$TMP/agac"
    sudo cp -a "$AGAC" "$TMP/agac"
    sudo chown -R "$(id -u):$(id -g)" "$TMP/agac"
fi
cp -a "$TMP/yuk/system/." "$TMP/agac/"
echo "kopya          : $TMP/agac ($(find "$TMP/agac" -type f | wc -l) dosya)"

SONUC=0
if ! python3 "$DIR/elf-kapanis.py" "$TMP/agac" --sembol; then
    SONUC=1
fi

if [ -n "$RAMDISK" ] && [ -d "$RAMDISK" ]; then
    echo
    if ! python3 "$DIR/init-denetle.py" "$TMP/agac" - "$RAMDISK"; then
        SONUC=1
    fi
else
    echo
    echo "init-denetle ATLANDI: ramdisk dizini bulunamadi (ucuncu argumani ver)"
fi

echo
if [ "$CAKISMA" -ne 0 ] || [ "${SONUC_MIM:-0}" -ne 0 ] \
   || [ "${SONUC_YER:-0}" -ne 0 ] || [ "$SONUC" -ne 0 ]; then
    echo "SONUC: GApps bu agaca guvenle uygulanamaz (yukaridaki X satirlari)"
    exit 1
fi
echo "SONUC: GApps uygulanabilir, sessiz-hata kapilari temiz"
