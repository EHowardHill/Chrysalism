import AppKit
import CoreGraphics

/// Creates and maintains one rain window per connected display, refreshing
/// dock collision rects on a slow poll and rebuilding when the display
/// arrangement changes.
///
/// Rain only renders on displays that share a single refresh rate; a mixed
/// 60 Hz / 120 Hz setup shows rain on one matched group at a time so the
/// animation never looks like it stutters next to a smoother neighbor.
final class ScreenManager {
    private var controllers: [RainWindowController] = []
    private var pollTimer: Timer?
    private var isRebuilding = false

    // MARK: - Refresh rates

    /// The display's current refresh rate in whole Hz, preferring the active
    /// display mode and falling back to the nominal maximum.
    static func refreshRate(of screen: NSScreen) -> Int {
        var rate = 0.0
        if let id = screen.displayID, let mode = CGDisplayCopyDisplayMode(id) {
            rate = mode.refreshRate
        }
        if rate < 1 {
            rate = Double(screen.maximumFramesPerSecond)
        }
        if rate < 1 {
            rate = 60
        }
        return Int(rate.rounded())
    }

    /// The refresh rate of the display group the rain should show on.
    static func activeRefreshRate(preferred: Int?) -> Int {
        let rates = Set(NSScreen.screens.map { refreshRate(of: $0) })
        if let preferred = preferred, rates.contains(preferred) {
            return preferred
        }
        if let main = NSScreen.screens.first {
            return refreshRate(of: main)
        }
        return 60
    }

    /// Display groups by refresh rate, ordered for display in the menu:
    /// (rate, screens). Only one group shows rain at a time.
    static func refreshRateGroups() -> [(rate: Int, screens: [NSScreen])] {
        let grouped = Dictionary(grouping: NSScreen.screens) { refreshRate(of: $0) }
        return grouped
            .map { (rate: $0.key, screens: $0.value) }
            .sorted { $0.rate < $1.rate }
    }

    // MARK: - Lifecycle

    func start() {
        rebuild()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.controllers.forEach { $0.refreshDock() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controllers.forEach { $0.setPaused(true) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controllers.forEach { $0.setPaused(false) }
        }
    }

    func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }

        controllers.forEach { $0.close() }
        controllers = NSScreen.screens.compactMap { RainWindowController(screen: $0) }

        let settings = Settings.shared
        controllers.forEach { $0.scene?.intensity = settings.intensity }
        controllers.forEach { $0.scene?.angle = settings.rainAngle }
        applyRainVisibility()
        controllers.forEach { $0.refreshDock() }
    }

    // MARK: - Settings

    func setRainEnabled(_ on: Bool) {
        Settings.shared.rainEnabled = on
        applyRainVisibility()
    }

    func setIntensity(_ intensity: RainIntensity) {
        Settings.shared.intensity = intensity
        controllers.forEach { $0.scene?.intensity = intensity }
    }

    func setAngle(_ angle: CGFloat) {
        Settings.shared.rainAngle = angle
        controllers.forEach { $0.scene?.angle = angle }
    }

    func setRainGroup(_ rate: Int) {
        Settings.shared.rainRefreshRate = rate
        applyRainVisibility()
    }

    func setDockBounce(enabled: Bool) {
        Settings.shared.dockBounceEnabled = enabled
        controllers.forEach { $0.refreshDock() }
    }

    func refreshDockCollision() {
        controllers.forEach { $0.refreshDock() }
    }

    private func applyRainVisibility() {
        let settings = Settings.shared
        let active = Self.activeRefreshRate(preferred: settings.rainRefreshRate)
        controllers.forEach { $0.setRunning(settings.rainEnabled && $0.refreshRate == active) }
    }
}