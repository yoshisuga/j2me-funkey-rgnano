import UIKit

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

// MARK: icon

extension Game {
    private static let iconCache = NSCache<NSString, UIImage>()

    /// The game's icon: a MIDlet's MIDlet-Icon (or the icon field of MIDlet-1); otherwise an
    /// icon image inside the jar (i-appli games carry files such as icon48.gif).
    func loadIcon() -> UIImage? {
        let key = jar.path as NSString
        if let hit = Game.iconCache.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: jar, options: .mappedIfSafe) else { return nil }
        let names = JarInfo.entryNames(data)
        func entry(_ name: String) -> String? {
            let n = name.hasPrefix("/") ? String(name.dropFirst()) : name
            return names.first { $0 == n } ?? names.first { $0.caseInsensitiveCompare(n) == .orderedSame }
        }
        var candidate: String?
        if let mf = manifest {
            var props: [String: String] = [:]
            for line in mf.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
                guard let i = line.firstIndex(of: ":") else { continue }
                props[String(line[..<i])] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            let fromM1 = props["MIDlet-1"].flatMap { v -> String? in
                let p = v.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                return p.count > 1 && !p[1].isEmpty ? p[1] : nil
            }
            candidate = [props["MIDlet-Icon"], fromM1].compactMap { $0 }.compactMap(entry).first
        }
        if candidate == nil {
            let images = names.filter { ["png", "gif", "jpg", "jpeg"].contains(($0 as NSString).pathExtension.lowercased()) }
            let icons = images.filter { ($0 as NSString).lastPathComponent.lowercased().contains("icon") }
            // prefer a small one (icon48 over icon96), then plain "icon"
            candidate = icons.first { $0.lowercased().contains("48") } ?? icons.first { $0.lowercased().contains("32") }
                ?? icons.first { ($0 as NSString).deletingPathExtension.lowercased().hasSuffix("icon") } ?? icons.first
        }
        guard let c = candidate, let bytes = JarInfo.readEntry(data, named: c), let img = UIImage(data: bytes) else { return nil }
        let out = Game.crisp(img, side: 96)
        Game.iconCache.setObject(out, forKey: key)
        return out
    }

    /// Pixel-art icons scaled up without blurring.
    private static func crisp(_ img: UIImage, side: CGFloat) -> UIImage {
        let size = img.size
        guard size.width > 0, size.height > 0 else { return img }
        let k = min(side / size.width, side / size.height)
        let target = CGSize(width: (size.width * (k >= 1 ? CGFloat(Int(k)) : k)).rounded(), height: (size.height * (k >= 1 ? CGFloat(Int(k)) : k)).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: target, format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = k >= 1 ? .none : .high
            img.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
