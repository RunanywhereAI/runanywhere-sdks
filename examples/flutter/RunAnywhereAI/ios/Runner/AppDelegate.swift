import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let platformChannel = FlutterMethodChannel(name: "com.runanywhere.sdk/native",
                                               binaryMessenger: controller.binaryMessenger)

    platformChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "configureAudioSession":
        let mode = (call.arguments as? [String: Any])?["mode"] as? String ?? "recording"
        self.configureAudioSession(mode: mode)
        result(nil)
      case "activateAudioSession":
        self.activateAudioSession()
        result(nil)
      case "deactivateAudioSession":
        self.deactivateAudioSession()
        result(nil)
      case "requestMicrophonePermission":
        self.requestMicrophonePermission(result: result)
      case "hasMicrophonePermission":
        result(self.hasMicrophonePermission())
      case "getDeviceCapabilities":
        result(self.getDeviceCapabilities())
      case "loadNativeModel":
        let args = call.arguments as? [String: Any]
        let modelId = args?["modelId"] as? String
        let modelPath = args?["modelPath"] as? String
        if let modelId = modelId, let modelPath = modelPath {
          self.loadNativeModel(modelId: modelId, modelPath: modelPath, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing modelId or modelPath", details: nil))
        }
      case "unloadNativeModel":
        let args = call.arguments as? [String: Any]
        let modelId = args?["modelId"] as? String
        if let modelId = modelId {
          self.unloadNativeModel(modelId: modelId)
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing modelId", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureAudioSession(mode: String) {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      switch mode {
      case "recording":
        try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
      case "playback":
        try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
      case "conversation":
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
      default:
        break
      }
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }

  private func activateAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setActive(true)
    } catch {
      print("Failed to activate audio session: \(error)")
    }
  }

  private func deactivateAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setActive(false)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      result(granted)
    }
  }

  private func hasMicrophonePermission() -> Bool {
    return AVAudioSession.sharedInstance().recordPermission == .granted
  }

  private func getDeviceCapabilities() -> [String: Any] {
    let processInfo = ProcessInfo.processInfo
    return [
      "totalMemory": processInfo.physicalMemory,
      "availableProcessors": processInfo.processorCount,
    ]
  }

  private func loadNativeModel(modelId: String, modelPath: String, result: @escaping FlutterResult) {
    // TODO: Implement native model loading (could bridge to Swift SDK)
    result(true)
  }

  private func unloadNativeModel(modelId: String) {
    // TODO: Implement native model unloading
  }
}

import AVFoundation
