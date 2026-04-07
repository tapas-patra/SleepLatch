import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showLaunchPanel()
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SleepLatchModel.shared.cleanupOnTerminate()
    }

    private func showLaunchPanel() {
        if launchPanel == nil {
            let hostingController = NSHostingController(
                rootView: ControlPanelView(
                    model: SleepLatchModel.shared,
                    onQuit: {
                        SleepLatchModel.shared.cleanupOnTerminate()
                        NSApp.terminate(nil)
                    }
                )
                .frame(width: 420)
            )
            if #available(macOS 13.0, *) {
                hostingController.sizingOptions = []
            }

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hostingController
            panel.title = "SleepLatch"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.center()

            launchPanel = panel
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        launchPanel?.makeKeyAndOrderFront(nil)
        launchPanel?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
