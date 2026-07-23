import AVFAudio
import Foundation
import Speech

/// Streams microphone audio into SpeechAnalyzer/SpeechTranscriber live,
/// while still recording — unlike Transcriber, which only transcribes a
/// finished file after the key is released. Purely a visual preview: the
/// real, authoritative transcript still comes from the existing
/// after-the-fact path (Transcriber or WhisperEngine), so if anything here
/// fails, dictation itself is completely unaffected — the live text simply
/// doesn't appear.
///
/// A fresh SpeechAnalyzer/SpeechTranscriber pair is created per recording,
/// same as the existing file-based Transcriber does per transcription —
/// no persistent state to manage across sessions.
final class LiveTranscriber {

    /// Fires on the main thread with the running partial transcript,
    /// replacing the previous value each time (analyzer results can revise
    /// earlier words as more audio arrives, so this isn't append-only).
    var onPartialText: ((String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var loggedFirstFeed = false
    private var droppedFeedCount = 0

    /// Debug-only tracing. Compiled out entirely in release builds (what
    /// ships) — this can include the live partial transcript itself, and
    /// Cadence's whole pitch is that dictation content never leaves the
    /// device, including into Console/log files.
    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[LiveTranscriber] \(message())\n".utf8))
        #endif
    }

    /// Begins a new live-transcription session. Best-effort: if the
    /// compatible audio format can't be determined, this quietly does
    /// nothing, and `feed(_:)` calls become no-ops.
    func start(locale: Locale, biasTerms: [String]) async {
        log("start() called, locale=\(locale.identifier)")
        loggedFirstFeed = false
        droppedFeedCount = 0
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber])
        else {
            log("bestAvailableAudioFormat returned nil — aborting")
            return
        }
        log("bestAvailableAudioFormat = \(format)")
        analyzerFormat = format

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        if !biasTerms.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: biasTerms]
            do {
                try await analyzer.setContext(context)
            } catch {
                log("setContext threw: \(error)")
            }
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            self?.log("results loop starting")
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.log("result: isFinal=\(result.isFinal) text=\"\(text)\"")
                    await MainActor.run { self?.onPartialText?(text) }
                }
                self?.log("results loop ended normally")
            } catch {
                self?.log("results loop threw: \(error)")
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
            log("analyzer.start(inputSequence:) returned")
        } catch {
            log("analyzer.start(inputSequence:) threw: \(error)")
        }
    }

    /// Feeds one raw tap buffer in. Safe to call from the audio thread —
    /// converts to the analyzer's required format and yields into the
    /// stream, which is documented safe for concurrent/cross-thread use.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation, let analyzerFormat else {
            droppedFeedCount += 1
            if droppedFeedCount == 1 || droppedFeedCount % 50 == 0 {
                log("feed() dropped (no continuation/format yet) — count=\(droppedFeedCount)")
            }
            return
        }
        guard let converted = convert(buffer, to: analyzerFormat) else {
            log("feed() buffer conversion failed")
            return
        }
        if !loggedFirstFeed {
            loggedFirstFeed = true
            log("feed() first successful buffer yielded, native format=\(buffer.format)")
        }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Ends the session. Fire-and-forget: the caller doesn't need to wait
    /// on this, since the live preview is purely decorative.
    func stop() {
        inputContinuation?.finish()
        inputContinuation = nil
        converter = nil
        analyzerFormat = nil
        let analyzer = analyzer
        self.analyzer = nil
        let resultsTask = resultsTask
        self.resultsTask = nil
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            resultsTask?.cancel()
        }
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }

        var conversionError: NSError?
        var suppliedInput = false
        converter.convert(to: output, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }
}
