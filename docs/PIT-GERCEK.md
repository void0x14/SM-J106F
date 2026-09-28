# Gerçek PIT — ölçülmüş bölüm tablosu

Bu dosya, J106F'in **kendi** bölüm tablosunu ölçer. Artık tahmin yok: PIT
Samsung'un stok firmware'inin içinden çıkarıldı ve repoda duruyor.

## Kaynak

| | |
|---|---|
| Stok firmware | `KSA-J106FJVU0APJ3-20161102091153.zip` (1.490.482.384 B) |
| Nereden | archive.org, öğe `KSAJ106FJVU0APJ320161102091153` |
| sha256 (zip) | `fc994fc8a68a8ca0af59c325f9b7ec2802dada30114e1252fc1132de5244c349` |
| PIT dosyası | `CSC_OJV_J106FOJV0APJ4_..._user_low_ship.tar.md5` içinde |
| PIT adı | `J1MINIVELTE_MEA_JV.pit` |
| PIT boyut / sha256 | 5.276 B / `458fef6dd8591131fa7db24d1d686d7aaa64e78ccf45c36b75df1e6e3ab24ec4` |
| PIT başlığı | magic `0x12349876`, 32 girdi, gang `COM_TAR2`, proje `SPRD8735` |

```bash
bash scripts/stok-indir.sh          # zip'i indirir, AP/BL/CP/CSC açar, PIT'i çıkarır
python3 scripts/pit-coz.py docs/pit/J1MINIVELTE_MEA_JV.pit
bash scripts/pit-dogrula.sh docs/pit/J1MINIVELTE_MEA_JV.pit
```

## Ölçülen tablo

Bölüm sırası ve boyutlar PIT'ten; **başlangıç blokları** bitişikliği kanıtlar.

| # | Ad | Başlangıç blok | Blok | Boyut (B) | MiB |
|---|---|---|---|---|---|
| 0 | BOOT | 0 | 1024 | 524.288 | 0,50 |
| 1 | BOOT2 | 0 | 2048 | 1.048.576 | 1,00 |
| 2 | PIT | 1024 | 1024 | 524.288 | 0,50 |
| 3 | MD5HDR | 2048 | 6144 | 3.145.728 | 3,00 |
| 4 | SBOOT | 8192 | 4096 | 2.097.152 | 2,00 |
| 5 | SBOOT2 | 12288 | 4096 | 2.097.152 | 2,00 |
| 6 | l_fixnv1 | 16384 | 2048 | 1.048.576 | 1,00 |
| 7 | l_fixnv2 | 18432 | 2048 | 1.048.576 | 1,00 |
| 8 | pm_sys | 20480 | 2048 | 1.048.576 | 1,00 |
| 9 | rsvdfixnv1 | 22528 | 2048 | 1.048.576 | 1,00 |
| 10 | l_ldsp | 24576 | 8192 | 4.194.304 | 4,00 |
| 11 | l_modem | 32768 | 32768 | 16.777.216 | 16,00 |
| 12 | l_gdsp | 65536 | 8192 | 4.194.304 | 4,00 |
| 13 | l_warm | 73728 | 8192 | 4.194.304 | 4,00 |
| 14 | FOTA_SIG | 81920 | 2048 | 1.048.576 | 1,00 |
| 15 | l_runtimenv1 | 83968 | 2048 | 1.048.576 | 1,00 |
| 16 | l_runtimenv2 | 86016 | 2048 | 1.048.576 | 1,00 |
| 17 | td_runtimenv1 | 88064 | 2048 | 1.048.576 | 1,00 |
| 18 | td_runtimenv2 | 90112 | 2048 | 1.048.576 | 1,00 |
| 19 | PARAM | 92160 | 4096 | 2.097.152 | 2,00 |
| 20 | **efs** | 96256 | 40960 | 20.971.520 | 20,00 |
| 21 | **prodnv** | 137216 | 10240 | 5.242.880 | 5,00 |
| 22 | RESERVED2 | 147456 | 11264 | 5.767.168 | 5,50 |
| 23 | **KERNEL** | 158720 | 40960 | **20.971.520** | 20,00 |
| 24 | **RECOVERY** | 199680 | 40960 | **20.971.520** | 20,00 |
| 25 | PERSISTENT | 240640 | 1024 | 524.288 | 0,50 |
| 26 | PERSDATA | 241664 | 18432 | 9.437.184 | 9,00 |
| 27 | STEADY | 260096 | 2048 | 1.048.576 | 1,00 |
| 28 | CACHE | 262144 | 409600 | 209.715.200 | 200,00 |
| 29 | SYSTEM | 671744 | 5.668.864 | 2.902.458.368 | 2768,00 |
| 30 | HIDDEN | 6340608 | 81920 | 41.943.040 | 40,00 |
| 31 | userdata | 6422528 | 0 | 0 | 0,00 |

