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

            SimplifiedModelsView()
                .tabItem {
                    Label("Models", systemImage: "cube")
                }
                .tag(1)

            NavigationView {
                SimplifiedSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToModelsTab"))) { _ in
            selectedTab = 1
        }
    }
}

#Preview {
    ContentView()
}
