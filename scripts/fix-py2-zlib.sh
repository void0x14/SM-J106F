#!/usr/bin/env bash
# LOS 15.1'in gomulu python2.7.5'i zlib modulu olmadan geliyor.
# releasetools (build_image.py -> import gzip -> import zlib) bu yuzden patliyor:
#   ImportError: No module named zlib
# Cozum: 32-bit modulu agactaki cpython2 kaynagindan derleyip lib-dynload'a kur.
set -euo pipefail
TOP="${TOP:-/home/void0x14/j106f/build/android}"
PY="$TOP/prebuilts/python/linux-x86/2.7.5"
INC="$PY/include/python2.7"
SRC="$TOP/external/python/cpython2/Modules/zlibmodule.c"

[ -f "$SRC" ] || { echo "kaynak yok: $SRC"; exit 1; }
[ -f "$PY/lib/python2.7/lib-dynload/zlib.so" ] && { echo "zlib.so zaten var"; exit 0; }

# Python 2.7.5, Py_SETREF/Py_XSETREF oncesi. Kaynak 2.7.13+ icin yazilmis; shim sart.
cat > /tmp/py275compat.h <<'EOF'
#ifndef Py_SETREF
#define Py_SETREF(op, op2) do { PyObject *_t=(PyObject*)(op); (op)=(op2); Py_DECREF(_t); } while (0)
#endif
#ifndef Py_XSETREF
#define Py_XSETREF(op, op2) do { PyObject *_t=(PyObject*)(op); (op)=(op2); Py_XDECREF(_t); } while (0)
#endif
EOF

gcc -m32 -O2 -fPIC -shared -include /tmp/py275compat.h \
    -I"$INC" "$SRC" -o "$PY/lib/python2.7/lib-dynload/zlib.so" -L/usr/lib32 -lz

"$PY/bin/python2.7" -c "import zlib,gzip,hashlib; print('zlib OK')"
