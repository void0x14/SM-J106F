# SM-J106F → Android 8.1 (Oreo) — Plan

**Cihaz:** Samsung Galaxy J1 Mini Prime **SM-J106F** — Spreadtrum **SC9830A** (SCX35L), Cortex-A7 32-bit ARMv7, Mali-400 MP2, 1 GB RAM, 8 GB eMMC, kernel **3.10.65**, stok 6.0.1, Treble yok, fastboot yok → **sadece Odin/AP**.
**Hedef:** Android 8.0/8.1, Google servisleri çalışır, sandbox yok, süreç AI-driven + gövde koruması.
**Kısıt:** Redmi 9 tamir edilmeyecek. Eldeki tek cihaz bu. Bu telefonda Android 8+ olacak.

---

## 0. Ana sonuç

Aynı SoC ailesinde Android 8.1 **boot ediyor**. Ve artık elimizde J106F'in kendi çip ailesi (SC9830/sc8830) için **tam bir LineageOS 15.1 ağacı** var: `djeman` geliştiricisinin J3 2016 / Galaxy Tab A6 ağacı.

| Referans | SoC | Kernel | RIL | Durum |
|---|---|---|---|---|
| **djeman sharkls (J3 2016 / Tab A6)** | SC9830I | 3.10.100 | **var** (`BOARD_PROVIDES_RILD`) | Derlenebilir ağaç; `board-j1minilte.c` + `board-j1acevelte.c` içinde |
| Grand Neo VE Plus GT-I9060I | SC8830 | 3.10.89 | **çalışıyor** | Boot ediyor, indirilebilir |
| Core 2 SM-G355H (kanas) | SC7735S | 3.10.108 | kırık | Boot ediyor |
| J3 2016 (notnoelchannel) | SC9830I | 3.10.x | — | **boot etmiyor** — "software rendering" |

`djeman` ağacı bizim için en değerli olan: aynı çip, aynı `mach-sc` mimarisi, aynı modem ailesi (`ro.modem.l.*`), ve RIL'i **kaynak seviyesinde** çözüyor.

---

## 1. djeman SC9830 Oreo ağacı — tam yapı

```
device/samsung/sharkls-common   (lineage-15.1)  13.7 MB
device/samsung/j3xlte           (lineage-15.1)   6.3 KB
kernel/samsung/sharkls          (lineage-15.1) 118.7 MB   Linux 3.10.100
vendor/samsung/common           (lineage-15.1)  13.8 MB
```

### 1.1 RIL — kaynak seviyesinde çözülmüş

`BoardConfigCommon.mk` (birebir):
```make
# telephony
BOARD_PROVIDES_LIBRIL := true
BOARD_PROVIDES_RILD := true
USE_BOOT_AT_DIAG := true
BOARD_RIL_CLASS := ../../../$(PLATFORM_PATH)/ril/java/

# SHIMS
TARGET_LD_SHIM_LIBS := \
    /system/vendor/bin/gpsd|/system/vendor/lib/libgpsshim.so \
    /system/vendor/lib/libsec-ril.so|/system/vendor/lib/libprotobufshim.so \
    /system/vendor/lib/libsec-ril-dsds.so|/system/vendor/lib/libprotobufshim.so
```

→ Oreo'da Samsung RIL blob'u (`libsec-ril.so`) **protobuf shim ile** çalıştırılıyor. Bu, `libsecril-shim` yolundan farklı ve daha doğrudan bir çözüm.

`libshims/` içeriği: `libgpsshim.cpp`, `libprotobufshim.cpp`, `libimsshim.c`

`manifest.xml` RIL girdisi (HIDL 1.0, iki SIM yuvası):
```xml
<hal format="hidl"><name>android.hardware.radio</name>
  <transport>hwbinder</transport><version>1.0</version>
  <interface><name>IRadio</name><instance>slot1</instance><instance>slot2</instance></interface>
  <interface><name>ISap</name><instance>slot1</instance><instance>slot2</instance></interface></hal>
<hal format="hidl"><name>android.hardware.radio.deprecated</name>
  <transport>hwbinder</transport><version>1.0</version>
  <interface><name>IOemHook</name><instance>slot1</instance><instance>slot2</instance></interface></hal>
```

Modem props `system.prop` içinde hazır: `ro.modem.l.*` (LTE), `ro.modem.t.*`, `ro.modem.tl.*`, `ro.modem.lf.*`, `ro.modem.wcn.*` + `persist.modem.*`.

### 1.2 Oreo uyumluluk yamaları — 12 dosya

`patches/sprd-diff/` (uygulama: `patches/apply_sprd-diff.sh`, `patch -p1`):
```
frameworks_base.diff        frameworks_native.diff     frameworks_av.diff
hardware_ril.diff           hardware_interfaces.diff   system_core.diff
system_media.diff           system_bt.diff             external_tinyalsa.diff
packages_apps.diff          bootable_recovery.diff     bootable_recovery-twrp.diff
```

### 1.3 Kernel — çok-cihazlı SC9830 ağacı

