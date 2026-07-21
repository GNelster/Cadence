import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Cadence", isDirectory: true)

        // One-time migration from the app's pre-rename data folders, so
        // history, dictionary, snippets and scratchpad survive.
        if !FileManager.default.fileExists(atPath: directory.path) {
            for legacyName in ["Utter", "Murmur", "WhisperFlow"] {
                let legacy = base.appendingPathComponent(legacyName, isDirectory: true)
                if FileManager.default.fileExists(atPath: legacy.path) {
                    try? FileManager.default.moveItem(at: legacy, to: directory)
                    break
                }
            }
        }

        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }
}
