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
        // Install bundled models from app bundle
        let success = await BundledModelsService.shared.installBundledModels()

        if !success {
            print("Failed to initialize bundled models")
        }
    }
}