`userdata` boyutu 0: cihazın PIT'i onu kalan tüm eMMC olarak tanımlar; TWRP/AOSP
bu bölümü formatlar. Bu yüzden 0 bir hata değil.

## Çözülen çelişki: RECOVERY boyutu

Tartışılan üç aday vardı. Gerçek PIT **20.971.520** diyor — `sharkls-common`'dan
miras gelen değer.

| Aday | Değer | Kaynak | Sonuç |
|---|---|---|---|
| `sharkls-common/BoardConfigCommon.mk:56-57` | 20.971.520 | J3 2016 sınıfından miras | **doğru** |
| `fuckyousamsung` + yerel `kaynak/ref` TWRP ağacı | RECOVERY 26.214.400 / KERNEL 10.978.320 | elle yazılmış | **yanlış** |
| `twrpdtgen/android_device_samsung_j1minivelte` | 10.978.320 | `image_info.origsize` | **yapıntı** |

`twrpdtgen`'in 10.978.320 değeri bir bölüm boyutu değil: `device_tree.py:56`
`origsize` değerini `aik_manager.unpackimg(image)`'ten alır — yani **dump edilen
recovery imajının dosya boyutu**. `templates/BoardConfig.mk.jinja2:131-132` onu
hem BOOT hem RECOVERY'ye yazar. twrpdtgen hiç PIT okumaz.

Ek kanıt — blok hizası:

```
20.971.520 / 512 = 40960.0000   tam        <- gerçek
26.214.400 / 512 = 51200.0000   tam        <- fazla büyük
10.978.320 / 512 = 21442.0312   TAM DEĞİL  <- dosya boyutu, sektör sayısı olamaz
```

10.978.320 = 16 × 686.145 ve 686.145 tek sayı → 512'ye bölünmez. Bir bölüm boyu
sektör hizalı olmak zorundadır. Bu tek başına twrpdtgen değerinin yapıntı olduğunu
kanıtlar.

## İmaj sığdırma

| İmaj | Boyut | Bölüm | Sınır | Sonuç |
|---|---|---|---|---|
| `boot.img` | 9.426.960 | KERNEL | 20.971.520 | sığar (45 %) |
| `recovery.img` | 17.291.280 | RECOVERY | 20.971.520 | sığar (82 %) |
| `dt.img` | 129.024 | — | boot.img içine gömülür | — |

`recovery.img` 17,29 MB; twrpdtgen'in 10,47 MB değeri kullanılsaydı **kendi
derlememiz bölüme sığmazdı**. `sharkls-common` değeri bu yüzden korunur.

## Stok imajlarla karşılaştırma

Stok AP tar'ından çıkarılan imajlar:

| İmaj | Stok boyut | Kernel | Ramdisk | Bizim boyut |
|---|---|---|---|---|
| `boot.img` | 10.048.528 | 5.231.776 | 4.682.996 | 9.426.960 |
| `recovery.img` | 10.974.224 | 5.231.776 | 5.609.077 | 17.291.280 |

Stok recovery imajı **10.974.224 B** — twrpdtgen'in 10.978.320 değeri buna çok
yakın. Yapıntı tezi böylece bağımsız olarak da doğrulanır: twrpdtgen bir *stok
recovery dump'ı* üzerinde koşmuş ve onun boyutunu yazmış.

## Bootloader cmdline'ı — ölçüldü

Stok `sboot.bin` (BL tar) içinde, `ATAG_CMDLINE` biçimlendirme dizesi:

```
 mem=1024M init=/init ram=1024M androidboot.hardware=sc8830
```

ve ayrı ayrı:

```
 console=ttyS1,115200n8 loglevel=7
 androidboot.mode=charger
 androidboot.bootloader=%s      (J106FJVU0APJ3)
```

