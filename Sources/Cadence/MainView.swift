import AppKit
import Speech
import SwiftUI

// MARK: - Palette (Cadence: warm paper, graphite accent, adaptive light/dark)

enum Palette {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark : light
        })
    }

    /// Warm backdrop behind the sidebar and panel.
    static let shell = dynamic(
        NSColor(red: 0.962, green: 0.954, blue: 0.940, alpha: 1),
        NSColor(red: 0.125, green: 0.123, blue: 0.118, alpha: 1))
    /// The main content sheet.
    static let panel = dynamic(
        .white,
        NSColor(red: 0.168, green: 0.165, blue: 0.160, alpha: 1))
    /// Cards on the sheet.
    static let card = dynamic(
        NSColor(red: 0.972, green: 0.965, blue: 0.952, alpha: 1),
        NSColor(red: 0.208, green: 0.204, blue: 0.198, alpha: 1))
    /// The promo banner — near-black charcoal in both modes, sampled from
    /// the app icon's own dark gradient stop.
    static let banner = dynamic(
        NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1),
        NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1))
    /// Soft graphite tint for callout cards.
    static let tint = dynamic(
        NSColor(red: 0.902, green: 0.910, blue: 0.925, alpha: 1),
        NSColor(red: 0.196, green: 0.208, blue: 0.227, alpha: 1))
    /// Primary text / filled buttons.
    static let ink = dynamic(
        NSColor(red: 0.13, green: 0.13, blue: 0.135, alpha: 1),
        NSColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1))
    /// Text on top of an ink-filled control.
    static let onInk = dynamic(
        .white,
        NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1))
    static let border = dynamic(
        NSColor.black.withAlphaComponent(0.08),
        NSColor.white.withAlphaComponent(0.12))
    /// Cadence's accent: a cool slate/graphite, matched to the app icon.
    static let accent = dynamic(
        NSColor(red: 0.32, green: 0.35, blue: 0.40, alpha: 1),
        NSColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1))
    /// The app icon's own graphite gradient — same top-to-bottom stops as
    /// scripts/make_icon.swift. Reused anywhere Cadence needs a recognizably
    /// "its own" dark surface (onboarding, the recording pill) rather than
    /// a generic black, same purpose as `banner` but with the icon's actual
    /// gradient instead of a flat fill.
    static let iconGradient = LinearGradient(
        colors: [
            Color(red: 0.40, green: 0.43, blue: 0.48),
            Color(red: 0.09, green: 0.10, blue: 0.12),
        ], startPoint: .top, endPoint: .bottom)
}

// MARK: - Shared page components

/// Centered icon + message for an empty list — used wherever a page's
/// primary content (dictionary entries, snippets, app rules, learned
/// corrections) hasn't been populated yet, instead of just an empty card.
struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Palette.accent.opacity(0.6))
            Text(title).font(.body.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// A small rounded tag — vocabulary hints, quick-reference labels.
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Palette.ink.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.tint, in: Capsule())
    }
}

/// Wraps chips left-to-right, moving to a new line when a chip won't fit.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                TagChip(text: item)
            }
        }
    }
}

/// Minimal flow layout: places subviews left-to-right, wrapping to a new
/// row when one would overflow the proposed width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: width.isFinite ? width : x, height: y)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// An installed app's actual icon, looked up by bundle ID — falls back to a
/// generic app-window glyph if the app can't be found. Used to make per-app
/// lists (Style overrides, dictation exclusions) more scannable at a glance.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = Self.icon(forBundleID: bundleID) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Pages

enum Page: Hashable {
    case insights, dictionary, training, snippets, style, transforms, scratchpad
    case settings, help

    var label: String {
        switch self {
        case .insights: return "Insights"
        case .dictionary: return "Dictionary"
        case .training: return "Voice Training"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .transforms: return "Transforms"
        case .scratchpad: return "Scratchpad"
        case .settings: return "Settings"
        case .help: return "Help"
        }
    }

