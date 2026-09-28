# SM-J106F — LineageOS 15.1 (Android 8.1) port

Samsung Galaxy J1 Mini Prime (SM-J106F, codename `j1minivelte`) için LineageOS 15.1
ağacı, cihaz ağacı, vendor blob'ları ve derleme sırasında çıkan gerçek engellerin
çözümleri.

Hedef: stok Android 6.0.1'de çalışmayan modern uygulamaların çalıştığı, Google
servislerinin (Play Store, YouTube) çalıştığı, root'lu bir sistem.

## Cihaz

| | |
|---|---|
| Model | SM-J106F (Galaxy J1 Mini Prime, LTE) |
| Codename | `j1minivelte` (`j1minive3g` = 3G varyantı) |
| SoC | Spreadtrum SC9830A / SCX35L, Cortex-A7 32-bit ARMv7 |
| GPU | Mali-400 MP2 |
| RAM / depolama | 1 GB / 8 GB eMMC |
| Çekirdek | 3.10.x |
| Stok | Android 6.0.1 |
| Treble | yok |
| fastboot | yok — yalnızca Odin / Heimdall download mode |

## Ağaç yapısı

```
device/samsung/j1minivelte/     cihaz ağacı (BoardConfig, lineage.mk, init, overlay)
vendor/samsung/j1minivelte/     proprietary blob'lar + device-vendor-blobs.mk
patches/                        derleme sırasında gereken yamalar
manifest/j106f.xml              repo local_manifest
scripts/                        derleme ortamı betikleri
docs/                           plan ve araştırma raporları
```

## Kaynaklar (upstream)

`repo` manifest'i `manifest/j106f.xml` içinde. Özet:

| Yol | Kaynak | Revizyon |
|---|---|---|
| `device/samsung/sharkls-common` | `djeman/android_device_samsung_sharkls-common` | `lineage-15.1` |
| `kernel/samsung/j1minivelte` | `lasania32198/android_kernel_samsung_j1minivelte` | `main` |
| `vendor/samsung/common` | `djeman/android_vendor_samsung_common` | `lineage-15.1` |
| `hardware/samsung`, `external/sony/boringssl-compat` | LineageOS | `lineage-15.1` |
| `bootable/recovery-twrp`, `external/busybox` | omnirom | `android-8.1` |
| `vendor/sprd` | `Talustus/android_vendor_sprd` | `lineage-15.1` |

`vendor/sprd` manifest'te **yok** — `repo sync` onu siler. Elle klonlanır:

```bash
git clone --depth=1 -b lineage-15.1 \
    https://github.com/Talustus/android_vendor_sprd vendor/sprd
```

Not: `djeman/android_vendor_sprd` DMCA nedeniyle **HTTP 451** döner. Talustus fork'u
kullanılır.

## Yamalar

`patches/` altındakiler, upstream'de olmayan ve derlemeyi kıran noktalara ait:

| Dosya | Hedef | Ne yapar |
|---|---|---|
| `kernel-isp-port.patch` | `kernel/samsung/j1minivelte` | ISP sürücüsünü djeman'ın sharkls çekirdeğindeki yeni arayüze taşır (bkz. `docs/ISP-BULGU.md`) |
| `kernel-binder-port.patch` | `kernel/samsung/j1minivelte` | Eski tek-cihazlı binder'ı AOSP 4.14 backport'u ile değiştirir; `/dev/hwbinder` + `/dev/vndbinder` yaratır (bkz. `docs/BINDER-BULGU.md`) |
| `sharkls-common-j1minivelte.patch` | `device/samsung/sharkls-common` | j1minivelte'yi ortak ağaca kaydeder (init.rc, OTA assert, ramdisk) |
| `hardware-ril-BOARD_PROVIDES_RILD.patch` | `hardware/ril` | AOSP `rild`'i `BOARD_PROVIDES_RILD` ile kapatır — cihaz ağacındaki kendi `rild`'iyle çakışmayı çözer |

