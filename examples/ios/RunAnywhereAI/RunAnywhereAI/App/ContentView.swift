//
//  ContentView.swift
//  RunAnywhereAI
//
//  Main app navigation with 5 tabs (iOS limit)
//  Organized by AI capability: Chat, Vision, Voice, More utilities, Settings
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Chat - Pure text LLM conversation
            ChatInterfaceView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(0)

            // Tab 1: Vision - Image understanding & generation
            VisionHubView()
                .tabItem {
                    Label("Vision", systemImage: "eye")
                }
                .tag(1)

            // Tab 2: Voice - Voice Assistant (hero feature)
            VoiceAssistantView()
                .tabItem {
                    Label("Voice", systemImage: "mic.circle")
                }
                .tag(2)

            // Tab 3: More - Additional utilities
            MoreHubView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tag(3)

            // Tab 4: Settings
            Group {
                #if os(macOS)
                CombinedSettingsView()
                #else
                NavigationView {
                    CombinedSettingsView()
                }
                .navigationViewStyle(.stack)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(4)
        }
        .accentColor(AppColors.primaryAccent)
        #if os(macOS)
        .frame(
            minWidth: 800, idealWidth: 1200, maxWidth: .infinity,
            minHeight: 600, idealHeight: 800, maxHeight: .infinity
        )
        #endif
    }
}

// MARK: - Vision Hub (VLM + Image Generation)

struct VisionHubView: View {
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        VLMCameraView()
                    } label: {
                        FeatureRow(
                            icon: "camera.viewfinder",
                            iconColor: .purple,
                            title: "Vision Chat",
                            subtitle: "Chat with images using your camera or photos"
                        )
                    }

                    NavigationLink {
                        ImageGenerationView()
                    } label: {
                        FeatureRow(
                            icon: "photo.on.rectangle.angled",
                            iconColor: .pink,
                            title: "Image Generation",
                            subtitle: "Create images from text prompts"
                        )
                    }
                } header: {
                    Text("Vision AI")
                } footer: {
                    Text("Understand and create visual content with AI")
                }
            }
            .navigationTitle("Vision")
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}

// MARK: - More Hub (Additional Utilities)

struct MoreHubView: View {
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        DocumentRAGView()
                    } label: {
                        FeatureRow(
                            icon: "doc.text.magnifyingglass",
                            iconColor: .indigo,
                            title: "Document Q&A",
                            subtitle: "Ask questions about PDF and JSON documents"
                        )
                    }

                    NavigationLink {
                        SpeechToTextView()
                    } label: {
                        FeatureRow(
                            icon: "waveform",
                            iconColor: .blue,
                            title: "Transcribe",
                            subtitle: "Convert speech to text"
                        )
                    }

                    NavigationLink {
                        TextToSpeechView()
                    } label: {
                        FeatureRow(
                            icon: "speaker.wave.2",
                            iconColor: .green,
                            title: "Speak",
                            subtitle: "Convert text to speech"
                        )
                    }

                    NavigationLink {
                        StorageView()
                    } label: {
                        FeatureRow(
                            icon: "folder",
                            iconColor: .orange,
                            title: "Storage",
                            subtitle: "Manage models and files"
                        )
                    }
                } header: {
                    Text("Utilities")
                } footer: {
                    Text("Additional tools and utilities")
                }
            }
            .navigationTitle("More")
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(iconColor)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}
