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
                    px.append(f'<rect x="{x}" y="{y}" width="{cell}" height="{cell}"/>')
glyphs = "".join(px)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a1466"/><stop offset="1" stop-color="#e0408a"/></linearGradient>
 <linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f45"/><stop offset="1" stop-color="#14162a"/></linearGradient>
 <linearGradient id="scr" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="#4fd3ff"/><stop offset="0.55" stop-color="#2a6cf0"/><stop offset="1" stop-color="#2a2aa8"/></linearGradient>
 <!-- one LCD pixel = 8 units: dark gaps between pixels, and the red/green/blue stripes of each -->
 <pattern id="grid" width="8" height="8" patternUnits="userSpaceOnUse">
  <rect width="8" height="1.4" fill="#000" fill-opacity="0.2"/><rect width="1.4" height="8" fill="#000" fill-opacity="0.2"/>
 </pattern>
 <pattern id="rgb" width="8" height="8" patternUnits="userSpaceOnUse">
  <rect x="1.4" width="2.2" height="8" fill="#f00" fill-opacity="0.16"/><rect x="3.6" width="2.2" height="8" fill="#0f0" fill-opacity="0.12"/><rect x="5.8" width="2.2" height="8" fill="#00f" fill-opacity="0.2"/>
 </pattern>
 <clipPath id="clip"><rect x="124" y="124" width="776" height="740" rx="56"/></clipPath>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<rect x="64" y="64" width="896" height="896" rx="150" fill="url(#body)" stroke="#6f76a8" stroke-width="8"/>
<g clip-path="url(#clip)">
 <rect x="124" y="124" width="776" height="740" fill="url(#scr)"/>
 <g fill="#0a0f5c" fill-opacity="0.75" transform="translate(8 8)">{glyphs}</g>
 <g fill="#ffe94a" transform="translate(-4 0)" opacity="0.9">{glyphs}</g>
 <g fill="#ffffff" transform="translate(0 -2)">{glyphs}</g>
 <rect x="124" y="124" width="776" height="740" fill="url(#rgb)"/>
 <rect x="124" y="124" width="776" height="740" fill="url(#grid)"/>
 <path d="M124 124 H620 L124 640 Z" fill="#fff" fill-opacity="0.10"/>
</g>
<circle cx="512" cy="912" r="14" fill="#e0408a"/>
</svg>'''
open("icon.svg", "w").write(svg)
