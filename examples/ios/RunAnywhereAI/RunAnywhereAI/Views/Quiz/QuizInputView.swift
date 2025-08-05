import SwiftUI

struct QuizInputView: View {
    @ObservedObject var viewModel: QuizViewModel
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)

                    Text("Create a Quiz")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Paste educational content to generate true/false questions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Educational Content")
                            .font(.headline)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(viewModel.inputCharacterCount) / \(viewModel.maxInputCharacters)")
                                .font(.caption)
                                .foregroundColor(viewModel.inputCharacterCount > viewModel.maxInputCharacters ? .red : .secondary)

                            Text("~\(viewModel.estimatedQuestionCount) questions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if viewModel.inputText.isEmpty {
                            Text("Paste your lesson, article, or educational content here...")
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        }

                        TextEditor(text: $viewModel.inputText)
                            .focused($isTextEditorFocused)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }

                    if viewModel.inputCharacterCount > viewModel.maxInputCharacters {
                        Label("Content is too long. Please reduce to under \(viewModel.maxInputCharacters) characters.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)

                // Model Status (temporarily hidden for debugging)
                if !viewModel.isModelLoaded && false {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)

                        Text("Please load a model from the Models tab to generate quizzes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Generate Button
                Button(action: {
                    isTextEditorFocused = false
                    Task {
                        await viewModel.generateQuiz()
                    }
                }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate Quiz")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canGenerateQuiz ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!viewModel.canGenerateQuiz)
                .padding(.horizontal)

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Tips for better results:", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 8) {
                        BulletPoint(text: "Use educational content like lessons, articles, or study materials")
                        BulletPoint(text: "Longer content generates more questions (up to 10)")
                        BulletPoint(text: "Questions will test understanding, not just memorization")
                        BulletPoint(text: "Each question includes an explanation")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 50)
            }
        }
        .onTapGesture {
            isTextEditorFocused = false
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
