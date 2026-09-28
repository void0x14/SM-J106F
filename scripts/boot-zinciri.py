#!/usr/bin/env python3
"""Onyukleme zincirinin kopuk halkalarini bulur.

Android init bazi seyleri sessizce yutar: var olmayan bir `import` dosyasi,
cozulemeyen `${ro.hardware}`. Ikisi de cihazi acmaz hale getirir, ama hicbir
hata mesaji uretmez. Bu betik uc halkayi denetler:

  1. Etkin cekirdek cmdline -> androidboot.hardware -> ro.hardware
     Etkin cmdline iki kaynaktan birlesir:
       - CONFIG_CMDLINE (derlenmis .config'den; CMDLINE_EXTEND/FORCE ile katilir)
       - DT /chosen bootargs
     androidboot.hardware YALNIZCA DT'de varsa ve LK /chosen bootargs'i
     eziyorsa kaybolur. CONFIG_CMDLINE'da olmasi LK'den bagimsiz garanti verir.

  2. rc import grafigi -> her import hedefi ramdisk'te var mi

  3. ramdisk yerlesimi -> boot.img ramdisk penceresi gecerli bir bellek
     bolgesinde mi ve /memreserve ile cakisiyor mu.
     NOT: DT'deki linux,initrd-start/end bir YER TUTUCUDUR; LK boot aninda
     update_device_tree() ile bu degeri boot.img'deki gercek ramdisk
     adresi/boyutuyla degistirir. Bu yuzden pencere boyutu denetlenmez;
     denetlenen sey boot.img'in yazdigi gercek yerlesimdir.

Kullanim:
  boot-zinciri.py <urun-dizini> [<kernel-dizini>]

Ornek:
  boot-zinciri.py /home/void0x14/j106f/build/android/out/target/product/j1minivelte \
                  /home/void0x14/j106f/build/android/kernel/samsung/j1minivelte
"""
import os
import re
import struct
import sys

BASARISIZ = []
NOTLAR = []


def bul(dizin, *adlar):
    for a in adlar:
        p = os.path.join(dizin, a)
        if os.path.exists(p):
            return p
    return None


# --------------------------------------------------------------------------
# FDT (flattened device tree) cozucu
# --------------------------------------------------------------------------
MAGIC = b"\xd0\x0d\xfe\xed"


def _fdt_walk(b):
    """(yol, ozellik_adi, deger) ucluleri uretir.

    DIKKAT: isim alanlari KENDI konumlarina gore 4 bayta hizalanir
    (p = p + ((e - p + 1 + 3) & ~3)), mutlak indekse gore degil.
    """
    if b[:4] != MAGIC:
        return None
    be = lambda o: struct.unpack_from(">I", b, o)[0]
    p = be(8)
    off_str = be(12)
    yigin = []
    while p + 4 <= len(b):
        tok = be(p)
        p += 4
        if tok == 1:                       # FDT_BEGIN_NODE
            e = b.index(b"\0", p)
            ad = b[p:e].decode("latin1")
            p = p + ((e - p + 1 + 3) & ~3)
            yigin.append(ad)
        elif tok == 2:                     # FDT_END_NODE
            if yigin:
                yigin.pop()
            if not yigin:
                break
        elif tok == 3:                     # FDT_PROP
            ln = be(p)
            no = be(p + 4)                 # ad, strings bloguna OFSET
            p += 8
            e = b.index(b"\0", off_str + no)
            ad = b[off_str + no:e].decode("latin1")
            deger = b[p:p + ln]
            p += (ln + 3) & ~3
            yield ("/" + "/".join(yigin[1:]), ad, deger)
        elif tok == 4:                     # FDT_NOP
            continue
        elif tok == 9:                     # FDT_END
            break
        else:
            break


def dtb_ozellik(dtb_yolu, istenen):
    """DTB'de istenen ozelligin degerini dondurur (yol, ad, deger)."""
    b = open(dtb_yolu, "rb").read()
    for yol, ad, deger in (_fdt_walk(b) or []):
        if ad in istenen:
            yield yol, ad, deger