`arch/arm/mach-sc/` içinde **J106F ailesinin board dosyaları zaten var**:
```
board-j1minilte.c      board-j1acevelte.c     board-j3xlte.c     board-j3xnlte.c
board-gtexslte.c       board_common_battery.c
```
`Kconfig` girdileri: `MACH_J1MINILTE` (satır 482), `MACH_J1ACEVELTE` (464), `MACH_J3XLTE` (493), `MACH_J3XNLTE` (504), `MACH_GTEXSLTE` (526).

Defconfig'ler: `j3xlte_permissive_defconfig`, `j3xnlte_permissive_defconfig`, `j3xlte_defconfig`, `j3xnlte_defconfig`

Doğrulanan flag'ler (`j3xlte_permissive_defconfig`): `CONFIG_ARCH_SCX35=y`, `CONFIG_SDCARD_FS=y`, `CONFIG_ANDROID_BINDER_IPC=y`, `CONFIG_SECURITY_SELINUX=y`, `CONFIG_SWAP=y`, `CONFIG_ION_SPRD=y`, `CONFIG_VIDEO_GSP_SPRD=y`, `CONFIG_FB_LCD_DUMMY=y`.

Kernel kendi içinde `drivers/gpu/mali400` **içermiyor** (`drivers/gpu/` = drm, host1x, ion, sprd_iommu, vga) → Mali ayrı derleniyor.

### 1.4 Mali-400 — iki kaynak yolu

**Yol A (djeman):** `modules.mk` GPU'yu ayrı derliyor:
```make
GPU_DRIVER_PATH := vendor/sprd/modules/libgpu/gpu/utgard
make -C $(GPU_DRIVER_PATH) MALI_PLATFORM=sc8830 BUILD=$(MBUILD_VAR) KDIR=$(KERNEL_OUT) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE)
mv $(GPU_DRIVER_PATH)/mali.ko $(KERNEL_MODULES_OUT)
```
`TARGET_GPU_PLATFORM := utgard`. **Sorun:** `github.com/djeman/android_vendor_sprd` **HTTP 451 (DMCA) — kaldırılmış**. Utgard DDK kaynağı başka yerden bulunmalı.

