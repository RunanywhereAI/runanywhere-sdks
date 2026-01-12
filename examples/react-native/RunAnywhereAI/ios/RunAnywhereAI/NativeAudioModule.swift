import Foundation
import AVFoundation
import React

/// Native iOS Audio Module for recording, playback, and TTS
/// Uses AVFoundation directly - compatible with New Architecture
@objc(NativeAudioModule)
class NativeAudioModule: NSObject, AVSpeechSynthesizerDelegate {

  private var audioEngine: AVAudioEngine?
  private var audioPlayer: AVAudioPlayer?
  private var audioRecorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var pcmBuffer: [Float] = []
  private var isRecording = false

  // System TTS
  private var speechSynthesizer: AVSpeechSynthesizer?
  private var ttsResolve: RCTPromiseResolveBlock?
  private var ttsReject: RCTPromiseRejectBlock?
  private var isSpeaking = false

  override init() {
    super.init()
    speechSynthesizer = AVSpeechSynthesizer()
    speechSynthesizer?.delegate = self
  }

  @objc static func requiresMainQueueSetup() -> Bool {
    return false
  }

  // MARK: - Audio Recording

  @objc(startRecording:withRejecter:)
  func startRecording(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async {
      self.startRecordingImpl(resolve: resolve, reject: reject)
    }
  }

  private func startRecordingImpl(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    // Set up audio session
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
      try audioSession.setActive(true)
    } catch {
      reject("AUDIO_SESSION_ERROR", "Failed to configure audio session: \(error.localizedDescription)", error)
      return
    }

    // Create recording URL
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    recordingURL = documentsPath.appendingPathComponent("recording_\(timestamp).wav")

