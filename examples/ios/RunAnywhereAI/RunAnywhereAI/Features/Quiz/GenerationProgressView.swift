import SwiftUI

struct GenerationProgressView: View {
    let generationText: String
    let onCancel: () -> Void

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Generating Quiz...")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            // Progress indicator
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)

                Text("Creating questions based on your content...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)

            // Token display
            ScrollViewReader { proxy in
                ScrollView {
                    Text(generationText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                        .blur(radius: 8) // Blur the JSON content
                }
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
                .frame(maxHeight: 300)
                .onChange(of: generationText) { _ in
                    // Auto-scroll to bottom as new text appears
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .overlay(
                    // Add a message over the blurred content
                    Text("Generating structured output...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding()
                        #if os(iOS)
                        .background(Color(.systemBackground).opacity(0.9))
                        #else
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        #endif
                        .cornerRadius(8)
                )
            }

            // Info text
            Text("The AI is generating a quiz from your content. You can see the response as it's being created.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                #if os(iOS)
                .fill(Color(.systemBackground))
                #else
                .fill(Color(NSColor.windowBackgroundColor))
                #endif
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding()
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .scale.combined(with: .opacity)
        ))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                isAnimating = true
            }
        }
    }
}
