//
//  AudioService.swift
//  LocalAIPlayground
//
//  =============================================================================
//  AUDIO SERVICE - MICROPHONE & AUDIO MANAGEMENT
//  =============================================================================
//
//  This service provides audio capture and playback capabilities for the app:
//
//  1. Microphone Recording - Capture audio for speech-to-text
//  2. Audio Playback      - Play synthesized speech from TTS
//  3. Audio Level Metering - Real-time audio level for visualizations
//  4. Audio Session Setup  - Configure iOS audio session properly
//
//  AUDIO SPECIFICATIONS:
//  ┌──────────────────┬─────────────────────────────────────────┐
//  │ Parameter        │ Value                                   │
//  ├──────────────────┼─────────────────────────────────────────┤
//  │ Sample Rate      │ 16000 Hz (required by Whisper STT)      │
//  │ Channels         │ Mono (1 channel)                        │
//  │ Bit Depth        │ 16-bit signed integer                   │
//  │ Format           │ Linear PCM                              │
//  └──────────────────┴─────────────────────────────────────────┘
//
//  PERMISSIONS REQUIRED:
//  - NSMicrophoneUsageDescription in Info.plist
//  - NSSpeechRecognitionUsageDescription (optional, for system STT)
//
//  =============================================================================

import Foundation
import SwiftUI
import AVFoundation
import Combine

// =============================================================================
// MARK: - Audio State
// =============================================================================
/// Represents the current state of audio capture/playback.
// =============================================================================
enum AudioState: Equatable {
    /// Audio system is idle
    case idle
    
    /// Currently recording from microphone
    case recording
    
    /// Currently playing audio
    case playing
    
    /// An error occurred
    case error(message: String)
}

// =============================================================================
// MARK: - Audio Service
// =============================================================================
/// Centralized service for audio capture and playback.
///
/// This service manages all audio-related functionality including microphone
/// recording for STT and audio playback for TTS output.
///
/// ## Usage Example
/// ```swift
/// let audioService = AudioService.shared
///
/// // Start recording
/// try await audioService.startRecording()
///
/// // Stop and get audio data
/// let audioData = try await audioService.stopRecording()
///
/// // Use with RunAnywhere STT
/// let transcription = try await RunAnywhere.transcribe(audioData)
/// ```
// =============================================================================
@MainActor
class AudioService: NSObject, ObservableObject {
    
    // -------------------------------------------------------------------------
    // MARK: - Singleton
    // -------------------------------------------------------------------------
    /// Shared instance for app-wide audio management.
    static let shared = AudioService()
    
    // -------------------------------------------------------------------------
    // MARK: - Published State
    // -------------------------------------------------------------------------
    /// Current state of the audio system
    @Published var state: AudioState = .idle
    
    /// Current audio input level (0.0 to 1.0) for visualizations
    @Published var inputLevel: Float = 0
    
    /// Current audio output level (0.0 to 1.0) for visualizations
    @Published var outputLevel: Float = 0
    
    /// Whether microphone permission has been granted
    @Published var hasPermission: Bool = false
    
    /// Duration of current recording in seconds
    @Published var recordingDuration: TimeInterval = 0
    
    // -------------------------------------------------------------------------
    // MARK: - Private Properties
    // -------------------------------------------------------------------------
    
    /// Audio engine for recording
    private var audioEngine: AVAudioEngine?
    
    /// Buffer to accumulate recorded audio
    private var audioBuffer: AVAudioPCMBuffer?
    
    /// Collected audio samples during recording
    private var recordedSamples: [Float] = []
    
    /// Audio player for TTS output
    private var audioPlayer: AVAudioPlayer?
    
    /// Timer for updating recording duration
    private var recordingTimer: Timer?
    
    /// Start time of current recording
    private var recordingStartTime: Date?
    
    /// Timer for metering audio levels
    private var meteringTimer: Timer?
    
    /// Native sample rate of the microphone (for resampling)
    private var nativeSampleRate: Double = 48000
    
    // -------------------------------------------------------------------------
    // MARK: - Audio Format Constants
    // -------------------------------------------------------------------------
    // These match the requirements of the Whisper STT model
    // -------------------------------------------------------------------------
    
    /// Sample rate required by Whisper STT (16 kHz)
    private let sampleRate: Double = 16000
    
    /// Number of audio channels (mono)
    private let channelCount: AVAudioChannelCount = 1
    
    /// Audio format for recording
    private var recordingFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Initialization
    // -------------------------------------------------------------------------
    private override init() {
        super.init()
        checkPermission()
    }
    
    // =========================================================================
    // MARK: - Permission Management
    // =========================================================================
    