Yani `androidboot.hardware=sc8830` **stok bootloader'dan geliyor** — kernel
`CONFIG_CMDLINE`'ına bağlı değil. Ama stok `j1minive3g-dt_defconfig` yine de onu
`CONFIG_CMDLINE`'da taşıyor ve `CONFIG_CMDLINE_EXTEND=y` ile birleştiriyor
(bkz. `docs/FLASH.md`). İkisi aynı anahtarı söylüyor; çakışma yok.

Doğrulanmış çekirdek içi dize karşılaştırması (inner gzip açıldı):

| Dize | Stok zImage | Bizim zImage |
|---|---|---|
| `androidboot.hardware=sc8830` | 0 | **2** |
| `androidboot.selinux=permissive` | 0 | **2** |
| `console=ttyS1,115200n8` | 2 | 2 |
| `initrd=0x80e00000` | 2 | **0** (kaldırıldı) |
| `mem=128M` | 2 | **0** (kaldırıldı) |
| `binder,hwbinder,vndbinder` | 0 | **1** |

Stok çekirdek `androidboot.hardware`'ı taşımıyor çünkü onu bootloader'dan
`CMDLINE_FROM_BOOTLOADER` ile alıyor. Biz `CMDLINE_EXTEND` kullanıyoruz ve
anahtarı çekirdeğe de yazıyoruz — bootloader ne yaparsa yapsın `ro.hardware`
doğru kurulur.

## Yedekleme boyutları — sabit değil, PIT'ten

`docs/FLASH.md` §6b'deki `dd` yedeği artık bu ölçülmüş değerleri kullanır:

| Bölüm | Boyut | Ne kaybı |
|---|---|---|
| `efs` | 20.971.520 | IMEI, şebeke |
| `l_modem` | 16.777.216 | RF kalibrasyonu |
| `l_fixnv2` | 1.048.576 | NV verisi |
| `prodnv` | 5.242.880 | ürün bilgisi |
| `PERSDATA` | 9.437.184 | kalıcı veri |
| `PARAM` | 2.097.152 | boot parametreleri |

## Gövde koruması ile uyum

`j106f-flash.mjs` yazmadan **önce** cihaza `heimdall print-pit` çalıştırır ve
imajın bölüme sığdığını doğrular (kapı 3b). PIT ayrıştırıcısı
(`pitBolumBoyu`, `j106f-flash.mjs:167`) bu gerçek PIT metniyle sınandı:

```
  ✔ KERNEL     koruma=20971520  gercek=20971520
  ✔ RECOVERY   koruma=20971520  gercek=20971520
  ✔ SYSTEM     koruma=2902458368  gercek=2902458368
  ✔ CACHE      koruma=209715200  gercek=209715200
  ✔ HIDDEN     koruma=41943040  gercek=41943040
  ✔ PERSDATA   koruma=9437184  gercek=9437184
  ✔ olmayan bolum -> null (reddeder)
```

`scripts/pit-coz.py` ham `.pit` ikilisini de, `heimdall print-pit` metnini de
okur; ikisi aynı 32 satırlık tabloyu verir (sınandı).

## Derleme yapılandırması ile fark

`pit-dogrula.sh` sonucu:

```
  ✔ CACHE      209715200 bayt — esit
  ✔ KERNEL     20971520 bayt — esit
  ✔ RECOVERY   20971520 bayt — esit
  ✔ SYSTEM     derleme 2147483648, cihaz 2902458368 — imaj sigar (derleme kucuk)
```

`SYSTEM`: derleme 2048 MiB, cihaz 2768 MiB. Derleme **küçük** olduğu için imaj
sığar; eksik kalan 720 MiB kullanılmaz. Daha büyük bir system.img gerekirse
`BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2902458368` yapılabilir — ama mevcut system
%41 dolu olduğundan gerek yok.

`BOARD_PERSISTIMAGE_PARTITION_SIZE := 10485760` **ölü** yapılandırmadır: bu
cihazda AOSP'nin `persist` bölümü yoktur (fstab'da `/persist` yok, derleme
`persist.img` üretmez). Cihazdaki `PERSDATA` ayrı bir bölümdür ve TWRP onu
`/persdata` olarak bağlar. İkisi eşleştirilmez.
