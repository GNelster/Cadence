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
    case welcome, permissions, pushToTalk, handsFree, selfCorrect, done
}

struct OnboardingView: View {
    @ObservedObject var app: AppDelegate
    @State private var step: OnboardingStep = .welcome

    private let permissionTimer = Timer.publish(
        every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .pushToTalk: pushToTalkStep
                case .handsFree: handsFreeStep
                case .selfCorrect: selfCorrectStep
                case .done: doneStep
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
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
                .font(.system(size: 30, weight: .medium))
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
            Text("Two quick permissions")
                .font(.system(size: 26, weight: .medium))
            Text("Cadence needs these to hear you and to paste at your cursor.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                onboardingPermissionRow(
                    granted: app.micAuthorized, title: "Microphone",
                    pane: "Privacy_Microphone")
                onboardingPermissionRow(
                    granted: app.axTrusted, title: "Accessibility",
                    pane: "Privacy_Accessibility")
            }
            .frame(maxWidth: 380)
        }
    }

    private var pushToTalkStep: some View {
        stepCard(icon: "hand.tap", iconStyle: .neutral) {
            Text("Hold \(app.hotkey.displayName) to dictate")
                .font(.system(size: 26, weight: .medium))
            Text("Click into any text field, hold \(app.hotkey.displayName), " +
                 "speak, and release. Try it now — watch for the pill above " +
                 "your Dock while you hold it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    private var handsFreeStep: some View {
        stepCard(icon: "hands.and.sparkles", iconStyle: .neutral) {
            Text("Hands-free mode")
                .font(.system(size: 26, weight: .medium))
            Text("Double-tap \(app.hotkey.displayName) to keep recording " +
                 "without holding it down. Tap once more to stop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    private var selfCorrectStep: some View {
        stepCard(icon: "arrow.uturn.backward", iconStyle: .neutral) {
            Text("Correct yourself out loud")
                .font(.system(size: 26, weight: .medium))
            VStack(alignment: .leading, spacing: 10) {
                onboardingTipRow("“scratch that” / “never mind”",
                    "erases back to the start of that sentence")
                onboardingTipRow("“delete last word”",
                    "drops just the one word before it")
                onboardingTipRow("Say “scratch that” alone, right after",
                    "undoes the entire last paste, like ⌘Z")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private var doneStep: some View {
        stepCard(icon: "checkmark.circle", iconStyle: .neutral) {
            Text("You're all set")
                .font(.system(size: 26, weight: .medium))
            Text("Everything else — Styles, Snippets, Voice Training — is " +
                 "in the sidebar whenever you want it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Shared pieces

    private enum IconStyle { case brand, neutral }

    private func stepCard<Content: View>(
        icon: String, iconStyle: IconStyle, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 20) {
            Group {
                switch iconStyle {
                case .brand:
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Palette.iconGradient, in: RoundedRectangle(cornerRadius: 24))
                case .neutral:
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 72, height: 72)
                        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            content()
        }
        .padding(40)
    }

    private func onboardingPermissionRow(
        granted: Bool, title: String, pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
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
    }

    private func onboardingTipRow(_ phrase: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.caption)
                .foregroundStyle(Palette.accent)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = newIndex
        }
    }
}