    var icon: String {
        switch self {
        case .insights: return "chart.bar"
        case .dictionary: return "text.book.closed"
        case .training: return "waveform.badge.mic"
        case .snippets: return "scissors"
        case .style: return "textformat"
        case .transforms: return "wand.and.sparkles"
        case .scratchpad: return "square.and.pencil"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }

    static let mainItems: [Page] = [
        .insights, .dictionary, .training, .snippets, .style, .transforms,
        .scratchpad,
    ]
    static let bottomItems: [Page] = [.settings, .help]
}

// MARK: - Root

struct MainView: View {
    @ObservedObject var app: AppDelegate
    @State private var page: Page = .insights
    @State private var showSidebar = true

    private let permissionTimer = Timer.publish(
        every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(app: app, page: $page, showSidebar: $showSidebar)
                    .frame(width: 232)
            }
            mainPanel
        }
        .background(Palette.shell)
        .ignoresSafeArea()
        .onReceive(permissionTimer) { _ in app.refreshPermissions() }
        
    }

    private var mainPanel: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.panel)
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    pageContent
                        .padding(.horizontal, 56)
                        .padding(.bottom, 40)
                        .frame(maxWidth: 1100, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: showSidebar ? 0 : 6, bottom: 6, trailing: 6))
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            if !showSidebar {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSidebar = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 76)
            }
            Spacer()
            if let status = app.transformStatus {
                Label(status, systemImage: "wand.and.sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
            if let error = app.lastError, app.uiState == .idle {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 460, alignment: .trailing)
            }
            RecordingPill(app: app)
        }
        .padding(.top, 18)
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .insights: InsightsPage(app: app, page: $page)
        case .dictionary: DictionaryPage()
        case .training: TrainingPage(app: app)
        case .snippets: SnippetsPage()
        case .style: StylePage(app: app)
        case .transforms: TransformsPage(app: app)
        case .scratchpad: ScratchpadPage()
        case .settings: SettingsPage(app: app)
        case .help: HelpPage(app: app)
        }
    }
}

// MARK: - Recording status pill (top bar)

