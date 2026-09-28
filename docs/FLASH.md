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

Heimdall bölüm adlarını yalnızca bu tablodan çözer; **takma ad yoktur**. Boot
bölümünün PIT adı `KERNEL`'dir — `heimdall flash --boot` çalışmaz:

```
Partition "boot" does not exist in the specified PIT.
```

`j106f-flash` bu eşlemeyi `govde/policy.json` içindeki `pit_bolum_adi` alanından
okur ve yazmadan **önce** `print-pit`'ten bölümün gerçek boyutunu çıkarıp imajın
sığdığını doğrular.

```bash
bash scripts/pit-dogrula.sh ~/j106f-pit-*.txt
```

Bu, PIT'teki gerçek boyutları derleme yapılandırmasıyla (`sharkls-common`'dan
miras `BOARD_*IMAGE_PARTITION_SIZE`) karşılaştırır. Fark varsa imaj bölüme
sığmaz; derleme boyutları düzeltilmeden yazılmaz.

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
7. `print-pit`'ten `RECOVERY` bölümünün gerçek boyutunu okur ve imajın sığdığını
   doğrular (kapı 3b).
8. `.tar` verildiyse içindeki `.img`'yi çıkarır, boyutunu PIT'e karşı doğrular ve
   **onu** yazar (kapı 3c). heimdall CLI arşiv açmaz; `recovery.tar`'ı olduğu
   gibi yazmak bölüme tar arşivini yazardı.
9. `--gercek` bayrağı yoksa sadece komutu yazar, yazmaz.

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

TWRP açılınca **hemen** yedek. İki aşama, ikisi de zorunlu.

### 6a. TWRP menüsünden (backup=1 olanlar)

- `Backup` → `Select Partitions to Back Up`
- İşaretle: **EFS**, **Preload**, **Product Info**
- Storage: **Micro SDcard** (dahili depolama değil — `Format Data` onu siler)
- `Swipe to Back Up`

### 6b. Ham `dd` — TWRP'nin yedeklemediği bölümler

TWRP fstab'ında `backup=1` yalnızca `/efs`, `/preload` (HIDDEN), `/productinfo`
(prodnv) üzerindedir. **`/l_modem` (l_modem) ve `/nvitem` (l_fixnv2) yedek
kapsamı dışındadır.** Bunlar RF kalibrasyonu ve IMEI verisidir; kaybolursa
şebeke bir daha gelmez ve geri yüklemenin yolu yoktur. Menüde görünmelerini
beklemeden, elle alınır.

```bash
# TWRP açıkken, bilgisayardan. Okuma işlemidir; hiçbir şey yazılmaz.
adb shell 'for B in l_modem l_fixnv2 prodnv efs; do
  D=/dev/block/platform/sdio_emmc/by-name/$B
  SZ=$(blockdev --getsize64 $D)
  echo "$B: $SZ bayt"
  dd if=$D of=/external_sd/$B.img bs=4096
done'
```

Boyut, cihazın gerçek PIT'inden okunur — sabit değer varsayılmaz.

### 6c. Bilgisayara çek

```bash
mkdir -p ~/j106f-yedek
adb pull /external_sd/TWRP/BACKUPS/ ~/j106f-yedek/TWRP/ 2>/dev/null
adb pull /external_sd/l_modem.img   ~/j106f-yedek/
adb pull /external_sd/l_fixnv2.img  ~/j106f-yedek/
adb pull /external_sd/prodnv.img    ~/j106f-yedek/
adb pull /external_sd/efs.img       ~/j106f-yedek/
ls -la ~/j106f-yedek/
```

## 7. Yedeği doğrula

Boyutlar sıfırdan büyük olmalı. `dd` çıktısındaki `blockdev --getsize64` değeriyle
karşılaştır — birebir eşit olmalı:

```bash
sha256sum ~/j106f-yedek/*
for f in l_modem l_fixnv2 prodnv efs; do
  echo "$f: $(stat -c %s ~/j106f-yedek/$f.img 2>/dev/null || echo YOK) bayt"
done
```

`l_modem` yedeği birkaç yüz KB, `l_fixnv2` birkaç yüz KB, `prodnv` birkaç MB
civarındadır. Sıfır baytlık veya eksik dosya varsa **ROM'a geçme**.

## 8. ROM'u yazma (yalnızca yedek doğrulandıktan sonra)

TWRP → `Wipe` → `Format Data` (system değil) → sonra:

- `Install` → zip'i SD karttan seç → `Swipe to Confirm Flash`

Zip'in kendisi TWRP tarafından yazılır; gövde koruması devrede değildir çünkü
yazma işlemini TWRP yapar. Bu yüzden zip'in kaynağı ve sha256'sı önceden
doğrulanır:

```bash
sha256sum out/target/product/j1minivelte/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip
```

### Google servisleri (Play Store) — ROM'dan SONRA, aynı TWRP oturumunda

LineageOS Google servissiz gelir. Play Store için GApps şart:

```bash
bash scripts/indir-gapps.sh
```

TWRP'de **wipe/format yapmadan**:

1. `Install` → `lineage-15.1-*.zip` → `Swipe to Confirm Flash`
2. `Install` → `MindTheGapps-8.1.0-arm-*.zip` → `Swipe to Confirm Flash`
3. `Reboot System`

GApps, ROM'dan sonra kurulur. Wipe data, GApps'tan sonra yapılırsa Play
Hizmetleri bozulur (veri şeması ilk boot'ta kurulur).

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
