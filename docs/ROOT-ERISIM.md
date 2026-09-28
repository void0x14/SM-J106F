# Root erişimi — varsayılan kapalı, Developer options'tan açılır

Bu ROM `userdebug`'dur ve `su` ikilisini taşır, ama LineageOS tasarımı gereği
root **varsayılan olarak kapalıdır**. Bu bir eksik değil, bilinçli bir kapıdır:
kullanıcı Developer options'tan açar. Bu belge zinciri kaynaktan doğrular.

## Ölçülen durum

```
system/build.prop : ro.build.type=userdebug
                    ro.lineage.version=15.1-20260928-UNOFFICIAL-j1minivelte
root/default.prop : ro.debuggable=1
system/xbin/su    : 276940 B   (system/bin/su -> ../xbin/su)
system/build.prop : persist.sys.root_access  ->  YOK (0 satır)
```

`persist.sys.root_access` hiçbir yerde tanımlı değil (ne cihaz ağacında, ne
`sharkls-common`'da, ne `vendor/lineage`'da). Yani ilk açılışta değer yoktur.

## Zincir — her halka kaynaktan

### 1. `su` her zaman daemon'a bağlanır

`system/extras/su/su.c:371-378` `main` → `su_main(argc, argv, 1)`; `need_client`
**daima 1**. `su.c:492-495`:

```c
if (need_client) {
    ALOGD("starting daemon client %d %d", getuid(), geteuid());
    return connect_daemon(argc, argv, ppid);
}
```

Daemon yoksa `daemon.c:587-590` `connect` başarısız → `exit(-1)`. Yani daemon
ayakta değilse `su` çalışmaz.

### 2. Daemon yalnız property ile başlar

`system/etc/init/superuser.rc`:

```
service su_daemon /system/xbin/su --daemon
    user root
    group root
    disabled
    seclabel u:r:sudaemon:s0

on property:persist.sys.root_access=1
    start su_daemon
on property:persist.sys.root_access=3
    start su_daemon
```

`disabled` + yalnız property tetikleyicisiyle başlar. Property yoksa soket
(`/dev/socket/su-daemon/su-daemon`) hiç oluşmaz.

### 3. `access_disabled` ikinci kapı

`su.c:318-345` `/data/property/persist.sys.root_access` dosyasını okur; dosya
yoksa `enabled = "0"` kabul eder ve hem uygulama (`LINEAGE_ROOT_ACCESS_APPS_ONLY`)
hem shell (`LINEAGE_ROOT_ACCESS_ADB_ONLY`) yollarını reddeder.

### 4. Ayarın kendisi Settings'te var

`packages/apps/Settings/.../DevelopmentSettings.java`:
`ROOT_ACCESS_PROPERTY = "persist.sys.root_access"`; dinleyici `/system/xbin/su`
varlığını kontrol eder (`:627-646`); `removeRootOptionsIfRequired()` (`:678-690`)
menüyü yalnız `Build.IS_DEBUGGABLE || "eng".equals(Build.TYPE)` iken gösterir.

Derlenmiş `Settings.apk` içinde `root_access` ve `persist.sys.root_access`
dizeleri bulundu — menü bu yapıda görünür (`ro.debuggable=1` kapıyı geçer).

## Kullanıcı ne yapar

Telefonda:

```
Ayarlar → Telefon hakkında → Yapı numarası (7 kez dokun)
Ayarlar → Geliştirici seçenekleri → Root erişimi → "Uygulamalar ve ADB"
```

Bu seçim `persist.sys.root_access=3` yazar. Kalıcılık doğrulanmıştır:

- `property_service.cpp:206` — `persistent_properties_loaded` sonrası
  `persist.*` değişiklikleri `/data/property/` altına yazılır.
- `load_persistent_properties()` (`:602`) `build.prop`'tan **sonra** çalışır
  (`on late-init` → `trigger load_persist_props_action`), yani kullanıcı seçimi
  derleme zamanı varsayılanını ezer.
- Dosya güvenlik denetimi (`:625-635`): root/root sahipli, grup/diğer izni yok,
  `nlink == 1` — `mkdir /data/property 0700 root root` (`init.rc:454`) bunu
  sağlar.

## Neden derleme zamanında açmıyoruz

`persist.sys.root_access=3` `system.prop`'a eklenebilirdi ve zincir çalışırdı.
Eklenmedi çünkü:

- Varsayılan kapalı olması LineageOS'un kendi davranışıdır; cihazı stoktan ayıran
  bir sapma yaratmaz.
- Ayar menüsü zaten var ve tek dokunuşla açılıyor; kullanıcı denetimi korunur.

İstenirse tek satırla açılır: `device/samsung/j1minivelte/system.prop` içine
`persist.sys.root_access=3` eklenir (her iki ağaçta) ve yeniden derlenir.

## Bilinen ve kabul edilen ikincil nokta

`/dev/socket/su-daemon(/.*)?` etiketi (`superuser_device`) yalnız
`device/lineage/sepolicy/common/public/file_contexts:2`'de tanımlıdır; derleme
`file_contexts` için **private** dizini okur (`system/sepolicy/Android.mk:604`,
`:667`), `public` dizinini okumaz. Ölçüm: derlenmiş `root/file_contexts.bin`
içinde `su-daemon` **0** kez geçer.

Bu bir boot engeli değildir: `sudaemon` domaini `permissive`'tir
(`common/private/su.te`) ve soket etiketi `type_transition sudaemon
socket_device:sock_file superuser_device` ile **çalışma anında** atanır — dosya
etiketi kuralına gerek kalmaz. Üstelik bu yapıda SELinux zaten permissive
çalışır (`CONFIG_CMDLINE` içinde `androidboot.selinux=permissive`,
`ALLOW_PERMISSIVE_SELINUX=1`). Upstream lineage-16.0 satırı `common/private/`
altına taşımıştır; sertleştirme istenirse aynısı yapılır.
