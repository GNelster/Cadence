import AppKit
import Carbon.HIToolbox
import Foundation

/// A voice command recognized by `CommandRouter`, distinct from ordinary
/// dictation text — executed instead of typed.
enum CadenceCommand: Equatable {
    case launchApp(query: String)
    case keystroke(keyCode: Int, flags: CGEventFlags.RawValue)
}

/// Parses a raw transcript for "command mode" voice commands — app
/// launching/switching ("open Safari", "switch to Mail") and a small fixed
/// set of text-editing shortcuts ("select all", "new tab"). Command mode is
/// opt-in (see `Settings.commandModeEnabled`) and, even when on, only ever
/// fires when the *entire* utterance is the command — never a substring
/// mid-sentence — so ordinary dictation containing words like "open" or
/// "select all" is never hijacked.
struct CommandRouter {

    /// Small, explicit table of editing commands mapped to a synthesized
    /// keystroke. Deliberately not a generic DSL — just the handful of
    /// shortcuts useful across most apps.
    private static let editingCommands: [(phrases: [String], keyCode: Int, flags: CGEventFlags)] = [
        (["select all"], kVK_ANSI_A, .maskCommand),
        (["new tab"], kVK_ANSI_T, .maskCommand),
        (["close tab"], kVK_ANSI_W, .maskCommand),
        (["new window"], kVK_ANSI_N, .maskCommand),
        (["delete that", "delete selection", "delete this"], kVK_Delete, []),
        (["save that", "save"], kVK_ANSI_S, .maskCommand),
    ]

    private static let launchLeadIns = ["open", "switch to", "go to", "launch", "activate"]

    /// Matches `raw` against the command grammar, requiring the whole
    /// utterance (after filler-stripping) to be the command. Returns `nil`
    /// for anything that isn't an exact command match, so normal prose
    /// always falls through to ordinary dictation.
    func match(_ raw: String) -> CadenceCommand? {
        let utterance = TextFormatter.normalizedUtterance(raw)
        guard !utterance.isEmpty else { return nil }

        for command in Self.editingCommands {
            let alternatives = command.phrases
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            let pattern = "(?i)^(\(alternatives))[,.!]?$"
            if utterance.range(of: pattern, options: .regularExpression) != nil {
                return .keystroke(keyCode: command.keyCode, flags: command.flags.rawValue)
            }
        }

        let leadIns = Self.launchLeadIns
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?i)^(?:\(leadIns))\\s+(.+?)[,.!]?$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
             in: utterance, range: NSRange(utterance.startIndex..., in: utterance)),
           let queryRange = Range(match.range(at: 1), in: utterance) {
            let query = String(utterance[queryRange]).trimmingCharacters(in: .whitespaces)
            if !query.isEmpty { return .launchApp(query: query) }
        }
        return nil
    }

    static func runSelfTest() -> Bool {
        let router = CommandRouter()
        let cases: [(input: String, expected: CadenceCommand?)] = [
            ("open safari", .launchApp(query: "safari")),
            ("open Safari", .launchApp(query: "Safari")),
            ("switch to mail", .launchApp(query: "mail")),
            ("select all", .keystroke(keyCode: kVK_ANSI_A, flags: CGEventFlags.maskCommand.rawValue)),
            ("new tab", .keystroke(keyCode: kVK_ANSI_T, flags: CGEventFlags.maskCommand.rawValue)),
            ("delete that", .keystroke(keyCode: kVK_Delete, flags: 0)),
            ("select all the files", nil),
            ("please open the door and select all your options", nil),
            ("hello world", nil),
            ("", nil),
        ]
        var passed = true
        for testCase in cases {
            let got = router.match(testCase.input)
            let ok = got == testCase.expected
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): CommandRouter.match(\"\(testCase.input)\") -> " +
                  "\(String(describing: got))" +
                  (ok ? "" : " (expected \(String(describing: testCase.expected)))"))
        }
        return passed
    }
}

/// All installed apps found in the standard Applications directories — not
/// just currently running ones — the pool offered when picking an app for a
/// per-app style override, a dictation exclusion, or a command-mode
/// "open <app>" match. Reads each app bundle's Info.plist directly rather
/// than going through Spotlight/LaunchServices, since Spotlight's index can
/// be disabled or incomplete on some Macs. Computed once per launch and
/// cached, since scanning ~100+ .app bundles on every SwiftUI re-render (or
/// every dictation, in command mode) would be wasteful.
let installedRegularAppsCache: [(bundleID: String, name: String)] =
    scanInstalledRegularApps()

func installedRegularApps() -> [(bundleID: String, name: String)] {
    installedRegularAppsCache
}

func scanInstalledRegularApps() -> [(bundleID: String, name: String)] {
    let fileManager = FileManager.default
    let roots = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]
    var seenBundleIDs = Set<String>()
    var results: [(bundleID: String, name: String)] = []
    for root in roots {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
        for entry in entries where entry.hasSuffix(".app") {
            let infoPlistPath = "\(root)/\(entry)/Contents/Info.plist"
            guard let data = fileManager.contents(atPath: infoPlistPath),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String,
                  !seenBundleIDs.contains(bundleID)
            else { continue }
            seenBundleIDs.insert(bundleID)
            let name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? String(entry.dropLast(".app".count))
            results.append((bundleID, name))
        }
    }
    return results.sorted { $0.name < $1.name }
}

/// Resolves a spoken app-name query against the installed-apps list,
/// refusing rather than guessing when there's no confident match — a wrong
/// launch is worse than an error. Precedence: exact case-insensitive name
/// match, then name containing the query as a whole word, then query
/// containing the name.
func resolveAppName(_ query: String) -> (bundleID: String, name: String)? {
    let apps = installedRegularApps()
    let lowerQuery = query.lowercased()

    if let exact = apps.first(where: { $0.name.lowercased() == lowerQuery }) {
        return exact
    }
    if let containsQuery = apps.first(where: {
        $0.name.lowercased().range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: lowerQuery))\\b",
            options: .regularExpression) != nil
    }) {
        return containsQuery
    }
    if let queryContainsName = apps.first(where: { lowerQuery.contains($0.name.lowercased()) }) {
        return queryContainsName
    }
    return nil
}
