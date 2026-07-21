import AppKit
import SwiftUI

/// Fixed footprint for the indicator panel. Both the waveform and the
/// processing-dots views render inside this same size (rather than sizing
/// the window to each view's ideal content size) so the pill never resizes
/// or drifts off-center when the state changes.
private let indicatorPanelSize = CGSize(width: 200, height: 56)

/// Floating, click-through pill that hovers just above the Dock while
/// dictation is active — a visual cue beyond the tiny menu bar icon.
@MainActor
final class RecordingIndicatorController {
    private var panel: NSPanel?
    private let model = IndicatorModel()

    func show(state: AppDelegate.UIState) {
        model.state = state == .processing ? .processing : .recording
        model.reset()
        reveal()
    }

    func updateState(_ state: AppDelegate.UIState) {
        model.state = state == .processing ? .processing : .recording
    }

    func updateLevel(_ level: Float) {
        model.pushLevel(level)
    }

    /// Briefly shows an "Undone" badge confirming a standalone "scratch
    /// that" / "nevermind" recording reverted the previous dictation, then
    /// hides on its own — no separate hide() call needed.
    func flashUndo() {
        model.state = .undone
        reveal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.hide()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    private func reveal() {
        let panel = panel ?? makePanel()
        position(panel)
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
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: indicatorPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.setContentSize(indicatorPanelSize)
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

    /// Centers the pill just above the Dock (or above the screen edge, if the
    /// Dock is auto-hidden) on whichever screen currently has focus.
    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 14
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

enum IndicatorState {
    case recording, processing, undone
}

@MainActor
final class IndicatorModel: ObservableObject {
    @Published var state: IndicatorState = .recording
    @Published private(set) var bars: [Float]

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
        // Fixed outer footprint keeps both variants centered on the same
        // point — the pill inside can be narrower (processing dots) or
        // wider (waveform) without moving the window or drifting off-center.
        ZStack {
            pill
        }
        .frame(width: indicatorPanelSize.width, height: indicatorPanelSize.height)
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
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private var borderColor: Color {
        model.state == .undone ? Color.orange.opacity(0.5) : Color.white.opacity(0.15)
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
