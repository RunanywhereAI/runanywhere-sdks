import SwiftUI

struct QuizInputView: View {
    @ObservedObject var viewModel: QuizViewModel
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // Header - Compact version
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create a Quiz")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Paste educational content to generate questions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Input Section with Fixed Height
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Educational Content")
                            .font(.headline)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(viewModel.inputCharacterCount) / \(viewModel.maxInputCharacters)")
                                .font(.caption)
                                .foregroundColor(viewModel.inputCharacterCount > viewModel.maxInputCharacters ? .red : .secondary)

                            Text("~\(viewModel.estimatedQuestionCount) questions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Fixed height TextEditor - 1/3 of screen height
                    ZStack(alignment: .topLeading) {
                        if viewModel.inputText.isEmpty {
                            Text("Paste your lesson, article, or educational content here...")
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        }

                        TextEditor(text: $viewModel.inputText)
                            .focused($isTextEditorFocused)
                            .frame(height: geometry.size.height / 3)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            #if os(iOS)
                            #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                            #else
                            .background(Color(NSColor.controlBackgroundColor))
                            #endif
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    #if os(iOS)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                                    #else
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                    #endif
                            )
                    }

                    if viewModel.inputCharacterCount > viewModel.maxInputCharacters {
                        Label("Content is too long. Please reduce to under \(viewModel.maxInputCharacters) characters.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)

                // Model Status - Compact
                HStack {
                    Image(systemName: viewModel.isModelLoaded ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(viewModel.isModelLoaded ? .green : .orange)
                        .font(.subheadline)

                    if viewModel.isModelLoaded {
                        Text("Using: \(viewModel.loadedModelName ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Please load a model from the Models tab")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
                .padding(.horizontal)

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
                    .padding(.vertical, 14)
                    .background(viewModel.canGenerateQuiz ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!viewModel.canGenerateQuiz)
                .padding(.horizontal)

                // Tips - Scrollable if needed
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tips for better results:", systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 6) {
                            BulletPoint(text: "Use educational content like lessons or articles")
                            BulletPoint(text: "Longer content generates more questions (up to 10)")
                            BulletPoint(text: "Questions test understanding, not memorization")
                            BulletPoint(text: "Each question includes an explanation")
                        }
                    }
                    .padding(12)
                    #if os(iOS)
                    .background(Color(.systemGray6))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                    .cornerRadius(10)
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 16)
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
