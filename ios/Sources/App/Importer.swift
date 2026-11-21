import Foundation

/// Copies games into Documents/java: loose .jar files, or an i-appli's .jar/.jam/.sp
/// (picked together, or as a folder) into a folder of its own.
enum Importer {
    static let extensions: Set<String> = ["jar", "jam", "sp", "net"]

    struct Result {
        var games = 0
        var files = 0
        var message: String {
            if games == 0 { return "No .jar files found. Pick a .jar (an i-appli: with its .jam and .sp) or a folder holding them." }
            return "Imported \(games) game\(games == 1 ? "" : "s")."
        }
    }

    private struct Item { let url: URL; let fromFolder: Bool }

    static func importItems(_ urls: [URL], into dir: URL) -> Result {
        let fm = FileManager.default
        var items: [Item] = []
        var opened: [URL] = []
        defer { opened.forEach { $0.stopAccessingSecurityScopedResource() } }

        for url in urls {
            if url.startAccessingSecurityScopedResource() { opened.append(url) }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDir {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL {
                    if extensions.contains(f.pathExtension.lowercased()) { items.append(Item(url: f, fromFolder: true)) }
                }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                items.append(Item(url: url, fromFolder: false))
            }
        }

        // one group per source folder: the files of one game (or of several plain jars)
        var groups: [String: [Item]] = [:]
        for it in items { groups[it.url.deletingLastPathComponent().path, default: []].append(it) }

        var result = Result()
        for (_, group) in groups {
            let jars = group.filter { $0.url.pathExtension.lowercased() == "jar" }
            guard !jars.isEmpty else { continue }
            let hasJam = group.contains { $0.url.pathExtension.lowercased() == "jam" }
            if hasJam {
                let first = jars[0]
                let name = first.fromFolder ? first.url.deletingLastPathComponent().lastPathComponent
                                            : first.url.deletingPathExtension().lastPathComponent
                let dest = dir.appendingPathComponent(clean(name), isDirectory: true)
                try? fm.removeItem(at: dest)
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                for it in group { copy(it.url, to: dest.appendingPathComponent(it.url.lastPathComponent), &result) }
                result.games += 1
            } else {
                for jar in jars {
                    let base = jar.url.deletingPathExtension().lastPathComponent
                    for it in group where it.url.deletingPathExtension().lastPathComponent == base {
                        copy(it.url, to: dir.appendingPathComponent(it.url.lastPathComponent), &result)
                    }
                    result.games += 1
                }
            }
        }
        return result
    }

    private static func copy(_ src: URL, to dst: URL, _ r: inout Result) {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        if (try? fm.copyItem(at: src, to: dst)) != nil { r.files += 1 }
    }

    private static func clean(_ s: String) -> String {
        let t = s.map { "/:\\".contains($0) ? "_" : $0 }.map(String.init).joined()
        return t.isEmpty ? "game" : t
    }

    /// Removes a game's files, and with them its saves and states.
    static func delete(_ game: Game, gamesDirectory: URL) {
        let fm = FileManager.default
        let parent = game.jar.deletingLastPathComponent()
        if parent.standardizedFileURL.path != gamesDirectory.standardizedFileURL.path,
           parent.deletingLastPathComponent().standardizedFileURL.path == gamesDirectory.standardizedFileURL.path {
            try? fm.removeItem(at: parent)      // the game's own folder
        } else {
            let base = game.jar.deletingPathExtension().lastPathComponent
            for f in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            where f.deletingPathExtension().lastPathComponent == base && extensions.contains(f.pathExtension.lowercased()) {
                try? fm.removeItem(at: f)
            }
        }
        Launcher.shared.deleteSaves(slug: game.slug)
    }
}
