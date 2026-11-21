import UIKit

/// Touch keypad button: sends the same key events the web page's pad does.
final class PadButton: UIControl {
    let action: PadAction
    private let label = UILabel()
    private let round: Bool

    init(_ action: PadAction, title: String, round: Bool = false, fontSize: CGFloat = 18) {
        self.action = action
        self.round = round
        self.normalTitle = title
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(white: 0.22, alpha: 1)
        layer.cornerRadius = 10
        layer.borderColor = UIColor(white: 0.4, alpha: 1).cgColor
        layer.borderWidth = 1
        label.text = title
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: fontSize, weight: .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.isUserInteractionEnabled = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setFont(_ size: CGFloat) { label.font = .systemFont(ofSize: size, weight: .semibold) }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 4, dy: 2)
        layer.cornerRadius = round ? min(bounds.width, bounds.height) / 2 : 10
    }

    /// While the runtime menu is open a button can show another name and send another key.
    private let normalTitle: String
    private var overrideAction: PadAction?
    private var tint: UIColor?
    private var pressedSym: Int32 = 0

    func setOverride(title: String?, action: PadAction?, tint: UIColor? = nil) {
        label.text = title ?? normalTitle
        overrideAction = action
        self.tint = tint
        backgroundColor = tint ?? UIColor(white: 0.22, alpha: 1)
    }

    private var down = false
    private func set(_ d: Bool) {
        guard d != down else { return }
        down = d
        backgroundColor = d ? UIColor(white: 0.5, alpha: 1) : (tint ?? UIColor(white: 0.22, alpha: 1))
        if d { pressedSym = Int32((overrideAction ?? action).sym) }
        host_key(pressedSym, d ? 1 : 0)
        if d && Settings.global("haptics") == "1" { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { set(true) }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { set(false) }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { set(false) }
}

/// A touch "stick" for the direction keys: not analog, it presses up/down/left/right (and both for a diagonal).
final class StickView: UIView {
    private let thumb = UIView()
    private var active = Set<Int32>()
    private var tracked: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(white: 0.22, alpha: 1)
        layer.borderColor = UIColor(white: 0.4, alpha: 1).cgColor
        layer.borderWidth = 1
        thumb.backgroundColor = UIColor(white: 0.55, alpha: 1)
        thumb.isUserInteractionEnabled = false
        addSubview(thumb)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var thumbSize: CGFloat { bounds.width * 0.44 }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        thumb.layer.cornerRadius = thumbSize / 2
        if tracked == nil { thumb.frame = CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize); thumb.center = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    private func update(_ t: UITouch) {
        let l = t.location(in: self)
        var dx = l.x - bounds.midX, dy = l.y - bounds.midY
        let r = bounds.width / 2
        let m = hypot(dx, dy)
        var want = Set<Int32>()
        if m > r * 0.28 {
            if abs(dx) > m * 0.38 { want.insert(Int32((dx < 0 ? PadAction.left : PadAction.right).sym)) }
            if abs(dy) > m * 0.38 { want.insert(Int32((dy < 0 ? PadAction.up : PadAction.down).sym)) }
        }
        let lim = r - thumbSize / 2
        if m > lim { dx *= lim / m; dy *= lim / m }
        thumb.center = CGPoint(x: bounds.midX + dx, y: bounds.midY + dy)
        if want != active {
            for k in active.subtracting(want) { host_key(k, 0) }
            for k in want.subtracting(active) { host_key(k, 1) }
            if !want.isEmpty && Settings.global("haptics") == "1" { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5) }
            active = want
        }
    }
    private func release() {
        for k in active { host_key(k, 0) }
        active = []
        tracked = nil
        UIView.animate(withDuration: 0.1) { self.thumb.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY) }
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if tracked == nil, let f = t.first { tracked = f; update(f) } }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { if let k = tracked, t.contains(k) { update(k) } }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { if let k = tracked, t.contains(k) { release() } }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { if let k = tracked, t.contains(k) { release() } }
}

enum PadGroup: String, CaseIterable { case dpad, soft1, soft2, fire, star, pound, keypad, toggle }

