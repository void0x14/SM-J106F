#!/usr/bin/env bun
// j106f-flash — gövde korumalı flash sarmalayıcısı
//
// Bunu SADECE kullanıcı kendi terminalinde çalıştırır. Gerçek bir TTY ister;
// bu yüzden opencode ajanı bu komutu çalıştıramaz (bash aracı stdin:"ignore"
// ile süreç başlatır ve komut reddedilir).
//
// Kullanım:
//   j106f-flash incele <imaj> --bolum <recovery|boot|system|modem>
//   j106f-flash flash  <imaj> --bolum <recovery|boot|system|modem>
//   j106f-flash durum

import fs from "node:fs"
import fsp from "node:fs/promises"
import path from "node:path"
import os from "node:os"
import crypto from "node:crypto"
import zlib from "node:zlib"
import { execFileSync, spawnSync } from "node:child_process"

const KOK = path.join(process.env.HOME, ".config", "opencode", "govde")
const POLICY = path.join(KOK, "policy.json")
const ONAY_DIR = path.join(KOK, "onay")
const KARANTINA = path.join(KOK, "karantina")
const JOURNAL = path.join(KOK, "govde-journal.jsonl")

const K = "\x1b[36m", Y = "\x1b[33m", G = "\x1b[32m", R = "\x1b[31m", B = "\x1b[1m", X = "\x1b[0m"

function dur(mesaj) {
  console.error(`\n${R}${B}⛔ REDDEDİLDİ:${X} ${mesaj}\n`)
  process.exit(2)
}

function gecti(mesaj) {
  console.log(`${G}✔${X} ${mesaj}`)
}

async function journal(yaz) {
  await fsp.mkdir(KOK, { recursive: true })
  await fsp.appendFile(JOURNAL, JSON.stringify({ zaman: new Date().toISOString(), ...yaz }) + "\n")
}

async function policyYukle() {
  try {
    return JSON.parse(await fsp.readFile(POLICY, "utf8"))
  } catch {
    dur(`Politika okunamadı: ${POLICY}`)
  }
}

async function sha256Dosya(yol) {
  return new Promise((resolve, reject) => {
    const h = crypto.createHash("sha256")
    const s = fs.createReadStream(yol)
    s.on("error", reject)
    s.on("data", (d) => h.update(d))
    s.on("end", () => resolve(h.digest("hex")))
  })
}

