//
//  AddModelURLSheet.swift
//  YapRun
//
//  Sheet for adding a custom STT model from a URL.
//  Shared between iOS and macOS.
//

import SwiftUI

struct AddModelURLSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (_ urlString: String, _ name: String) -> Void

    @State private var urlString = ""
    @State private var modelName = ""

    private var isValid: Bool {
        !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/model.tar.gz", text: $urlString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Model URL")
                } footer: {
                    Text("Direct link to an ONNX model file or archive (.tar.gz, .zip).")
                }

                Section("Display Name") {
                    TextField("My Custom Model", text: $modelName)
                }
            }
            .navigationTitle("Add Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(
                            urlString.trimmingCharacters(in: .whitespacesAndNewlines),
                            modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        isPresented = false
                    }
                    .disabled(!isValid)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
