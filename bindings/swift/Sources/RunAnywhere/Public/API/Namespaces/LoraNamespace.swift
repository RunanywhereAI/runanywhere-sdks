//
//  LoraNamespace.swift
//  RunAnywhere SDK
//
//  The v3 `lora.*` verbs, layered on the existing `RunAnywhere.LoRA` namespace.
//  Adapters register through `models.register` or `lora.registerArtifact`, like
//  any other artifact.
//

import Foundation

public extension RunAnywhere.LoRA {

    /// Apply the catalogued adapter `adapterId` to the loaded base model.
    ///
    /// ```swift
    /// try await RunAnywhere.lora.apply(adapterId: "chat-tuned")
    /// ```
    ///
    /// - Parameter scale: Adapter strength; `nil` uses the catalog default.
    /// - Throws: `SDKException` when the adapter is unknown, has no local file,
    ///   or is incompatible with the loaded model.
    func apply(adapterId: String, scale: Float? = nil) async throws {
        var request = RALoraAdapterCatalogGetRequest()
        request.adapterID = adapterId
        let lookup = try await getCatalogEntry(request)
        guard lookup.found, lookup.hasEntry else {
            throw SDKException(
                code: .modelNotFound,
                message: "LoRA adapter '\(adapterId)' is not registered",
                category: .validation
            )
        }
        let result = try await apply(lookup.entry, scale: scale)
        guard !result.hasError else {
            throw SDKException(proto: result.error)
        }
    }

    /// Remove one applied adapter.
    ///
    /// - Throws: `SDKException` when the removal is rejected.
    func remove(adapterId: String) async throws {
        var request = RALoraRemoveRequest()
        request.adapterIds = [adapterId]
        let state = try await remove(request)
        if state.hasError {
            throw SDKException(proto: state.error)
        }
    }

    /// Remove every applied adapter.
    ///
    /// - Throws: `SDKException` when the removal is rejected.
    func removeAll() async throws {
        var request = RALoraRemoveRequest()
        request.clearAll_p = true
        let state = try await remove(request)
        if state.hasError {
            throw SDKException(proto: state.error)
        }
    }

    /// Deprecated: `nil` forwards to `removeAll()`.
    @available(*, deprecated, message: "Use remove(adapterId:) or removeAll()")
    func remove(adapterId: String? = nil) async throws {
        if let adapterId {
            try await remove(adapterId: adapterId)
        } else {
            try await removeAll()
        }
    }
}
