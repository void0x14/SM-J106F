# Dosya sistemi sözleşmesi — fstab ↔ çekirdek

Boot blocker sınıfı: çekirdek açılır, `init` çalışır, ama `/data` ya da `/cache`
bağlanamaz. Belirti ya "şifreleme hatası" ya da sürekli yeniden başlatmadır.
Bu belge fstab'ın çekirdekle tutarlı olduğunu ölçer.

## Ölçüm — çekirdek neyi destekliyor

Derlenmiş çekirdek yapılandırması
(`out/target/product/j1minivelte/obj/KERNEL_OBJ/.config`):

```
CONFIG_EXT4_FS=y
# CONFIG_F2FS_FS is not set
```

`fs/f2fs/` kaynağı ağaçta **vardır** (yani f2fs'i açmak mümkündür), ama
yapılandırmada kapalıdır. Stok firmware de aynı: stok defconfig
(`kaynak/j106f-kernel/j1minive3g-dt_defconfig`) f2fs'ten hiç söz etmez ve stok
`boot.img` ikilisinde `f2fs` dizesi **0** kez geçer.

## Bulgu — fstab f2fs'i ext4'ün önüne koyuyordu

`device/samsung/sharkls-common/rootdir/etc/fstab.sc8830` (ve `recovery/root/`
kopyası) `/data` ile `/cache` için **iki** satır taşıyordu, f2fs **önce**:

```
/dev/block/.../by-name/userdata /data  f2fs ...  wait,check,formattable,encryptable=footer
/dev/block/.../by-name/userdata /data  ext4 ...  wait,check,formattable,encryptable=footer
```

`fs_mgr`'ın sıralaması (`system/core/fs_mgr/fs_mgr.cpp:600-616`
`mount_with_alternatives`) aynı bağlama noktası için satırları **sırayla**
dener; ilk başarılı olan kazanır. Ayrıca `fs_mgr_do_format()`
(`fs_mgr_format.cpp:134-150`) biçimlendirmeyi `top_idx` — yani **ilk** satır —
üzerinden yapar.

Yani iki ayrı sonuç doğuyordu:

1. **Normal boot.** `/data` ext4 olduğundan f2fs satırı bağlanamaz; `fs_mgr`
   ext4 satırına düşer. Boot çalışır ama `prepare_fs_for_mount()`
   (`fs_mgr.cpp:441-466`) ilk satır için `MF_CHECK` görüp `check_fs()` çağırır,
   o da `fsck.f2fs -a /dev/.../userdata` çalıştırır (`fs_mgr.cpp:221-233`).
   ext4 bölümünde geçerli f2fs süper bloğu olmadığından `fsck.f2fs`
   `f2fs_do_mount` → `validate_super_block` → `sanity_check_raw_super`
   (`mount.c:560-565`) üzerinden `-EINVAL` ile döner; `main.c:707-716`
   `goto out_err` ile hiçbir şey yazmadan çıkar. **Veri kaybı yok**, ama her
   açılışta gereksiz bir fsck ve kafa karıştırıcı log üretir.

2. **`formattable` yolu — asıl risk.** `/data` boş/`0xff` ise
   (`partition_wiped()`, `system/core/libcutils/partition_utils.c:40-65`)
   `fs_mgr` `fs_mgr_do_format()` çağırır. O da `top_idx`'i yani **f2fs**
   satırını kullanır ve `/system/bin/make_f2fs` çalıştırır. Çekirdek f2fs
   olmadan derlendiği için o bölüm **hiçbir zaman bağlanamaz**: cihaz
   "şifreleme başarısız" döngüsüne girer ve TWRP'den yeniden biçimlendirmek
   gerekir. TWRP imajı f2fs yapabildiğinden (`recovery/root/sbin/mkfs.f2fs`)
   kurtulunabilir, ama gereksiz bir tuzaktır.

Cihazın gerçek `/data`'sı stok ext4'tür (stok `fstab.sc8830`: `userdata /data
ext4 ...`), ve `updater-script` `/data`'ya **dokunmaz**. Yani 2. yol ancak
kullanıcı TWRP'den `Format Data` yaparsa tetiklenir — ki runbook bunu
söylüyor (`docs/FLASH.md` §8).

## Düzeltme

`device/samsung/sharkls-common`:

| dosya | değişiklik |
|---|---|
| `rootdir/etc/fstab.sc8830` | `/data` ve `/cache` için f2fs satırı **kaldırıldı** |
| `recovery/root/fstab.sc8830` | aynı |
| `BoardConfigCommon.mk:65` | `BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := f2fs` → `ext4` |
| `BoardConfigCommon.mk:69` | `TARGET_USERIMAGES_USE_F2FS := true` **kaldırıldı** |

Böylece fstab, `BoardConfig`, derlenmiş çekirdek ve stok firmware dördü de
ext4 der. Kalan `fsck.f2fs` ikilisi (`sharkls.mk:128`) zararsızdır: artık
hiçbir fstab satırı f2fs istemediği için çağrılmaz.

Doğrulama: düzeltmeden sonra `grep -rn f2fs device/samsung/` → yalnız
`sharkls.mk`'daki `fsck.f2fs` paket satırı kalır.

## Sınır

Bu ölçüm cihazda çalıştırılmadı; statik analizdir. Kesin kanıt, ROM
yazıldıktan sonra `/data`'nın bağlandığının görülmesidir (ayarların kalıcı
olması, yeniden başlatmada verinin durması). Bu belge o ölçümün yerine
geçmez; onu önceler.
