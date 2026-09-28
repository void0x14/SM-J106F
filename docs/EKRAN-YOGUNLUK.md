# Ekran ve yoğunluk — panel gerçeği

Cihaz: SM-J106F (j1minivelte). Panel ölçümü (kernel DTS, 6 panelin hepsi):
`gen-panel-xres=480`, `gen-panel-yres=800`, `gen-panel-width=56 mm`,
`gen-panel-height=94 mm` → çapraz 109.4 mm (4.31"), `dpi = 933.8 / 4.31 = 216.6`
→ **hdpi (240)**.

`device/samsung/sharkls-common` ağacı J3 2016 (j320fn, 720x1280, 5.0", ~294 dpi,
xhdpi) için yazılmış. Bu cihazda birkaç değer J3'ten miras kalıyordu.

## Ölçüm ve düzeltme

| Anahtar | Kaynak | J3 değeri (miras) | J106F (doğru) | Durum |
|---|---|---|---|---|
| `ro.sf.lcd_density` | `sharkls-common/system.prop` | 320 | 240 | önceki oturumda `j1minivelte/system.prop` ile ezildi (dosyada önce geldiği için kazanır) |
| `TARGET_SCREEN_WIDTH/HEIGHT` | `BoardConfigCommon.mk:77-78` | 720x1280 | 480x800 | bu oturumda `j1minivelte/BoardConfig.mk`'de ezildi |
| `PRODUCT_AAPT_PREF_CONFIG` | `sharkls.mk:99` | xhdpi | hdpi | bu oturumda `j1minivelte/j1minivelte.mk`'de ezildi |
| `DEVICE_RESOLUTION` | `BoardConfigCommon.mk:25` | 720x1280 | (TWRP GUI) | bu oturumda 480x800 yapıldı |

### Üretilen kanıt (önce)

```
$ unzip -p out/.../system/media/bootanimation.zip desc.txt
720 240 60          # J3 720x1280'den üretilmiş; panel 480x800
```

`vendor/lineage/bootanimation/Android.mk:18-31` `TARGET_SCREEN_WIDTH/HEIGHT`
tüketicisidir; `generate-bootanimation.sh` desc.txt'i bu değerlerden yazar.

### `PRODUCT_AAPT_PREF_CONFIG`

`aapt`'ın hangi yoğunluk kaynağını tercih edeceğini belirler; üretilen
`ro.build.aapt.config.prefer` değerine yansır (`system/build.prop`). xhdpi,
216.6 dpi panelde yanlış kovadır; hdpi doğrudur. `PRODUCT_AAPT_CONFIG`
(`normal hdpi xhdpi`) aynen korundu, yalnız tercih değişti.

### `DEVICE_RESOLUTION` ve TWRP

TWRP `gui/Android.mk:133-152` mantığı: `TW_CUSTOM_THEME` yok, `TW_THEME` **var**
(`portrait_hdpi`) → `DEVICE_RESOLUTION` dalı hiç çalışmaz; GUI genişliği
`TARGET_SCREEN_WIDTH/HEIGHT`'tan türetilir. Bizde `TW_THEME := portrait_hdpi`
açıkça set olduğu için `DEVICE_RESOLUTION` yalnız tutarlılık için düzeltildi.
`portrait_hdpi` teması referans TWRP ağacında da aynı (`ref/twrp_device_samsung_j1minivelte/BoardConfig.mk:81`).

## Sınır

Statik ölçüm; cihazda çalıştırılmadı. Gerçek kanıt: flash sonrası
`getprop ro.sf.lcd_density` (240), `getprop ro.build.aapt.config.prefer` (hdpi),
açılış animasyonunun 480x800 panelde kırpılmadan görünmesi.
