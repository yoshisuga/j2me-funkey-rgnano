import Foundation

/// How the games screen shows and orders its games (kept between launches).
enum Library {
    enum Layout: String { case grid, list }
    enum SortKey: String { case name, added }

    private static let ud = UserDefaults.standard

    static var layout: Layout {
        get { Layout(rawValue: ud.string(forKey: "lib.layout") ?? "") ?? .grid }
        set { ud.set(newValue.rawValue, forKey: "lib.layout") }
    }
    static var sortKey: SortKey {
        get { SortKey(rawValue: ud.string(forKey: "lib.sort") ?? "") ?? .name }
        set { ud.set(newValue.rawValue, forKey: "lib.sort") }
    }
    static var ascending: Bool {
        get { ud.object(forKey: "lib.asc") as? Bool ?? true }
        set { ud.set(newValue, forKey: "lib.asc") }
    }

    // MARK: date added

    private static func addedDates() -> [String: Double] { ud.dictionary(forKey: "lib.added") as? [String: Double] ?? [:] }

    /// When the game came to the app: noted at import; for files that arrived another way
    /// (file sharing) the first time the app saw them, from the file's own date.
    static func added(_ game: Game) -> Date {
        var d = addedDates()
        if let t = d[game.slug] { return Date(timeIntervalSince1970: t) }
        let date = (try? game.jar.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        d[game.slug] = date.timeIntervalSince1970
        ud.set(d, forKey: "lib.added")
        return date
    }

    static func markAdded(slug: String, date: Date = Date()) {
        var d = addedDates()
        d[slug] = date.timeIntervalSince1970
        ud.set(d, forKey: "lib.added")
    }

    static func forget(slug: String) {
        var d = addedDates()
        d[slug] = nil
        ud.set(d, forKey: "lib.added")
    }

    // MARK: order

    static func sorted(_ games: [Game]) -> [Game] {
        let dates = Dictionary(uniqueKeysWithValues: games.map { ($0.slug, added($0)) })
        let list = games.sorted { a, b in
            switch sortKey {
            case .name:
                let r = a.name.localizedStandardCompare(b.name)
                return r == .orderedSame ? a.slug < b.slug : r == .orderedAscending
            case .added:
                let da = dates[a.slug]!, db = dates[b.slug]!
                return da == db ? a.name.localizedStandardCompare(b.name) == .orderedAscending : da < db
            }
        }
        return ascending ? list : list.reversed()
    }

    static func orderTitles(for key: SortKey) -> (asc: String, desc: String) {
        key == .name ? ("A to Z", "Z to A") : ("Oldest First", "Newest First")
    }
}
