//
//  CloudSttProvider.swift
//  RunAnywhere
//
//  Swift binding for the cross-SDK named cloud STT provider table
//  (rac_cloud_stt_provider.h). The `cloud` engine ships static adapters for
//  built-in providers (e.g. "sarvam"). For any other vendor, register a
//  handler by name via `Cloud.registerProvider` and tie a model to it with
//  `Cloud.register(id:provider:...)` (same `provider` string). The cloud
//  engine then delegates the ENTIRE request — build, HTTP, and response
//  parse — to the handler, so a developer supports any cloud STT API (key,
//  URL, request and response shape) without a native adapter or a recompile.
//
//  The handler runs on the engine's request thread (off the main thread); it
//  may block on network. It must be thread-safe — the engine may invoke it
//  concurrently for distinct utterances. Thrown errors surface to the router
//  as a transcribe failure (so the cascade policy can fall back).
//
//  Boxing follows the SDK's standard Swift↔C callback convention
//  (Unmanaged.passRetained → user_data → fromOpaque) with an
//  OSAllocatedUnfairLock-guarded name→box map for lifetime, mirroring
//  HybridCustomFilter.swift / HybridDeviceState.swift (per AGENTS.md NSLock
//  is forbidden). Mirrors the Kotlin CloudSttProvider.kt surface.
//

import CRACommons
import Foundation
import os

// MARK: - Provider contract

/// Audio container of the bytes handed to a cloud STT handler. Raw values
/// mirror the native `rac_audio_format_enum_t`.
public enum CloudAudioFormat: Int32, Sendable {
    case pcm = 0
    case wav = 1
    case mp3 = 2
    case opus = 3
    case aac = 4
    case flac = 5
    case unknown = -1

    /// The native `rac_audio_format_enum_t` wire value.
    public var nativeValue: Int32 { rawValue }

    public init(nativeValue: Int32) {
        self = CloudAudioFormat(rawValue: nativeValue) ?? .unknown
    }
}

/// One cloud transcribe request handed to a registered provider handler.
public struct CloudSttRequest: Sendable {
    /// The provider name this entry was registered under.
    public let provider: String
    /// The provider model id from `Cloud.register`.
    public let model: String
    /// The API key from registration. Sensitive; never log.
    public let apiKey: String
    /// Optional base-URL override from registration, if set.
    public let baseUrl: String?
    /// Optional BCP-47 language hint, if set.
    public let languageCode: String?
    /// Audio bytes for this utterance.
    public let audio: Data
    /// Container/encoding of `audio`.
    public let audioFormat: CloudAudioFormat
    /// The full registered config as JSON, for any extra keys a provider
    /// needs beyond the typed fields above.
    public let configJson: String

    public init(
        provider: String,
        model: String,
        apiKey: String,
        baseUrl: String?,
        languageCode: String?,
        audio: Data,
        audioFormat: CloudAudioFormat,
        configJson: String
    ) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.languageCode = languageCode
        self.audio = audio
        self.audioFormat = audioFormat
        self.configJson = configJson
    }
}

/// Result of a cloud transcribe.
public struct CloudSttResult: Sendable {
    /// The transcript (empty if the provider found no speech).
    public let text: String
    /// Detected/echoed BCP-47 language, if the provider reports one.
    public let languageCode: String?
    /// Optional 0..1 confidence; leave `.nan` (the default) when the provider
    /// returns no score. The hybrid router treats NaN as "no signal" and never
    /// cascades on it.
    public let confidence: Float

    public init(text: String, languageCode: String? = nil, confidence: Float = .nan) {
        self.text = text
        self.languageCode = languageCode
        self.confidence = confidence
    }
}

// MARK: - Cloud provider registration

public extension Cloud {

    /// Performs a complete cloud STT request host-side for one utterance.
    /// Implementations build and send the HTTP request and parse the response.
    typealias SttProviderHandler = @Sendable (CloudSttRequest) throws -> CloudSttResult

