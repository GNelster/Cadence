import AppKit
import SwiftUI

/// Footprint of the pill itself (no live-text bubble) — fixed, so switching
/// between the waveform and processing-dots views never resizes or drifts
/// the window off-center. The panel grows taller than this, upward from a
/// constant bottom edge, only to fit the live partial-transcript bubble
/// when there's text to show; see `RecordingIndicatorController.resizePanel`.
private let basePanelSize = CGSize(width: 340, height: 76)

/// Floating, click-through pill that hovers just above the Dock while
/// dictation is active — a visual cue beyond the tiny menu bar icon.
@MainActor
final class RecordingIndicatorController {
    private var panel: NSPanel?
    private let model = IndicatorModel()
    /// The auto-hide scheduled by `flashUndo()`. Cancelled by `reveal()` so
    /// a new recording started right after an undo flash can't be yanked
    /// away mid-recording by that stale timer.
    private var pendingAutoHide: DispatchWorkItem?
    /// Bumped on every reveal()/hide() call; hide()'s animation completion
    /// only orders the panel out if this hasn't changed since it started.
    /// A fast double-tap can fire hide() (from the first tap's onCancel)
    /// and reveal() (from the second tap's onStart) within the same
    /// ~150ms animation window — without this guard, hide()'s delayed
    /// completion handler could order the panel out right after reveal()
    /// had already brought it back, making hands-free activation look
    /// like it silently failed.
    private var animationGeneration = 0

    func show(state: AppDelegate.UIState) {
        model.state = state == .processing ? .processing : .recording
        model.reset()
        model.partialText = ""
        reveal()
    }

    func updateState(_ state: AppDelegate.UIState) {
        model.state = state == .processing ? .processing : .recording
        if state == .processing {
            // The real transcript is what gets pasted, not this live
            // preview — don't leave a stale live guess on screen once
            // the authoritative pass takes over.
            model.partialText = ""
            resizePanel(animated: true)
        }
    }

    func updateLevel(_ level: Float) {
        model.pushLevel(level)
    }

    /// Updates the live partial-transcript preview shown above the pill.
    /// Grows (or shrinks) the panel to fit, up to `bubbleMaxLines`.
    func updatePartialText(_ text: String) {
        model.partialText = text
        resizePanel(animated: true)
    }

    /// Briefly shows an "Undone" badge confirming a standalone "scratch
    /// that" / "nevermind" recording reverted the previous dictation, then
    /// hides on its own — no separate hide() call needed.
    func flashUndo() {
        model.state = .undone
        reveal()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        pendingAutoHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }

    func hide() {
        pendingAutoHide?.cancel()
        pendingAutoHide = nil
        guard let panel, panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, self.animationGeneration == generation else { return }
            panel?.orderOut(nil)
        }
    }

    private func reveal() {
        // A recording (or another flash) starting now supersedes any
        // auto-hide a previous flashUndo() scheduled, and any in-flight
        // hide() animation whose completion hasn't fired yet.
        pendingAutoHide?.cancel()
        pendingAutoHide = nil
        animationGeneration += 1
        let panel = panel ?? makePanel()
        resizePanel(animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: IndicatorView(model: model))
        // Without this, the window tracks SwiftUI's ideal content size and
        // resizes (from its top-left corner) whenever the view's natural
        // size changes — which is what caused the pill to shrink and drift
        // left when switching between the waveform and processing views.
        // We drive the panel's size ourselves instead, via resizePanel(),
        // so the live-text bubble can still grow the window on purpose.
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: basePanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.setContentSize(basePanelSize)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    /// Font/metrics mirroring `partialTextBubble` in `IndicatorView` below —
    /// kept in sync manually since this measurement happens in AppKit
    /// (to size the actual window) while the view itself is drawn in
    /// SwiftUI. `bubbleMaxLines` caps how tall the panel can grow for a
    /// very long hands-free utterance; text beyond that is what SwiftUI's
    /// own `lineLimit` on `partialTextBubble` truncates.
    private let bubbleFont = NSFont.systemFont(ofSize: 15)
    private let bubbleMaxLines = 5
    private let bubbleHorizontalPadding: CGFloat = 32
    private let bubbleVerticalPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 300
    private let bubbleSpacing: CGFloat = 10

    private func bubbleHeight(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let lineHeight = (bubbleFont.ascender - bubbleFont.descender + bubbleFont.leading).rounded(.up)
        let maxTextHeight = lineHeight * CGFloat(bubbleMaxLines)
        let constraintWidth = bubbleMaxWidth - bubbleHorizontalPadding
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: constraintWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bubbleFont])
        let textHeight = min(bounding.height.rounded(.up), maxTextHeight)
        return textHeight + bubbleVerticalPadding
    }

    /// Resizes (and repositions) the panel to fit the current live-text
    /// bubble, if any, keeping the pill's bottom edge anchored at a
    /// constant spot above the Dock — the window grows upward, not the
    /// pill moving down, as the bubble gains lines.
    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let bubbleH = bubbleHeight(for: model.partialText)
        let extra = bubbleH > 0 ? bubbleH + bubbleSpacing : 0
        let newSize = CGSize(width: basePanelSize.width, height: basePanelSize.height + extra)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - newSize.width / 2, y: visible.minY + 14)
        let newFrame = NSRect(origin: origin, size: newSize)
        guard panel.frame != newFrame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }
}

enum IndicatorState {
    case recording, processing, undone
}

@MainActor
final class IndicatorModel: ObservableObject {
    @Published var state: IndicatorState = .recording
    @Published private(set) var bars: [Float]
    @Published var partialText: String = ""

    private let barCount = 20

    init() {
        bars = Array(repeating: 0.06, count: barCount)
    }

    func pushLevel(_ level: Float) {
        bars.removeFirst()
        bars.append(max(0.06, level))
    }

    func reset() {
        bars = Array(repeating: 0.06, count: barCount)
    }
}

struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        // Bottom-aligned within whatever frame the panel currently is: the
        // pill stays anchored to the bottom edge regardless of state
        // (narrower processing dots vs. wider waveform), and the panel
        // itself (sized by RecordingIndicatorController.resizePanel) grows
        // upward to fit the live-text bubble rather than this view trying
        // to sizing the window.
        VStack(spacing: 10) {
            if !model.partialText.isEmpty {
                partialTextBubble
            }
            pill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var partialTextBubble: some View {
        Text(model.partialText)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .lineLimit(5)
            .truncationMode(.head)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.iconGradient))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.15), value: model.partialText)
    }

    private var pill: some View {
        Group {
            switch model.state {
            case .processing:
                ProcessingDots()
            case .undone:
                UndoneBadge()
            case .recording:
                HStack(spacing: 3) {
                    ForEach(Array(model.bars.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 3, height: 6 + CGFloat(level) * 26)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: model.bars)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Palette.iconGradient))
        .overlay {
            // Only the "Undone" flash gets a border — it's a rarer,
            // momentary state worth visually calling out. The everyday
            // waveform/processing pills stay borderless.
            if model.state == .undone {
                Capsule().stroke(Color.orange.opacity(0.5), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

private struct UndoneBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
            Text("Undone")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.orange)
    }
}

private struct ProcessingDots: View {
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
