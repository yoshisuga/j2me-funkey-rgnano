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

/// The on-screen controls. Two layouts, switched by a button: the game pad
/// (d-pad, OK, soft keys, * #) and a full-size phone keypad (soft keys, OK, 1-9 * 0 #).
/// In landscape the d-pad stays on the left and the keypad takes the right side.
final class PadView: UIView {
    private let dirs: [PadButton] = [
        PadButton(.up, title: "▲"), PadButton(.left, title: "◀"),
        PadButton(.right, title: "▶"), PadButton(.down, title: "▼"),
    ]
    private let fire = PadButton(.fire, title: "OK", round: true)
    private let soft1 = PadButton(.soft1, title: "Soft L")
    private let soft2 = PadButton(.soft2, title: "Soft R")
    private let star = PadButton(.star, title: "*")
    private let pound = PadButton(.pound, title: "#")
    private let numbers: [PadButton]
    private let toggle = UIButton(type: .system)

    /// The runtime menu names its keys A / B / Power: OK is A, Soft R is B, Soft L is Power (the menu key).
    func setRuntimeMenu(_ on: Bool) {
        let power = UIColor(red: 0.55, green: 0.2, blue: 0.2, alpha: 1)
        fire.setOverride(title: on ? "A" : nil, action: nil)
        soft2.setOverride(title: on ? "B" : nil, action: nil)
        soft1.setOverride(title: on ? "Power" : nil, action: on ? .menu : nil, tint: on ? power : nil)
    }

    private(set) var keypad = false { didSet { applyMode(); setNeedsLayout() } }

    override init(frame: CGRect) {
        numbers = [PadAction.k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8, .k9, .k0].map {
            PadButton($0, title: $0 == .k0 ? "0" : String($0.phoneCode - 48), fontSize: 26)
        }
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        (dirs + [fire, soft1, soft2, star, pound] + numbers).forEach(addSubview)
        toggle.addAction(UIAction { [weak self] _ in self?.keypad.toggle() }, for: .touchUpInside)
        addSubview(toggle)
        applyMode()
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let landscape = b.width > b.height * 1.4
        let g: CGFloat = 8
        let toggleSize = CGSize(width: 140, height: 36)

        if !keypad || landscape {
            // d-pad block, left (portrait keypad mode hides it)
            let cell = max(40, min(landscape ? (b.height - toggleSize.height - 12) / 3.3 : b.width / 6.2, 76))
            let dpadW = cell * 3 + g * 2
            let dx = g * 2, dy = max(4, (b.height - dpadW - (landscape ? toggleSize.height : 0)) / 2)
            let cx = dx + cell + g, cy = dy + cell + g
            dirs[0].frame = CGRect(x: cx, y: dy, width: cell, height: cell)
            dirs[1].frame = CGRect(x: dx, y: cy, width: cell, height: cell)
            dirs[2].frame = CGRect(x: cx + cell + g, y: cy, width: cell, height: cell)
            dirs[3].frame = CGRect(x: cx, y: cy + cell + g, width: cell, height: cell)
            dirs.forEach { $0.isHidden = false }

            if !keypad {
                let fw = cell * 1.3
                fire.frame = CGRect(x: b.width - fw - g * 2, y: b.midY - fw / 2, width: fw, height: fw)
                let sw = min(cell * 1.6, (b.width - dpadW) / 3)
                soft1.frame = CGRect(x: b.width - fw - g * 2 - sw - g, y: b.midY - fw / 2 - cell * 0.9, width: sw, height: cell * 0.7)
                soft2.frame = CGRect(x: b.width - sw - g * 2, y: b.midY - fw / 2 - cell * 0.9, width: sw, height: cell * 0.7)
                star.frame = CGRect(x: b.width - fw - g * 2 - sw - g, y: b.midY + fw / 2 + g, width: sw, height: cell * 0.6)
                pound.frame = CGRect(x: b.width - sw - g * 2, y: b.midY + fw / 2 + g, width: sw, height: cell * 0.6)
            }
            toggle.frame = landscape
                ? CGRect(x: dx + dpadW / 2 - toggleSize.width / 2, y: b.height - toggleSize.height - 4, width: toggleSize.width, height: toggleSize.height)
                : CGRect(x: b.midX - toggleSize.width / 2, y: b.height - toggleSize.height - 4, width: toggleSize.width, height: toggleSize.height)
        } else {
            dirs.forEach { $0.isHidden = true }
            toggle.frame = CGRect(x: b.midX - toggleSize.width / 2, y: b.height - toggleSize.height - 4, width: toggleSize.width, height: toggleSize.height)
        }

        if keypad {
            // keypad region: the whole width in portrait, the right part in landscape
            let r = landscape
                ? CGRect(x: b.width * 0.42, y: 4, width: b.width * 0.58 - 12, height: b.height - 8)
                : CGRect(x: 12, y: 4, width: b.width - 24, height: b.height - toggleSize.height - 18)
            let softH: CGFloat = min(44, r.height * 0.14)
            let sw = (r.width - 2 * g) / 3
            soft1.frame = CGRect(x: r.minX, y: r.minY, width: sw, height: softH)
            fire.frame = CGRect(x: r.minX + sw + g, y: r.minY, width: sw, height: softH)
            soft2.frame = CGRect(x: r.minX + 2 * (sw + g), y: r.minY, width: sw, height: softH)
            fire.setNeedsLayout()
            let top = r.minY + softH + g
            let ch = (r.maxY - top - 3 * g) / 4
            func place(_ v: UIView, _ col: Int, _ row: Int) {
                v.frame = CGRect(x: r.minX + CGFloat(col) * (sw + g), y: top + CGFloat(row) * (ch + g), width: sw, height: ch)
            }
            for (i, n) in numbers.enumerated() {
                if i == 9 { place(n, 1, 3) } else { place(n, i % 3, i / 3) }   // 0 below 8
            }
            place(star, 0, 3)
            place(pound, 2, 3)
            [star, pound].forEach { $0.setFont(26) }
        } else {
            [star, pound].forEach { $0.setFont(18) }
        }
        fire.layoutIfNeeded()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }
}
