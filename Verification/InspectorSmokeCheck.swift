import Foundation

@main
enum InspectorSmokeCheck {
    static func main() {
        let processes = CaffeinateInspector().runningProcesses()
        for process in processes {
            print("\(process.pid)\t\(process.elapsed)\t\(process.command)")
        }
    }
}
