//
//  ModelCompatibilityView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import SwiftUI

struct ModelCompatibilityView: View {
    let model: ModelInfo
    let framework: LLMFramework
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @State private var compatibilityResult: ModelCompatibilityChecker.CompatibilityResult?
    
    var body: some View {
        List {
            Section("Model Information") {
                InfoRow(title: "Name", value: model.name)
                InfoRow(title: "Framework", value: framework.displayName)
                InfoRow(title: "Format", value: model.format.displayName)
                InfoRow(title: "Size", value: model.displaySize)
                if let quantization = model.quantization {
                    InfoRow(title: "Quantization", value: quantization)
                }
            }
            
            if let result = compatibilityResult {
                Section("Compatibility Check") {
                    // Overall Compatibility
                    CompatibilityRow(
                        title: "Overall Compatibility",
                        isCompatible: result.isCompatible,
                        message: result.isCompatible ? "Model is compatible" : "Model has compatibility issues"
                    )
                    
                    // Show errors
                    ForEach(result.errors, id: \.self) { error in
                        CompatibilityRow(
                            title: "Error",
                            isCompatible: false,
                            message: error
                        )
                    }
                    
                    // Show warnings
                    ForEach(result.warnings, id: \.self) { warning in
                        CompatibilityRow(
                            title: "Warning",
                            isCompatible: true,
                            message: warning
                        )
                    }
                    
                    // Neural Engine info for Core ML
                    if framework == .coreML, let deviceInfo = deviceInfoService.deviceInfo {
                        CompatibilityRow(
                            title: "Neural Engine",
                            isCompatible: deviceInfo.neuralEngineAvailable,
                            message: deviceInfo.neuralEngineAvailable ? 
                                "Neural Engine acceleration available" : 
                                "No Neural Engine on this device"
                        )
                    }
                }
                
                Section("Performance Expectations") {
                    if let deviceInfo = deviceInfoService.deviceInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            performanceEstimate(for: model, deviceInfo: deviceInfo)
                        }
                    }
                }
                
                if !result.recommendations.isEmpty {
                    Section("Recommendations") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.recommendations, id: \.self) { recommendation in
                                Label(recommendation, systemImage: "lightbulb")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Checking compatibility...")
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Model Compatibility")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await MainActor.run {
                compatibilityResult = ModelCompatibilityChecker.checkCompatibility(
                    model: model,
                    framework: framework
                )
            }
        }
    }
    
    @ViewBuilder
    private func performanceEstimate(for model: ModelInfo, deviceInfo: SystemDeviceInfo) -> some View {
        let modelSize = extractSizeInBytes(from: model.size)
        let sizeGB = Double(modelSize) / (1_024 * 1_024 * 1_024)
        
        // Rough estimates based on model size and device
        let tokensPerSecond: String = {
            if deviceInfo.neuralEngineAvailable && framework == .coreML {
                if sizeGB < 1 {
                    return "50-100 tokens/sec"
                } else if sizeGB < 3 {
                    return "20-50 tokens/sec"
                } else {
                    return "10-20 tokens/sec"
                }
            } else {
                if sizeGB < 1 {
                    return "20-40 tokens/sec"
                } else if sizeGB < 3 {
                    return "10-20 tokens/sec"
                } else {
                    return "5-10 tokens/sec"
                }
            }
        }()
        
        Label("Estimated Speed: \(tokensPerSecond)", systemImage: "speedometer")
            .foregroundColor(.blue)
        
        if deviceInfo.neuralEngineAvailable && framework == .coreML {
            Label("Neural Engine acceleration available", systemImage: "cpu")
                .foregroundColor(.green)
        }
        
        let loadTime = sizeGB < 1 ? "< 5 seconds" : sizeGB < 3 ? "5-15 seconds" : "15-30 seconds"
        Label("Load Time: \(loadTime)", systemImage: "timer")
            .foregroundColor(.orange)
    }
    
    private func extractSizeInBytes(from sizeString: String) -> Int64 {
        let pattern = #"(\d+\.?\d*)\s*([KMGT]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: sizeString, range: NSRange(sizeString.startIndex..., in: sizeString)),
              let numberRange = Range(match.range(at: 1), in: sizeString),
              let unitRange = Range(match.range(at: 2), in: sizeString),
              let number = Double(sizeString[numberRange]) else {
            return 0
        }
        
        let unit = String(sizeString[unitRange])
        let multiplier: Double = {
            switch unit {
            case "KB": return 1_024
            case "MB": return 1_024 * 1_024
            case "GB": return 1_024 * 1_024 * 1_024
            case "TB": return 1_024 * 1_024 * 1_024 * 1_024
            default: return 1
            }
        }()
        
        return Int64(number * multiplier)
    }
}

struct CompatibilityRow: View {
    let title: String
    let isCompatible: Bool
    let message: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: isCompatible ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isCompatible ? .green : .red)
        }
    }
}

struct ModelCompatibilityView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ModelCompatibilityView(
                model: ModelInfo(
                    name: "Llama 2 7B",
                    format: .gguf,
                    size: "3.8 GB",
                    framework: .llamaCpp,
                    quantization: "Q4_K_M"
                ),
                framework: .llamaCpp
            )
        }
    }
}