struct RecordingPill: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        Group {
            switch app.uiState {
            case .idle:
                EmptyView()
            case .recording:
                Label(app.isHandsFree ? "Recording — hands-free" : "Recording…",
                      systemImage: "waveform")
                    .foregroundStyle(.red)
            case .processing:
                Label("Transcribing…", systemImage: "hourglass")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.medium))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @Binding var showSidebar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSidebar = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Text("Cadence")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(Page.mainItems, id: \.self) { item in
                    navRow(item)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            wordsCard
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(Page.bottomItems, id: \.self) { item in
                    navRow(item, compact: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(Palette.shell)
    }

    private func navRow(_ item: Page, compact: Bool = false) -> some View {
        let selected = page == item
        return HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: compact ? 13 : 14))
                .frame(width: 20)
            Text(item.label)
                .font(.system(size: compact ? 13 : 14,
                              weight: selected ? .medium : .regular))
            Spacer()
        }
        .foregroundStyle(Palette.ink.opacity(selected ? 1 : 0.8))
        .padding(.vertical, compact ? 6 : 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Palette.panel : .clear)
                .shadow(color: selected ? .black.opacity(0.06) : .clear,
                        radius: 2, y: 1))
        .contentShape(Rectangle())
        .onTapGesture { page = item }
    }

    private var wordsCard: some View {
        let missingNames = [
            app.micAuthorized ? nil : "Microphone",
            app.axTrusted ? nil : "Accessibility",
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            if !missingNames.isEmpty {
                Text("\(missingNames.count) permission\(missingNames.count == 1 ? "" : "s") needed")
                    .font(.system(size: 14, weight: .semibold))
                Text("Grant \(missingNames.joined(separator: " and ")) to start dictating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { page = .settings } label: {
                    Text("Fix now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Text("Unlimited, always")
                    .font(.system(size: 14, weight: .semibold))
                Text("Every dictation runs on-device — no quotas, no " +
                     "subscription, nothing to track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { page = .help } label: {
                    Text("How it works")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Insights

struct InsightsPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Insights")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)

            voiceProfileHero

            HStack(spacing: 16) {
                tile("\(app.entries.count)", "dictations")
                tile(compact(totalWords), "total words")
                tile(avgWords, "avg words")
                tile(wpmText, "wpm")
                tile("\(dayStreak)", "day streak")
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Words per day — last 7 days")
                    .font(.headline)
                chart
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Voice Profile — the hero: your own persona, held in quotes

    private var voiceProfileHero: some View {
        ZStack {
            Image(systemName: "quote.opening")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.white.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 22)
                .padding(.top, 14)
            Image(systemName: "quote.closing")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.white.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 22)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE PROFILE")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .kerning(0.8)
                if let profile = app.voiceProfile {
                    Text(profile.title)
                        .font(.system(size: 28, design: .serif))
                        .italic()
                        .foregroundStyle(.white)
                    if !profile.summary.isEmpty {
                        Text(profile.summary)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Still listening…")
                        .font(.system(size: 28, design: .serif))
                        .italic()
                        .foregroundStyle(.white)
                    Text("Dictate a bit more and Cadence will sketch your " +
                         "persona from what you talk about.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    Text((Locale.current.localizedString(
                        forIdentifier: app.localeID) ?? app.localeID)
                        + " · Hold \(app.hotkey.displayName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Click to train your pronunciation")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                    if app.voiceProfile != nil {
                        Button {
                            app.refreshVoiceProfileIfDue(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh profile from your latest dictations")
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .frame(height: 190)
        .background(Palette.banner, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { page = .training }
    }

    // MARK: Stats

    private var totalWords: Int {
        app.entries.reduce(0) { $0 + $1.wordCount }
    }

    private var avgWords: String {
        app.entries.isEmpty ? "—" : "\(totalWords / app.entries.count)"
    }

    private var wpmText: String {
        let timed = app.entries.filter { ($0.duration ?? 0) > 1 }
        let seconds = timed.reduce(0.0) { $0 + ($1.duration ?? 0) }
        guard seconds > 0 else { return "—" }
        let words = timed.reduce(0) { $0 + $1.wordCount }
        return "\(Int(Double(words) / (seconds / 60)))"
    }

    private var dayStreak: Int {
        let calendar = Calendar.current
        let days = Set(app.entries.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    private func compact(_ number: Int) -> String {
        number >= 1000
            ? String(format: "%.1fK", Double(number) / 1000)
            : "\(number)"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, design: .serif))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var last7Days: [(day: Date, words: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let words = app.entries
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            return (day, words)
        }
    }

    private var chart: some View {
        let data = last7Days
        let maxWords = max(data.map(\.words).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(data, id: \.day) { point in
                VStack(spacing: 6) {
                    Text(point.words > 0 ? "\(point.words)" : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(point.words > 0 ? Palette.accent : Palette.border)
                        .frame(height: max(6,
                            CGFloat(point.words) / CGFloat(maxWords) * 140))
                    Text(point.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 190, alignment: .bottom)
    }
}

// MARK: - Dictionary

struct DictionaryPage: View {
    @State private var rows: [DictionaryRow] = []
    @State private var newSpoken = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dictionary")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("Spoken phrases are replaced in every transcript, " +
                 "so names and jargon come out spelled your way.")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                if rows.isEmpty {
                    EmptyState(
                        icon: "text.book.closed",
                        title: "No custom spellings yet",
                        detail: "Add a name or term below and Cadence will " +
                            "always spell it your way, in every dictation.")
                }
                ForEach($rows) { $row in
                    HStack {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Palette.accent)
                            .frame(width: 18)
                        TextField("spoken phrase", text: $row.spoken)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save() }
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("replacement", text: $row.replacement)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save() }
                        Button {
                            rows.removeAll { $0.id == row.id }
                            save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
                HStack {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    TextField("new spoken phrase", text: $newSpoken)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("replacement", text: $newReplacement)
                        .textFieldStyle(.roundedBorder)
                    Button { add() } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newSpoken.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .onAppear(perform: load)
    }

    private func add() {
        let spoken = newSpoken.trimmingCharacters(in: .whitespaces)
        guard !spoken.isEmpty else { return }
        rows.append(DictionaryRow(
            spoken: spoken,
            replacement: newReplacement.trimmingCharacters(in: .whitespaces)))
        newSpoken = ""
        newReplacement = ""
        save()
    }

    private func load() {
        rows = TextFormatter.loadDictionary()
            .sorted { $0.key < $1.key }
            .map { DictionaryRow(spoken: $0.key, replacement: $0.value) }
    }

    private func save() {
        var dictionary: [String: String] = [:]
        for row in rows {
            let spoken = row.spoken.trimmingCharacters(in: .whitespaces)
            if !spoken.isEmpty {
                dictionary[spoken] = row.replacement
            }
        }
        if let data = try? JSONEncoder().encode(dictionary) {
            try? data.write(to: TextFormatter.dictionaryURL, options: .atomic)
        }
    }
}

struct DictionaryRow: Identifiable {
    let id = UUID()
    var spoken: String
    var replacement: String
}

// MARK: - Scratchpad

struct ScratchpadPage: View {
    @State private var text = ""

    private var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("scratchpad.txt")
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Scratchpad")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("A place to park text. Saved automatically.")
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Jot something down, or dictate here — it saves " +
                         "automatically, without pasting into another app.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                        .padding(.leading, 21)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
            .frame(minHeight: 380)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            if !text.isEmpty {
                Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear {
            text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
        .onChange(of: text) { _, newValue in
            try? newValue.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var supportedLocaleIDs: [String] = []
    @State private var excludedApps: [String: String] = ExcludedAppsSettings.apps
    @State private var pickedExclusionBundleID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("General").font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Cadence at login")
                        Text("Starts automatically so the dictation key is always ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { app.launchAtLogin },
                        set: { app.setLaunchAtLogin($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions").font(.headline)
                permissionRow(
                    granted: app.micAuthorized,
                    title: "Microphone",
                    detail: "Required to hear your dictation.",
                    pane: "Privacy_Microphone")
                Divider()
                permissionRow(
                    granted: app.axTrusted,
                    title: "Accessibility",
                    detail: "Required for the global hotkey and pasting. " +
                            "Relaunch Cadence after granting.",
                    pane: "Privacy_Accessibility")
                if !app.axTrusted {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Toggle on in System Settings but still red here? " +
                             "The saved grant belongs to an older build. Click " +
                             "Reset Grant — the app relaunches, macOS asks once " +
                             "more, and the new grant sticks for all future updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset Grant & Relaunch") {
                            app.resetAccessibilityGrant()
                        }
                        Button("Relaunch") { app.relaunch() }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text("Dictation").font(.headline)
                HStack {
                    Text("Dictation key")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.hotkey },
                        set: { app.setHotkey($0) })) {
                        ForEach(HotkeyMonitor.Hotkey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.localeID },
                        set: { app.setLocale($0) })) {
                        ForEach(pickerLocaleIDs, id: \.self) { identifier in
                            Text(Locale.current.localizedString(
                                forIdentifier: identifier) ?? identifier)
                                .tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recognition engine")
                        Text(app.engine == "whisper"
                            ? "Whisper: best accuracy on accents and jargon; " +
                              "your vocabulary is fed to the model. Runs locally."
                            : "Apple: instant, built into macOS. Runs locally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.engine },
                        set: { app.setEngine($0) })) {
                        Text("Apple — instant").tag("apple")
                        Text("Whisper — precise").tag("whisper")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if app.engine == "whisper" {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Whisper model")
                            Text(app.whisperReady
                                ? "Model loaded — Whisper is transcribing your dictations."
                                : app.whisperEngine.isModelDownloaded(app.whisperModel)
                                    ? "Model downloaded — loading. Apple engine covers " +
                                      "dictations until it's ready."
                                    : "Downloading in the background. Apple engine covers " +
                                      "dictations until it's ready.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { app.whisperModel },
                            set: { app.setWhisperModel($0) })) {
                            ForEach(WhisperEngine.availableModels, id: \.id) { model in
                                Text(model.label).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text("Excluded apps").font(.headline)
                Text("The dictation key won't activate while one of these apps " +
                     "is frontmost — handy for password managers or anywhere " +
                     "you don't want Cadence listening.")
                    .font(.caption).foregroundStyle(.secondary)
                if excludedApps.isEmpty {
                    Text("No excluded apps.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(excludedApps.sorted(by: { $0.value < $1.value }),
                        id: \.key) { bundleID, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button {
                            excludedApps.removeValue(forKey: bundleID)
                            ExcludedAppsSettings.apps = excludedApps
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
                HStack {
                    Picker("", selection: $pickedExclusionBundleID) {
                        Text("Choose an app…").tag("")
                        ForEach(installedRegularApps(), id: \.bundleID) { appInfo in
                            Text(appInfo.name).tag(appInfo.bundleID)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Add") {
                        guard let appInfo = installedRegularApps().first(
                            where: { $0.bundleID == pickedExclusionBundleID })
                        else { return }
                        excludedApps[appInfo.bundleID] = appInfo.name
                        ExcludedAppsSettings.apps = excludedApps
                        pickedExclusionBundleID = ""
                    }
                    .disabled(pickedExclusionBundleID.isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .onAppear(perform: loadLocales)
    }

    private var pickerLocaleIDs: [String] {
        var ids = supportedLocaleIDs
        if !ids.contains(app.localeID) {
            ids.insert(app.localeID, at: 0)
        }
        return ids
    }

    private func loadLocales() {
        Task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = locales
                .map { $0.identifier(.bcp47) }
                .sorted {
                    (Locale.current.localizedString(forIdentifier: $0) ?? $0)
                    < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
                }
        }
    }

    private func permissionRow(
        granted: Bool, title: String, detail: String, pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings") {
                    let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Help

struct HelpPage: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Help")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 14) {
                helpRow("hand.tap", "Push-to-talk",
                    "Click into any text field, hold \(app.hotkey.displayName), speak, " +
                    "release. The cleaned-up text is pasted at your cursor.")
                Divider()
                helpRow("hands.and.sparkles", "Hands-free",
                    "Double-tap \(app.hotkey.displayName) to keep recording without " +
                    "holding. Tap once to stop.")
                Divider()
                helpRow("text.insert", "Voice commands",
                    "Say “new line” or “new paragraph” to add line breaks. " +
                    "Punctuation is added automatically from your pauses and tone.")
                Divider()
                helpRow("arrow.uturn.backward", "Self-correct mid-sentence",
                    "Slip up? Say “scratch that,” “never mind,” “strike that,” or " +
                    "“back up” to erase everything back to the start of that " +
                    "sentence — no need to release \(app.hotkey.displayName) and " +
                    "start over.")
                Divider()
                helpRow("pencil.and.outline", "Pinpoint corrections",
                    "For a quick fix to a time, date, day, or amount, just correct " +
                    "it in place: “the meeting's at 3pm — actually let's do 4pm” " +
                    "becomes “the meeting's at 4pm,” without touching the rest " +
                    "of the sentence.")
                Divider()
                helpRow("delete.left", "Delete last word",
                    "Said the wrong word? Say “delete last word” (or “scratch " +
                    "last word,” “undo last word”) to drop just that one word " +
                    "and keep going, without erasing the whole sentence.")
                Divider()
                helpRow("arrow.uturn.left.circle", "Undo the last paste",
                    "Hold \(app.hotkey.displayName) again and say only “scratch " +
                    "that” (or “never mind,” “go back”) with nothing else — " +
                    "Cadence undoes the previous paste, like ⌘Z.")
                Divider()
                helpRow("lock.shield", "Private by design",
                    "Recognition runs entirely on this Mac using Apple's on-device " +
                    "speech model. No audio or text ever leaves your machine.")
            }
            .padding(20)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New to Cadence?").font(.body.weight(.medium))
                    Text("Replay the first-run walkthrough — push-to-talk, " +
                         "hands-free, self-correct, and permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.replayOnboarding()
                } label: {
                    Label("View Onboarding", systemImage: "sparkles")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func helpRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Snippets

struct SnippetsPage: View {
    @State private var snippets: [Snippet] = []
    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Snippets")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("Say the trigger phrase while dictating and the whole block is " +
                 "inserted instead — signatures, addresses, meeting links, " +
                 "canned replies.")
                .foregroundStyle(.secondary)

            if snippets.isEmpty {
                EmptyState(
                    icon: "scissors",
                    title: "No snippets yet",
                    detail: "Save a signature, address, or canned reply below, " +
                        "then just say the trigger phrase while dictating.")
                .padding(20)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }

            ForEach($snippets) { $snippet in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "quote.bubble")
                            .foregroundStyle(Palette.accent)
                        TextField("trigger phrase (what you say)",
                                  text: $snippet.trigger)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save() }
                        Button {
                            snippets.removeAll { $0.id == snippet.id }
                            save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    TextEditor(text: $snippet.expansion)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 64)
                        .background(Palette.panel,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Palette.border, lineWidth: 1))
                        .onChange(of: snippet.expansion) { _, _ in save() }
                }
                .padding(16)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add new").font(.headline)
                TextField("trigger phrase (what you say)", text: $newTrigger)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newExpansion)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 64)
                    .background(Palette.panel,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Palette.border, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Add snippet") {
                        snippets.append(Snippet(
                            trigger: newTrigger.trimmingCharacters(in: .whitespaces),
                            expansion: newExpansion))
                        newTrigger = ""
                        newExpansion = ""
                        save()
                    }
                    .disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || newExpansion.isEmpty)
                }
            }
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .onAppear { snippets = SnippetStore.load() }
    }

    private func save() {
        SnippetStore.save(snippets.filter {
            !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty
        })
    }
}

// MARK: - Style

struct StylePage: View {
    @ObservedObject var app: AppDelegate
    @State private var defaultStyle: WritingStyle = StyleSettings.defaultStyle
    @State private var overrides: [String: AppStyleRule] = StyleSettings.overrides
    @State private var pickedBundleID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Style")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("Cadence adapts your tone to where you're writing — formal in docs, " +
                 "casual in chat. Rewriting runs on-device with Apple Intelligence.")
                .foregroundStyle(.secondary)

            if let note = app.rewriteEngine.availabilityNote {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(note).font(.callout)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Default style").font(.headline)
                Text("Used in every app unless overridden below.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $defaultStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: defaultStyle) { _, newValue in
                    StyleSettings.defaultStyle = newValue
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text("Per-app styles").font(.headline)
                if overrides.isEmpty {
                    EmptyState(
                        icon: "textformat",
                        title: "No app rules yet",
                        detail: "Pick an app below to give it its own tone — " +
                            "formal in your editor, casual in chat.")
                }
                ForEach(overrides.sorted(by: { $0.value.appName < $1.value.appName }),
                        id: \.key) { bundleID, rule in
                    HStack {
                        AppIconView(bundleID: bundleID)
                        Text(rule.appName)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { rule.style },
                            set: { newStyle in
                                overrides[bundleID] = AppStyleRule(
                                    appName: rule.appName, style: newStyle)
                                StyleSettings.overrides = overrides
                            })) {
                            ForEach(WritingStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button {
                            overrides.removeValue(forKey: bundleID)
                            StyleSettings.overrides = overrides
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
                HStack {
                    Picker("", selection: $pickedBundleID) {
                        Text("Choose an app…").tag("")
                        ForEach(runningApps, id: \.bundleID) { appInfo in
                            Text(appInfo.name).tag(appInfo.bundleID)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Add rule") {
                        guard let appInfo = runningApps.first(
                            where: { $0.bundleID == pickedBundleID }) else { return }
                        overrides[appInfo.bundleID] = AppStyleRule(
                            appName: appInfo.name, style: .casual)
                        StyleSettings.overrides = overrides
                        pickedBundleID = ""
                    }
                    .disabled(pickedBundleID.isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var runningApps: [(bundleID: String, name: String)] {
        installedRegularApps()
    }
}

/// All installed apps found in the standard Applications directories — not
/// just currently running ones — the pool offered when picking an app for a
/// per-app style override or a dictation exclusion. Reads each app bundle's
/// Info.plist directly rather than going through Spotlight/LaunchServices,
/// since Spotlight's index can be disabled or incomplete on some Macs.
/// Computed once per launch and cached, since scanning ~100+ .app bundles
/// on every SwiftUI re-render would be wasteful.
private let installedRegularAppsCache: [(bundleID: String, name: String)] =
    scanInstalledRegularApps()

private func installedRegularApps() -> [(bundleID: String, name: String)] {
    installedRegularAppsCache
}

private func scanInstalledRegularApps() -> [(bundleID: String, name: String)] {
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

// MARK: - Transforms

struct TransformsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var tryText = ""
    @State private var result = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Transforms")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("Select text in any app, press the shortcut, and it's rewritten " +
                 "in place — on-device.")
                .foregroundStyle(.secondary)

            if let note = app.rewriteEngine.availabilityNote {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(note).font(.callout)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Transform.all) { transform in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: transformIcon(for: transform))
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 34, height: 34)
                            .background(Palette.tint, in: RoundedRectangle(cornerRadius: 10))
                        Text(transform.keyLabel)
                            .font(.system(size: 13, weight: .semibold,
                                          design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Palette.panel,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Palette.border, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transform.name).font(.body.weight(.medium))
                            Text(transform.description)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if transform.id != Transform.all.last?.id {
                        Divider()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("Try it here").font(.headline)
                TextEditor(text: $tryText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 70)
                    .background(Palette.panel,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Palette.border, lineWidth: 1))
                HStack {
                    ForEach(Transform.all) { transform in
                        Button(transform.name) { runTransform(transform) }
                            .disabled(running || tryText.isEmpty
                                      || !app.rewriteEngine.isAvailable)
                    }
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if !result.isEmpty {
                    Text(result)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Palette.border, lineWidth: 1))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runTransform(_ transform: Transform) {
        running = true
        result = ""
        Task {
            defer { running = false }
            do {
                result = try await app.transformManager.apply(transform, to: tryText)
            } catch {
                result = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func transformIcon(for transform: Transform) -> String {
        switch transform.id {
        case "polish": return "sparkles"
        case "promptEngineer": return "wand.and.sparkles"
        default: return "text.badge.star"
        }
    }
}


// MARK: - Voice Training

/// Records a short sample, shows what the model heard, and saves the
/// misheard → intended mapping so Cadence learns the user's pronunciation.
@MainActor
final class TrainingModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var heard: String?
    @Published var result: String?

    private let recorder = AudioRecorder()

    func toggle(app: AppDelegate, target: String) {
        if isRecording {
            stop(app: app, target: target)
        } else {
            start()
        }
    }

    private func start() {
        heard = nil
        result = nil
        do {
            try recorder.start()
            isRecording = true
            NSSound(named: "Pop")?.play()
        } catch {
            result = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stop(app: AppDelegate, target: String) {
        isRecording = false
        guard let url = recorder.stop() else { return }
        NSSound(named: "Tink")?.play()
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let raw = try await app.transcribeRaw(fileAt: url)
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
                heard = cleaned.isEmpty ? nil : cleaned
                let intended = target.trimmingCharacters(in: .whitespaces)
                guard let heardText = heard else {
                    result = "Nothing was heard — try again, a bit louder."
                    return
                }
                if heardText.lowercased() == intended.lowercased() {
                    LearnedStore.addTerm(intended)
                    result = "Recognized correctly! Added “\(intended)” to your " +
                             "vocabulary so it stays reliable."
                } else {
                    LearnedStore.add(heard: heardText, intended: intended)
                    result = "Learned: “\(heardText)” → “\(intended)”. Cadence will " +
                             "make this correction automatically from now on."
                }
            } catch {
                result = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Small breathing red dot indicating an active recording, used where a
/// full waveform would be overkill.
struct PulsingDot: View {
    @State private var isLarge = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .scaleEffect(isLarge ? 1.3 : 0.8)
            .opacity(isLarge ? 1 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    isLarge = true
                }
            }
    }
}

struct TrainingPage: View {
    @ObservedObject var app: AppDelegate
    @StateObject private var model = TrainingModel()
    @State private var target = ""
    @State private var learned = LearnedStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Voice Training")
                .font(.system(size: 30, weight: .medium))
                .padding(.top, 24)
            Text("Teach Cadence how you pronounce names and jargon. Type a word, " +
                 "say it, and Cadence learns what it hears from you — the mapping " +
                 "is applied to every future dictation, and the word is fed to " +
                 "the speech model as expected vocabulary.")
                .foregroundStyle(.secondary)
            teachCard
            correctionsCard
        }
        .onAppear { learned = LearnedStore.load() }
    }

    private var teachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach a word or phrase").font(.headline)
            HStack(spacing: 10) {
                TextField("word or phrase, e.g. “Søren” or “Baseten”",
                          text: $target)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.toggle(app: app, target: target)
                } label: {
                    Label(model.isRecording ? "Stop" : "Record",
                          systemImage: model.isRecording
                            ? "stop.circle.fill" : "mic.circle.fill")
                        .foregroundStyle(model.isRecording ? .red : Palette.accent)
                }
                .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.isProcessing || !app.micAuthorized)
                if model.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            if model.isRecording {
                HStack(spacing: 8) {
                    PulsingDot()
                    Text("Say “\(target)” now, then press Stop.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            if let result = model.result {
                Text(result)
                    .font(.callout)
                    .foregroundStyle(Palette.accent)
                    .onAppear { learned = LearnedStore.load() }
            }
            Text("Tip: repeat a word 2–3 times — different mishearings each " +
                 "become their own correction.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var correctionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learned corrections").font(.headline)
            Text("Recorded here whenever you teach a word above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if learned.corrections.isEmpty {
                EmptyState(
                    icon: "waveform.badge.mic",
                    title: "Nothing learned yet",
                    detail: "Teach a word above, or correct a mistranscription " +
                        "and Cadence will remember it here.")
            } else {
                correctionsList
            }
            if !learned.terms.isEmpty {
                Text("Vocabulary hints").font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                FlowChips(items: learned.terms)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var correctionsList: some View {
        VStack(spacing: 8) {
            ForEach(learned.corrections.reversed()) { correction in
                correctionRow(correction)
            }
        }
    }

    private func correctionRow(_ correction: LearnedCorrection) -> some View {
        HStack {
            Text("“\(correction.heard)”")
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("“\(correction.intended)”")
                .fontWeight(.medium)
            if correction.timesSeen > 1 {
                Text("×\(correction.timesSeen)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.tint, in: Capsule())
            }
            Spacer()
            Button {
                var data = LearnedStore.load()
                data.corrections.removeAll { $0.id == correction.id }
                LearnedStore.save(data)
                learned = data
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}
