import SwiftUI

/// "GENJ2" in the dot-matrix type of the app icon: lit pixels (white, with a shadow) on a small
/// blue LCD whose unlit pixels show as a faint grid. Drawn in code, so it is sharp at any size.
struct PixelTitle: View {
    private static let glyphs: [Character: [String]] = [
        "G": [".###.", "#...#", "#....", "#..##", "#...#", "#...#", ".###."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
        "J": ["....#", "....#", "....#", "....#", "#...#", "#...#", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    ]
    private static let text = Array("GENJ2")
    private static let cols = text.count * 6 - 1 + 6        // the letters and three blank pixels either side
    private static let rows = 7 + 4
    private static let cell: CGFloat = 2.8
    private static let bezel: CGFloat = 3

    static var size: CGSize {
        CGSize(width: CGFloat(cols) * cell + 2 * bezel, height: CGFloat(rows) * cell + 2 * bezel)
    }

    var body: some View {
        Canvas { ctx, size in
            let c = PixelTitle.cell, b = PixelTitle.bezel
            let body = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: body, cornerRadius: 9, style: .continuous),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.27), Color(red: 0.08, green: 0.09, blue: 0.16)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9, style: .continuous),
                       with: .color(Color(red: 0.44, green: 0.46, blue: 0.66)), lineWidth: 1)
            let screen = body.insetBy(dx: b, dy: b)
            ctx.fill(Path(roundedRect: screen, cornerRadius: 6, style: .continuous),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.31, green: 0.83, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.94), Color(red: 0.16, green: 0.16, blue: 0.66)]),
                                           startPoint: CGPoint(x: screen.minX, y: screen.minY), endPoint: CGPoint(x: screen.maxX, y: screen.maxY)))

            // every pixel of the panel: the unlit ones as a faint dark dot
            func rect(_ col: Int, _ row: Int, inset: CGFloat) -> CGRect {
                CGRect(x: screen.minX + CGFloat(col) * c + inset, y: screen.minY + CGFloat(row) * c + inset,
                       width: c - 2 * inset, height: c - 2 * inset)
            }
            var lit: [(Int, Int)] = []
            for (i, ch) in PixelTitle.text.enumerated() {
                guard let g = PixelTitle.glyphs[ch] else { continue }
                for (r, line) in g.enumerated() {
                    for (k, v) in line.enumerated() where v == "#" { lit.append((3 + i * 6 + k, 2 + r)) }
                }
            }
            for row in 0..<PixelTitle.rows {
                for col in 0..<PixelTitle.cols {
                    ctx.fill(Path(roundedRect: rect(col, row, inset: 0.35), cornerRadius: 0.5), with: .color(.black.opacity(0.14)))
                }
            }
            // the lit ones: a shadow, a yellow edge, then white
            for (col, row) in lit {
                ctx.fill(Path(roundedRect: rect(col, row, inset: 0.2).offsetBy(dx: 0.9, dy: 0.9), cornerRadius: 0.5),
                         with: .color(Color(red: 0.04, green: 0.06, blue: 0.36).opacity(0.7)))
            }
            for (col, row) in lit {
                ctx.fill(Path(roundedRect: rect(col, row, inset: 0.2).offsetBy(dx: -0.4, dy: 0), cornerRadius: 0.5),
                         with: .color(Color(red: 1.0, green: 0.91, blue: 0.29).opacity(0.9)))
            }
            for (col, row) in lit {
                ctx.fill(Path(roundedRect: rect(col, row, inset: 0.3).offsetBy(dx: 0, dy: -0.2), cornerRadius: 0.5), with: .color(.white))
            }
            // a glint across the corner
            var glint = Path()
            glint.move(to: CGPoint(x: screen.minX, y: screen.minY))
            glint.addLine(to: CGPoint(x: screen.minX + screen.width * 0.6, y: screen.minY))
            glint.addLine(to: CGPoint(x: screen.minX, y: screen.minY + screen.height * 0.8))
            glint.closeSubpath()
            ctx.fill(glint, with: .color(.white.opacity(0.1)))
        }
        .frame(width: PixelTitle.size.width, height: PixelTitle.size.height)
        .accessibilityElement()
        .accessibilityLabel("GenJ2")
    }
}
