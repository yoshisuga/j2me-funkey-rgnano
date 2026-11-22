import UIKit

/// App settings (slug == nil) or one game's settings, which override the app's.
final class SettingsViewController: UITableViewController {
    private let slug: String?
    private let gameName: String?
    private let isIAppli: Bool
    private var sections: [(title: String, defs: [SettingDef])] = []

    init(slug: String?, name: String? = nil, isIAppli: Bool = false) {
        self.slug = slug
        self.gameName = name
        self.isIAppli = isIAppli
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = gameName.map { "\($0)" } ?? "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Reset", primaryAction: UIAction { [weak self] _ in self?.confirmReset() })
        for name in Settings.sectionOrder {
            let defs = Settings.defs.filter { d in
                d.section == name && (slug == nil ? d.key != "lcd" : d.perGame && !(d.key == "lcd" && isIAppli))
            }
            if !defs.isEmpty { sections.append((name, defs)) }
        }
        tableView.allowsSelection = false
    }

    private func confirmReset() {
        let a = UIAlertController(title: slug == nil ? "Reset app settings?" : "Reset this game's settings?",
                                  message: nil, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            if let s = self.slug { Settings.resetGame(s) } else { Settings.resetGlobal() }
            self.tableView.reloadData()
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(a, animated: true)
    }

    // MARK: table

    override func numberOfSections(in tv: UITableView) -> Int { sections.count }
    override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { sections[s].defs.count }
    override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { sections[s].title }

    override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
        guard s == sections.count - 1 else { return nil }
        return slug == nil
            ? "These apply to every game that has no setting of its own. Changes take effect the next time a game starts."
            : "Changes apply the next time the game starts. “Same as app setting” follows Settings on the games list."
    }

    override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let d = sections[ip.section].defs[ip.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var cfg = cell.defaultContentConfiguration()
        cfg.text = d.title
        cell.contentConfiguration = cfg
        cell.accessoryView = button(for: d)
        return cell
    }

    private func button(for d: SettingDef) -> UIButton {
        let override = slug.flatMap { Settings.override($0, d.key) }
        let current = override ?? Settings.global(d.key)
        var actions: [UIAction] = []
        if let s = slug {
            let inherited = UIAction(title: "Same as app setting (\(Settings.label(d.key, Settings.global(d.key))))",
                                     state: override == nil ? .on : .off) { [weak self] _ in
                Settings.setOverride(s, d.key, nil)
                self?.reload(d)
            }
            actions.append(inherited)
        }
        for c in d.choices {
            actions.append(UIAction(title: c.label, state: (slug == nil || override != nil) && current == c.value ? .on : .off) { [weak self] _ in
                if let s = self?.slug {
                    Settings.setOverride(s, d.key, c.value)
                    // a runtime-menu choice for the same thing would win: drop it
                    if let k = d.cfgKey { Launcher.shared.removeRuntimeChoice(slug: s, key: k) }
                } else {
                    Settings.setGlobal(d.key, c.value)
                }
                self?.reload(d)
            })
        }
        var cfg = UIButton.Configuration.plain()
        cfg.title = override == nil && slug != nil ? "Same as app" : Settings.label(d.key, current)
        cfg.image = UIImage(systemName: "chevron.up.chevron.down")
        cfg.imagePlacement = .trailing
        cfg.imagePadding = 6
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11)
        let b = UIButton(configuration: cfg)
        b.menu = UIMenu(children: actions)
        b.showsMenuAsPrimaryAction = true
        b.sizeToFit()
        return b
    }

    private func reload(_ d: SettingDef) {
        for (si, sec) in sections.enumerated() {
            if let ri = sec.defs.firstIndex(where: { $0.key == d.key }) {
                tableView.reloadRows(at: [IndexPath(row: ri, section: si)], with: .none)
            }
        }
    }
}
