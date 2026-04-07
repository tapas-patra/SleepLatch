import Darwin
import Foundation

final class CaffeinateInspector {
    func runningProcesses(excluding excludedPIDs: Set<Int32> = []) -> [ExternalCaffeinateProcess] {
        let output = shellOutput(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,etime=,comm=,command="]
        )

        return output
            .split(separator: "\n")
            .compactMap { parseProcessLine(String($0)) }
            .filter { !excludedPIDs.contains($0.pid) }
            .sorted { $0.pid < $1.pid }
    }

    @discardableResult
    func stop(pid: Int32) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    private func parseProcessLine(_ line: String) -> ExternalCaffeinateProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        let components = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace)
        guard components.count == 4,
              let pid = Int32(components[0]) else {
            return nil
        }

        let commandLine = String(components[3])
        let launchedExecutable = commandLine
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
            .map { URL(fileURLWithPath: $0).lastPathComponent }

        let commName = URL(fileURLWithPath: String(components[2])).lastPathComponent
        let isCaffeinateProcess = launchedExecutable == "caffeinate"
            || commandLine == "caffeinate"
            || commName == "caffeinate"
            || commandLine.contains("/caffeinate ")
            || commandLine.hasSuffix("/caffeinate")

        guard isCaffeinateProcess else {
            return nil
        }

        return ExternalCaffeinateProcess(
            pid: pid,
            elapsed: String(components[1]),
            command: commandLine
        )
    }

    private func shellOutput(executable: String, arguments: [String]) -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        guard process.terminationStatus == 0 else {
            return ""
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
