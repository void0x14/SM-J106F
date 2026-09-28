// gövde koruması — opencode eklentisi
//
// Ham flash komutlarını opencode araç çağrısı katmanında keser. Böylece ajan
// heimdall/odin/dd ile doğrudan telefona yazamaz; yazma yalnızca kullanıcının
// kendi terminalinde çalıştırdığı j106f-flash sarmalayıcısından geçer.
//
// Sarmalayıcı TTY ister ve parola doğrular. opencode'un bash aracı
// stdin:"ignore" ile süreç başlattığı için ajan o kapıdan geçemez.
//
// Engelleme throw ile olur; argümanlar asla yeniden yazılmaz.

import fs from "node:fs/promises"
import path from "node:path"
import os from "node:os"

// Eklenti ~/.config/opencode/plugins/ içinde, çekirdek ~/.config/opencode/govde/ içinde.
const KOK = path.join(os.homedir(), ".config", "opencode", "govde")
const JOURNAL = path.join(KOK, "govde-journal.jsonl")

// Yazma komutlarının ayırt edici parçaları. Kural listesi değil, davranış sınıfı:
// hepsi "ham bir imajı bir aygıta yazar" işini yapan araçlar.
const YAZMA_ISARETLERI = [
  /\bheimdall\b[^\n]*\bflash\b/i,
  /\bheimdall\b[^\n]*--(recovery|boot|system|modem|uboot|cache|hidden|userdata)\b/i,
  /\bheimdall\b[^\n]*\b(download-pit|close-pc-screen)\b/i,
  /\bodin\d*\b/i,
  /\bod?in4?\b/i,
  /\bfastboot\b[^\n]*\bflash\b/i,
  /\bflash_image\b/i,
  /\bdd\b[^\n]*\bof=\/dev\/block\//i,
  /\bdd\b[^\n]*\bof=\/dev\/sd[a-z]/i,
  /\bmtkclient\b/i,
  /\bspd_dump\b/i,
]

function yazmaKomutuMu(komut) {
  return YAZMA_ISARETLERI.some((re) => re.test(komut))
}

async function journal(yaz) {
  try {
    await fs.mkdir(KOK, { recursive: true })
    await fs.appendFile(JOURNAL, JSON.stringify({ zaman: new Date().toISOString(), ...yaz }) + "\n")
  } catch {
    // günlük yazılamazsa karar değişmez
  }
}

export const GovdeKorumaPlugin = async () => {
  await journal({ olay: "eklenti_yuklendi" })

  return {
    "tool.execute.before": async (input, output) => {
      const arac = typeof input?.tool === "string" ? input.tool : ""
      if (arac !== "bash") return

      const komut = typeof output?.args?.command === "string" ? output.args.command : ""
      if (!komut || !yazmaKomutuMu(komut)) return

      await journal({
        olay: "flash_engellendi",
        arac,
        komut,
        oturum: input?.sessionID ?? null,
      })

      throw new Error(
        [
          "GÖVDE KORUMASI: Ham flash komutu engellendi.",
          "",
          "Telefona yazma işlemi yalnızca kullanıcının kendi terminalinde çalıştırdığı",
          "sarmalayıcıdan geçer. Ajan bu kapıyı açamaz.",
          "",
          "Kullanıcının çalıştıracağı komut:",
          "    j106f-flash <imaj-dosyası> --bolum <recovery|boot|system|modem>",
          "",
          "Sarmalayıcı imajı inceler, cihaz kodunu doğrular ve parola ister.",
        ].join("\n"),
      )
    },
  }
}

export default GovdeKorumaPlugin
