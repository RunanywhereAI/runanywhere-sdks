//
//  ContentView.swift
//  SDKTestApp
//

import SwiftUI
import RunAnywhere

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var frameworks: [InferenceFramework] = []
    @State private var isLoadingFrameworks = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                statusList
            }
            .tabItem {
                Label("Status", systemImage: "checkmark.circle")
            }
            .tag(0)

            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "message")
            }
            .tag(1)

            NavigationStack {
                TTSView()
            }
            .tabItem {
                Label("TTS", systemImage: "speaker.wave.2")
            }
            .tag(2)
        }
    }

    private var statusList: some View {
        List {
            Section("SDK Status") {
                Label(
                    RunAnywhere.isActive ? "Active" : "Inactive",
                    systemImage: RunAnywhere.isActive ? "checkmark.circle.fill" : "xmark.circle"
                )
                .foregroundStyle(RunAnywhere.isActive ? .green : .red)
            }

            Section("Registered frameworks") {
                if isLoadingFrameworks {
                    HStack {
                        ProgressView()
                        Text("Loading…")
                    }
                } else if frameworks.isEmpty {
                    Text("None yet (or tap Refresh)")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(frameworks, id: \.self) { fw in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fw.displayName)
                                .font(.headline)
                            Text(fw.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("SDK Test")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task { await loadFrameworks() }
                }
                .disabled(isLoadingFrameworks)
            }
        }
        .refreshable { await loadFrameworks() }
        .task { await loadFrameworks() }
    }

    private func loadFrameworks() async {
        isLoadingFrameworks = true
        defer { isLoadingFrameworks = false }
        frameworks = await RunAnywhere.getRegisteredFrameworks()
    }
}

#Preview {
    ContentView()
}
