# Üretilen recovery.img — TWRP mi, ROM zip'i kurulabilir mi

Soru: `mka bacon` çıktısındaki `recovery.img` ROM zip'ini kurmaya yeter mi,
yoksa ayrıca TWRP mi gerekli?

Cevap: Üretilen `recovery.img` **TWRP 3.2.3-0**'dır ve ROM zip'ini kuracak
kadardır. Ayrı bir TWRP indirmek gerekmez. Ölçüm aşağıda.

## Ölçüm — recovery.img gerçekten TWRP

`out/target/product/j1minivelte/recovery.img` açıldı (ANDROID! başlığı,
page 2048):

| alan | değer |
|---|---|
| kernel_size | 5.492.664 |
| ramdisk_size | 11.666.131 |
| dt_size | 129.024 |
| cmdline | `console=ttyS1,115200n8` |

Ramdisk (`/sbin/recovery`, 549.584 B) içinde TWRP'ye özgü dizeler:

```
Check for TWRP App
config_twrp=Configuring TWRP...
E:Installing SuperSU was deprecated from TWRP.
E:This TWRP does not have synthetic password decrypt support
E:/etc/twrp.flags
```

Sürüm izi: `3.2.3-0`. Kaynak ağaçta `bootable/recovery-twrp` var
(`bootable/recovery` ayrı duruyor; `mka bacon` TWRP'yi seçiyor).

## Ölçüm — TWRP ROM zip'ini kurabilir

TWRP zip kurulumu `META-INF/com/google/android/update-binary`'yi çalıştırır
(ramdisk içinde: `META-INF/com/google/android/update-binary`, `/tmp/updater`,
`Installing Zip`).

1. **`assert` cihaz kapısı geçer.** `updater-script` `ro.product.device` için
   `j1minivelte` ister. TWRP ramdisk `default.prop`:
   ```
   ro.product.model=SM-J106F
   ro.product.name=j1miniveltejv
   ro.product.device=j1minivelte
   ro.build.product=j1minivelte
   ```
   Yani assert geçer, `E3004` ile abort etmez.

2. **Brotli desteği var.** Zip `ota-type=BLOCK` ve yük `system.new.dat.br`
   (brotli). `update-binary`, derlenen `updater` ikilisinin birebir kopyasıdır:
   ```
   sha256 3f598276013b28f5246b116c4d6e25d8462bca51c5494c47c5d6fab2bd54daf1
   (hem out/.../updater_intermediates/updater hem zip'teki update-binary)
   ```
   Bu ikili brotli kodunu taşır. Kanıt, sembol araması değil **veri**dir:
   `libbrotli.a:dictionary.o` içindeki `.rodata.kBrotliDictionary` (122.944 B)
   stripli `update-binary` içinde birebir bulunur. (`strings` ile "brotli"
   aramak yanıltıcıydı: sembol adları striplenmiş, geriye yalnız veri kalır.)
   Kod tarafı da kaynakta: `bootable/recovery/updater/blockimg.cpp:1478`
   `EndsWith(new_data_fn, ".br")` → brotli yolu.

3. **`block_image_update` hedefi cihazın PIT adı.** `updater-script`
   `/dev/block/platform/sdio_emmc/by-name/SYSTEM` ve `.../KERNEL` yazar; TWRP
   `etc/twrp.fstab` aynı yolları kullanır.

4. **Yedekleme yolları hazır.** `etc/twrp.fstab` içinde `efs`, `prodnv`,
   `l_modem`, `l_fixnv2` (`/nvitem`), `PERSDATA`, `pm_sys`, `HIDDEN`
   (`/preload`) tanımlı. Flash öncesi zorunlu yedekler buradan alınır.

5. **İmza kapısı takılmaz.** Ölçüldü, üç ayrı olgu:

   a. Zip **imzalıdır**. EOCD yorumunda 1738 baytlık blok var; footer
      `b806ffffca06` → `signature_start=1720`, `comment_size=1738`.
      `bootable/recovery-twrp/verifier.cpp:129-190` düzenine göre
      `signed_len = boyut - (comment_size+22) + 22 - 2 = 371690750`, imza
      `0x30` (DER SEQUENCE) ile başlar. PKCS#7 doğrulaması zip'teki
      `META-INF/com/android/otacert` ile **geçer** (`Verification successful`).

   b. TWRP'nin anahtarlığında bu anahtar **vardır**. `recovery/root/res/keys`
      iki anahtar taşır; 1. anahtarın modülüsü `build/target/product/security/
      testkey.x509.pem` ile birebir aynıdır (`d6931904…91f`). Anahtar kodlaması
      `verifier.cpp:476+` `load_keys()` biçimidir: 4 baytlık sözcükler
      big-endian, sözcük sırası ters; `n0inv` bunu doğrular.

   c. İmza denetimi **varsayılan olarak kapalıdır**. `twrp/data.cpp:728`
      `mPersist.SetValue(TW_SIGNED_ZIP_VERIFY_VAR, "0")`. `twinstall.cpp:368`
      bu değeri okur; `0` iken `verify_file()` çağrılmaz. Ayrıca TWRP
      `Install` düğmesi `gui/action.cpp:389` → `TWinstall_zip()` yolundan
      gider; AOSP'nin `install.cpp:really_install_package()` imza denetimi bu
      yolda çalışmaz.

   Yani imza hem geçerli hem de kabul edilebilir; kapı yine de kapalı.

6. **Digest kapısı tetiklenmez.** `twinstall.cpp:327-345` yalnızca yanında
   `.md5`/`.md5sum` dosyası varsa denetler. Zip tek başına kopyalanırsa
   ("Skipping Digest check: no Digest file found") atlanır. Yanına md5
   dosyası koymak istenirse değer `45ab977c616b7c52b92297386897838b6d7ca8701c2a707c253e69534126fe84`
   (sha256) — md5 değil — olduğundan md5 dosyası **koyulmamalıdır**.

## Sınırlar

- TWRP ramdisk'inde `su` ikilisi yok. Zip'i kurmak root gerektirmez (TWRP
  zaten root yetkisiyle çalışır); ancak ROM'a root gömmek ayrı iş, bu
  belgenin konusu değil.
- TWRP sürümü 3.2.3-0, ROM'un kendi Android sürümünden bağımsızdır: TWRP
  kendi çekirdeğiyle açılır, kurulum bitince ROM'un `boot.img`'si KERNEL
  bölümüne yazılır.
- `recovery.img` (17.291.280 B) RECOVERY bölümüne (20.971.520 B) sığar;
  `recovery.tar` (17.295.360 B) da.

## Sonuç

`recovery.img` = TWRP 3.2.3-0. Cihazın kendi `recovery.img`'si hem TWRP'dir
hem de bu ROM zip'ini kuracak sürümdedir. Ayrı TWRP indirmeye gerek yok.
