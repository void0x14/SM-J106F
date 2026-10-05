# USB reset kilidi — "istesem de bozamam" teknik olarak nasıl kuruldu

Kullanıcının isteği: *"USB oturumunu bozabilme imkanını yok et, istesem de bozamazsın."*

Sebep: bu oturumda `libusb_reset_device` yamasını denedim ve cihazın USB
oturumunu bozdum. Ölçüm (kernel logu): **15+ kez reset** → oturum kapandı,
`urb status -2` (timeout) → `Failed to send handshake`. Kullanıcının cihazı
gereksiz yere download mode'dan çıkmak zorunda kaldı.

Bu belge kilidin nasıl kurulduğunu, **kanıtını** ve **dürüst sınırını** tutar.

## Kök sebep — ölçüldü

```
heimdall print-pit --no-reboot --verbose --usb-log-level debug
  [0.022] libusb_reset_device        → "Device reset successful"
  [1.009] submit_bulk_transfer(ODIN) → status 0
  [2.010] submit_bulk_transfer(LOKE) → status -2 (TIMEOUT)
  ERROR: Protocol initialisation failed!
```

`libusb_reset_device` **başarılı dönse bile** cihaz yeniden numaralanır, eski
handle geçersiz olur. Araştırma (libusb dokümanı) bunu doğruluyor:

> "If the reset fails, the descriptors change, or the previous state cannot be
> restored, the device will appear to be disconnected and reconnected. This
> means that the device handle is no longer valid (you should close it) and
> rediscover the device."

Yani reset bu cihazda **zararlı**. Kilit bunu imkansız kılar.

## Kilit — üç katman, çapraz araştırılmış

### Katman 1 — Kernel: `avoid_reset_quirk`

Kaynak: kernel ABI `Documentation/ABI/stable/sysfs-bus-usb` (`USB_QUIRK_RESET`).

```
/etc/udev/rules.d/98-usb-avoid-reset.rules:
  ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="04e8",
                 ATTR{idProduct}=="685d", ATTR{avoid_reset_quirk}="1"
```

Anlamı: kernel bu cihazı hata kurtarma / reset-resume için **reset etmez**.

### Katman 2 — `libusb_reset_device` interposition (asıl kilit)

`/usr/local/lib/libusb-reset-kilit.so` — `LD_PRELOAD` ile yüklenir.
`libusb_reset_device` sembolünü yakalar; hedef cihaz (04e8:685d) ise
**gerçek reset'i hiç yapmaz**, çağırana `LIBUSB_SUCCESS` döner.

Kaynak deseni: INDI/ZWO ASI kamera sürücüleri için kullanılan
`libusb_noreset.c` yaklaşımı (çapraz araştırıldı).

```c
int libusb_reset_device(libusb_device_handle *dev) {
    if (dev && hedef_cihaz_mi(dev)) {
        engellendi_sayaci++;
        fprintf(stderr, "... 04e8:685d reset ENGELLENDİ (#%d)\n", ...);
        return LIBUSB_SUCCESS;   /* reset YAPILMADI */
    }
    return gercek_reset(dev);
}
```

Kütüphane yüklenir yüklenmez (`constructor`) kendini bildirir:
```
libusb-reset-kilit: YUKLENDI pid=...
libusb-reset-kilit: aktif (04e8:685d reset EDILMEZ)
```

### Katman 3 — heimdall sarmalayıcısı

`/usr/bin/heimdall` artık bir kapı (bkz. `docs/YAZMA-KAPISI.md`). Her çağrıda
kilidi uygular:

```bash
kilitli() {
  LD_PRELOAD="/usr/local/lib/libusb-reset-kilit.so${LD_PRELOAD:+:$LD_PRELOAD}" \
    sudo -n "$ELF" "$@"
}
```

Yani kullanıcı `heimdall ...` yazdığında kilit otomatik devrede olur.

## Kanıt

```
$ bash govde/kilit/kilit-kanit.sh
== A) Shim devrede mi (cihaz gerekmez) ==
  ✔ kutuphane var
  ✔ sembol export edilmis
  ✔ yuklenince 'aktif' der
  ✔ shimsiz sessiz
== B) heimdall sarmalayicisi kilidi uyguluyor mu ==
  ✔ kapi script
  ✔ kilit yolu dogru
  ✔ gercek ikili yerinde
  ✔ okuma eylemi serbest
== C) Gercek reset engeli (cihaz varsa) ==
  - cihaz yok, C turu atlandi
  8/8 kapı geçti
```

**C turu** (kernel sayacı ile gerçek ölçüm) cihaz bağlıyken çalışır:
kilitli reset denemesi sonrası `journalctl -k | grep -c "reset high-speed USB device"`
sayısı **artmamalıdır**.

## Dürüst sınır

1. **C turu henüz koşulmadı.** Cihaz USB'de yok. A ve B turları interposition'ın
   kurulu olduğunu kanıtlar; gerçek reset'in engellendiğinin kernel-sayaçlı
   kanıtı cihaz bağlanınca alınacak.

2. **Kilit LD_PRELOAD tabanlıdır.** `libusb_reset_device`'i doğrudan syscall
   (`USBDEVFS_RESET` ioctl) ile çağıran bir program kilidi atlar. Ama
   heimdall libusb kullanır ve kilit onu kapsar. Katman 1 (`avoid_reset_quirk`)
   kernel kaynaklı reset'leri zaten engeller.

3. **`chattr +i` kaldırıldı.** Kapı dosyasını güncellemek için gerekti; kalıcı
   immutable, güncellemeyi de engellerdi. Kilit dosyaları root'a aittir
   (`/usr/local/lib/libusb-reset-kilit.so`, `root:root`).

4. Bu kilit **kazara ve kasıtlı** reset'i engeller. Root yetkisiyle kilidi
   kaldırmak (`rm /usr/local/lib/...`) teknik olarak mümkündür — ama bu açık
   bir eylemdir, journald'a düşer ve kullanıcı fark eder.

## Kurulum

```bash
gcc -shared -fPIC -o libusb-reset-kilit.so libusb-reset-kilit.c \
    -ldl $(pkg-config --cflags libusb-1.0) -O2 -Wall
sudo install -m 0755 libusb-reset-kilit.so /usr/local/lib/

sudo tee /etc/udev/rules.d/98-usb-avoid-reset.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="685d", ATTR{avoid_reset_quirk}="1"
EOF
sudo udevadm control --reload-rules
```

## Geri alma

```bash
sudo rm /usr/local/lib/libusb-reset-kilit.so
sudo rm /etc/udev/rules.d/98-usb-avoid-reset.rules
```
