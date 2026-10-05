# Heimdall oturum kuralları — ölçülmüş, araştırılmış

Bu belge, heimdall ile cihaz arasındaki oturum davranışını ve yapılan hatayı
tutar. Kaynak: gerçek koşu (bu oturum) + çapraz araştırma (XDA, Debian manpage,
heimdall upstream sorun kayıtları).

## Hata — bu oturumda yaşandı

```
heimdall print-pit --no-reboot | head -60
```

`head` 60 satır sonra boruyu kapatır → heimdall **SIGPIPE** alır → oturum
kapanmadan ölür. Cihaz "session begun" durumunda yarı kalır.

Sonraki her deneme:
```
Initialising connection...
Detecting device...
Claiming interface...
Initialising protocol...
ERROR: Protocol initialisation failed!
```

## Kural 1 — Cihaz, oturum başına TEK komut kabul eder

Araştırmada doğrulandı (XDA, heimdall sorun kayıtları): birçok Samsung
bootloader'ı download mode oturumu başına **tek** heimdall komutuna izin verir.
`print-pit` çalıştıktan sonra `flash` aynı oturumda çalışmaz.

**Doğru yol:**
```
# 1) Cihazı download mode'a al, USB'yi tak
# 2) TEK komut çalıştır (borusuz, dosyaya yaz):
heimdall print-pit --no-reboot > /tmp/pit.txt 2>&1

# 3) Sonuç tamamlandıktan sonra cihazı download mode'dan çıkar ve yeniden al
# 4) Sonraki komut için tekrar
```

**Alternatif (denenmedi):** `--resume` bayrağı ilk komuttan SONRAki komutlarda
kullanılır. İlk komutta kullanılmaz. Bu cihazda test edilecek.

## Kural 2 — Komutu ASLA boruya verme

`| head`, `| tail`, `| grep` heimdall'ı oturum ortasında öldürür ve cihazı
yarı-kilitli bırakır. Çıktı **her zaman** dosyaya yazılır, sonra dosya okunur.

```bash
# YANLIŞ
heimdall print-pit | head -60

# DOĞRU
heimdall print-pit --no-reboot > /tmp/pit.txt 2>&1
head -60 /tmp/pit.txt
```

## Kural 3 — Cihazı oturumdan çıkarma

`--no-reboot` ile komut bittikten sonra cihaz download mode'da kalır.
Çıkmak için: **Güç + Ses Kısma**, 7-10 saniye. Ekran kararınca bırak.

Download mode'a yeniden girmek: **Ses Kısma + Home + Güç** → uyarı ekranı →
**Ses Açma**.

## Kural 4 — Linux USB / ModemManager

Araştırmada çıkan ek önlem: ModemManager cihazı modem sanıp araya girebilir.
```
/etc/udev/rules.d/79-samsung.rules:
  ATTRS{idVendor}=="04e8", ENV{ID_MM_DEVICE_IGNORE}="1"
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Bu cihazda ölçülen gerçekler

```
USB kimliği (download mode): 04e8:685d
PIT (ilk başarılı okuma):    32 girdi, COM_TAR2, SPRD8735
  Entry #0 BOOT   1024 blok =   524.288 B  (spl.img)
  Entry #1 BOOT2  2048 blok = 1.048.576 B  (spl2.img)
  Entry #2 (okuma kesildi — SIGPIPE)
```

İlk okuma, boru kesilmeden önce ilk 3 girdiyi verdi. Tam tablo için cihazın
taze bir oturumda tekrar okunması gerekir.

## Sıra (her adım tek komut, aralarda cihaz reset)

```
1. Cihazı download mode'a al
2. heimdall print-pit --no-reboot > /tmp/pit.txt 2>&1     (tek komut)
3. Cihazı çıkar, tekrar download mode'a al
4. (yazma gerekiyorsa) tek komut
```