def dtb_bootargs(dtb_yolu):
    for _y, ad, deger in dtb_ozellik(dtb_yolu, {"bootargs"}):
        return deger.rstrip(b"\0").decode("latin1")
    return None


def dts_bootargs(dts_yolu):
    """DTS chosen/bootargs satirini okur (yoksa None)."""
    if not dts_yolu or not os.path.exists(dts_yolu):
        return None
    s = open(dts_yolu, errors="replace").read()
    m = re.search(r'bootargs\s*=\s*"([^"]*)"', s)
    return m.group(1) if m else None


def dts_memreserve(dts_yolu):
    """DTS'teki /memreserve/ bolgelerini (baslangic, boyut) olarak dondurur."""
    out = []
    if not dts_yolu or not os.path.exists(dts_yolu):
        return out
    s = open(dts_yolu, errors="replace").read()
    for m in re.finditer(r'/memreserve/\s*<(0x[0-9a-fA-F]+)>\s*<(0x[0-9a-fA-F]+)>', s):
        out.append((int(m.group(1), 16), int(m.group(2), 16)))
    return out


def dts_memory(dts_yolu):
    """DT /memory reg = <taban boyut> (ilk banka)."""
    if not dts_yolu or not os.path.exists(dts_yolu):
        return None
    s = open(dts_yolu, errors="replace").read()
    m = re.search(r'device_type\s*=\s*"memory";\s*reg\s*=\s*<(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)>', s)
    if not m:
        return None
    return int(m.group(1), 16), int(m.group(2), 16)


def kernel_config(kernel_dizini, urun=None):
    """Derlenmis .config'den onyukleme ile ilgili anahtarlari okur.

    Arama yollari:
      <kernel>/.config
      <kernel>/../obj/KERNEL_OBJ/.config
      <urun>/obj/KERNEL_OBJ/.config
      <urun>/../../KERNEL/.config
    """
    adaylar = []
    if kernel_dizini:
        adaylar += [
            os.path.join(kernel_dizini, ".config"),
            os.path.join(kernel_dizini, "..", "obj/KERNEL_OBJ/.config"),
        ]
    if urun:
        adaylar += [
            os.path.join(urun, "obj/KERNEL_OBJ/.config"),
            os.path.join(urun, "..", "KERNEL/.config"),
            os.path.join(urun, "KERNEL/.config"),
        ]
    for p in adaylar:
        p = os.path.normpath(p)
        if os.path.exists(p):
            s = open(p, errors="replace").read()
            cfg = {}
            for satir in s.splitlines():
                m = re.match(r'(CONFIG_CMDLINE(?:_[A-Z_]+)?)="?(.*?)"?$', satir)
                if m:
                    cfg[m.group(1)] = m.group(2)
                m = re.match(r'# (CONFIG_CMDLINE(?:_[A-Z_]+)?) is not set', satir)
                if m:
                    cfg[m.group(1)] = None
            cfg["_yol"] = p
            return cfg
    return None


# --------------------------------------------------------------------------
# rc import grafigi
# --------------------------------------------------------------------------
def rc_grafik(kok, ilk, hw, zy="zygote32"):
    """init.rc'ten baslayip import'lari ozyinelemeli cozer."""
    okunan, eksik = [], []

    def gez(ad, derinlik=0):
        if derinlik > 32:
            return
        p = os.path.join(kok, ad.lstrip("/"))
        if not os.path.exists(p):
            eksik.append(ad)
            return
        okunan.append(ad)
        try:
            satirlar = open(p, errors="replace").read().splitlines()
        except OSError:
            return
        for ln in satirlar:
            m = re.match(r'\s*import\s+(\S+)', ln)
            if not m:
                continue
            hedef = (m.group(1)
                     .replace("${ro.hardware}", hw)
                     .replace("${ro.zygote}", zy))
            if hedef not in okunan:
                gez(hedef, derinlik + 1)

    gez(ilk)
    return sorted(set(okunan)), sorted(set(eksik))


