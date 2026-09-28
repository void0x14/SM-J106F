# ISP arayüz uyuşmazlığı — bulgu ve çözüm

## Belirti

Derleme, `vendor/sprd/modules/libcamera` (userspace kamera HAL'i, `libcamisp2.0`)
aşamasında şu hatalarla duruyordu:

```
isp_u_anti_flicker.c:108: error: use of undeclared identifier 'ISP_PRO_ANTI_FLICKER_TRANSADDR'
isp_u_binning4awb.c:226: error: use of undeclared identifier 'ISP_PRO_BINNING4AWB_INITBUF'
isp_u_buf_queue.c:34:    error: use of undeclared identifier 'ISP_BLOCK_BUFQUEUE'
isp_u_buf_queue.c:48:    error: variable has incomplete type 'struct isp_buf_node'
```

## Kök neden

İki ayrı upstream'in ISP arayüzleri farklı:

- **Çekirdek**: `lasania32198/android_kernel_samsung_j1minivelte` (J106F'e özel,
  Linux 3.10.65) — **eski** ISP arayüzü.
- **userspace**: `Talustus/android_vendor_sprd` (`lineage-15.1`) — djeman'ın sharkls
  ağacından gelir ve **yeni** ISP arayüzünü bekler.

`libcamsensor` ve `libcamisp2.0` derlenirken `sprd_isp.h` başlığını kernel ağacından
alır (`$(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ/source/include/video`). Başlık eskisi
olduğu için yeni semboller bulunamaz.

Fark tam olarak şu 22 satırlık eklemedir (`include/video/sprd_isp.h`):

```
ISP_CLK_468M,
ISP_BLOCK_BUFQUEUE,
ISP_PRO_BINNING4AWB_INITBUF,
enum isp_buf_node_type { ISP_NODE_TYPE_BINNING4AWB, ISP_NODE_TYPE_RAWAEM, ISP_NODE_TYPE_AE_RESERVED };
struct isp_buf_node { uint32_t type; uint64_t k_addr; uint64_t u_addr; };
enum isp_bufqueue_property { ISP_PRO_BUFQUEUE_INIT, ISP_PRO_BUFQUEUE_ENQUEUE_BUF, ISP_PRO_BUFQUEUE_DEQUEUE_BUF };
ISP_PRO_ANTI_FLICKER_TRANSADDR,
```

Yani djeman'ın başlığı yerelin **tam üst kümesidir** — hiçbir mevcut sembol kaldırılmaz,
yalnızca ekleme yapılır.

## Neden stock blob kullanmak çözmüyor

J106F stock `camera.sc8830.so` (Android 6.0.1 blob'u) çekirdeğin **eski** arayüzüyle
uyuşur — kanıt, sembol tablosu:

| Sembol | Stock HAL | J106F çekirdeği | Talustus userspace |
|---|---|---|---|
| `isp_u_anti_flicker_statistic` | var | var | var |
| `isp_u_binning4awb_transaddr` | var | var | var |
| `isp_u_anti_flicker_transaddr` | **yok** | yok | **bekler** |
| `isp_u_bq_init_bufqueue` | **yok** | yok | **bekler** |

Yani stock HAL ile Talustus userspace'i karıştırmak tutarsızdır: HAL eski arayüzü
kullanır, userspace yenisini. Aynı kaynak ağacından tutarlı bir çift üretmek gerekir.

## Çözüm

Çekirdeğin ISP sürücüsü djeman'ın sharkls çekirdeğindeki sürümle değiştirildi
(`patches/kernel-isp-port.patch`). Değişen dosyalar:

```
include/video/sprd_isp.h                                        (+22 satır, salt ekleme)
drivers/media/sprd_isp/isp_drv.c
drivers/media/sprd_isp/Makefile                                 (isp_k_buf_queue.o eklendi)
drivers/media/sprd_isp/isp2.0/tshark2/inc/isp_drv.h
drivers/media/sprd_isp/isp2.0/tshark2/inc/isp_block.h
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_cfg_param.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_anti_flicker.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_binning4awb.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_buf_queue.c    (yeni dosya)
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_raw_aem.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_raw_afm.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_capability.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_fetch.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_gamma.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_isr.c
drivers/media/sprd_isp/isp2.0/tshark2/src/isp_k_nlm.c
```

Port güvenli, çünkü ISP alt sistemi kendi içinde kapalıdır: çekirdek ağacında
`drivers/media/sprd_isp/` dışında `sprd_isp.h`'ı include eden başka dosya yoktur.
Dolayısıyla `isp_drv.c`'nin dışa açtığı ioctl arayüzü (`ISP_IO_CFG_PARAM` vb.)
değişmez; yalnızca iç sürücü mantığı güncellenir.

Kernel tarafındaki diğer farklar:

- `isp_drv.c`: yeni `ISP_BUFQUEUE` alt bloğu, `isp_k_buf_queue` yönlendirmesi.
- `isp_k_anti_flicker.c`: `ISP_PRO_ANTI_FLICKER_TRANSADDR` — kullanıcıdan fiziksel
  adres alıp sürücüye yazar (eski sürüm arabelleği kendisi ayırıyordu).
- `isp_k_binning4awb.c`: `ISP_PRO_BINNING4AWB_INITBUF` — çift arabellek (ping-pong)
  yönetimi.
- `isp_k_buf_queue.c`: dairesel arabellek kuyruğu (`isp_buf_queue_init/read/write`),
  BINNING4AWB ve RAW_AEM için kullanılır.

## Doğrulama

- `zImage` derlendi: 5.485.864 B (boot bölümü 10.978.320 B — sığar).
- `libcamisp2.0` ve `libcamsensor` hatasız derlendi.
- Kernel başlığı derleme sırasında `out/.../KERNEL_OBJ/source/include/video/` altına
  kurulur; userspace buradan okur, yani başlık ve sürücü aynı sürümden gelir.

## Kaynak

- `djeman/android_kernel_samsung_sharkls`, branch `lineage-15.1`,
  `drivers/media/sprd_isp/isp2.0/tshark2/` (59 dosya karşılaştırıldı).
- Referans cihaz: `j3xlte` (Galaxy J3 2016) — aynı SC9830 ailesi, aynı tshark2 ISP
  donanımı (`CONFIG_MACH_SP9830I=y` her ikisinde de `tshark2_isp_like=1` yapar).
