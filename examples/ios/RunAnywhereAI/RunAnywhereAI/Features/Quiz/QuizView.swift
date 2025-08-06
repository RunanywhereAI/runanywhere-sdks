import SwiftUI
import RunAnywhereSDK

struct QuizView: View {
    @StateObject private var viewModel = QuizViewModel()
    @State private var showingModelSelection = false

    var body: some View {
        NavigationView {
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
