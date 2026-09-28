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

### 4b. Cihaz olmadan da doğrulanabilir

Cihazın **kendi** PIT tablosu stok firmware'in CSC tar'ı içinde gelir. Repoda
ölçülmüş hâli durur (`docs/pit/J1MINIVELTE_MEA_JV.pit`), ayrıntısı
`docs/PIT-GERCEK.md`'de:

```bash
bash scripts/stok-indir.sh        # stok firmware'i indirir, PIT'i çıkarır (cihaz gerekmez)
bash scripts/pit-dogrula.sh docs/pit/J1MINIVELTE_MEA_JV.pit
```

Bu, PIT'teki gerçek boyutları derleme yapılandırmasıyla (`sharkls-common`'dan
miras `BOARD_*IMAGE_PARTITION_SIZE`) **ve** derlenen imajlarla karşılaştırır.
Cihaz download mode'a girmeden de aynı karşılaştırma yapılır.

Ölçülmüş sonuç:

```
  ✔ CACHE      209715200 bayt — esit
  ✔ KERNEL     20971520 bayt — esit
  ✔ RECOVERY   20971520 bayt — esit
  ✔ SYSTEM     derleme 2147483648, cihaz 2902458368 — imaj sigar (derleme kucuk)

  ✔ boot.img       9426960 bayt <= KERNEL 20971520 bayt (sigar)
  ✔ recovery.img   17291280 bayt <= RECOVERY 20971520 bayt (sigar)
```

## 5. TWRP'yi yaz (ilk yazma işlemi)

Derleme çıktısı: `out/target/product/j1minivelte/recovery.tar`

```bash
j106f-flash incele out/target/product/j1minivelte/recovery.tar --bolum recovery
```

Ekranda görünen sha256'yı **aşağıdaki referansla karşılaştır** (kör kopyalama yok):

| Dosya | sha256 | Bayt |
|---|---|---|
| `recovery.tar` | `0852e7d3a58e0ff036d9bff1c2ba94dc75fdfcf218f799852b5fa0e626dc835a` | 17295360 |
| `recovery.img` (tar içindeki) | `7485d7a0dd2a7aa000b96b30f695800ebc14d10b6c3294f93a7d080aeb38fc77` | 17291280 |
| `boot.img` | `e203d7d80abaa1dcccdd8a076d0bd3ff8995e4531e1a9b1ee3b76f61b9e08982` | 9426960 |
| `dt.img` | `baa67a565dd59ddd76f5305f3e1ea111466fb98b8f0edf73bea7dedd51276d71` | 129024 |
| `lineage-15.1-*-UNOFFICIAL-j1minivelte.zip` | `45ab977c616b7c52b92297386897838b6d7ca8701c2a707c253e69534126fe84` | 371692490 |
| `zImage` (zip'teki çekirdek) | `02b15a66d823ecf65ee0b000160067be2d5b3e49bd0ee41a97ac7d0480188a33` | — |
| MindTheGapps zip | `e4f65de26de8515acd4f37d52c2321fc8c07211e2522a474f7b54953f52299c2` | 106590724 |

Kendi tarafında doğrula:

```bash
sha256sum out/target/product/j1minivelte/recovery.tar \
          out/target/product/j1minivelte/boot.img \
          out/target/product/j1minivelte/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip
```

Sonra:

```bash
j106f-flash flash out/target/product/j1minivelte/recovery.tar --bolum recovery
```

Araç sırayla şunları ister:

1. İmajın cihaz kodunu (`j1minivelte`) ve `ro.product.device` değerini gösterir.
2. Bölüm adının izin listesinde olduğunu doğrular (`recovery` ✔).
3. İmaj boyutunu bölüm sınırıyla karşılaştırır (20.971.520 B — gerçek PIT).
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
adb shell 'for B in l_modem l_fixnv2 prodnv efs PERSDATA PARAM; do
  D=/dev/block/platform/sdio_emmc/by-name/$B
  SZ=$(blockdev --getsize64 $D)
  echo "$B: $SZ bayt"
  dd if=$D of=/external_sd/$B.img bs=4096
done'
```

Boyut, cihazın gerçek PIT'inden okunur — sabit değer varsayılmaz. Ölçülmüş
değerler (`docs/PIT-GERCEK.md`):

| Bölüm | Boyut | Kaybı |
|---|---|---|
| `efs` | 20.971.520 B (20 MiB) | IMEI, şebeke |
| `l_modem` | 16.777.216 B (16 MiB) | RF kalibrasyonu |
| `l_fixnv2` | 1.048.576 B (1 MiB) | NV verisi |
| `prodnv` | 5.242.880 B (5 MiB) | ürün bilgisi |
| `PERSDATA` | 9.437.184 B (9 MiB) | kalıcı veri |
| `PARAM` | 2.097.152 B (2 MiB) | boot parametreleri |

### 6c. Bilgisayara çek

```bash
mkdir -p ~/j106f-yedek
adb pull /external_sd/TWRP/BACKUPS/ ~/j106f-yedek/TWRP/ 2>/dev/null
for B in l_modem l_fixnv2 prodnv efs PERSDATA PARAM; do
  adb pull /external_sd/$B.img ~/j106f-yedek/ 2>/dev/null
done
ls -la ~/j106f-yedek/
```

## 7. Yedeği doğrula

Boyutlar **PIT'teki gerçek boyutla birebir** eşit olmalı. Yedek bölümün tamamı
okunduğu için dosya boyutu = bölüm boyutu:

```bash
sha256sum ~/j106f-yedek/*.img
declare -A PIT=( [efs]=20971520 [l_modem]=16777216 [l_fixnv2]=1048576 \
                 [prodnv]=5242880 [PERSDATA]=9437184 [PARAM]=2097152 )
for f in "${!PIT[@]}"; do
  b=$(stat -c %s ~/j106f-yedek/$f.img 2>/dev/null || echo YOK)
  if [ "$b" = "${PIT[$f]}" ]; then
    echo "  ✔ $f: $b bayt"
  else
    echo "  ✘ $f: $b bayt, beklenen ${PIT[$f]} — ROM'a GEÇME"
  fi
done
```

Sıfır baytlık, eksik veya yanlış boyutlu dosya varsa **ROM'a geçme**. Boyutlar
sabit değil: `docs/PIT-GERCEK.md`'de ölçülmüş, `scripts/pit-dogrula.sh` ile
doğrulanabilir.

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
