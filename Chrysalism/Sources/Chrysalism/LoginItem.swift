import ServiceManagement

/// Launch-at-login support via SMAppService (macOS 13+).
enum LoginItem {
    static var isAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isRegistered: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration only works from a proper app bundle location.
            }
        }
    }
}
