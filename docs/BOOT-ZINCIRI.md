# Boot zinciri — kaynaktan doğrulama

Boot blocker sınıfı: çekirdek açılır, `init` çalışır ama cihaz **açılmaz**; hiçbir
hata mesajı görünmez. En bilinen sebep `ro.hardware`'ın çözülememesidir. Bu
belge zinciri kaynaktan ve derlenmiş ikililerden doğrular.

## 1. Halka: cmdline → `androidboot.hardware` → `ro.hardware`

Etkin cmdline iki kaynaktan birleşir. Kernel 3.10 DT yolu
(`drivers/of/fdt.c:744-760`):

| Kconfig | `overwrite_incoming` | `read_dt_cmdline` | `concat_cmdline` |
|---|---|---|---|
| `CMDLINE_FORCE` | 1 | – | – |
| `CMDLINE_EXTEND` | 0 | 1 | 1 |
| `CMDLINE_FROM_BOOTLOADER` | 0 | 1 | 0 |

`CMDLINE_EXTEND` seçiliyken: `CONFIG_CMDLINE` yazılır, ardından DT
`/chosen bootargs` **eklenir**. Yani ikisi de etkin cmdline'da bulunur.

Ölçüm (derlenmiş `vmlinux`):

```
CONFIG_CMDLINE = androidboot.selinux=permissive androidboot.hardware=sc8830 console=ttyS1,115200n8
DT bootargs    = loglevel=1 init=/init root=/dev/ram0 rw
```

`strings vmlinux` bu cmdline'ı birebir gösterir. `androidboot.hardware=sc8830`
→ `init` bunu `ro.hardware=sc8830` yapar (`init.cpp` `import_kernel_nv`).

### ATAGS yolu da aynı sonucu verir

`arch/arm/kernel/atags_parse.c:128-134` `parse_tag_cmdline()`:

```c
#if defined(CONFIG_CMDLINE_EXTEND)
    strlcat(default_command_line, " ", ...);
    strlcat(default_command_line, tag->u.cmdline.cmdline, ...);
```

Aynı: `CONFIG_CMDLINE` + bootloader tag cmdline birleşir.

### Cihazın kendi bootloader'ı da bu değeri veriyor

`sboot.bin` / `sboot2.bin` içinde `androidboot.hardware=sc8830` ve `mem=1024M`
dizeleri var. Yani `ro.hardware` üç bağımsız kaynaktan da `sc8830` çıkar:
`CONFIG_CMDLINE`, bootloader tag, DT (DT'de yok ama gerekmiyor).

### Stok ile fark

Stok çekirdek (`stok/stokimg/boot.img`, açılmış): `CONFIG_CMDLINE_FROM_BOOTLOADER`,
`CONFIG_CMDLINE="root=/dev/ram0 rw initrd=0x80e00000,0x1f243f console=ttyS1,115200n8 init=/init mem=128M"`.
`androidboot.hardware` stok çekirdekte **yok**; değer bootloader'dan gelir.

Bizimki `CONFIG_CMDLINE`'a ekledi → bootloader'a bağımlılık azaldı.

Ölçülen farklar (yorum değil):

| | stok | bizim |
|---|---|---|
| cmdline modu | `FROM_BOOTLOADER` | `EXTEND` |
| `CONFIG_CMDLINE` | `... mem=128M` | `androidboot.selinux=permissive androidboot.hardware=sc8830 ...` |
| `androidboot.hardware` çekirdekte | yok | var |
| `mem=` çekirdekte | `128M` | yok |
| bootloader (`sboot.bin`) | `mem=1024M` | aynı bootloader |

`EXTEND` modunda `concat=1`: `CONFIG_CMDLINE` yazılır, bootloader/DT cmdline
arkasına **eklenir** — ikisi de etkin cmdline'da kalır. `FROM_BOOTLOADER`
modunda `concat=0`: DT `/chosen bootargs` cmdline'ı ezer
(`drivers/of/fdt.c:755-760`).

`mem=1024M` bootloader'dan gelir; cihazın gerçek RAM boyu DT `/memory`
`reg = 80000000 40000000` (1 GB) ile de bildirilir. Hangi yolun kazandığı
cihazda ölçülür (bkz. aşağıdaki sınır).

## 2. Halka: rc import grafiği

`ro.hardware=sc8830` ile `init.rc` şunları okur:

```
import /init.${ro.hardware}.rc                  -> /init.sc8830.rc        (var)
import /vendor/etc/init/hw/init.${ro.hardware}.rc -> /vendor/etc/init/hw/init.sc8830.rc (yok)
```

İkincisi **yok** ama ölümcül değil: `ImportParser::EndFile()`
(`system/core/init/import_parser.cpp:46-53`) başarısız import için
`PLOG(ERROR)` yazıp **devam eder**. `init.sc8830.rc` zaten ramdisk kökünde
olduğu için donanım servisleri tanımlı kalır.

Ölçüm: 19 rc dosyası ramdisk'te, `init.sc8830.rc` dahil.

## 3. Halka: ramdisk yerleşimi

`boot.img` ramdisk penceresi `0x01000000 + 3801974` = `0x013a0376`. DT'deki
`linux,initrd-start/end` bir **yer tutucudur**; LK `update_device_tree()` ile
boot anında gerçek adres/boyutla değiştirir. Bu yüzden denetlenen şey
`boot.img`'in yazdığı gerçek yerleşimdir, DT'deki sabit değer değil.

## Doğrulama komutu

```bash
python3 scripts/boot-zinciri.py \
  /home/void0x14/j106f/build/android/out/target/product/j1minivelte \
  /home/void0x14/j106f/build/android/kernel/samsung/j1minivelte
```

Sonuç: `SONUC: onyukleme zinciri saglam`.

## Servis zinciri

`scripts/init-denetle.py <system> - <ramdisk>`: 71 servis — her ikili yerinde,
etiketli, domain geçişi tanımlı. `SAGLAM`.
