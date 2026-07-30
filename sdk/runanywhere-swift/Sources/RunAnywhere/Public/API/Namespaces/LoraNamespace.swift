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
        guard result.success else {
            throw SDKException(
                code: .processingFailed,
                message: result.hasErrorMessage ? result.errorMessage : "LoRA apply failed",
                category: .component
            )
        }
    }

    /// Remove one adapter, or every applied adapter when `adapterId` is `nil`.
    ///
    /// - Throws: `SDKException` when the removal is rejected.
    func remove(adapterId: String? = nil) async throws {
        var request = RALoRARemoveRequest()
        if let adapterId {
            request.adapterIds = [adapterId]
        } else {
            request.clearAll_p = true
        }
        let state = try await remove(request)
        if state.errorCode != 0 {
            throw SDKException(
                code: .processingFailed,
                message: state.hasErrorMessage ? state.errorMessage : "LoRA remove failed",
                category: .component
            )
        }
    }
}
