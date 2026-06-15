import AppKit
import SwiftUI
import Combine

/// Owns the actual menu bar status item + the popover. Using an explicit
/// NSStatusItem (rather than SwiftUI's MenuBarExtra) gives us full control over
/// the button, lets us log that it was really created, and lets us inspect where
/// the system placed it (useful for diagnosing the notch hiding the icon).
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: UsageStore
    private var cancellable: AnyCancellable?

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "CC Token usage")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " " + store.menuBarText
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(store)
        )

        // Keep the menu bar text live.
        cancellable = store.$menuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.statusItem.button?.title = " " + text
            }

        logPlacement()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Logs whether the button exists and where it landed, plus the notch inset —
    /// so we can tell "not created" apart from "created but hidden behind the notch".
    private func logPlacement() {
        log("init")
        // Re-log after the menu bar has laid the item out — the synchronous frame at
        // creation time isn't yet positioned.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.log("after-layout")
        }
    }

    private func log(_ stage: String) {
        let exists = statusItem.button != nil
        let visible = statusItem.isVisible
        let frame = statusItem.button?.window?.frame ?? .zero
        let notch = NSScreen.main?.safeAreaInsets.top ?? 0
        let screenW = NSScreen.main?.frame.width ?? 0
        NSLog("CCToken[\(stage)]: created=\(exists) isVisible=\(visible) buttonWindowFrame=\(NSStringFromRect(frame)) notchTopInset=\(notch) screenWidth=\(screenW)")
    }
}
