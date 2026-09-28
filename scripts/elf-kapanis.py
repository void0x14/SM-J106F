#!/usr/bin/env python3
"""Sessiz yukleyici hatalarini bulur: DT_NEEDED grafiginde cozulemeyen bag.

Android'de eksik bir paylasimli kutuphane hicbir hata uretmez. bionic yukleyici
dosyayi acmaz, servis sessizce olur, logda tek satir cikar. Bu betik system.img
icindeki her ELF'i tarar ve ulasilabilir olanlarin bag kapanisini cozer.

Neden "ulasilabilir": stok Samsung blob seti bazi kutuphaneleri (arccamera,
quram, secface, samsungearcare ...) hic icermiyor, ama bu dosyalar hicbir
yerden yuklenmiyor — olu agirlik. Onlari da hata saymak gercek sorunlari
gurultuye bogar. Kok kumesi: bin/xbin/vendor/bin + hw/egl/soundfx/drm modulleri
+ rc/xml/conf icinde adi gecen .so'lar. Oradan DT_NEEDED ile yuruyoruz.

Ayrica sembol seviyesinde de denetler: ulasilabilir bir dosyanin UND sembolu
hicbir kutuphanede yoksa bu da ayni sekilde sessiz olumdur (BIND_NOW ile).

Kullanim:
  elf-kapanis.py <system-agaci>            # cozulen agac (debugfs rdump cikisi)
  elf-kapanis.py <system-agaci> --sembol   # UND sembol denetimini de yap
"""
import os
import re
import struct
import subprocess
import sys
import collections

# ld.config.txt: namespace.default.search.paths = /system/${LIB}:/vendor/${LIB}
LIBDIR = ["lib", "vendor/lib"]
# dlopen ile yuklenen modul dizinleri (kok kumesine girer)
MODUL_DIZIN = ["lib/hw", "vendor/lib/hw", "lib/egl", "vendor/lib/egl",
               "lib/soundfx", "vendor/lib/soundfx", "lib/drm", "vendor/lib/drm"]
IKILI_DIZIN = ["bin", "xbin", "vendor/bin"]


def _elf_baslik(b):
    if b[:4] != b"\x7fELF" or b[4] != 1 or b[5] != 1:
        return None
    (e_phoff, _e_shoff, e_phentsize, e_phnum,
     _e_shentsize, _e_shnum, _e_shstrndx) = \
        struct.unpack_from("<II", b, 0x1c) + struct.unpack_from("<HH", b, 0x2a) + \
        struct.unpack_from("<HHH", b, 0x2e)
    return e_phoff, e_phentsize, e_phnum


def elf_bag(yol):
    """DT_NEEDED listesi (yoksa None)."""
    try:
        b = open(yol, "rb").read()
    except OSError:
        return None
    h = _elf_baslik(b)
    if not h:
        return None
    e_phoff, e_phentsize, e_phnum = h
    dyn = None
    yuk = []
    for i in range(e_phnum):
        t = struct.unpack_from("<8I", b, e_phoff + i * e_phentsize)
        if t[0] == 2:                      # PT_DYNAMIC
            dyn = (t[1], t[4])
        elif t[0] == 1:                    # PT_LOAD
            yuk.append((t[1], t[2], t[4]))
    if not dyn:
        return []
    off, sz = dyn
    kayit = []
    for o in range(off, off + sz, 8):
        tag, val = struct.unpack_from("<iI", b, o)
        if tag == 0:
            break
        kayit.append((tag, val))
    strtab = next((v for t, v in kayit if t == 5), None)
    if strtab is None:
        return []
    def v2o(v):
        for po, pv, pf in yuk:
            if pv <= v < pv + pf:
                return po + (v - pv)
        return None
    so = v2o(strtab)
    if so is None:
        return []
    def dz(no):
        e = b.index(b"\0", so + no)
        return b[so + no:e].decode("latin1")
    return [dz(v) for t, v in kayit if t == 1]


