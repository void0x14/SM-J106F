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
- Dosya adı da kanıt sayılır: `twrp-j3xlte-recovery.tar` reddedilir
- `reddedilecek_cihaz_kodlari` eşleşirse → karantinaya kopyala + dur
- `ro.product.device` / `ro.build.product` izinli değilse → karantina + dur
- Hiç kanıt yoksa → dur (kullanıcı `--kanit-yok-kabul` ile geçebilir)
- Boyut bölüm sınırını aşıyorsa → dur

## Test matrisi (çalıştırılmış)

| Senaryo | Beklenen | Sonuç |
|---|---|---|
| Doğru cihaz, nötr dosya adı | geçer | ✔ exit 0 |
| Yanlış cihaz (`j3xlte`) ramdisk'te | reddedilir | ✔ exit 2 |
| Yanlış cihaz dosya adında | reddedilir | ✔ exit 2 |
| `--bolum efs` | reddedilir | ✔ exit 2 |
| `--bolum userdata` | reddedilir | ✔ exit 2 |
| Uzantı `.bin` | reddedilir | ✔ exit 2 |
| 34 MB recovery | reddedilir (sınır 32 MB) | ✔ exit 2 |
| `--bolum` yok | reddedilir | ✔ exit 2 |
| Dosya yok | reddedilir | ✔ exit 2 |
| `flash` (ajan, TTY yok) | reddedilir | ✔ exit 2 |

Journal: `~/.config/opencode/govde/govde-journal.jsonl`