Ek olarak `device/samsung/sharkls-common/patches/sprd-diff/` (upstream'de var)
12 yama içerir; hepsi uygulanmalıdır:

```bash
cd <tree>
BASE=$(pwd)
for FILE in $BASE/device/samsung/sharkls-common/patches/sprd-diff/*.diff; do
    SNAME=$(basename $FILE); RELPATH=${SNAME%%.*}; RELPATH=${RELPATH/_//}
    (cd $BASE/$RELPATH && patch -p1 --forward < $FILE)
done
```

## Derleme ortamı

LineageOS 15.1 iki eski araç ister; ikisi de ağacın içinde hazır:

- **python2** — `prebuilts/python/linux-x86/2.7.5/bin/python2.7`
  (sistemde python2 yoksa `build/tools/findleaves.py` SyntaxError verir ve
  `first-makefiles-under` sessizce boş döner)
- **JDK 8** — `prebuilts/jdk/jdk8/linux-x86`
  (`build/make/envsetup.sh` içindeki `set_java_home()` sabit
  `/usr/lib/jvm/java-8-openjdk-amd64` yolunu arar; sistemde yoksa
  `JAVA_HOME` elle verilmelidir)

`envsetup.sh` **bash** ister, zsh ile çalışmaz.

`scripts/buildenv.sh`:

```bash
export TOP=<ağaç kökü>
export JAVA_HOME=$TOP/prebuilts/jdk/jdk8/linux-x86
export ANDROID_JAVA_HOME=$JAVA_HOME
export PATH=$JAVA_HOME/bin:$TOP/../py2shim:$PATH
export LC_ALL=C
export USE_CCACHE=0
cd $TOP
source build/envsetup.sh
```

`py2shim/`, `python` ve `python2` adlarını ağaçtaki python2.7'ye bağlayan symlink
dizinidir.

### Host paketleri

`zip` ve `bc` zorunlu; `gperf`, `lzop`, `pngcrush`, `schedtool` önerilir.
Ayrıca prebuilt clang (`clang-4053586`) `libncurses.so.5` / `libtinfo.so.5` ister.
Modern dağıtımlarda ncurses 6 vardır; symlink yeterlidir:

```bash
mkdir -p ncurses5compat
ln -sf /usr/lib/libncursesw.so.6 ncurses5compat/libncurses.so.5
ln -sf /usr/lib/libtinfo.so.6    ncurses5compat/libtinfo.so.5
export LD_LIBRARY_PATH=$PWD/ncurses5compat:$LD_LIBRARY_PATH
```

### Derleme

```bash
bash scripts/buildenv.sh
lunch lineage_j1minivelte-userdebug
mka bacon
```

Çıktı: `out/target/product/j1minivelte/lineage-15.1-*-UNOFFICIAL-j1minivelte.zip`

## Cihaz ağacı notları

- `TARGET_KERNEL_SOURCE := kernel/samsung/j1minivelte` — `sharkls-common`'ın
  `kernel/samsung/sharkls` varsayılanını geçersiz kılar.
- `BOARD_KERNEL_IMAGE_NAME := zImage` (sharkls-common'dan gelir). J106F boot bölümü
  10.978.320 B; zImage ~5.4 MB sığar, sıkıştırılmamış `Image` ~12.4 MB sığmaz.
- `BOARD_BOOTIMAGE_PARTITION_SIZE := 10978320`
- `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 26214400`
- `BOARD_KERNEL_PAGESIZE := 2048`, `BOARD_KERNEL_BASE := 0x00000000`
- `TARGET_COPY_OUT_VENDOR` ayarlı değil → varsayılan `system/vendor`.

## Güvenlik

Flash işlemi **gövde koruması** (body guard) altındadır: cihaz izin listesi, bölüm
izin listesi, boyut sınırı, TTL'li onay kaydı, imaj hash doğrulaması ve TTY zorunluluğu.
Onay olmadan hiçbir imaj yazılamaz. Ayrıntı: `docs/plan.md` §7.

Flash öncesi mutlaka yedeklenmeli: `efs`, `l_modem`, `nvitem`, `prodnv`.

## Belgeler

- `docs/plan.md` — ana plan, kararlar, riskler
- `docs/ISP-BULGU.md` — ISP arayüz uyuşmazlığı ve çözümü (kritik)
- `docs/BINDER-BULGU.md` — binder ABI uyuşmazlığı ve çözümü (kritik, boot blocker)
- `docs/arastirma-raporu.md`, `docs/arastirma-raporu-2.md` — ROM araştırması
