import UIKit

/// A game tile of the grid: its icon on a rounded square, the name below.
final class GameGridCell: UICollectionViewCell {
    private let back = UIView()
    private let icon = UIImageView()
    private let badge = UILabel()
    private let name = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        back.backgroundColor = .secondarySystemGroupedBackground
        back.layer.cornerRadius = 20
        back.layer.cornerCurve = .continuous
        back.layer.borderWidth = 1
        back.layer.borderColor = UIColor.separator.cgColor
        icon.contentMode = .scaleAspectFit
        icon.layer.magnificationFilter = .nearest
        icon.layer.cornerRadius = 8
        icon.layer.masksToBounds = true
        badge.text = " i-appli "
        badge.font = .systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        badge.layer.cornerRadius = 4
        badge.layer.masksToBounds = true
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textAlignment = .center
        name.numberOfLines = 2
        name.textColor = .label
        [back, name].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        [icon, badge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; back.addSubview($0) }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: contentView.topAnchor),
            back.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            back.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            back.heightAnchor.constraint(equalTo: back.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: back.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            icon.widthAnchor.constraint(equalTo: back.widthAnchor, multiplier: 0.66),
            icon.heightAnchor.constraint(equalTo: back.heightAnchor, multiplier: 0.66),
            badge.trailingAnchor.constraint(equalTo: back.trailingAnchor, constant: -6),
            badge.topAnchor.constraint(equalTo: back.topAnchor, constant: 6),
            name.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 6),
            name.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            name.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            name.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ g: Game) {
        if let img = g.loadIcon() {
            icon.image = img
            icon.tintColor = nil
        } else {
            icon.image = UIImage(systemName: "gamecontroller.fill")
            icon.tintColor = .tertiaryLabel
        }
        badge.isHidden = !g.isIAppli
        name.text = g.name
    }

    override var isHighlighted: Bool { didSet { contentView.alpha = isHighlighted ? 0.55 : 1 } }
}

/// The games in Documents/java (plus the bundled demo): a grid or a list, sorted, and starts one.
final class GameListViewController: UICollectionViewController, UIDocumentPickerDelegate {
    private var games: [Game] = []

    init() { super.init(collectionViewLayout: UICollectionViewLayout()) }
    required init?(coder: NSCoder) { fatalError() }

    private var gridCell: UICollectionView.CellRegistration<GameGridCell, Game>!
    private var listCell: UICollectionView.CellRegistration<UICollectionViewListCell, Game>!

