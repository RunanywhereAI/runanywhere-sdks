//
//  DeviceInfoView.swift
//  RunAnywhereAI
//
//  Simplified device info view
//

import SwiftUI

struct DeviceInfoView: View {
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if let info = deviceInfoService.deviceInfo {
                    Section("Device Information") {
                        HStack {
                            Text("Model")
                            Spacer()
                            Text(info.modelName)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("OS Version")
                            Spacer()
                            Text(info.osVersion)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Chip")
                            Spacer()
                            Text(info.chipName)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Total Memory")
                            Spacer()
                            Text(info.totalMemory.formattedFileSize)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Neural Engine")
                            Spacer()
                            Text(info.neuralEngineAvailable ? "Available" : "Not Available")
                                .foregroundColor(info.neuralEngineAvailable ? .green : .secondary)
                        }
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading device information...")
                        }
                    }
                }
            }
            .navigationTitle("Device Info")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await deviceInfoService.refreshDeviceInfo()
        }
    }
}

#Preview {
    DeviceInfoView()
}
