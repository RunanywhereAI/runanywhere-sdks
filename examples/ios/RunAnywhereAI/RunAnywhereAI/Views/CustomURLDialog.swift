//
//  CustomURLDialog.swift
//  RunAnywhereAI
//
//  Dialog for adding custom URLs for unavailable models
//

import SwiftUI

struct CustomURLDialog: View {
    let model: ModelDownloadInfo
    let onSuccess: (URL) -> Void
    let onCancel: () -> Void
    
    @State private var customURL = ""
    @State private var isValidating = false
    @State private var validationError: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Add Custom URL")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("The original URL for '\(model.name)' is not available. You can provide a custom download URL.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Original URL info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original URL (broken):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(model.url.absoluteString)
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .foregroundColor(.red)
                }
                
                // Custom URL input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom URL:")
                        .font(.headline)
                    
                    TextField("Enter alternative download URL", text: $customURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    
                    Text("Provide a working URL that hosts the same model file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Validation error
                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: validateAndSave) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 8)
                            }
                            Text(isValidating ? "Validating..." : "Use Custom URL")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canUseURL ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canUseURL || isValidating)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.body)
                    .foregroundColor(.red)
                }
            }
            .padding()
            .navigationTitle("Custom URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
    
    private var canUseURL: Bool {
        !customURL.isEmpty && URL(string: customURL) != nil
    }
    
    private func validateAndSave() {
        guard let url = URL(string: customURL) else {
            validationError = "Invalid URL format"
            return
        }
        
        isValidating = true
        validationError = nil
        
        Task {
            do {
                // Validate URL accessibility
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 10
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    isValidating = false
                    
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 200 || httpResponse.statusCode == 302 {
                        onSuccess(url)
                    } else {
                        validationError = "URL is not accessible (status: \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationError = "Failed to validate URL: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    CustomURLDialog(
        model: ModelDownloadInfo(
            id: "test-model",
            name: "Test Model",
            url: URL(string: "https://broken-url.com/model.gguf")!,
            requiresUnzip: false
        ),
        onSuccess: { _ in },
        onCancel: { }
    )
}