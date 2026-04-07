import Combine
import Dispatch
import Foundation

@MainActor
final class SleepLatchModel: ObservableObject {
    static let shared = SleepLatchModel()

    @Published private(set) var statusLine = "Idle"
    @Published private(set) var detailLine = ""
    @Published private(set) var statusButtonLabel = ""
    @Published private(set) var selectedFlags = CaffeinateFlag.loadSelection()
    @Published private(set) var externalProcesses: [ExternalCaffeinateProcess] = []
    @Published private(set) var isRefreshingExternalProcesses = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var hasManagedSession = false
    @Published private(set) var powerSourceLabel = PowerSourceState.unknown.label

    var onStatusChange: (() -> Void)?

    private let sessionController = CaffeinateSessionController()
    private let inspector = CaffeinateInspector()
    private var refreshTick = 0
    private var timer: Timer?
    private var externalRefreshToken = UUID()

    private init() {
        sessionController.onChange = { [weak self] in
            self?.refresh(forceExternalRefresh: true)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.refreshTick += 1
                self.refresh(forceExternalRefresh: self.refreshTick.isMultiple(of: 5))
            }
        }

        refresh(forceExternalRefresh: true)
    }

    func setFlag(_ flag: CaffeinateFlag, enabled: Bool) {
        if enabled {
            selectedFlags.append(flag)
        } else {
            selectedFlags.removeAll { $0 == flag }
        }

        selectedFlags = CaffeinateFlag.normalize(selectedFlags)
        CaffeinateFlag.persistSelection(selectedFlags)
        refresh(forceExternalRefresh: false)
    }

    func isFlagEnabled(_ flag: CaffeinateFlag) -> Bool {
        selectedFlags.contains(flag)
    }

    func isPresetActive(duration: TimeInterval?) -> Bool {
        sessionController.isManagedSessionActive(for: duration)
    }

    func startSession(duration: TimeInterval?) {
        let powerSource = PowerSourceMonitor.currentState()
        do {
            try sessionController.startManagedSession(duration: duration, flags: selectedFlags, powerSource: powerSource)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            refresh(forceExternalRefresh: true)
        }
    }

    func stopManagedSession() {
        sessionController.stopManagedSession()
        refresh(forceExternalRefresh: true)
    }

    func stopExternalSession(pid: Int32) {
        if inspector.stop(pid: pid) {
            lastErrorMessage = nil
        } else {
            lastErrorMessage = "Failed to stop external PID \(pid)"
        }

        refresh(forceExternalRefresh: true)
    }

    func stopAllExternalSessions() {
        isRefreshingExternalProcesses = true

        DispatchQueue.global(qos: .userInitiated).async {
            let inspector = CaffeinateInspector()
            let failures = inspector
                .runningProcesses()
                .filter { !inspector.stop(pid: $0.pid) }

            DispatchQueue.main.async {
                if failures.isEmpty {
                    self.lastErrorMessage = nil
                } else {
                    let failedPIDs = failures.map { String($0.pid) }.joined(separator: ", ")
                    self.lastErrorMessage = "Failed to stop PIDs: \(failedPIDs)"
                }

                self.refresh(forceExternalRefresh: true)
            }
        }
    }

    func refresh(forceExternalRefresh: Bool) {
        let now = Date()
        let powerSource = PowerSourceMonitor.currentState()
        powerSourceLabel = powerSource.label

        do {
            try sessionController.refreshRuntimeState(now: now, powerSource: powerSource)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        statusLine = sessionController.statusLine(now: now, powerSource: powerSource)
        detailLine = sessionController.hasManagedSession
            ? sessionController.detailLine(powerSource: powerSource)
            : "Selected flags: \(sessionController.flagsDescription(selectedFlags))"
        statusButtonLabel = sessionController.buttonLabel(now: now)
        hasManagedSession = sessionController.hasManagedSession

        if forceExternalRefresh {
            refreshExternalProcesses()
        }

        onStatusChange?()
    }

    func cleanupOnTerminate() {
        externalRefreshToken = UUID()
        timer?.invalidate()
        sessionController.stopManagedSession()
    }

    private func refreshExternalProcesses() {
        let refreshToken = UUID()

        externalRefreshToken = refreshToken
        isRefreshingExternalProcesses = true

        DispatchQueue.global(qos: .utility).async {
            let processes = CaffeinateInspector().runningProcesses()

            DispatchQueue.main.async {
                guard self.externalRefreshToken == refreshToken else {
                    return
                }

                self.externalProcesses = processes
                self.isRefreshingExternalProcesses = false
                self.onStatusChange?()
            }
        }
    }
}
