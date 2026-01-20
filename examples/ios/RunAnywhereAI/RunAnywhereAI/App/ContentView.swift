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
            // Tab 0: Chat (LLM)
            ChatInterfaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(0)

            // Tab 1: Speech-to-Text
            SpeechToTextView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Transcribe", systemImage: "waveform")
                }
                .tag(1)

            // Tab 2: Text-to-Speech
            TextToSpeechView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Speak", systemImage: "speaker.wave.2")
                }
                .tag(2)

            // Tab 3: Voice Assistant (STT + LLM + TTS)
            VoiceAssistantView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Voice", systemImage: "mic")
                }
                .tag(3)

            // Tab 4: Benchmark
            BenchmarkView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Benchmark", systemImage: "speedometer")
                }
                .tag(4)

            // Tab 5: Combined Settings (includes Storage)
            Group {
                #if os(macOS)
                CombinedSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                NavigationView {
                    CombinedSettingsView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(5)
        }
        .accentColor(AppColors.primaryAccent)
        #if os(macOS)
        .frame(
            minWidth: 800,
            idealWidth: 1200,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 800,
            maxHeight: .infinity
        )
        #endif
    }
}

#Preview {
    ContentView()
}
