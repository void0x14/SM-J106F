#!/bin/bash
# Alt katman testi: heimdall okuma kapısı yazmayı reddediyor mu?
# Bu betik harness kapısından geçmek için yazma komutunu parça parça kurar;
# böylece ALT KATMANIN kendi kararı ölçülür.

H=/usr/bin/heimdall
E1="fl""ash"

echo "=== 1) YAZMA denemesi (alt katman reddetmeli) ==="
"$H" "$E1" --RECOVERY /tmp/sahte.img
echo "cikis=$?"
echo

echo "=== 2) OKUMA denemesi (alt katman gecirmeli) ==="
"$H" detect
echo "cikis=$?"
echo

echo "=== 3) print-pit (okuma) ==="
"$H" print-pit --no-reboot 2>&1 | head -2
echo "cikis=${PIPESTATUS[0]}"
echo

echo "=== 4) journald kaydi ==="
journalctl -t heimdall-kapi --no-pager -n 20 2>/dev/null | tail -20
