import Foundation

@main
enum ModelExternalSmokeCheck {
    @MainActor
    static func main() {
        let model = SleepLatchModel.shared
        model.refresh(forceExternalRefresh: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        for process in model.externalProcesses {
            print("\(process.pid)\t\(process.elapsed)\t\(process.command)")
        }
    }
}
