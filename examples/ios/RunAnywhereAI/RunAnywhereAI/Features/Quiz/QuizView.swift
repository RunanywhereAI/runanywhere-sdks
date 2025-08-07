import SwiftUI
import RunAnywhereSDK

struct QuizView: View {
    @StateObject private var viewModel = QuizViewModel()
    @State private var showingModelSelection = false

    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ZStack {
                    switch viewModel.viewState {
                    case .input:
                        QuizInputView(viewModel: viewModel)

                    case .generating:
                        QuizGeneratingView()

                    case .quiz:
                        QuizSwipeView(viewModel: viewModel)

                    case .results(let results):
                        QuizResultsView(results: results, viewModel: viewModel)
                    }
                }
                .blur(radius: 3)
                .disabled(true)

                // Coming Soon overlay
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .symbolRenderingMode(.hierarchical)

                        Text("Coming Soon")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("This feature is under development")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
            }
            .navigationTitle("Quiz Generator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingModelSelection = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "cube")
                            Text("Model")
                                .font(.caption)
                        }
                    }
                    .disabled(true)
                    .opacity(0.5)
                }
            }
            .sheet(isPresented: $showingModelSelection) {
                ModelSelectionSheet { model in
                    await handleModelSelected(model)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
    }

    private func handleModelSelected(_ model: ModelInfo) async {
        // Model is already loaded in the SDK by the sheet
        // Could update quiz viewModel if needed
    }
}

struct QuizGeneratingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Generating Quiz...")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Analyzing your content and creating questions")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ProgressView()
                .scaleEffect(1.5)
                .padding(.top)
        }
        .padding()
    }
}

#Preview {
    QuizView()
}
