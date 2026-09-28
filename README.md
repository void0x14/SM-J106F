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
scripts/                        derleme ortamı + kanıt betikleri
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

#### Ağaçtaki python2'de zlib yok

`prebuilts/python/linux-x86/2.7.5` gömülü python2.7.5'in `lib-dynload/` dizininde
`zlib.so` **yoktur**. `releasetools/build_image.py` → `import gzip` → `import zlib`
zinciri kırılır:

```
ImportError: No module named zlib
FAILED: out/target/product/j1minivelte/cache.img
```

Çözüm: modülü ağacın kendi kaynağından (`external/python/cpython2/Modules/zlibmodule.c`)
32-bit olarak derleyip `lib-dynload/` içine kur. Kaynak 2.7.13+ için yazılmıştır;
python2.7.5'te bulunmayan `Py_SETREF`/`Py_XSETREF` makroları shim ile verilir.

```bash
bash scripts/fix-py2-zlib.sh
```

#### Git LFS nesneleri

`repo sync` LFS nesnelerini indirmez. `external/chromium-webview/prebuilt/*/webview.apk`
133 baytlık pointer olarak kalır ve signapk patlar:

```
java.util.zip.ZipException: error in opening zip file
FAILED: out/target/product/j1minivelte/obj/APPS/webview_intermediates/package.apk
```

```bash
bash scripts/fix-webview-lfs.sh
```

Ağaçta LFS kullanan tek yer bu dört dizindir.

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
  `kernel/samsung/shandong` varsayılanını geçersiz kılar.
