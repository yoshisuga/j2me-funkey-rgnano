import SwiftUI

extension Game: Identifiable {
    var id: String { jar.path }
    /// A game shipped inside the app (cannot be deleted).
    var isBundled: Bool { jar.path.hasPrefix(Bundle.main.bundlePath) }
}

/// The games in Documents/java (plus the bundled demos). The screen is driven by `games`:
/// whatever changes it (an import, a delete, a sort) shows up at once.
final class GameStore: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var loaded = false
    private var generation = 0

    /// Scans the games folder off the main thread, then publishes the sorted list.
    func reload(completion: (() -> Void)? = nil) {
        generation += 1
        let mine = generation
        let dir = Launcher.shared.gamesDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Library.sorted(GameStore.scan(dir))
            DispatchQueue.main.async {
                if mine == self.generation {
                    self.games = list
                    self.loaded = true
                }
                completion?()
            }
        }
    }

    func reloadAsync() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in reload { c.resume() } }
    }

    func resort() { games = Library.sorted(games) }

    private static func scan(_ dir: URL) -> [Game] {
        var list: [Game] = []
        for name in ["StarCatcher", "VoidWave", "RainbowHop", "GemSwap"] {   // demo games shipped in the app
            if let demo = Bundle.main.url(forResource: name, withExtension: "jar"), let g = Game.load(jar: demo) { list.append(g) }
        }
        // jars in Documents/java, also one folder deep (a game with its .jam and .sp in a folder)
        let fm = FileManager.default
        var jars: [URL] = []
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            if item.pathExtension.lowercased() == "jar" { jars.append(item) }
            else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                jars += ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "jar" }
            }
        }
        return list + jars.compactMap { Game.load(jar: $0) }
    }
}

/// A game's icon, read off the main thread; a controller symbol until it is there (or if it has none).
private struct GameIcon: View {
    let game: Game
    var size: CGFloat = 44          // how big it is drawn: pixel art stays sharp when enlarged, smooth when reduced
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().interpolation(size < image.size.width ? .high : .none).scaledToFit()
            } else {
                Image(systemName: "gamecontroller.fill").resizable().scaledToFit()
                    .foregroundColor(Color(.tertiaryLabel)).padding(6)
            }
        }
        .task(id: game.id) {
            let g = game
            image = await Task.detached(priority: .userInitiated) { g.loadIcon() }.value
        }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct GameListView: View {
    @ObservedObject var store: GameStore
    @AppStorage("lib.layout") private var layout = "grid"
    @AppStorage("lib.tile") private var tile = 120.0

    var open: (Game) -> Void
    var settings: (Game) -> Void
    var delete: (Game) -> Void

    static let tileRange: ClosedRange<Double> = 70...220

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if layout == "list" { list } else { grid }
            if store.loaded && store.games.count <= 1 {
                Text("Tap + to import games from Files.\nAn i-appli needs its .jam (and .sp):\nimport them together or as a folder.")
                    .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .padding(24).allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if layout != "list" { sizeSlider }
        }
    }

    private var sizeSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill").foregroundColor(.secondary)
            Slider(value: $tile, in: GameListView.tileRange)
            Image(systemName: "square.grid.2x2.fill").foregroundColor(.secondary)
        }
        .imageScale(.small)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private func menu(_ g: Game) -> some View {
        Button { settings(g) } label: { Label("Game Settings", systemImage: "gearshape") }
        if !g.isBundled {
            Button(role: .destructive) { delete(g) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: grid

    private let gridSpacing: CGFloat = 14

    private var grid: some View {
        GeometryReader { geo in
            // every tile is exactly `tile` wide (so the icons follow the slider continuously);
            // the number of columns is what fits, and the rows are centred
            let avail = max(geo.size.width - 32, 60)
            let t = min(CGFloat(tile), avail)
            let n = max(1, Int((avail + gridSpacing) / (t + gridSpacing)))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(t), spacing: gridSpacing, alignment: .top), count: n),
                          spacing: 18) {
                    ForEach(store.games) { g in
                        Button { open(g) } label: { tileView(g, t) }
                            .buttonStyle(PressStyle())
                            .contextMenu { menu(g) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12).padding(.bottom, 16)
            }
            .refreshable { await store.reloadAsync() }
        }
    }

    private func tileView(_ g: Game, _ t: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: t * 0.17, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: t * 0.17, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1))
                GameIcon(game: g, size: t * 0.66).padding(t * 0.17)
                if g.isIAppli {
                    Text("i-appli").font(.system(size: max(8, t * 0.075), weight: .bold))
                        .foregroundColor(.white).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red.opacity(0.85)).cornerRadius(4).padding(6)
                }
            }
            .frame(width: t, height: t)
            Text(g.name).font(.system(size: max(11, min(16, t * 0.11)), weight: .medium))
                .foregroundColor(.primary).multilineTextAlignment(.center).lineLimit(2)
                .frame(width: t)
        }
    }

    // MARK: list

    private var list: some View {
        List(store.games) { g in
            Button { open(g) } label: {
                HStack(spacing: 14) {
                    GameIcon(game: g).frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill)).cornerRadius(9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).foregroundColor(.primary)
                        Text(g.jar.lastPathComponent + (g.isIAppli ? "  ·  i-appli" : ""))
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .swipeActions(edge: .trailing) {
                if !g.isBundled {
                    // not role: .destructive: that makes the list drop the row at once, before the
                    // confirmation (a mismatch with the data crashes UICollectionView)
                    Button { delete(g) } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                }
            }
            .contextMenu { menu(g) }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reloadAsync() }
    }
}
