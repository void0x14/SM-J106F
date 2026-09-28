#!/usr/bin/env python3
# init servis denetimi: bir .rc dosyasindaki `service <ad> <yol> ...` satirinin
# cihaz acilisinda GERCEKTEN calisip calismayacagini olcer. Derleme her zaman
# gecer; hata yalnizca cihazda, cogu zaman sessizce ortaya cikar. Dort sinif:
#
#   1) EKSIK       ikili imajda hic yok
#                  system/core/init/service.cpp:720 `stat(args_[0])` basarisiz ->
#                  "cannot find '<yol>', disabling '<ad>'" -> servis olur.
#
#   2) YANLIS YOL  ikili imajda VAR ama rc baska yolu gosteriyor
#                  ayni sekilde stat basarisiz -> servis olur. "var" gorundugu
#                  icin gozden kacar.
#
#   3) ETIKETSIZ   ikili dogru yolda, ama dosyanin SELinux etiketi genel
#                  (vendor_file / system_file) veya hic yok.
#                  service.cpp:730 `ComputeContextFromExecutable()`:
#                  security_compute_create init context'ini dondurur ->
#                  "does not have a SELinux domain defined" -> ENFORCING'de
#                  "" dondurur -> Start() false -> servis olur. UYARI BASMAZ.
#
#   4) SECLABEL YOK rc acik `seclabel u:r:X:s0` veriyor, X politikada tanimsiz.
#                  service.cpp:281 setexeccon basarisiz -> cocuk PLOG(FATAL) ile
#                  olur; init ayni servisi tekrar tekrar dogurmaya calisir.
#
# Etiket cozumu init'in gercek baglama noktalarina gore yapilir:
# init.rc:56 `symlink /system/vendor /vendor` -> /vendor ve /system/vendor ayni
# dosyadir. file_contexts dosyalari ramdisk'te duz metin olarak durur; derlenmis
# sepolicy ikilisi de ayni ramdisk kokundedir.
#
# Kullanim: init-denetle.py <imaj-koku> [rc-dizini] [ramdisk-dizini]
#   imaj-koku     : system agacinin koku (icinde vendor/ olan)
#   rc-dizini     : init_rc/*.rc kaynagi (verilmezse imajdaki kopyalar okunur)
#   ramdisk-dizini: plat_/nonplat_file_contexts + sepolicy bulunan dizin
import os, re, sys

kok = sys.argv[1] if len(sys.argv) > 1 else "."
rc_kaynak = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
ramdisk_arg = sys.argv[3] if len(sys.argv) > 3 else None


# ------------------------------------------------------------------ ramdisk
def ramdisk_bul(kok, ipucu):
    """plat_file_contexts + nonplat_file_contexts + sepolicy iceren dizini bul."""
    gerekli = ("plat_file_contexts", "nonplat_file_contexts", "sepolicy")
    adaylar = []
    if ipucu:
        adaylar.append(ipucu)
    # kok ve ust dizinlerinde 'bootrd/rd', 'rd', 'ramdisk' ara
    d = os.path.abspath(kok)
    for _ in range(4):
        for alt in ("bootrd/rd", "rd", "ramdisk", "boot/rd"):
            adaylar.append(os.path.join(d, alt))
        yeni = os.path.dirname(d)
        if yeni == d:
            break
        d = yeni
    for a in adaylar:
        if a and all(os.path.isfile(os.path.join(a, g)) for g in gerekli):
            return a
    return None


ramdisk = ramdisk_bul(kok, ramdisk_arg)

kurallar = []
politika = b""

if ramdisk:
    for ad in ("plat_file_contexts", "nonplat_file_contexts"):
        for satir in open(os.path.join(ramdisk, ad), errors="replace"):
            satir = satir.strip()
            if not satir or satir.startswith("#"):
                continue
            par = satir.split()
            if len(par) >= 2:
                kurallar.append((par[0], par[1]))
    with open(os.path.join(ramdisk, "sepolicy"), "rb") as f:
        politika = f.read()

domainler = set()
for d in re.findall(rb'\x00([A-Za-z_][A-Za-z_0-9]{2,})\x00', politika):
    domainler.add(d.decode())


def onek_uzunlugu(rx):
    m = re.match(r'[A-Za-z0-9_/.\-]*', rx)
    return len(m.group(0)) if m else 0


def etiket_bul(yol):
    """init'in kurali: tam regex eslesmesi, en uzun sabit onek kazanir."""
    en_iyi, en_uzun = None, -1
    for rx, ctx in kurallar:
        try:
            if re.fullmatch(rx, yol):
                u = onek_uzunlugu(rx)
                if u >= en_uzun:
                    en_uzun, en_iyi = u, ctx
        except re.error:
            continue
    return en_iyi


# --------------------------------------------------------------- imaj agaci
# init'in ikili aradigi yerler: /system ve /vendor system bolumunde,
# /sbin ramdisk'te (rootfs). init.rc:56 /vendor -> /system/vendor.
kokler = [
    ("/system", kok),
    ("/vendor", os.path.join(kok, "vendor")),
    ("/system/vendor", os.path.join(kok, "vendor")),
]
if ramdisk:
    kokler.append(("/sbin", os.path.join(ramdisk, "sbin")))


