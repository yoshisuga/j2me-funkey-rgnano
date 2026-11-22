#!/bin/bash
# Prints the file URLs (jar, and jam / sp / jad when there are any) of one j2me.one game page.
#   scripts/game-urls.sh https://j2me.one/game/xevious-for-mobage
# Add -d to also download the files into ./<game-id>/ .
set -e
DL=0; [ "$1" = "-d" ] && { DL=1; shift; }
PAGE=${1:?usage: game-urls.sh [-d] <game page url>}
python3 -I - "$PAGE" "$DL" <<'PY'
import json, re, sys, urllib.request, urllib.parse, os
page, dl = sys.argv[1], sys.argv[2] == "1"
req = urllib.request.Request(page, headers={"User-Agent": "game-urls.sh (personal use)"})
html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
m = re.search(r'<script[^>]*id="game-data"[^>]*>(.*?)</script>', html, re.S)
if not m: sys.exit("no game data on that page")
g = json.loads(m.group(1))
urls = []
for k in ("jar", "jam", "sp", "jad", "jarUrl", "jadUrl"):
    v = g.get(k)
    if v:
        u = urllib.parse.urljoin(page, "/" + v.lstrip("/")) if not v.startswith("http") else v
        if u not in urls: urls.append(u); print(u)
if dl:
    d = g.get("id") or page.rstrip("/").rsplit("/", 1)[-1]
    os.makedirs(d, exist_ok=True)
    for u in urls:
        r = urllib.request.Request(u, headers={"User-Agent": "game-urls.sh (personal use)"})
        open(os.path.join(d, os.path.basename(u)), "wb").write(urllib.request.urlopen(r, timeout=60).read())
    print("saved to", d + "/", file=sys.stderr)
PY
