//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI

@main
struct RunAnywhereAIApp: App {
    @StateObject private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .task {
                    // Initialize bundled models on app launch
                    await initializeBundledModels()
                }
        }
    }

    private func initializeBundledModels() async {
        do {
            // Install bundled models from app bundle
            try await BundledModelsService.shared.installBundledModels()

            // Refresh model list
            await modelManager.refreshModelList()
        } catch {
            print("Failed to initialize bundled models: \(error)")
        }
    }
}
