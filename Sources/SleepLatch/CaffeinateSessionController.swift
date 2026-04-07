import Foundation
import IOKit.pwr_mgt

enum ManagedSessionError: LocalizedError, Equatable {
    case systemSleepRequiresACPower
    case assertionCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .systemSleepRequiresACPower:
            return "System sleep prevention requires AC power."
        case let .assertionCreationFailed(message):
            return message
        }
    }
}

typealias AssertionCreateHandler = (
    _ type: CFString,
    _ name: CFString,
    _ details: CFString,
    _ reason: CFString,
    _ bundlePath: CFString,
    _ timeout: TimeInterval?
) throws -> IOPMAssertionID

typealias AssertionReleaseHandler = (_ assertionID: IOPMAssertionID) -> Void

private func systemAssertionCreate(
    type: CFString,
    name: CFString,
    details: CFString,
    reason: CFString,
    bundlePath: CFString,
    timeout: TimeInterval?
) throws -> IOPMAssertionID {
    var assertionID = IOPMAssertionID(0)
    let result = IOPMAssertionCreateWithDescription(
        type,
        name,
        details,
        reason,
        bundlePath,
        timeout ?? 0,
        nil,
        &assertionID
    )

    guard result == kIOReturnSuccess else {
        throw ManagedSessionError.assertionCreationFailed("IOPMAssertionCreateWithDescription failed with code \(result).")
    }

    return assertionID
}

private func systemAssertionRelease(_ assertionID: IOPMAssertionID) {
    IOPMAssertionRelease(assertionID)
}

@MainActor
final class CaffeinateSessionController: @unchecked Sendable {
    var onChange: (() -> Void)?

    private(set) var managedSession: ManagedSession?
    private let assertionCreate: AssertionCreateHandler
    private let assertionRelease: AssertionReleaseHandler

    var hasManagedSession: Bool {
        managedSession != nil
    }

    init(
        assertionCreate: @escaping AssertionCreateHandler = systemAssertionCreate,
        assertionRelease: @escaping AssertionReleaseHandler = systemAssertionRelease
    ) {
        self.assertionCreate = assertionCreate
        self.assertionRelease = assertionRelease
    }

    func startManagedSession(duration: TimeInterval?, flags: [CaffeinateFlag], powerSource: PowerSourceState) throws {
        stopManagedSession()

        let normalizedFlags = CaffeinateFlag.normalize(flags)
        if normalizedFlags == [.system], !powerSource.isOnACPower {
            throw ManagedSessionError.systemSleepRequiresACPower
        }

        let now = Date()
        managedSession = ManagedSession(
            startedAt: now,
            endsAt: duration.map { now.addingTimeInterval($0) },
            flags: normalizedFlags,
            assertionIDs: [:]
        )

        do {
            try reconcileAssertions(now: now, powerSource: powerSource)
            onChange?()
        } catch {
            stopManagedSession()
            throw error
        }
    }

    func refreshRuntimeState(now: Date = Date(), powerSource: PowerSourceState) throws {
        guard let managedSession else {
            return
        }

        if let endsAt = managedSession.endsAt, endsAt <= now {
            stopManagedSession()
            return
        }

        try reconcileAssertions(now: now, powerSource: powerSource)
    }

    func updateManagedSessionFlags(_ flags: [CaffeinateFlag], powerSource: PowerSourceState) throws {
        guard var managedSession else {
            return
        }

        let normalizedFlags = CaffeinateFlag.normalize(flags)
        if normalizedFlags == [.system], !powerSource.isOnACPower {
            throw ManagedSessionError.systemSleepRequiresACPower
        }

        managedSession.flags = normalizedFlags
        self.managedSession = managedSession
        try reconcileAssertions(now: Date(), powerSource: powerSource)
    }

    func stopManagedSession() {
        guard var managedSession else {
            return
        }

        releaseAssertions(from: &managedSession)
        self.managedSession = nil
        onChange?()
    }

    func statusLine(now: Date = Date(), powerSource: PowerSourceState) -> String {
        guard let managedSession else {
            return "Idle"
        }

        let activeFlags = activeFlagsDescription(from: managedSession)
        let note = suspensionNote(for: managedSession, powerSource: powerSource)
        if let endsAt = managedSession.endsAt {
            let remaining = max(endsAt.timeIntervalSince(now), 0)
            let suffix = note.map { " - \($0)" } ?? ""
            return "Active (\(activeFlags)) - \(DurationFormatter.compactLabel(for: remaining)) remaining\(suffix)"
        }

        let suffix = note.map { " - \($0)" } ?? ""
        return "Active (\(activeFlags)) - until stopped\(suffix)"
    }

