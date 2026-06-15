import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for the "Launch at login" toggle (macOS 13+).
/// Registration only sticks for a properly bundled .app — see scripts/build-app.sh.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
