import AVFoundation
import Foundation

/// Captures microphone audio into a temporary file while the hotkey is held.
///
/// Deliberately simple: the engine starts on key-down and stops on release.
/// Two "improvements" were tried and reverted after breaking things:
/// - setVoiceProcessingEnabled: its echo canceller ducks/mutes other apps'
///   audio system-wide and can feed the recognizer silence.
/// - A warm always-on engine with a pre-roll ring buffer: wedged the engine
///   so recording never started.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var currentFileURL: URL?
    private(set) var isRecording = false

    /// Fires on the main thread with a normalized 0...1 input level for
    /// every tap buffer, so callers can drive a live waveform UI.
    var onLevel: ((Float) -> Void)?

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "Cadence", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-\(UUID().uuidString).caf")
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
            self?.emitLevel(from: buffer)
        }

        file = audioFile
        currentFileURL = url
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops recording and returns the captured audio file URL,
    /// or nil if nothing was recorded.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        file = nil
        let url = currentFileURL
        currentFileURL = nil
        return url
    }

    /// Stops and deletes the in-progress recording.
    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Root-mean-square of the buffer, boosted and clamped to 0...1 so quiet
    /// speech still registers visibly in the waveform UI.
    private func emitLevel(from buffer: AVAudioPCMBuffer) {
        guard let onLevel, let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += samples[i] * samples[i]
        }
        let rms = (sum / Float(frameLength)).squareRoot()
        let level = min(1, rms * 12)
        DispatchQueue.main.async {
            onLevel(level)
        }
    }
}
