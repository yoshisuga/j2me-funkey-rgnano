import Foundation

/// A game on disk: a MIDP jar, or an i-appli (DoJa) jar with its .jam and optional .sp scratchpad.
struct Game {
    struct IAppli {
        var jam: Data
        var appClass: String
        var appParam: String
        var appVer: String
        var spSize: String
        var area: (Int, Int)
        var platform: String     // handset model the game was made for ("" = default)
        var sp: URL?
    }

    let jar: URL
    var name: String
    var midletClass: String?          // MIDP
    var manifest: String?             // MIDP: becomes the .jad
    var iappli: IAppli?

    /// Screen size the game draws: 240x320 for MIDP, the .jam DrawArea for an i-appli.
    var lcd: (Int, Int) { iappli?.area ?? Settings.screenSize(slug) }
    var isIAppli: Bool { iappli != nil }

    var slug: String {
        jar.deletingPathExtension().lastPathComponent.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    /// Reads a jar and what belongs to it: a .jam (same name, or the only one in the folder)
    /// and a .sp (same name as the jar or the .jam).
    static func load(jar: URL) -> Game? {
        let dir = jar.deletingLastPathComponent()
        let base = jar.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        let siblings = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        func sibling(_ ext: String) -> URL? {
            if let same = siblings.first(where: { $0.pathExtension.lowercased() == ext
                && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(base) == .orderedSame }) { return same }
            let all = siblings.filter { $0.pathExtension.lowercased() == ext }
            let jars = siblings.filter { $0.pathExtension.lowercased() == "jar" }
            return all.count == 1 && jars.count == 1 ? all[0] : nil     // alone in its folder
        }

        if let info = JarInfo(jarURL: jar), sibling("jam") == nil {
            return Game(jar: jar, name: info.name, midletClass: info.mainClass, manifest: info.manifest, iappli: nil)
        }
        guard let jamURL = sibling("jam"), let jam = try? Data(contentsOf: jamURL) else { return nil }
        let text = String(data: jam, encoding: .shiftJIS) ?? String(decoding: jam, as: UTF8.self)
        var v: [String: String] = [:]
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
            guard let i = line.firstIndex(of: "=") else { continue }
            v[line[..<i].trimmingCharacters(in: .whitespaces)] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        guard let cls = v["AppClass"], !cls.isEmpty else { return nil }
        func ascii(_ s: String?) -> String { (s ?? "").unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7f } ? (s ?? "") : "" }
        var area = (240, 240)
        if let da = v["DrawArea"] {
            let p = da.split(separator: "x").compactMap { Int($0) }
            if p.count == 2, p[0] > 0, p[1] > 0 { area = (p[0], p[1]) }
        }
        let platform = ascii(v["TargetDevice"]).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            .first { $0.count >= 2 && $0.count <= 16 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } } ?? ""
        let spURL = siblings.first { $0.pathExtension.lowercased() == "sp"
            && ["\(base)", jamURL.deletingPathExtension().lastPathComponent].contains($0.deletingPathExtension().lastPathComponent) }
        let ia = IAppli(jam: jam, appClass: cls, appParam: ascii(v["AppParam"]), appVer: ascii(v["AppVer"]),
                        spSize: ascii(v["SPsize"]), area: area, platform: platform, sp: spURL)
        return Game(jar: jar, name: v["AppName"].flatMap { $0.isEmpty ? nil : $0 } ?? base,
                    midletClass: nil, manifest: nil, iappli: ia)
    }
}
