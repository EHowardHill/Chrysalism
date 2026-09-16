import AppKit

/// A menu-item view that lets the user drag a slider to set the rainfall's
/// slant, updating the rain in real time.
final class AngleMenuView: NSView {

    var onAngleChange: ((CGFloat) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Slant")
    private let valueLabel = NSTextField(labelWithString: "0°")
    private let slider = NSSlider()

    /// Horizontal inset of menu item titles (state + image column), matching
    /// where AppKit places the text of sibling items like "Rain" or "Quit".
    private static let titleInset: CGFloat = 24
    private let viewWidth: CGFloat = 250
    private let rowHeight: CGFloat = 36

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))

        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor

        valueLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        slider.minValue = -45
        slider.maxValue = 45
        slider.doubleValue = Double(Settings.shared.rainAngle)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.setAccessibilityLabel("Rain slant")

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)

        let textY = (rowHeight - 16) / 2
        let valueX = viewWidth - Self.titleInset - 44
        titleLabel.frame = NSRect(x: Self.titleInset, y: textY, width: 44, height: 16)
        valueLabel.frame = NSRect(x: valueX, y: textY, width: 44, height: 16)
        slider.frame = NSRect(
            x: Self.titleInset + 52,
            y: (rowHeight - 26) / 2,
            width: valueX - 8 - (Self.titleInset + 52),
            height: 26
        )

        syncLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let angle = CGFloat(sender.doubleValue)
        valueLabel.stringValue = Self.format(angle)
        onAngleChange?(angle)
    }

    private func syncLabels() {
        valueLabel.stringValue = Self.format(CGFloat(slider.doubleValue))
    }

    private static func format(_ angle: CGFloat) -> String {
        let rounded = (angle * 2).rounded() / 2
        if rounded == 0 { return "0°" }
        return String(format: "%.1f°", rounded).replacingOccurrences(of: ".0", with: "")
    }
}