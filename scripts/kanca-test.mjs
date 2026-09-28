// kanca-test.mjs — gövde koruması kancasını doğrudan sınar.
//
// Neden: `opencode run` ile canlı denemede modelin KENDİ güvenlik reddi
// devreye girebiliyor (özellikle `dd of=/dev/...`), o zaman guard'ın
// engellediği sanılır ama aslında engelleyen modeldir. Bu betik modeli
// tamamen devre dışı bırakır: eklentinin `tool.execute.before` kancasını
// doğrudan çağırır ve yalnızca kancanın kararını ölçer.
//
// Cihaz gerekmez, hiçbir şey yazmaz.
//
// Kullanım: node scripts/kanca-test.mjs [eklenti-yolu]
//   eklenti-yolu verilmezse kurulu kopya (~/.config/opencode/plugins/) kullanılır.
import os from "node:os"
import path from "node:path"
import { pathToFileURL } from "node:url"

const varsayilan = path.join(os.homedir(), ".config", "opencode", "plugins", "govde-koruma.js")
const yol = process.argv[2] || varsayilan

// Yazma komutlarının ayırt edici parçaları — kancanın engellemesi gerekenler.
const ENGELLENMELI = [
  "heimdall flash --RECOVERY /tmp/r.img",
  "heimdall flash --KERNEL /tmp/b.img",
  "heimdall download-pit --output pit.txt",
  "dd if=/tmp/x.img of=/dev/block/mmcblk0p20",
  "dd if=/tmp/x.img of=/dev/sda",
  "fastboot flash boot /tmp/b.img",
  "flash_image boot /tmp/b.img",
  "mtkclient w write boot /tmp/b.img",
  "spd_dump exec_addr 0x0 fdl /tmp/fdl",
  "odin4 -a /tmp/r.tar",
]

// Yazmayan komutlar — kanca bunlara dokunmamalı.
// `dd of=` düz dosyaya, `dd if=` blok aygıttan OKUMA: ikisi de izinli.
const GECMELI = [
  "echo merhaba",
  "ls -la /tmp",
  "git status",
  "dd if=/dev/block/mmcblk0p1 of=/tmp/yedek.img",
  "heimdall detect",
  "heimdall print-pit --output pit.txt",
]

const mod = await import(pathToFileURL(yol).href)
const eklenti = mod.GovdeKorumaPlugin || mod.default
if (typeof eklenti !== "function") {
  console.error(`eklenti yuklenemedi: ${yol}`)
  process.exit(2)
}

const { "tool.execute.before": kanca } = await eklenti()
if (typeof kanca !== "function") {
  console.error("tool.execute.before kancasi yok")
  process.exit(2)
}

let hata = 0

// bash aracı dışındaki araçlar hiç dokunulmamalı.
try {
  await kanca({ tool: "read" }, { args: { command: "dd if=x of=/dev/block/mmcblk0" } })
} catch {
  hata++
  console.log("  ✘ bash disi arac engellendi")
}

for (const komut of ENGELLENMELI) {
  let engellendi = false
  try {
    await kanca({ tool: "bash" }, { args: { command: komut } })
  } catch {
    engellendi = true
  }
  if (engellendi) console.log("  ✔ engellendi :", komut)
  else {
    hata++
    console.log("  ✘ ENGELLENMEDI:", komut)
  }
}

for (const komut of GECMELI) {
  let engellendi = false
  try {
    await kanca({ tool: "bash" }, { args: { command: komut } })
  } catch {
    engellendi = true
  }
  if (!engellendi) console.log("  ✔ gecti       :", komut)
  else {
    hata++
    console.log("  ✘ YANLIS ENGELLENDI:", komut)
  }
}

console.log(hata === 0 ? "\nSONUC: kanca matrisi temiz" : `\nSONUC: ${hata} hata`)
process.exit(hata === 0 ? 0 : 1)
