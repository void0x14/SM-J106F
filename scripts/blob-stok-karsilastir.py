#!/usr/bin/env python3
"""blob-stok-karsilastir.py — vendor blob'larimizin stok sistem imajindaki
kopyalariyla BIREBIR ayni oldugunu kanitlar.

Neden: vendor/samsung/j1minivelte/proprietary altindaki dosyalar stok cihazdan
cekilir. Bir blob eksik, eski ya da yanlis surumse hata cihazda ve SESSIZ cikar
(ornek: DT_NEEDED uyusmazligi -> linker yuklemez, log tek satir bile basmaz).
Kaynak imaj elimizde oldugu icin her blob sha256 ile dogrulanabilir.

Yontem: stok system.img ext4 -> debugfs ile dosya cikarma yerine 'debugfs dump'
kullanilir. Cikarilan kopya ile blob karsilastirilir.

Cikis kodu: farkli dosya varsa 1. Bu bir HATA DEGILDIR — stok imaj baska bir
yapidan (or. APJ3) geliyorsa farklar beklenir. Ayrinti: docs/BLOB-KOKEN.md.

Kullanim:
  blob-stok-karsilastir.py <stok-system.img> <proprietary-dizini> [--liste]
  blob-stok-karsilastir.py <stok-system.img> <proprietary-dizini> --koken
      --koken: farkli cikan dosyalarin ICINDEN gomulu derleme tarihini
      cikarir. Boylece "farkli" sonucunun sebebi (surum kaymasi mi, bozulma
      mi) tahminle degil olcumle ayrilir. Stok imaj baska bir yapidan
      geliyorsa tarihler sistematik olarak kayar; bozulmada kayma olmaz.

Not: sparse imaj ham ext4'e cevrilir (~2.5 GB gecici). Betik bu dosyayi
cikista siler.
"""
import hashlib
import os
import re
import struct
import subprocess
import sys

# "Mar  7 2018" bicimli gomulu derleme tarihi (__DATE__ / asm .ascii).
# ELF rodata'da ham metin olarak durur; sembol tablosu striplenmis olsa da kalir.
AY_ADI = {b"Jan": 1, b"Feb": 2, b"Mar": 3, b"Apr": 4, b"May": 5, b"Jun": 6,
          b"Jul": 7, b"Aug": 8, b"Sep": 9, b"Oct": 10, b"Nov": 11, b"Dec": 12}
TARIH_RE = re.compile(
    rb"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-9][0-9] 20[0-9]{2}")

# Stok system.img icinde blob'larin bulundugu onekler.
ONEKLER = ("system/bin/", "system/lib/", "system/etc/", "system/vendor/",
           "system/xbin/", "system/usr/")

# Android sparse imaj sihirli sayisi (system/core/libsparse/sparse_format.h).
SPARSE_MAGIC = 0xED26FF3A


def ham_ext4(img):
    """Stok system.img genelde Android sparse imajdir; debugfs ham ext4 ister.

    Sparse ise simg2img ile ham hale cevirir ve gecici dosya yolunu dondurur.
    Zaten ham ext4 ise yolu oldugu gibi dondurur.

    DIKKAT: donusturulen dosya ~2.5 GB'dir. Cagiran taraf silmekle yukumludur;
    birakmak her kosuda disk doldurur (olculdu).
    """
    with open(img, "rb") as f:
        bas = f.read(4)
    if len(bas) == 4 and struct.unpack("<I", bas)[0] == SPARSE_MAGIC:
        import tempfile
        ham = os.path.join(tempfile.mkdtemp(prefix="hamsys."),
                           os.path.basename(img) + ".raw")
        subprocess.run(["simg2img", img, ham], check=True)
        return ham, True
    return img, False


