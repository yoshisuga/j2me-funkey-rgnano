import Foundation

/// Copies games into Documents/java: loose .jar files, or an i-appli's .jar/.jam/.sp
/// (picked together, or as a folder) into a folder of its own.
enum Importer {
    static let extensions: Set<String> = ["jar", "jam", "sp", "net"]

    struct Result {
        var games = 0
        var files = 0
        var incomplete: [String] = []     // jars that came across but cannot start (an i-appli without its .jam)
        var message: String {
            var m = games == 0 && !incomplete.isEmpty ? "" : text
            if !incomplete.isEmpty {
                m += (m.isEmpty ? "" : "\n\n") + incomplete.joined(separator: ", ") + (incomplete.count == 1 ? " is" : " are")
                    + " not listed: it needs its .jam file (an i-appli). Import the .jam (and .sp) together with the .jar, or as a folder."
            }
            return m
        }
        private var text: String {
            if games == 0 { return "No .jar files found. Pick a .jar (an i-appli: with its .jam and .sp), a .zip or a folder holding them." }
            return "Imported \(games) game\(games == 1 ? "" : "s")."
        }
    }

    private struct Item { let url: URL; let fromFolder: Bool }

    static func importItems(_ urls: [URL], into dir: URL) -> Result {
        let fm = FileManager.default
        var items: [Item] = []
        var opened: [URL] = []
        let scratch = fm.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        defer {
            opened.forEach { $0.stopAccessingSecurityScopedResource() }
            try? fm.removeItem(at: scratch)
        }

        for url in urls {
            if url.startAccessingSecurityScopedResource() { opened.append(url) }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDir {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL {
                    if extensions.contains(f.pathExtension.lowercased()) { items.append(Item(url: f, fromFolder: true)) }
                }
            } else if url.pathExtension.lowercased() == "zip" {
                // a zip holding the game: unpacked to a folder of its own (named like the zip), then handled as a folder
                for f in unzip(url, into: scratch) { items.append(Item(url: f, fromFolder: true)) }
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
                Library.markAdded(slug: Game.slug(forJar: dest.appendingPathComponent(first.url.lastPathComponent)))
                result.games += 1
            } else {
                for jar in jars {
                    let base = jar.url.deletingPathExtension().lastPathComponent
                    for it in group where it.url.deletingPathExtension().lastPathComponent == base {
                        copy(it.url, to: dir.appendingPathComponent(it.url.lastPathComponent), &result)
                    }
                    let dest = dir.appendingPathComponent(jar.url.lastPathComponent)
                    if Game.load(jar: dest) == nil {
                        // cannot start: take the copy back out instead of leaving an invisible file
                        try? fm.removeItem(at: dest)
                        result.incomplete.append(jar.url.deletingPathExtension().lastPathComponent)
                        continue
                    }
                    Library.markAdded(slug: Game.slug(forJar: dest))
                    result.games += 1
                }
            }
        }
        return result
    }

    /// Writes the game files (.jar .jam .sp) of a zip below `scratch/<zip name>/`, keeping their folders.
    private static func unzip(_ zip: URL, into scratch: URL) -> [URL] {
        guard let data = try? Data(contentsOf: zip, options: .mappedIfSafe) else { return [] }
        let fm = FileManager.default
        let root = scratch.appendingPathComponent(clean(zip.deletingPathExtension().lastPathComponent), isDirectory: true)
        var out: [URL] = []
        for name in JarInfo.entryNames(data) where !name.hasSuffix("/") {
            let parts = name.split(separator: "/").map(String.init)
            guard !parts.contains(".."), !parts.contains("__MACOSX"), !(parts.last ?? "").hasPrefix("."),
                  extensions.contains((name as NSString).pathExtension.lowercased()),
                  let bytes = JarInfo.readEntry(data, named: name) else { continue }
            let dest = parts.reduce(root) { $0.appendingPathComponent($1) }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? bytes.write(to: dest)) != nil { out.append(dest) }
        }
        return out
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
        Library.forget(slug: game.slug)
        Launcher.shared.deleteSaves(slug: game.slug)
    }
}
