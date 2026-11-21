import Foundation

/// Phone keys the on-screen pad (and the runtime's PHONEME_PC_KEYS) use.
/// SDL key symbols are VIRTUAL_SYM + index, as in launchers/web/index.html.
enum PadAction: Int, CaseIterable {
    case up, down, left, right, fire, soft1, soft2
    case k1, k2, k3, k4, k5, k6, k7, k8, k9, k0, star, pound
    case menu                       // opens the runtime menu (display, sound, keys)

    static let virtualSym = 1400
    var sym: Int { PadAction.virtualSym + rawValue }

    /// Phone key code; the soft keys follow the handset style chosen in the settings.
    func phoneCode(soft: (Int, Int)) -> Int {
        switch self {
        case .soft1: return soft.0
        case .soft2: return soft.1
        default: return phoneCode
        }
    }

    var phoneCode: Int {
        switch self {
        case .up: return -1
        case .down: return -2
        case .left: return -3
        case .right: return -4
        case .fire: return -5
        case .soft1: return -6
        case .soft2: return -7
        case .k1: return 49
        case .k2: return 50
        case .k3: return 51
        case .k4: return 52
        case .k5: return 53
        case .k6: return 54
        case .k7: return 55
        case .k8: return 56
        case .k9: return 57
        case .k0: return 48
        case .star: return 42
        case .pound: return 35
        case .menu: return 1000
        }
    }
}

/// Prepares the sandbox the VM sees as "/" (runtime files, the game, saves)
/// and starts it; this is the iOS counterpart of launchers/<target>/.
final class Launcher {
    static let shared = Launcher()

    let root: URL
    private var cStrings: [UnsafeMutablePointer<CChar>?] = []   // kept alive for the VM

    private init() {
        let support = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        root = support.appendingPathComponent("j2me", isDirectory: true)
    }

    /// Documents/java: where the user drops .jar files (an i-appli: with its .jam and .sp) (Files app / Finder file sharing).
    var gamesDirectory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("java", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func installRuntimeFiles() throws {
        let fm = FileManager.default
        let marker = root.appendingPathComponent("midp/.installed")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        if let m = try? String(contentsOf: marker), m == build { return }
        try? fm.removeItem(at: root.appendingPathComponent("midp"))
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard let src = Bundle.main.url(forResource: "midp", withExtension: nil) else {
            throw NSError(domain: "j2me", code: 1, userInfo: [NSLocalizedDescriptionKey: "runtime files missing from the app"])
        }
        try fm.copyItem(at: src, to: root.appendingPathComponent("midp"))
        try build.write(to: marker, atomically: true, encoding: .utf8)
    }

    private(set) var currentSlug = ""
    var stateURL: URL { root.appendingPathComponent("save/\(currentSlug).state") }
    private var rmsSaveURL: URL { root.appendingPathComponent("save/\(currentSlug).rms") }
    var hasState: Bool { FileManager.default.fileExists(atPath: stateURL.path) }

    /// Called after a successful host_save_state: the game's record stores belong to the state.
    func saveRecordStores() {
        let fm = FileManager.default
        let src = root.appendingPathComponent("rms/\(currentSlug)")
        try? fm.removeItem(at: rmsSaveURL)
        try? fm.copyItem(at: src, to: rmsSaveURL)
    }

    // MARK: the runtime menu's choices (cfg/<slug>.cfg, as the web launcher reads them)

    private func cfgURL(_ slug: String) -> URL { root.appendingPathComponent("cfg/\(slug).cfg") }

    private func readRuntimeChoices(_ slug: String) -> [String: String] {
        guard let text = try? String(contentsOf: cfgURL(slug), encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let i = line.firstIndex(of: "=") else { continue }
            out[line[..<i].trimmingCharacters(in: .whitespaces)] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    private func applyRuntimeChoices(slug: String, to env: inout [String: String]) {
        let g = readRuntimeChoices(slug)
        if let v = g["DISPLAY_MODE"] { env["PHONEME_SCALE_MODE"] = v }
        if let v = g["FILTER"] { env["PHONEME_SCALE_FILTER"] = v }
        if let v = g["FPS_LIMIT"] { env["PHONEME_FPS_LIMIT"] = v }
        if let v = g["VOLUME"] { env["PHONEME_SOUND_VOLUME"] = v }
        if let v = g["SYNTH"] { env["PHONEME_SYNTH"] = v }
        if let z = g["SCALE"], z.hasPrefix("zoom-"), let n = Int(z.dropFirst(5)) {   // zoom-150 = 150%, zoom-1875 = 187.5%
            env["PHONEME_SCALE_RATIO"] = String(z.dropFirst(5).count <= 3 ? n * 10 : n)
        }
        if let x = g["PAN_X"] { env["PHONEME_PAN"] = "\(x),\(g["PAN_Y"] ?? "0")" }
        if let v = g["VIEW"] {
            if v == "full" { env["PHONEME_SOURCE_SIZE"] = "full" }
            else if v.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil {
                env["PHONEME_SOURCE_SIZE"] = v; env["PHONEME_LCD_SIZE"] = v
            }
        }
    }

    /// Drops one saved runtime-menu choice (the settings screen changed the same thing).
    func removeRuntimeChoice(slug: String, key: String) {
        guard let text = try? String(contentsOf: cfgURL(slug), encoding: .utf8) else { return }
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            guard let i = line.firstIndex(of: "=") else { return true }
            return line[..<i].trimmingCharacters(in: .whitespaces) != key
        }
        try? kept.joined(separator: "\n").write(to: cfgURL(slug), atomically: true, encoding: .utf8)
    }

    /// True when the game ended because "Restart" was picked in its runtime menu.
    var restartRequested: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("tmp/restart-request").path)
    }