    private func makeRegistrations() {
        gridCell = UICollectionView.CellRegistration<GameGridCell, Game> { cell, _, g in cell.configure(g) }
        listCell = UICollectionView.CellRegistration<UICollectionViewListCell, Game> { cell, _, g in
        var cfg = cell.defaultContentConfiguration()
        cfg.text = g.name
        cfg.secondaryText = g.jar.lastPathComponent + (g.isIAppli ? "  ·  i-appli" : "")
        cfg.image = g.loadIcon() ?? UIImage(systemName: "gamecontroller.fill")
        cfg.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        cfg.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
        cfg.imageProperties.cornerRadius = 9
        cfg.imageProperties.tintColor = .tertiaryLabel
        cfg.imageToTextPadding = 14
            cell.contentConfiguration = cfg
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "J2ME"
        makeRegistrations()
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in self?.reload(); refresh?.endRefreshing() }, for: .valueChanged)
        collectionView.refreshControl = refresh
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in
            self?.presentSettings(slug: nil, name: nil, isIAppli: false)
        })
        updateBarItems()
        reload()
    }

    // MARK: layout and sorting

    private func makeLayout() -> UICollectionViewLayout {
        switch Library.layout {
        case .list:
            var cfg = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            cfg.backgroundColor = .systemGroupedBackground
            cfg.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                guard let self = self, self.games.indices.contains(ip.item) else { return nil }
                let g = self.games[ip.item]
                if g.jar.path.hasPrefix(Bundle.main.bundlePath) { return nil }       // the bundled demo
                let del = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
                    self.confirmDelete(g) { done($0) }
                }
                return UISwipeActionsConfiguration(actions: [del])
            }
            return UICollectionViewCompositionalLayout.list(using: cfg)
        case .grid:
            return UICollectionViewCompositionalLayout { _, env in
                let w = env.container.effectiveContentSize.width
                let cols = max(2, Int((w - 24) / 120))
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1 / CGFloat(cols)), heightDimension: .estimated(150)))
                item.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(150)), subitem: item, count: cols)
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 24, trailing: 12)
                return section
            }
        }
    }

    private func updateBarItems() {
        let titles = Library.orderTitles(for: Library.sortKey)
        let sort = UIMenu(children: [
            UIMenu(title: "Sort By", options: .displayInline, children: [
                UIAction(title: "Name", image: UIImage(systemName: "textformat"), state: Library.sortKey == .name ? .on : .off) { [weak self] _ in
                    Library.sortKey = .name; self?.resort()
                },
                UIAction(title: "Date Added", image: UIImage(systemName: "calendar"), state: Library.sortKey == .added ? .on : .off) { [weak self] _ in
                    Library.sortKey = .added; self?.resort()
                },
            ]),
            UIMenu(title: "Order", options: .displayInline, children: [
                UIAction(title: titles.asc, image: UIImage(systemName: "arrow.up"), state: Library.ascending ? .on : .off) { [weak self] _ in
                    Library.ascending = true; self?.resort()
                },
                UIAction(title: titles.desc, image: UIImage(systemName: "arrow.down"), state: Library.ascending ? .off : .on) { [weak self] _ in
                    Library.ascending = false; self?.resort()
                },
            ]),
        ])
        let sortItem = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), menu: sort)
        let layoutItem = UIBarButtonItem(
            image: UIImage(systemName: Library.layout == .grid ? "list.bullet" : "square.grid.2x2"),
            primaryAction: UIAction { [weak self] _ in
                Library.layout = Library.layout == .grid ? .list : .grid
                self?.relayout()
            })
        layoutItem.accessibilityLabel = Library.layout == .grid ? "Show as list" : "Show as grid"
        let plus = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.pickFiles() })
        navigationItem.rightBarButtonItems = [plus, sortItem, layoutItem]
    }

    private func resort() {
        games = Library.sorted(games)
        updateBarItems()
        collectionView.reloadData()
    }

    private func relayout() {
        updateBarItems()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.reloadData()
    }

    // MARK: data

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
        list += jars.compactMap { Game.load(jar: $0) }
        games = Library.sorted(list)
        collectionView.reloadData()
        collectionView.backgroundView = games.count <= 1 ? hint : nil
    }

    private lazy var hint: UILabel = {
        let l = UILabel()
        l.text = "Tap + to import games from Files.\nAn i-appli needs its .jam (and .sp):\nimport them together or as a folder."
        l.numberOfLines = 0
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.font = .preferredFont(forTextStyle: .footnote)
        return l
    }()

    override func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { games.count }

    override func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let g = games[ip.item]
        switch Library.layout {
        case .grid: return cv.dequeueConfiguredReusableCell(using: gridCell, for: ip, item: g)
        case .list: return cv.dequeueConfiguredReusableCell(using: listCell, for: ip, item: g)
        }
    }

    override func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: true)
        if host_running() != 0 {
            let a = UIAlertController(title: "A game is still closing", message: "Try again in a moment.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        present(GameViewController(game: games[ip.item]), animated: true)
    }

    // MARK: context menu, settings, delete

    private func presentSettings(slug: String?, name: String?, isIAppli: Bool) {
        let nav = UINavigationController(rootViewController: SettingsViewController(slug: slug, name: name, isIAppli: isIAppli))
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    override func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let g = games[ip.item]
        let demo = g.jar.path.hasPrefix(Bundle.main.bundlePath)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions = [UIAction(title: "Game Settings", image: UIImage(systemName: "gearshape")) { _ in
                self?.presentSettings(slug: g.slug, name: g.name, isIAppli: g.isIAppli)
            }]
            if !demo {
                actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.confirmDelete(g) { _ in }
                })
            }
            return UIMenu(children: actions)
        }
    }

    private func confirmDelete(_ g: Game, done: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: "Delete \(g.name)?", message: "The game's files and its saves are removed.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Importer.delete(g, gamesDirectory: Launcher.shared.gamesDirectory)
            self?.reload()
            done(true)
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
        present(a, animated: true)
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
}