// tar / tar.md5 / zip / ham imaj içeriğinden kod adı ve ro.product.* çıkarır.
async function imajIncele(yol, policy) {
  // Uc ayri kanit katmani. Ham icerikte kod adi gecmesi ZAYIF kanittir:
  // dokunmatik firmware yolu (melfas/j1minilte.fw) cihaz kimligi degildir.
  // Bu yuzden icerik taramasi tek basina reddetmez; yalnizca prop ve dosya
  // adi kaniti yokken konusur.
  const kodlar = new Set()     // ham icerik   — zayif
  const adKodlari = new Set()  // dosya/arsiv adi — guclu
  const prop = []
  const icerik = []
  const sinir = policy.icerik_tarama_limiti_bayt ?? 64 * 1024 * 1024
  const tumKodlar = [...policy.izinli_cihaz_kodlari, ...(policy.reddedilecek_cihaz_kodlari ?? [])]

  // Icerik taramasinda kod adinin GECMESI yetmez; KIMLIK KALIBINA uymasi gerekir.
  // Olculdu: stok j1minivelte boot.img icinde 'j1minilte' yalniz dokunmatik
  // firmware yolundan gelir (melfas/j1minilte.fw, /sdcard/j1minilte.bin);
  // ayni dosyada gercek kimlik izi 'samsung/j1miniveltejv/j1minivelte:6.0.1/...'
  // seklindedir. Yol parcasini kimlik sanmak, telefonun KENDI imajini yabanci
  // sayar. Bu yuzden kalipsiz gecisler yok sayilir.
  const kimlikKaliplari = (kod) => {
    const k = kod.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    return [
      // ro.product.device=j3xlte / ro.build.product=j3xlte / ro.product.name=j3xlte
      new RegExp(`ro\\.(?:product\\.device|build\\.product|product\\.name)\\s*=\\s*${k}(?![a-z0-9])`, "i"),
      // fingerprint govdesi: <marka>/<urun>/<kod>:<surum>  (or. samsung/j1miniveltejv/j1minivelte:6.0.1)
      new RegExp(`/[a-z0-9_]*${k}[a-z0-9_]*/${k}:`, "i"),
      // build flavor / description: <kod>-user
      new RegExp(`(?<![a-z0-9])${k}-user(?![a-z0-9])`, "i"),
    ]
  }
  const kimlikIzi = (metin, kod) => kimlikKaliplari(kod).some((re) => re.test(metin))
  const adIzi = (metin, kod) =>
    new RegExp(`(?<![a-z0-9])${kod.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![a-z0-9])`, "i").test(metin)

  const tara = (buf, etiket, hedef = kodlar, kalipli = true) => {
    // Android boot image / bootloader bloblari sikistirilmis olabilir. Ham bayt
    // taramasi gzip akisinin icini goremez; metin aramasindan once ac.
    // Not: sikistirilmis verinin ICINDE de 1f 8b 08 dizisi gecebilir; ilk
    // eslesmede durmak yanlis. Adaylarin hepsi denenir, acilabilen kabul edilir.
    const parcalar = [buf]
    const gorulen = new Set()
    const sinirTarama = Math.min(buf.length, 8 * 1024 * 1024)
    for (let i = 0; i + 3 <= sinirTarama; i++) {
      if (buf[i] !== 0x1f || buf[i + 1] !== 0x8b || buf[i + 2] !== 0x08) continue
      if (gorulen.has(i)) continue
      gorulen.add(i)
      // 1f 8b 08 gzip imzasidir -> gunzipSync. inflateSync zlib sarmali bekler
      // ve gzip basligini "incorrect header check" ile reddeder.
      try {
        const acik = zlib.gunzipSync(buf.subarray(i))
        if (acik.length > 1024) parcalar.push(acik)
      } catch {}
    }
    for (const p of parcalar) {
      const metin = p.toString("latin1")
      for (const kod of tumKodlar) {
        if ((kalipli ? kimlikIzi : adIzi)(metin, kod)) hedef.add(kod)
      }
      const propRe = /(ro\.(?:product\.device|build\.product|product\.name|product\.model))\s*=\s*([A-Za-z0-9_\-.]+)/g
      let m
      while ((m = propRe.exec(metin)) !== null) prop.push({ etiket, anahtar: m[1], deger: m[2] })
    }
  }

  const alt = yol.toLowerCase()
  const oku = (arac, args) => {
    try {
      // stderr yutulur: 'tar: Exiting with failure status' gibi arac hatalari
      // inceleme ciktisina sizarak kullaniciyi yanlis yonlendirmesin.
      return execFileSync(arac, args, { maxBuffer: sinir, stdio: ["ignore", "pipe", "ignore"] })
    } catch {
      return null
    }
  }

  let adlar = null
  if (alt.endsWith(".zip")) {
    const l = oku("unzip", ["-Z1", yol])
    if (l) adlar = l.toString().split("\n").filter(Boolean)
  }
  if (!adlar) {
    const l = oku("tar", ["-tf", yol])
    if (l) adlar = l.toString().split("\n").filter(Boolean)
  }

  // BOS liste arsiv DEGILDIR. Olculdu: sifir dolu bir dosyada `tar -tf` exit 0
  // verip hicbir ad basmaz; `[]` truthy oldugu icin koruma ham icerigi hic
  // taramaz ve 'kanit yok' deyip gecer. Arsiv ancak en az bir uye varsa arsivdir.
  if (adlar && adlar.length) {
    for (const ad of adlar) icerik.push(ad)
    const arsiv = alt.endsWith(".zip") ? "unzip" : "tar"
    for (const ad of adlar.slice(0, 60)) {
      const buf = arsiv === "unzip" ? oku("unzip", ["-p", yol, ad]) : oku("tar", ["-xOf", yol, ad])
      if (buf) tara(buf, ad)
    }
  } else {
    // ham imaj
    const fd = await fsp.open(yol, "r")
    try {
      const boy = (await fd.stat()).size
      const buf = Buffer.alloc(Math.min(sinir, boy))
      await fd.read(buf, 0, buf.length, 0)
      tara(buf, path.basename(yol))
    } finally {
      await fd.close()
    }
  }

  // dış dosya adı da kanıt sayılır: 'twrp-j3xlte-recovery.tar' reddedilmeli
  // Dosya adinda kalip aranmaz; ad gecmesi yeter (kalipli=false).
  tara(Buffer.from(path.basename(yol), "latin1"), "dosya-adı", adKodlari, false)

  return { kodlar: [...kodlar], adKodlari: [...adKodlari], prop, icerik }
}

