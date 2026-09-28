#!/usr/bin/env bash
# system.img icindeki SELinux etiketlerini olcer. Amac: cihaza ozel *_exec
# etiketlerinin imaja GERCEKTEN yazildigini kanitlamak.
#
# Neden gerekli: derleme her zaman gecer. file_contexts kurallari imaja
# uygulanmazsa hata cikmaz; hata yalnizca cihazda, init servisleri sessizce
# olurken gorunur (system/core/init/service.cpp:730
# ComputeContextFromExecutable -> "does not have a SELinux domain defined").
#
# Kullanim:
#   etiket-sayim.sh <system.img>
#
# Yontem: img'yi salt-okunur baglar, getfattr ile her dosyanin
# security.selinux xattr'ini okur, init'in gercek yollarindaki
# (/vendor/bin/*) etiketleri listeler.
set -euo pipefail

IMG="${1:?kullanim: etiket-sayim.sh <system.img>}"
IMG="$(readlink -f "$IMG")"
MNT="$(mktemp -d /tmp/etiket-mnt.XXXXXX)"

temizle() {
    mountpoint -q "$MNT" && sudo umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap temizle EXIT

sudo mount -o loop,ro "$IMG" "$MNT"
echo "img     : $IMG"
echo "baglama : $MNT"

# ---------------------------------------------------------------- tam sayim
echo
echo "=== imajdaki butun etiketler (ilk 60) ==="
sudo find "$MNT" -exec getfattr -d -m - --absolute-names {} + 2>/dev/null \
  | grep -o 'security\.selinux="[^"]*"' \
  | sed 's/.*="//;s/"$//' \
  | sort | uniq -c | sort -rn | head -60

# ------------------------------------------------- cihaza ozel exec etiketleri
# Cihaz file_contexts'inde tanimli etiketler (AOSP'de olmayanlar).
CIHAZ_ETIKETLER=(
    wcnd_exec engpc_exec autotest_exec charge_exec refnotify_exec
    modem_control_exec cp_diskserver_exec download_exec gnss_download_exec
    slogmodem_exec factorytest_exec phasecheckserver_exec GPSenseEngine_exec
    IPSecService_exec at_distributor_exec connfwexe_exec ddexe_exec
    ext_symlink_exec macloader_exec smdexe_exec batterysrv_exec
    cmd_services_exec thermald_exec ext_data_exec prepare_param_exec
    charon_exec gpsd_exec mfgloader_exec wlandutservice_exec
    slogd_exec srtd_exec sswap_exec zram_exec aprd_exec ylog_exec
    iqfeed_exec aprd_exec modemdriver_vpad_exec data_on_exec data_off_exec
)

echo
echo "=== cihaza ozel exec etiketleri imajda var mi ==="
sayim="$(sudo find "$MNT" -exec getfattr -d -m - --absolute-names {} + 2>/dev/null \
  | grep -o 'security\.selinux="[^"]*"' | sed 's/.*="//;s/"$//' | sort -u)"
var=0; yok=0
for e in "${CIHAZ_ETIKETLER[@]}"; do
    if printf '%s\n' "$sayim" | grep -qx "u:object_r:$e:s0"; then
        printf '  VAR  %s\n' "$e"; var=$((var+1))
    else
        printf '  YOK  %s\n' "$e"; yok=$((yok+1))
    fi
done

# ------------------------------------------- gercek servis yollarinin etiketi
echo
echo "=== /vendor/bin altindaki servis ikililerinin GERCEK etiketi ==="
for f in wcnd engpc modemd phoneserver modem_control cp_diskserver \
         refnotify download gnss_download slog slogmodem factorytest \
         phasecheckserver GPSenseEngine macloader smdexe at_distributor \
         ddexe connfwexe IPSecService cmd_services charon gpsd mfgloader \
         wlandutservice ext_data.sh ext_symlink.sh prepare_param.sh \
         hostapd hw/wpa_supplicant; do
    p="$MNT/vendor/bin/$f"
    if [ -e "$p" ]; then
        et="$(sudo getfattr -d -m - --absolute-names "$p" 2>/dev/null \
              | grep -o 'security\.selinux="[^"]*"' | sed 's/.*="//;s/"$//')"
        printf '  %-24s %s\n' "$f" "${et:-ETIKETSIZ}"
    fi
done

echo
echo "ozet: cihaz etiketi VAR=$var  YOK=$yok"
[ "$yok" -eq 0 ] || echo "UYARI: $yok cihaz etiketi imajda bulunamadi -> file_contexts mount-point onekini kontrol et"
