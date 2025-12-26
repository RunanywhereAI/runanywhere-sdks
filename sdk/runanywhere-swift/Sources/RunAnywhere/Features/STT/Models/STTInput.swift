//
//  STTInput.swift
//  RunAnywhere SDK
//
//  Input model for Speech-to-Text
//

@preconcurrency import AVFoundation
import Foundation

// MARK: - STT Input

/// Input for Speech-to-Text (conforms to ComponentInput protocol)
public struct STTInput: ComponentInput {
    /// Audio data to transcribe
    public let audioData: Data

    /// Audio buffer (alternative to data)
    public let audioBuffer: AVAudioPCMBuffer?

    /// Audio format information
    public let format: AudioFormat

    /// Language code override (e.g., "en-US")
    public let language: String?

    /// Optional VAD output for context
    public let vadOutput: VADOutput?

    /// Custom options override
    public let options: STTOptions?

    public init(
        audioData: Data,
        format: AudioFormat = .wav,
        language: String? = nil,
        vadOutput: VADOutput? = nil,
        options: STTOptions? = nil
    ) {
        self.audioData = audioData
        self.audioBuffer = nil
        self.format = format
        self.language = language
        self.vadOutput = vadOutput
        self.options = options
    }

    public init(
        audioBuffer: AVAudioPCMBuffer,
        format: AudioFormat = .pcm,
        language: String? = nil,
        vadOutput: VADOutput? = nil,
        options: STTOptions? = nil
    ) {
        self.audioData = Data()
        self.audioBuffer = audioBuffer
        self.format = format
        self.language = language
        self.vadOutput = vadOutput
        self.options = options
    }

    public func validate() throws {
        if audioData.isEmpty && audioBuffer == nil {
            throw SDKError.general(.validationFailed, "STTInput must contain either audioData or audioBuffer")
        }
    }
}
