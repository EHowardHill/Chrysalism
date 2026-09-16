import AppKit
import QuartzCore
import SpriteKit

/// Window levels from CGWindowLevel.h, computed rather than read through
/// CGWindowLevelKey because recent SDKs no longer expose the enum's case
/// names to Swift. The formulas are long-stable public ABI:
/// kCGMinimumWindowLevel = INT32_MIN + 5, kCGDesktopWindowLevel = +20,
/// kCGDesktopIconWindowLevel = kCGDesktopWindowLevel + 20.
enum WindowLevels {
    static let desktopIcon = Int(Int32.min) + 5 + 40
    /// Just below the desktop icons, above the wallpaper — the live wallpaper slot.
    static let belowDesktopIcons = desktopIcon - 1
}

/// Owns one borderless rain window pinned to a single display, sitting above
/// the wallpaper but beneath desktop icons and every app window.
final class RainWindowController {
    let displayID: CGDirectDisplayID
    /// This display's refresh rate — rain only shows on displays sharing one rate.
    let refreshRate: Int
    private let screen: NSScreen
    private var window: NSWindow?
    private var skView: SKView?
    private(set) var scene: RainScene?
    private var running = false
    /// Per-screen CADisplayLink (macOS 15+) driving synchronous rendering.
    /// SpriteKit's internal loop paces by bursts on displays it can't vsync
    /// to, which reads as stutter; the display link locks to each panel.
    private var displayLink: AnyObject?

    init?(screen: NSScreen) {
        guard let id = screen.displayID else { return nil }
        self.screen = screen
        self.displayID = id
        self.refreshRate = ScreenManager.refreshRate(of: screen)

        let frame = screen.frame
        let view = SKView(frame: frame)
        view.allowsTransparency = true
        view.preferredFramesPerSecond = refreshRate
        if #available(macOS 15.0, *) {
            view.isAsynchronous = false
            let link = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
            link.add(to: .main, forMode: .default)
            link.isPaused = true
            displayLink = link
        } else {
            view.isPaused = true
        }

        let scene = RainScene(size: frame.size)
        scene.backgroundColor = .clear
        // Nothing draws until rain is enabled for this display.
        scene.isHidden = true
        view.presentScene(scene)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: WindowLevels.belowDesktopIcons)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = view
        // The transparent shell stays on screen permanently. Ordering it in
        // and out on every toggle makes the whole desktop flash, so rain is
        // toggled by hiding the scene and pausing rendering instead.
        window.orderFrontRegardless()

        self.window = window
        self.skView = view
        self.scene = scene
    }

    deinit {
        close()
    }

    func close() {
        if #available(macOS 15.0, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        skView = nil
        scene = nil
    }

    var isRunning: Bool { running }

    /// Toggles rain for this display without touching the window or the
    /// render pipeline — ordering a full-screen window in/out or tearing the
    /// scene down flashes the desktop. The window stays; only the scene's
    /// visibility and the render clock change.
    func setRunning(_ on: Bool) {
        guard let view = skView, let scene = scene else { return }
        guard running != on else { return }
        running = on
        if on {
            if view.scene == nil { view.presentScene(scene) }
            scene.isHidden = false
            setPaused(false)
            refreshDock()
        } else {
            scene.isHidden = true
            // Flush one transparent frame so the last rain frame doesn't
            // linger on screen while rendering is paused.
            view.display()
            setPaused(true)
        }
    }

    /// Pauses rendering without changing visibility (used when displays sleep).
    func setPaused(_ paused: Bool) {
        let effectively = paused || !running
        if #available(macOS 15.0, *) {
            (displayLink as? CADisplayLink)?.isPaused = effectively
        } else {
            skView?.isPaused = effectively
        }
    }

    /// Per-screen vsync tick: ask the (synchronous) SKView to render.
    @available(macOS 15.0, *)
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard running else { return }
        skView?.needsDisplay = true
    }

    /// Re-queries the Dock and updates the scene's collision rect. Only the
    /// display that actually hosts the Dock produces a bar, so the effect is
    /// naturally confined to one screen.
    func refreshDock() {
        guard running, let scene = scene else { return }
        guard Settings.shared.dockBounceEnabled,
              let bar = DockObserver.bottomDockBar(on: screen) else {
            if scene.dockRect != nil { scene.dockRect = nil }
            return
        }
        scene.dockRect = bar.rect
        scene.dockCornerRadius = bar.cornerRadius
    }
}