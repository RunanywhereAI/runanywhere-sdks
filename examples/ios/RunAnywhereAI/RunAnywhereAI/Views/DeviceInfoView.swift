//
//  DeviceInfoView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import SwiftUI

struct DeviceInfoView: View {
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @StateObject private var storageService = StorageMonitorService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshingStorage = false
    @State private var showingDownloadsManagement = false

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

                    // Storage monitoring section
                    if let storageInfo = storageService.storageInfo {
                        Section {
                            DeviceInfoRow(
                                label: "Total App Size",
                                value: storageInfo.totalAppSize.formattedFileSize,
                                valueColor: .primary
                            )
                            DeviceInfoRow(
                                label: "Models Storage",
                                value: storageInfo.modelsSize.formattedFileSize,
                                valueColor: .blue
                            )
                            DeviceInfoRow(
                                label: "Documents",
                                value: storageInfo.documentsSize.formattedFileSize,
                                valueColor: .secondary
                            )
                            DeviceInfoRow(
                                label: "Cache",
                                value: storageInfo.cacheSize.formattedFileSize,
                                valueColor: .secondary
                            )
                            DeviceInfoRow(
                                label: "App % of Device",
                                value: String(format: "%.2f%%", storageInfo.appPercentageOfDevice),
                                valueColor: storageInfo.appPercentageOfDevice > 10 ? .orange : .green
                            )
                        } header: {
                            HStack {
                                Text("App Storage Usage")
                                Spacer()
                                Button(action: {
                                    Task {
                                        isRefreshingStorage = true
                                        await storageService.refreshStorageInfo()
                                        isRefreshingStorage = false
                                    }
                                }) {
                                    if isRefreshingStorage {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(isRefreshingStorage)
                            }
                        }

                        Section("Device Storage") {
                            DeviceInfoRow(
                                label: "Total Storage",
                                value: storageInfo.totalDeviceStorage.formattedFileSize,
                                valueColor: .primary
                            )
                            DeviceInfoRow(
                                label: "Used Storage",
                                value: storageInfo.usedDeviceStorage.formattedFileSize,
                                valueColor: .orange
                            )
                            DeviceInfoRow(
                                label: "Free Storage",
                                value: storageInfo.freeDeviceStorage.formattedFileSize,
                                valueColor: .green
                            )
                        }

                        if !storageInfo.downloadedModels.isEmpty {
                            Section("Downloaded Models (\(storageInfo.downloadedModels.count))") {
                                ForEach(storageInfo.downloadedModels.prefix(5), id: \.path) { model in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(model.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(model.formattedSize)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .fontWeight(.medium)
                                        }

                                        HStack {
                                            Text(model.framework)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("Downloaded \(model.formattedDate)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                if storageInfo.downloadedModels.count > 5 {
                                    Text("+ \(storageInfo.downloadedModels.count - 5) more models")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                                
                                // Manage downloads button
                                Button(action: {
                                    showingDownloadsManagement = true
                                }) {
                                    HStack {
                                        Image(systemName: "folder.badge.gearshape")
                                        Text("Manage All Downloads")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }
                    } else {
                        Section("Storage") {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Calculating storage usage...")
                                    .foregroundColor(.secondary)
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
                    Task {
                        await storageService.refreshStorageInfo()
                    }
                }
                .onDisappear {
                    deviceInfoService.stopMonitoring()
                }
                .sheet(isPresented: $showingDownloadsManagement) {
                    DownloadedModelsManagementView()
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
