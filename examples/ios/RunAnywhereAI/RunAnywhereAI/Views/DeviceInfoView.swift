//
//  DeviceInfoView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import SwiftUI

struct DeviceInfoView: View {
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            if let info = deviceInfoService.deviceInfo {
                List {
                    Section("Device") {
                        DeviceInfoRow(label: "Model", value: info.modelName)
                        DeviceInfoRow(label: "OS Version", value: info.osVersion)
                        DeviceInfoRow(label: "Processor", value: info.processorType)
                        DeviceInfoRow(label: "CPU Cores", value: "\(info.coreCount)")
                        DeviceInfoRow(label: "Neural Engine", value: info.neuralEngineAvailable ? "Available" : "Not Available",
                               valueColor: info.neuralEngineAvailable ? .green : .secondary)
                    }
                    
                    Section("Memory") {
                        DeviceInfoRow(label: "Total Memory", value: info.totalMemory)
                        DeviceInfoRow(label: "Available", value: info.availableMemory, 
                               valueColor: .green)
                        DeviceInfoRow(label: "Used", value: info.usedMemory,
                               valueColor: .orange)
                        DeviceInfoRow(label: "Memory Pressure", value: info.memoryPressure,
                               valueColor: memoryPressureColor(for: info.memoryPressure))
                    }
                    
                    Section("Battery") {
                        DeviceInfoRow(label: "Battery Level", value: "\(info.batteryLevel)%",
                               valueColor: batteryColor(for: info.batteryLevel))
                        DeviceInfoRow(label: "Battery State", value: info.batteryState)
                    }
                    
                    Section("System Status") {
                        DeviceInfoRow(label: "Thermal State", value: info.thermalState,
                               valueColor: thermalStateColor(for: info.thermalState))
                    }
                    
                    Section("AI Capabilities") {
                        if info.neuralEngineAvailable {
                            Label("Neural Engine accelerated inference", systemImage: "cpu")
                                .foregroundColor(.green)
                        }
                        
                        Label("Core ML optimizations available", systemImage: "brain")
                            .foregroundColor(.blue)
                        
                        if info.totalMemory.contains("GB") {
                            if let memoryGB = extractGBValue(from: info.totalMemory), memoryGB >= 6 {
                                Label("Sufficient memory for large models", systemImage: "memorychip")
                                    .foregroundColor(.green)
                            } else {
                                Label("Limited memory for large models", systemImage: "memorychip")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .navigationTitle("Device Information")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    deviceInfoService.startMonitoring()
                }
                .onDisappear {
                    deviceInfoService.stopMonitoring()
                }
            } else {
                ProgressView("Loading device information...")
                    .navigationTitle("Device Information")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
        }
    }
    
    private func memoryPressureColor(for pressure: String) -> Color {
        switch pressure {
        case "Low":
            return .green
        case "Moderate":
            return .yellow
        case "High":
            return .orange
        case "Critical":
            return .red
        default:
            return .secondary
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        switch level {
        case 0..<20:
            return .red
        case 20..<50:
            return .orange
        case 50..<80:
            return .yellow
        default:
            return .green
        }
    }
    
    private func thermalStateColor(for state: String) -> Color {
        switch state {
        case "Normal":
            return .green
        case "Fair":
            return .yellow
        case "Serious":
            return .orange
        case "Critical":
            return .red
        default:
            return .secondary
        }
    }
    
    private func extractGBValue(from memory: String) -> Double? {
        let pattern = #"(\d+\.?\d*)\s*GB"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: memory, range: NSRange(memory.startIndex..., in: memory)),
              let numberRange = Range(match.range(at: 1), in: memory) else {
            return nil
        }
        
        return Double(memory[numberRange])
    }
}

struct DeviceInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .fontWeight(.medium)
        }
    }
}

struct DeviceInfoView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceInfoView()
    }
}