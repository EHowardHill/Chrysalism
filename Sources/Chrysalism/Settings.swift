import AppKit
import CoreGraphics

enum RainIntensity: Int, CaseIterable {
    case drizzle = 0
    case light = 1
    case steady = 2
    case downpour = 3

    var label: String {
        switch self {
        case .drizzle: return "Drizzle"
        case .light: return "Light"
        case .steady: return "Steady"
        case .downpour: return "Downpour"
        }
    }

    /// Total number of live raindrops on screen.
    var dropCount: Int {
        switch self {
        case .drizzle: return 90
        case .light: return 180
        case .steady: return 310
        case .downpour: return 480
        }
    }
}

/// User-facing settings, persisted to UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "rainEnabled": true,
            "intensity": RainIntensity.steady.rawValue,
            "rainAngle": -8.0,
        ])
        Self.migrateSettings(into: d)
        defaults = d
    }

    /// Carries settings over from the app's earlier life as "hi-rain", whose
    /// preferences lived under a different bundle identifier.
    private static func migrateSettings(into defaults: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: "dev.hi-rain.hi-rain") else { return }
        for key in ["rainEnabled", "intensity", "rainAngle",
                    "dockBounceEnabled", "dockBounceDisplayID", "rainRefreshRate"] {
            guard defaults.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
    }

    var rainEnabled: Bool {
        get { defaults.bool(forKey: "rainEnabled") }
        set { defaults.set(newValue, forKey: "rainEnabled") }
    }

    /// Base slant of the rainfall in degrees — positive leans right.
    /// lo-rain's rain falls at a slight angle, so the default is a gentle
    /// leftward lean.
    var rainAngle: CGFloat {
        get { min(45, max(-45, CGFloat(defaults.double(forKey: "rainAngle")))) }
        set { defaults.set(Double(newValue), forKey: "rainAngle") }
    }

    var intensity: RainIntensity {
        get { RainIntensity(rawValue: defaults.integer(forKey: "intensity")) ?? .steady }
        set { defaults.set(newValue.rawValue, forKey: "intensity") }
    }

    /// Whether raindrops bounce off the Dock panel. Only the display that
    /// hosts the Dock can show the effect — like lo-rain, it is never active
    /// on more than one screen.
    var dockBounceEnabled: Bool {
        get {
            if defaults.object(forKey: "dockBounceEnabled") != nil {
                return defaults.bool(forKey: "dockBounceEnabled")
            }
            // Migrate from the older per-screen setting.
            return defaults.integer(forKey: "dockBounceDisplayID") >= 0
        }
        set { defaults.set(newValue, forKey: "dockBounceEnabled") }
    }

    /// The refresh rate (Hz) of the display group the rain is shown on, or
    /// nil to follow the main display's group automatically. Rain only ever
    /// renders on displays that share one refresh rate, so the effect looks
    /// equally smooth everywhere.
    var rainRefreshRate: Int? {
        get {
            let v = defaults.integer(forKey: "rainRefreshRate")
            return v > 0 ? v : nil
        }
        set { defaults.set(newValue ?? -1, forKey: "rainRefreshRate") }
    }
}

extension NSScreen {
    /// Core Graphics display ID for this screen, if available.
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}