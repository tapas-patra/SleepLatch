import Foundation
import IOKit.ps

enum PowerSourceMonitor {
    static func currentState() -> PowerSourceState {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String else {
                continue
            }

            switch state {
            case kIOPSACPowerValue:
                return .ac
            case kIOPSBatteryPowerValue:
                return .battery
            case kIOPSOffLineValue:
                return .offline
            default:
                continue
            }
        }

        return .unknown
    }
}
