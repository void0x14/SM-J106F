# Vendor blob kökeni — APJ3 vs ARH1 sürüm kayması

## Soru

`vendor/samsung/j1minivelte/proprietary` altındaki 147 dosya stok cihazdan
çekilmiştir. ROM ARH1 parmak iziyle derlenir (`device/samsung/j1minivelte/lineage.mk:50`).
Elimizdeki stok `system.img` ise **APJ3**'tür. İki ayrı yapı olduğu için her blob
birebir uyuşmaz. Bu, "blob bozuk mu" sorusunu doğurur — ve bu soru **sessiz** bir
arıza sınıfıdır: eksik ya da uyumsuz bir `.so` bionic yükleyicide tek satır log
bırakmadan ölür (`docs/YUKLEYICI-BULGU.md`).

`scripts/blob-stok-karsilastir.py` bu soruyu ölçer. Cihaz gerekmez.

## Ölçüm

```
$ python3 scripts/blob-stok-karsilastir.py \
      /home/void0x14/j106f/stok/stoksys/system.img \
      vendor/samsung/j1minivelte/proprietary
== vendor blob'lari vs stok system.img ==
  birebir ayni        : 45
  yalniz build-id     : 43   (davranis esdeger, linker bu bolumu okumaz)
  GERCEKTEN FARKLI    : 57
  stokta yok          : 2
  toplam              : 147
```

Yöntem ve üç ayrım:

- **birebir aynı** — sha256 eşit.
- **yalnız build-id** — aynı boyut, tek fark `.note.gnu.build-id` (16 baytlık
  SHA1 damgası). Linker bu bölümü okumaz; iki dosya davranış olarak eşdeğerdir.
  Ham sha256 karşılaştırması bunları yanlışlıkla "farklı" sayar.
- **GERÇEKTEN FARKLI** — build-id dışında da ayrışma var (çoğu boyut farkı).

Sonuç iki **bağımsız** yöntemle doğrulandı: betiğin kendi ELF section-header
ayrıştırıcısı ve `readelf -S --wide` çıktısı üzerinden `.note.gnu.build-id`
bölümünü sıfırlayan ayrı bir hesap. İkisi de 45 / 43 / 57 / 2 verdi.

Ölçüm deterministiktir: aynı stok `system.img`'den `simg2img` ile üretilen yedi
ham kopyanın yedisi de bit-bit aynıdır (sha256 `54f6c3c5f42bfd21…`).

## Kök neden: sürüm kayması

| | bizim blob seti | stok `system.img` |
|---|---|---|
| Samsung PDA kodu | ARH1 (parmak izinde) | **APJ3** |
| Kod çözümü | R=2018, H=Ağustos → **2018-08** | P=2016, J=Ekim → **2016-10** |
| `build.prop` parmak izi | — | `…/MMB29Q/J106FJVU0APJ3:user/release-keys` |
| AP/BL tar mtime | — | 2016-10-10 08:58 UTC |

`device/samsung/j1minivelte/lineage.mk:50` ARH1'i, `init_j1minivelte.cpp:115`
ise `J106MVJU0ARH1`'i (Latin Amerika varyantı) kullanır. Yani blob seti
**ARH1'den**, kıyas tabanı **APJ3'ten**. Farkların sebebi budur.

