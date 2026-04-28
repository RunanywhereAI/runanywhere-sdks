//
//  RAVADTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* VAD types.
//

import CRACommons
import Foundation

// MARK: - RAVADConfiguration: ComponentConfiguration

extension RAVADConfiguration: ComponentConfiguration {
    public var modelId: String? { modelID.isEmpty ? nil : modelID }
}

// MARK: - RAVADStatistics: C-bridge

public extension RAVADStatistics {
    init(from cStats: rac_energy_vad_stats_t) {
        var s = RAVADStatistics()
        s.currentEnergy = cStats.current
        s.currentThreshold = cStats.threshold
        s.ambientLevel = cStats.ambient
        s.recentAvg = cStats.recent_avg
        s.recentMax = cStats.recent_max
        self = s
    }
}

// MARK: - RAVADResult convenience

public extension RAVADResult {
    var isSpeechDetected: Bool { isSpeech }
    var energyLevel: Float { energy }
}
