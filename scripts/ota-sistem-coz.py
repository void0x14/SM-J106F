#!/usr/bin/env python3
# system.new.dat.br + system.transfer.list -> ham system.img
# Blok-OTA (ota-type=BLOCK) sistemini diske doker. sdat2img esdegeri.
#
# transfer.list bicimi (surum 3/4):
#   satir 1: surum
#   satir 2: toplam blok sayisi
#   satir 3,4: yazilacak/okunacak bayt ipuclari (kullanilmaz)
#   "erase <N>,<s>,<e>,..."  N tam sayi = N/2 adet (bas,bitis) araligi, silinecek
#   "new   <N>,<s>,<e>,..."  N tam sayi = N/2 adet aralik; hedef bloklar bu
#                            araliklara SIRAYLA, veri akisindan doldurulur
#   "zero  <N>,<s>,<e>,..."  araliklari sifirla
#
# Kritik nokta: sayidan sonra gelen degerler tek tek blok degil, (bas,bitis)
# CIFTIDIR. "new 2,0,1024" = blok [0,1024), yani 1024 blok.
import brotli, sys, os

br_yol, tl_yol, cikti = sys.argv[1], sys.argv[2], sys.argv[3]
BLK = 4096

satir = [s.strip() for s in open(tl_yol) if s.strip()]
surum = int(satir[0])
toplam_blok = int(satir[1])

def araliklar(alan):
    # alan: virgulle ayrilmis tam sayilar; ilk deger adet, sonrasi (bas,bitis) ciftleri
    v = [int(x) for x in alan.split(",")]
    n = v[0]
    degerler = v[1:1 + n]
    if len(degerler) != n:
        raise SystemExit("transfer.list bozuk: beklenen %d deger, %d var" % (n, len(degerler)))
    if n % 2:
        raise SystemExit("transfer.list bozuk: cift sayida deger gerekli")
    return [(degerler[i], degerler[i + 1]) for i in range(0, n, 2)]

komutlar = []
for s in satir[2:]:
    p = s.split(" ", 1)
    if len(p) != 2:
        continue
    komutlar.append((p[0], araliklar(p[1])))

veri = brotli.decompress(open(br_yol, "rb").read())
print("transfer surum", surum, "toplam blok", toplam_blok)
print("sikistirilmis sonrasi veri", len(veri), "bayt =", len(veri) // BLK, "blok")

yeni_blok = sum(e - s for k, ar in komutlar if k == "new" for s, e in ar)
print("new komutlarinin kapsadigi blok", yeni_blok)
if yeni_blok != len(veri) // BLK:
    raise SystemExit("UYUSMAZLIK: new blok %d != veri blok %d" % (yeni_blok, len(veri) // BLK))

with open(cikti, "wb") as o:
    o.truncate(toplam_blok * BLK)
    konum = 0
    for k, ar in komutlar:
        for s, e in ar:
            if k == "new":
                for b in range(s, e):
                    o.seek(b * BLK)
                    o.write(veri[konum:konum + BLK])
                    konum += BLK
            elif k == "zero":
                o.seek(s * BLK)
                o.write(b"\x00" * ((e - s) * BLK))
print("yazilan ham imaj", os.path.getsize(cikti), "bayt")
