import SwiftUI
import UIKit

/// The games screen: a SwiftUI grid or list of the games in the store, with UIKit bars around it.
final class GameListViewController: UIViewController, UIDocumentPickerDelegate {
    private let store = GameStore()
    /// Files that opened the app before this screen was visible.
    var pendingURLs: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GenJ2"
        view.backgroundColor = .systemGroupedBackground
        let root = GameListView(
            store: store,
            open: { [weak self] g in self?.start(g) },
            settings: { [weak self] g in self?.presentSettings(slug: g.slug, name: g.name, isIAppli: g.isIAppli) },
            delete: { [weak self] g in self?.confirmDelete(g) { _ in } })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in
            self?.presentSettings(slug: nil, name: nil, isIAppli: false)
        })
        updateBarItems()
        store.reload()
    }

    // MARK: sorting and layout

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
                Library.layout = Library.layout == .grid ? .list : .grid     // the SwiftUI screen follows the setting
                self?.updateBarItems()
            })
        layoutItem.accessibilityLabel = Library.layout == .grid ? "Show as list" : "Show as grid"
        let plus = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.pickFiles() })
        navigationItem.rightBarButtonItems = [plus, sortItem, layoutItem]
    }

    private func resort() {
        updateBarItems()
        store.resort()
    }

    // MARK: data

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); store.reload() }

    private var autostarted = false
    private var importedAtLaunch = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs = []
            importURLs(urls)
        }
        // testing aid: `-import <path>` imports a file or folder at launch
        if let i = CommandLine.arguments.firstIndex(of: "-import"), i + 1 < CommandLine.arguments.count, !importedAtLaunch {
            importedAtLaunch = true
            importURLs([URL(fileURLWithPath: CommandLine.arguments[i + 1])])
        }
        // testing aid: `simctl launch <device> com.ievo.genj2 -autostart [n]`
        if !autostarted, let i = CommandLine.arguments.firstIndex(of: "-autostart") {
            autostarted = true
            let n = i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) ?? 0 : 0
            store.reload { [weak self] in
                guard let self = self, !self.store.games.isEmpty else { return }
                self.present(GameViewController(game: self.store.games[min(n, self.store.games.count - 1)]), animated: false)
            }
        }
    }

    private func start(_ g: Game) {
        if host_running() != 0 {
            let a = UIAlertController(title: "A game is still closing", message: "Try again in a moment.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        present(GameViewController(game: g), animated: true)
    }

    // MARK: context menu, settings, delete

    private func presentSettings(slug: String?, name: String?, isIAppli: Bool) {
        let nav = UINavigationController(rootViewController: SettingsViewController(slug: slug, name: name, isIAppli: isIAppli))
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func confirmDelete(_ g: Game, done: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: "Delete \(g.name)?", message: "The game's files and its saves are removed.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Importer.delete(g, gamesDirectory: Launcher.shared.gamesDirectory)
            self?.store.reload()
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
        let dir = Launcher.shared.gamesDirectory
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Importer.importItems(urls, into: dir)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.store.reload()          // the new games appear behind the message
                let a = UIAlertController(title: result.games > 0 ? "Imported" : "Nothing imported", message: result.message, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                (self.presentedViewController ?? self).present(a, animated: true)
            }
        }
    }
}
