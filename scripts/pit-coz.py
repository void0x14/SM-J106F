#!/usr/bin/env python3
"""Samsung/SPRD PIT (Partition Information Table) cozucu.

Iki girdi bicimini de okur:
  1. ham .pit ikili dosyasi (magic 0x12349876) — stok firmware'in CSC tar'i icinde gelir
  2. `heimdall print-pit` metin ciktisi — cihaz download mode'dayken alinir

Ikisi de ayni alanlari verir; bu betik tek bir tabloya indirir. Amac:
BOARD_*IMAGE_PARTITION_SIZE degerlerini cihazin GERCEK tablosuyla
karsilastirmak — cihaz bagli olmadan da yapilabilir.

Bicim (kaynak: samsung-loki/samsung-docs PIT.md, FergusInLondon/PitParser):
  28 bayt baslik: magic u32 | girdi sayisi u32 | gang adi 8s | proje adi 8s | rezerve u32
  ardindan her girdi 132 bayt:
    binary_type u32, device_type u32, id u32, attributes u32, update_attrs u32,
    block_size u32, block_count u32, file_offset u32, file_size u32,
    name 32s, filename 32s, delta 32s

Surum ayrimi: blok boyutlari esitse v1 (block_size * block_count),
farkliysa v2 (block_size = baslangic blogu, boyut = block_count * 512).
Bu cihazda (olculdu) v2: 32 girdi, bloklar 512 bayt.

Kullanim:
  pit-coz.py <pit-dosyasi>            # insan okur tablo
  pit-coz.py <pit-dosyasi> --tsv      # makine okur: ad<TAB>bayt
  pit-coz.py <pit-dosyasi> --json
"""
import json
import struct
import sys

MAGIC = 0x12349876
BASLIK = 28
GIRDI = 132
BLOK = 512


def ham_pit(d):
    """Ham .pit ikilisini girdi listesine cevirir. Degilse None."""
    if len(d) < BASLIK or struct.unpack_from("<I", d, 0)[0] != MAGIC:
        return None
    sayi = struct.unpack_from("<I", d, 4)[0]
    if sayi == 0 or BASLIK + sayi * GIRDI > len(d):
        return None
    gang = d[8:16].rstrip(b"\0").decode(errors="replace")
    proje = d[16:24].rstrip(b"\0").decode(errors="replace")
    girdiler = []
    for i in range(sayi):
        (bt, dt, pid, attr, upd, bs, bc, fo, fs,
         name, fname, delta) = struct.unpack_from("<9I32s32s32s", d, BASLIK + i * GIRDI)
        girdiler.append({
            "binary_type": bt, "device_type": dt, "id": pid,
            "attributes": attr, "update_attrs": upd,
            "block_size": bs, "block_count": bc,
            "file_offset": fo, "file_size": fs,
            "name": name.rstrip(b"\0").decode(errors="replace"),
            "filename": fname.rstrip(b"\0").decode(errors="replace"),
        })
    # v2 ayrimi: blok boyutlari farkliysa "block_size" alani baslangic blogudur.
    v2 = len({g["block_size"] for g in girdiler}) > 1
    for g in girdiler:
        g["baslangic_blok"] = g["block_size"] if v2 else g["file_offset"]
        g["boyut"] = g["block_count"] * BLOK if v2 else g["block_size"] * g["block_count"]
    return {"surum": 2 if v2 else 1, "gang": gang, "proje": proje, "girdiler": girdiler}


def metin_pit(d):
    """`heimdall print-pit` metin ciktisini girdi listesine cevirir."""
    s = d.decode(errors="replace")
    if "Partition Name:" not in s:
        return None
    girdiler = []
    for blok in s.split("--- Entry #")[1:]:
        def alan(ad):
            for satir in blok.splitlines():
                satir = satir.strip()
                if satir.startswith(ad + ":"):
                    return satir[len(ad) + 1:].strip()
            return None
        ad = alan("Partition Name")
        if not ad:
            continue
        sayi = alan("Partition Block Count")
        if sayi is None:
            continue
        # Blok boyutu: MMC -> 512, UFS -> 4096 (FlashAction.cpp:331-334)
        ufs = "(UFS)" in (alan("Device Type") or "")
        girdiler.append({
            "name": ad, "block_count": int(sayi),
            "boyut": int(sayi) * (4096 if ufs else BLOK),
            "device_type": 3 if ufs else 2,
        })
    return {"surum": 0, "girdiler": girdiler} if girdiler else None


def coz(yol):
    d = open(yol, "rb").read()
    return ham_pit(d) or metin_pit(d)