def boot_img_header(yol):
    """boot.img v0 basligini cozer."""
    b = open(yol, "rb").read()
    if b[:8] != b"ANDROID!":
        return None
    (magic, ksz, kaddr, rsz, raddr,
     ssz, saddr, tags, psize, dtsz) = struct.unpack("<8sIIIIIIIII", b[:44])
    return {
        "kernel_size": ksz, "kernel_addr": kaddr,
        "ramdisk_size": rsz, "ramdisk_addr": raddr,
        "second_size": ssz, "tags_addr": tags,
        "page_size": psize, "dt_size": dtsz,
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    urun = sys.argv[1]
    kok = os.path.join(urun, "root")
    print(f"urun dizini : {urun}")

    kernel_dizini = sys.argv[2] if len(sys.argv) > 2 else None
    dts_dizin = None
    if kernel_dizini:
        dts_dizin = os.path.join(kernel_dizini, "arch/arm/boot/dts")
        if not os.path.isdir(dts_dizin):
            dts_dizin = kernel_dizini if os.path.isdir(kernel_dizini) else None

    # ---- kaynak DTS sec --------------------------------------------------
    kaynak_dts = None
    if dts_dizin and os.path.isdir(dts_dizin):
        for f in sorted(os.listdir(dts_dizin)):
            if f.endswith(".dts") and "j1minivelte" in f:
                kaynak_dts = os.path.join(dts_dizin, f)
                break

    # ---- 1. halka: etkin cmdline -> ro.hardware --------------------------
    print("\n== 1. halka: etkin cekirdek cmdline -> ro.hardware ==")
    cfg = kernel_config(kernel_dizini, urun)
    cfg_cmdline = None
    mod = None
    if cfg:
        cfg_cmdline = cfg.get("CONFIG_CMDLINE")
        if cfg.get("CONFIG_CMDLINE_FORCE"):
            mod = "FORCE"
        elif cfg.get("CONFIG_CMDLINE_EXTEND"):
            mod = "EXTEND"
        else:
            mod = "FROM_BOOTLOADER"
        print(f"  .config        : {cfg.get('_yol')}")
        print(f"  CONFIG_CMDLINE : {cfg_cmdline!r}")
        print(f"  cmdline modu   : {mod}")
    else:
        print("  .config bulunamadi (kernel dizini verilmedi mi?)")

    dba = dts_bootargs(kaynak_dts)
    print(f"  DT bootargs    : {dba!r}")

    # LK /chosen bootargs'i ezer ya da ekler -> DT tek basina garanti degil.
    kaynaklar = []
    if mod in ("EXTEND", "FORCE") and cfg_cmdline:
        kaynaklar.append(("CONFIG_CMDLINE", cfg_cmdline))
        print("  -> CONFIG_CMDLINE cmdline'a KATILIYOR (LK'den bagimsiz garanti)")
    elif mod == "FROM_BOOTLOADER":
        print("  -> CONFIG_CMDLINE yalnizca yedek; etkin cmdline DT/LK'den gelir")
    if dba:
        kaynaklar.append(("DT bootargs", dba))

    hw = "unknown"
    for kaynak, metin in kaynaklar:
        m = re.search(r'androidboot\.hardware=(\S+)', metin)
        if m:
            hw = m.group(1)
            print(f"  ro.hardware    : {hw}  (kaynak: {kaynak})")
            break
    if hw == "unknown":
        print("  ro.hardware    : BULUNAMADI")
        print("                   init /init.unknown.rc arar; cihaza ozel tum rc")
        print("                   dosyalari okunmadan kalir.")
        BASARISIZ.append("etkin cmdline'da androidboot.hardware yok")

    # derlenmis DTB'ler de ayni seyi soyluyor mu?
    dtb_dizin = os.path.join(urun, "obj/KERNEL_OBJ/arch/arm/boot/dts")
    dtbler = []
    if os.path.isdir(dtb_dizin):
        dtbler = sorted(os.path.join(dtb_dizin, f)
                        for f in os.listdir(dtb_dizin)
                        if f.endswith(".dtb") and "j1minivelte" in f)
    for d_ in dtbler:
        print(f"  {os.path.basename(d_)}: bootargs={dtb_bootargs(d_)!r}")

    # ---- 2. halka: rc import grafigi -------------------------------------
    print("\n== 2. halka: rc import grafigi ==")
    okunan, eksik = rc_grafik(kok, "/init.rc", hw)
    print(f"  ro.hardware={hw} ile okunan {len(okunan)} dosya:")
    for f in okunan:
        print(f"    + {f}")
    # /vendor/etc/init/hw/... AOSP'de her cihazda yok; olumcul degil
    gercek_eksik = [e for e in eksik if not e.startswith("/vendor/etc/init/hw/")]
    for f in eksik:
        isaret = "." if f.startswith("/vendor/etc/init/hw/") else "X"
        print(f"    {isaret} {f} (yok)")
    if gercek_eksik:
        BASARISIZ.append(f"cozulemeyen import: {', '.join(gercek_eksik)}")
    for beklenen in ("/init.sc8830.rc", f"/init.{hw}.rc"):
        if beklenen not in okunan:
            BASARISIZ.append(f"{beklenen} okunmuyor (import zinciri kopuk)")

    # ---- 3. halka: ramdisk yerlesimi -------------------------------------
    print("\n== 3. halka: ramdisk yerlesimi (LK boot aninda DT'yi yamalar) ==")
    bootimg = bul(urun, "boot.img")
    if not bootimg:
        print("  boot.img bulunamadi")
    else:
        h = boot_img_header(bootimg)
        rs, ra = h["ramdisk_size"], h["ramdisk_addr"]
        print(f"  boot.img ramdisk: 0x{ra:08x} + {rs} bayt -> 0x{ra+rs:08x}")
        print(f"  boot.img boyut  : {os.path.getsize(bootimg)} bayt")
        # NOT: boot.img basligindaki kernel_addr/ramdisk_addr/tags_addr
        # BOARD_KERNEL_BASE'e goreli degerlerdir (burada taban 0x0). LK bunlari
        # ABOOT_FORCE_* sabitleriyle gecersiz kilip gercek yerlesimi kendisi
        # yapar ve /chosen'a yazar. Dolayisiyla bu adreslerin DT /memory ile
        # dogrudan karsilastirilmasi anlamsizdir.
        # Denetlenebilir olan: ramdisk boyutu boot bolumune sigiyor mu, ve
        # DT'deki yer tutucu pencere LK tarafindan yamalaniyor mu.
        if rs <= 0:
            BASARISIZ.append("boot.img ramdisk boyutu sifir")
        # DT yer tutucu penceresi: LK yamalar, ama en azindan DT'de mevcut olmali
        if kaynak_dts:
            s = open(kaynak_dts, errors="replace").read()
            m = re.search(r'linux,initrd-start\s*=\s*<(0x[0-9a-fA-F]+)>', s)
            n = re.search(r'linux,initrd-end\s*=\s*<(0x[0-9a-fA-F]+)>', s)
            if m and n:
                a, b_ = int(m.group(1), 16), int(n.group(1), 16)
                print(f"  DT yer tutucu   : 0x{a:08x}..0x{b_:08x} "
                      f"({b_-a} bayt)")
                print("                    (LK boot aninda gercek ramdisk")
                print("                     adresi/boyutu ile degistirir)")
                if b_ <= a:
                    BASARISIZ.append("DT initrd penceresi gecersiz (end<=start)")
            else:
                BASARISIZ.append(
                    "DT'de linux,initrd-start/end yok: LK yamalayacak yer bulamaz")

    print()
    if BASARISIZ:
        print("SONUC: KOPUK HALKA VAR")
        for s in BASARISIZ:
            print(f"  - {s}")
        return 1
    print("SONUC: onyukleme zinciri saglam")
    return 0


if __name__ == "__main__":
    sys.exit(main())
