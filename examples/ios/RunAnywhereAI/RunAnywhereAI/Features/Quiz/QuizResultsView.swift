import SwiftUI

struct QuizResultsView: View {
    let results: QuizResults
    @ObservedObject var viewModel: QuizViewModel
    @State private var showingIncorrectAnswers = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Score Circle
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 20)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: results.session.percentage / 100)
                        .stroke(scoreColor, lineWidth: 20)
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: results.session.percentage)

                    VStack(spacing: 8) {
                        Text("\(results.session.score)")
                            .font(.system(size: 60, weight: .bold, design: .rounded))

                        Text("out of \(results.session.generatedQuiz.questions.count)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("\(Int(results.session.percentage))%")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(scoreColor)
                    }
                }
                .padding(.top, 40)

                // Performance Message
                Text(performanceMessage)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Statistics
                VStack(spacing: 16) {
                    StatRow(
                        icon: "clock.fill",
                        label: "Time Spent",
                        value: formatTime(results.totalTimeSpent)
                    )

                    StatRow(
                        icon: "checkmark.circle.fill",
                        label: "Correct Answers",
                        value: "\(results.session.score)",
                        color: .green
                    )

                    StatRow(
                        icon: "xmark.circle.fill",
                        label: "Incorrect Answers",
                        value: "\(results.incorrectQuestions.count)",
                        color: .red
                    )

                    StatRow(
                        icon: "timer",
                        label: "Avg. Time per Question",
                        value: formatTime(results.totalTimeSpent / Double(results.session.generatedQuiz.questions.count))
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)

                // Review Section
                if !results.incorrectQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            showingIncorrectAnswers.toggle()
                        }) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)

                                Text("Review Incorrect Answers")
                                    .fontWeight(.medium)

                                Spacer()

                                Image(systemName: showingIncorrectAnswers ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)

                        if showingIncorrectAnswers {
                            VStack(spacing: 16) {
                                ForEach(results.incorrectQuestions) { question in
                                    IncorrectAnswerCard(
                                        question: question,
                                        userAnswer: getUserAnswer(for: question.id)
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await viewModel.retryQuiz()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Quiz")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        viewModel.startNewQuiz()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New Quiz")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
    }

    private var scoreColor: Color {
        let percentage = results.session.percentage
        if percentage >= 80 {
            return .green
        } else if percentage >= 60 {
            return .orange
        } else {
            return .red
        }
    }

    private var performanceMessage: String {
        let percentage = results.session.percentage
        if percentage == 100 {
            return "Perfect Score! 🎉"
        } else if percentage >= 80 {
            return "Great Job! 👏"
        } else if percentage >= 60 {
            return "Good Effort! 💪"
        } else {
            return "Keep Practicing! 📚"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }

    private func getUserAnswer(for questionId: String) -> Bool {
        results.session.answers.first { $0.questionId == questionId }?.userAnswer ?? false
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .accentColor

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}

struct IncorrectAnswerCard: View {
    let question: QuizQuestion
    let userAnswer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.question)
                .fontWeight(.medium)

            HStack {
                Label("Your answer: \(userAnswer ? "True" : "False")", systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)

                Spacer()

                Label("Correct: \(question.correctAnswer ? "True" : "False")", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            Text("Explanation:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(question.explanation)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
