import AppKit
import ApplicationServices

/// Locates the Dock bar on a given screen, permission-free.
enum DockObserver {
    struct DockBar {
        /// Collision rect in scene coordinates (origin at the bottom-left of
        /// the screen's full frame).
        let rect: CGRect
        /// Radius of the panel's rounded top corners.
        let cornerRadius: CGFloat
    }

    private static var dockDefaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.dock")
    }

    private static var isTahoe: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    static func bottomDockBar(on screen: NSScreen) -> DockBar? {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let reserved = visible.minY - frame.minY
        guard reserved > 8, reserved < frame.height * 0.4, visible.width > 100 else {
            return nil
        }

        if let bar = accessibilityDockBar(on: screen, reserved: reserved) {
            return bar
        }
        return estimatedDockBar(on: screen, reserved: reserved)
    }

    // MARK: - Exact (Accessibility)

    private static func accessibilityDockBar(on screen: NSScreen, reserved: CGFloat) -> DockBar? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(dock.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        let frame = screen.frame

        for window in windows {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionRaw = positionValue,
                  let sizeRaw = sizeValue else {
                continue
            }
            let positionRef = positionRaw as! AXValue
            let sizeRef = sizeRaw as! AXValue
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionRef, .cgPoint, &position)
            AXValueGetValue(sizeRef, .cgSize, &size)

            // Reject the full-screen click-catcher; keep panel-sized windows.
            guard size.width > 100, size.width < screen.frame.width - 4,
                  size.height > 20, size.height < 300 else { continue }

            // AX coordinates are ambiguous (top-left vs bottom-left global);
            // accept whichever interpretation lands the panel at the bottom
            // of this screen.
            var candidates: [CGRect] = []
            if let displayID = screen.displayID {
                let displayBounds = CGDisplayBounds(displayID)
                // CG-style top-left origin: flip into scene coordinates.
                candidates.append(CGRect(
                    x: position.x - displayBounds.minX,
                    y: frame.height + displayBounds.minY - (position.y + size.height),
                    width: size.width,
                    height: size.height
                ))
            }
            // AppKit-style bottom-left origin.
            candidates.append(CGRect(
                x: position.x - frame.minX,
                y: position.y - frame.minY,
                width: size.width,
                height: size.height
            ))

            for candidate in candidates {
                guard candidate.minX > -50,
                      candidate.maxX < frame.width + 50,
                      candidate.minY > -20, candidate.minY < 60,
                      candidate.maxY < reserved + 60 else { continue }
                return DockBar(
                    rect: candidate,
                    cornerRadius: cornerRadius(reserved: reserved, width: candidate.width)
                )
            }
        }
        return nil
    }

    // MARK: - Estimation

    private static func estimatedDockBar(on screen: NSScreen, reserved: CGFloat) -> DockBar? {
        let visible = screen.visibleFrame
        let defaults = dockDefaults

        let rawTile = defaults?.double(forKey: "tilesize") ?? 0
        let tile: CGFloat = (rawTile >= 32 && rawTile <= 128) ? CGFloat(rawTile) : 64

        let persistentAppIDs = Set(
            (defaults?.array(forKey: "persistent-apps") as? [[String: Any]] ?? [])
                .compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
        )
        let othersCount = (defaults?.array(forKey: "persistent-others") as? [[String: Any]] ?? []).count

        let runningRegularIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .compactMap { $0.bundleIdentifier }
        )
        .subtracting([Bundle.main.bundleIdentifier].compactMap { $0 })

        var tileCount: CGFloat = 0
        if !persistentAppIDs.contains("com.apple.finder") { tileCount += 1 }
        tileCount += CGFloat(persistentAppIDs.count)
        tileCount += CGFloat(othersCount)
        tileCount += 1  // Trash is implicit
        tileCount += CGFloat(runningRegularIDs.subtracting(persistentAppIDs).subtracting(["com.apple.finder"]).count)

        let recentsEnabled: Bool
        if let defaults = defaults, defaults.object(forKey: "show-recents") != nil {
            recentsEnabled = defaults.bool(forKey: "show-recents")
        } else {
            recentsEnabled = true
        }
        if recentsEnabled {
            let recentIDs = Set(
                (defaults?.array(forKey: "recent-apps") as? [[String: Any]] ?? [])
                    .compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
            )
            tileCount += CGFloat(
                recentIDs
                    .subtracting(persistentAppIDs)
                    .subtracting(runningRegularIDs)
                    .count
            )
        }

        // Content-fitted panel: each tile occupies its size plus a small gap,
        // with a little glass padding at each end. Leaned slightly narrow —
        // rain falling past a glass end is far less noticeable than rain
        // bouncing on empty air beside it.
        let cell = tile + 5
        let width = min(visible.width, max(100, tileCount * cell + 20))

        let pinning = defaults?.string(forKey: "pinning") ?? ""
        let x: CGFloat
        if pinning == "start" {
            x = 0
        } else if pinning == "end" {
            x = visible.width - width
        } else {
            x = (visible.width - width) / 2
        }

        return DockBar(
            rect: CGRect(x: x, y: 0, width: width, height: reserved),
            cornerRadius: cornerRadius(reserved: reserved, width: width)
        )
    }

    /// The modern Dock panel is a capsule: its ends curve with roughly half
    /// the panel's height. Older systems use a flatter bar.
    private static func cornerRadius(reserved: CGFloat, width: CGFloat) -> CGFloat {
        let base: CGFloat = isTahoe ? reserved / 2 : 16
        return min(base, width / 2)
    }
}