/// The on-screen controls. Two layouts, switched by a button: the game pad
/// (d-pad or stick, OK, soft keys, * #) and a phone keypad (soft keys, OK, 1-9 * 0 #).
/// Each block (d-pad, actions, keypad, switch button) can be dragged in edit mode;
/// positions are kept per orientation.
final class PadView: UIView {
    private let dirs: [PadButton] = [
        PadButton(.up, title: "▲"), PadButton(.left, title: "◀"),
        PadButton(.right, title: "▶"), PadButton(.down, title: "▼"),
    ]
    private let stick = StickView()
    private let fire = PadButton(.fire, title: "OK", round: true)
    private let soft1 = PadButton(.soft1, title: "Soft L")
    private let soft2 = PadButton(.soft2, title: "Soft R")
    private let star = PadButton(.star, title: "*")
    private let pound = PadButton(.pound, title: "#")
    private let numbers: [PadButton]
    private let toggle = UIButton(type: .system)
    private var outlines: [PadGroup: UIView] = [:]
    private let editBar = UIStackView()

    /// Side safe-area insets: the pad spans the whole width, but blocks start inside these margins
    /// (they can be dragged out into them).
    var leftInset: CGFloat = 0 { didSet { if leftInset != oldValue { setNeedsLayout() } } }
    var rightInset: CGFloat = 0 { didSet { if rightInset != oldValue { setNeedsLayout() } } }
    var onEditEnd: (() -> Void)?
    private(set) var editing = false

    /// The runtime menu names its keys A / B / Power: OK is A, Soft R is B, Soft L is Power (the menu key).
    func setRuntimeMenu(_ on: Bool) {
        let power = UIColor(red: 0.55, green: 0.2, blue: 0.2, alpha: 1)
        fire.setOverride(title: on ? "A" : nil, action: nil)
        soft2.setOverride(title: on ? "B" : nil, action: nil)
        soft1.setOverride(title: on ? "Power" : nil, action: on ? .menu : nil, tint: on ? power : nil)
    }

    private(set) var keypad = false { didSet { applyMode(); setNeedsLayout() } }
    private var styleShown = Settings.global("dpadStyle")

    /// Picks up a changed "Direction control" setting.
    func refreshStyle() {
        let s = Settings.global("dpadStyle")
        if s != styleShown { styleShown = s; setNeedsLayout() }
    }

    override init(frame: CGRect) {
        numbers = [PadAction.k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8, .k9, .k0].map {
            PadButton($0, title: $0 == .k0 ? "0" : String($0.phoneCode - 48), fontSize: 24)
        }
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        for g in PadGroup.allCases {
            let o = UIView()
            o.isHidden = true
            o.isUserInteractionEnabled = false
            o.layer.borderColor = UIColor.systemYellow.cgColor
            o.layer.borderWidth = 2
            o.layer.cornerRadius = 12
            o.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.12)
            outlines[g] = o
            addSubview(o)
        }
        (dirs + [stick, fire, soft1, soft2, star, pound] + numbers).forEach(addSubview)
        toggle.addAction(UIAction { [weak self] _ in self?.keypad.toggle() }, for: .touchUpInside)
        addSubview(toggle)
        applyMode()

        func barButton(_ title: String, _ handler: @escaping () -> Void) -> UIButton {
            var c = UIButton.Configuration.filled()
            c.title = title; c.cornerStyle = .capsule
            c.baseBackgroundColor = .systemYellow; c.baseForegroundColor = .black
            let b = UIButton(configuration: c)
            b.addAction(UIAction { _ in handler() }, for: .touchUpInside)
            return b
        }
        editBar.axis = .horizontal; editBar.spacing = 10
        editBar.addArrangedSubview(barButton("Reset") { [weak self] in self?.resetPositions() })
        editBar.addArrangedSubview(barButton("Done") { [weak self] in self?.setEditing(false); self?.onEditEnd?() })
        editBar.isHidden = true
        addSubview(editBar)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        gestureRecognizers?.first?.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyMode() {
        numbers.forEach { $0.isHidden = !keypad }
        var cfg = UIButton.Configuration.filled()
        cfg.title = keypad ? "D-pad" : "Keypad"
        cfg.image = UIImage(systemName: keypad ? "gamecontroller" : "circle.grid.3x3")
        cfg.imagePadding = 6
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = UIColor(white: 0.3, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        toggle.configuration = cfg
    }

    // MARK: positions

    private var landscape: Bool { bounds.width > bounds.height * 1.4 }
    private var orient: String { landscape ? "land" : "port" }
    private func key(_ g: PadGroup) -> String { "pad.\(orient).\(g.rawValue)" }
    private func offset(_ g: PadGroup) -> CGPoint {
        guard let s = UserDefaults.standard.string(forKey: key(g)) else { return .zero }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? CGPoint(x: p[0], y: p[1]) : .zero
    }
    private func setOffset(_ g: PadGroup, _ o: CGPoint) {
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: key(g))
    }
    private func resetPositions() {
        for g in PadGroup.allCases { UserDefaults.standard.removeObject(forKey: key(g)) }
        setNeedsLayout()
    }

