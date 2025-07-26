//
//  SettingsView.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("temperature") private var temperature: Double = 0.7
    @AppStorage("maxTokens") private var maxTokens: Double = 150
    @AppStorage("topP") private var topP: Double = 0.95
    @AppStorage("topK") private var topK: Double = 40
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    
    var body: some View {
        Form {
            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(temperature, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                }
                
                VStack(alignment: .leading) {
                    Text("Max Tokens: \(Int(maxTokens))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $maxTokens, in: 10...500, step: 10)
                }
                
                Toggle("Show Advanced Settings", isOn: $showAdvancedSettings)
            }
            
            if showAdvancedSettings {
                Section("Advanced Settings") {
                    VStack(alignment: .leading) {
                        Text("Top P: \(topP, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $topP, in: 0...1, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Top K: \(Int(topK))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $topK, in: 1...100, step: 1)
                    }
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Device Memory")
                    Spacer()
                    Text(deviceMemoryString)
                        .foregroundColor(.secondary)
                }
                
                Link("GitHub Repository", destination: URL(string: "https://github.com/RunanywhereAI/sdks")!)
            }
            
            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var deviceMemoryString: String {
        let memory = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)
    }
    
    private func resetToDefaults() {
        temperature = 0.7
        maxTokens = 150
        topP = 0.95
        topK = 40
        showAdvancedSettings = false
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}