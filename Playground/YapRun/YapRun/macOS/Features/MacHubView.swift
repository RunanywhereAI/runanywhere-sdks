#if os(macOS)
//
//  MacHubView.swift
//  YapRun
//
//  Main Hub window with sidebar navigation: Home, Playground, Notepad, Settings.
//

import SwiftUI

struct MacHubView: View {
    @State private var selectedSection: HubSection = .home
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            MacOnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            .frame(width: 520, height: 560)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(HubSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .home:
            MacHomeView()
        case .playground:
            MacPlaygroundView()
        case .notepad:
            MacNotepadView()
        case .settings:
            MacSettingsView()
        }
    }
}

#endif
