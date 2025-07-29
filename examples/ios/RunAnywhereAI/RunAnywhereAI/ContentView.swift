//
//  ContentView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatInterfaceView()
            .tabItem {
                Label("Chat", systemImage: "message")
            }
            .tag(0)

            UnifiedModelsView()
                .tabItem {
                    Label("Models", systemImage: "cube")
                }
                .tag(1)

            NavigationView {
                BenchmarkView()
            }
            .tabItem {
                Label("Benchmark", systemImage: "speedometer")
            }
            .tag(2)

            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToModelsTab"))) { _ in
            selectedTab = 1
        }
    }
}

#Preview {
    ContentView()
}
