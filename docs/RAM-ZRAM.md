# RAM ve zram — servis ölümlerinin kökü

Cihaz: SM-J106F (j1minivelte), 1 GB RAM. Kullanıcının şikâyeti: "servisler ölüyor,
RAM tükeniyor". Bu belge, o şikâyetin ölçülmüş teknik kökünü ve düzeltmesini tutar.

## Ölçüm — çekirdek

| | Stok J106F | Bizim port (önce) |
|---|---|---|
| `CONFIG_ZRAM` | **`=y`** | **`# ... is not set`** |
| `CONFIG_ZSMALLOC` | `=y` | `=y` |
| `CONFIG_SWAP` | `=y` | `=y` |
| `CONFIG_FRONTSWAP` | not set | `=y` |

Kaynaklar:
- Stok defconfig: `kaynak/j106f-kernel/j1minive3g-dt_defconfig:3351-3353`
- Bizim `.config`: `out/target/product/j1minivelte/obj/KERNEL_OBJ/.config:2891`
  (`# CONFIG_ZRAM is not set`)
- Sürücü kaynağı bizim ağaçta **var**: `kernel/samsung/j1minivelte/drivers/staging/zram/`
  (`zram_drv.c`, `zram_sysfs.c`), `drivers/staging/Kconfig` + `drivers/staging/Makefile:33`
  (`obj-$(CONFIG_ZRAM) += zram/`).

Yani tek eksik satır `CONFIG_ZRAM=y` idi. Bağımlılıkların hepsi zaten açıktı:
`CONFIG_STAGING=y`, `CONFIG_ZSMALLOC=y`, `CONFIG_LZO_COMPRESS/DECOMPRESS=y`.

Sonuç: zram'sız 1 GB cihazda takas alanı yok → bellek baskısında düşük öncelikli
servisler (ve arka plan uygulamaları) öldürülür. Şikâyetin mekanizması budur.

## Ölçüm — rc tarafı

Stok ramdisk (`/tmp/stokx/x/init.sc8830.rc`) zram'i iki parça ile kurar:

```
on property:ro.config.zram.support=true
    write /proc/sys/vm/page-cluster  0
    start zram

service zram /system/xbin/zram.sh
        disabled
        oneshot
```

Ayrıca `ro.board_ram_size` blokları `zram.disksize` (MB) ve
`/proc/sys/vm/extra_free_kbytes` değerlerini seçer (stok: `min`=64, `low`=200,
`mid`=400, `high`=600).

Bizim `init.sc8830.rc`'de `ro.board_ram_size` blokları **vardı** ama
`on property:ro.config.zram.support=true` tetikleyicisi ve `service zram`
tanımı **yoktu** → `ro.config.zram.support=true` prop'u hiçbir şeyi başlatmıyordu.

## Ölçüm — prop tarafı

| Prop | Stok J106F | Bizim (önce) | Bizim (sonra) |
|---|---|---|---|
| `ro.board_ram_size` | `mid` | `high` | `mid` |
| `ro.config.low_ram` | `true` | `false` | `true` |
| `ro.config.zram.support` | `true` | `true` | `true` |

Stok değerler `/tmp/stoksys/raw.img` (stok `system.img`) içinden ölçüldü:
`ro.board_ram_size=mid`, `ro.config.low_ram=true`, `ro.config.zram.support=true`.

`high` (J3 2016 / j320fn değeri) 600 MB zram ister; 1 GB cihazda stok `mid` (400 MB).
`ro.config.low_ram=true`, `ActivityManager.isLowRamDeviceStatic()` ile
`AndroidRuntime`'ın `-XX:LowMemoryMode` bayrağını açar.

## Düzeltme

1. `kernel/samsung/j1minivelte/arch/arm/configs/j1minivelte_defconfig`
   → `CONFIG_ZRAM=y` eklendi (`CONFIG_ZSMALLOC=y` satırından sonra).
2. `device/samsung/sharkls-common/rootdir/etc/init.sc8830.rc`
   → stok blok aynen port edildi: `on property:ro.config.zram.support=true` +
   `service zram /system/xbin/zram.sh`.
3. `device/samsung/sharkls-common/rootdir/xbin/zram.sh` (yeni)
   → `zram.disksize` MB'ını bayta çevirip `/sys/block/zram0/disksize`'a yazar,
   `mkswap` + `swapon`.
4. `device/samsung/sharkls-common/rootdir/Android.mk` + `sharkls.mk`
   → `zram.sh` `/system/xbin`'e kurulur ve `PRODUCT_PACKAGES`'e eklenir.
5. `device/samsung/j1minivelte/system.prop`
   → `ro.board_ram_size=mid`, `ro.config.low_ram=true`.

## Neden `/system/xbin/zram.sh` — ve sepolicy

`sepolicy/file_contexts:86` zaten `/system/xbin/zram.sh u:object_r:zram_exec:s0`
etiketini tanımlıyor; `sepolicy/zram.te` `init_daemon_domain(zram)` ile
`init` → `zram` domain geçişini ve `sys_admin`, `proc:file write`,
`zram_block_device:blk_file` izinlerini veriyor. `init_daemon_domain`
`domain_auto_trans(init, zram_exec, zram)` açar; bu da entrypoint iznini içerir.

Bu yüzden servise ayrıca `seclabel` yazılmadı: betik `zram_exec` etiketli olduğu
için geçiş init tarafından otomatik yapılır. (`seclabel` yazmak, dosya etiketiyle
aynı domaini göstermediği sürece exec'i kırar — bgcompact/`sswap` durumunda
dosya etiketi `sswap_exec`, domain `sswap` olduğu için elle `seclabel` yazılmış.)

## Stok notu

Stok cihazda `/system/xbin/zram.sh` **diskte yok** — stok rc onu çağırıyor ama
blob bulunmuyor (stok `system.img` içinde `zram.sh` araması 0 sonuç; string
`zramsize=` inode 727 = `/bin/uncrypt`). Yani stok zram yolu da kırık; stok
`ro.config.zram.support=true` set ediyor ama servis başlamıyor. Bizim portumuz
bu betiği gerçekten sağlayarak stokun bıraktığı işi tamamlar.

## Sınır (kanıt seviyesi)

- Yukarıdakiler **statik ölçüm**tür: `.config` satırı, rc satırı, prop değeri,
  sepolicy kuralı. Hiçbiri cihazda çalıştırılmadı (cihaz bağlı değil).
- Gerçek kanıt: flash sonrası `cat /sys/block/zram0/disksize` (0 olmamalı),
  `cat /proc/swaps` (`/dev/block/zram0` görünmeli), `getprop ro.board_ram_size`
  (`mid`), `getprop ro.config.low_ram` (`true`), `dmesg | grep -i zram`.
