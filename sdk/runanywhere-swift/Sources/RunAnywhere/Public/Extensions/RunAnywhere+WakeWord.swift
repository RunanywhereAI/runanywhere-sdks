//
//  RunAnywhere+WakeWord.swift
//  RunAnywhere SDK
//
//  P2 feature B11 — Wake Word public facade.
//
//  The C ABI `rac_wake_word_*` exists in runanywhere-commons but is
//  currently stubbed (returns RAC_ERROR_FEATURE_NOT_AVAILABLE) and is
//  not yet re-exported through the `CRACommons` Swift module umbrella
//  header. Until it is, the `RunAnywhere.wakeWord` namespace exposes
//  the canonical `load / detect / unload` triple but surfaces a
//  `featureNotAvailable` error so apps linking against this API will
//  get a clear signal instead of a link-time failure.
//

import Foundation

public extension RunAnywhere {

    /// Wake-word detection capability surface.
    ///
    /// Mirrors `RunAnywhere.vad`, `RunAnywhere.stt` shape. Once the
    /// `rac_wake_word_*` C ABI is wired through `CRACommons`, the
    /// three methods below will forward to native commons.
    enum wakeWord {

        /// Load a wake-word model from disk.
        ///
        /// - Parameter modelPath: Absolute path to the wake-word model
        ///   file (e.g. a Porcupine/OpenWakeWord/pv-keyword blob).
        /// - Throws: `SDKException.wakeWord(.featureNotAvailable, ...)`
        ///   while the native wake-word pipeline is still stubbed.
        public static func load(modelPath: String) async throws {
            guard isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            _ = modelPath
            throw SDKException.wakeWord(
                .featureNotAvailable,
                "Wake-word detection is not yet wired in runanywhere-commons (rac_wake_word_* is stubbed)."
            )
        }

        /// Run wake-word detection over a PCM buffer.
        ///
        /// - Parameter audio: Raw PCM bytes. The commons C ABI expects
        ///   `float` samples at 16 kHz mono; the public facade accepts
        ///   `Data` so call sites need not depend on `CRACommons` types.
        /// - Returns: `true` when the wake-word was detected in the
        ///   buffer, otherwise `false`.
        /// - Throws: `SDKException.wakeWord(.featureNotAvailable, ...)`
        ///   while the native wake-word pipeline is still stubbed.
        public static func detect(audio: Data) async throws -> Bool {
            guard isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            _ = audio
            throw SDKException.wakeWord(
                .featureNotAvailable,
                "Wake-word detection is not yet wired in runanywhere-commons (rac_wake_word_* is stubbed)."
            )
        }

        /// Unload the currently loaded wake-word model and release all
        /// native resources.
        ///
        /// Safe to call even when no model is loaded — matches the
        /// `rac_wake_word_destroy` contract which is NULL-safe.
        public static func unload() async throws {
            guard isInitialized else {
                // unload is idempotent — swallow the pre-init case so
                // teardown in `deinit`/`cleanupAll` stays robust.
                return
            }
            // Intentionally no-op until `rac_wake_word_destroy` is wired.
        }
    }
}