    private static let providerLogger = SDKLogger(category: "Cloud.SttProvider")

    /// name → retained handler box. A box stays retained from register until
    /// the matching unregister (after `rac_cloud_unregister_stt_provider`), so
    /// commons never calls a freed closure.
    private static let registeredProviders =
        OSAllocatedUnfairLock<[String: Unmanaged<CloudProviderHandlerBox>]>(initialState: [:])

    /// Register (or replace) a developer-defined cloud STT provider handler.
    /// The handler performs the whole request host-side (build + HTTP +
    /// parse), so any vendor works without a native adapter. Tie a model to it
    /// by calling `Cloud.register` with the same `provider` string:
    ///
    ///     Cloud.registerProvider("deepgram") { request in
    ///         // build + POST with URLSession, parse the JSON …
    ///         CloudSttResult(text: transcript, confidence: score)
    ///     }
    ///     Cloud.register(
    ///         id: "dg-nova2", provider: "deepgram", model: "nova-2",
    ///         apiKey: "…", baseURL: "https://api.deepgram.com"
    ///     )
    ///
    /// The handler is invoked on the router's request thread and may be called
    /// concurrently; it may block on network. Built-in providers (e.g.
    /// "sarvam") cannot be shadowed — a static adapter always wins over a host
    /// callback of the same name.
    @discardableResult
    static func registerProvider(_ name: String, _ handler: @escaping SttProviderHandler) -> Bool {
        guard !name.isEmpty else {
            providerLogger.error("cloud provider name must be non-empty")
            return false
        }

        // Ensure the cloud engine plugin is in the registry (idempotent),
        // mirroring the Kotlin binding's ensurePluginRegistered().
        register()

        let box = CloudProviderHandlerBox(handler)
        let retained = Unmanaged.passRetained(box)

        // `@convention(c)` trampoline: decode the registered config + audio,
        // dispatch to the boxed Swift handler, and hand back a malloc'd
        // result-JSON string commons frees via rac_cloud_stt_result_free.
        let trampoline: rac_cloud_stt_transcribe_fn_t = { configJson, audio, audioLen, audioFormat, outResultJson, userData in
            guard let outResultJson else { return RAC_ERROR_NULL_POINTER }
            outResultJson.pointee = nil
            guard let box = CloudProviderHandlerBox.unwrap(userData) else {
                return RAC_ERROR_INTERNAL
            }

            let config = configJson.map { String(cString: $0) } ?? "{}"
            let audioData: Data
            if let audio, audioLen > 0 {
                audioData = Data(bytes: audio, count: audioLen)
            } else {
                audioData = Data()
            }

            let resultJSON = Cloud.invokeProviderHandler(
                box: box,
                configJson: config,
                audio: audioData,
                audioFormat: CloudAudioFormat(nativeValue: audioFormat)
            )
            guard let cString = strdup(resultJSON) else { return RAC_ERROR_OUT_OF_MEMORY }
            outResultJson.pointee = cString
            return RAC_SUCCESS
        }

        let rc = name.withCString { namePtr in
            rac_cloud_register_stt_provider(namePtr, trampoline, retained.toOpaque())
        }

        guard rc == RAC_SUCCESS else {
            retained.release()
            providerLogger.error("rac_cloud_register_stt_provider('\(name)') failed: rc=\(rc)")
            return false
        }

        // Replace any prior box registered under the same name and retire it.
        let previous: Unmanaged<CloudProviderHandlerBox>? = registeredProviders.withLock { map in
            let old = map[name]
            map[name] = retained
            return old
        }
        previous?.release()
        return true
    }

