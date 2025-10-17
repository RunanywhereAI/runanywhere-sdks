import SwiftUI
import RunAnywhere

struct QuizView: View {
    @StateObject private var viewModel = QuizViewModel()
    @State private var showingModelSelection = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Use full window without NavigationView
            ZStack {
                // Main content
                Group {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Generation progress overlay
                if viewModel.showGenerationProgress {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    GenerationProgressView(
                        generationText: viewModel.generationText,
                        onCancel: viewModel.cancelGeneration
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingModelSelection = true }) {
                        HStack(spacing: AppSpacing.xSmall) {
                            Image(systemName: "cube")
                            Text("Model")
                                .font(AppTypography.caption)
                        }
                    }
                }
            }
            #else
            // iOS: Keep NavigationView
            NavigationView {
                ZStack {
                    // Main content
                    Group {
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

                    // Generation progress overlay
                    if viewModel.showGenerationProgress {
                        AppColors.overlayLight
                            .ignoresSafeArea()
                            .transition(.opacity)

                        GenerationProgressView(
                            generationText: viewModel.generationText,
                            onCancel: viewModel.cancelGeneration
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
                .navigationTitle("Quiz Generator")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingModelSelection = true }) {
                            HStack(spacing: AppSpacing.xSmall) {
                                Image(systemName: "cube")
                                Text("Model")
                                    .font(AppTypography.caption)
                            }
                        }
                    }
                }
            }
            #endif
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
        .animation(.easeInOut(duration: AppLayout.animationRegular), value: viewModel.showGenerationProgress)
    }

    private func handleModelSelected(_ model: ModelInfo) async {
        // Model is already loaded in the SDK by the sheet
        // Could update quiz viewModel if needed
    }
}

struct QuizGeneratingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            Image(systemName: "brain")
                .font(AppTypography.system60)
                .foregroundColor(AppColors.primaryAccent)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: AppLayout.animationLoopSlow).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Generating Quiz...")
                .font(AppTypography.title2Semibold)

            Text("Analyzing your content and creating questions")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.large)

            ProgressView()
                .scaleEffect(1.5)
                .padding(.top)
        }
        .padding(AppSpacing.large)
    }
}

#Preview {
    QuizView()
}
