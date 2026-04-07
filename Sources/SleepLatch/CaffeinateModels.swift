import Foundation
import IOKit.pwr_mgt

enum CaffeinateFlag: String, CaseIterable, Hashable {
    case idle = "-i"
    case display = "-d"
    case disk = "-m"
    case system = "-s"

    private static let defaultsKey = "selectedCaffeinateFlags"

    var menuTitle: String {
        switch self {
        case .idle:
            return "Prevent Idle Sleep (-i)"
        case .display:
            return "Keep Display Awake (-d)"
        case .disk:
            return "Prevent Disk Sleep (-m)"
        case .system:
            return "Prevent System Sleep on AC (-s)"
        }
    }

    var shortLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .display:
            return "display"
        case .disk:
            return "disk"
        case .system:
            return "system-ac"
        }
    }

    var order: Int {
        switch self {
        case .idle:
            return 0
        case .display:
            return 1
        case .disk:
            return 2
        case .system:
            return 3
        }
    }

    var tag: Int {
        order
    }

    static var defaultSelection: [CaffeinateFlag] {
        [.idle]
    }

    static func from(tag: Int) -> CaffeinateFlag? {
        allCases.first { $0.tag == tag }
    }

    static func loadSelection(defaults: UserDefaults = .standard) -> [CaffeinateFlag] {
        let rawValues = defaults.stringArray(forKey: defaultsKey) ?? []
        let loadedFlags = rawValues.compactMap(Self.init(rawValue:))
        return normalize(loadedFlags)
    }

    static func persistSelection(_ selection: [CaffeinateFlag], defaults: UserDefaults = .standard) {
        let rawValues = normalize(selection).map(\.rawValue)
        defaults.set(rawValues, forKey: defaultsKey)
    }

    static func normalize(_ selection: [CaffeinateFlag]) -> [CaffeinateFlag] {
        let uniqueFlags = Array(Set(selection))
        let normalized = uniqueFlags.sorted { $0.order < $1.order }
        return normalized.isEmpty ? defaultSelection : normalized
    }
}

struct ManagedSession {
    let startedAt: Date
    let endsAt: Date?
    var flags: [CaffeinateFlag]
    var assertionIDs: [CaffeinateFlag: IOPMAssertionID]
}

struct ExternalCaffeinateProcess: Hashable {
    let pid: Int32
    let elapsed: String
    let command: String
}

enum PowerSourceState: String {
    case ac = "AC Power"
    case battery = "Battery"
    case offline = "Offline"
    case unknown = "Unknown"

    var isOnACPower: Bool {
        self == .ac
    }

    var label: String {
        switch self {
        case .ac:
            return "AC power"
        case .battery:
            return "Battery"
        case .offline:
            return "Offline power source"
        case .unknown:
            return "Unknown power source"
        }
    }
}

enum DurationFormatter {
    static func compactLabel(for remaining: TimeInterval) -> String {
        let clamped = max(Int(remaining.rounded(.down)), 0)
        if clamped >= 3600 {
            let hours = clamped / 3600
            let minutes = (clamped % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        if clamped >= 60 {
            let minutes = clamped / 60
            let seconds = clamped % 60
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }

        return "\(clamped)s"
    }

    static func buttonLabel(for remaining: TimeInterval) -> String {
        let clamped = max(Int(remaining.rounded(.down)), 0)
        if clamped >= 3600 {
            return "\(clamped / 3600)h"
        }

        if clamped >= 60 {
            return "\(clamped / 60)m"
        }

        return "\(clamped)s"
    }
}
