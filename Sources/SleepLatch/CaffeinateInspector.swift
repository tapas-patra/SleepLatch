import Darwin
import Foundation

final class CaffeinateInspector {
    func runningProcesses(excluding excludedPIDs: Set<Int32> = []) -> [ExternalCaffeinateProcess] {
        listAllPIDs()
            .filter { $0 > 0 }
            .filter { !excludedPIDs.contains($0) }
            .compactMap(processInfo(for:))
            .sorted { $0.pid < $1.pid }
    }

    @discardableResult
    func stop(pid: Int32) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    private func processInfo(for pid: Int32) -> ExternalCaffeinateProcess? {
        guard let bsdInfo = bsdInfo(for: pid) else {
            return nil
        }

        let executablePath = pidPath(for: pid)
        let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
        let processName = string(from: bsdInfo.pbi_name)
        let commandName = string(from: bsdInfo.pbi_comm)

        let isCaffeinateProcess = executableName == "caffeinate"
            || processName == "caffeinate"
            || commandName == "caffeinate"

        guard isCaffeinateProcess else {
            return nil
        }

        let command = executablePath.isEmpty ? (processName.isEmpty ? commandName : processName) : executablePath
        let startTime = TimeInterval(bsdInfo.pbi_start_tvsec) + (TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000)

        return ExternalCaffeinateProcess(
            pid: pid,
            elapsed: elapsedLabel(since: startTime),
            command: command
        )
    }

    private func listAllPIDs() -> [Int32] {
        let estimatedCount = max(proc_listallpids(nil, 0), 256)
        let bufferSize = Int(estimatedCount) * MemoryLayout<Int32>.stride
        let buffer = UnsafeMutablePointer<Int32>.allocate(capacity: Int(estimatedCount))
        defer { buffer.deallocate() }

        let actualCount = proc_listallpids(buffer, Int32(bufferSize))
        guard actualCount > 0 else {
            return []
        }

        return Array(UnsafeBufferPointer(start: buffer, count: Int(actualCount)))
    }

    private func bsdInfo(for pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard result == Int32(MemoryLayout<proc_bsdinfo>.size) else {
            return nil
        }

        return info
    }

    private func pidPath(for pid: Int32) -> String {
        let bufferSize = Int(4 * MAXPATHLEN)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let result = proc_pidpath(pid, buffer, UInt32(bufferSize))
        guard result > 0 else {
            return ""
        }

        return String(cString: buffer)
    }

    private func elapsedLabel(since startTime: TimeInterval) -> String {
        let elapsed = max(Int(Date().timeIntervalSince1970 - startTime), 0)
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private func string<T>(from value: T) -> String {
        withUnsafeBytes(of: value) { buffer in
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return ""
            }

            return String(cString: baseAddress)
        }
    }
}
