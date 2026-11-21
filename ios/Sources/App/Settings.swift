import Foundation

/// One option. Every option is a choice from a short list (a switch is On/Off),
/// kept globally and optionally overridden per game.
struct SettingDef {
    let key: String
    let title: String
    let section: String
    let choices: [(value: String, label: String)]
    let def: String
    let perGame: Bool
    var env: String? = nil          // runtime environment variable it sets
    var cfgKey: String? = nil       // the runtime menu's name for it (its saved choice is dropped when this changes)
    var onlyWhenOn = false          // switch: the variable is set only for "1"
}

enum Settings {
    private static let onOff = [("1", "On"), ("0", "Off")]

    static let defs: [SettingDef] = [
        // Display
        SettingDef(key: "scaleMode", title: "Scaling", section: "Display",
                   choices: [("auto", "Automatic"), ("fit", "Fit"), ("fill", "Fill"), ("crop", "Crop"), ("center", "Centered"), ("integer", "Whole pixels")],
                   def: "auto", perGame: true, env: "PHONEME_SCALE_MODE", cfgKey: "DISPLAY_MODE"),
        SettingDef(key: "filter", title: "Smoothing", section: "Display",
                   choices: [("", "Runtime default"), ("sharp", "Sharp"), ("smooth", "Smooth"), ("pixel", "Pixel"), ("scale2x", "Scale2x")],
                   def: "", perGame: true, env: "PHONEME_SCALE_FILTER", cfgKey: "FILTER"),
        SettingDef(key: "fps", title: "Frame rate limit", section: "Display",
                   choices: [("", "Runtime default"), ("off", "No limit"), ("20", "20"), ("25", "25"), ("30", "30"), ("50", "50"), ("60", "60")],
                   def: "", perGame: true, env: "PHONEME_FPS_LIMIT", cfgKey: "FPS_LIMIT"),
        SettingDef(key: "showFPS", title: "Show FPS counter", section: "Display", choices: onOff, def: "0", perGame: true,
                   env: "PHONEME_SHOW_FPS", onlyWhenOn: true),
        // Screen (plain jars only)
        SettingDef(key: "lcd", title: "Screen size", section: "Screen",
                   choices: [("128x128", "128 x 128"), ("128x160", "128 x 160"), ("176x208", "176 x 208"), ("176x220", "176 x 220"),
                             ("240x240", "240 x 240"), ("240x320", "240 x 320"), ("240x400", "240 x 400"), ("320x240", "320 x 240"),
                             ("320x480", "320 x 480"), ("360x640", "360 x 640")],
                   def: "240x320", perGame: true),
        // Controls
        SettingDef(key: "softKeys", title: "Soft key codes", section: "Controls",
                   choices: [("standard", "Standard (-6 / -7)"), ("motorola", "Motorola (-21 / -22)"), ("moto-old", "Older Motorola (21 / 22)"), ("siemens", "Siemens (-1 / -4)")],
                   def: "standard", perGame: true),
        SettingDef(key: "haptics", title: "Haptic feedback", section: "Controls", choices: onOff, def: "1", perGame: false),
        SettingDef(key: "padOpacity", title: "Pad opacity", section: "Controls",
                   choices: [("100", "100%"), ("80", "80%"), ("60", "60%"), ("40", "40%")], def: "100", perGame: false),
        // Sound
        SettingDef(key: "volume", title: "Volume", section: "Sound",
                   choices: [("100", "100%"), ("80", "80%"), ("60", "60%"), ("40", "40%"), ("20", "20%"), ("0", "Muted")],
                   def: "100", perGame: true, env: "PHONEME_SOUND_VOLUME", cfgKey: "VOLUME"),
        SettingDef(key: "synth", title: "MIDI synthesizer", section: "Sound",
                   choices: [("", "Runtime default"), ("hybrid", "Hybrid"), ("wavetable", "Wavetable"), ("fm", "FM")],
                   def: "", perGame: true, env: "PHONEME_SYNTH", cfgKey: "SYNTH"),
        SettingDef(key: "quality", title: "Audio quality", section: "Sound",
                   choices: [("", "Runtime default"), ("low", "Low (faster)"), ("high", "High")],
                   def: "", perGame: true, env: "PHONEME_AUDIO_QUALITY"),
        SettingDef(key: "audioBuffer", title: "Audio buffer", section: "Sound",
                   choices: [("", "Runtime default"), ("512", "Small (low latency)"), ("1024", "Normal"), ("2048", "Large"), ("4096", "Largest (safest)")],
                   def: "", perGame: true, env: "PHONEME_AUDIO_BUFFER"),
        SettingDef(key: "mono", title: "Mix to mono", section: "Sound", choices: onOff, def: "0", perGame: true,
                   env: "PHONEME_AUDIO_SUM", onlyWhenOn: true),
        // System
        SettingDef(key: "heap", title: "Java heap", section: "System",
                   choices: [("32", "32 MB"), ("48", "48 MB"), ("64", "64 MB"), ("96", "96 MB"), ("128", "128 MB")],
                   def: "64", perGame: true, env: "PHONEME_HEAP_MB"),
        SettingDef(key: "keepAwake", title: "Keep screen awake", section: "System", choices: onOff, def: "1", perGame: false),
        SettingDef(key: "autoSave", title: "Save state when leaving the app", section: "System", choices: onOff, def: "0", perGame: false),
    ]

    static let sectionOrder = ["Display", "Screen", "Controls", "Sound", "System"]

    static func def(_ key: String) -> SettingDef { defs.first { $0.key == key }! }

    private static let ud = UserDefaults.standard

    static func global(_ key: String) -> String { ud.string(forKey: "set.\(key)") ?? def(key).def }
    static func setGlobal(_ key: String, _ value: String?) {
        if let v = value { ud.set(v, forKey: "set.\(key)") } else { ud.removeObject(forKey: "set.\(key)") }
    }

    static func override(_ slug: String, _ key: String) -> String? {
        (ud.dictionary(forKey: "game.\(slug)") as? [String: String])?[key]
    }
    static func setOverride(_ slug: String, _ key: String, _ value: String?) {
        var d = (ud.dictionary(forKey: "game.\(slug)") as? [String: String]) ?? [:]
        d[key] = value
        ud.set(d, forKey: "game.\(slug)")
    }

    static func effective(_ slug: String?, _ key: String) -> String {
        if let s = slug, let o = override(s, key) { return o }
        return global(key)
    }

    static func label(_ key: String, _ value: String) -> String {
        def(key).choices.first { $0.value == value }?.label ?? value
    }

    static func resetGlobal() { defs.forEach { ud.removeObject(forKey: "set.\($0.key)") } }
    static func resetGame(_ slug: String) { ud.removeObject(forKey: "game.\(slug)") }
    static func deleteGame(_ slug: String) { resetGame(slug) }

    /// Soft key codes for the chosen style.
    static func softCodes(_ slug: String?) -> (Int, Int) {
        switch effective(slug, "softKeys") {
        case "motorola": return (-21, -22)
        case "moto-old": return (21, 22)
        case "siemens": return (-1, -4)
        default: return (-6, -7)
        }
    }

    /// Environment variables of the runtime for a game (app settings only).
    static func runtimeEnv(_ slug: String) -> [String: String] {
        var env: [String: String] = [:]
        for d in defs {
            guard let name = d.env else { continue }
            let v = effective(slug, d.key)
            if v.isEmpty || (d.onlyWhenOn && v != "1") { continue }
            env[name] = v
        }
        return env
    }

    static func screenSize(_ slug: String) -> (Int, Int) {
        let p = effective(slug, "lcd").split(separator: "x").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : (240, 320)
    }
}
