import Foundation
import IOKit.pwr_mgt

@main
enum SessionSmokeCheck {
    @MainActor
    static func main() throws {
        try verifiesManagedSessionLifecycle()
        try verifiesManagedSessionFlagUpdates()
        try verifiesBatteryGuardrail()
        try verifiesBatterySuspension()
        try verifiesSessionExpiry()
        try verifiesDurationFormatting()

        print("SleepLatch smoke checks passed.")
    }

    @MainActor
    private static func verifiesManagedSessionLifecycle() throws {
        let backend = FakeAssertionBackend()
        let controller = CaffeinateSessionController(
            assertionCreate: backend.create,
            assertionRelease: backend.release
        )

        try controller.startManagedSession(duration: nil, flags: [.display, .idle], powerSource: .ac)

        try expect(controller.hasManagedSession, "Managed session should start.")
        try expect(
            Set(controller.managedSession?.assertionIDs.keys.map { $0 } ?? []) == Set([.idle, .display]),
            "Idle and display assertions should be active."
        )
        try expect(
            Set(backend.createdTypes) == Set([
                kIOPMAssertPreventUserIdleSystemSleep as String,
                kIOPMAssertPreventUserIdleDisplaySleep as String,
            ]),
            "Unexpected assertion types were created."
        )

        let activeAssertionIDs = Set(controller.managedSession?.assertionIDs.values.map { $0 } ?? [])
        controller.stopManagedSession()

        try expect(!controller.hasManagedSession, "Managed session should stop cleanly.")
        try expect(Set(backend.releasedIDs) == activeAssertionIDs, "All created assertions should be released.")
    }

    @MainActor
    private static func verifiesBatteryGuardrail() throws {
        let backend = FakeAssertionBackend()
        let controller = CaffeinateSessionController(
            assertionCreate: backend.create,
            assertionRelease: backend.release
        )

        do {
            try controller.startManagedSession(duration: nil, flags: [.system], powerSource: .battery)
            throw SmokeCheckError("System-only sessions should be rejected on battery.")
        } catch ManagedSessionError.systemSleepRequiresACPower {
        }

        try expect(!controller.hasManagedSession, "Battery guardrail should not leave a managed session behind.")
        try expect(backend.createdTypes.isEmpty, "Battery guardrail should not create assertions.")
    }

    @MainActor
    private static func verifiesManagedSessionFlagUpdates() throws {
        let backend = FakeAssertionBackend()
        let controller = CaffeinateSessionController(
            assertionCreate: backend.create,
            assertionRelease: backend.release
        )

        try controller.startManagedSession(duration: nil, flags: [.idle], powerSource: .ac)
        let initialIdleAssertionID = try require(controller.managedSession?.assertionIDs[.idle], "Missing idle assertion.")

        try controller.updateManagedSessionFlags([.display, .idle], powerSource: .ac)

        try expect(
            Set(controller.managedSession?.assertionIDs.keys.map { $0 } ?? []) == Set([.idle, .display]),
            "Live flag updates should apply new assertions immediately."
        )
        try expect(
            controller.managedSession?.assertionIDs[.idle] == initialIdleAssertionID,
            "Unchanged assertions should not be recreated during live updates."
        )

        try controller.updateManagedSessionFlags([.display], powerSource: .ac)

        try expect(
            Set(controller.managedSession?.assertionIDs.keys.map { $0 } ?? []) == Set([.display]),
            "Live flag updates should release removed assertions immediately."
        )
        try expect(backend.releasedIDs.contains(initialIdleAssertionID), "Removed assertions should be released.")
    }

    @MainActor
    private static func verifiesBatterySuspension() throws {
        let backend = FakeAssertionBackend()
        let controller = CaffeinateSessionController(
            assertionCreate: backend.create,
            assertionRelease: backend.release
        )

        try controller.startManagedSession(duration: nil, flags: [.idle, .system], powerSource: .ac)
        let systemAssertionID = try require(controller.managedSession?.assertionIDs[.system], "Missing system assertion.")

        try controller.refreshRuntimeState(now: Date().addingTimeInterval(30), powerSource: .battery)

        try expect(
            Set(controller.managedSession?.assertionIDs.keys.map { $0 } ?? []) == Set([.idle]),
            "System assertion should be suspended on battery."
        )
        try expect(backend.releasedIDs.contains(systemAssertionID), "Suspended assertions should be released.")
        try expect(
            controller.detailLine(powerSource: .battery).contains("paused on battery"),
            "Battery suspension should be visible in the UI copy."
        )
    }

    @MainActor
    private static func verifiesSessionExpiry() throws {
        let backend = FakeAssertionBackend()
        let controller = CaffeinateSessionController(
            assertionCreate: backend.create,
            assertionRelease: backend.release
        )

        try controller.startManagedSession(duration: 1, flags: [.idle], powerSource: .ac)
        let idleAssertionID = try require(controller.managedSession?.assertionIDs[.idle], "Missing idle assertion.")

        try controller.refreshRuntimeState(now: Date().addingTimeInterval(5), powerSource: .ac)

        try expect(!controller.hasManagedSession, "Expired sessions should stop automatically.")
        try expect(backend.releasedIDs == [idleAssertionID], "Expired sessions should release their assertions.")
    }

    private static func verifiesDurationFormatting() throws {
        try expect(DurationFormatter.compactLabel(for: 3660) == "1h 1m", "Hour formatting regressed.")
        try expect(DurationFormatter.compactLabel(for: 125) == "2m 5s", "Minute formatting regressed.")
        try expect(DurationFormatter.buttonLabel(for: 3660) == "1h1m", "Hour button formatting regressed.")
        try expect(DurationFormatter.buttonLabel(for: 5400) == "1h30m", "Custom hour button formatting regressed.")
        try expect(DurationFormatter.buttonLabel(for: 125) == "2m", "Minute button formatting regressed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SmokeCheckError(message)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw SmokeCheckError(message)
        }

        return value
    }
}

private struct SmokeCheckError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

private final class FakeAssertionBackend {
    private var nextID: IOPMAssertionID = 1
    private(set) var createdTypes: [String] = []
    private(set) var releasedIDs: [IOPMAssertionID] = []

    func create(
        type: CFString,
        name: CFString,
        details: CFString,
        reason: CFString,
        bundlePath: CFString,
        timeout: TimeInterval?
    ) throws -> IOPMAssertionID {
        createdTypes.append(type as String)
        defer { nextID += 1 }
        return nextID
    }

    func release(_ assertionID: IOPMAssertionID) {
        releasedIDs.append(assertionID)
    }
}