**Yol B (J106F'e özel, doğrulandı):** `fuckyousamsung/android_kernel_samsung_j106b` (kernel **3.10.65**) içinde Mali kaynağı **in-tree**:
```
drivers/gpu/mali400/Kconfig          → menuconfig MALI400 "Mali-300/400/450 support", default MALI_VER_R4P1
drivers/gpu/mali400/Makefile         → obj-$(CONFIG_MALI_VER_R4P1) += r4p1/
drivers/gpu/mali400/r4p1/            → mali_kernel_linux.c, platform/arm/arm.c, common/, include/, regs/
arch/arm/configs/j1minive3g-dt_defconfig:
  CONFIG_MALI400=y            (satır 1095)
  CONFIG_MALI_VER_R4P1=y      (satır 1096)
  CONFIG_MALI400_PROFILING=y
  CONFIG_MALI_DMA_BUF_MAP_ON_ATTACH=y
  CONFIG_MALI_SHARED_INTERRUPTS=y
  CONFIG_MACH_SCX35_DT=y
  CONFIG_MACH_VIVALTO5MVE3G=y   ← dikkat: J1MINIVE3G değil (satır 361)
```
`arch/arm/mach-sc/Kconfig:1140` → `config MACH_J1MINIVE3G / bool "pikeb_j1minive3g Board" / depends on ARCH_SCX35` ✔ mevcut.
`board-pikeb_j1minive3g.c` ✔ mevcut.

**dr-8 düzeltmesi — Yol B'nin iki tuzağı (doğrulandı):**

1. **`CONFIG_MODULES` kapalı.** J106F'in sevk edilen defconfig'inde modül desteği yok. Yani Mali sürücüsü `mali.ko` olarak **üretilmez**, çekirdeğe **gömülü** derlenir (`CONFIG_MALI400=y`). Bu bir engel değil, tersine djeman'ın `mv .../mali.ko $(KERNEL_MODULES_OUT)` adımını **tamamen ortadan kaldırır**: ayrı `modules.mk` GPU bloğu gerekmez, DMCA'lı utgard kaynağı hiç gerekmez.
2. **`CONFIG_MALI_PLATFORM_SC8830` defconfig sembolü olarak yok.** sc8830 platform seçimi `drivers/gpu/mali400/r4p1/Makefile` içindeki `ifeq ($(CONFIG_MALI_PLATFORM_SC8830),y)` koşuluyla yapılır → `MALI_PLATFORM := sc8830`, `TARGET_PLATFORM := sc8830`. BoardConfig'e bu değişkeni geçirmek yeterli; `defconfig`'e sembol eklemeye çalışmak boşa çıkar.

**Ama bu yol artık kullanılmayacak** — bkz. §1.4b: J106F'in kendi kernel ağacında in-tree Mali yok, `vendor/sprd` utgard yolu kullanılacak.

### 1.4b Karar değişikliği — J106F'in **kendi** kernel ağacı daha üstün

`lasania32198/android_kernel_samsung_j1minivelte` (Linux 3.10.65) incelendi. j106b'den **ölçülebilir şekilde üstün**:

| Ölçüt | `fuckyousamsung/…j106b` | `lasania32198/…j1minivelte` |
|---|---|---|
| Board sembolü | `MACH_J1MINIVE3G` tanımlı **ama defconfig `CONFIG_MACH_VIVALTO5MVE3G=y` seçiyor** — ve bu sembol **hiçbir Kconfig'de tanımlı değil** (yalnızca `sm5701_charger.c` içinde `#if` olarak geçiyor) → **ölü yapılandırma** | `CONFIG_MACH_J1MINIVELTE=y`, `arch/arm/mach-sc/Kconfig:613` tanımlı, `Makefile:28` `obj-$(CONFIG_MACH_J1MINIVELTE) += board-j1minivelte.o` |
| DT compat | `sprd_boards_compat[] = {"sprd,scx35"}` **ama** DTS `compatible = "sprd,sp8835eb"` → **uyuşmuyor** | `sprd_boards_compat[] = {"sprd,sp8835eb"}` ↔ DTS `compatible = "sprd,sp8835eb"` → **uyuşuyor** |
| DTS | `sprd-scx20_j1minive3g_r00.dts` (scx20 serisi, 3G) | `sprd-scx35l_sharkls_j1minivelte_rev00.dts` + `rev01` — **LTE, kendi adıyla** |
| Panel DTSI | `st7701_j1mini3g` + `s6d77a1a01_j1mini3g` | `st7701_j1minilte_mea` + `s6d77a1a01_j1minilte` — **J106F'in kendi paneli** |
| Memreserve (DTS) | fb `0x9F8AD000`, ion `0x9FD12000` | fb `0x9EFFC000`, ion `0x9F5FC000` — J106F'in gerçek düzeni |
| `CONFIG_MODULES` | **kapalı** | `CONFIG_MODULES=y` (satır 209) → WiFi `sc2331` modülü ayrı derlenebilir |
| `CONFIG_PSTORE_RAM` | yok | **var** (3064) → boot hatalarında ramoops |
| `CONFIG_ARCH_SCX35L` | yok | **var** (311) — `MACH_J1MINIVELTE` bunu şart koşuyor |
| Mali | r4p1 in-tree (ama kullanılmayan yol) | in-tree yok → `vendor/sprd/.../utgard`'dan (Yol A) |

→ **Yeni karar: `lasania32198/android_kernel_samsung_j1minivelte` ana kernel.** j106b sadece yedek.

Bunun sonucu: **Mali-400 artık `vendor/sprd` utgard yolundan derlenecek** (djeman'ın `modules.mk` `GPU_DRIVER_PATH`'i aynen çalışır), çünkü bu kernelde in-tree r4p1 yok. `Talustus/android_vendor_sprd` (lineage-15.1) `modules/libgpu/gpu/utgard/platform/sc8830/` içeriyor → **DMCA engeli yok**.

### 1.4c `vendor/sprd` — DMCA engeli aşıldı

`djeman/android_vendor_sprd` HTTP 451. Ama aynı içerik başka fork'ta canlı:

- **`Talustus/android_vendor_sprd`, dal `lineage-15.1`** — doğrulandı:
  - `modules/libgpu/gpu/utgard/Makefile` → **HTTP 200**, `platform/sc8830/mali_platform.c` mevcut
  - `proprietaries/proprietaries-scx35l.mk` → **HTTP 200** (`sharkls.mk` bunu `inherit-product` ediyor — olmazsa derleme durur)
  - `wcn/wifi/sc2331/6.0/Makefile` → **HTTP 200** (`modules.mk` `WLAN_DRIVER_PATH` bunu kullanır)
  - Klonlandı: 332 MB, `external/ gps/ modules/ open-source/ proprietaries/ wcn/`

→ Manifest'te `vendor/sprd` bu fork'a bağlanacak.

### 1.5 Grafik katmanı — dr-8'in "kritik boşluk" bulgusu ÇÜRÜDÜ

dr-8, "ağaçta gralloc0→gralloc1 uyarlaması yok, J3 portu bu yüzden boot etmedi" dedi. **Bu yanlıştı.** Gerçek AOSP `lineage-15.1` kaynağında her iki katman da hazır:

| Ne | Nerede | Durum |
|---|---|---|
| `Gralloc0Mapper.cpp` + `Gralloc1Mapper.cpp` | `hardware/interfaces/graphics/mapper/2.0/default/` | **İkisi de var**; `Android.bp` `srcs: ["GrallocMapper.cpp", "Gralloc0Mapper.cpp", "Gralloc1Mapper.cpp"]` — ikisi birlikte derlenir |
| `Gralloc0Allocator.cpp` + `Gralloc1Allocator.cpp` | `hardware/interfaces/graphics/allocator/2.0/default/` | **İkisi de var** |
| Çalışma-zamanı seçimi | `allocator/2.0/default/Gralloc.cpp` | `module_api_version >> 8` → `major==1` Gralloc1, `major==0` Gralloc0. **Stok `gralloc.sc8830.so` gralloc0'dır → `Gralloc0Allocator` seçilir** |
| HWC1→HWC2 adaptörü | `frameworks/native/libs/hwc2on1adapter/HWC2On1Adapter.cpp` | **Ağaçta mevcut** |
| Çalışma-zamanı seçimi | `composer/2.1/default/Hwc.cpp:52-67` | `majorVersion != 2` → `HWC2On1Adapter` sarar; `minorVersion < 1` ise `abort()`. **Stok SPRD HWC1.1+ ise sorunsuz** |
| `libgralloc1-adapter` (`gralloc1-adapter.cpp` + `Gralloc1On0Adapter.cpp`) | `allocator/2.0/default/Android.bp` | Ayrıca mevcut — gralloc1 API'sini gralloc0'a çeviren ikinci yol |

**J106F stok blob doğrulaması:**
- `lib/hw/gralloc.sc8830.so` → `strings | grep -iE "gralloc1|mapper@2|IAllocator"` → **hiç eşleşme yok** = saf gralloc0. `Gralloc0Allocator` yolu doğru.
- `lib/hw/hwcomposer.sc8830.so` → NEEDED listesi `libhardware.so`, `libui.so`, `libsync.so` taşır; HWC1 blob'u. `HWC2On1Adapter` sarar.

→ **Sonuç:** Grafik katmanı **ek yama gerektirmiyor**. dr-8'in önerdiği `GRALLOC1_LAST_FUNCTION = 22→23` hack'i ve `Gralloc1On0Adapter` geri-getirme işi **gereksiz**. J3 portunun boot etmemesinin nedeni bu değil.

**Adım 4b iptal.** Tek şart: `USE_SPRD_HWCOMPOSER := true` ile gelen SPRD HWC blob'u **HWC1.1 veya üstü** olmalı (`minorVersion >= 1`); HWC1.0 ise `Hwc.cpp` `abort()` eder. Ölçüm: derleme sonrası `strings hwcomposer.sc8830.so | grep -i "hwc_composer_device_1"` + `hwcomposer` açılış logu.

### 1.6 RIL — J106F blob'u doğrulandı

İki blob karşılaştırıldı (`readelf -d` NEEDED listeleri):

| | J106F stok (`lasania32198/android_vendor_samsung_j1minivelte`) | djeman J3 (`sharkls-common/ril/vendor/`) |
|---|---|---|
| BuildID | `6c13c841a9b4eaa38bc8f33844b1e2a2` | `e22a9fe3cf70f4b882b61ccc6199176b` |
| md5 | `6de6f486d5f583892d57fefaa676d773` | `bcd9f81523a8e7b8d8d397b39e878325` |
| ELF | 32-bit ARM, Android 23, stripped | aynı |
| NEEDED | `libcutils libril libnetutils libsqlite libhardware_legacy libcrypto librilutils libxml2 libsecnativefeature libc++ libdl` **`libprotobuf-cpp-full`** `libc libm` | **birebir aynı liste** |

→ **Sonuç:** J106F'in kendi RIL blob'u `libprotobuf-cpp-full.so`'ya bağlanıyor, tam djeman'ın `TARGET_LD_SHIM_LIBS` satırının beklediği gibi (`libsec-ril.so|libprotobufshim.so`). **Shim uyumu yapısal olarak doğrulandı**; djeman'ın J3 blob'una düşmeye gerek yok.

Ayrıca `lasania32198/android_vendor_samsung_j1minivelte` (53 MB, 198 dosya) J106F'in **tüm** stok blob setini taşıyor: `lib/hw/{gralloc,hwcomposer,sprd_gsp,sensors,camera,lights,power}.sc8830.so`, `lib/egl/libGLES_mali.so`, `lib/libsec-ril.so` + `-dsds`, `libsecril-client.so`, `libsecnativefeature.so`, `bin/`, `etc/`.

**Kalan belirsizlik:** `device-vendor-blobs.mk` jeneratör çıktısı ve 2016 tarihli — `system/vendor` yolları kullanıyor; Oreo'da `TARGET_COPY_OUT_VENDOR := vendor` ile uyumlu ama yollar **elle gözden geçirilmeli**. `j1minivelte-vendor.mk` → `vendor/samsung/j1minivelte-vendor-blobs.mk` bekliyor (depo kökünde var, `j1minivelte/` altında değil) → dizin yapısı düzeltilecek.

---

## 2. Kernel kaynakları — karşılaştırma

| Repo | Sürüm | Mali | Defconfig | Karar |
|---|---|---|---|---|
| **`lasania32198/android_kernel_samsung_j1minivelte`** | 3.10.65 | yok (utgard'dan) | `j1minivelte_defconfig` | **ANA TEMEL** — kendi board/DTS/panel/memreserve (§1.4b) |
| `fuckyousamsung/android_kernel_samsung_j106b` | 3.10.65 | r4p1 in-tree | `j1minive3g-dt_defconfig` | Yedek; defconfig'i ölü sembol seçiyor |
| `naimrlet/android_kernel_samsung_j1minive3g` | 3.10.65 | yok | `j1minive3g-dt_defconfig` | Kullanılmıyor |

---

## 3. Uygulama planı

### Adım 0 — Kaynak ağacı (TAMAMLANDI)

`/home/void0x14/j106f/build/android` — `repo init -u https://github.com/LineageOS/android.git -b lineage-15.1`, `repo sync -c -j8` **başarıyla bitti** (65 GB).

`repo` aracı `/home/void0x14/j106f/build/bin/repo` içinde (PATH'e eklenir).

### Adım 1 — Manifest (TAMAMLANDI)

`.repo/local_manifests/j106f.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="dj"   fetch="https://github.com/djeman" />
  <remote name="fk"   fetch="https://github.com/fuckyousamsung" />
  <remote name="ln"   fetch="https://github.com/LineageOS" />
  <remote name="omni" fetch="https://github.com/omnirom" />

  <project path="device/samsung/sharkls-common" name="android_device_samsung_sharkls-common" remote="dj" revision="lineage-15.1" />
  <project path="kernel/samsung/j1minive3g"      name="android_kernel_samsung_j106b"             remote="fk" revision="master" />
  <project path="vendor/samsung/common"          name="android_vendor_samsung_common"           remote="dj" revision="lineage-15.1" />

  <project path="hardware/samsung"               name="android_hardware_samsung"                remote="ln" revision="lineage-15.1" />
  <project path="external/sony/boringssl-compat" name="android_external_sony_boringssl-compat"   remote="ln" revision="lineage-15.1" />

  <project path="bootable/recovery-twrp"         name="android_bootable_recovery"               remote="omni" revision="android-8.1" />
  <project path="external/busybox"               name="android_external_busybox"                remote="omni" revision="android-8.1" />
</manifest>
```

**Yapılacak değişiklikler:**
1. `kernel/samsung/j1minive3g` → `lasania32198/android_kernel_samsung_j1minivelte` (yeni remote `las`, `main` dalı), path `kernel/samsung/j1minivelte`.
2. `vendor/sprd` **manifest'e konmayacak** — `repo` `--depth=1` klonuyla çakışıyor (`unsupported checkout state`). Elle klonlanacak (Adım 1b).

### Adım 1b — vendor/sprd (DMCA aşıldı, TAMAMLANDI)

```bash
cd /home/void0x14/j106f/build/android
git clone --depth=1 -b lineage-15.1 https://github.com/Talustus/android_vendor_sprd vendor/sprd
```
332 MB. `repo sync` bunu **siler** (manifest'te yok) → sync'ten **sonra** klonlanacak veya `.git` yerine manifest'e `--force-sync` olmadan eklenecek.

### Adım 2 — Device tree türet

`device/samsung/j1minivelte/` oluşturulacak. Temel: `sharkls-common` + j3xlte'nin 11 dosyası + J106F'e özel init.

**BoardConfig.mk:**
```make
-include device/samsung/sharkls-common/BoardConfigCommon.mk

TARGET_KERNEL_CONFIG := j1minivelte_defconfig
TARGET_KERNEL_SOURCE := kernel/samsung/j1minivelte

TARGET_INIT_VENDOR_LIB := libinit_j1minivelte
TARGET_RECOVERY_DEVICE_MODULES := libinit_j1minivelte
```

**BoardConfigCommon.mk'de J106F'e uyarlanacak satırlar** (sharkls-common'ı **değiştirmeden**, j1minivelte'nin kendi BoardConfig'inde `:=` ile ezer):
```make
TARGET_OTA_ASSERT_DEVICE := j1minivelte,j1minivelteub,j1miniveltejv,j1minive3g,SM-J106F
TARGET_BOOTLOADER_BOARD_NAME := SC9830I
DEVICE_RESOLUTION := 480x800
TARGET_SCREEN_HEIGHT := 800
TARGET_SCREEN_WIDTH := 480
TARGET_CPU_VARIANT := cortex-a7
```
Kamera (J106F'in gerçek sensörü stok blob'dan doğrulanacak):
```make
CAMERA_SENSOR_TYPE_BACK := "s5k4h5yc_mipi"    # doğrulanacak
CAMERA_SENSOR_TYPE_FRONT := "s5k5e3yx_mipi"   # doğrulanacak
```

**init/init_j1minivelte.cpp** — j3xlte'nin `init_j3xlte.cpp`'si örnek; J106F için:
- `ro.bootloader` içinde `J106F` ara → `ro.product.model = SM-J106F`
- `/proc/simslot_count` → `ro.multisim.simslotcount`, `ro.msms.phone_count`, `ro.modem.w.count`, `persist.msms.phone_count`
- **J106F tek-SIM ise** `persist.radio.multisim.config` yazılmayacak (J106F vs J106F/DS ayrımı bootloader'dan okunacak)
- `ANDROID_TARGET` = `sc8830`

**sharkls-common'da değiştirilecek 3 yer** (J106F'e özel kopya yerine ortak dosyada filtre):
- `Android.mk` `ifneq ($(filter j3xnlte j3xlte,$(TARGET_DEVICE)),)` → `j1minivelte` ekle
- `sharkls.mk` ramdisk listesi: `init.j3xnlte.rc` + `init.j3xnlte_base.rc` → j1minivelte sürümleri
- `rootdir/Android.mk` ilgili prebuilt girdileri

Panel: `CONFIG_FB_LCD_DUMMY=y` + `CONFIG_SPRDFB_GEN_PANEL=y` zaten defconfig'de; DTS `st7701_j1minilte_mea` + `s6d77a1a01_j1minilte` include ediyor → **dokunma**.

### Adım 3 — Oreo yamaları
`device/samsung/sharkls-common/patches/apply_sprd-diff.sh` çalıştır (12 diff, `patch -p1`).

### Adım 4 — Blob'lar (TAMAMLANDI)

`lasania32198/android_vendor_samsung_j1minivelte` klonlandı → `/home/void0x14/j106f/kaynak/ref/android_vendor_samsung_j1minivelte` (53 MB, 198 dosya). J106F'in **kendi** stok 6.0.1 blob seti:

```
lib/egl/libGLES_mali.so        lib/egl/libGLES_android.so
lib/hw/gralloc.sc8830.so       lib/hw/hwcomposer.sc8830.so
lib/hw/sprd_gsp.sc8830.so      lib/hw/sensors.sc8830.so
lib/hw/camera.sc8830.so        lib/hw/lights.sc8830.so
lib/hw/power.sc8830.so         lib/libion.so
lib/libmemoryheapion.so        lib/librilutils.so
lib/libsec-ril.so              lib/libsec-ril-dsds.so
lib/libsecril-client.so        lib/libsecnativefeature.so
bin/  etc/  usr/keylayout/  vendor/lib/mediadrm/
```

**Dizin yapısı düzeltmesi gerekli:** depo kökünde `j1minivelte-vendor-blobs.mk` var, ama `j1minivelte/j1minivelte-vendor.mk` `vendor/samsung/j1minivelte-vendor-blobs.mk`'yi bekliyor. Dosyalar `vendor/samsung/j1minivelte/` altına `proprietary/` + `j1minivelte-vendor.mk` + `device-vendor-blobs.mk` + `BoardConfigVendor.mk` olarak yerleşecek.

**RIL blob uyumu — DOĞRULANDI (§1.6):** J106F `libsec-ril.so` NEEDED listesi djeman'ın J3 blob'uyla birebir aynı, `libprotobuf-cpp-full.so` dahil → `libprotobufshim` uyumlu.

**Yol yolları gözden geçirilecek:** `device-vendor-blobs.mk` 2016 jeneratör çıktısı, `system/vendor/...` yolları kullanıyor. Oreo `TARGET_COPY_OUT_VENDOR := vendor` ile uyumlu ama elle doğrulanacak.

### Adım 4b — Grafik katmanı: **iş yok** (bkz. §1.5)

AOSP `lineage-15.1` `Gralloc0Mapper`/`Gralloc0Allocator`/`HWC2On1Adapter`'ı zaten taşıyor ve `module_api_version` ile çalışma zamanında seçiyor. J106F'in stok `gralloc.sc8830.so`'su saf gralloc0, `hwcomposer.sc8830.so`'su HWC1 — ikisi de desteklenen yol. Ek yama yok.

Tek kontrol: HWC blob sürümü `>= 1.1` olmalı.

### Adım 5 — Derle

Ağaç hazır (`/home/void0x14/j106f/build/android`, sync bitti). Kalan: j1minivelte device tree + vendor/sprd + kernel swap.

```bash
cd /home/void0x14/j106f/build/android
export PATH="/home/void0x14/j106f/build/bin:$PATH"

# 1. device tree
mkdir -p device/samsung/j1minivelte
# (Adım 2'ye göre doldur)

# 2. vendor/sprd (sync'ten SONRA, manifest'te olmadığı için)
git clone --depth=1 -b lineage-15.1 https://github.com/Talustus/android_vendor_sprd vendor/sprd

# 3. kernel swap: j106b → j1minivelte
git clone --depth=1 https://github.com/lasania32198/android_kernel_samsung_j1minivelte kernel/samsung/j1minivelte

# 4. yamalar
bash device/samsung/sharkls-common/patches/apply_sprd-diff.sh

# 5. derle
. build/envsetup.sh
lunch lineage_j1minivelte-userdebug
mka bacon -j$(nproc)
```

### Adım 6 — Flash (gövde koruması kapısı)

Kapı kurulu ve test edildi (§7). Kullanıcı kendi terminalinde:
```bash
j106f-flash incele recovery.tar --bolum recovery
j106f-flash flash  recovery.tar --bolum recovery          # kuru
j106f-flash flash  recovery.tar --bolum recovery --gercek # gerçek
```

Sıra:
```
1. İmaj SHA256 + ro.product.device assert (izinli_cihaz_kodlari listesi)
2. Yasak bölüm kontrolü (bootloader/efs/nvdata/persist...)
3. TTY + parola + sha256 öneki + "YAZ <bolum>" onayı
4. TWRP (Nazarikov, 4PDA 886898) → EFS/modem yedeği → Wipe System/Data/Cache/Dalvik
5. ROM → GApps (arm 8.1 pico) → reboot
```
**EFS/modem yedeği ZORUNLU.** TWRP fstab'da `efs`, `l_modem`, `nvitem`, `prodnv` bölümleri var → hepsi yedeklenecek.

---

## 4. Riskler (dürüst)

| # | Konu | Olasılık | Dayanak |
|---|---|---|---|
| 1 | Grafik / gralloc0 + HWC1 | **Düşük** | AOSP Oreo `Gralloc0Mapper`/`Gralloc0Allocator`/`HWC2On1Adapter`'ı zaten taşıyor, `module_api_version` ile seçiyor; J106F blob'ları saf gralloc0 + HWC1 (bkz. §1.5) |
| 2 | Boot (kernel → init → servisler) | Yüksek | 4 SCX35 cihaz boot ediyor; J106F'in **kendi** board/DTS/kernel ağacı bulundu (bkz. §1.4b) |
| 3 | RIL | Orta | J106F'in kendi `libsec-ril.so` blob'u var ve NEEDED listesi djeman'ın J3 blob'uyla **birebir aynı** (`libprotobuf-cpp-full.so` dahil) → `libprotobufshim` uyumlu (bkz. §1.6) |
| 4 | WiFi/BT/Ses/Sensör/GPS | Orta-Yüksek | sharkls-common + vendor/sprd'de hazır; `libgpsshim`/`libimsshim` mevcut |
| 5 | Kamera | Orta | `CAMERA_SENSOR_TYPE_BACK` J106F'te farklı olabilir; `camera.sc8830.so` blob'u elimizde |
| 6 | 1 GB RAM | Yönetilebilir | Go Edition + ZRAM + KSM |
| 7 | Mali-400 kaynağı | **Çözüldü** | `Talustus/android_vendor_sprd` fork'unda `utgard/platform/sc8830` canlı (bkz. §1.4c) |
| 8 | DMCA riski | **Çözüldü** | Fork canlı; `proprietaries-scx35l.mk` + `sc2331` WiFi de orada |
| 9 | Panel | Orta | defconfig `CONFIG_FB_LCD_DUMMY=y` + `CONFIG_SPRDFB_GEN_PANEL=y`; DTS `st7701_j1minilte_mea` + `s6d77a1a01_j1minilte` include ediyor — J106F'in kendi paneli |
| 10 | HWC sürümü | Düşük | `Hwc.cpp` `minorVersion < 1` ise `abort()`; J106F blob'u HWC1.1+ olmalı |

---

## 5. Kaynaklar (canlı doğrulandı)

**djeman SC9830 Oreo ağacı (ana referans):**
- https://github.com/djeman/android_device_samsung_sharkls-common (lineage-15.1)
- https://github.com/djeman/android_device_samsung_j3xlte (lineage-15.1)
- https://github.com/djeman/android_kernel_samsung_sharkls (lineage-15.1, 3.10.100)
- https://github.com/djeman/android_vendor_samsung_common (lineage-15.1)
- https://github.com/djeman/android_vendor_sprd — **HTTP 451 DMCA, kaldırılmış**
- Local manifest wiki: https://github.com/djeman/android_device_samsung_j3xnlte/wiki/Local-manifest-Lineage-15.1

**J106F kernel (ANA):**
- https://github.com/lasania32198/android_kernel_samsung_j1minivelte (3.10.65) ← **ana temel**; `CONFIG_MACH_J1MINIVELTE`, `board-j1minivelte.c`, `sprd-scx35l_sharkls_j1minivelte_rev00/01.dts`, `j1minivelte_defconfig`, `CONFIG_MODULES=y`, `CONFIG_PSTORE_RAM=y`, `CONFIG_ARCH_SCX35L=y`
- https://github.com/lasania32198/android_vendor_samsung_j1minivelte (53 MB, 198 dosya) ← **J106F stok blob seti**
- https://github.com/fuckyousamsung/android_kernel_samsung_j106b (3.10.65, Mali r4p1 in-tree) — yedek
- https://github.com/naimrlet/android_kernel_samsung_j1minive3g (3.10.65)
- https://github.com/fuckyousamsung/twrp_device_samsung_j1minivelte — TWRP ağacı (`BOARD_RECOVERYIMAGE_PARTITION_SIZE := 26214400`, `TARGET_KERNEL_CONFIG := j1minivelte_defconfig`)
- https://github.com/twrpdtgen/android_device_samsung_j1minivelte — jeneratör çıktısı, `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 10978320`

**vendor/sprd (DMCA aşıldı):**
- https://github.com/Talustus/android_vendor_sprd — dal `lineage-15.1`; `modules/libgpu/gpu/utgard/platform/sc8830/`, `proprietaries/proprietaries-scx35l.mk`, `wcn/wifi/sc2331/6.0/` — **hepsi HTTP 200**
- Diğer fork'lar: `phoenix-wnd` (lineage-15.0), `versusx` (master), `parthibx24`/`anryl` (cm-13.0), `j3xlte-dev` (cm-12.1)
- `djeman/android_vendor_sprd` — HTTP 451, kullanılmıyor

**Diğer SCX35 Oreo portları:**
- https://github.com/Samsung-GNP/android_device_samsung_grandneove3g (RIL çalışıyor)
- https://github.com/Rpal2k01/Bosskurt_kernel_samsung_grandneove3g (3.10.89)
- https://github.com/Samsung-Galaxy-Core-II/device_samsung_kanas (RIL kırık)
- https://xdaforums.com/t/rom-8-1-0-lineageos-15-1-for-grandneove3g-i9060i.4746516/
- https://xdaforums.com/t/closed-dev-wip-development-discontiuned-sm-j320fn-lineageos-15-1-for-samsung-galaxy-j3-2016.4694498/ ← **boot etmeyen J3 portu**

**RIL shim:**
- https://github.com/LineageOS/android_device_samsung_galaxys2-common/tree/lineage-15.1/shims/libsecril-shim

**TWRP / Odin:**
- https://4pda.to/forum/index.php?showtopic=886898 (SM-J106F/DS — Nazarikov TWRP)
- https://xdaforums.com/t/recovery-port-sm-j106b-twrp-3-2-1-0-for-galaxy-j1-mini-prime.3934513/

**Grafik (AOSP'de hazır — yama gerekmiyor):**
- `hardware/interfaces/graphics/mapper/2.0/default/Gralloc0Mapper.cpp` + `Gralloc1Mapper.cpp` (ikisi de `Android.bp` `srcs` içinde)
- `hardware/interfaces/graphics/allocator/2.0/default/Gralloc0Allocator.cpp` + `Gralloc1Allocator.cpp`; seçim `Gralloc.cpp` `module_api_version >> 8`
- `frameworks/native/libs/hwc2on1adapter/HWC2On1Adapter.cpp`; seçim `composer/2.1/default/Hwc.cpp:52-67`
- `allocator/2.0/default/Gralloc1On0Adapter.cpp` + `gralloc1-adapter.cpp` → `libgralloc1-adapter`

---

## 6. Derleme ortamı (kurulu)

| | |
|---|---|
| Ağaç | `/home/void0x14/j106f/build/android` (65 GB) |
| `repo` | `/home/void0x14/j106f/build/bin/repo` (PATH'e ekle) |
| Kaynak referanslar | `/home/void0x14/j106f/kaynak/ref/` — `android_device_samsung_j3xlte`, `android_device_samsung_j1minivelte` (twrpdtgen), `twrp_device_samsung_j1minivelte`, `android_kernel_samsung_j1minivelte`, `android_vendor_samsung_j1minivelte` |
| Diskim | 928 GB, 230 GB boş (sync sonrası) |
| CPU/RAM | 12 çekirdek / 15 GB |
| Heimdall | 2.2.2 (`heimdall detect`, `heimdall flash --<bölüm> <dosya>`) |

---

## 7. Gövde koruması (KURULU + TEST EDİLDİ)

opencode eklentisi + Bun CLI. Python değil.

- **`~/.config/opencode/plugins/govde-koruma.js`** — `tool.execute.before` kancası; `bash` aracında ham flash komutunu (`heimdall flash`, `odin`, `fastboot flash`, `dd of=/dev/block/`, `mtkclient`...) `throw` ile engeller. Yükleme kanıtı: `govde-journal.jsonl` içinde `eklenti_yuklendi`.
- **`~/.config/opencode/govde/policy.json`** — izinli/yasak cihaz kodları, bölümler, boyut sınırları (kod içinde gömülü değil).
- **`~/.config/opencode/govde/j106f-flash.mjs`** → `~/.local/bin/j106f-flash` — TTY ister, parola + sha256 öneki + `YAZ <bölüm>` onayı alır, onay kaydı tek kullanımlık (`tuketildi` damgası), reddedilen imaj `karantina/`'ya.
- **Doğrulama:** komut matrisi 12/12; EFS *yedekleme* (okuma) izinli / EFS *geri yükleme* (yazma) engelli 7/7; tam onay zinciri `pty` sürücüsüyle uçtan uca çalıştı (`--gercek` onayı tüketti, tekrar oynatma reddedildi).
- **Neden ajan açamaz:** opencode'un `bash` aracı süreçleri `stdin: "ignore"` ile başlatır → TTY kapısı yapısal olarak geçilemez.
- **Bilinen açık:** `opencode run` bash aracını çağıran her istemde `UnknownError` veriyor; `--pure` (eklentiler kapalı) ile de tekrarlandı → **eklentiden değil, harness'ın kendisinden**. Bu yüzden canlı ajan-içi engelleme gösterimi yapılamadı; eklenti yüklemesi ve kanca mantığı ayrı ayrı kanıtlandı.