    /// Checks current microphone permission status.
    // -------------------------------------------------------------------------
    func checkPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            hasPermission = true
        case .denied, .undetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }
    
    /// Requests microphone permission from the user.
    ///
    /// - Returns: `true` if permission was granted, `false` otherwise
    // -------------------------------------------------------------------------
    func requestPermission() async -> Bool {
        // -----------------------------------------------------------------
        // Request Microphone Permission
        // -----------------------------------------------------------------
        // iOS requires explicit user consent before accessing the microphone.
        // The permission prompt will show the message from Info.plist key:
        // NSMicrophoneUsageDescription
        // -----------------------------------------------------------------
        let granted = await AVAudioApplication.requestRecordPermission()
        
        await MainActor.run {
            hasPermission = granted
        }
        
        if granted {
            print("✅ Microphone permission granted")
        } else {
            print("❌ Microphone permission denied")
        }
        
        return granted
    }
    
    // =========================================================================
    // MARK: - Audio Session Configuration
    // =========================================================================
    
    /// Configures the audio session for recording.
    ///
    /// Sets up the audio session with appropriate category and options for
    /// voice recording with potential playback.
    // -------------------------------------------------------------------------
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        // -----------------------------------------------------------------
        // Configure Audio Session Category
        // -----------------------------------------------------------------
        // .playAndRecord: Allows both recording and playback
        // .defaultToSpeaker: Routes audio to speaker instead of earpiece
        // .allowBluetooth: Enables Bluetooth headset support
        // -----------------------------------------------------------------
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        
        // Activate the session
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        print("🎙️ Audio session configured for recording")
    }
    
    /// Configures the audio session for playback only.
    // -------------------------------------------------------------------------
    private func configureAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        print("🔊 Audio session configured for playback")
    }
    
    // =========================================================================
    // MARK: - Recording
    // =========================================================================
    
    /// Audio converter for resampling
    private var audioConverter: AVAudioConverter?
    
    /// Target format for STT (16kHz, mono, Int16)
    private var targetFormat: AVAudioFormat?
    
    /// Buffer to accumulate converted audio
    private var convertedBuffers: [AVAudioPCMBuffer] = []
    
    /// Starts recording audio from the microphone.
    ///
    /// The audio is captured and converted to 16kHz mono for Whisper STT.
    ///
    /// - Throws: An error if recording cannot be started
    // -------------------------------------------------------------------------
    func startRecording() async throws {
        // Ensure we have permission
        if !hasPermission {
            let granted = await requestPermission()
            if !granted {
                throw AudioError.permissionDenied
            }
        }
        
        // Configure audio session - request 16kHz if possible
        try configureAudioSession()
        
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineInitFailed
        }
        
        // Get input node (microphone)
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ Microphone format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch, \(inputFormat.commonFormat.rawValue)")
        
        // Create target format: 16kHz, mono, Int16
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            throw AudioError.formatError
        }
        targetFormat = target
        
        // Create converter from input to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            print("❌ Could not create audio converter")
            throw AudioError.formatError
        }
        audioConverter = converter
        
        // Clear buffers
        convertedBuffers = []
        recordedSamples = []
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, time in
            self?.processAndConvertBuffer(buffer)
        }
        
        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Update state
        state = .recording
        recordingStartTime = Date()
        startRecordingTimer()
        
        print("🎙️ Recording started (will convert to 16kHz Int16)")
    }
    
    /// Processes and converts incoming audio buffer to 16kHz Int16.
    // -------------------------------------------------------------------------
    private func processAndConvertBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter,
              let targetFormat = targetFormat else { return }
        
        // Calculate output frame count based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .haveData || status == .inputRanDry {
            // Store converted buffer
            DispatchQueue.main.async { [weak self] in
                self?.convertedBuffers.append(outputBuffer)
                
                // Calculate level for visualization from original buffer
                if let channelData = buffer.floatChannelData {
                    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
                    if !samples.isEmpty {
                        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
                        self?.inputLevel = min(rms * 5, 1.0)
                    }
                }
            }
        } else if let error = error {
            print("❌ Conversion error: \(error)")
        }
    }
    
    /// Stops recording and returns the captured audio data.
    ///
    /// - Returns: Audio data in 16kHz mono Int16 PCM format
    /// - Throws: An error if recording fails
    // -------------------------------------------------------------------------
    func stopRecording() async throws -> Data {
        guard state == .recording else {
            throw AudioError.notRecording
        }
        
        // Stop the audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        
        // Stop timers
        stopRecordingTimer()
        
        // Update state
        state = .idle
        inputLevel = 0
        
        print("🎙️ Recording stopped. Buffers: \(convertedBuffers.count)")
        
        // Combine all converted buffers into one Data
        var audioData = Data()
        for buffer in convertedBuffers {
            if let int16Data = buffer.int16ChannelData {
                let frameLength = Int(buffer.frameLength)
                let samples = UnsafeBufferPointer(start: int16Data[0], count: frameLength)
                for sample in samples {
                    audioData.append(contentsOf: sample.littleEndianBytes)
                }
            }
        }
        
        // Clear buffers
        convertedBuffers = []
        recordedSamples = []
        
        print("🎙️ Final audio: \(audioData.count) bytes (16kHz Int16 PCM)")
        return audioData
    }
    
    /// Converts Float32 samples to Int16 Data (standard for Whisper STT).
    // -------------------------------------------------------------------------
    private func convertSamplesToInt16Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        
        for sample in samples {
            // Clamp to -1.0...1.0 and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: int16Value.littleEndianBytes)
        }
        
        return data
    }
    
    /// Converts Float32 samples to Float32 Data (alternative format).
    // -------------------------------------------------------------------------
    private func convertSamplesToFloat32Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 4)
        
        for sample in samples {
            var value = sample
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    /// Cancels the current recording without returning data.
    // -------------------------------------------------------------------------
    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        stopRecordingTimer()
        
        state = .idle
        inputLevel = 0
        recordedSamples = []
        
        print("🎙️ Recording cancelled")
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Recording Timer
    // -------------------------------------------------------------------------
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        recordingStartTime = nil
    }
    
    // =========================================================================
    // MARK: - Audio Playback
    // =========================================================================
    
    /// Plays audio data (e.g., from TTS synthesis).
    ///
    /// - Parameter data: Audio data to play. Can be WAV or raw PCM (will auto-detect).
    /// - Parameter sampleRate: Sample rate for raw PCM data (default 22050 Hz for Piper TTS)
    /// - Throws: An error if playback fails
    // -------------------------------------------------------------------------
    func playAudio(_ data: Data, sampleRate: Int = 22050) throws {
        // Configure for playback
        try configureAudioSessionForPlayback()
        
        // Log the first few bytes to help debug format
        let headerBytes = data.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("🔊 Audio data header: \(headerBytes)")
        print("🔊 Audio data size: \(data.count) bytes")
        
        // Check if data already has WAV header (starts with "RIFF")
        let isWAV = data.count > 4 && data.prefix(4) == Data("RIFF".utf8)
        
        let audioData: Data
        if isWAV {
            // Already WAV format - use as-is
            audioData = data
            print("🔊 Audio is WAV format")
        } else {
            // Piper TTS outputs Float32 PCM - convert to Int16 WAV
            let int16Data = convertFloat32ToInt16(data)
            audioData = createWAVFile(from: int16Data, sampleRate: sampleRate)
            print("🔊 Converted Float32 to Int16 WAV (\(sampleRate) Hz)")
        }
        
        // Write to temp file (AVAudioPlayer is more reliable with files)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts_output_\(UUID().uuidString).wav")
        try audioData.write(to: tempURL)
        print("🔊 Wrote audio to: \(tempURL.lastPathComponent)")
        
        // Create player from file
        audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
        audioPlayer?.delegate = self
        audioPlayer?.isMeteringEnabled = true
        audioPlayer?.prepareToPlay()
        
        // Start playback
        let success = audioPlayer?.play() ?? false
        if success {
            state = .playing
            startMeteringTimer()
            print("🔊 Playback started")
        } else {
            throw AudioError.playbackFailed
        }
        
        // Clean up temp file after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    /// Converts Float32 PCM audio samples to Int16 PCM.
    ///
    /// Piper TTS outputs 32-bit float samples (-1.0 to 1.0).
    /// AVAudioPlayer needs 16-bit signed integer PCM.
    // -------------------------------------------------------------------------
    private func convertFloat32ToInt16(_ floatData: Data) -> Data {
        // Float32 = 4 bytes per sample
        let sampleCount = floatData.count / 4
        var int16Data = Data(capacity: sampleCount * 2)
        
        floatData.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            
            for i in 0..<sampleCount {
                let floatSample = floatBuffer[i]
                // Clamp to -1.0...1.0 and convert to Int16
                let clamped = max(-1.0, min(1.0, floatSample))
                let int16Sample = Int16(clamped * Float(Int16.max))
                
                // Append as little-endian
                int16Data.append(contentsOf: int16Sample.littleEndianBytes)
            }
        }
        
        print("🔊 Converted \(sampleCount) float samples to int16")
        return int16Data
    }
    
    /// Creates a complete WAV file from raw PCM audio data.
    ///
    /// - Parameters:
    ///   - pcmData: Raw PCM audio samples (16-bit signed integer, mono)
    ///   - sampleRate: Sample rate in Hz (e.g., 22050 for Piper TTS medium)
    /// - Returns: Complete WAV file data with proper header
    // -------------------------------------------------------------------------
    private func createWAVFile(from pcmData: Data, sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(pcmData.count)
        let chunkSize: UInt32 = 36 + subchunk2Size
        
        var wavData = Data()
        
        // RIFF chunk descriptor
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wavData.append(contentsOf: chunkSize.littleEndianBytes)
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt sub-chunk
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wavData.append(contentsOf: UInt32(16).littleEndianBytes) // Subchunk1Size (16 for PCM)
        wavData.append(contentsOf: UInt16(1).littleEndianBytes)  // AudioFormat (1 = PCM)
        wavData.append(contentsOf: numChannels.littleEndianBytes)
        wavData.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        wavData.append(contentsOf: byteRate.littleEndianBytes)
        wavData.append(contentsOf: blockAlign.littleEndianBytes)
        wavData.append(contentsOf: bitsPerSample.littleEndianBytes)
        
        // data sub-chunk
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: subchunk2Size.littleEndianBytes)
        wavData.append(pcmData)
        
        return wavData
    }
    
    /// Stops audio playback.
    // -------------------------------------------------------------------------
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        stopMeteringTimer()
        
        state = .idle
        outputLevel = 0
        
        print("🔊 Playback stopped")
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Metering Timer
    // -------------------------------------------------------------------------
    
    private func startMeteringTimer() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let player = self?.audioPlayer else { return }
            player.updateMeters()
            
            // Convert dB to linear scale
            let db = player.averagePower(forChannel: 0)
            let level = pow(10, db / 20)
            
            Task { @MainActor in
                self?.outputLevel = min(level * 2, 1.0)
            }
        }
    }
    
    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        outputLevel = 0
    }
    
    // =========================================================================
    // MARK: - Audio Data Conversion
    // =========================================================================
    
    /// Converts float32 samples to 16-bit PCM data.
    ///
    /// This is the format expected by the RunAnywhere STT transcribe function.
    ///
    /// - Parameter samples: Float32 audio samples (-1.0 to 1.0)
    /// - Returns: Data containing 16-bit signed integer PCM
    // -------------------------------------------------------------------------
    private func convertSamplesToData(_ samples: [Float]) -> Data {
        var data = Data()
        
        for sample in samples {
            // Clamp to valid range
            let clamped = max(-1.0, min(1.0, sample))
            
            // Convert to Int16
            let int16Value = Int16(clamped * Float(Int16.max))
            
            // Append as little-endian bytes
            withUnsafeBytes(of: int16Value.littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    /// Resamples audio to the target sample rate if needed.
    ///
    /// Not currently used since we record at 16kHz directly, but useful
    /// for processing audio from other sources.
    // -------------------------------------------------------------------------
    func resampleAudio(_ data: Data, fromRate: Double, toRate: Double) -> Data? {
        // For simplicity, return original if rates match
        guard fromRate != toRate else { return data }
        
        // TODO: Implement proper resampling using vDSP
        // For now, the audio engine handles format conversion
        return data
    }
}

// =============================================================================
// MARK: - AVAudioPlayerDelegate
// =============================================================================
extension AudioService: AVAudioPlayerDelegate {
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stopMeteringTimer()
            state = .idle
            outputLevel = 0
            print("🔊 Playback finished (success: \(flag))")
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            state = .error(message: error?.localizedDescription ?? "Playback error")
            print("❌ Playback error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// =============================================================================
// MARK: - Audio Errors
// =============================================================================
/// Errors that can occur during audio operations.
// =============================================================================
enum AudioError: LocalizedError {
    case permissionDenied
    case engineInitFailed
    case formatError
    case notRecording
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied. Please enable it in Settings."
        case .engineInitFailed:
            return "Failed to initialize audio engine."
        case .formatError:
            return "Audio format configuration failed."
        case .notRecording:
            return "Not currently recording."
        case .playbackFailed:
            return "Audio playback failed."
        }
    }
}

// =============================================================================
// MARK: - Little Endian Helpers
// =============================================================================
/// Extensions for converting integers to little-endian byte arrays.
// =============================================================================
private extension Int16 {
    var littleEndianBytes: [UInt8] {
        let value = self.littleEndian
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        let value = self.littleEndian
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        let value = self.littleEndian
        return [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }
}

// =============================================================================
// MARK: - Preview Helpers
// =============================================================================
#if DEBUG
extension AudioService {
    /// Creates a mock audio service for previews.
    static var preview: AudioService {
        let service = AudioService.shared
        service.hasPermission = true
        return service
    }
}
#endif
