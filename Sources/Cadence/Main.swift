import AppKit
import Foundation

@main
struct CadenceMain {
    @MainActor
    static func main() async {
        Settings.migrateLegacyDefaults()

        if CommandLine.arguments.dropFirst().contains("--selftest") {
            let formatterPassed = TextFormatter.runSelfTest()
            let learnedPassed = LearnedStore.runSelfTest()
            exit(formatterPassed && learnedPassed ? 0 : 1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
