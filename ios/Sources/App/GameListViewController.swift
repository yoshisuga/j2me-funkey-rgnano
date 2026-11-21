import UIKit

/// Lists the jars in Documents/java (plus the bundled demo) and starts one.
final class GameListViewController: UITableViewController, UIDocumentPickerDelegate {
    private var games: [Game] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "J2ME"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in
            let nav = UINavigationController(rootViewController: SettingsViewController(slug: nil))
            nav.modalPresentationStyle = .pageSheet
            self?.present(nav, animated: true)
        })
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.pickFiles() }),
            UIBarButtonItem(systemItem: .refresh, primaryAction: UIAction { [weak self] _ in self?.reload() }),
        ]
        reload()
    }

    // MARK: import

    private func pickFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder])
        picker.allowsMultipleSelection = true
        picker.delegate = self
        picker.shouldShowFileExtensions = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importURLs(urls)
    }

    /// Also used for files opened from Files / AirDrop / the share sheet.
    func importURLs(_ urls: [URL]) {
        let result = Importer.importItems(urls, into: Launcher.shared.gamesDirectory)
        reload()
        let a = UIAlertController(title: result.games > 0 ? "Imported" : "Nothing imported", message: result.message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        (presentedViewController ?? self).present(a, animated: true)
    }

    override func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let g = games[ip.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Game Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in
                let nav = UINavigationController(rootViewController: SettingsViewController(slug: g.slug, name: g.name, isIAppli: g.isIAppli))
                nav.modalPresentationStyle = .pageSheet
                self?.present(nav, animated: true)
            }])
        }
    }

    // MARK: delete

    override func tableView(_ tv: UITableView, trailingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? {
        let g = games[ip.row]
        if g.jar.path.hasPrefix(Bundle.main.bundlePath) { return nil }          // the bundled demo
        let del = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            let a = UIAlertController(title: "Delete \(g.name)?", message: "The game's files and its saves are removed.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                Importer.delete(g, gamesDirectory: Launcher.shared.gamesDirectory)
                self?.reload()
                done(true)
            })
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
            self?.present(a, animated: true)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }

    private var autostarted = false
    private var importedAtLaunch = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // testing aid: `-import <path>` imports a file or folder at launch
        if let i = CommandLine.arguments.firstIndex(of: "-import"), i + 1 < CommandLine.arguments.count, !importedAtLaunch {
            importedAtLaunch = true
            importURLs([URL(fileURLWithPath: CommandLine.arguments[i + 1])])
        }
        // testing aid: `simctl launch <device> org.j2me.funkey -autostart [n]`
        if !autostarted, let i = CommandLine.arguments.firstIndex(of: "-autostart"), !games.isEmpty {
            autostarted = true
            let n = i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) ?? 0 : 0
            present(GameViewController(game: games[min(n, games.count - 1)]), animated: false)
        }
    }

    private func reload() {
        var list: [Game] = []
        if let demo = Bundle.main.url(forResource: "MotherLoad", withExtension: "jar"), let g = Game.load(jar: demo) { list.append(g) }
        // jars in Documents/java, also one folder deep (a game with its .jam and .sp in a folder)
        let fm = FileManager.default
        let dir = Launcher.shared.gamesDirectory
        var jars: [URL] = []
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            if item.pathExtension.lowercased() == "jar" { jars.append(item) }
            else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                jars += ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "jar" }
            }
        }
        list += jars.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { Game.load(jar: $0) }
        games = list
        tableView.reloadData()
        tableView.backgroundView = games.count <= 1 ? hint : nil
    }

    private lazy var hint: UILabel = {
        let l = UILabel()
        l.text = "Tap + to import games\n(.jar, or an i-appli's .jar + .jam + .sp)"
        l.numberOfLines = 0
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.font = .preferredFont(forTextStyle: .footnote)
        return l
    }()

    override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { games.count }

    override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip)
        var cfg = c.defaultContentConfiguration()
        let g = games[ip.row]
        cfg.text = g.name
        cfg.secondaryText = g.jar.lastPathComponent + (g.isIAppli ? "  ·  i-appli" : "")
        cfg.image = g.loadIcon() ?? UIImage(systemName: "gamecontroller.fill")
        cfg.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        cfg.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
        cfg.imageProperties.cornerRadius = 9
        cfg.imageProperties.tintColor = .tertiaryLabel
        cfg.imageToTextPadding = 14
        c.contentConfiguration = cfg
        return c
    }

    override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
        "Tap + to import games from Files. An i-appli needs its .jam (and .sp): import them together or as a folder. Swipe a game to delete it."
    }

    override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        if host_running() != 0 {
            let a = UIAlertController(title: "A game is still closing", message: "Try again in a moment.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        present(GameViewController(game: games[ip.row]), animated: true)
    }
}
