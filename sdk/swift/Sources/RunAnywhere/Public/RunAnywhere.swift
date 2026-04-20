// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — public entry point for Swift.
//
// The 20-line developer API:
//
//     let session = try await RunAnywhere.solution(.voiceAgent(
//         llm: "qwen3-4b", stt: "whisper-base", tts: "kokoro"))
//     for try await event in session.run() {
//         switch event {
//         case .userSaid(let text):    transcript.append(.user(text))
//         case .assistantToken(let t): transcript.appendToken(t)
//         case .audio(let pcm):        player.enqueue(pcm)
//         case .interrupted:           player.flush()
//         case .error(let e):          onError(e)
//         }
//     }

import Foundation
import CRACommonsCore

@MainActor
public enum RunAnywhere {

    // MARK: - Public API

    /// Creates a `VoiceSession` from a solution config. Throws if:
    ///   - the required engines are not registered (static iOS) or cannot
    ///     be dlopen'd (macOS)
    ///   - the model files are not reachable via the model registry
    public static func solution(
        _ config: SolutionConfig
    ) async throws -> VoiceSession {
        try await VoiceSession.create(from: config)
    }

    // MARK: - Engine plugin registration (iOS/macOS static mode)

    /// Registers a static engine plugin. Called by application code at
    /// launch on iOS — iOS prohibits dlopen, so every plugin must be
    /// compiled into the XCFramework and registered explicitly.
    public static func configure(_ setup: (inout RegistrationBuilder) -> Void) {
        var b = RegistrationBuilder()
        setup(&b)
        b.apply()
    }

    /// Loads an engine plugin from a shared-library path. macOS only — iOS
    /// cannot dlopen, so iOS apps register plugins statically via
    /// `configure`. Returns true on success.
    ///
    /// Example:
    ///
    ///     RunAnywhere.loadPlugin(at: "/usr/local/lib/librunanywhere_llamacpp.dylib")
    @discardableResult
    public static func loadPlugin(at libraryPath: String) -> Bool {
        libraryPath.withCString { cstr in
            ra_registry_load_plugin(cstr) == Int32(RA_OK)
        }
    }

    /// Count of currently-registered engine plugins. Useful for tests that
    /// assert a plugin was loaded before creating a session.
    public static var registeredPluginCount: Int {
        Int(ra_registry_plugin_count())
    }
}
