# Generates icon.svg (and icon-1024.png via rsvg-convert): "GEN" / "J2" in pixel type on an LCD screen.
G = {
 "G": [".###.", "#...#", "#....", "#..##", "#...#", "#...#", ".###."],
 "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
 "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
 "J": ["....#", "....#", "....#", "....#", "#...#", "#...#", ".###."],
 "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
}
cell, line_gap = 40, 60
rows = ["GEN", "J2"]
h = 2 * 7 * cell + line_gap
y0 = 512 - h // 2
px = []
for li, word in enumerate(rows):
    w = (len(word) * 6 - 1) * cell
    x0 = 512 - w // 2
    for gi, ch in enumerate(word):
        for r, row in enumerate(G[ch]):
            for c, v in enumerate(row):
                if v == "#":
                    x = x0 + (gi * 6 + c) * cell
                    y = y0 + li * (7 * cell + line_gap) + r * cell
                    px.append(f'<rect x="{x}" y="{y}" width="{cell - 4}" height="{cell - 4}" rx="4"/>')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a1466"/><stop offset="1" stop-color="#e0408a"/></linearGradient>
 <linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f45"/><stop offset="1" stop-color="#14162a"/></linearGradient>
 <linearGradient id="scr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b9f5a0"/><stop offset="1" stop-color="#7fd66a"/></linearGradient>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<rect x="64" y="64" width="896" height="896" rx="150" fill="url(#body)" stroke="#6f76a8" stroke-width="8"/>
<rect x="124" y="124" width="776" height="740" rx="56" fill="url(#scr)"/>
<g fill="#16341a">{"".join(px)}</g>
<circle cx="512" cy="912" r="14" fill="#e0408a"/>
</svg>'''
open("icon.svg", "w").write(svg)
