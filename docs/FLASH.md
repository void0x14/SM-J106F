# Flash prosedürü — J106F

Bu dosya cihaza bir şey yazmadan **önce** okunur. Sıra atlanmaz.

## 0. Neden bu sıra

J106F'te fastboot yok; yazma yolu Odin/Heimdall download mode. Download mode'da
yanlış bir bölüme yanlış imaj yazmak cihazı tuğlaya çevirir. `efs`, `prodnv`,
`l_modem` kaybı geri gelmez (IMEI gider). Bu yüzden:

1. Önce **TWRP** yazılır (recovery bölümü — tek başına, küçük, geri dönüşü kolay).
2. TWRP açılınca **yedek** alınır (efs, modem, nvitem, prodnv).
3. Ancak ondan sonra ROM denenir.

## 1. Cihaz tarafı hazırlık (telefonda)

- Ayarlar → Geliiştirici seçenekleri → **USB hata ayıklama** aç.
- Ayarlar → Geliştirici seçenekleri → **OEM kilidi açma** aç (varsa).
- Telefonu şarj %60 üstüne getir.
- Samsung hesabı / Google hesabı varsa çıkış yap (FRP kilidi sorun çıkarmasın).

## 2. Download mode'a girme

Telefon kapalıyken:

```
Ses Kısma + Home + Güç   →  uyarı ekranı  →  Ses Açma
```

Ekranda `Downloading... Do not turn off target` yazısı görünür. Bu modda ekran
dokunmatik çalışmaz; çıkış için pil sökülür veya uzun süre Güç basılır.

## 3. Bağlantı doğrulama (yazma yok)

```bash
heimdall detect
```

`Device detected` dönerse bağlantı hazır. Dönmezse kablo/port değiştir; USB hub
kullanma.

## 4. PIT'i oku (yazma yok)

```bash
heimdall print-pit --no-reboot > ~/j106f-pit-$(date +%F).txt
```

Çıktı, cihazdaki gerçek bölüm tablosunu verir. Bölüm adları buradan doğrulanır —
sonraki adımlarda kullanılan isimler bu dosyayla eşleşmiyorsa **durulur**.

## 5. TWRP'yi yaz (ilk yazma işlemi)

Derleme çıktısı: `out/target/product/j1minivelte/recovery.tar`

```bash
j106f-flash incele out/target/product/j1minivelte/recovery.tar --bolum recovery
```

Ekranda görünen sha256'yı not al. Sonra:

```bash
j106f-flash flash out/target/product/j1minivelte/recovery.tar --bolum recovery
```

Araç sırayla şunları ister:

1. İmajın cihaz kodunu (`j1minivelte`) ve `ro.product.device` değerini gösterir.
2. Bölüm adının izin listesinde olduğunu doğrular (`recovery` ✔).
3. İmaj boyutunu bölüm sınırıyla karşılaştırır (26.214.400 B).
4. Gerçek bir TTY olduğunu doğrular — bu yüzden ajan çalıştıramaz.
5. sha256 öneki + `YAZ recovery` yazısını ister.
6. `heimdall detect` ile cihazı tekrar bulur.
7. `--gercek` bayrağı yoksa sadece komutu yazar, yazmaz.

Son adım:

```bash
j106f-flash flash out/target/product/j1minivelte/recovery.tar --bolum recovery --gercek
```

Yazma bitince cihaz kendini yeniden başlatır.

## 6. TWRP'ye gir ve yedek al

Telefon kapalıyken:

```
Ses Açma + Home + Güç
```

TWRP açılınca **hemen** yedek:

- `Backup` → `Select Partitions to Back Up`
- İşaretle: **EFS**, **Modem** (l_modem), **Nvitem** (l_fixnv2), **Product Info** (prodnv)
- Storage: **Micro SDcard** (dahili depolama değil — formatlanabilir)
- `Swipe to Back Up`

Yedek dosyasını bilgisayara da kopyala:

```bash
adb pull /external_sd/TWRP/BACKUPS/<seri-no>/ ~/j106f-yedek/
```

> TWRP fstab'ında bu bölümler `backup=1` olarak işaretli:
> `/efs`, `/preload` (HIDDEN), `/productinfo` (prodnv).
> `/nvitem` (l_fixnv2) ve `/l_modem` `backup=1` **değil** — TWRP menüsünde
> görünmezlerse `adb shell` ile elle `dd` alınır:
>
> ```bash
> adb shell 'dd if=/dev/block/platform/sdio_emmc/by-name/l_fixnv2 of=/external_sd/nvitem.img'
> adb shell 'dd if=/dev/block/platform/sdio_emmc/by-name/l_modem  of=/external_sd/l_modem.img'
> adb shell 'dd if=/dev/block/platform/sdio_emmc/by-name/prodnv   of=/external_sd/prodnv.img'
> ```
>
> Bu okuma işlemidir; yazma değil.

## 7. Yedeği doğrula

```bash
ls -la ~/j106f-yedek/
sha256sum ~/j106f-yedek/*
```

Boyutlar sıfırdan büyük olmalı. `efs` yedeği tipik olarak birkaç MB'dir.

## 8. ROM'u yazma (yalnızca yedek doğrulandıktan sonra)

TWRP → `Wipe` → `Format Data` (system değil) → sonra:

- `Install` → zip'i SD karttan seç → `Swipe to Confirm Flash`

Zip'in kendisi TWRP tarafından yazılır; gövde koruması devrede değildir çünkü
yazma işlemini TWRP yapar. Bu yüzden zip'in kaynağı ve sha256'sı önceden
doğrulanır:

```bash
sha256sum out/target/product/j1minivelte/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip
```

## 9. Geri dönüş (ROM açılmazsa)

TWRP → `Restore` → yedek seç → `EFS` + `Modem` + `Nvitem` + `Product Info`.

Stok ROM'a dönmek için Odin ile stok firmware (SamMobile/Updato, `J106F` model
kodu tam eşleşmeli) yazılır. **Stok firmware'i yazarken `BL` (bootloader) ve
`CP` (modem) bölümleri de yazılır** — bu, gövde korumasının kapsamı dışındadır
ve ayrı bir karar gerektirir.

## Yasak bölümler

Gövde koruması bu bölümlere yazmayı reddeder:

```
bootloader  uboot  sbl1  spl  efs  modemst1  modemst2
prodnv  nvdata  persist
```

Bu bölümlere yazma girişimi ajan tarafından da, `j106f-flash` tarafından da
engellenir. Stok firmware'e dönüş de dahil, bu bölümler için ayrı bir yol
izlenir ve kullanıcının açık kararı gerekir.
