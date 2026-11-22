import UIKit

/// Shows the game's frames and the touch pad.
final class GameViewController: UIViewController {
    private let game: Game
    private let screenLayer = CALayer()
    private let screenHost = UIView()
    private let pad = PadView()
    private let menuButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var link: CADisplayLink?
    private let audio = AudioOutput()
    private var lastGen: UInt64 = 0
    private var started = false
    private var frameSize: CGSize { CGSize(width: game.lcd.0, height: game.lcd.1) }

    init(game: Game) {
        self.game = game
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = Settings.global("keepAwake") == "1"
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        NotificationCenter.default.removeObserver(self)
    }

    /// "Save state when leaving the app": a state is written before iOS suspends the app.
    @objc private func appDidEnterBackground() {
        guard Settings.global("autoSave") == "1", started, host_running() != 0 else { return }
        let path = Launcher.shared.stateURL.path
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
        DispatchQueue.global().async {
            if host_save_state(path) == 0 { Launcher.shared.saveRecordStores() }
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        screenHost.backgroundColor = .black
        screenHost.clipsToBounds = true
        screenLayer.magnificationFilter = .nearest
        screenLayer.minificationFilter = .linear
        screenHost.layer.addSublayer(screenLayer)
        view.addSubview(screenHost)
        view.addSubview(pad)

        titleLabel.text = game.name
        titleLabel.textColor = UIColor(white: 1, alpha: 0.6)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        var cfg = UIButton.Configuration.plain()
        cfg.image = UIImage(systemName: "ellipsis.circle.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular))
        cfg.baseForegroundColor = UIColor(white: 1, alpha: 0.85)
        menuButton.configuration = cfg
        menuButton.accessibilityLabel = "Game menu"
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] done in
                guard let self = self else { return done([]) }
                let on = self.isFullScreen
                let mode = Settings.effective(self.game.slug, "scaleMode")
                func item(_ title: String, _ image: String, full: Bool, scale: String?, selected: Bool) -> UIAction {
                    UIAction(title: title, image: UIImage(systemName: image), state: selected ? .on : .off) { [weak self] _ in
                        self?.setFullScreen(full, scale: scale)
                    }
                }
                done([UIMenu(title: "Full Screen", image: UIImage(systemName: on ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"), children: [
                    item("Off", "rectangle.compress.vertical", full: false, scale: nil, selected: !on),
                    item("Fit (keep shape)", "arrow.up.left.and.arrow.down.right", full: true, scale: "auto", selected: on && mode != "fill" && mode != "crop"),
                    item("Crop (fill screen, trim edges)", "crop", full: true, scale: "crop", selected: on && mode == "crop"),
                    item("Stretch (fill screen)", "rectangle.expand.vertical", full: true, scale: "fill", selected: on && mode == "fill"),
                ])])
            },
            UIAction(title: "Edit Controls", image: UIImage(systemName: "hand.draw")) { [weak self] _ in self?.pad.setEditing(true) },
            UIAction(title: "Runtime Menu", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.runtimeMenu() },
            UIAction(title: "Game Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in self?.gameSettings() },
            UIAction(title: "Save State", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in self?.saveState() },
            UIDeferredMenuElement.uncached { done in
                let ok = Launcher.shared.hasState
                done([UIAction(title: "Load State", image: UIImage(systemName: "square.and.arrow.up"),
                               attributes: ok ? [] : .disabled) { [weak self] _ in self?.loadState() }])
            },
            UIAction(title: "Close Game", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                self?.confirmClose()
            },
        ])
        view.addSubview(menuButton)
    }

    private var isFullScreen: Bool { Settings.effective(game.slug, "fullScreen") == "1" }

    /// Full screen on/off, and how the game fills it (kept per game).
    private func setFullScreen(_ on: Bool, scale: String?) {
        Settings.setOverride(game.slug, "fullScreen", on ? "1" : "0")
        if let sc = scale {
            Settings.setOverride(game.slug, "scaleMode", sc)
            Launcher.shared.removeRuntimeChoice(slug: game.slug, key: "DISPLAY_MODE")
        }
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// The runtime's own menu (display, sound, keys), opened with its menu key.
    private func runtimeMenu() {
        let sym = Int32(PadAction.menu.sym)
        host_key(sym, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { host_key(sym, 0) }
    }

    private func gameSettings() {
        let vc = SettingsViewController(slug: game.slug, name: game.name, isIAppli: game.isIAppli)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func confirmClose() {
        let a = UIAlertController(title: "Close \(game.name)?", message: "Progress since the last saved state is lost.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Save State & Close", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let path = Launcher.shared.stateURL.path
            DispatchQueue.global().async {
                let r = host_save_state(path)
                DispatchQueue.main.async {
                    if r == 0 { Launcher.shared.saveRecordStores() }
                    self.quit()
                }
            }
        })
        a.addAction(UIAlertAction(title: "Close Without Saving", style: .destructive) { [weak self] _ in self?.quit() })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(a, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let rawSafe = view.bounds.inset(by: view.safeAreaInsets)
        let landscape = rawSafe.width > rawSafe.height
        // Upright, side insets (a hinge bar or similar) are ignored so the picture is centred on the real
        // screen; in landscape they stay (notch / island).
        let safe = landscape ? rawSafe : CGRect(x: 0, y: rawSafe.minY, width: view.bounds.width, height: rawSafe.height)
        let aspect = frameSize.width / frameSize.height
        let full = isFullScreen
        let padH: CGFloat = landscape ? 0 : min(safe.height * 0.42, 300)
        var w: CGFloat, h: CGFloat

        if full {
            // the game fills the screen (its shape kept); the controls lie over it
            let mode = Settings.effective(game.slug, "scaleMode")
            if mode == "fill" || mode == "crop" {
                // the game is drawn in its own shape, large enough to cover the screen, and the picture
                // fills the whole screen: stretched ("fill") or with its edges cropped ("crop")
                let cover = max(view.bounds.width / frameSize.width, view.bounds.height / frameSize.height)
                w = frameSize.width * cover; h = frameSize.height * cover
                screenHost.frame = view.bounds
                screenLayer.contentsGravity = mode == "fill" ? .resize : .resizeAspectFill
            } else {
                let area = landscape ? view.bounds
                                     : CGRect(x: 0, y: safe.minY, width: view.bounds.width, height: view.bounds.height - safe.minY)
                w = area.width; h = w / aspect
                if h > area.height { h = area.height; w = h * aspect }
                screenHost.frame = CGRect(x: area.midX - w / 2, y: landscape ? area.midY - h / 2 : area.minY, width: w, height: h)
                screenLayer.contentsGravity = .resize
            }
            titleLabel.isHidden = true
            menuButton.frame = CGRect(x: safe.maxX - 48, y: safe.minY + 4, width: 40, height: 40)
            menuButton.backgroundColor = UIColor(white: 0, alpha: 0.35)
            menuButton.layer.cornerRadius = 20
        } else {
            let barH: CGFloat = landscape ? 0 : 44
            let area = CGRect(x: safe.minX, y: safe.minY + barH, width: safe.width, height: safe.height - padH - barH)
            w = area.width; h = w / aspect
            if h > area.height { h = area.height; w = h * aspect }
            screenHost.frame = CGRect(x: area.midX - w / 2, y: area.minY + (landscape ? (area.height - h) / 2 : 0), width: w, height: h)
            screenLayer.contentsGravity = .resize
            menuButton.frame = CGRect(x: safe.maxX - 48, y: safe.minY + (landscape ? 4 : 0), width: 44, height: 44)
            menuButton.backgroundColor = .clear
            titleLabel.frame = CGRect(x: safe.minX + 56, y: safe.minY, width: safe.width - 112, height: 44)
            titleLabel.isHidden = landscape
        }
        screenLayer.frame = screenHost.bounds
        // the pad spans the full width so blocks can be dragged into the side safe areas
        pad.leftInset = safe.minX
        pad.rightInset = view.bounds.width - safe.maxX
        // upright the pad covers the whole screen (touches pass through empty parts) so controls can be dragged anywhere;
        // its default layout sits in the lower part
        pad.homeRect = landscape ? nil : CGRect(x: 0, y: safe.height - padH, width: view.bounds.width, height: padH)
        pad.frame = CGRect(x: 0, y: safe.minY, width: view.bounds.width, height: safe.height)
        pad.opacityFactor = full ? 0.7 : 1
        view.bringSubviewToFront(pad)
        view.bringSubviewToFront(menuButton)

        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let px = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        if !started {
            started = true
            do {
                try Launcher.shared.start(game: game, screenPixels: px)
            } catch {
                let a = UIAlertController(title: "Cannot start", message: error.localizedDescription, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.dismiss(animated: true) })
                present(a, animated: true)
                return
            }
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        } else {
            host_resize(Int32(px.width), Int32(px.height))
        }
    }

    private var overlayShown = false

    @objc private func tick() {
        audio.update()
        let overlay = host_overlay_open() != 0
        pad.refreshStyle()
        if overlay != overlayShown { overlayShown = overlay; pad.setRuntimeMenu(overlay) }
        var w: Int32 = 0, h: Int32 = 0
        var gen: UInt64 = 0
        if let p = host_frame_acquire(&w, &h, &gen) {
            if gen != lastGen {
                lastGen = gen
                let bytes = Int(w) * Int(h) * 4
                let data = Data(bytes: p, count: bytes)
                host_frame_release()
                if let provider = CGDataProvider(data: data as CFData),
                   let img = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: Int(w) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    screenLayer.contents = img
                    CATransaction.commit()
                }
            } else {
                host_frame_release()
            }
        }
        if host_running() == 0 && started && lastGen > 0 {
            if Launcher.shared.restartRequested { restartGame() } else { quit() }
        }
    }

    private let toast = UILabel()
    private func say(_ text: String) {
        toast.text = "  \(text)  "
        toast.textColor = .white
        toast.backgroundColor = UIColor(white: 0, alpha: 0.7)
        toast.font = .systemFont(ofSize: 14)
        toast.layer.cornerRadius = 8; toast.layer.masksToBounds = true
        toast.sizeToFit()
        toast.center = CGPoint(x: view.bounds.midX, y: view.safeAreaInsets.top + 64)
        view.addSubview(toast)
        toast.alpha = 1
        UIView.animate(withDuration: 0.4, delay: 1.5, options: []) { self.toast.alpha = 0 }
    }

    private func saveState() {
        let path = Launcher.shared.stateURL.path
        say("Saving…")
        DispatchQueue.global().async {
            let r = host_save_state(path)
            DispatchQueue.main.async {
                if r == 0 { Launcher.shared.saveRecordStores(); self.say("State saved") }
                else { self.say(r == -2 ? "Game busy, try again" : "Save failed") }
            }
        }
    }

    private func loadState() {
        guard Launcher.shared.hasState else { say("No saved state"); return }
        say("Loading…")
        link?.invalidate(); link = nil
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let px = CGSize(width: (screenHost.bounds.width * scale).rounded(), height: (screenHost.bounds.height * scale).rounded())
        DispatchQueue.global().async {
            _ = host_stop()
            DispatchQueue.main.async {
                do { try Launcher.shared.start(game: self.game, screenPixels: px, restore: true) }
                catch { self.say("Load failed: \(error.localizedDescription)"); return }
                self.lastGen = 0
                self.link = CADisplayLink(target: self, selector: #selector(self.tick))
                self.link?.add(to: .main, forMode: .common)
                host_resize(Int32(px.width), Int32(px.height))   // makes the game redraw
                self.say("State loaded")
            }
        }
    }

    /// "Restart" in the runtime menu: the game ended with a request to start again with its new choices.
    private func restartGame() {
        link?.invalidate(); link = nil
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let px = CGSize(width: (screenHost.bounds.width * scale).rounded(), height: (screenHost.bounds.height * scale).rounded())
        do { try Launcher.shared.start(game: game, screenPixels: px) } catch { quit(); return }
        lastGen = 0
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    private func quit() {
        link?.invalidate(); link = nil
        audio.stop()
        host_quit()
        dismiss(animated: true)
    }
}
