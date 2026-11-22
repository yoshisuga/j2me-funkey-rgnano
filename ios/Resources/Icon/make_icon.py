# Generates icon.svg (and icon-1024.png via rsvg-convert): a pixel "J2" on a handset screen.
J = ["....#", "....#", "....#", "....#", "#...#", "#...#", ".###."]
T = [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"]
cell, x0, y0 = 32, 512 - 11 * 16, 236
px = []
for gi, g in enumerate((J, T)):
    for r, row in enumerate(g):
        for c, ch in enumerate(row):
            if ch == "#":
                x = x0 + (gi * 6 + c) * cell
                px.append(f'<rect x="{x}" y="{y0 + r * cell}" width="{cell - 3}" height="{cell - 3}" rx="3"/>')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a1466"/><stop offset="1" stop-color="#e0408a"/></linearGradient>
 <linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f45"/><stop offset="1" stop-color="#14162a"/></linearGradient>
 <linearGradient id="scr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b9f5a0"/><stop offset="1" stop-color="#7fd66a"/></linearGradient>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<rect x="272" y="110" width="480" height="804" rx="96" fill="url(#body)" stroke="#6f76a8" stroke-width="8"/>
<rect x="320" y="178" width="384" height="340" rx="28" fill="url(#scr)"/>
<g fill="#16341a">{"".join(px)}</g>
<g fill="#3a3f63"><rect x="332" y="560" width="116" height="40" rx="20"/><rect x="576" y="560" width="116" height="40" rx="20"/></g>
<circle cx="512" cy="700" r="70" fill="#3a3f63"/><circle cx="512" cy="700" r="28" fill="#e0408a"/>
<g fill="#3a3f63"><rect x="344" y="800" width="96" height="44" rx="14"/><rect x="464" y="800" width="96" height="44" rx="14"/><rect x="584" y="800" width="96" height="44" rx="14"/></g>
</svg>'''
open("icon.svg", "w").write(svg)