Doğrudan kanıt — farklı dosyaların **içine gömülü** derleme tarihleri
(`__DATE__`, ELF rodata'da ham metin):

```
$ python3 scripts/blob-stok-karsilastir.py <imaj> <prop> --koken
  /lib/libsthmb.so     bizim blob : 2018-03     stok yapı : 2016-07
  /lib/libsxqk.so      bizim blob : 2016-12     stok yapı : 2016-06
```

Kayma tek yönlüdür: bizimki **daha yeni**. Bozulmada tarih kaymaz, rastgele
bayt değişir.

## Mühendislik sorusu: farklar çalışmayı bozar mı

Farklı olmak tek başına sorun değildir. Sorun, bir modülün **karışık** yapılardan
birleşmesidir (yarısı APJ3, yarısı ARH1). İki ölçüm bunu sınadı:

**1. Farklı küme kendi içinde kapalı mı** — bir dosyanın `DT_NEEDED` komşusu
farklı, kendisi stokla aynı ise karışıklık var demektir.

```
karışık kenarlar:
  lib/hw/bluetooth.default.so[farklı] -> libbt-iopdb.so[build-id]
  lib/libsdp_crypto.so[build-id]      -> libsec_km.so[farklı]
  lib/libsomxvencsw.so[aynı]          -> libsavscmn.so[farklı]   (+2)
```

**2. Derlenen sistemde gerçekten yüklenen farklı blob'lar** — `elf-kapanis.py`'nin
erişilebilirlik grafiği (554 kütüphane, 291 kök, 594 ELF):

```
farklı toplam           : 57
  yüklenen + farklı     :  5   libatparser, libbt-iopdb_mod, libfactoryutil,
                               libomission_avoidance, libsprdftms
  farklı ama yüklenmiyor: 52   (250 kütüphanelik ölü ağırlık içinde)
```

Kalan tek bayt-seviyesi şüpheli, tek baytlık bir farkla kapanıyor:

```
lib/libbt-iopdb_mod.so  @1193  (ELF başlığında, .rodata)
  biz  = b'ldCase_58'
  stok = b'ldCase_55'
```

Bu bir Bluetooth IOP veritabanı sürüm damgasıdır; kod değil, veri. Kalan dokuz
aynı-boyut-farklı dosyanın ayrışması ise derleyici sürüm/`.comment` ve tarih
damgalarıdır (`GCC 4.8` vs `4.9.x-google + clang 3.6`), kod değil.

## Karar

Farklar **sürüm kaymasıdır, bozulma değildir**. Dayanaklar:

1. Gömülü derleme tarihleri tek yönlü ve tutarlı biçimde bizim lehimize yeni.
2. Yüklenen 5 farklı blob'un `DT_NEEDED` komşuları ya stokla aynı ya da kendi
   yeni kümeleriyle tutarlı; hiçbiri "eski kütüphane + yeni kütüphane" karışımı
   değil.
3. `elf-kapanis.py --sembol` derlenen sistemde **çözülemeyen tek bir sembol bile**
   bulmuyor (`SONUC: yukleyici zinciri saglam`). Karışık yapı olsaydı burada
   kırılırdı.
4. Denetlenen 57 farklı dosyanın **57'si de** ROM'a birebir girmiş; ROM'daki
   kopya ile repo kopyası ayrışmıyor.

## Kalan sınır — dürüst kayıt

ARH1 stok `system.img` elimizde **yok**; bu yüzden farkların hepsi birebir
eşleşmeyle kapatılamadı. Erişim denendi ve kapandı:

- `archive.org` yalnız APJ3'ü barındırıyor (`KSAJ106FJVU0APJ320161102091153`).
- Samsung FUS (`neofussvr.sslcs.cdngc.net`) nonce veriyor ama
  `NF_DownloadBinaryInform.do` bu IP'den `500` dönüyor.
- FOTA (`fota-cloud-dn.ospserver.net`) bu IP'den `Access Denied`.
- `samfrew` ARH1 listeliyor; indirme oturum açma istiyor.
- `firmwaredrive` indirme bağlantısı `403`.

Bu yüzden ARH1 imajı elde edilirse aynı betik yeniden koşulmalıdır:

```
python3 scripts/blob-stok-karsilastir.py <ARH1-system.img> \
    vendor/samsung/j1minivelte/proprietary
```

Farkların build-id'ye çökmesi beklenir. Çökmezse gerçek bir sorun var demektir.

## Cihaz testi bunu nasıl doğrular

Host'ta kanıtlanan şey "blob seti kendi içinde tutarlı ve eksiksiz". Cihazda
doğrulanacak şey aynı değil: **ARH1 vendor blob'ları ARH1 olmayan bir çekirdekle
(3.10.65, J106F kaynağı) uyuşuyor mu.** İlk açılışta `logcat`'te
`linker`/`CANNOT LINK`/`dlopen failed` satırı aranır; `libbt-iopdb_mod.so`
Bluetooth açılışında yüklenir, `libsprdftms.so` FTMS servisinde.
