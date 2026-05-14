//
//  RAVADTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* VAD types.
//


// MARK: - RAVADConfiguration

extension RAVADConfiguration {
    public var modelId: String? { modelID.isEmpty ? nil : modelID }
}

// Post-Phase-6h, VAD statistics arrive via `rac_vad_component_get_statistics_proto`
// decoded directly into `RAVADStatistics`. The `init(from cStats: rac_energy_vad_stats_t)`
// constructor was orphaned after that migration. Deleted per swift.md
// SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD.

// MARK: - RAVADResult convenience

public extension RAVADResult {
    var isSpeechDetected: Bool { isSpeech }
    var energyLevel: Float { energy }
}
