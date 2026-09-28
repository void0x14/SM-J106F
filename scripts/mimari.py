#!/usr/bin/env python3
"""Her arguman icin ELF e_machine degerini (ondalik) basar.

Kullanildigi yer: gapps-denetle.sh mimari uyumunu dogrularken. Paketin
.so'lari ile cihaz agacindaki ELF'ler ayni e_machine'e sahip olmali;
farkliysa bionic yukleyici onlari hic acmaz.

Sabit mimari adi/listesi YOKTUR; yalnizca basliktaki sayi okunur.
ELF olmayan dosya icin 'ELF-degil', okunamayan icin 'okunamadi' basar.
"""
import struct
import sys


def e_machine(yol):
    try:
        with open(yol, "rb") as f:
            d = f.read(20)
    except OSError:
        return "okunamadi"
    if len(d) < 20 or d[:4] != b"\x7fELF":
        return "ELF-degil"
    sira = "<" if d[5] == 1 else ">"
    return str(struct.unpack(sira + "H", d[18:20])[0])


def main(argv):
    if len(argv) < 2:
        print("kullanim: mimari.py <elf> [elf...]", file=sys.stderr)
        return 2
    for yol in argv[1:]:
        print(e_machine(yol))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