def main(argv):
    if len(argv) < 2:
        print(__doc__.split("Kullanim:")[-1].strip(), file=sys.stderr)
        return 2
    yol = argv[1]
    bicim = argv[2] if len(argv) > 2 else ""
    try:
        p = coz(yol)
    except OSError as e:
        print(f"okunamadi: {e}", file=sys.stderr)
        return 2
    if p is None:
        print(f"PIT ayristirilamadi: {yol}\n"
              f"  ne ham .pit (magic 0x{MAGIC:08x}) ne de print-pit metni.",
              file=sys.stderr)
        return 1

    if bicim == "--json":
        print(json.dumps(p, ensure_ascii=False, indent=2))
        return 0
    if bicim == "--tsv":
        for g in p["girdiler"]:
            print(f"{g['name']}\t{g['boyut']}")
        return 0
    if bicim == "--print-pit":
        # heimdall 'print-pit' metin bicimi. Neden gerekli: koruma
        # (govde/j106f-flash.mjs pitBolumBoyu) bolum adini ve Device Type'i
        # bu bicimden okur; ham .pit ikilisini okumaz. Ayni PIT'i iki ayri
        # yoldan ayni sonuca baglamak icin.
        #
        # Alan sirasi ve adlari KAYNAKTAN alindi
        # (/tmp/hd/Heimdall-v2.2.2/heimdall/source/Interface.cpp:208-320):
        #   Binary Type, Device Type, Identifier, Attributes, Update Attributes,
        #   Partition Block Size/Offset, Partition Block Count,
        #   File Offset (Obsolete), File Size (Obsolete),
        #   Partition Name, Flash Filename, FOTA Filename
        # Cihazin gercek degerleri yazilir; sabit metin degil.
        # Enum degerleri KAYNAKTAN (libpit/source/libpit.h:53-79):
        #   binary: 0 AP, 1 CP
        #   device: 0 OneNAND, 1 File/FAT, 2 MMC, 3 All (?), 8 UFS
        #   attr  : bit0 Read/Write, bit1 STL
        #   update: bit0 FOTA, bit1 Secure
        adlar = {0: "OneNAND", 1: "File/FAT", 2: "MMC", 3: "All (?)", 8: "UFS"}
        ikili = {0: "AP", 1: "CP"}
        print("--- PIT Header ---")
        print(f"Entry Count: {len(p['girdiler'])}")
        print(f"Unknown string: {p.get('gang', '')}")
        print(f"CPU/bootloader tag: {p.get('proje', '')}")
        print(f"Logic unit count: {len(p['girdiler'])}")
        for i, g in enumerate(p["girdiler"]):
            dt = g.get("device_type", 2)
            attr = g.get("attributes", 0)
            upd = g.get("update_attrs", 0)
            attr_metin = ("STL " if attr & 2 else "") + ("Read/Write" if attr & 1 else "Read-Only")
            if upd:
                upd_metin = f" ({'FOTA, Secure' if upd & 3 == 3 else 'FOTA' if upd & 1 else 'Secure'})"
            else:
                upd_metin = ""
            print()
            print(f"--- Entry #{i} ---")
            print(f"Binary Type: {g.get('binary_type', 0)} ({ikili.get(g.get('binary_type', 0), 'Unknown')})")
            print(f"Device Type: {dt} ({adlar.get(dt, 'Unknown')})")
            print(f"Identifier: {g.get('id', i)}")
            print(f"Attributes: {attr} ({attr_metin})")
            print(f"Update Attributes: {upd}{upd_metin}")
            print(f"Partition Block Size/Offset: {g.get('baslangic_blok', 0)}")
            print(f"Partition Block Count: {g['block_count']}")
            print(f"File Offset (Obsolete): {g.get('file_offset', 0)}")
            print(f"File Size (Obsolete): {g.get('file_size', 0)}")
            print(f"Partition Name: {g['name']}")
            print(f"Flash Filename: {g.get('filename') or g['name'] + '.img'}")
            print("FOTA Filename: ")
        print()
        return 0

    print(f"dosya       : {yol}")
    print(f"girdi sayisi: {len(p['girdiler'])}")
    print(f"bicim       : " + ("ham .pit (v%d)" % p["surum"] if p["surum"] else "print-pit metni"))
    print()
    print(f"  {'#':>3}  {'AD':<16} {'BLOK':>10} {'BASLANGIC':>12} {'BOYUT(B)':>12} {'MiB':>9}")
    for i, g in enumerate(p["girdiler"]):
        mb = g["boyut"] / 1048576
        print(f"  {i:>3}  {g['name']:<16} {g['block_count']:>10} "
              f"{g.get('baslangic_blok', 0):>12} {g['boyut']:>12} {mb:>9.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
