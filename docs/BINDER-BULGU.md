# Binder ABI boşluğu — boot blocker #2

ISP portundan sonra ortaya çıkan ikinci ve daha sinsi engel. ISP'den farkı: **derleme hatası vermez**, cihaz sessizce bootloop'a girer.

## Belirti

Derleme temiz geçer. Zip kurulur. Cihaz açılışta takılır — logcat'e `hwservicemanager` hiç çıkmaz.

`hwservicemanager` servis tanımı `critical` (system/hwservicemanager/hwservicemanager.rc):

```
service hwservicemanager /system/bin/hwservicemanager
    user system
    disabled
    group system readproc
    critical
```

`critical` = init bu servis 4 kez başarısız olursa **reboot**. Servis `/dev/hwbinder`'ı açamayınca (kernel o düğümü yaratmıyor) → bootloop.

## Kök neden

Yerel kernel (lasania32198, 3.10.65) **tek cihazlı eski binder**'a sahip:

| | Yerel kernel | Oreo userspace |
|---|---|---|
| Cihaz düğümleri | yalnız `/dev/binder` | `/dev/binder` + `/dev/hwbinder` + `/dev/vndbinder` |
| `binder_miscdev` | tek `static struct miscdevice` | cihaz başına bir tane, `ANDROID_BINDER_DEVICES` ile |
| UAPI nesneleri | `flat_binder_object` | + `BINDER_TYPE_PTR`, `BINDER_TYPE_FDA`, `binder_buffer_object`, `binder_fd_array_object` |
| Komutlar | `BC_TRANSACTION` | + `BC_TRANSACTION_SG`, `BC_REPLY_SG` |
| Kconfig | yok | `ANDROID_BINDER_DEVICES`, `ANDROID_BINDER_IPC_SELFTEST` |
| Tahsis motoru | `binder.c` içinde gömülü | ayrı `binder_alloc.c` / `binder_alloc.h` |
| Protocol | 7 | 7 (`-DBINDER_IPC_32BIT=1`) |

Protocol sürümü **eşleşiyor** (ikisi de 7). Bu yüzden `ProcessState` "protocol mismatch" demez; sorun protocol numarası değil, **cihaz düğümü ve UAPI nesne seti**.

### Kanıtlar (ölçüm)

1. `system/core/rootdir/ueventd.rc:54-55` — `/dev/hwbinder`, `/dev/vndbinder` bekliyor.
2. `system/core/rootdir/init.rc:307-308` — `start hwservicemanager` + `start vndservicemanager`.
3. `system/libhwbinder/ProcessState.cpp:342` — `open("/dev/hwbinder", O_RDWR | O_CLOEXEC)`.
4. `system/libhwbinder/IPCThreadState.cpp`, `Parcel.cpp` — `BINDER_TYPE_PTR`, `BC_TRANSACTION_SG` kullanıyor.
5. `frameworks/native/libs/binder/Android.bp:86` ve `system/libhwbinder/Android.bp:54` — `-DBINDER_IPC_32BIT=1`.
6. Yerel `drivers/staging/android/binder.c` — `binder_miscdev` tek, `struct binder_device` yok, `hwbinder` string'i hiç geçmiyor.
7. `system/libhwbinder/include/hwbinder/binder_kernel.h` — AOSP, upstream'e girmemiş hwbinder UAPI eklemelerini **yerel olarak** tanımlıyor; yorum aynen: *"the uapi kernel headers in bionic are built from upstream kernel headers only, and the hwbinder kernel changes haven't made it upstream yet."*

7 numaralı madde işin özü: bionic'teki `linux/android/binder.h` sade upstream sürümünü taşır, hwbinder eklentileri kernel'da olmak zorunda. Eski kernel bunları sağlamaz.

## Çözüm

djeman'ın `sharkls-common` (lineage-15.1) ağacından AOSP 4.14 binder backport'u port edildi. Aynı SC9830 ailesi (j3xlte), aynı 3.10 tabanı.

| Dosya | Kaynak |
|---|---|
| `drivers/staging/android/binder.c` | djeman (5.701 satır, `binder_alloc` ayrılmış) |
| `drivers/staging/android/binder_alloc.c` | djeman (yeni) |
| `drivers/staging/android/binder_alloc.h` | djeman (yeni) |
| `drivers/staging/android/binder_alloc_selftest.c` | djeman (yeni) |
| `drivers/staging/android/binder_trace.h` | djeman |
| `drivers/staging/android/uapi/binder.h` | djeman |
| `drivers/staging/android/Kconfig` | `ANDROID_BINDER_DEVICES` + `ANDROID_BINDER_IPC_SELFTEST` eklendi |
| `drivers/staging/android/Makefile` | `binder.o binder_alloc.o` + selftest |
| `arch/arm/configs/j1minivelte_defconfig` | `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"` |

### Neden güvenli

- `drivers/staging/android/binder.h` (ince sarmalayıcı) **değişmedi** — yerel ile djeman bit bit aynı.
- Yerel kernel ağacında `staging/android/binder.h`'ı veya `uapi/binder.h`'ı include eden **başka hiçbir dosya yok** (ölçüldü). Binder tek başına izole.
- SELinux hook'ları (`security_binder_set_context_mgr` vb.) yerel `security/selinux/hooks.c` ve `include/linux/security.h`'ta **zaten mevcut** — ek yama gerekmedi.
- Trace event'leri (`binder_trace.h`) kendi kendine yetiyor; `include/trace/events/binder.h` gerekmiyor (djeman'da da yok).
- Kullanılan tüm çekirdek API'leri 3.10.65'te var: `task_work_add`, `get_task_mm`, `vm_insert_page`, `map_kernel_range_noflush`, `unmap_kernel_range`, `get_vm_area`, `rt_mutex_init`, `sched_setscheduler_nocheck` (hepsi ölçüldü).

## Doğrulama (ölçüm)

İzole kernel derlemesi (`O=/tmp/kobj`, arm-eabi-4.8, j1minivelte_defconfig):

```
CC      drivers/staging/android/binder.o
CC      drivers/staging/android/binder_alloc.o
...
OBJCOPY arch/arm/boot/zImage
Kernel: arch/arm/boot/zImage is ready
```

- `zImage` = **5.244.928 B** (boot bölümü 10.978.320 B — sığar)
- `binder.o` içinde gömülü string: **`binder,hwbinder,vndbinder`**
- `vmlinux` sembolleri: `binder_init`, `binder_devices_param` mevcut
- `binder.o`'nun `binder_alloc_*` çağrılarının **tamamı** `binder_alloc.o` tarafından karşılanıyor (çözülmemiş sembol yok)

## Kaynak

`j3xlte` — aynı SC9830/tshark2 ailesi, aynı 3.10 tabanı, aynı ISP/binder backport'ları. djeman'ın `sharkls-common` ağacı bu sınıfın çalışan referansı.
