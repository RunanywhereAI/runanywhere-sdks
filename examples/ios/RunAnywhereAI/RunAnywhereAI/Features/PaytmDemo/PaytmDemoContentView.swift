//
//  PaytmDemoContentView.swift
//  RunAnywhereAI
//
//  Created for VSS Demo on 7/22/25.
//  This is a demo-specific content view for the Paytm presentation
//

import SwiftUI

struct PaytmDemoContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Voice Payment Demo
            PaytmVoicePaymentView()
                .tabItem {
                    Label("Pay", systemImage: "indianrupeesign.circle.fill")
                }
                .tag(0)

            // Merchant Dashboard Demo
            PaytmMerchantDashboard()
                .tabItem {
                    Label("Business", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

            // Original Chat with Paytm styling
            PaytmStyledChatView()
                .tabItem {
                    Label("AI Chat", systemImage: "message.fill")
                }
                .tag(2)

            // Settings
            PaytmSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .accentColor(PaytmTheme.primaryBlue)
    }
}

struct PaytmStyledChatView: View {
    var body: some View {
        ZStack {
            PaytmTheme.lightBlue.opacity(0.3)
                .ignoresSafeArea()

            VStack {
                // Paytm-style header
                HStack {
                    HStack(spacing: 0) {
                        Text("pay")
                            .font(PaytmTheme.headlineFont(24))
                            .foregroundColor(PaytmTheme.primaryBlue)
                        Text("tm")
                            .font(PaytmTheme.headlineFont(24))
                            .foregroundColor(PaytmTheme.secondaryBlue)
                    }
                    Text("AI Assistant")
                        .font(PaytmTheme.bodyFont(18))
                        .foregroundColor(PaytmTheme.grayText)

                    Spacer()
                }
                .padding()
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 2)

                // Original chat interface with minor styling
                ChatInterfaceView()
            }
        }
    }
}

struct PaytmSettingsView: View {
    @State private var isOfflineMode = true
    @State private var enableVoice = true
    @State private var selectedLanguage = "Hindi"

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(PaytmTheme.primaryBlue)
                        Toggle("Offline Mode", isOn: $isOfflineMode)
                            .tint(PaytmTheme.secondaryBlue)
                    }

                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(PaytmTheme.primaryBlue)
                        Toggle("Voice Commands", isOn: $enableVoice)
                            .tint(PaytmTheme.secondaryBlue)
                    }
                } header: {
                    Text("AI Settings")
                        .foregroundColor(PaytmTheme.darkText)
                }

                Section {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(PaytmTheme.primaryBlue)
                        Picker("Language", selection: $selectedLanguage) {
                            Text("English").tag("English")
                            Text("Hindi").tag("Hindi")
                            Text("Tamil").tag("Tamil")
                            Text("Telugu").tag("Telugu")
                            Text("Bengali").tag("Bengali")
                        }
                    }
                } header: {
                    Text("Language")
                        .foregroundColor(PaytmTheme.darkText)
                }

                Section {
                    PerformanceMetricsRow(
                        title: "Average Latency",
                        value: "87ms",
                        comparison: "vs Cloud: 450ms"
                    )

                    PerformanceMetricsRow(
                        title: "Cost per Query",
                        value: "₹0.002",
                        comparison: "vs Cloud: ₹0.15"
                    )

                    PerformanceMetricsRow(
                        title: "Privacy Score",
                        value: "100%",
                        comparison: "All data on-device"
                    )
                } header: {
                    Text("Performance")
                        .foregroundColor(PaytmTheme.darkText)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RunAnywhere SDK")
                            .font(PaytmTheme.headlineFont(16))
                            .foregroundColor(PaytmTheme.darkText)

                        Text("Version 1.0.0")
                            .font(PaytmTheme.captionFont())
                            .foregroundColor(PaytmTheme.grayText)

                        Text("Powered by on-device AI")
                            .font(PaytmTheme.captionFont(12))
                            .foregroundColor(PaytmTheme.secondaryBlue)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct PerformanceMetricsRow: View {
    let title: String
    let value: String
    let comparison: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PaytmTheme.bodyFont())
                    .foregroundColor(PaytmTheme.darkText)
                Text(comparison)
                    .font(PaytmTheme.captionFont(12))
                    .foregroundColor(PaytmTheme.grayText)
            }

            Spacer()

            Text(value)
                .font(PaytmTheme.headlineFont(16))
                .foregroundColor(PaytmTheme.primaryBlue)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PaytmDemoContentView()
}
