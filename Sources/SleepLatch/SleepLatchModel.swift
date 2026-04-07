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

        refresh(forceExternalRefresh: false)
        refreshExternalProcesses(showProgress: true)
    }

    func setFlag(_ flag: CaffeinateFlag, enabled: Bool) {
        let previousSelection = selectedFlags

        if enabled {
            selectedFlags.append(flag)
        } else {
            selectedFlags.removeAll { $0 == flag }
        }

        selectedFlags = CaffeinateFlag.normalize(selectedFlags)
        let powerSource = PowerSourceMonitor.currentState()

        if hasManagedSession {
            do {
                try sessionController.updateManagedSessionFlags(selectedFlags, powerSource: powerSource)
                lastErrorMessage = nil
            } catch {
                selectedFlags = previousSelection
                lastErrorMessage = error.localizedDescription
            }
        } else {
            lastErrorMessage = nil
        }

        refresh(forceExternalRefresh: false)
        CaffeinateFlag.persistSelection(selectedFlags)
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

        refresh(forceExternalRefresh: false)
        refreshExternalProcesses(showProgress: true)
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

                self.refresh(forceExternalRefresh: false)
                self.refreshExternalProcesses(showProgress: true)
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

    func refreshExternalProcessesManually() {
        refresh(forceExternalRefresh: false)
        refreshExternalProcesses(showProgress: true)
    }

    func cleanupOnTerminate() {
        externalRefreshToken = UUID()
        timer?.invalidate()
        sessionController.stopManagedSession()
    }

    private func refreshExternalProcesses(showProgress: Bool = false) {
        let refreshToken = UUID()

        externalRefreshToken = refreshToken
        if showProgress {
            isRefreshingExternalProcesses = true
        }

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