def _semboller(yol):
    """(saglanan, cozulmeyen) sembol adlari. readelf yoksa (None, None).

    Iki eleme yapilir, ikisi de olculerek dogrulandi:

    - WEAK UND semboller ATLANIR. Zayif tanimsiz sembol tanimsiz kalsa da
      baglama hatasi vermez, 0'a cozulur. Ornek: ASAN enstrumantasyonunun
      __asan_init'i (libmedia, libminijail), linker'in __loader_* kancalari
      (adbd, libdl), C++ thread_local guard'lari (_ZTH*).

    - Yalnizca DINAMIK olarak baglanan dosyalar denetlenir. Statik ikililerin
      (or. bin/adbd: "statically linked", .dynamic bolumu yok) UND kayitlari
      zaten cozulmustur.

    - Hicbir relocation'in gostermedigi UND kaydi ATLANIR. Boyle bir sembol
      yukleyiciyi hic mesgul etmez. Olcum: bin/linker'da __dl_posix_memalign
      UND kayitli ama `readelf -r` sifir relocation dondurur; linker zaten
      dinamik yukleyicinin kendisidir ve __dl_* adlarini kendi ic
      tablosundan cozer.
    """
    try:
        b = open(yol, "rb").read(64)
    except OSError:
        return None, None
    if b[:4] != b"\x7fELF":
        return None, None
    if len(b) >= 20 and struct.unpack_from("<H", b, 16)[0] != 3:  # ET_DYN
        return None, None
    try:
        o = subprocess.run(["readelf", "-sW", yol], capture_output=True,
                           text=True, timeout=120).stdout
        r = subprocess.run(["readelf", "-rW", yol], capture_output=True,
                           text=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError):
        return None, None

    # relocation'larin dokundugu adlar
    yerine = set()
    for ln in r.splitlines():
        f = ln.split()
        if len(f) >= 5 and f[2].startswith("R_ARM"):
            yerine.add(f[4].split("@")[0])

    sag, und = set(), set()
    for ln in o.splitlines():
        f = ln.split()
        if len(f) >= 8 and f[0].endswith(":"):
            # <Num>: <Value> <Size> <Type> <Bind> <Vis> <Ndx> <Name>
            baglama, ndx, ad = f[4], f[6], f[7].split("@")[0]
            if not ad or ad.startswith("$"):
                continue
            if ndx == "UND":
                if baglama != "WEAK" and ad in yerine:
                    und.add(ad)
            elif ndx != "ABS":
                sag.add(ad)
    return sag, und


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    kok = sys.argv[1]
    sembol_denetimi = "--sembol" in sys.argv
    if not os.path.isdir(kok):
        print(f"dizin yok: {kok}", file=sys.stderr)
        return 2

    # --- saglanan kutuphaneler -------------------------------------------
    saglanan = {}
    for d in LIBDIR:
        p = os.path.join(kok, d)
        if not os.path.isdir(p):
            continue
        for f in os.listdir(p):
            fp = os.path.join(p, f)
            if os.path.isfile(fp) or os.path.islink(fp):
                saglanan.setdefault(f, fp)

    # --- kok kumesi -------------------------------------------------------
    kokler = set()
    for d in IKILI_DIZIN:
        p = os.path.join(kok, d)
        if not os.path.isdir(p):
            continue
        for f in os.listdir(p):
            fp = os.path.join(p, f)
            if os.path.isfile(fp) and not os.path.islink(fp):
                kokler.add(fp)
    for d in MODUL_DIZIN:
        p = os.path.join(kok, d)
        if not os.path.isdir(p):
            continue
        for f in os.listdir(p):
            if f.endswith(".so"):
                kokler.add(os.path.join(p, f))
    for dizin, _, dosyalar in os.walk(kok):
        for f in dosyalar:
            if not f.endswith((".rc", ".xml", ".conf", ".cfg")):
                continue
            try:
                s = open(os.path.join(dizin, f), errors="replace").read()
            except OSError:
                continue
            for m in re.finditer(r'([\w.\-+]+\.so)\b', s):
                if m.group(1) in saglanan:
                    kokler.add(saglanan[m.group(1)])

    # --- erisim (BFS) -----------------------------------------------------
    eris = set()
    kuyruk = list(kokler)
    while kuyruk:
        fp = kuyruk.pop()
        if fp in eris:
            continue
        eris.add(fp)
        for ad in elf_bag(fp) or []:
            if ad in saglanan and saglanan[ad] not in eris:
                kuyruk.append(saglanan[ad])

    print(f"saglanan kutuphane : {len(saglanan)}")
    print(f"kok sayisi         : {len(kokler)}")
    print(f"erisilebilen ELF   : {len(eris)}")

    # --- 1. eksik DT_NEEDED ----------------------------------------------
    eksik = collections.OrderedDict()
    for fp in sorted(eris):
        for ad in elf_bag(fp) or []:
            if ad not in saglanan:
                eksik.setdefault(ad, []).append(os.path.relpath(fp, kok))

    hata = 0
    print("\n== 1. DT_NEEDED kapanisi ==")
    if not eksik:
        print("   OK  erisilebilen her bag cozuluyor")
    else:
        hata = 1
        for ad, kullanan in eksik.items():
            print(f"   X  {ad}")
            for k in sorted(set(kullanan))[:5]:
                print(f"        <- {k}")
    print(f"   (olu agirlik: {sum(1 for v in saglanan.values() if v not in eris)}"
          f" kutuphane hic yuklenmiyor)")

    # --- 2. cozulemeyen sembol -------------------------------------------
    if sembol_denetimi:
        print("\n== 2. UND sembol cozumu (readelf) ==")
        tum = set()
        for ad, fp in saglanan.items():
            s, _ = _semboller(fp)
            if s:
                tum |= s
        if not tum:
            print("   .  readelf sonuc vermedi, atlandi")
        else:
            sorun = collections.OrderedDict()
            for fp in sorted(eris):
                _, u = _semboller(fp)
                if not u:
                    continue
                e = u - tum
                if e:
                    sorun[os.path.relpath(fp, kok)] = sorted(e)
            if not sorun:
                print("   OK  erisilebilen her sembol cozuluyor")
            else:
                hata = 1
                for f, e in sorun.items():
                    print(f"   X  {f} ({len(e)})")
                    for x in e[:8]:
                        print(f"        {x}")
                    if len(e) > 8:
                        print(f"        ... +{len(e)-8}")

    print()
    if hata:
        print("SONUC: SESSIZ YUKLEYICI HATASI VAR")
        return 1
    print("SONUC: yukleyici zinciri saglam")
    return 0


if __name__ == "__main__":
    sys.exit(main())
