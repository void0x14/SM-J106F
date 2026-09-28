# BULGU — Sessiz yükleyici hataları (eksik `DT_NEEDED`)

Tarih: build8 sonrası, build9 öncesi.

## Neden bu sınıf tehlikeli

Android'de eksik bir paylaşımlı kütüphane **hiçbir hata üretmez**. bionic
yükleyici dosyayı açmaz, `init` servisi `stat()` başarısız olduğu için
sessizce devre dışı bırakır, logda tek satır çıkar. Cihaz açılır ama servis
ölüdür.

Bu, `boot-zinciri.py` ve `init-denetle.py`'nin kapsamadığı ayrı bir katmandır:
onlar *hangi* dosyanın okunacağını denetler, bu katman *dosyanın içindeki
bağların* çözülüp çözülmediğini denetler.

## Ölçüm yöntemi

`scripts/elf-kapanis.py` system.img içindeki her ELF'i tarar:

1. `DT_NEEDED` grafiğini köklerden (bin/xbin/vendor/bin + hw/egl/soundfx/drm
   modülleri + rc/xml/conf içinde adı geçen `.so`'lar) BFS ile gezer.
2. Ulaşılan dosyalarda çözülemeyen `DT_NEEDED` var mı diye bakar.
3. `--sembol` ile `UND` sembolleri de denetler.

`ld.config.txt` bu ağaçta `namespace.default.search.paths = /system/${LIB}:
/vendor/${LIB}` verir; arama yolu bu ikisi.

**Ölü ağırlık ayrımı kritik:** stok blob seti `libseccameracore`, `libsecface`,
`libarccamera`, `libQjpeg`, `libsamsungearcare`, `libsecure_storage` gibi
kütüphaneleri içeriyor ama bunlar **hiçbir yerden yüklenmiyor** — hiçbir
ikilinin `DT_NEEDED`'inde yok, hiçbir `dex/odex/vdex/apk` adlarını geçmiyor
(ölçüldü: `strings` taraması, 0 eşleşme). Bunları hata saymak gerçek sorunları
gürültüye boğar. Ölçüm: 553 sağlanan kütüphaneden yalnızca 594 dosya
ulaşılabilir kümede; geri kalanı ölü.

## Bulunan üç gerçek hata

Hepsi `BIND_NOW` (eager binding) ile bağlı, yani yükleme anında ölümcül.
Her biri gerçek bir `R_ARM_JUMP_SLOT` relocation'a dayanır — süsleme değil.

### 1. `libbt-iopdb_mod.so` — ICU 55 → 58

```
u_foldCase_55   (UND, R_ARM_JUMP_SLOT @ 0x4fbc)
```

Blob ICU 55'e karşı derlenmiş; ağaçta ICU 58 var
(`external/icu/icu4c/source/common/unicode/uvernum.h:87`
`#define U_ICU_VERSION_SUFFIX _58`). Ağaçta `u_foldCase_55` **hiçbir**
kütüphanede yok; `u_foldCase_58` var.

İmza aynı (`external/icu/.../unicode/uchar.h:3570`):
`UChar32 u_foldCase(UChar32 c, uint32_t options)`.

**Düzeltme:** dize uzunluğu eşit olduğu için `.dynstr` içinde yerinde
yamanır — `u_foldCase_55` → `u_foldCase_58`. Yeni dosya yok, boyut değişmez,
hash tabloları bozulmaz. `scripts/blob-fixup.sh`.

Zincir: `bluetooth.default.so` → `libbt-iopdb.so` → `libbt-iopdb_mod.so`.

### 2. `libedmnativehelper.so` — stok sette hiç yok

```
c_isBTOutgoingCallEnabled   (UND, R_ARM_JUMP_SLOT @ 0x1c2f0c)
```

`vendor/lib/hw/bluetooth.default.so` (BIND_NOW) bu kütüphaneyi `DT_NEEDED`
ile istiyor. Ne cihazın kendi blob setinde ne referans kopyasında
(`lasania32198/android_vendor_samsung_j1minivelte`, README'si zaten
"i cant confirm if they are fully complete" der) var. Tüm diskte yok.

`bluetooth.default.so`'nun 182 `UND` sembolünden **181'i** diğer
kütüphanelerden çözülüyor; bu kütüphaneden beklenen **tek** sembol bu.

İki çağrı yeri var, ikisi de aynı desende:

```
bta_ag_sco_open:      blx c_isBTOutgoingCallEnabled@plt
                      cbz r0, <normal yol>
bta_ag_sco_conn_open: blx c_isBTOutgoingCallEnabled@plt
                      cbz r0, <normal yol>
```

`cbz r0` → 0 dönüşü "özel yönlendirme yok" dalını seçer. Samsung'un
"outgoing call" özel davranışı (operatör bazlı) devre dışı kalır.

**Düzeltme:** `device/samsung/j1minivelte/libshims/edmnativehelper_shim.c`
`c_isBTOutgoingCallEnabled()` → 0 döndürür. Shim **aynı adla** derlenir
(`LOCAL_MODULE := libedmnativehelper`), yani `bluetooth.default.so`'ya
hiç dokunulmaz. Aynı adı kullanmak, eksik dosyayı kapatmanın en az
müdahaleli yoludur.

### 3. `libaudiopreprocessing.so` — eski webrtc ABI'si

```
_ZN6webrtc15AudioProcessing6CreateEi       (UND)
_ZN6webrtc15AudioProcessing7DestroyEPS0_   (UND)
```

Stok blob **eski** AOSP modül adını (`libwebrtc_audio_preprocessing.so`) ve
**eski** API'yi (`Create(int)`) istiyor. Ağaçta derlenen kütüphane
`libwebrtc_audio_preprocessing.so` adını koruyor ama yeni API'yi sunuyor:
`external/webrtc/webrtc/modules/audio_processing/include/audio_processing.h:244`
`static AudioProcessing* Create();`.

AOSP'nin kendi preprocessing efekti (`frameworks/av/media/libeffects/
preprocessing/PreProcessing.cpp:831`) `Create()` çağırıyor — yani blob,
**derlenmiş AOSP sürümünün üzerine yazıyordu**.

Ölçüm:
```
AOSP derlenen : _ZN6webrtc15AudioProcessing6CreateEv   (yeni)
stok blob     : _ZN6webrtc15AudioProcessing6CreateEi   (eski)
```

**Düzeltme:** blob satırı `device-vendor-blobs.mk`'den kaldırıldı. AOSP
sürümü `build/make/target/core_base.mk:27` ile zaten `PRODUCT_PACKAGES`'te.

## Kapsam dışı bırakılanlar (gerekçeli)

| Şey | Neden değil |
|---|---|
| `/vendor/etc/audio_effects.conf` yolları | `EffectsConfigLoader.c:112-145` `checkLibraryPath()` zaten fallback yapar: yol açılmazsa `/odm/lib/soundfx`, `/vendor/lib/soundfx`, `/system/lib/soundfx` sırayla denenir. `ALOGW` basar, devam eder |
| `_ZTH13tlNBLogWriter`, `__asan_init`, `__loader_*` | WEAK UND — 0'a çözülür, hata değil |
| `bin/linker`'da `__dl_posix_memalign` | Sıfır relocation; linker `__dl_*` adlarını kendi iç tablosundan çözer |
| `bin/adbd` sembolleri | Statik bağlı, `.dynamic` bölümü yok |
| `libseccameracore` ve arkadaşları | Ulaşılamaz — hiçbir yerden yüklenmiyor |

## Doğrulama

`scripts/elf-kapanis.py <system-agaci> --sembol` düzeltme öncesi 3 gerçek
hata bulur, sonrasında temiz döner. Düzeltme sonrası beklenen:

```
SONUC: yukleyici zinciri saglam
```