    private var defaults: [PadGroup: CGRect] = [:]
    private var frames: [PadGroup: CGRect] = [:]
    private var shown: [PadGroup] = []

    /// The block's default rectangle moved by the user's offset and kept inside the pad.
    private func placed(_ g: PadGroup, _ def: CGRect) -> CGRect {
        defaults[g] = def
        let o = offset(g)
        var r = def.offsetBy(dx: o.x * bounds.width, dy: o.y * bounds.height)
        r.origin.x = min(max(r.origin.x, 0), max(0, bounds.width - r.width))
        r.origin.y = min(max(r.origin.y, 0), max(0, bounds.height - r.height))
        frames[g] = r
        shown.append(g)
        return r
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let land = landscape
        let g: CGFloat = 8
        let tw: CGFloat = 130, th: CGFloat = 34
        let useStick = Settings.global("dpadStyle") == "stick"
        shown = []

        let cell = max(40, min(land ? (b.height - 16) / 4.2 : b.width / 6.2, land ? 64 : 76))
        let D = cell * 3 + g * 2

        // d-pad or stick (hidden in portrait keypad mode)
        let showDpad = !keypad || land
        var dpadRect = CGRect.zero
        if showDpad {
            let dy = land ? b.height - D - 8 : max(4, (b.height - D) / 2)
            dpadRect = placed(.dpad, CGRect(x: 16 + leftInset, y: dy, width: D, height: D))
            if useStick {
                stick.frame = dpadRect
                dirs.forEach { $0.isHidden = true }
            } else {
                let cx = dpadRect.minX + cell + g, cy = dpadRect.minY + cell + g
                dirs[0].frame = CGRect(x: cx, y: dpadRect.minY, width: cell, height: cell)
                dirs[1].frame = CGRect(x: dpadRect.minX, y: cy, width: cell, height: cell)
                dirs[2].frame = CGRect(x: cx + cell + g, y: cy, width: cell, height: cell)
                dirs[3].frame = CGRect(x: cx, y: cy + cell + g, width: cell, height: cell)
                dirs.forEach { $0.isHidden = false }
            }
        } else {
            dirs.forEach { $0.isHidden = true }
        }
        stick.isHidden = !(showDpad && useStick)

        if !keypad {
            let sw = min(cell * 1.6, 110), fw = cell * 1.3, softH = cell * 0.7, starH = cell * 0.6
            let w = 2 * sw + g, h = softH + g + fw + g + starH
            let def = CGRect(x: b.width - w - 16 - rightInset, y: land ? b.height - h - 8 : (b.height - h) / 2, width: w, height: h)
            // each button is its own movable block; defaults are the old cluster
            soft1.frame = placed(.soft1, CGRect(x: def.minX, y: def.minY, width: sw, height: softH))
            soft2.frame = placed(.soft2, CGRect(x: def.minX + sw + g, y: def.minY, width: sw, height: softH))
            fire.frame = placed(.fire, CGRect(x: def.maxX - fw, y: def.minY + softH + g, width: fw, height: fw))
            star.frame = placed(.star, CGRect(x: def.minX, y: def.maxY - starH, width: sw, height: starH))
            pound.frame = placed(.pound, CGRect(x: def.minX + sw + g, y: def.maxY - starH, width: sw, height: starH))
            [star, pound].forEach { $0.setFont(18) }
        } else {
            let kw: CGFloat, kh: CGFloat, softH: CGFloat, w: CGFloat
            if land {
                kw = min(64, (b.width * 0.4 - 2 * g) / 3)
                kh = min(44, (b.height - 16 - 4 * g) / 5.3)
                softH = kh * 0.8
                w = 3 * kw + 2 * g
            } else {
                w = b.width - 24 - leftInset - rightInset
                kw = (w - 2 * g) / 3
                let avail = b.height - th - 18
                softH = min(44, avail * 0.14)
                kh = (avail - softH - g - 3 * g) / 4
            }
            let h = softH + g + 4 * kh + 3 * g
            let def = land ? CGRect(x: b.width - w - 16 - rightInset, y: b.height - h - 8, width: w, height: h)
                           : CGRect(x: 12 + leftInset, y: 4, width: w, height: h)
            let r = placed(.keypad, def)
            soft1.frame = CGRect(x: r.minX, y: r.minY, width: kw, height: softH)
            fire.frame = CGRect(x: r.minX + kw + g, y: r.minY, width: kw, height: softH)
            soft2.frame = CGRect(x: r.minX + 2 * (kw + g), y: r.minY, width: kw, height: softH)
            let top = r.minY + softH + g
            func place(_ v: UIView, _ col: Int, _ row: Int) {
                v.frame = CGRect(x: r.minX + CGFloat(col) * (kw + g), y: top + CGFloat(row) * (kh + g), width: kw, height: kh)
            }
            for (i, n) in numbers.enumerated() { if i == 9 { place(n, 1, 3) } else { place(n, i % 3, i / 3) } }
            place(star, 0, 3)
            place(pound, 2, 3)
            [star, pound].forEach { $0.setFont(24) }
        }

        // switch button: under the d-pad on a phone held upright, above it in landscape
        let tdef = land
            ? CGRect(x: 16 + leftInset + (D - tw) / 2, y: max(4, (showDpad ? dpadRect.minY : b.height) - th - 6), width: tw, height: th)
            : CGRect(x: b.midX - tw / 2, y: b.height - th - 4, width: tw, height: th)
        toggle.frame = placed(.toggle, tdef)

        for gr in PadGroup.allCases {
            let o = outlines[gr]!
            if editing, let f = frames[gr], shown.contains(gr) { o.frame = f.insetBy(dx: -4, dy: -4); o.isHidden = false } else { o.isHidden = true }
            sendSubviewToBack(o)
        }
        let es = editBar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        editBar.frame = CGRect(x: b.midX - es.width / 2, y: 6, width: es.width, height: es.height)
        bringSubviewToFront(editBar)
        fire.layoutIfNeeded()
    }

