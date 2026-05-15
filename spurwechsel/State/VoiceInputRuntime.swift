import AVFoundation
import Foundation
import Speech
import os

@MainActor
final class VoiceInputRuntime {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "VoiceInput"
    )
    private static func trace(_ message: String) {
        #if DEBUG
        print("[voice-input-runtime] \(message)")
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<VoiceInputEvent>.Continuation?
    private var latestTranscription = ""
    private var deliveredTranscription = ""
    private var isStopping = false
    private var isAudioTapInstalled = false

    func start(sessionID: UUID) -> AsyncStream<VoiceInputEvent> {
        Self.trace("start requested session=\(sessionID.uuidString)")
        stop(emitStoppedEvent: false, reason: "restart-before-start")
        latestTranscription = ""
        deliveredTranscription = ""

        return AsyncStream { continuation in
            self.continuation = continuation
            Self.trace("stream opened session=\(sessionID.uuidString)")
            Task { @MainActor in
                await self.startRecognition()
            }
        }
    }

    func stop() {
        stop(emitStoppedEvent: true, reason: "explicit-stop")
    }

    private func startRecognition() async {
        Self.trace("start recognition begin")
        guard let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent) else {
            Self.trace("recognizer unavailable for locale")
            emit(.failed("Speech recognizer unavailable for current locale."))
            stop(emitStoppedEvent: true, reason: "recognizer-unavailable")
            return
        }
        guard recognizer.isAvailable else {
            Self.trace("recognizer currently unavailable")
            emit(.failed("Speech recognizer is currently unavailable."))
            stop(emitStoppedEvent: true, reason: "recognizer-offline")
            return
        }
        self.recognizer = recognizer

        let hasMicPermission = await requestMicrophonePermission()
        Self.trace("microphone permission granted=\(hasMicPermission)")
        guard hasMicPermission else {
            emit(.failed("Microphone permission denied."))
            stop(emitStoppedEvent: true, reason: "mic-permission-denied")
            return
        }

        let hasSpeechPermission = await requestSpeechPermission()
        Self.trace("speech permission granted=\(hasSpeechPermission)")
        guard hasSpeechPermission else {
            emit(.failed("Speech recognition permission denied."))
            stop(emitStoppedEvent: true, reason: "speech-permission-denied")
            return
        }

        do {
            try beginAudioCapture(with: recognizer)
            Self.trace("audio capture started")
        } catch {
            Self.trace("audio capture start failed error=\(error.localizedDescription)")
            emit(.failed("Unable to start voice input: \(error.localizedDescription)"))
            stop(emitStoppedEvent: true, reason: "audio-start-failed")
        }
    }

    private func beginAudioCapture(with recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        isAudioTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        Self.trace("audio engine running=\(audioEngine.isRunning)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            let fullText = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            latestTranscription = fullText
            Self.trace("recognition callback final=\(result.isFinal) chars=\(fullText.count)")
            emitAppendableDeltaIfPossible(fullText, isFinal: result.isFinal)
            if result.isFinal {
                latestTranscription = ""
                deliveredTranscription = ""
            }
        }

        guard let error, !isStopping else {
            return
        }
        Self.trace("recognition error=\(error.localizedDescription)")
        emit(.failed("Voice input stopped: \(error.localizedDescription)"))
        stop(emitStoppedEvent: true, reason: "recognition-error")
    }

    private func stop(emitStoppedEvent: Bool, reason: String) {
        Self.trace("stop begin emitStopped=\(emitStoppedEvent) reason=\(reason)")
        isStopping = true

        emitFinalRemainderIfNeeded()

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognizer = nil
        latestTranscription = ""
        deliveredTranscription = ""

        if emitStoppedEvent {
            Self.trace("emit stopped event")
            emit(.stopped)
        }
        continuation?.finish()
        continuation = nil

        isStopping = false
        Self.trace("stop complete")
    }

    private func emitAppendableDeltaIfPossible(_ fullText: String, isFinal: Bool) {
        guard !fullText.isEmpty else {
            return
        }
        guard let delta = voiceInputAppendableDelta(previous: deliveredTranscription, current: fullText) else {
            Self.trace("delta skipped non-appendable previousChars=\(deliveredTranscription.count) currentChars=\(fullText.count) final=\(isFinal)")
            return
        }
        guard !delta.isEmpty else {
            return
        }
        deliveredTranscription = fullText
        Self.trace("emit delta chars=\(delta.count) final=\(isFinal)")
        emit(.transcriptDelta(delta, isFinal: isFinal))
    }

    private func emitFinalRemainderIfNeeded() {
        let trimmed = latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let remainder = voiceInputAppendableDelta(previous: deliveredTranscription, current: trimmed),
              !remainder.isEmpty else {
            return
        }
        deliveredTranscription = trimmed
        Self.trace("emit final remainder chars=\(remainder.count)")
        emit(.transcriptDelta(remainder, isFinal: true))
    }

    private func emit(_ event: VoiceInputEvent) {
        continuation?.yield(event)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { resolvedStatus in
                    continuation.resume(returning: resolvedStatus == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

func voiceInputAppendableDelta(previous: String, current: String) -> String? {
    if previous.isEmpty {
        return current
    }
    guard current.hasPrefix(previous) else {
        return nil
    }
    return String(current.dropFirst(previous.count))
}
