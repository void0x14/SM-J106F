#!/usr/bin/env bash
# Gövde koruması — Grok PreToolUse kapısı.
#
# Grok'un run_terminal_command aracı çalışmadan ÖNCE bu betik çağrılır. JSON
# stdin'den gelir; karar stdout'a JSON olarak yazılır. `deny` + exit 2 çağrıyı
# engeller.
#
# ÖNEMLİ: Grok hook'ları HATA DURUMUNDA FAIL-OPEN olur. Yani bu betik çökerse
# komut geçer. Bu yüzden betik hiçbir yerde çökmemeli ve yazma sınıfına giren
# her komut için açıkça `deny` yazmalı. Girdi okunamazsa dahi deny yazılır.
#
# Sınıf tanımı (kural listesi değil, davranış): "ham bir imajı bir aygıta/bölüme
# yazan" araçlar. Telefona yazma yolu yalnızca kullanıcının kendi terminalinde
# çalıştırdığı j106f-flash sarmalayıcısıdır.

set -u

GIRDI="$(cat 2>/dev/null || true)"

# --- Girdiyi çöz. jq yoksa node'a düş; o da yoksa deny. ---
coz() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$GIRDI" | jq -r "$1" 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    printf '%s' "$GIRDI" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let j={};try{j=JSON.parse(s)}catch(e){}
        const y=(o,p)=>p.split(".").reduce((a,k)=>a==null?a:a[k],o);
        process.stdout.write(String(y(j,process.argv[1])??""));
      });' "$1" 2>/dev/null
  else
    echo ""
  fi
}

ARAC="$(coz '.toolName')"
KOMUT="$(coz '.toolInput.command')"

# Sadece terminal komutları denetlenir.
case "$ARAC" in
  run_terminal_command|Bash|bash|shell|exec_command) ;;
  *) echo '{"decision":"defer"}'; exit 0 ;;
esac

[ -n "$KOMUT" ] || { echo '{"decision":"defer"}'; exit 0; }

# --- Yazma sınıfı. Komut metni üzerinde desen araması. ---
engelle() {
  # $1 = gerekçe
  printf '{"decision":"deny","reason":"GÖVDE KORUMASI: %s\\nTelefona yazma yalnızca kullanıcının kendi terminalinden j106f-flash ile yapılır. Ajan bu kapıdan geçemez."}\n' "$1"
  exit 2
}

# 1) heimdall yazma (flash / download-pit / close-pc-screen)
if printf '%s' "$KOMUT" | grep -qiE 'heimdall[^|;&]*(flash|download-pit|close-pc-screen|--recovery|--kernel|--system|--modem|--uboot|--cache|--hidden|--userdata)'; then
  engelle "heimdall yazma komutu"
fi

# 2) Odin ailesi
if printf '%s' "$KOMUT" | grep -qiE '\b(odin4?|odin|JOdin3)\b'; then
  engelle "Odin yazma komutu"
fi

# 3) fastboot yazma
if printf '%s' "$KOMUT" | grep -qiE 'fastboot[^|;&]*(flash|erase|format|update)'; then
  engelle "fastboot yazma komutu"
fi

# 4) Ham blok yazma (dd of=...)
if printf '%s' "$KOMUT" | grep -qiE 'dd[^|;&]*of=/dev/(block|sd[a-z]|mmcblk|disk)'; then
  engelle "dd ile ham blok yazma"
fi

# 5) flash_image / benzeri
if printf '%s' "$KOMUT" | grep -qiE '\b(flash_image|flashcp|nandwrite|erase_image|dump_image)\b'; then
  engelle "ham flash aracı"
fi

# 6) SPRD/MTK düşük seviye araçlar
if printf '%s' "$KOMUT" | grep -qiE '\b(mtkclient|spd_dump|sprd_dump|research_download)\b'; then
  engelle "düşük seviye SoC yazma aracı"
fi

# 7) Bölüm tablosu yazma
if printf '%s' "$KOMUT" | grep -qiE '(heimdall[^|;&]*write-pit|write-pit|pit[^|;&]*flash)'; then
  engelle "PIT yazma"
fi

# 8) Doğrudan aygıt düğümüne yönlendirme (>, >>, tee)
if printf '%s' "$KOMUT" | grep -qiE '(>|>>|tee)[[:space:]]*/dev/(block|mmcblk|sd[a-z]|disk)'; then
  engelle "aygıt düğümüne yönlendirme"
fi

echo '{"decision":"allow"}'
exit 0