    /// Remove a developer-defined provider previously registered via
    /// `registerProvider`. Idempotent for unknown names.
    static func unregisterProvider(_ name: String) {
        guard !name.isEmpty else { return }

        let rc = name.withCString { rac_cloud_unregister_stt_provider($0) }
        if rc != RAC_SUCCESS {
            providerLogger.error("rac_cloud_unregister_stt_provider('\(name)') failed: rc=\(rc)")
        }

        // Per rac_cloud_stt_provider.h, unregister retires the previous table
        // snapshot one generation later, so an in-flight call could still be
        // running. We release our retain here regardless — registration
        // brackets policy install/teardown, when the router is not
        // concurrently transcribing.
        let previous: Unmanaged<CloudProviderHandlerBox>? = registeredProviders.withLock { map in
            map.removeValue(forKey: name)
        }
        previous?.release()
    }

    // MARK: - Trampoline support

    /// Decodes the registered config into a `CloudSttRequest`, runs the boxed
    /// handler, and encodes the engine-facing result JSON. Never throws —
    /// failures are encoded as `{"error_code": 1, "error_message": "…"}`,
    /// which the engine surfaces as a transcribe failure (mirrors Kotlin's
    /// NativeCloudSttProvider.invoke).
    private static func invokeProviderHandler(
        box: CloudProviderHandlerBox,
        configJson: String,
        audio: Data,
        audioFormat: CloudAudioFormat
    ) -> String {
        let config =
            (try? JSONDecoder().decode(ProviderConfig.self, from: Data(configJson.utf8)))
                ?? ProviderConfig()
        let request = CloudSttRequest(
            provider: config.provider ?? "",
            model: config.model ?? "",
            apiKey: config.apiKey ?? "",
            baseUrl: nonBlank(config.baseUrl),
            languageCode: nonBlank(config.languageCode),
            audio: audio,
            audioFormat: audioFormat,
            configJson: configJson
        )

        do {
            let result = try box.handler(request)
            return serializeResultJSON(ProviderResult(
                text: result.text,
                languageCode: result.languageCode,
                confidence: result.confidence.isNaN ? nil : Double(result.confidence),
                errorCode: 0,
                errorMessage: nil
            ))
        } catch {
            return serializeResultJSON(ProviderResult(
                text: nil,
                languageCode: nil,
                confidence: nil,
                errorCode: 1,
                errorMessage: error.localizedDescription
            ))
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func serializeResultJSON(_ result: ProviderResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result),
              let json = String(bytes: data, encoding: .utf8)
        else {
            return #"{"error_code":1,"error_message":"result serialization failed"}"#
        }
        return json
    }
}

/// Typed view of the registered cloud entry JSON (snake_case wire keys).
private struct ProviderConfig: Decodable {
    var provider: String?
    var model: String?
    var apiKey: String?
    var baseUrl: String?
    var languageCode: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case languageCode = "language_code"
    }

    init() {}
}

/// Engine-facing result JSON shape parsed by the cloud engine's
/// parse_host_result_json (snake_case wire keys; nil fields omitted).
private struct ProviderResult: Encodable {
    let text: String?
    let languageCode: String?
    let confidence: Double?
    let errorCode: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case confidence
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

/// Heap box carrying a Swift handler across the C `user_data` pointer.
///
/// `@unchecked Sendable`: immutable box over an already-`@Sendable` closure,
/// so storing its `Unmanaged` handle in the `OSAllocatedUnfairLock` map is
/// safe across isolation domains.
private final class CloudProviderHandlerBox: @unchecked Sendable {
    let handler: Cloud.SttProviderHandler
    init(_ handler: @escaping Cloud.SttProviderHandler) { self.handler = handler }

    /// Resolve the box from a C `user_data` pointer without consuming a
    /// retain (the callback borrows; ownership stays with the registry map).
    static func unwrap(_ userData: UnsafeMutableRawPointer?) -> CloudProviderHandlerBox? {
        guard let userData else { return nil }
        return Unmanaged<CloudProviderHandlerBox>.fromOpaque(userData).takeUnretainedValue()
    }
}
