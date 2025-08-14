import AVFoundation
import Foundation

public class AudioCapture: NSObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode
    private var audioFormat: AVAudioFormat
    private var recordingBuffer: [Float] = []
    private var isRecording = false

    public override init() {
        inputNode = audioEngine.inputNode
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        super.init()
    }

    public func startRecording() async throws {
        guard !isRecording else { return }

        let hasPermission = await AudioCapture.requestMicrophonePermission()
        guard hasPermission else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        recordingBuffer.removeAll()
        isRecording = true

        try await configureAudioSession()

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: audioFormat
        ) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            self.processAudioBuffer(buffer)
        }

        try audioEngine.start()
    }

    public func stopRecording() async throws -> Data {
        guard isRecording else {
            throw AudioCaptureError.notRecording
        }

        isRecording = false
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)

        try await deactivateAudioSession()

        return convertBufferToData(recordingBuffer)
    }

    public func recordAudio(duration: TimeInterval) async throws -> Data {
        try await startRecording()

        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        return try await stopRecording()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer(
            start: channelDataValue,
            count: channelDataCount
        ))

        recordingBuffer.append(contentsOf: samples)
    }

    private func convertBufferToData(_ buffer: [Float]) -> Data {
        let data = buffer.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
        return data
    }

    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    public static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public var isCurrentlyRecording: Bool {
        isRecording
    }

    public func getRecordingDuration() -> TimeInterval {
        Double(recordingBuffer.count) / 16000.0
    }
}

public enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case notRecording
    case audioEngineError(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable microphone access in Settings."
        case .notRecording:
            return "No active recording to stop."
        case .audioEngineError(let message):
            return "Audio engine error: \(message)"
        }
    }
}