def coz(yol):
    for onek, gercek in kokler:
        if yol == onek or yol.startswith(onek + "/"):
            return os.path.join(gercek, yol[len(onek):].lstrip("/"))
    return None


def var_mi(yol):
    g = coz(yol)
    return None if g is None else os.path.exists(g)


def baska_bolumde_ara(yol):
    """rc'nin gosterdigi yol yoksa, ayni dosya adi imajin baska yerinde var mi?"""
    ad = os.path.basename(yol)
    for alt in ("bin", "xbin", "vendor/bin", "vendor/xbin", "vendor/bin/hw"):
        if os.path.exists(os.path.join(kok, alt, ad)):
            return "/system/" + alt if alt.startswith("vendor/") else "/" + alt
    return None


# --------------------------------------------------------------- rc dosyalari
servis_re = re.compile(r'^\s*service\s+(\S+)\s+(\S+)')
seclabel_re = re.compile(r'^\s*seclabel\s+u:r:([A-Za-z_0-9]+):s0')


def rc_dosyalari():
    """Kaynak dizin verildiyse yalnizca onu tara: imajdaki kopyalar eski
    derlemeden kalmis olabilir ve yaniltici sonuc verir."""
    if rc_kaynak and os.path.isdir(rc_kaynak):
        yerler = [rc_kaynak]
    else:
        yerler = [os.path.join(kok, "etc/init"), os.path.join(kok, "vendor/etc/init")]
    for d in yerler:
        if os.path.isdir(d):
            for ad in sorted(os.listdir(d)):
                if ad.endswith(".rc"):
                    yield os.path.join(d, ad)


servisler = {}
seclabeler = {}
for yol_dosya in rc_dosyalari():
    ad_dosya = os.path.basename(yol_dosya)
    aktif = None
    for i, satir in enumerate(open(yol_dosya, errors="replace"), 1):
        if satir[:1] not in (" ", "\t") and satir.strip():
            m = servis_re.match(satir)
            aktif = m.group(2) if (m and m.group(2).startswith("/")) else None
            if aktif:
                servisler.setdefault(aktif, []).append((ad_dosya, i, m.group(1)))
            continue
        s = seclabel_re.match(satir)
        if s and aktif:
            seclabeler[aktif] = s.group(1)

# ------------------------------------------------------------------- denetim
eksik, yanlis_yol, etiketsiz, bilinmeyen, seclabel_yok = [], [], [], [], []
GENEL_ETIKET = {"u:object_r:vendor_file:s0", "u:object_r:system_file:s0", "u:object_r:rootfs:s0"}

for yol in sorted(servisler):
    r = var_mi(yol)
    if r is None:
        bilinmeyen.append(yol)
        continue
    if r is False:
        yer = baska_bolumde_ara(yol)
        (yanlis_yol if yer else eksik).append((yol, yer))
        continue
    if yol in seclabeler:
        if seclabeler[yol] not in domainler:
            seclabel_yok.append((yol, seclabeler[yol]))
        continue
    et = etiket_bul(yol)
    if et is None or et in GENEL_ETIKET:
        etiketsiz.append((yol, et))


# --------------------------------------------------------------------- rapor
print(f"imaj koku        : {kok}")
print(f"ramdisk          : {ramdisk or 'BULUNAMADI (etiket/domain denetimi yapilamaz)'}")
print(f"etiket kurali    : {len(kurallar)}")
print(f"tanimli servis   : {len(servisler)}")
print(f"politikadaki tip : {len(domainler)}")


def bas(ad, liste, aciklama):
    if not liste:
        return
    print(f"\n{ad} ({len(liste)}): {aciklama}")
    for oge in liste:
        yol = oge[0]
        kim = ", ".join(f"{a}:{b}:{c}" for a, b, c in servisler[yol])
        if ad == "YANLIS YOL":
            print(f"  ✘ rc: {yol}\n    gercek: {oge[1]}\n    {kim}")
        elif ad == "ETIKETSIZ":
            print(f"  ✘ {yol}  [etiket: {oge[1] or 'yok'}]  <- {kim}")
        elif ad == "SECLABEL YOK":
            print(f"  ✘ {yol}  seclabel u:r:{oge[1]}:s0 politikada yok  <- {kim}")
        else:
            print(f"  ✘ {yol}  <- {kim}")


bas("EKSIK", eksik, "ikili imajda hic yok, servis olur")
bas("YANLIS YOL", yanlis_yol, "ikili imajda VAR ama rc baska yol gosteriyor")
bas("ETIKETSIZ", etiketsiz, "yol dogru, etiket genel/yok -> domain gecisi yok, ENFORCING'de servis olur")
bas("SECLABEL YOK", seclabel_yok, "rc acik seclabel veriyor, tip politikada tanimsiz")
if bilinmeyen:
    print(f"\nBILINMEYEN ({len(bilinmeyen)}): init'in baglamadigi bolumde olabilir")
    for yol in bilinmeyen:
        print(f"  ? {yol}")

sorunlu = len(eksik) + len(yanlis_yol) + len(etiketsiz) + len(seclabel_yok)
if sorunlu == 0:
    print("\nSAGLAM: her servis ikilisi yerinde, etiketli ve domain gecisi tanimli")
else:
    print(f"\ntoplam sorunlu servis yolu: {sorunlu}")
sys.exit(1 if sorunlu else 0)
