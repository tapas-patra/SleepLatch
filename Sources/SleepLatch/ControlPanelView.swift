import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var model: SleepLatchModel
    let onQuit: () -> Void
    @State private var pendingConfirmation: PendingConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusBlock
            if let pendingConfirmation {
                confirmationBlock(for: pendingConfirmation)
            }
            startBlock
            flagsBlock
            externalBlock
            footer
        }
        .padding(18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 20, weight: .semibold))
            Text("SleepLatch")
                .font(.title2.weight(.semibold))
            Spacer()
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.statusLine)
                .font(.headline)
            Text(model.detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Power source: \(model.powerSourceLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastErrorMessage = model.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var startBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start")
                .font(.headline)

            HStack(spacing: 10) {
                presetButton("15m", duration: 15 * 60)
                presetButton("30m", duration: 30 * 60)
                presetButton("1h", duration: 60 * 60)
                Button("Until Stopped") {
                    pendingConfirmation = .indefiniteSession
                }
                .modifier(PresetButtonModifier(isActive: model.isPresetActive(duration: nil)))
            }
        }
    }

    private var flagsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flags")
                .font(.headline)

            ForEach(CaffeinateFlag.allCases.sorted(by: { $0.order < $1.order }), id: \.self) { flag in
                Toggle(
                    flag.menuTitle,
                    isOn: Binding(
                        get: { model.isFlagEnabled(flag) },
                        set: { model.setFlag(flag, enabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)
            }
        }
    }

    private var externalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("External caffeinate")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    model.refresh(forceExternalRefresh: true)
                }
            }

            if model.externalProcesses.isEmpty {
                if model.isRefreshingExternalProcesses {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning for external caffeinate sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No external caffeinate sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.externalProcesses, id: \.pid) { process in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PID \(process.pid) • \(process.elapsed)")
                                        .font(.subheadline.weight(.medium))
                                    Text(process.command)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("Stop") {
                                    model.stopExternalSession(pid: process.pid)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)

                Button("Stop All External Sessions", role: .destructive) {
                    pendingConfirmation = .stopAllExternalSessions
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Stop Current Session") {
                model.stopManagedSession()
            }
            .disabled(!model.hasManagedSession)

            Spacer()

            Button("Quit", role: .destructive) {
                onQuit()
            }
        }
    }

    private func presetButton(_ title: String, duration: TimeInterval?) -> some View {
        Button(title) {
            model.startSession(duration: duration)
        }
        .modifier(PresetButtonModifier(isActive: model.isPresetActive(duration: duration)))
    }

    private func confirmationBlock(for pendingConfirmation: PendingConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pendingConfirmation.title)
                .font(.headline)
            Text(pendingConfirmation.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) {
                    self.pendingConfirmation = nil
                }

                Spacer()

                Button(pendingConfirmation.confirmButtonTitle, role: .destructive) {
                    confirm(pendingConfirmation)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func confirm(_ pendingConfirmation: PendingConfirmation) {
        self.pendingConfirmation = nil

        switch pendingConfirmation {
        case .indefiniteSession:
            model.startSession(duration: nil)
        case .stopAllExternalSessions:
            model.stopAllExternalSessions()
        }
    }
}

private struct PresetButtonModifier: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private enum PendingConfirmation {
    case indefiniteSession
    case stopAllExternalSessions

    var title: String {
        switch self {
        case .indefiniteSession:
            return "Keep Awake Until Stopped?"
        case .stopAllExternalSessions:
            return "Stop All External Sessions?"
        }
    }

    var message: String {
        switch self {
        case .indefiniteSession:
            return "Untimed sessions can keep the Mac awake indefinitely and drain the battery if you forget to stop them."
        case .stopAllExternalSessions:
            return "This will terminate caffeinate processes started outside SleepLatch too."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .indefiniteSession:
            return "Keep Awake"
        case .stopAllExternalSessions:
            return "Stop All"
        }
    }
}