    func detailLine(powerSource: PowerSourceState) -> String {
        guard let managedSession else {
            return "Selected flags: \(flagsDescription(CaffeinateFlag.defaultSelection))"
        }

        let activeFlags = activeFlagsDescription(from: managedSession)
        if let note = suspensionNote(for: managedSession, powerSource: powerSource) {
            return "Managed flags: \(activeFlags) - \(note)"
        }

        return "Managed flags: \(activeFlags)"
    }

    func buttonLabel(now: Date = Date()) -> String {
        guard let managedSession else {
            return ""
        }

        guard let endsAt = managedSession.endsAt else {
            return "ON"
        }

        let remaining = max(endsAt.timeIntervalSince(now), 0)
        return DurationFormatter.buttonLabel(for: remaining)
    }

    func isManagedSessionActive(for duration: TimeInterval?) -> Bool {
        guard let managedSession else {
            return false
        }

        switch (duration, managedSession.endsAt) {
        case (nil, nil):
            return true
        case let (.some(expectedDuration), .some(endsAt)):
            let actualDuration = endsAt.timeIntervalSince(managedSession.startedAt)
            return abs(actualDuration - expectedDuration) < 1
        default:
            return false
        }
    }

    func flagsDescription(_ flags: [CaffeinateFlag]) -> String {
        CaffeinateFlag.normalize(flags)
            .map(\.shortLabel)
            .joined(separator: ", ")
    }

    private func reconcileAssertions(now: Date, powerSource: PowerSourceState) throws {
        guard var managedSession else {
            return
        }

        let desiredFlags = activeDesiredFlags(for: managedSession, powerSource: powerSource)
        let activeFlags = Set(managedSession.assertionIDs.keys)

        for flag in activeFlags.subtracting(desiredFlags) {
            if let assertionID = managedSession.assertionIDs.removeValue(forKey: flag) {
                assertionRelease(assertionID)
            }
        }

        for flag in desiredFlags.subtracting(activeFlags) {
            let remaining = managedSession.endsAt.map { max($0.timeIntervalSince(now), 0) }
            let assertionID = try createAssertion(for: flag, timeout: remaining)
            managedSession.assertionIDs[flag] = assertionID
        }

        self.managedSession = managedSession
    }

    private func createAssertion(for flag: CaffeinateFlag, timeout: TimeInterval?) throws -> IOPMAssertionID {
        do {
            return try assertionCreate(
                assertionType(for: flag),
                "SleepLatch" as CFString,
                "SleepLatch is preventing sleep for \(flag.menuTitle)." as CFString,
                humanReadableReason(for: flag) as CFString,
                Bundle.main.bundlePath as CFString,
                timeout
            )
        } catch let error as ManagedSessionError {
            throw error
        } catch {
            throw ManagedSessionError.assertionCreationFailed("Failed to create power assertion for \(flag.shortLabel).")
        }
    }

    private func assertionType(for flag: CaffeinateFlag) -> CFString {
        switch flag {
        case .idle:
            return kIOPMAssertPreventUserIdleSystemSleep as CFString
        case .display:
            return kIOPMAssertPreventUserIdleDisplaySleep as CFString
        case .disk:
            return kIOPMAssertPreventDiskIdle as CFString
        case .system:
            return kIOPMAssertNetworkClientActive as CFString
        }
    }

    private func humanReadableReason(for flag: CaffeinateFlag) -> String {
        switch flag {
        case .idle:
            return "Keeping the Mac awake while SleepLatch prevents idle system sleep."
        case .display:
            return "Keeping the display awake while SleepLatch is active."
        case .disk:
            return "Preventing disk idle while SleepLatch is active."
        case .system:
            return "Keeping the Mac awake on AC power while SleepLatch is active."
        }
    }

    private func activeDesiredFlags(for managedSession: ManagedSession, powerSource: PowerSourceState) -> Set<CaffeinateFlag> {
        Set(managedSession.flags.filter { flag in
            guard flag == .system else {
                return true
            }

            return powerSource.isOnACPower
        })
    }

    private func activeFlagsDescription(from managedSession: ManagedSession) -> String {
        let activeFlags = managedSession.assertionIDs.keys.sorted { $0.order < $1.order }
        if activeFlags.isEmpty {
            return flagsDescription(managedSession.flags)
        }

        return flagsDescription(activeFlags)
    }

    private func suspensionNote(for managedSession: ManagedSession, powerSource: PowerSourceState) -> String? {
        guard managedSession.flags.contains(.system), !powerSource.isOnACPower else {
            return nil
        }

        return "AC-only system sleep prevention is paused on battery"
    }

    private func releaseAssertions(from managedSession: inout ManagedSession) {
        for assertionID in managedSession.assertionIDs.values {
            assertionRelease(assertionID)
        }

        managedSession.assertionIDs.removeAll()
    }
}