    // MARK: editing

    func setEditing(_ on: Bool) {
        editing = on
        editBar.isHidden = !on
        gestureRecognizers?.forEach { ($0 as? UIPanGestureRecognizer)?.isEnabled = on }
        setNeedsLayout()
    }

    private var dragging: PadGroup?
    private var dragStart = CGRect.zero
    @objc private func pan(_ p: UIPanGestureRecognizer) {
        switch p.state {
        case .began:
            let pt = p.location(in: self)
            let order: [PadGroup] = [.toggle, .fire, .soft1, .soft2, .star, .pound, .keypad, .dpad]
            dragging = order.first { shown.contains($0) && (frames[$0]?.insetBy(dx: -8, dy: -8).contains(pt) ?? false) }
            dragStart = dragging.flatMap { frames[$0] } ?? .zero
        case .changed:
            guard let g = dragging, let d = defaults[g] else { return }
            let t = p.translation(in: self)
            let nx = (dragStart.minX + t.x - d.minX) / bounds.width
            let ny = (dragStart.minY + t.y - d.minY) / bounds.height
            setOffset(g, CGPoint(x: nx, y: ny))
            setNeedsLayout(); layoutIfNeeded()
        default:
            dragging = nil
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        if editing { return v is UIButton && !(v is PadButton) ? v : (bounds.contains(point) ? self : nil) }
        return v === self ? nil : v
    }
}
