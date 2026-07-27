import SwiftUI

/// Root content of the main window: the first-run walkthrough until it's
/// completed once, then the dashboard from then on.
struct RootView: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        ZStack {
            if app.showOnboarding {
                OnboardingView(app: app)
                    .transition(.opacity)
            } else {
                MainView(app: app)
                    .transition(.opacity)
            }
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, pushToTalk, handsFree, selfCorrect, commandMode, done
}

struct OnboardingView: View {
    @ObservedObject var app: AppDelegate
    @State private var step: OnboardingStep = .welcome
    @State private var goingForward = true

    private let permissionTimer = Timer.publish(
        every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                QuoteWatermark()
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .pushToTalk: pushToTalkStep
                case .handsFree: handsFreeStep
                case .selfCorrect: selfCorrectStep
                case .commandMode: commandModeStep
                case .done: doneStep
                }
            }
            .id(step)
            .transition(goingForward
                ? .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
                : .asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)))
            .frame(maxWidth: 560, minHeight: 660)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            Spacer()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.shell)
        .onReceive(permissionTimer) { _ in app.refreshPermissions() }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        stepCard(icon: "quote.closing", iconStyle: .brand) {
            Text("Welcome to Cadence")
                .font(.system(size: 30, weight: .medium, design: .serif))
            Text("Private, unlimited voice dictation — 100% on-device. " +
                 "No cloud, no subscription, nothing leaves your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    private var permissionsStep: some View {
        stepCard(icon: "lock.shield", iconStyle: .neutral) {
            VStack(spacing: 6) {
                eyebrow("Permissions")
                Text("Two quick permissions")
                    .font(.system(size: 26, weight: .medium, design: .serif))
            }
            Text("Cadence needs these to hear you and to paste at your cursor.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                PermissionRow(
                    granted: app.micAuthorized, title: "Microphone",
                    pane: "Privacy_Microphone")
                PermissionRow(
                    granted: app.axTrusted, title: "Accessibility",
                    pane: "Privacy_Accessibility")
            }
            .frame(maxWidth: 380)
        }
    }

    private var pushToTalkStep: some View {
        stepCard(icon: "hand.tap", iconStyle: .neutral) {
            VStack(spacing: 6) {
                eyebrow("Push to talk")
                Text("Hold \(app.hotkey.displayName) to dictate")
                    .font(.system(size: 26, weight: .medium, design: .serif))
            }
            Text("Click into any text field, hold \(app.hotkey.displayName), " +
                 "speak, and release. Try it now — this is a live preview of " +
                 "the pill that shows above your Dock while you speak.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            OnboardingWaveform(state: app.uiState)
        }
    }

    private var handsFreeStep: some View {
        stepCard(icon: "hands.and.sparkles", iconStyle: .neutral) {
            VStack(spacing: 6) {
                eyebrow("Hands-free")
                Text("Hands-free mode")
                    .font(.system(size: 26, weight: .medium, design: .serif))
            }
            Text("Double-tap \(app.hotkey.displayName) to keep recording " +
                 "without holding it down. Tap once more to stop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if app.isHandsFree {
                HStack(spacing: 6) {
                    Image(systemName: "hands.and.sparkles")
                    Text("Hands-free active")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Palette.tint, in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: app.isHandsFree)
    }

    private var selfCorrectStep: some View {
        stepCard(icon: "arrow.uturn.backward", iconStyle: .neutral) {
            VStack(spacing: 6) {
                eyebrow("Self-correction")
                Text("Correct yourself out loud")
                    .font(.system(size: 26, weight: .medium, design: .serif))
            }
            SelfCorrectDemo()
                .frame(maxWidth: 380)
            VStack(spacing: 4) {
                Text("“scratch that” / “never mind”")
                    .font(.body.weight(.medium))
                Text("erases back to the start of that sentence")
                    .font(.caption).foregroundStyle(.secondary)
                Text("“delete last word”")
                    .font(.body.weight(.medium))
                    .padding(.top, 6)
                Text("drops just the one word before it")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Say “scratch that” alone, right after")
                    .font(.body.weight(.medium))
                    .padding(.top, 6)
                Text("undoes the entire last paste, like ⌘Z")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
    }

    private var commandModeStep: some View {
        stepCard(icon: "command", iconStyle: .neutral, lit: app.commandModeEnabled) {
            VStack(spacing: 6) {
                eyebrow("Command mode")
                Text("Say it, don't type it")
                    .font(.system(size: 26, weight: .medium, design: .serif))
            }
            Text("Switch tasks without reaching for the mouse or hunting " +
                 "through Launchpad — just say what you want.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command mode")
                    Text("Speak \"open Safari\" or \"select all\" to run commands " +
                         "instead of typing text. Off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.commandModeEnabled },
                    set: { app.setCommandModeEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            CommandModeDemo()
                .frame(maxWidth: 380)
            VStack(spacing: 4) {
                Text("“open Safari” / “switch to Mail”")
                    .font(.body.weight(.medium))
                Text("launches or brings an app to the front")
                    .font(.caption).foregroundStyle(.secondary)
                Text("“select all” / “new tab” / “delete that”")
                    .font(.body.weight(.medium))
                    .padding(.top, 6)
                Text("runs the matching shortcut in the frontmost app")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
    }

    private var doneStep: some View {
        stepCard(icon: "checkmark.circle", iconStyle: .neutral, celebratory: true) {
            Text("You're all set")
                .font(.system(size: 26, weight: .medium, design: .serif))
            Text("Everything else — Voice Training, Snippets, Style, " +
                 "Transforms, Dictionary, and Insights — is in the sidebar " +
                 "whenever you want it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Shared pieces

    /// A small tracked-caps label naming the current step — real structure,
    /// not decoration: onboarding is a genuine sequence of named topics, so
    /// this gives that sequence a legible label beyond the footer's dots.
    /// Left off the welcome/done bookends, which are the cover and closing
    /// screens rather than a labeled topic.
    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(1.6)
            .foregroundStyle(Palette.accent)
            .textCase(.uppercase)
    }

    private func stepCard<Content: View>(
        icon: String, iconStyle: IconStyle, lit: Bool = false, celebratory: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 20) {
            StepIcon(systemName: icon, style: iconStyle, lit: lit, celebratory: celebratory)
            content()
        }
        .padding(40)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                    Circle()
                        .fill(candidate == step ? Palette.accent : Palette.border)
                        .frame(width: 6, height: 6)
                }
            }
            HStack {
                if step != .welcome {
                    Button("Back") { advance(by: -1) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if step == .done {
                        app.completeOnboarding()
                    } else {
                        advance(by: 1)
                    }
                } label: {
                    Text(step == .done ? "Get Started" : "Continue")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
        }
        .padding(.bottom, 48)
    }

    private func advance(by delta: Int) {
        guard let newIndex = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        goingForward = delta > 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = newIndex
        }
    }
}

/// A permission row that celebrates a live ungranted→granted flip (driven
/// by `OnboardingView`'s permission-poll timer) with a bounce + symbol
/// swap, instead of silently updating the icon.
private struct PermissionRow: View {
    let granted: Bool
    let title: String
    let pane: String

    @State private var bump = false

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(granted ? .green : .red)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(bump ? 1.3 : 1)
            Text(title).font(.body.weight(.medium))
            Spacer()
            if !granted {
                Button("Open Settings") {
                    let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: granted) { _, newValue in
            guard newValue else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { bump = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) { bump = false }
        }
    }
}

/// A miniature preview of the real floating dictation pill
/// (`RecordingIndicator.swift`'s `IndicatorView`/bars), embedded inline in
/// onboarding so the push-to-talk/hands-free steps can react live to the
/// actual `AppDelegate.uiState`/`isHandsFree` if the user tries the hotkey
/// while reading — genuine state, though bar heights are self-animated
/// (there's no published mic-level stream to drive them literally). At
/// rest (`.idle`, the default before anyone presses anything) the bars
/// settle to a calm low level rather than looking empty or broken.
private struct OnboardingWaveform: View {
    let state: AppDelegate.UIState

    @State private var bars: [CGFloat] = Array(repeating: 0.1, count: 20)
    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if state == .processing {
                OnboardingProcessingDots()
            } else {
                HStack(spacing: 3) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 3, height: 6 + level * 26)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: bars)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Palette.iconGradient))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .onReceive(timer) { _ in
            if state == .recording {
                bars.removeFirst()
                bars.append(CGFloat.random(in: 0.15...1))
            } else {
                bars = bars.map { max(0.1, $0 * 0.7) }
            }
        }
    }
}

private struct OnboardingProcessingDots: View {
    @State private var activeIndex = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(activeIndex == i ? 1 : 0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .onReceive(timer) { _ in activeIndex = (activeIndex + 1) % 3 }
    }
}

/// A small scripted, looping demo of a self-correction: types a sentence,
/// flashes a "scratch that" moment, erases back to the correction point,
/// and retypes — illustrative rather than tied to real app state, since
/// there's no safe way to run actual dictation through onboarding. Runs
/// via `.task`, which cancels automatically when the step is torn down
/// (steps are re-inserted per `.id(step)` in `OnboardingView`).
private struct SelfCorrectDemo: View {
    @State private var typed = ""
    @State private var showingChip = false
    @State private var caretOn = true

    private let prefix = "Let's meet on "
    private let firstWord = "Tuesday"
    private let secondWord = "Wednesday"

    var body: some View {
        HStack(spacing: 4) {
            Text(typed)
                .font(.body.weight(.medium))
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 2, height: 16)
                .opacity(caretOn ? 1 : 0)
            Spacer(minLength: 0)
            if showingChip {
                Text("“scratch that”")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingChip)
        .frame(minHeight: 24)
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .task { await runLoop() }
        .task { await blinkCaret() }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            typed = ""
            await type(prefix + firstWord)
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation { showingChip = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await erase(to: prefix)
            withAnimation { showingChip = false }
            await type(secondWord)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await erase(to: "")
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    @MainActor
    private func type(_ text: String) async {
        for char in text {
            if Task.isCancelled { return }
            typed.append(char)
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
    }

    @MainActor
    private func erase(to target: String) async {
        while typed.count > target.count, !Task.isCancelled {
            typed.removeLast()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    @MainActor
    private func blinkCaret() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.5)) { caretOn.toggle() }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

/// A small scripted, looping preview of command mode: shows the spoken
/// phrase, then the corresponding action — a mock app launching for "open
/// Safari," a mock text selection for "select all" — so the step
/// demonstrates the feature rather than only describing it. Illustrative,
/// like `SelfCorrectDemo`: no real command actually runs during onboarding.
private struct CommandModeDemo: View {
    @State private var spoken = ""
    @State private var appLaunched = false
    @State private var textSelected = false
    @State private var showingSelect = false

    private let sampleText = "Let's ship this Friday"

    var body: some View {
        VStack(spacing: 14) {
            Text(spoken.isEmpty ? " " : "“\(spoken)”")
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 20)

            ZStack {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(i == 1 && appLaunched
                                ? AnyShapeStyle(Palette.iconGradient)
                                : AnyShapeStyle(Palette.tint))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if i == 1 {
                                    Image(systemName: "safari")
                                        .foregroundStyle(appLaunched ? .white : Palette.accent)
                                }
                            }
                            .scaleEffect(i == 1 && appLaunched ? 1.15 : 1)
                    }
                }
                .opacity(showingSelect ? 0 : 1)

                Text(sampleText)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        textSelected ? Palette.accent.opacity(0.3) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4))
                    .opacity(showingSelect ? 1 : 0)
            }
            .frame(height: 44)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appLaunched)
            .animation(.easeOut(duration: 0.3), value: textSelected)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .task { await runLoop() }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            showingSelect = false
            appLaunched = false
            await type("open Safari")
            try? await Task.sleep(nanoseconds: 400_000_000)
            appLaunched = true
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            spoken = ""
            try? await Task.sleep(nanoseconds: 400_000_000)

            showingSelect = true
            textSelected = false
            await type("select all")
            try? await Task.sleep(nanoseconds: 400_000_000)
            textSelected = true
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            spoken = ""
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    @MainActor
    private func type(_ text: String) async {
        spoken = ""
        for char in text {
            if Task.isCancelled { return }
            spoken.append(char)
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
    }
}

/// Onboarding's signature: an oversized editorial quotation mark, echoing
/// the "quote.closing" glyph on the welcome step's own icon and the app's
/// core act — turning what you say into quoted text. Sits low-opacity
/// behind every step, clipped to the panel, tying the whole walkthrough
/// back to the one thing Cadence actually does.
private struct QuoteWatermark: View {
    var body: some View {
        Text("\u{201D}")
            .font(.system(size: 200, weight: .bold, design: .serif))
            .foregroundStyle(Palette.accent.opacity(0.07))
            .padding(.top, 4)
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

private enum IconStyle { case brand, neutral }

/// The rounded-rect icon badge shared by every onboarding step. Because
/// each step's content is torn down and re-inserted (keyed by `.id(step)`
/// in `OnboardingView`), this view's `.onAppear` fires fresh on every
/// step change — giving every step a subtle entrance pop without any
/// per-step state in `OnboardingView` itself.
private struct StepIcon: View {
    let systemName: String
    let style: IconStyle
    var lit: Bool = false
    var celebratory: Bool = false

    @State private var appeared = false
    @State private var glow = false

    private var filled: Bool { style == .brand || lit }
    private var size: CGFloat { style == .brand ? 96 : 72 }
    private var cornerRadius: CGFloat { style == .brand ? 24 : 20 }
    private var fontSize: CGFloat { style == .brand ? 40 : 30 }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: style == .brand ? .bold : .medium))
            .foregroundStyle(filled ? .white : Palette.accent)
            .frame(width: size, height: size)
            .background(
                filled ? AnyShapeStyle(Palette.iconGradient) : AnyShapeStyle(Palette.tint),
                in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Palette.accent.opacity(glow ? 0.5 : 0), radius: glow ? 18 : 0)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: lit)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    appeared = true
                }
                if celebratory {
                    withAnimation(.easeOut(duration: 0.35).delay(0.15)) { glow = true }
                    withAnimation(.easeIn(duration: 0.5).delay(0.7)) { glow = false }
                }
            }
    }
}
