# Gövde koruması — kurulum

İki parça: opencode eklentisi (ajanı engeller) + Bun CLI (kullanıcının onay kapısı).

## Kurulum

```bash
mkdir -p ~/.config/opencode/govde ~/.config/opencode/plugins ~/.local/bin
cp govde/policy.json       ~/.config/opencode/govde/
cp govde/j106f-flash.mjs   ~/.config/opencode/govde/
cp govde/govde-koruma.js   ~/.config/opencode/plugins/
chmod +x ~/.config/opencode/govde/j106f-flash.mjs
ln -sf ~/.config/opencode/govde/j106f-flash.mjs ~/.local/bin/j106f-flash
```

## Neden ajan bu kapıyı açamaz

opencode'un `bash` aracı süreçleri `stdin: "ignore"` ile başlatır
(`packages/opencode/src/tool/shell.ts`). `j106f-flash flash` `process.stdin.isTTY`
ister; bu koşul ajanın çalıştırdığı hiçbir komutta sağlanmaz. Yapısal bir kapı —
politika değil.

Ek olarak `govde-koruma.js`, `tool.execute.before` kancasında ham flash komutlarını
(`heimdall flash`, `odin`, `fastboot flash`, `dd of=/dev/block/`, `mtkclient`,
`spd_dump`) `throw` ile engeller.

## Kapı sırası (`flash`)

1. `--bolum` verilmiş mi
2. bölüm yasak listesinde mi (`efs`, `bootloader`, `nvdata`, `persist`...)
3. bölüm izinli listede mi (`recovery`, `boot`, `system`, `modem`)
4. gerçek TTY mi  ← ajan burada durur
5. imaj var mı
6. `bekleyen-<sha256>.json` inceleme kaydı var mı, bölüm eşleşiyor mu
7. onay kaydı daha önce tüketilmiş mi
8. onay TTL'i (varsayılan 1800 sn) dolmuş mu
9. yoksa: sha256 ilk 16 karakter yazılı onayı
10. `heimdall detect` — cihaz download mode'da mı
11. imaj hash'i onaydan sonra değişti mi (yeniden hesaplanır)
12. `YAZ <bölüm>` tam yazısı
13. `--gercek` yoksa kuru çalışma

## İmaj inceleme (`incele`)

- Uzantı izinli mi (`.tar`, `.tar.md5`, `.img`, `.zip`)
- Arşiv içeriği açılır; **gzip'li ramdisk de açılır** (Android boot image
  ramdisk'i sıkıştırılmıştır; ham bayt taraması cihaz kanıtını göremez)
- Boyut bölüm sınırını aşıyorsa → dur

### Cihaz kimliği: üç kanıt katmanı

| Katman | Kaynak | Güç | Karar |
|---|---|---|---|
| 1 | `ro.product.device` / `ro.build.product` | güçlü | yasak cihaz derse → karantina + dur |
| 2 | dosya adı | güçlü | yasak kod adı geçerse → karantina + dur |
| 3 | ham içerikte kod adı | **zayıf** | yalnızca 1 ve 2 bir şey söylemiyorsa → karantina + dur |

Hiçbir katman izinli cihaz demiyorsa → dur (kullanıcı `--kanit-yok-kabul` ile geçebilir).

**3. katman neden zayıf — ölçülmüş:** J106F çekirdeği dokunmatik panel firmware'ini
`melfas/j1minilte.fw` ve `/sdcard/j1minilte.bin` yollarıyla taşır. Ham bayt araması
`j1minilte` görüp bunu cihaz kimliği sanıyordu ve **kendi ürettiği doğru
`recovery.tar`'ı reddediyordu**. Ayrım şu: bu diziler bir dosya *yolu*, cihaz
*özelliği* değil. Prop ve dosya adı katmanları doğru cevabı zaten veriyor.

`reddedilecek_cihaz_kodlari` içindeki `j1minilte` bu yüzden tehlikeli bir tuzağa
dönüşmüştü; artık yalnızca güçlü katmanlarda reddettiriyor.

## Test matrisi (çalıştırılmış)

| Senaryo | Beklenen | Sonuç |
|---|---|---|
| Doğru cihaz, nötr dosya adı | geçer | ✔ exit 0 |
| **Gerçek derlenmiş `recovery.tar`** | geçer | ✔ exit 0 |
| Yanlış cihaz (`j3xlte`) ramdisk'te | reddedilir | ✔ exit 2 |
| Yanlış cihaz dosya adında | reddedilir | ✔ exit 2 |
| Doğru cihaz dosya adında | geçer | ✔ exit 0 |
| `--bolum efs` | reddedilir | ✔ exit 2 |
| `--bolum userdata` | reddedilir | ✔ exit 2 |
| Uzantı `.bin` | reddedilir | ✔ exit 2 |
| 34 MB recovery | reddedilir (sınır 32 MB) | ✔ exit 2 |
| `--bolum` yok | reddedilir | ✔ exit 2 |
| Dosya yok | reddedilir | ✔ exit 2 |
| `flash` (ajan, TTY yok) | reddedilir | ✔ exit 2 |

Journal: `~/.config/opencode/govde/govde-journal.jsonl`
