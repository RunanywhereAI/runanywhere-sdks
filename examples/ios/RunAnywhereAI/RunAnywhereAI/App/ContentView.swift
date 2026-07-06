//
//  ContentView.swift
//  RunAnywhereAI
//
//  Consumer assistant shell. Chat is the product; advanced SDK demos live behind
//  Settings/Advanced instead of top-level tabs.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Group {
            #if os(macOS)
            ConsumerMacShell()
            #else
            ConsumerCompactShell()
            #endif
        }
        .accentColor(AppColors.primaryAccent)
    }
}

#if os(macOS)
private enum ConsumerRootDestination: Hashable {
    case assistant
    case models
    case settings
    case advanced
}

private struct ConsumerMacShell: View {
    @State private var selectedDestination: ConsumerRootDestination? = .assistant

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                Section("RunAnywhere") {
                    NavigationLink(value: ConsumerRootDestination.assistant) {
                        Label("Assistant", systemImage: "sparkles")
                    }
                    NavigationLink(value: ConsumerRootDestination.models) {
                        Label("Models", systemImage: "square.stack.3d.up")
                    }
                }

                Section("Manage") {
                    NavigationLink(value: ConsumerRootDestination.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    NavigationLink(value: ConsumerRootDestination.advanced) {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("RunAnywhere")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            switch selectedDestination ?? .assistant {
            case .assistant:
                ChatInterfaceView()
            case .models:
                SimplifiedModelsView()
            case .settings:
                NavigationStack {
                    CombinedSettingsView()
                }
            case .advanced:
                NavigationStack {
                    ConsumerAdvancedHubView()
                }
            }
        }
        .frame(
            minWidth: 900,
            idealWidth: 1200,
            maxWidth: .infinity,
            minHeight: 620,
            idealHeight: 820,
            maxHeight: .infinity
        )
    }
}
#else
private struct ConsumerCompactShell: View {
    var body: some View {
        ChatInterfaceView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

#Preview {
    ContentView()
}
