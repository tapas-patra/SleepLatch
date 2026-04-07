import AppKit
import SwiftUI

@main
struct SleepLatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SleepLatchModel.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ControlPanelView(
                model: model,
                onQuit: quit
            )
            .frame(width: 420)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                if !model.statusButtonLabel.isEmpty {
                    Text(model.statusButtonLabel)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func quit() {
        model.cleanupOnTerminate()
        NSApp.terminate(nil)
    }
}
