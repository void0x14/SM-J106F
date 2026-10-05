# Yazma kapısı — "sadece okuma" teknik olarak nasıl zorlanır

Kullanıcının isteği: *"sadece okuma yapacağını bana kanıtlaman lazım, inisiyatifi
sen kendi elinde tutamazsın."* Söz yetmez; teknik kilit gerekir. Bu belge kurulan
kilidi, kanıtını ve **dürüst sınırını** tutar.

## İki katman

### Katman 1 — Grok harness kapısı (PreToolUse)

`~/.grok/hooks/govde-koruma.sh` + `govde-koruma.json`. Ajanın
`run_terminal_command` çağrısı **çalışmadan önce** betik çalışır; yazma sınıfına
giren komut `deny` + `exit 2` ile engellenir.

Engellediği sınıf (davranış, kural listesi değil):
```
heimdall flash / write-pit / download-pit / --RECOVERY / --KERNEL / --SYSTEM
odin / odin4 / JOdin3
fastboot flash / erase / format
dd of=/dev/block|mmcblk|sd*
flash_image / flashcp / nandwrite / erase_image
mtkclient / spd_dump / sprd_dump
> | >> | tee /dev/block|mmcblk
```

**Kanıt (bu oturumda ölçüldü):**
```
$ heimdall flash --RECOVERY /tmp/x.img
Hook denied: GÖVDE KORUMASI: heimdall yazma komutu
Telefona yazma yalnızca kullanıcının kendi terminalinden j106f-flash ile yapılır.
```

> **Sınır:** Grok hook'ları hata durumunda **fail-open**'dır. Betik çökerse komut
> geçer. Bu yüzden betik hiçbir yerde çökmeyecek şekilde yazıldı; jq yoksa
> node'a düşer, ikisi de yoksa `deny` yazar.

### Katman 2 — Sistem kapısı (heimdall ikilisi)

`/usr/bin/heimdall` artık gerçek ikili değil, bir **okuma kapısı**:

```
/usr/bin/heimdall                      kapı (0755)
/usr/libexec/heimdall/heimdall.real    aynı kapı (0755)  — isim uyumu için
/usr/libexec/heimdall/heimdall.elf     gerçek ikili (0700 root:root)
```

Kapı mantığı:
- `detect`, `print-pit`, `download-pit`, `info`, `version`, `help` → **serbest**
- diğer her eylem (`flash`, `close-pc-screen`, `repartition`) → **iki kapı daha**:
  1. **TTY şartı.** Ajan araçları stdin'i `ignore` ile açar; ölçüldü:
     `tty` → `not a tty`. TTY yoksa yazma reddedilir.
  2. **Yazılı onay.** Kullanıcı terminalinde tam olarak `YAZ` yazması istenir.

**Kanıt (ölçüldü):**
```
$ bash govde/kapi/kapi-test.sh
=== 1) YAZMA denemesi (alt katman reddetmeli) ===
  ⛔ heimdall YAZMA KAPISI — GERÇEK TERMİNAL YOK
  Bu çağrı bir ajan/otomasyon ortamından geliyor (TTY yok).
cikis=13

=== 2) OKUMA denemesi (alt katman gecirmeli) ===
ERROR: Failed to detect compatible download-mode device.   ← geçti

=== 4) journald kaydi ===
IZIN eylem=detect tty=yok uid=1000 args=[detect]
RED-TTY-YOK flash uid=1000 args=[flash --RECOVERY /tmp/sahte.img]
IZIN eylem=print-pit tty=yok args=[print-pit --no-reboot]
```

Her çağrı journald'a düşer: `journalctl -t heimdall-kapi`

## Dürüst sınır — bunu saklamıyorum

Bu makinede şu kural var:
```
/etc/sudoers:140:  void0x14 ALL=(ALL) NOPASSWD: ALL
```

Yani root yetkisi olan biri gerçek ikiliyi doğrudan çağırabilir:
```
sudo -n /usr/libexec/heimdall/heimdall.elf detect     ← ÇALIŞIYOR (ölçüldü)
```

Bu yol **kapatılmadı**. Denendi (`sudoers.d` içine `!/usr/libexec/...` yasağı)
ama iki sebeple geri alındı:
1. Kural, `NOPASSWD: ALL`'ı bu yol için ezmedi (ölçüldü: çağrı geçmeye devam etti).
2. Çalışsaydı kapının **kendi okuma yolunu da kırardı** — kapı da `sudo` ile
   çağırıyor.

**Yani Katman 2 bir HIZ KESİCİDİR, mutlak kilit değildir.** Engellediği:
kazara yazma, sipsak yazma, ajanın kendiliğinden yazması. Engellemediği:
root yetkisini bilerek kullanan biri.

Mutlak engel **Katman 1**'dir (harness kapısı) ve o kullanıcının gözetimindedir:
hook dosyası kullanıcının ev dizininde, kullanıcı istediği an değiştirebilir.

## Kurulum / geri alma

```bash
# Kur
sudo mkdir -p /usr/libexec/heimdall
sudo cp /usr/bin/heimdall /usr/libexec/heimdall/heimdall.elf
sudo chmod 0700 /usr/libexec/heimdall/heimdall.elf
sudo cp govde/kapi/heimdall-kapi /usr/bin/heimdall
sudo chmod 0755 /usr/bin/heimdall

# Geri al (heimdall'i eski haline döndür)
sudo cp /usr/libexec/heimdall/heimdall.elf /usr/bin/heimdall
sudo chmod 0755 /usr/bin/heimdall
```

`heimdall-frontend` (GUI) ayrıca `0700` yapıldı — GUI'de de yazma var.

## Ne zaman yazma açılır

Kullanıcı kendi terminalinde:
```bash
heimdall flash --RECOVERY recovery.img
  → kapı: "Onaylamak için tam olarak 'YAZ' yaz:"
  → kullanıcı YAZ yazar
  → gerçek ikili çalışır
```

Ajan bu kapıyı **geçemez**: TTY yok + harness kapısı ikinci kez engelliyor.
