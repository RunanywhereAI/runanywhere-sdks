//
//  KaggleAuthView.swift
//  RunAnywhereAI
//
//  Kaggle authentication view for TensorFlow Lite model downloads
//

import SwiftUI

struct KaggleAuthView: View {
    let model: ModelInfo
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @StateObject private var authService = KaggleAuthService.shared
    @State private var username = ""
    @State private var apiKey = ""
    @State private var isAuthenticating = false
    @State private var showingInstructions = false
    @State private var authError: Error?
    @State private var showingError = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Instructions
                    instructionsSection

                    // Credentials Form
                    credentialsForm

                    // Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Kaggle Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Help") {
                        showingInstructions = true
                    }
                }
            }
            .alert("Authentication Error", isPresented: $showingError) {
                Button("OK") {
                    authError = nil
                }
                Button("View Instructions") {
                    showingInstructions = true
                }
            } message: {
                Text(authError?.localizedDescription ?? "Unknown error")
            }
            .sheet(isPresented: $showingInstructions) {
                KaggleInstructionsView()
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Kaggle Authentication Required")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("The model '\(model.name)' is hosted on Kaggle and requires authentication to download.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Quick Setup")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Sign in to kaggle.com")
                instructionStep(number: 2, text: "Go to Account → API → Create New API Token")
                instructionStep(number: 3, text: "Download kaggle.json and copy credentials below")
            }

            Button("View Detailed Instructions") {
                showingInstructions = true
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.headline)

                TextField("Enter your Kaggle username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.headline)

                SecureField("Enter your Kaggle API key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)

                Text("Your API key should be a 32+ character string from kaggle.json")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: authenticate) {
                HStack {
                    if isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    }
                    Text(isAuthenticating ? "Authenticating..." : "Authenticate")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canAuthenticate ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canAuthenticate || isAuthenticating)

            if authService.isAuthenticated {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Already authenticated as \(authService.currentCredentials?.username ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Use Existing Authentication") {
                        onSuccess()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Sign Out") {
                        authService.logout()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Helper Components

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var canAuthenticate: Bool {
        !username.isEmpty && !apiKey.isEmpty && apiKey.count >= 32
    }

    // MARK: - Actions

    private func authenticate() {
        isAuthenticating = true

        Task {
            do {
                try await authService.authenticate(username: username, apiKey: apiKey)
                await MainActor.run {
                    isAuthenticating = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = error
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Instructions View

struct KaggleInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Get Kaggle API Credentials")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Follow these steps to create your Kaggle API token:")
                            .foregroundColor(.secondary)
                    }

                    // Steps
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(KaggleAuthService.shared.getAuthInstructions().enumerated()), id: \.offset) { index, instruction in
                            instructionStep(number: index + 1, text: instruction)
                        }
                    }

                    // Important Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Important Notes:")
                            .font(.headline)
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 8) {
                            noteItem(icon: "exclamationmark.triangle", text: "Keep your API key secure - don't share it publicly")
                            noteItem(icon: "clock", text: "API keys may have rate limits for downloads")
                            noteItem(icon: "shield", text: "Your credentials are stored securely in iOS Keychain")
                            noteItem(icon: "trash", text: "You can revoke API tokens anytime from your Kaggle account")
                        }
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(12)

                    // Sample kaggle.json
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample kaggle.json format:")
                            .font(.headline)

                        Text(sampleKaggleJson)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Setup Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)

                if number == 4 {
                    Text("This downloads a file called 'kaggle.json'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer()
        }
    }

    private func noteItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var sampleKaggleJson: String {
        """
        {
          "username": "yourusername",
          "key": "1234567890abcdef1234567890abcdef"
        }
        """
    }
}

// MARK: - Preview

#Preview {
    KaggleAuthView(
        model: ModelInfo(
            id: "test-kaggle-model",
            name: "Test Kaggle Model",
            path: nil,
            format: .gguf,
            size: "1.0GB",
            framework: .llamaCpp,
            quantization: nil,
            contextLength: nil,
            isLocal: false,
            downloadURL: URL(string: "https://www.kaggle.com/models/google/test"),
            downloadedFileName: nil,
            modelType: .text,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true,
            alternativeURLs: [],
            notes: nil,
            description: "Test Kaggle model for preview",
            minimumMemory: 0,
            recommendedMemory: 0
        ),
        onSuccess: { },
        onCancel: { }
    )
}
