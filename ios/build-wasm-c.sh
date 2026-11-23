#!/bin/sh
# Turns the browser build's runMidlet.wasm into C for the iOS app (ios/Generated)
# and unpacks the runtime files (ios/Resources/midp).
#   needs: wabt (wasm2c), python3, git; WASM_SRC=<dir> with runMidlet.wasm,
#   midp-files.js/.data (default: fetched from origin/gh-pages = the published web build)
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GEN=$HERE/Generated
mkdir -p "$GEN" "$HERE/Resources"
if [ -z "${WASM_SRC:-}" ]; then
    WASM_SRC=$GEN/web
    mkdir -p "$WASM_SRC"
    git -C "$HERE/.." fetch -q origin gh-pages
    for f in runMidlet.wasm midp-files.js midp-files.data; do
        git -C "$HERE/.." show "origin/gh-pages:$f" > "$WASM_SRC/$f"
    done
fi
rm -f "$GEN"/midp*.c "$GEN"/midp*.h
wasm2c "$WASM_SRC/runMidlet.wasm" --module-name=midp --num-outputs=8 -o "$GEN/midp.c"
python3 -I "$HERE/gen-sigs.py" "$WASM_SRC/runMidlet.wasm" "$GEN/fk_sigs.c"
python3 -I - "$WASM_SRC" "$HERE/Resources" <<'PY'
import json, os, re, shutil, sys
src, dst = sys.argv[1:3]
js = open(os.path.join(src, 'midp-files.js')).read()
meta = json.loads(re.search(r'loadPackage\((\{.*?\})\);\s*\n', js, re.S).group(1))
data = open(os.path.join(src, 'midp-files.data'), 'rb').read()
shutil.rmtree(os.path.join(dst, 'midp'), ignore_errors=True)
for f in meta['files']:
    p = os.path.join(dst, f['filename'].lstrip('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(data[f['start']:f['end']])
print(len(meta['files']), 'runtime files')
PY
python3 -I "$HERE/patch-generated.py" "$GEN"
# wasm-rt runtime, copied so the Xcode project is self-contained
WABT=$(dirname "$(dirname "$(command -v wasm2c)")")
cp -f "$WABT"/include/wasm-rt.h "$WABT"/include/wasm2c/*.h "$GEN/" 2>/dev/null || true
cp -f "$(brew --prefix wabt)"/include/wasm-rt.h "$GEN/"
for f in wasm-rt-impl.c wasm-rt-mem-impl.c wasm-rt-exceptions-impl.c wasm-rt-impl.h wasm-rt-impl-tableops.inc wasm-rt-mem-impl-helper.inc; do
    cp -f "$(brew --prefix wabt)/share/wabt/wasm2c/$f" "$GEN/"
done
echo "generated: $GEN"
