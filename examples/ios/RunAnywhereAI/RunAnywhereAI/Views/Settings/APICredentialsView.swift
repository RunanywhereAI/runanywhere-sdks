//
//  APICredentialsView.swift
//  RunAnywhereAI
//
//  Manage API credentials for model downloads
//

import SwiftUI

struct APICredentialsView: View {
    @StateObject private var kaggleAuth = KaggleAuthService.shared
    @StateObject private var huggingFaceAuth = HuggingFaceAuthService.shared
    
    @State private var kaggleUsername = ""
    @State private var kaggleAPIKey = ""
    @State private var huggingFaceToken = ""
    
    @State private var showingKaggleInstructions = false
    @State private var showingHuggingFaceInstructions = false
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""
    
    var body: some View {
        Form {
            // Hugging Face Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: huggingFaceAuth.isAuthenticated ? "checkmark.circle.fill" : "key.fill")
                            .foregroundColor(huggingFaceAuth.isAuthenticated ? .green : .secondary)
                        Text("Hugging Face")
                            .font(.headline)
                        Spacer()
                        if huggingFaceAuth.isAuthenticated {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if !huggingFaceAuth.isAuthenticated {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            SecureField("hf_...", text: $huggingFaceToken)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            HStack {
                                Button("How to Get Token") {
                                    showingHuggingFaceInstructions = true
                                }
                                .font(.caption)
                                
                                Spacer()
                                
                                Button("Connect") {
                                    authenticateHuggingFace()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(huggingFaceToken.isEmpty || isAuthenticating)
                            }
                        }
                    } else {
                        HStack {
                            if let credentials = huggingFaceAuth.currentCredentials {
                                VStack(alignment: .leading) {
                                    Text("Token: \(String(credentials.token.prefix(10)))...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Connected at: \(credentials.createdAt, style: .date)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Disconnect") {
                                huggingFaceAuth.logout()
                                huggingFaceToken = ""
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            } header: {
                Label("Hugging Face", systemImage: "key.fill")
            } footer: {
                Text("Required for downloading models from Hugging Face. Your token is stored securely in Keychain.")
                    .font(.caption)
            }
            
            // Kaggle Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: kaggleAuth.isAuthenticated ? "checkmark.circle.fill" : "person.badge.key")
                            .foregroundColor(kaggleAuth.isAuthenticated ? .green : .secondary)
                        Text("Kaggle")
                            .font(.headline)
                        Spacer()
                        if kaggleAuth.isAuthenticated {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if !kaggleAuth.isAuthenticated {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("Your Kaggle username", text: $kaggleUsername)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            SecureField("Your Kaggle API key", text: $kaggleAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            HStack {
                                Button("How to Get API Key") {
                                    showingKaggleInstructions = true
                                }
                                .font(.caption)
                                
                                Spacer()
                                
                                Button("Connect") {
                                    authenticateKaggle()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(kaggleUsername.isEmpty || kaggleAPIKey.isEmpty || isAuthenticating)
                            }
                        }
                    } else {
                        HStack {
                            if let credentials = kaggleAuth.currentCredentials {
                                VStack(alignment: .leading) {
                                    Text("Username: \(credentials.username)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Connected at: \(credentials.createdAt, style: .date)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Disconnect") {
                                kaggleAuth.logout()
                                kaggleUsername = ""
                                kaggleAPIKey = ""
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            } header: {
                Label("Kaggle", systemImage: "person.badge.key")
            } footer: {
                Text("Required for downloading models from Kaggle. Your credentials are stored securely in Keychain.")
                    .font(.caption)
            }
            
            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Why are credentials needed?", systemImage: "info.circle")
                        .font(.headline)
                    
                    Text("Some model providers require authentication to download their models. Your credentials are stored securely in the iOS Keychain and are only used for downloading models.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• Credentials are never sent to our servers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• You can disconnect at any time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Credentials are removed when you delete the app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("API Credentials")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: .constant(authError != nil)) {
            Button("OK") {
                authError = nil
            }
        } message: {
            Text(authError ?? "")
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") {
                showingSuccessAlert = false
            }
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showingHuggingFaceInstructions) {
            HuggingFaceInstructionsView()
        }
        .sheet(isPresented: $showingKaggleInstructions) {
            KaggleInstructionsView()
        }
        .overlay {
            if isAuthenticating {
                ProgressView("Authenticating...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
            }
        }
    }
    
    private func authenticateHuggingFace() {
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                try await huggingFaceAuth.authenticate(token: huggingFaceToken)
                await MainActor.run {
                    isAuthenticating = false
                    successMessage = "Successfully connected to Hugging Face!"
                    showingSuccessAlert = true
                    // Clear the token field for security
                    huggingFaceToken = ""
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = error.localizedDescription
                }
            }
        }
    }
    
    private func authenticateKaggle() {
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                try await kaggleAuth.authenticate(username: kaggleUsername, apiKey: kaggleAPIKey)
                await MainActor.run {
                    isAuthenticating = false
                    successMessage = "Successfully connected to Kaggle!"
                    showingSuccessAlert = true
                    // Clear the fields for security
                    kaggleUsername = ""
                    kaggleAPIKey = ""
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Instruction Views

struct HuggingFaceInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How to Get Your Hugging Face Token")
                        .font(.title2)
                        .bold()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InstructionStep(number: 1, text: "Go to huggingface.co and sign in")
                        InstructionStep(number: 2, text: "Click on your profile picture in the top right")
                        InstructionStep(number: 3, text: "Select 'Settings' from the dropdown")
                        InstructionStep(number: 4, text: "Navigate to 'Access Tokens' in the left sidebar")
                        InstructionStep(number: 5, text: "Click 'New token' button")
                        InstructionStep(number: 6, text: "Give your token a name (e.g., 'RunAnywhereAI')")
                        InstructionStep(number: 7, text: "Select 'Read' permission (or 'Write' if needed)")
                        InstructionStep(number: 8, text: "Click 'Generate token'")
                        InstructionStep(number: 9, text: "Copy the token (starts with 'hf_')")
                        InstructionStep(number: 10, text: "Paste it in the field above")
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Important Notes", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text("• Keep your token secure - treat it like a password")
                            .font(.caption)
                        Text("• The token will only be stored in your device's Keychain")
                            .font(.caption)
                        Text("• You can revoke the token anytime from Hugging Face settings")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Hugging Face Instructions")
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
}

struct KaggleInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How to Get Your Kaggle API Key")
                        .font(.title2)
                        .bold()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(KaggleAuthService.shared.getAuthInstructions().indices, id: \.self) { index in
                            InstructionStep(number: index + 1, text: KaggleAuthService.shared.getAuthInstructions()[index])
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Important Notes", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text("• Your API key is like a password - keep it secure")
                            .font(.caption)
                        Text("• The credentials will only be stored in your device's Keychain")
                            .font(.caption)
                        Text("• You can regenerate your API key anytime from Kaggle")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Kaggle Instructions")
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
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

#Preview {
    NavigationView {
        APICredentialsView()
    }
}