    /// Record stores, saved states and the runtime menu's choices of a game.
    func deleteSaves(slug: String) {
        let fm = FileManager.default
        Settings.deleteGame(slug)
        for p in ["rms/\(slug)", "save/\(slug).state", "save/\(slug).rms", "cfg/\(slug).cfg"] {
            try? fm.removeItem(at: root.appendingPathComponent(p))
        }
    }

    func start(game: Game, screenPixels: CGSize, restore: Bool = false) throws {
        let fm = FileManager.default
        try installRuntimeFiles()
        let slug = game.slug
        let lcd = game.lcd

        currentSlug = slug
        if restore {
            guard hasState else { throw NSError(domain: "j2me", code: 4, userInfo: [NSLocalizedDescriptionKey: "no saved state"]) }
            let rms = root.appendingPathComponent("rms/\(slug)")
            try? fm.removeItem(at: rms)
            if fm.fileExists(atPath: rmsSaveURL.path) { try? fm.copyItem(at: rmsSaveURL, to: rms) }
        }
        for d in ["game", "rms/\(slug)", "cfg", "tmp", "save"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let gameJar = root.appendingPathComponent("game/game.jar")
        try? fm.removeItem(at: gameJar)
        try fm.copyItem(at: game.jar, to: gameJar)
        try? fm.removeItem(at: root.appendingPathComponent("tmp/restart-request"))

        var args: [String]
        if let ia = game.iappli {
            // the scratchpad lives with the saves; the .sp that came with the game only seeds an empty one
            let sp = root.appendingPathComponent("rms/\(slug)/game.sp")
            let kept = (try? fm.attributesOfItem(atPath: sp.path)[.size] as? Int) ?? 0
            if !restore && kept == 0 {
                if let src = ia.sp { try? fm.removeItem(at: sp); try fm.copyItem(at: src, to: sp) }
                else if !fm.fileExists(atPath: sp.path) { fm.createFile(atPath: sp.path, contents: Data()) }
            }
            let hex = ia.jam.map { String(format: "%02x", $0) }.joined()
            args = ["-UseVerifier", "=MaxMethodToCompile3000",
                    "-Ddoja.app.class=\(ia.appClass)", "-Ddoja.app.param=\(ia.appParam)", "-Ddoja.app.ver=\(ia.appVer)",
                    "-Dmicroedition.encoding=SJIS", "-Ddoja.scratchpad.path=/rms/\(slug)/game.sp"]
            if !ia.platform.isEmpty { args.append("-Dmicroedition.platform=\(ia.platform)") }
            args += ["-Ddoja.spsize=\(ia.spSize)", "-Ddoja.jam.hex=\(hex)", "-Ddoja.pictures=",
                     "-classpathext", "/game/game.jar:/midp/lib/doja-support.jar",
                     "internal", "com.funkey.doja.DoJaMIDlet"]
        } else {
            // getAppProperty() reads a .jad next to the jar, made from the manifest
            try (game.manifest ?? "").write(to: root.appendingPathComponent("game/game.jad"), atomically: true, encoding: .utf8)
            args = ["-UseVerifier", "-classpathext", "/game/game.jar", "internal", game.midletClass ?? ""]
        }

        host_set_root(root.path)

        let soft = Settings.softCodes(slug)
        let keys = PadAction.allCases.map { "\($0.sym)=\($0.phoneCode(soft: soft))" }.joined(separator: ";")
        var env: [String: String] = [
            "MIDP_HOME": "/midp",
            "PHONEME_RMS_HOME": "/rms/\(slug)",
            "PHONEME_HEAP_MB": "64",
            "PHONEME_LCD_SIZE": "\(lcd.0)x\(lcd.1)",
            "PHONEME_ENABLE_AUDIO": "1",
            "PHONEME_RESTART_FLAG": "/tmp/restart-request",
            "PHONEME_DEBUG_CONFIG": "/cfg/debug.cfg",
            "PHONEME_CONFIG_PATH": "/cfg/\(slug).cfg",
            "PHONEME_WINDOW_SIZE": "\(Int(screenPixels.width))x\(Int(screenPixels.height))",
            "PHONEME_JIT": "0",
            "PHONEME_PC_KEYS": keys,
        ]
        if game.isIAppli { env["PHONEME_SOURCE_SIZE"] = "\(lcd.0)x\(lcd.1)" }
        env.merge(Settings.runtimeEnv(slug)) { $1 }
        applyRuntimeChoices(slug: slug, to: &env)      // what the runtime menu saved wins
        // PHONEME_* variables of the app's own environment (debugging: simctl SIMCTL_CHILD_PHONEME_KEY_DEBUG=1)
        for (k, v) in ProcessInfo.processInfo.environment where k.hasPrefix("PHONEME_") { env[k] = v }
        let env2 = env.map { "\($0.key)=\($0.value)" }.sorted()
        let a = makeArray(args), e = makeArray(env2)
        let statePath: UnsafeMutablePointer<CChar>? = restore ? strdup(stateURL.path) : nil
        if host_start(a, e, statePath) != 0 {
            throw NSError(domain: "j2me", code: 3, userInfo: [NSLocalizedDescriptionKey: "cannot start the VM thread"])
        }
    }

    private func makeArray(_ strings: [String]) -> UnsafeMutablePointer<UnsafePointer<CChar>?> {
        // leaked on purpose: the VM thread reads them until it ends
        let arr = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (i, s) in strings.enumerated() { arr[i] = UnsafePointer(strdup(s)) }
        arr[strings.count] = nil
        return arr
    }
}
