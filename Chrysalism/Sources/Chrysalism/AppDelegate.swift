import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    /// NSApplication.delegate is weak, and this class is created inside
    /// main(); the static keeps the delegate alive for the process lifetime
    /// the way main.swift's top-level constant used to.
    @MainActor private static var retainedDelegate: AppDelegate?

    private var statusItem: NSStatusItem?
    private let screenManager = ScreenManager()

    private var rainMenuItem: NSMenuItem?
    private var intensityMenu: NSMenu?
    private var bounceMenuItem: NSMenuItem?
    private var rainOnItem: NSMenuItem?
    private var rainOnMenu: NSMenu?
    private var loginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        takeOverFromRunningCopies()
        buildStatusItem()
        screenManager.start()
    }

    /// Chrysalism is single-instance: a freshly launched copy takes over from
    /// any copy already running (e.g. the login-item copy), so rain is never
    /// doubled up by accident.
    private func takeOverFromRunningCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return }
        for other in others {
            other.terminate()
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuIcon()
            button.toolTip = "Chrysalism"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item

        let title = NSMenuItem(title: "Chrysalism", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let rain = NSMenuItem(title: "Rain", action: #selector(toggleRain(_:)), keyEquivalent: "")
        rain.target = self
        menu.addItem(rain)
        rainMenuItem = rain

        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        let intensities = NSMenu()
        intensities.autoenablesItems = false
        for intensity in RainIntensity.allCases {
            let entry = NSMenuItem(
                title: intensity.label,
                action: #selector(selectIntensity(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = intensity.rawValue
            intensities.addItem(entry)
        }
        intensityItem.submenu = intensities
        menu.addItem(intensityItem)
        intensityMenu = intensities

        let angleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let angleView = AngleMenuView()
        angleView.onAngleChange = { [weak self] angle in
            self?.screenManager.setAngle(angle)
        }
        angleItem.view = angleView
        menu.addItem(angleItem)

        let bounce = NSMenuItem(
            title: "Rain Bounces Off Dock",
            action: #selector(toggleBounce(_:)),
            keyEquivalent: ""
        )
        bounce.target = self
        menu.addItem(bounce)
        bounceMenuItem = bounce

        let rainOnItem = NSMenuItem(title: "Show Rain On", action: nil, keyEquivalent: "")
        let rainOnMenu = NSMenu()
        rainOnMenu.autoenablesItems = false
        rainOnItem.submenu = rainOnMenu
        menu.addItem(rainOnItem)
        self.rainOnItem = rainOnItem
        self.rainOnMenu = rainOnMenu

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginMenuItem = login
        if !LoginItem.isAvailable {
            login.isEnabled = false
        }

        let quit = NSMenuItem(title: "Quit Chrysalism", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private static func menuIcon() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Chrysalism") {
            symbol.isTemplate = true
            return symbol
        }
        // Fallback: a hand-drawn droplet for systems without SF Symbols.
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setFill()
        let circle = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10))
        circle.fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 9, y: 16))
        tail.line(to: NSPoint(x: 4.5, y: 9))
        tail.line(to: NSPoint(x: 13.5, y: 9))
        tail.close()
        tail.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let rainMenuItem = rainMenuItem,
              let intensityMenu = intensityMenu,
              let bounceMenuItem = bounceMenuItem,
              let rainOnItem = rainOnItem,
              let rainOnMenu = rainOnMenu,
              let loginMenuItem = loginMenuItem else { return }

        let settings = Settings.shared
        rainMenuItem.state = settings.rainEnabled ? .on : .off
        bounceMenuItem.state = settings.dockBounceEnabled ? .on : .off
        for entry in intensityMenu.items {
            let intensity = RainIntensity(rawValue: entry.tag)
            entry.state = (intensity == settings.intensity) ? .on : .off
        }
        loginMenuItem.state = LoginItem.isRegistered ? .on : .off
        rebuildRainOnMenu(rainOnMenu, for: rainOnItem)
    }

    /// Rebuilds the refresh-rate groups. Rain only shows on displays that
    /// share one refresh rate, so mixed-rate setups pick a group here. The
    /// item is hidden when every display matches.
    private func rebuildRainOnMenu(_ submenu: NSMenu, for item: NSMenuItem) {
        submenu.removeAllItems()
        let groups = ScreenManager.refreshRateGroups()
        item.isHidden = groups.count <= 1
        guard groups.count > 1 else { return }

        let active = ScreenManager.activeRefreshRate(preferred: Settings.shared.rainRefreshRate)
        for group in groups {
            let name = group.screens.count == 1
                ? group.screens[0].localizedName
                : "\(group.screens.count) Displays"
            let entry = NSMenuItem(
                title: "\(group.rate) Hz — \(name)",
                action: #selector(selectRainGroup(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = group.rate
            entry.state = group.rate == active ? .on : .off
            submenu.addItem(entry)
        }
    }

    // MARK: - Actions

    @objc private func toggleRain(_ sender: NSMenuItem) {
        screenManager.setRainEnabled(!Settings.shared.rainEnabled)
    }

    @objc private func selectIntensity(_ sender: NSMenuItem) {
        guard let intensity = RainIntensity(rawValue: sender.tag) else { return }
        screenManager.setIntensity(intensity)
    }

    @objc private func toggleBounce(_ sender: NSMenuItem) {
        screenManager.setDockBounce(enabled: !Settings.shared.dockBounceEnabled)
    }

    @objc private func selectRainGroup(_ sender: NSMenuItem) {
        screenManager.setRainGroup(sender.tag)
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isRegistered)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}