def sha256(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for p in iter(lambda: f.read(1 << 20), b""):
            h.update(p)
    return h.hexdigest()


def buildid_araligi(d):
    """ELF icindeki .note.gnu.build-id bolumunun (off, size) araligini dondurur.

    Neden: ayni kaynaktan farkli bir derlemede dosya BIREBIR ayni olur; tek
    fark bu bolumdur. Olculdu: 100 'farkli' dosyanin cogu yalnizca bu 16 baytta
    ayrisiyor. Bu bolum yukleme aninda KULLANILMAZ (linker okumaz), yani iki
    dosya davranis olarak esdegerdir. Fark saymak yanlis alarm uretir.
    """
    if len(d) < 52 or d[:4] != b"\x7fELF":
        return None
    if d[4] == 1:      # 32-bit
        e_shoff, = struct.unpack_from("<I", d, 32)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", d, 46)
    elif d[4] == 2:    # 64-bit
        e_shoff, = struct.unpack_from("<Q", d, 40)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", d, 58)
    else:
        return None
    if e_shoff == 0 or e_shnum == 0 or e_shoff + e_shnum * e_shentsize > len(d):
        return None
    shs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        if d[4] == 1:
            nm, typ, flags, addr, off, size = struct.unpack_from("<6I", d, o)
        else:
            nm, typ, flags, addr, off, size = struct.unpack_from("<2I4Q", d, o)
        shs.append((nm, typ, off, size))
    if e_shstrndx >= len(shs):
        return None
    stroff = shs[e_shstrndx][2]
    for nm, typ, off, size in shs:
        if typ != 7:   # SHT_NOTE
            continue
        try:
            e = d.index(b"\0", stroff + nm)
            ad = d[stroff + nm:e].decode()
        except (ValueError, UnicodeDecodeError):
            continue
        if ad == ".note.gnu.build-id":
            return (off, size)
    return None


def esdeger_mi(a, b):
    """Iki dosyayi karsilastirir. (sonuc, aciklama) dondurur.

    sonuc: 'ayni' | 'buildid' | 'farkli'
    """
    if os.path.getsize(a) != os.path.getsize(b):
        return "farkli", f"boyut {os.path.getsize(a)} != {os.path.getsize(b)}"
    with open(a, "rb") as f:
        da = f.read()
    with open(b, "rb") as f:
        db = f.read()
    if da == db:
        return "ayni", ""
    aralik = buildid_araligi(da)
    if aralik is None:
        return "farkli", "build-id bolumu yok, icerik farkli"
    off, size = aralik
    # build-id bolumunu ayni degerle degistirip tekrar karsilastir.
    da2 = da[:off] + db[off:off + size] + da[off + size:]
    if da2 == db:
        return "buildid", f".note.gnu.build-id ({size} bayt)"
    return "farkli", "build-id disinda da fark var"


def gomulu_tarihler(veri):
    """Dosyanin icindeki gomulu derleme tarihlerini (yil, ay) olarak dondurur.

    Neden: iki blob ayni boyutta ama icerigi farkli oldugunda 'bozuk mu, baska
    surum mu' sorusu kalir. Derleyicinin __DATE__ makrosu ile gomdugu tarih
    hangi yapidan geldigini dogrudan soyler.
    """
    out = []
    for m in TARIH_RE.finditer(veri):
        yil = int(m.group(0)[-4:])
        ay = AY_ADI[m.group(1)]
        out.append((yil, ay))
    return out


def stok_dosya_cikar(img, ic_yol, hedef):
    """debugfs ile imajdan tek dosya cikarir. Basariliysa True."""
    r = subprocess.run(
        ["debugfs", "-R", f'dump -p "{ic_yol}" "{hedef}"', img],
        capture_output=True, text=True)
    return r.returncode == 0 and os.path.isfile(hedef) and os.path.getsize(hedef) > 0


def main(argv):
    if len(argv) < 3:
        print(__doc__.split("Kullanim:")[-1].strip(), file=sys.stderr)
        return 2
    img, prop = argv[1], argv[2]
    liste = "--liste" in argv
    koken = "--koken" in argv

    if not os.path.isfile(img):
        print(f"stok imaj yok: {img}", file=sys.stderr)
        return 2

    ham, cevrildi = ham_ext4(img)
    if cevrildi:
        print(f"sparse imaj ham ext4'e cevrildi: {ham}")
        img = ham

    import shutil
    import tempfile
    tmp = tempfile.mkdtemp(prefix="blobchk.")

    def temizle():
        shutil.rmtree(tmp, ignore_errors=True)
        if cevrildi:
            # ~2.5 GB'lik ham kopya. Birakmak disk doldurur (olculdu).
            shutil.rmtree(os.path.dirname(ham), ignore_errors=True)

    ayni = buildid = farkli = eksik = 0
    farkli_liste = []
    buildid_liste = []
    eksik_liste = []
    koken_liste = []      # (ic_yol, bizim tarihler, stok tarihler)

    for kok, _, dosyalar in os.walk(prop):
        for ad in dosyalar:
            yerel = os.path.join(kok, ad)
            rel = os.path.relpath(yerel, prop)          # or. bin/at_distributor
            # Stok system.img'in KOKU zaten /system'dir: ic yollar "/bin/...",
            # "/lib/..." seklindedir; "system/" oneki YANLIS olur (olculdu).
            ic = "/" + rel.replace(os.sep, "/")
            hedef = os.path.join(tmp, ad)
            if os.path.exists(hedef):
                os.unlink(hedef)

            if not stok_dosya_cikar(img, ic, hedef):
                eksik += 1
                eksik_liste.append(ic)
                continue

            sonuc, aciklama = esdeger_mi(yerel, hedef)
            if sonuc == "ayni":
                ayni += 1
            elif sonuc == "buildid":
                buildid += 1
                buildid_liste.append(ic)
            else:
                farkli += 1
                farkli_liste.append((ic, os.path.getsize(yerel),
                                     os.path.getsize(hedef), aciklama))
                if koken:
                    with open(yerel, "rb") as f:
                        tb = gomulu_tarihler(f.read())
                    with open(hedef, "rb") as f:
                        ts = gomulu_tarihler(f.read())
                    if tb or ts:
                        koken_liste.append((ic, tb, ts))

    print(f"== vendor blob'lari vs stok system.img ==")
    print(f"  birebir ayni        : {ayni}")
    print(f"  yalniz build-id     : {buildid}   (davranis esdeger, linker bu bolumu okumaz)")
    print(f"  GERCEKTEN FARKLI    : {farkli}")
    print(f"  stokta yok          : {eksik}")
    print(f"  toplam              : {ayni + buildid + farkli + eksik}")
    print()

    if farkli_liste:
        print("  GERCEKTEN FARKLI dosyalar:")
        for ic, y, s, ac in farkli_liste[:40]:
            print(f"    {ic}  {y} vs {s} bayt — {ac}")
        print()
    if buildid_liste:
        print("  yalniz build-id farki (ilk 20):")
        for ic in buildid_liste[:20]:
            print(f"    {ic}")
        print()
    if eksik_liste:
        print("  stokta bulunamayan (yol farkli olabilir):")
        for ic in eksik_liste[:40]:
            print(f"    {ic}")
        print()

    if koken and koken_liste:
        print("  farkli dosyalarin ICINDEKI gomulu derleme tarihi:")
        for ic, tb, ts in koken_liste:
            fark = sorted(set(tb) ^ set(ts))
            b = ", ".join(f"{y}-{m:02d}" for y, m in sorted(set(tb))) or "-"
            s = ", ".join(f"{y}-{m:02d}" for y, m in sorted(set(ts))) or "-"
            print(f"    {ic}")
            print(f"        bizim blob : {b}")
            print(f"        stok yapi  : {s}")
        print()

    temizle()
    if liste:
        return 0
    return 0 if (farkli == 0) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