function cizgi() {
  console.log("=".repeat(72))
}

// heimdall print-pit ciktisindan bir bolumun bayt cinsinden boyutunu cikarir.
// Alan sirasi KAYNAKTAN dogrulandi (heimdall/source/Interface.cpp:214-320):
// her girdi "--- Entry #N ---" ile baslar; icinde sirayla
//   Device Type: <n> (MMC|UFS|...)
//   Partition Block Size/Offset: <n>
//   Partition Block Count: <n>
//   ...
//   Partition Name: <ad>
// Yani Partition Block Count, Partition Name'DEN ONCE gelir; ikisini tek bir
// "Name ... Count" regex'i ile eslemek YANLIS girdiyi yakalar.
// Blok boyutu: MMC -> 512, UFS -> 4096 (FlashAction.cpp:331-334).
function pitBolumBoyu(pitMetin, pitAdi) {
  const girdiler = pitMetin.split(/--- Entry #\d+ ---/)
  for (const g of girdiler) {
    const ad = /Partition Name: (.+)/.exec(g)
    if (!ad || ad[1].trim() !== pitAdi) continue
    const sayi = /Partition Block Count: (\d+)/.exec(g)
    if (!sayi) return null
    const ufs = /Device Type: \d+ \(UFS\)/.test(g)
    return Number(sayi[1]) * (ufs ? 4096 : 512)
  }
  return null
}

async function incele(imaj, bolum, kabul = false) {
  const policy = await policyYukle()
  const yol = path.resolve(imaj)

  if (!fs.existsSync(yol)) dur(`İmaj yok: ${yol}`)
  if (!policy.izinli_uzantilar.some((u) => yol.toLowerCase().endsWith(u))) {
    dur(`Uzantı izinli değil: ${path.basename(yol)}\n     izinliler: ${policy.izinli_uzantilar.join(", ")}`)
  }
  if (!bolum) dur("--bolum belirtilmedi.")
  if (policy.yasak_bolumler.includes(bolum)) dur(`Bölüm yasak: ${bolum}`)
  if (!policy.hedef_bolumler.includes(bolum)) {
    dur(`Bölüm izinli değil: ${bolum}\n     izinliler: ${policy.hedef_bolumler.join(", ")}`)
  }

  const sha = await sha256Dosya(yol)
  const boyMb = fs.statSync(yol).size / (1024 * 1024)
  const ic = await imajIncele(yol, policy)

  cizgi()
  console.log(`  ${B}GÖVDE KORUMASI — İMAJ İNCELEMESİ${X}`)
  cizgi()
  console.log(`  dosya      : ${yol}`)
  console.log(`  boyut      : ${boyMb.toFixed(2)} MB`)
  console.log(`  sha256     : ${sha}`)
  console.log(`  hedef bölüm: ${bolum}`)
  if (ic.icerik.length) {
    console.log(`  içerik     : ${ic.icerik.length} dosya`)
    for (const ad of ic.icerik.slice(0, 15)) console.log(`      - ${ad}`)
    if (ic.icerik.length > 15) console.log(`      … +${ic.icerik.length - 15}`)
  }
  console.log(`  cihaz izi  : ${ic.kodlar.length ? ic.kodlar.join(", ") : "(içerikte kod adı yok)"}`)
  if (ic.adKodlari.length) console.log(`  ad kanıtı  : ${ic.adKodlari.join(", ")}`)
  for (const p of ic.prop) console.log(`      ${p.anahtar} = ${p.deger}   (${p.etiket})`)

  const yasak = policy.reddedilecek_cihaz_kodlari ?? []
  const propRed = ic.prop.filter(
    (p) => (p.anahtar === "ro.product.device" || p.anahtar === "ro.build.product") &&
           !policy.izinli_cihaz_kodlari.includes(p.deger),
  )
  const propYesil = ic.prop.filter(
    (p) => (p.anahtar === "ro.product.device" || p.anahtar === "ro.build.product") &&
           policy.izinli_cihaz_kodlari.includes(p.deger),
  )
  const adRed = ic.adKodlari.filter((k) => yasak.includes(k))
  const adYesil = ic.adKodlari.filter((k) => policy.izinli_cihaz_kodlari.includes(k))
  const icerikRed = ic.kodlar.filter((k) => yasak.includes(k))
  const icerikYesil = ic.kodlar.filter((k) => policy.izinli_cihaz_kodlari.includes(k))

  const karantina = async (sebep, detay) => {
    await fsp.mkdir(KARANTINA, { recursive: true })
    const hedef = path.join(KARANTINA, `${path.basename(yol)}.${sha.slice(0, 12)}.reddedildi`)
    await fsp.copyFile(yol, hedef)
    await journal({ olay: "reddedildi", sebep, detay, sha256: sha, dosya: yol })
    return hedef
  }

  // 1) En guclu kanit: imajin kendi ro.product.device degeri yasak bir cihaz diyorsa dur.
  if (propRed.length) {
    const h = await karantina("prop_cihaz_uyusmadi", JSON.stringify(propRed))
    dur(`${propRed[0].anahtar} = '${propRed[0].deger}' — bu senin telefonun değil.\n` +
        `     Senin telefonun: ${policy.cihaz.model}\n` +
        `     Kopya karantinaya alındı: ${h}`)
  }
  // 2) Dosya adi bilerek yazilmis bir kanittir: 'twrp-j3xlte-recovery.tar' reddedilmeli.
  if (adRed.length) {
    const h = await karantina("yanlis_cihaz_ad", adRed.join(","))
    dur(`YANLIŞ CİHAZ İMAJI (dosya adı). Bu imaj şunlara ait: ${adRed.join(", ")}\n` +
        `     Senin telefonun: ${policy.cihaz.model} (${policy.cihaz.soc})\n` +
        `     Kopya karantinaya alındı: ${h}`)
  }
  // 3) Ham icerikteki kod adi ZAYIF kanittir. Prop ve dosya adi bir sey soylemiyorsa konusur.
  //    Dokunmatik firmware yolu (melfas/j1minilte.fw) yuzunden dogru imaj reddedilmesin.
  //    Icerik IZINLI kodu da gosteriyorsa iki zayif kanit celisir; zayif kanit karar vermez.
  //    (Olculdu: stok boot.img'de j1minilte yalniz melfas/j1minilte.fw yolundan gelir;
  //     ayni dosyada j1minivelte 552 kez gecer. Kural icerikYesil'i saymadigi icin
  //     koruma telefonun KENDI stok boot.img'sini reddediyordu.)
  if (!propYesil.length && !adYesil.length && !icerikYesil.length && icerikRed.length) {
    const h = await karantina("yanlis_cihaz_icerik", icerikRed.join(","))
    dur(`YANLIŞ CİHAZ İMAJI (içerik). Bu imaj şunlara ait: ${icerikRed.join(", ")}\n` +
        `     Senin telefonun: ${policy.cihaz.model} (${policy.cihaz.soc})\n` +
        `     Kopya karantinaya alındı: ${h}`)
  }

  const kanitVar = propYesil.length || adYesil.length || icerikYesil.length
  if (!kanitVar && !kabul) {
    await journal({ olay: "reddedildi", sebep: "kanit_yok", sha256: sha, dosya: yol })
    dur(`Bu imajın ${policy.cihaz.model} için olduğuna dair HİÇBİR kanıt yok.\n` +
        `     İçinde kod adı da, ro.product.device da bulunamadı.\n` +
        `     Emin olduğunu söylüyorsan: --kanit-yok-kabul ekle`)
  }

  const sinir = policy.bolum_boyut_ust_siniri_mb?.[bolum]
  if (sinir && boyMb > sinir) dur(`Boyut bölüm sınırını aşıyor: ${boyMb.toFixed(2)} MB > ${sinir} MB`)

  await fsp.mkdir(ONAY_DIR, { recursive: true })
  const kayit = {
    surum: 1, sha256: sha, dosya: yol, dosya_adi: path.basename(yol),
    boyut_mb: +boyMb.toFixed(3), bolum, cihaz_izi: ic.kodlar,
    prop_kanit: ic.prop, hedef_cihaz: policy.cihaz.model,
    olusturma: Date.now(), kanit_yok_kabul: !!kabul,
  }
  await fsp.writeFile(path.join(ONAY_DIR, `bekleyen-${sha}.json`), JSON.stringify(kayit, null, 2))
  await journal({ olay: "incelendi", sha256: sha, bolum, dosya: yol, cihaz_izi: ic.kodlar })

  cizgi()
  gecti("İnceleme tamam. Hiçbir şey yazılmadı.")
  console.log(`\n  Sıradaki adım:\n      j106f-flash flash ${yol} --bolum ${bolum}\n`)
  return sha
}

// Kullanıcının kendi terminalinde onay + yazma
async function flash(imaj, bolum, gercek) {
  const policy = await policyYukle()
  const yol = path.resolve(imaj)

  if (!bolum) dur("--bolum belirtilmedi.")
  if (policy.yasak_bolumler.includes(bolum)) dur(`Bölüm yasak: ${bolum}`)
  if (!policy.hedef_bolumler.includes(bolum)) dur(`Bölüm izinli değil: ${bolum}`)

  // heimdall bir bolume HAM BAYT yazar. OTA zip'i ham imaj degildir: icinde
  // blok haritasi (system.transfer.list) ve brotli yuku vardir; ayrica
  // updater-script'i calistiran sey TWRP'dir. Zip'i heimdall'a vermek bolume
  // zip dosyasini yazar. ROM zip'i TWRP'den kurulur (bkz. docs/FLASH.md).
  if (yol.toLowerCase().endsWith(".zip")) {
    dur(`Bu bir OTA zip'i, ham imaj değil: ${path.basename(yol)}\n` +
        `     heimdall bölüme ham bayt yazar; zip'in içindeki blok haritasını\n` +
        `     çalıştıracak olan TWRP'dir. ROM'u TWRP'den kur:\n` +
        `     Install → ${path.basename(yol)} → Swipe to confirm`)
  }

  if (!process.stdin.isTTY) {
    dur("Bu adım gerçek bir terminal gerektirir.\n" +
        "     Bu komutu KENDİ terminalinde çalıştır — ajan bu kapıyı açamaz.")
  }

  cizgi()
  console.log(`  ${B}GÖVDE KORUMASI — FLASH KAPISI${X}`)
  cizgi()

  if (!fs.existsSync(yol)) dur(`İmaj yok: ${yol}`)
  const sha = await sha256Dosya(yol)

  const bekleyen = path.join(ONAY_DIR, `bekleyen-${sha}.json`)
  if (!fs.existsSync(bekleyen)) {
    dur(`Bu sha256 için inceleme kaydı yok: ${sha}\n     Önce: j106f-flash incele ${yol} --bolum ${bolum}`)
  }
  const kayit = JSON.parse(await fsp.readFile(bekleyen, "utf8"))
  if (kayit.bolum !== bolum) dur(`İnceleme kaydı '${kayit.bolum}' bölümü için, sen '${bolum}' istedin.`)
  gecti(`Kapı 1 — inceleme kaydı var (${kayit.dosya_adi})`)

  const onayDosya = path.join(ONAY_DIR, `${sha}.json`)
  let onay = null
  if (fs.existsSync(onayDosya)) onay = JSON.parse(await fsp.readFile(onayDosya, "utf8"))
  if (onay?.tuketildi) dur("Bu onay daha önce kullanıldı. Yeniden incele ve onayla.")
  if (onay && (Date.now() - onay.imzalandi) / 1000 > (policy.onay_gecerlilik_saniye ?? 1800)) {
    dur("Onay süresi doldu. Yeniden incele ve onayla.")
  }

  if (!onay) {
    cizgi()
    console.log(`  YAZILACAK : ${path.basename(yol)}`)
    console.log(`  BÖLÜM     : ${bolum}`)
    console.log(`  SHA256    : ${sha}`)
    console.log(`  CİHAZ     : ${kayit.hedef_cihaz}`)
    cizgi()
    const cevap = await sor(`Onaylıyorsan sha256'nın ilk 16 karakterini yaz (${sha.slice(0, 16)}): `)
    if (cevap.trim().toLowerCase() !== sha.slice(0, 16)) {
      await journal({ olay: "onay_reddi", sebep: "yazi_uyusmadi", sha256: sha })
      dur("Yazılı onay verilmedi.")
    }
    onay = { surum: 1, sha256: sha, bolum, imzalandi: Date.now(), tuketildi: null }
    await fsp.writeFile(onayDosya, JSON.stringify(onay, null, 2))
    await journal({ olay: "onaylandi", sha256: sha, bolum, dosya: yol })
    gecti("Kapı 2 — kullanıcı onayı alındı")
  } else {
    gecti("Kapı 2 — geçerli onay bulundu")
  }

  if (!spawnSync("heimdall", ["--version"], { encoding: "utf8" }).error &&
      !spawnSync("which", ["heimdall"], { encoding: "utf8" }).stdout?.trim()) {
    dur("heimdall kurulu değil.")
  }
  const detect = spawnSync("heimdall", ["detect"], { encoding: "utf8" })
  if (detect.status !== 0) {
    dur("Download mode cihaz bulunamadı.\n" +
        "     Telefonu kapat, Home+Power+SesKısık ile download mode'a al, USB'ye tak.")
  }
  gecti("Kapı 3 — cihaz download mode'da")

  // Heimdall bolum adlarini YALNIZCA cihazin PIT tablosundan cozer; takma ad
  // yoktur. Boot bolumunun PIT adi KERNEL'dir — '--boot' yazmak
  // "Partition boot does not exist in the specified PIT" ile biter.
  // Mantiksal ad -> PIT adi eslemesi policy.json'dadir.
  const pitAdi = policy.pit_bolum_adi?.[bolum] ?? bolum
  const pit = spawnSync("heimdall", ["print-pit", "--no-reboot"], { encoding: "utf8" })
  if (pit.status !== 0) dur(`PIT tablosu okunamadı (heimdall print-pit, kod ${pit.status}).`)
  const pitBoy = pitBolumBoyu(pit.stdout ?? "", pitAdi)
  if (pitBoy === null) {
    dur(`Cihazin PIT tablosunda '${pitAdi}' bolumu yok (mantiksal ad: ${bolum}).\n` +
        `     Yanlis cihaz olabilir. PIT'i elle kontrol et: heimdall print-pit --no-reboot`)
  }
  const dosyaBoy = fs.statSync(yol).size
  if (dosyaBoy > pitBoy) {
    dur(`Imaj cihazin bolumune SIGMAZ: dosya ${dosyaBoy} bayt > ${pitAdi} ${pitBoy} bayt.`)
  }
  gecti(`Kapı 3b — PIT: ${pitAdi} ${pitBoy} bayt, imaj ${dosyaBoy} bayt (sigar)`)

  // heimdall CLI arsiv ACMAZ. Tar destegi yalnizca heimdall-frontend'dedir
  // (olculdu: /usr/bin/heimdall ikilisinde 'ustar'/'tar'/'extract' dizeleri
  // yok; heimdall-frontend'de 'temporary TAR file' var). Bu yuzden
  // recovery.tar'i oldugu gibi yazmak bolume tar arsivini yazar, imaji degil.
  // .tar/.tar.md5 verilirse icindeki imaji cikarip ONU yazariz.
  let yazilacakYol = yol
  let gecici = null
  let geciciDir = null
  if (yol.toLowerCase().endsWith(".tar") || yol.toLowerCase().endsWith(".tar.md5")) {
    const uye = (execFileSync("tar", ["-tf", yol], { encoding: "utf8" }) || "")
      .split("\n").map((s) => s.trim()).filter(Boolean)
      .find((s) => s.toLowerCase().endsWith(".img"))
    if (!uye) dur("Tar arsivinde .img dosyasi yok.")
    geciciDir = await fsp.mkdtemp(path.join(os.tmpdir(), "govde-"))
    execFileSync("tar", ["-xf", yol, "-C", geciciDir, uye])
    gecici = path.join(geciciDir, path.basename(uye))
    yazilacakYol = gecici
    const cikBoy = fs.statSync(gecici).size
    if (cikBoy > pitBoy) dur(`Tar icindeki imaj bolume SIGMAZ: ${cikBoy} > ${pitBoy} bayt.`)
    gecti(`Kapı 3c — tar acildi: ${uye} ${cikBoy} bayt`)
  }

  // son kontrol: imaj hâlâ aynı mı
  if ((await sha256Dosya(yol)) !== sha) dur("İmaj onaydan sonra değişti.")
  gecti("Kapı 4 — imaj bayt bayt aynı")

  cizgi()
  const son = await sor(`Yazmak için tam olarak "YAZ ${bolum}" yaz: `)
  if (son.trim() !== `YAZ ${bolum}`) {
    if (geciciDir) await fsp.rm(geciciDir, { force: true, recursive: true })
    await journal({ olay: "flash_reddi", sebep: "son_onay_yok", sha256: sha })
    dur("Son onay verilmedi.")
  }

  const komut = ["heimdall", "flash", `--${pitAdi}`, yazilacakYol, "--no-reboot"]
  await journal({ olay: "flash_basliyor", sha256: sha, bolum, komut, gercek: !!gercek })

  if (!gercek) {
    console.log(`\n  ${Y}KURU ÇALIŞMA. Gerçek yazım yapılmadı.${X}`)
    console.log(`  Komut: ${komut.join(" ")}`)
    console.log(`  Gerçekten yazmak için: --gercek ekle\n`)
    if (geciciDir) await fsp.rm(geciciDir, { force: true, recursive: true })
    return
  }

  onay.tuketildi = Date.now()
  await fsp.writeFile(onayDosya, JSON.stringify(onay, null, 2))

  console.log(`\n  ${B}YAZILIYOR...${X}`)
  const r = spawnSync("heimdall", komut.slice(1), { stdio: "inherit" })
  if (geciciDir) await fsp.rm(geciciDir, { force: true, recursive: true })
  await journal({ olay: "flash_bitti", sha256: sha, bolum, cikis_kodu: r.status })
  if (r.status !== 0) dur(`heimdall başarısız (kod ${r.status})`)
  gecti("Yazım tamam. Telefonu elle yeniden başlat.")
}

function sor(metin) {
  process.stdout.write(metin)
  return new Promise((resolve) => {
    process.stdin.resume()
    process.stdin.once("data", (d) => {
      process.stdin.pause()
      resolve(d.toString())
    })
  })
}

async function durum() {
  await fsp.mkdir(ONAY_DIR, { recursive: true })
  const dosyalar = (await fsp.readdir(ONAY_DIR)).filter((f) => f.startsWith("bekleyen-"))
  console.log(`Onay bekleyen imaj: ${dosyalar.length}`)
  for (const f of dosyalar) {
    const k = JSON.parse(await fsp.readFile(path.join(ONAY_DIR, f), "utf8"))
    const onayVar = fs.existsSync(path.join(ONAY_DIR, `${k.sha256}.json`))
    const yas = ((Date.now() - k.olusturma) / 60000).toFixed(1)
    console.log(`  - ${k.dosya_adi.padEnd(40)} ${k.sha256.slice(0, 16)}… ${k.bolum.padEnd(10)} ` +
                `${onayVar ? "ONAYLI ✔" : "onaysız"}  (${yas} dk)`)
  }
}

// ---- argümanlar ----
const argv = process.argv.slice(2)
const komut = argv[0]
const kalan = argv.slice(1)
const pozisyonel = kalan.filter((a) => !a.startsWith("--"))
const bayrakli = new Set(kalan.filter((a) => a.startsWith("--")))

function bayrakDeger(ad) {
  const i = kalan.indexOf(ad)
  return i >= 0 ? kalan[i + 1] : null
}

const bolum = bayrakDeger("--bolum")

if (komut === "incele") {
  await incele(pozisyonel[0], bolum, bayrakli.has("--kanit-yok-kabul"))
} else if (komut === "flash") {
  await flash(pozisyonel[0], bolum, bayrakli.has("--gercek"))
} else if (komut === "durum") {
  await durum()
} else {
  console.log(`j106f-flash — gövde korumalı flash sarmalayıcısı

  j106f-flash incele <imaj> --bolum <recovery|boot|system|modem>
  j106f-flash flash  <imaj> --bolum <recovery|boot|system|modem> [--gercek]
  j106f-flash durum

Bu komutlar gerçek bir terminal ister. Ajan bu kapıdan geçemez.`)
}
