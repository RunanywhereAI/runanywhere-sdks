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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(0)

            PaytmVoicePaymentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Pay", systemImage: "indianrupeesign.circle.fill")
                }
                .tag(1)

            StorageView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(2)

            Group {
                #if os(macOS)
                SimplifiedSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                NavigationView {
                    SimplifiedSettingsView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)

            QuizView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Quiz", systemImage: "questionmark.circle")
                }
                .tag(4)
        }
        #if os(macOS)
        .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
               minHeight: 600, idealHeight: 800, maxHeight: .infinity)
        #endif
    }
}

#Preview {
    ContentView()
}
