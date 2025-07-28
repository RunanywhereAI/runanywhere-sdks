//
//  SettingsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("temperature") private var temperature: Double = 0.7
    @AppStorage("maxTokens") private var maxTokens: Double = 150
    @AppStorage("topP") private var topP: Double = 0.95
    @AppStorage("topK") private var topK: Double = 40
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    @State private var showingFrameworkConfig = false
    @State private var selectedFramework: LLMFramework?

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

            Section("Framework Configuration") {
                ForEach(LLMFramework.availableFrameworks.filter { !$0.isDeferred }, id: \.self) { framework in
                    Button(action: {
                        selectedFramework = framework
                        showingFrameworkConfig = true
                    }) {
                        HStack {
                            Text(framework.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Model Management") {
                NavigationLink(destination: ModelDownloadView()) {
                    Label("Download Models", systemImage: "arrow.down.circle")
                }

                NavigationLink(destination: ModelDownloadStatusView()) {
                    Label("Download Manager", systemImage: "arrow.down.doc")
                }

                NavigationLink(destination: ModelURLSettingsView()) {
                    Label("Model URLs", systemImage: "link")
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

                if let url = URL(string: "https://github.com/RunanywhereAI/sdks") {
                    Link("GitHub Repository", destination: url)
                }
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
        .sheet(isPresented: $showingFrameworkConfig) {
            if let framework = selectedFramework {
                FrameworkConfigurationView(framework: framework)
            }
        }
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