- `BOARD_KERNEL_IMAGE_NAME := zImage` (sharkls-common'dan gelir). J106F boot bölümü
  20.971.520 B; zImage ~5.4 MB sığar.
- `BOARD_BOOTIMAGE_PARTITION_SIZE := 20971520`
- `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 20971520`
- `BOARD_KERNEL_PAGESIZE := 2048`, `BOARD_KERNEL_BASE := 0x00000000`
- `TARGET_COPY_OUT_VENDOR` ayarlı değil → varsayılan `system/vendor`.

Bölüm boyutları tahmin değil: cihazın **kendi PIT tablosundan** ölçüldü
(`docs/PIT-GERCEK.md`, `docs/pit/J1MINIVELTE_MEA_JV.pit`). Cihaz olmadan
doğrulanır:

```bash
bash scripts/stok-indir.sh     # stok firmware → PIT (cihaz gerekmez)
bash scripts/pit-dogrula.sh docs/pit/J1MINIVELTE_MEA_JV.pit
```

Sonuç: KERNEL ve RECOVERY 20.971.520 B — `sharkls-common` değeri doğru.
Dolaşımdaki `10.978.320` değeri bir **dump edilen imaj dosyasının boyutu**
(twrpdtgen `origsize`), bölüm boyu değil; 512'ye bölünmez.

## Önyükleme zinciri

Init, cihaza özel rc dosyalarını `ro.hardware`'a göre okur. Bu değer
`androidboot.hardware=sc8830` çekirdek cmdline'ında yoksa `ro.hardware=unknown`
olur ve `/init.unknown.rc` aranır — cihaz açılmaz, hiçbir hata basılmaz.

cmdline iki kaynaktan birleşir:

| Kaynak | Nerede | LK ezer mi? |
|---|---|---|
| `CONFIG_CMDLINE` | derlenmiş `.config` | hayır |
| DT `/chosen/bootargs` | `dt.img` | evet — `update_device_tree()` |

Yalnızca DT'ye yazmak yetmez; LK `/chosen/bootargs`'ı ezdiğinde anahtar kaybolur.
Bu yüzden anahtar `CONFIG_CMDLINE`'a konur ve modu `EXTEND` yapılır.

`arch/arm/kernel/atags_parse.c:33` `default_command_line = CONFIG_CMDLINE`;
ATAGS yolunda `parse_tag_cmdline()` (`:128-134`) `CMDLINE_EXTEND` ile tag cmdline'ı
buna **ekler**. DT yolunda `drivers/of/fdt.c:744-760` `boot_command_line[0]==0`
iken `CONFIG_CMDLINE`'ı yazıp DT bootargs'ı ekler. Yani `EXTEND` modunda
`androidboot.hardware=sc8830` her iki yolda da cmdline'a girer.

`init.cpp:473-487` `import_kernel_nv()` yalnızca `androidboot.*` anahtarlarını
`ro.boot.*` yapar; `:511` `ro.hardware` eşlemesi `export_kernel_boot_props()`
(`:1095`) içinde, `/init.rc` parse edilmeden (`:1140`) önce kurulur.

Stok J106F da bu yolu kullanır (`kaynak/j106f-kernel/j1minive3g-dt_defconfig:525-528`),
djeman'ın çalışan `j3xnlte_permissive_defconfig`'i de (`:553-556`):

```
CONFIG_CMDLINE="androidboot.selinux=permissive androidboot.hardware=sc8830 console=ttyS1,115200n8"
# CONFIG_CMDLINE_FROM_BOOTLOADER is not set
CONFIG_CMDLINE_EXTEND=y
```

Stok upstream defconfig'teki `initrd=0x80e00000,0x1f243f` ve `mem=128M` **kaldırıldı**:
ramdisk yerleşimini LK kendisi yapar (`boot.img` başlığındaki adresler
`BOARD_KERNEL_BASE`'e göreli, LK `ABOOT_FORCE_*` ile geçersiz kılar) ve `mem=`
1 GB cihazda RAM'i kırpar.

`scripts/boot-zinciri.py` bu zinciri üç halkada denetler: etkin cmdline →
`ro.hardware`, rc `import` grafiği kapanışı, ve ramdisk yerleşimi.

Üçüncü halka **kaynak `.dts` metnini değil, cihaza giden `dt.img` konteynerini**
ayrıştırır. Sebep: cihaza yazılan şey konteynerdir. SPRD biçimi
`<4s 'SPRD'><u32 sürüm><u32 adet>` ardından her girdi için
`<u32 boyut><u32 ofset>`; bir girdi **birden fazla** FDT taşıyabilir ve her
FDT'nin uzunluğu kendi `totalsize` alanındadır (başlığın 4. baytı, big-endian).

Ölçüldü (bu cihazın `dt.img`'si): `sürüm=1 girdi=2 boyut=129024`; `girdi1`
iki FDT içerir (`@+0` ve `@+63488`, her biri 61.539 B), ikisinde de initrd
penceresi `0x85500000..0x855a3212` (668.178 B). Bu **yer tutucudur**, gerçek
ramdisk 3.801.974 B; LK boot anında yamalar, bu yüzden pencere boyutu değil
geçerliliği ve varlığı denetlenir. Derlenen `dt.img`, stok referansla
(`kaynak/ref/*/prebuilt/dt.img`) **sha256 birebir aynıdır**.

```
$ python3 scripts/boot-zinciri.py out/target/product/j1minivelte <kernel-dizini>
  cmdline modu   : EXTEND
  ro.hardware    : sc8830  (kaynak: CONFIG_CMDLINE)
  SPRD konteyner : surum=1 girdi=2 boyut=129024 bayt
    girdi1@+0: boyut=61539 initrd 0x85500000..0x855a3212 (668178 bayt)
    girdi1@+63488: boyut=61539 initrd 0x85500000..0x855a3212 (668178 bayt)
SONUC: onyukleme zinciri saglam
```

Negatif deneme: `dt.img` içindeki `linux,initrd-start/end` adları bozulunca
betik `KOPUK HALKA VAR` verip exit 1 döner.

### QEMU ile önyükleme neden denenemez

Derlenen çekirdek yalnızca `CONFIG_ARCH_SCX35L=y` içerir;
`CONFIG_ARCH_VERSATILE`, `CONFIG_ARCH_EXYNOS`, `CONFIG_ARCH_VIRT` **kapalıdır**
(`obj/KERNEL_OBJ/.config`). QEMU'nun `vexpress-*` ve `virt` makineleri bu
yapılandırmayla çalışmaz. QEMU için yeniden yapılandırmak, cihaza giden
çekirdekten **başka** bir çekirdek üretir; o yüzden init servislerinin
ayakta kalktığını QEMU ile kanıtlamak bu ROM için geçerli bir ölçüm değildir.

### Çekirdek sözleşmesi (Android 8.1 ↔ 3.10.65)

Derlenen zImage Android 8.1'in istediği arayüzleri karşılıyor. Denetlenen her
anahtar ya `=y`, ya djeman'ın çalışan çekirdeğinde de kapalı, ya da init/userspace
tarafında sessizce tolere ediliyor:

- binder/ashmem/logger/lowmemorykiller/selinux/cgroups/fuse/tmpfs/ext4/configfs — tam
- `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"` — `kernel-binder-port.patch` ile
- netd netfilter seti (quota2, u32, state, connmark, mark, limit, quota, socket) — tam
- `PM_SLEEP`/`SUSPEND_FREEZER`/`WAKELOCK`/`EARLYSUSPEND`/`ANDROID_INTF_ALARM_DEV=y`;
  libsuspend `/sys/power/wakeup_count` + `/sys/power/state` kullanır (`kernel/power/main.c:423-460,749`)
- `NAMESPACES=n` **engel değil**: bu 3.10 ağacında `CLONE_NEWNS` `CONFIG_NAMESPACES`
  ile kapılanmaz (`fs/namespace.c:2497` `copy_mnt_ns`, `kernel/nsproxy.c:126`
  `copy_namespaces`); zygote'un `unshare(CLONE_NEWNS)` çağrısı geçer
- `F2FS_FS=n` **engel değil**: `fstab` `auto`/`ext4`/`f2fs` listeler,
  `fs_mgr::mount_with_alternatives()` (`fs_mgr.cpp:600-669`) geçersiz ext4 magic'ini
  atlar; TWRP `recovery.fstab` zaten ext4-only
- `UID_CPUTIME=n`, `CGROUP_SCHEDTUNE=n`, `POMEMR_RECLAIM=n`, `USB_HOST_NOTIFY` yok —
  hepsi djeman'da da aynı; ilgili sysfs yazımları sessizce başarısız olur

## Google servisleri (Play Store, YouTube)

LineageOS 15.1 Google servissiz gelir. ROM kurulduktan **sonra**, aynı TWRP
oturumunda GApps zip'i kurulur.

```bash
bash scripts/indir-gapps.sh
```

| | |
|---|---|
| Paket | MindTheGapps 8.1.0 arm |
| Neden bu | cihaz 32-bit ARM + Android 8.1 + 1 GB RAM; OpenGApps `stock` fazla ağır, MindTheGapps yalnızca Play Store + Play Hizmetleri çekirdeği + gerekli çerçeveleri kurar |
| Boyut | 106.590.724 B (GitHub'ın 100 MB tek-dosya limitini aştığı için repoya gömülemez; script indirir) |
| sha256 | `e4f65de26de8515acd4f37d52c2321fc8c07211e2522a474f7b54953f52299c2` |
| İçerik | `Phonesky` (Play Store), `PrebuiltGmsCore` (Play Hizmetleri), `GoogleServicesFramework`, `SetupWizard`, `Velvet` (YouTube için gerekli) |

Kurulum sırası: `lineage-15.1-*.zip` → GApps zip'i → yeniden başlat.

### GApps uyumluluk ölçümü

Paket cihaza uyuyor mu sorusu host'ta yanıtlanır; cihazda denenirse boot
kaybedilir ve sebep görünmez. `scripts/gapps-denetle.sh` yükü ağacın
**kopyasına** uygular (cihaza hiçbir şey yazmaz) ve beş kapı koşar:

```bash
bash scripts/gapps-denetle.sh <gapps.zip> <system-agaci> [<ramdisk-dizini>] [<system.img>]
```

| Kapı | Ne sınar |
|---|---|
| mimari | yükteki her ELF'in `e_machine`'i cihaz ağacıyla aynı mı (sabit mimari adı yok; referans ağaçtan okunur) |
| çakışma | yükteki her dosya ağaçta var mı (idempotans: zaten uygulanmış ağaçta 25 çakışma verir) |
| hedef dizin | kurucunun yazacağı dizinler var mı |
| yer | ham imajdan (`tune2fs`) bölümün gerçek boş alanı yetiyor mu |
| sessiz-hata | `elf-kapanis.py` + `init-denetle.py` uygulanmış kopya üzerinde |

Ölçüldü (build10 sistemi, `MindTheGapps-8.1.0-arm`):

```
yuk e_machine  : 40   (agac referansi: 40)   -> OK
cakisan dosya  : 0
agacta olmayan : 0
bolum          : 2048 MB, bos 1207 MB        -> OK  yuk bolume sigiyor
saglanan kutuphane : 555 / kok : 292 / erisilebilen ELF : 595  -> yukleyici zinciri saglam
tanimli servis : 71  -> SAGLAM
SONUC: GApps uygulanabilir, sessiz-hata kapilari temiz
```

Ek olarak ölçüldü: `ro.control_privapp_permissions` build.prop'ta yok
(`RoSystemProperties.java:56-63` → `CONTROL_PRIVAPP_PERMISSIONS_DISABLE`),
yani GApps'in `privapp-permissions-google.xml` boşlukları boot'u kilitleyemez.
GApps'in yazdığı yollar AOSP yakalayıcısına düşer
(`plat_file_contexts:26` `/system(/.*)? → system_file`), kurucunun
`chcon system_file`'ı platform varsayılanıyla birebir aynıdır.

## Ekran yoğunluğu düzeltmesi

`device/samsung/sharkls-common/system.prop` başlığı `# system.prop for j320fn` —
J3 2016'dan miras. Oradaki `ro.sf.lcd_density=320` bu panelde yanlıştır.

Ölçüm (kernel panel DTS'leri, 6 panelin hepsi `kernel/samsung/j1minivelte/arch/arm/boot/dts/`):

```
gen-panel-xres = 480      gen-panel-yres = 800
gen-panel-width = 56 mm   gen-panel-height = 94 mm
çapraz = sqrt(56² + 94²) = 109.4 mm = 4.31"
dpi = sqrt(480² + 800²) / 4.31 = 933.8 / 4.31 = 216.6
```

216.6 dpi → **hdpi (240)**. 320 verilirse 480/320 = 1.5" gibi fiziksel olarak
imkânsız bir genişlik çıkar.

Düzeltme `device/samsung/j1minivelte/system.prop` içinde; `BoardConfig.mk` onu
`TARGET_SYSTEM_PROP` listesinin **başına** koyar:

```make
TARGET_SYSTEM_PROP := device/samsung/j1minivelte/system.prop \
                      device/samsung/sharkls-common/system.prop
```

Mekanizma: `system_prop_file` bir listedir (`build/make/core/Makefile:314` `foreach`)
ve satırlar build.prop'a bu sırayla yazılır. Init'te `ro.*` write-once'tır
(`system/core/init/property_service.cpp:186-193`), yani **ilk satır kazanır**.

Not: `TARGET_SCREEN_DENSITY` bu ağaçta hiçbir yerde tüketilmez — `build/`,
`bootable/`, `vendor/` tarandı, tüketici yok. Bu yüzden yoğunluk prop'tan verilir.

## Root

`su` paketlenir ama **`WITH_SU` BoardConfig'te verilirse çalışmaz**. Ölçülmüş tuzak:

```
build/make/core/envsetup.mk:208   include product_config.mk     <- common.mk burada okunur
build/make/core/envsetup.mk:234   include $(board_config_mk)   <- BoardConfig SONRA
```

`vendor/lineage/config/common.mk:238` `ifeq ($(WITH_SU),true)` testi BoardConfig
yüklenmeden önce koşar; değer boş olduğu için `su` `PRODUCT_PACKAGES`'e hiç girmez.
`get_build_var WITH_SU` sonradan `true` okur — yanıltıcı.

Doğru yer, cihazın product makefile'ı, **ilk `inherit-product`'tan önce**:

```make
# device/samsung/j1minivelte/lineage.mk
WITH_SU := true
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
```

Doğrulama (final `system.img`, `debugfs`):

```
/xbin/su   inode 2844, 0755, uid 0 gid 2000, 276940 B
/bin/su    symlink -> ../xbin/su
/etc/init/superuser.rc
```

SELinux: `(type su)`, `(typetransition shell su_exec process su)`, `(typepermissive su)`
— `adb shell` sonrası `su` çalışır.

## Güvenlik

Flash işlemi **gövde koruması** (body guard) altındadır: cihaz izin listesi, bölüm
izin listesi, boyut sınırı, TTL'li onay kaydı, imaj hash doğrulaması, PIT boyut
denetimi ve TTY zorunluluğu. Onay olmadan hiçbir imaj yazılamaz. Ayrıntı:
`docs/plan.md` §7, `govde/KURULUM.md`, `docs/FLASH.md`.

İki sessiz tuzak ölçülerek kapatıldı:

- Heimdall bölüm adlarını **yalnızca cihazın PIT tablosundan** çözer. Boot
  bölümünün PIT adı `KERNEL`'dir; `--boot` yazmak
  `Partition "boot" does not exist in the specified PIT` verir. Eşleme
  `govde/policy.json:pit_bolum_adi`.
- heimdall **CLI arşiv açmaz** (tar desteği yalnızca `heimdall-frontend`'de).
  `recovery.tar`'ı olduğu gibi yazmak bölüme tar arşivini yazardı. Araç artık
  içindeki `.img`'yi çıkarıp boyutunu PIT'e karşı doğrulayıp onu yazar.

Cihaz kimliği üç kanıt katmanıyla sınanır:

1. **prop** (`ro.product.device` / `ro.build.product`) — en güçlü; yasak cihaz derse dur
2. **dosya adı** — `twrp-j3xlte-recovery.tar` gibi bilerek yazılmış kanıt
3. **ham içerik** — yalnızca ilk ikisi bir şey söylemiyorsa konuşur

3. katmanın zayıf olmasının sebebi ölçülmüştür: J106F çekirdeği dokunmatik panel
firmware'ini `melfas/j1minilte.fw` yoluyla taşır. Ham arama bunu cihaz kimliği sanıp
doğru `recovery.tar`'ı reddediyordu.

Flash öncesi mutlaka yedeklenmeli: `efs`, `l_modem`, `nvitem`, `prodnv`.

### Servis yolu etiketi (SELinux)

Derleme her zaman geçer; `file_contexts` kuralı eksikse hata çıkmaz. Hata
yalnızca cihazda görünür ve **sessizdir**: `init` servis ikilisinden domain
türetemez (`system/core/init/service.cpp:730` `ComputeContextFromExecutable`),
`Start()` false döner, logda tek satır bile çıkmaz.

`TARGET_COPY_OUT_VENDOR` ayarlı olmadığı için `e2fsdroid` imajı `/system/vendor/...`
önekiyle etiketler. AOSP'nin yakalayıcısı
(`system/sepolicy/private/file_contexts:281`)
`/(vendor|system/vendor)(/.*)?` → `vendor_file` olduğu için, cihaz kuralı bu
alternasyonu içermiyorsa **genel etiket kazanır**.

`/(vendor|system/vendor)/bin/rild` kuralı bu yüzden gerekliydi: cihazın kendi
`rild`'i (`device/samsung/sharkls-common/ril/rild`, `BOARD_PROVIDES_RILD=true`
ile AOSP'ninki devre dışı) `bin/rild`'e kurulur; tek `bin/rild` kuralı
`system/sepolicy/vendor/file_contexts:28`'de **`bin/hw/rild`** içindir, o dosya
imajda yok. Sonuç: `rild` + `ril-daemon1` servisleri ENFORCING'de ölü.

İki bağımsız ölçüm aynı sonucu vermeli — biri `file_contexts` metninden
tahmin eder, öbürü imajın gerçek xattr'ını okur:

```bash
python3 scripts/init-denetle.py <system-agaci> - <out>/root
sudo bash scripts/etiket-sayim.sh <system.img>
```

## Bölüm tablosu — gerçek PIT

Cihazın **kendi** PIT tablosu ölçüldü. Stok firmware'in CSC tar'ından çıkarıldı,
repoda durur (`docs/pit/J1MINIVELTE_MEA_JV.pit`), cihazın bağlı olması gerekmez.

| Bölüm | Boyut | Kaybı |
|---|---|---|
| `efs` | 20.971.520 B (20 MiB) | IMEI, şebeke |
| `l_modem` | 16.777.216 B (16 MiB) | RF kalibrasyonu |
| `l_fixnv2` | 1.048.576 B (1 MiB) | NV verisi |
| `prodnv` | 5.242.880 B (5 MiB) | ürün bilgisi |
| `PERSDATA` | 9.437.184 B (9 MiB) | kalıcı veri |
| `PARAM` | 2.097.152 B (2 MiB) | boot parametreleri |

Tam tablo (32 bölüm), kaynak sha256'ları ve çözülen boyut çelişkisi:
`docs/PIT-GERCEK.md`.

## Doğrulama

`scripts/dogrula.sh` — 18/18. Çıktıların var olduğunu ve cihaza uygunluğunu sınar.
Bölüm sınırları artık **sabit yazılmaz**: `docs/pit/*.pit`'ten okunur. Sabit
yazmak yanlış bir değeri doğru gibi gösterir — çözülen hata tam buydu.

Kanıt scriptleri, "derledim" ile "cihaza giden şey gerçekten o" arasındaki
boşluğu kapatır. Hiçbiri diğerinin yerine geçmez:

| Script | Kanıtladığı |
| --- | --- |
| `boot-zinciri.py` | etkin cmdline → `ro.hardware`, rc import grafiği, ramdisk yerleşimi |
| `init-denetle.py` | her init servis ikilisi yerinde + etiketli + domain geçişi tanımlı |
| `etiket-sayim.sh` | aynı soruyu imajın **gerçek xattr**'ından yanıtlar (init-denetle metinden tahmin eder; ikisi bağımsız ölçüm) |
| `elf-kapanis.py` | `DT_NEEDED` kapanışı + çözülemeyen sembol (sessiz yükleyici hatası sınıfı) |
| `kernel-kanit.sh` | zip içindeki `boot.img` çekirdeğinde `binder,hwbinder,vndbinder` var |
| `ota-sistem-kanit.sh` | zip içindeki sistem, doğrulanmış `system.img` ile **bit bit** aynı |
| `gapps-denetle.sh` | GApps yükü cihaza uyuyor mu: mimari, çakışma, yer, sessiz-hata kapıları |
| `stok-indir.sh` | stok firmware'i indirir, **gerçek PIT'i** ve referans imajları çıkarır (cihaz gerekmez) |
| `pit-coz.py` | ham `.pit` ikilisini ve `heimdall print-pit` metnini tek tabloya indirir |
| `pit-dogrula.sh` | derleme boyutlarını **cihazın gerçek PIT'iyle** ve derlenen imajlarla karşılaştırır |
| `govde-test.sh` | koruma red matrisi + PIT ayrıştırıcı (cihaz gerekmez) |
| `kanca-test.mjs` | guard kancasının kararı, model devre dışı (canlı denemede modelin kendi reddi karışabilir) |
| `govde/j106f-flash.mjs` | yanlış imajın yazılması teknik olarak imkânsız |

### stok-indir.sh + pit-coz.py + pit-dogrula.sh

Bölüm boyutları hakkındaki çelişki **ölçümle** kapandı: cihazın gerçek PIT'i stok
firmware'in CSC tar'ı içinde gelir, cihazın bağlı olması gerekmez.

```
archive.org -> stok zip (1.490.482.384 B, sha256 doğrulandı)
    -> CSC tar -> J1MINIVELTE_MEA_JV.pit (5.276 B, magic 0x12349876, 32 girdi)
    -> pit-coz.py -> tablo
```

İki bağımsız okuma yolu aynı 32 satırı verir (sınandı):

```
python3 scripts/pit-coz.py docs/pit/J1MINIVELTE_MEA_JV.pit --tsv   # ham ikili
python3 scripts/pit-coz.py /tmp/print-pit.txt              --tsv   # heimdall metni
diff -> aynı
```

Ölçülen sonuç — `sharkls-common`'dan miras değerler **doğru**:

| Bölüm | Derleme | Cihaz (PIT) | Sonuç |
|---|---|---|---|
| KERNEL | 20.971.520 | 20.971.520 | eşit |
| RECOVERY | 20.971.520 | 20.971.520 | eşit |
| CACHE | 209.715.200 | 209.715.200 | eşit |
| SYSTEM | 2.147.483.648 | 2.902.458.368 | sığar (derleme küçük) |

Dolaşımdaki `10.978.320` değeri **bölüm boyu değil**: twrpdtgen onu
`image_info.origsize`'tan alır (`device_tree.py:56` =
`aik_manager.unpackimg(image)`), yani dump edilen imajın dosya boyutu. Stok
`recovery.img` 10.974.224 B — yapıntı tezi bağımsız doğrulanır. Ayrıca 10.978.320
512'ye **bölünmez** (21.442,03 blok); bir bölüm boyu sektör hizalı olmak zorunda.
Ayrıntı: `docs/PIT-GERCEK.md`.

Bootloader cmdline'ı da ölçüldü: stok `sboot.bin` içinde
`mem=1024M init=/init ram=1024M androidboot.hardware=sc8830` geçiyor — yani
anahtar stok bootloader'dan geliyor. Stok `j1minive3g-dt_defconfig` onu ayrıca
`CONFIG_CMDLINE`'da taşıyor ve `CONFIG_CMDLINE_EXTEND=y` ile birleştiriyor;
ikisi çakışmıyor.

### kernel-kanit.sh

`strings zImage | grep hwbinder` **yanlış negatif** verir: çekirdek sıkıştırılmış
bir zImage'dir ve dize iç gzip akışının içindedir. Script doğru yolu izler:

```
zip -> boot.img -> ANDROID! başlığı -> çekirdek dilimi -> iç gzip -> dize sayımı
```

Ölçüldü: çekirdek 5.492.592 B, iç gzip ofseti `0x4131`, çözülen 12.481.912 B,
`binder,hwbinder,vndbinder` sayısı 1, sürüm `3.10.65-g19cb2671-dirty`.

### ota-sistem-kanit.sh

Android 8.1 blok-OTA kullanır: zip içinde `system.img` yoktur,
`system.new.dat.br` + `system.transfer.list` vardır. "Zip'te system var" demek
yetmez; **içeriğin** derlenen sistem olduğunu göstermek gerekir.

```
zip -> brotli -> transfer.list blok haritası -> ham ext4
    -> debugfs rdump -> dosya dosya sha256
```

Ölçüldü: 2678 girdi (dosya + symlink) yapı birebir aynı, 2098 normal dosya
sha256 birebir aynı.

### govde-test.sh

Korumanın red matrisini ve PIT ayrıştırıcısını cihazsız sınar. Hiçbir şey yazmaz.

```
✔ yanlis cihaz (dosya adi j3xlte)   ✔ yasak bolum (efs)
✔ izinli olmayan uzanti             ✔ bolum belirtilmedi
✔ TTY kapisi                        ✔ PIT alan sirasi + MMC/UFS blok boyutu
```

PIT ayrıştırıcısı kaynaktan doğrulandı (`heimdall/source/Interface.cpp:214-320`):
alan sırası `Device Type` → `Partition Block Count` → `Partition Name`. Tek bir
"Name ... Count" regex'i **yanlış girdiyi** yakalar. Blok boyutu `MMC`=512,
`UFS`=4096 (`FlashAction.cpp:331-334`).

`transfer.list` tuzağı: `new 2,0,1024` iki tam sayı = **tek** `(baş,bitiş)`
aralığı `[0,1024)`, yani 1024 blok. Değerleri tek tek blok sanmak imajı bozar —
ilk denemede 456 blok yazıldı ve dosya sistemi okunamadı.

## Belgeler

- `docs/plan.md` — ana plan, kararlar, riskler
- `docs/ISP-BULGU.md` — ISP arayüz uyuşmazlığı ve çözümü (kritik)
- `docs/BINDER-BULGU.md` — binder ABI uyuşmazlığı ve çözümü (kritik, boot blocker)
- `docs/YUKLEYICI-BULGU.md` — sessiz yükleyici hataları: eksik `DT_NEEDED`,
  çözülemeyen sembol (kritik, hiç hata mesajı üretmez)
- `docs/PIT-GERCEK.md` — cihazın gerçek bölüm tablosu, ölçülmüş; boyut çelişkisinin
  çözümü ve bootloader cmdline kanıtı
- `docs/arastirma-raporu.md`, `docs/arastirma-raporu-2.md` — ROM araştırması
