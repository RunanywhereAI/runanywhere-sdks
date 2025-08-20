import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct QuizSwipeView: View {
    @ObservedObject var viewModel: QuizViewModel
    @State private var showInstructions = true

    var body: some View {
        VStack(spacing: 0) {
            // Progress Header
            HStack {
                Text(viewModel.progressText)
                    .font(.headline)

                Spacer()

                Button(action: {
                    viewModel.resetQuiz()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        #if os(iOS)
                        .fill(Color(.systemGray5))
                        #else
                        .fill(Color(NSColor.controlBackgroundColor))
                        #endif
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * progressPercentage,
                            height: 4
                        )
                        .animation(.spring(), value: viewModel.currentQuestionIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)

            // Cards Area
            ZStack {
                if showInstructions {
                    InstructionsOverlay(showInstructions: $showInstructions)
                }

                ForEach(visibleQuestions.indices, id: \.self) { index in
                    QuizCardView(
                        question: visibleQuestions[index],
                        offset: cardOffset(for: index),
                        scale: cardScale(for: index),
                        opacity: cardOpacity(for: index)
                    )
                    .offset(x: index == 0 ? viewModel.dragOffset.width : 0)
                    .rotationEffect(.degrees(index == 0 ? Double(viewModel.dragOffset.width / 20) : 0))
                    .gesture(
                        index == 0 ? dragGesture : nil
                    )
                }
            }
            .padding()

            // Bottom Controls
            HStack(spacing: 40) {
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.answerCurrentQuestion(false)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("False")
                            .font(.headline)
                    }
                }
                .opacity(viewModel.swipeDirection == .left ? 1 : 0.6)
                .scaleEffect(viewModel.swipeDirection == .left ? 1.1 : 1)

                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.answerCurrentQuestion(true)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        Text("True")
                            .font(.headline)
                    }
                }
                .opacity(viewModel.swipeDirection == .right ? 1 : 0.6)
                .scaleEffect(viewModel.swipeDirection == .right ? 1.1 : 1)
            }
            .padding(.bottom, 30)
        }
    }

    private var progressPercentage: Double {
        guard case .quiz(let session) = viewModel.viewState,
              !session.generatedQuiz.questions.isEmpty else {
            return 0
        }
        return Double(viewModel.currentQuestionIndex) / Double(session.generatedQuiz.questions.count)
    }

    private var visibleQuestions: [QuizQuestion] {
        guard case .quiz(let session) = viewModel.viewState else {
            return []
        }

        let questions = session.generatedQuiz.questions
        let startIndex = viewModel.currentQuestionIndex
        let endIndex = min(startIndex + 3, questions.count)

        return Array(questions[startIndex..<endIndex])
    }

    private func cardOffset(for index: Int) -> CGSize {
        CGSize(width: 0, height: CGFloat(index * 10))
    }

    private func cardScale(for index: Int) -> CGFloat {
        1.0 - (CGFloat(index) * 0.05)
    }

    private func cardOpacity(for index: Int) -> Double {
        index == 0 ? 1.0 : 0.8
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.handleSwipe(value.translation)
            }
            .onEnded { _ in
                withAnimation(.spring()) {
                    viewModel.completeSwipe()
                }
            }
    }
}

struct InstructionsOverlay: View {
    @Binding var showInstructions: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("How to Play")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Swipe left or tap ✗ for False")
                }

                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("Swipe right or tap ✓ for True")
                }
            }

            Button("Got it!") {
                withAnimation {
                    showInstructions = false
                }
            }
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(30)
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .cornerRadius(20)
        .shadow(radius: 20)
    }
}
