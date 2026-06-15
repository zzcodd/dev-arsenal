import SwiftUI
import AppKit

@main
struct CCTokenDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app: the status item + popover are managed imperatively in
        // AppDelegate. This empty Settings scene just satisfies the App protocol and
        // never shows a window.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        menuBar = MenuBarController(store: store)
    }
}
