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

            StorageView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(1)

            NavigationView {
                SimplifiedSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)

            QuizView()
                .tabItem {
                    Label("Quiz", systemImage: "questionmark.circle")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
