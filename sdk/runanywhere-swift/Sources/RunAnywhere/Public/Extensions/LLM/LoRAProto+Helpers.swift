//
//  LoRAProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical LoRA proto types.
//

import Foundation

// MARK: - RALoRAAdapterConfig

extension RALoRAAdapterConfig {
    public init(adapterPath: String, scale: Float = 1.0, adapterID: String? = nil) {
        self.init()
        self.adapterPath = adapterPath
        self.scale = scale
        if let id = adapterID { self.adapterID = id }
    }

    public func validate() throws {
        guard !adapterPath.isEmpty else {
            throw SDKException.validationFailed("LoRA adapter path is empty")
        }
        guard scale >= 0 else {
            throw SDKException.validationFailed("LoRA scale must be >= 0 (got \(scale))")
        }
    }
}

// MARK: - RALoraAdapterCatalogEntry

extension RALoraAdapterCatalogEntry {
    public func isCompatible(with baseModelId: String) -> Bool {
        compatibleModels.contains(baseModelId)
    }
}

// MARK: - RALoraCompatibilityResult

extension RALoraCompatibilityResult {
    public static func compatible() -> RALoraCompatibilityResult {
        var r = RALoraCompatibilityResult()
        r.isCompatible = true
        return r
    }

    public static func incompatible(
        reason: String,
        baseModelRequired: String? = nil
    ) -> RALoraCompatibilityResult {
        var r = RALoraCompatibilityResult()
        r.isCompatible = false
        r.errorMessage = reason
        if let base = baseModelRequired { r.baseModelRequired = base }
        return r
    }
}

extension LoRAAdapterInfo {
    public init(from proto: RALoRAAdapterInfo) {
        self.init(
            path: proto.adapterPath,
            scale: proto.scale,
            applied: proto.applied
        )
    }
}

extension LoraCompatibilityResult {
    public init(from proto: RALoraCompatibilityResult) {
        self.init(
            isCompatible: proto.isCompatible,
            error: proto.hasErrorMessage ? proto.errorMessage : nil
        )
    }
}
