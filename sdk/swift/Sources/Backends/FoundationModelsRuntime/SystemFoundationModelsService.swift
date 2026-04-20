// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Apple Foundation Models bridge. Wires iOS 26+ / macOS 26+
// `FoundationModels.LanguageModelSession` into the v2 `ra_platform_llm_*`
// callback table so the core can route LLM calls to Apple's built-in
// on-device model.

@_exported import RunAnywhere
import Foundation
import CRACommonsCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Strong-ref holder for Apple FM session objects. Key = raw pointer
/// returned to C ABI as the session handle.
@available(iOS 26.0, macOS 26.0, *)
final class FMSessionHandle {
    #if canImport(FoundationModels)
    let session: LanguageModelSession
    init(session: LanguageModelSession) { self.session = session }
    #else
    init() {}
    #endif
}

public enum SystemFoundationModelsService {

    // Handle registry: we retain the Swift handle while the C side holds
    // an opaque pointer. `destroy` releases it.
    private nonisolated(unsafe) static var handles: [OpaquePointer: AnyObject] = [:]
    private static let handlesLock = NSLock()

    /// Install the FoundationModels callback table into `ra_platform_llm_*`
    /// under the `RA_PLATFORM_LLM_FOUNDATION_MODELS` slot. Idempotent.
    public static func installPlatformCallbacks() {
        var cbs = ra_platform_llm_callbacks_t()
        cbs.can_handle = { spec, _ in
            SystemFoundationModelsService.canHandle(spec: spec)
        }
        cbs.create = { spec, cfg, outSession, _ in
            SystemFoundationModelsService.create(spec: spec, cfg: cfg, outSession: outSession)
        }
        cbs.destroy = { session, _ in
            SystemFoundationModelsService.destroy(session: session)
        }
        cbs.generate = { session, prompt, onToken, onError, callbackUserData, _ in
            SystemFoundationModelsService.generate(
                session: session, prompt: prompt,
                onToken: onToken, onError: onError,
                userData: callbackUserData)
        }
        cbs.cancel = { _, _ in ra_status_t(RA_OK) }
        _ = withUnsafePointer(to: cbs) { ptr in
            ra_platform_llm_set_callbacks(
                ra_platform_llm_backend_t(RA_PLATFORM_LLM_FOUNDATION_MODELS), ptr)
        }
        _ = ra_backend_platform_register(
            ra_platform_llm_backend_t(RA_PLATFORM_LLM_FOUNDATION_MODELS))
    }

    // MARK: - C callback implementations

    private static func canHandle(spec: UnsafePointer<ra_model_spec_t>?) -> UInt8 {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: return 1
            default:         return 0
            }
        }
        return 0
        #else
        _ = spec
        return 0
        #endif
    }

    private static func create(
        spec: UnsafePointer<ra_model_spec_t>?,
        cfg: UnsafePointer<ra_session_config_t>?,
        outSession: UnsafeMutablePointer<OpaquePointer?>?
    ) -> ra_status_t {
        _ = spec; _ = cfg
        guard let outSession = outSession else { return ra_status_t(RA_ERR_INVALID_ARGUMENT) }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        }
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let handle = FMSessionHandle(session: session)
        let unmanaged = Unmanaged.passRetained(handle)
        let ptr = OpaquePointer(unmanaged.toOpaque())
        storeHandle(ptr, handle)
        outSession.pointee = ptr
        return ra_status_t(RA_OK)
        #else
        return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        #endif
    }

    private static func destroy(session: OpaquePointer?) {
        guard let session = session else { return }
        if let obj = takeHandle(session) {
            Unmanaged.passUnretained(obj).release()
        }
    }

    private static func generate(
        session: OpaquePointer?,
        prompt: UnsafePointer<ra_prompt_t>?,
        onToken: ra_token_callback_t?,
        onError: ra_error_callback_t?,
        userData: UnsafeMutableRawPointer?
    ) -> ra_status_t {
        guard let session = session, let prompt = prompt?.pointee,
              let text = prompt.text.map({ String(cString: $0) }) else {
            return ra_status_t(RA_ERR_INVALID_ARGUMENT)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *),
           let handle = lookupHandle(session) as? FMSessionHandle {
            Task.detached {
                do {
                    let response = try await handle.session.respond(to: text)
                    let responseText = response.content
                    responseText.withCString { cstr in
                        var token = ra_token_output_t()
                        token.text = cstr
                        token.is_final = 1
                        token.token_kind = 1
                        withUnsafePointer(to: token) { ptr in
                            onToken?(ptr, userData)
                        }
                    }
                } catch {
                    let msg = error.localizedDescription
                    msg.withCString { cstr in
                        onError?(ra_status_t(RA_ERR_INTERNAL), cstr, userData)
                    }
                }
            }
            return ra_status_t(RA_OK)
        }
        return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        #else
        _ = session
        return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        #endif
    }

    // MARK: - Handle registry helpers

    private static func storeHandle(_ raw: OpaquePointer, _ obj: AnyObject) {
        handlesLock.lock(); defer { handlesLock.unlock() }
        handles[raw] = obj
    }

    private static func lookupHandle(_ raw: OpaquePointer) -> AnyObject? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles[raw]
    }

    private static func takeHandle(_ raw: OpaquePointer) -> AnyObject? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles.removeValue(forKey: raw)
    }
}