    // Recording settings for WAV format at 16kHz mono (optimal for STT)
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    do {
      audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
      audioRecorder?.isMeteringEnabled = true
      audioRecorder?.prepareToRecord()
      audioRecorder?.record()
      isRecording = true

      print("[NativeAudioModule] Recording started: \(recordingURL!.path)")
      resolve(["status": "recording", "path": recordingURL!.path])
    } catch {
      reject("RECORDING_ERROR", "Failed to start recording: \(error.localizedDescription)", error)
    }
  }

  @objc(stopRecording:withRejecter:)
  func stopRecording(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
      reject("NOT_RECORDING", "No recording in progress", nil)
      return
    }

    recorder.stop()
    isRecording = false

    // Get file info
    if FileManager.default.fileExists(atPath: url.path) {
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        print("[NativeAudioModule] Recording stopped: \(url.path), size: \(fileSize) bytes")
        resolve([
          "status": "stopped",
          "path": url.path,
          "fileSize": fileSize
        ])
      } catch {
        resolve([
          "status": "stopped",
          "path": url.path,
          "fileSize": 0
        ])
      }
    } else {
      reject("FILE_NOT_FOUND", "Recording file not found", nil)
    }
  }

  @objc(cancelRecording:withRejecter:)
  func cancelRecording(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    audioRecorder?.stop()
    isRecording = false

    if let url = recordingURL {
      try? FileManager.default.removeItem(at: url)
    }

    recordingURL = nil
    resolve(["status": "cancelled"])
  }

  @objc(getAudioLevel:withRejecter:)
  func getAudioLevel(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard let recorder = audioRecorder, isRecording else {
      resolve(["level": 0.0])
      return
    }

    recorder.updateMeters()
    let averagePower = recorder.averagePower(forChannel: 0)
    // Convert dB to linear scale (0-1)
    let level = pow(10, averagePower / 20)
    resolve(["level": min(1.0, max(0.0, level))])
  }

  // MARK: - Audio Playback

  @objc(playAudio:withResolver:withRejecter:)
  func playAudio(filePath: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    let url = URL(fileURLWithPath: filePath)

    guard FileManager.default.fileExists(atPath: filePath) else {
      reject("FILE_NOT_FOUND", "Audio file not found: \(filePath)", nil)
      return
    }

    do {
      // Set up audio session for playback
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default)
      try audioSession.setActive(true)

      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.prepareToPlay()
      audioPlayer?.play()

      print("[NativeAudioModule] Playing audio: \(filePath)")
      resolve([
        "status": "playing",
        "duration": audioPlayer?.duration ?? 0
      ])
    } catch {
      reject("PLAYBACK_ERROR", "Failed to play audio: \(error.localizedDescription)", error)
    }
  }

  @objc(stopPlayback:withRejecter:)
  func stopPlayback(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    audioPlayer?.stop()
    audioPlayer = nil
    resolve(["status": "stopped"])
  }

  @objc(pausePlayback:withRejecter:)
  func pausePlayback(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    audioPlayer?.pause()
    resolve(["status": "paused"])
  }

  @objc(resumePlayback:withRejecter:)
  func resumePlayback(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    audioPlayer?.play()
    resolve(["status": "playing"])
  }

  @objc(getPlaybackStatus:withRejecter:)
  func getPlaybackStatus(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard let player = audioPlayer else {
      resolve([
        "isPlaying": false,
        "currentTime": 0,
        "duration": 0
      ])
      return
    }

    resolve([
      "isPlaying": player.isPlaying,
      "currentTime": player.currentTime,
      "duration": player.duration
    ])
  }

  @objc(setVolume:withResolver:withRejecter:)
  func setVolume(volume: Float, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    audioPlayer?.volume = volume
    resolve(["volume": volume])
  }

  // MARK: - System TTS (AVSpeechSynthesizer)

  @objc(speak:withRate:withPitch:withResolver:withRejecter:)
  func speak(text: String, rate: Float, pitch: Float, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    // Stop any ongoing speech
    speechSynthesizer?.stopSpeaking(at: .immediate)

    // Set up audio session
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default)
      try audioSession.setActive(true)
    } catch {
      reject("AUDIO_SESSION_ERROR", "Failed to configure audio session: \(error.localizedDescription)", error)
      return
    }

    // Create utterance
    let utterance = AVSpeechUtterance(string: text)

    // Rate: AVSpeechUtterance rate is 0.0 to 1.0, with 0.5 being normal
    // User rate is typically 0.5 to 2.0, so we map it
    let mappedRate = min(1.0, max(0.0, (rate - 0.5) / 1.5 * 0.5 + 0.5))
    utterance.rate = Float(mappedRate)

    // Pitch: AVSpeechUtterance pitch is 0.5 to 2.0, with 1.0 being normal
    utterance.pitchMultiplier = min(2.0, max(0.5, pitch))

    // Use default voice for the device's language
    utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())

    // Store callbacks for delegate
    ttsResolve = resolve
    ttsReject = reject
    isSpeaking = true

    print("[NativeAudioModule] Speaking: \(text.prefix(50))... rate: \(mappedRate), pitch: \(pitch)")
    speechSynthesizer?.speak(utterance)
  }

  @objc(stopSpeaking:withRejecter:)
  func stopSpeaking(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    speechSynthesizer?.stopSpeaking(at: .immediate)
    isSpeaking = false
    ttsResolve = nil
    ttsReject = nil
    resolve(["status": "stopped"])
  }

  @objc(isSpeaking:withRejecter:)
  func checkIsSpeaking(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    resolve(["isSpeaking": speechSynthesizer?.isSpeaking ?? false])
  }

  // MARK: - AVSpeechSynthesizerDelegate

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    print("[NativeAudioModule] Speech finished")
    isSpeaking = false
    ttsResolve?(["status": "finished"])
    ttsResolve = nil
    ttsReject = nil
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    print("[NativeAudioModule] Speech cancelled")
    isSpeaking = false
    ttsResolve?(["status": "cancelled"])
    ttsResolve = nil
    ttsReject = nil
  }
}
