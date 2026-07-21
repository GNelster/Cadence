import Foundation

/// Rule-based cleanup of raw transcripts: filler removal, spoken layout
/// commands, spacing/capitalization fixes, and personal-dictionary
/// substitutions. Mirrors Wispr Flow's "AI edits" with local rules.
struct TextFormatter {

    /// Filler words removed when they appear as standalone tokens.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ehm", "mhm", "hmm",
    ]

    /// Spoken self-corrections: saying one of these mid-dictation discards
    /// everything since the previous sentence, so a slip of the tongue can
    /// be corrected without releasing the hotkey and starting over.
    static let cancelPhrases = [
        "scratch that", "scratch all that", "strike that", "strike all that",
        "delete that", "delete last sentence", "undo that", "undo last sentence",
        "cancel that", "forget that", "forget it",
        "never mind", "nevermind", "back up", "backup", "go back",
    ]

    /// A structured value type a pinpoint correction can retarget.
    private struct CorrectionEntity {
        let name: String
        let pattern: String
    }

    private static let correctionEntities: [CorrectionEntity] = [
        CorrectionEntity(name: "time",
            pattern: "\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)\\b|\\b\\d{1,2}\\s*o'?clock\\b"),
        CorrectionEntity(name: "currency",
            pattern: "\\$\\d+(?:\\.\\d{2})?|\\b\\d+\\s*(?:dollars|bucks)\\b"),
        CorrectionEntity(name: "day",
            pattern: "\\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b"),
        CorrectionEntity(name: "number",
            pattern: "\\b\\d+(?:\\.\\d+)?\\b"),
    ]

    /// Lead-ins for a pinpointed correction — "the meeting's at 3pm,
    /// actually let's do 4pm" — as opposed to `cancelPhrases`, which
    /// discard the whole sentence. Longest phrases first so regex
    /// alternation prefers them over their own shorter prefixes (e.g.
    /// "actually let's do" over bare "actually").
    private static let correctionLeadIns = [
        "actually let's make it instead", "actually let's make it",
        "actually let's do instead", "actually let's do",
        "actually make it instead", "actually make it",
        "let's make it instead", "let's make it",
        "let's do instead", "let's do",
        "sorry, i meant", "sorry i meant", "on second thought",
        "i meant", "i mean", "make that", "actually",
    ]

    var dictionary: [String: String]

    init(dictionary: [String: String] = TextFormatter.loadDictionary()) {
        self.dictionary = dictionary
    }

    static var dictionaryURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("dictionary.json")
    }

    static func loadDictionary() -> [String: String] {
        guard let data = try? Data(contentsOf: dictionaryURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    func format(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        text = applyPinpointCorrection(to: text)
        text = applyCancelCommands(to: text)
        text = removeFillers(from: text)
        text = applySpokenCommands(to: text)
        text = applyDictionary(to: text)
        text = tidyWhitespaceAndPunctuation(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)
        return text
    }

    /// True when the whole utterance (after stripping filler words) is
    /// nothing but a cancel phrase — e.g. a fresh recording that just says
    /// "nevermind" or "scratch that" with nothing else. That signals "undo
    /// the last thing I dictated," not "insert an empty string," so callers
    /// should trigger an undo instead of silently discarding the result of
    /// `format(_:)`.
    func isStandaloneCancelPhrase(_ raw: String) -> Bool {
        let trimmed = removeFillers(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let alternatives = Self.cancelPhrases
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?i)^(\(alternatives))[,.!]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Passes

    private func removeFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            // Filler optionally followed by a comma, as its own word.
            let pattern = "(?i)(^|\\s)\(filler)[,.]?(?=\\s|$)"
            result = result.replacingOccurrences(
                of: pattern, with: "$1", options: .regularExpression)
        }
        return result
    }

    /// Retargets a structured value (a time, day, number, or amount) when
    /// the user corrects themselves mid-dictation — "the meeting's at
    /// 3pm, actually let's do 4pm" becomes "the meeting's at 4pm" — by
    /// swapping the most recent same-type value instead of erasing the
    /// whole sentence like `applyCancelCommands` does. No-ops (leaves the
    /// text untouched) unless both a lead-in and a same-type value earlier
    /// in the text are found, so ordinary uses of "actually" or "I mean"
    /// don't get mangled.
    private func applyPinpointCorrection(to text: String) -> String {
        guard let match = firstPinpointCorrectionMatch(in: text),
              let correctionRange = Range(match.range, in: text),
              let entity = Self.correctionEntities.first(where: {
                  match.range(withName: $0.name).location != NSNotFound
              }),
              let valueRange = Range(match.range(withName: entity.name), in: text),
              let entityRegex = try? NSRegularExpression(pattern: "(?i)\(entity.pattern)")
        else { return text }

        let newValue = String(text[valueRange])
        let priorSearchRange = NSRange(text.startIndex..<correctionRange.lowerBound, in: text)
        guard let lastPrior = entityRegex.matches(in: text, range: priorSearchRange).last,
              let priorRange = Range(lastPrior.range, in: text)
        else { return text }

        var result = text
        result.removeSubrange(correctionRange)
        if correctionRange.lowerBound > result.startIndex,
           correctionRange.lowerBound < result.endIndex {
            let before = result.index(before: correctionRange.lowerBound)
            if !result[before].isWhitespace, !result[correctionRange.lowerBound].isWhitespace {
                result.insert(" ", at: correctionRange.lowerBound)
            }
        }
        result.replaceSubrange(priorRange, with: newValue)
        return result
    }

    /// Finds a correction lead-in immediately followed (allowing small
    /// connector words like "at" or "it's") by a structured value.
    private func firstPinpointCorrectionMatch(in text: String) -> NSTextCheckingResult? {
        let leadIn = Self.correctionLeadIns
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let connector = "(?:\\s*(?:it'?s|it|at|to|for|instead|make it))*"
        let alternatives = Self.correctionEntities
            .map { "(?<\($0.name)>\($0.pattern))" }
            .joined(separator: "|")
        let pattern = "(?i)\\b(?:\(leadIn))\\b\(connector)\\s*(?:\(alternatives))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Erases everything since the previous sentence whenever a cancel
    /// phrase (see `cancelPhrases`) is spoken, then removes the phrase
    /// itself — letting a dictation continue past a self-correction
    /// instead of forcing the recording to stop.
    private func applyCancelCommands(to text: String) -> String {
        var result = text
        while let range = firstCancelPhraseRange(in: result) {
            let start = sentenceStart(before: range.lowerBound, in: result)
            result.removeSubrange(start..<range.upperBound)
            if start > result.startIndex, start < result.endIndex {
                let before = result.index(before: start)
                if !result[before].isWhitespace, !result[start].isWhitespace {
                    result.insert(" ", at: start)
                }
            }
        }
        return result
    }

    /// Range of the earliest cancel phrase in `text`, including a trailing
    /// comma/period and any whitespace right after it.
    private func firstCancelPhraseRange(in text: String) -> Range<String.Index>? {
        let alternatives = Self.cancelPhrases
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?i)\\b(\(alternatives))\\b[,.!]?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return range
    }

    /// Walks back from `index` to just past the previous sentence
    /// terminator, or to the start of the text if there isn't one.
    private func sentenceStart(before index: String.Index, in text: String) -> String.Index {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if ".!?\n".contains(text[previous]) {
                return cursor
            }
            cursor = previous
        }
        return text.startIndex
    }

    private func applySpokenCommands(to text: String) -> String {
        var result = text
        let commands: [(pattern: String, replacement: String)] = [
            ("(?i)[,.]?\\s*\\bnew paragraph[,.]?\\s*", "\n\n"),
            ("(?i)[,.]?\\s*\\bnew ?line[,.]?\\s*", "\n"),
        ]
        for command in commands {
            result = result.replacingOccurrences(
                of: command.pattern, with: command.replacement,
                options: .regularExpression)
        }
        return result
    }

    private func applyDictionary(to text: String) -> String {
        var result = text
        for (spoken, replacement) in dictionary {
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            result = result.replacingOccurrences(
                of: "(?i)\\b\(escaped)\\b", with: replacement,
                options: .regularExpression)
        }
        return result
    }

    private func tidyWhitespaceAndPunctuation(in text: String) -> String {
        var result = text
        // Collapse runs of spaces/tabs (not newlines).
        result = result.replacingOccurrences(
            of: "[ \\t]+", with: " ", options: .regularExpression)
        // No space before closing punctuation.
        result = result.replacingOccurrences(
            of: " +([,.;:!?])", with: "$1", options: .regularExpression)
        // Collapse duplicate punctuation like ",." or ".." left by edits.
        result = result.replacingOccurrences(
            of: "([,.;:!?])[,.]", with: "$1", options: .regularExpression)
        // Trim each line.
        result = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        // At most one blank line in a row.
        result = result.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var characters = Array(text)
        var capitalizeNext = true
        for index in characters.indices {
            let character = characters[index]
            if capitalizeNext, character.isLetter {
                characters[index] = Character(character.uppercased())
                capitalizeNext = false
            } else if ".!?\n".contains(character) {
                capitalizeNext = true
            } else if !character.isWhitespace, !"\"'([{".contains(character) {
                capitalizeNext = false
            }
        }
        return String(characters)
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last else { return text }
        if last.isLetter || last.isNumber {
            return text + "."
        }
        return text
    }

    // MARK: - Self test

    static func runSelfTest() -> Bool {
        let formatter = TextFormatter(dictionary: ["jira": "Jira", "claude code": "Claude Code"])
        let cases: [(input: String, expected: String)] = [
            ("um hello world", "Hello world."),
            ("this is, uh, a test", "This is, a test."),
            ("first line new line second line", "First line\nSecond line."),
            ("intro new paragraph details here", "Intro\n\nDetails here."),
            ("file a ticket in jira today", "File a ticket in Jira today."),
            ("i use claude code daily", "I use Claude Code daily."),
            ("hello world. this is fine", "Hello world. This is fine."),
            ("  spaced   out   words ", "Spaced out words."),
            ("already punctuated!", "Already punctuated!"),
            ("my phone number is 555 scratch that its 867",
             "Its 867."),
            ("hello world never mind ignore that last part",
             "Ignore that last part."),
            ("i love pizza. actually scratch that i hate it",
             "I love pizza. I hate it."),
            ("call the client at 3pm and send the deck actually let's do 4pm",
             "Call the client at 4pm and send the deck."),
            ("the budget is 500 dollars actually make it 700 dollars",
             "The budget is 700 dollars."),
            ("let's meet on monday actually let's do tuesday",
             "Let's meet on tuesday."),
            ("please actually check the door before you leave",
             "Please actually check the door before you leave."),
            ("", ""),
        ]
        var passed = true
        for testCase in cases {
            let got = formatter.format(testCase.input)
            let ok = got == testCase.expected
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \"\(testCase.input)\" -> \"\(got)\"" +
                  (ok ? "" : " (expected \"\(testCase.expected)\")"))
        }

        let standaloneCases: [(input: String, expected: Bool)] = [
            ("nevermind", true),
            ("Nevermind.", true),
            ("scratch that", true),
            ("um, scratch that", true),
            ("go back", true),
            ("undo last sentence", true),
            ("I went to the store, nevermind", false),
            ("let's go back to the store", false),
            ("hello world", false),
            ("", false),
        ]
        for testCase in standaloneCases {
            let got = formatter.isStandaloneCancelPhrase(testCase.input)
            let ok = got == testCase.expected
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): isStandaloneCancelPhrase(\"\(testCase.input)\") -> \(got)" +
                  (ok ? "" : " (expected \(testCase.expected))"))
        }
        return passed
    }
}
