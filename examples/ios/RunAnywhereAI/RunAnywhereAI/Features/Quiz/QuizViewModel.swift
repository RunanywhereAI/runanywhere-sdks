import SwiftUI
import Foundation
import RunAnywhere
import os
import Combine

// MARK: - Quiz Generation Errors

enum QuizGenerationError: LocalizedError {
    case noQuestionsGenerated
    case invalidJSONFormat
    case parsingFailed(String)
    case sdkGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noQuestionsGenerated:
            return "No questions could be generated from the provided content."
        case .invalidJSONFormat:
            return "The AI generated invalid response format. Please try again or load a different model."
        case .parsingFailed(let detail):
            return "Failed to parse AI response: \(detail). Please try again or load a different model."
        case .sdkGenerationFailed(let detail):
            return "Quiz generation failed: \(detail). Please ensure a model is loaded and try again."
        }
    }
}

// MARK: - Quiz Models

struct QuizGeneration: Codable, Generatable {
    let questions: [QuizQuestion]
    let topic: String
    let difficulty: String

    static var jsonSchema: String {
        """
        {
          "type": "object",
          "properties": {
            "questions": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "id": {"type": "string"},
                  "question": {"type": "string"},
                  "correctAnswer": {"type": "boolean"},
                  "explanation": {"type": "string"}
                },
                "required": ["id", "question", "correctAnswer", "explanation"]
              }
            },
            "topic": {"type": "string"},
            "difficulty": {"type": "string", "enum": ["easy", "medium", "hard"]}
          },
          "required": ["questions", "topic", "difficulty"]
        }
        """
    }

    static var generationHints: GenerationHints? {
        GenerationHints(
            temperature: 0.7,
            maxTokens: 1500,
            systemRole: "educational quiz generator"
        )
    }
}

struct QuizQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let correctAnswer: Bool
    let explanation: String
}

struct QuizAnswer: Identifiable {
    let id = UUID()
    let questionId: String
    let userAnswer: Bool
    let isCorrect: Bool
    let timeSpent: TimeInterval
}

struct QuizSession {
    let id = UUID()
    let generatedQuiz: QuizGeneration
    var answers: [QuizAnswer] = []
    let startTime: Date
    var endTime: Date?

    var isComplete: Bool {
        answers.count == generatedQuiz.questions.count
    }

    var score: Int {
        answers.filter { $0.isCorrect }.count
    }

    var percentage: Double {
        guard !generatedQuiz.questions.isEmpty else { return 0 }
        return Double(score) / Double(generatedQuiz.questions.count) * 100
    }
}

struct QuizResults {
    let session: QuizSession
    let totalTimeSpent: TimeInterval

    var incorrectQuestions: [QuizQuestion] {
        session.answers
            .filter { !$0.isCorrect }
            .compactMap { answer in
                session.generatedQuiz.questions.first { $0.id == answer.questionId }
            }
    }
}

enum QuizViewState {
    case input
    case generating
    case quiz(QuizSession)
    case results(QuizResults)
}

enum SwipeDirection {
    case left
    case right
    case none
}

@MainActor
class QuizViewModel: ObservableObject {
    @Published var viewState: QuizViewState = .input
    @Published var inputText: String = ""
    @Published var currentQuestionIndex: Int = 0
    @Published var dragOffset: CGSize = .zero
    @Published var swipeDirection: SwipeDirection = .none
    @Published var error: String?
    @Published var isModelLoaded: Bool = false
    @Published var loadedModelName: String?

    // Streaming UI State
    @Published var showGenerationProgress = false
    @Published var generationText = ""
    @Published var streamingTokens: [String] = []

    private var currentSession: QuizSession?
    private var questionStartTime: Date?
    private var generationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.runanywhere.app", category: "QuizViewModel")

    // Constants
    let maxInputCharacters: Int = 12000
    let minQuestionsCount: Int = 3
    let maxQuestionsCount: Int = 10
    let swipeThreshold: CGFloat = 100

    var estimatedTokenCount: Int {
        inputText.count / 4
    }

    var estimatedQuestionCount: Int {
        let baseCount = estimatedTokenCount / 300
        return min(max(minQuestionsCount, baseCount), maxQuestionsCount)
    }

    var inputCharacterCount: Int {
        inputText.count
    }

    var isInputValid: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        inputCharacterCount <= maxInputCharacters
    }

    var canGenerateQuiz: Bool {
        isInputValid && isModelLoaded
    }

    var currentQuestion: QuizQuestion? {
        guard case .quiz(let session) = viewState,
              currentQuestionIndex < session.generatedQuiz.questions.count else {
            return nil
        }
        return session.generatedQuiz.questions[currentQuestionIndex]
    }

    var progressText: String {
        guard case .quiz(let session) = viewState else { return "" }
        return "\(currentQuestionIndex + 1) of \(session.generatedQuiz.questions.count)"
    }

    init() {
        checkModelStatus()

        // Listen for model loaded notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelLoaded(_:)),
            name: Notification.Name("ModelLoaded"),
            object: nil
        )

        // Listen for model unloaded notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelUnloaded),
            name: Notification.Name("ModelUnloaded"),
            object: nil
        )
    }

    @objc private func modelLoaded(_ notification: Notification) {
        if let model = notification.object as? ModelInfo {
            Task { @MainActor in
                self.isModelLoaded = true
                self.loadedModelName = model.name
            }
        }
    }

    @objc private func modelUnloaded() {
        Task { @MainActor in
            self.isModelLoaded = false
            self.loadedModelName = nil
        }
    }

    private func checkModelStatus() {
        Task { @MainActor in
            // Check if any model is loaded via ModelManager
            let currentModel = ModelManager.shared.getCurrentModel()
            isModelLoaded = currentModel != nil
            loadedModelName = currentModel?.name

            // Also try to check via the shared ModelListViewModel
            if !isModelLoaded {
                let sharedModel = ModelListViewModel.shared.currentModel
                isModelLoaded = sharedModel != nil
                loadedModelName = sharedModel?.name
            }

            logger.info("🔍 Model status check: isLoaded=\(self.isModelLoaded), modelName=\(self.loadedModelName ?? "none")")
        }
    }

    // MARK: - Quiz Generation

    func generateQuiz() async {
        guard isInputValid else {
            return
        }

        viewState = .generating
        showGenerationProgress = true
        generationText = ""
        streamingTokens = []
        error = nil

        // Cancel any existing generation task
        generationTask?.cancel()


        generationTask = Task {
            do {
                // Check if a model is already loaded
                guard isModelLoaded else {
                    throw QuizGenerationError.sdkGenerationFailed("No model is currently loaded. Please load a model from the Models tab first.")
                }

                logger.info("✅ Using already loaded model: \(self.loadedModelName ?? "unknown")")

                // Get user preferences from UserDefaults (now applied per-request)
                let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
                let temperature = savedTemperature != 0 ? savedTemperature : 0.7
                let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
                let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : 10000

                let options = RunAnywhereGenerationOptions(
                    maxTokens: maxTokens,
                    temperature: Float(temperature),
                    topP: 0.9,
                    preferredExecutionTarget: .onDevice  // Force on-device execution
                )

                // Use the new streaming structured output API
                let streamResult = RunAnywhere.generateStructuredStream(
                    QuizGeneration.self,
                    content: inputText,
                    options: options
                )

                // Stream tokens to UI
                for try await token in streamResult.tokenStream {
                    await MainActor.run {
                        self.generationText += token.text
                        self.streamingTokens.append(token.text)
                    }
                }

                // Wait for the final parsed result
                let generatedQuiz = try await streamResult.result.value

                // Validate we have questions
                guard !generatedQuiz.questions.isEmpty else {
                    throw QuizGenerationError.noQuestionsGenerated
                }

                // Create session
                let session = QuizSession(
                    generatedQuiz: generatedQuiz,
                    startTime: Date()
                )

                await MainActor.run {
                    self.currentSession = session
                    self.currentQuestionIndex = 0
                    self.questionStartTime = Date()
                    self.showGenerationProgress = false
                    self.viewState = .quiz(session)
                }

            } catch {
                await MainActor.run {
                    logger.error("🚨 Quiz generation failed: \(error.localizedDescription)")

                    let errorMessage: String
                    if let quizError = error as? QuizGenerationError {
                        errorMessage = quizError.localizedDescription
                    } else if let timeoutError = error as? TimeoutError {
                        errorMessage = "Quiz generation timed out after \(timeoutError.seconds) seconds. The model may be taking too long to respond. Please try again or use a smaller model."
                    } else if error.localizedDescription.contains("No model loaded") || error.localizedDescription.contains("model not found") {
                        errorMessage = "No model is currently loaded. Please go to the Models tab and load a model first."
                    } else if error.localizedDescription.contains("Generated text in cloud") {
                        errorMessage = "The SDK is routing to cloud instead of using the loaded model. Please check your model loading or SDK configuration."
                    } else {
                        errorMessage = "Quiz generation failed: \(error.localizedDescription)"
                    }

                    self.error = errorMessage
                    self.showGenerationProgress = false
                    self.viewState = .input
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        showGenerationProgress = false
        viewState = .input
    }

    // MARK: - Quiz Interaction

    func handleSwipe(_ translation: CGSize) {
        dragOffset = translation

        if translation.width > swipeThreshold {
            swipeDirection = .right
        } else if translation.width < -swipeThreshold {
            swipeDirection = .left
        } else {
            swipeDirection = .none
        }
    }

    func completeSwipe() {
        guard swipeDirection != .none else {
            withAnimation(.spring()) {
                dragOffset = .zero
            }
            return
        }

        let userAnswer = swipeDirection == .right
        answerCurrentQuestion(userAnswer)

        // Reset for next question
        dragOffset = .zero
        swipeDirection = .none
    }

    func answerCurrentQuestion(_ answer: Bool) {
        guard case .quiz(var session) = viewState,
              let question = currentQuestion,
              let startTime = questionStartTime else { return }

        let timeSpent = Date().timeIntervalSince(startTime)
        let isCorrect = answer == question.correctAnswer

        let quizAnswer = QuizAnswer(
            questionId: question.id,
            userAnswer: answer,
            isCorrect: isCorrect,
            timeSpent: timeSpent
        )

        session.answers.append(quizAnswer)

        // Check if quiz is complete
        if session.isComplete {
            session.endTime = Date()
            currentSession = session
            showResults()
        } else {
            // Move to next question
            currentQuestionIndex += 1
            questionStartTime = Date()
            viewState = .quiz(session)
        }
    }

    // MARK: - Results

    private func showResults() {
        guard let session = currentSession else { return }

        let totalTime = session.endTime?.timeIntervalSince(session.startTime) ?? 0
        let results = QuizResults(session: session, totalTimeSpent: totalTime)

        viewState = .results(results)
    }

    // MARK: - Navigation

    func startNewQuiz() {
        resetQuiz()
        // The reset already sets viewState to .input
    }

    func retryQuiz() async {
        guard let session = currentSession else { return }

        // Reset session but keep the same questions
        let newSession = QuizSession(
            generatedQuiz: session.generatedQuiz,
            startTime: Date()
        )

        currentSession = newSession
        currentQuestionIndex = 0
        questionStartTime = Date()
        viewState = .quiz(newSession)
    }

    func reviewIncorrectAnswers() {
        // This could navigate to a review screen
        // For now, we'll just go back to results
    }

    // MARK: - Reset

    func resetQuiz() {
        // Clear all state
        viewState = .input
        inputText = ""
        currentQuestionIndex = 0
        currentSession = nil
        questionStartTime = nil
        dragOffset = .zero
        swipeDirection = .none
        error = nil

        // Cancel any ongoing operations
        withAnimation(.easeInOut(duration: 0.3)) {
            viewState = .input
        }
    }

    // MARK: - Fallback Parsing

    private func parseQuizFromText(_ text: String) throws -> QuizGeneration {
        logger.info("🔍 Parsing quiz from text: \(String(text.prefix(300)))...")

        // Try to extract JSON from the text
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON boundaries
        guard let startIndex = cleanedText.firstIndex(of: "{"),
              let endIndex = cleanedText.lastIndex(of: "}") else {
            logger.warning("⚠️ No JSON boundaries found in generated text")
            throw QuizGenerationError.invalidJSONFormat
        }

        let jsonString = String(cleanedText[startIndex...endIndex])
        logger.info("🔍 Extracted JSON: \(jsonString)")

        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.warning("⚠️ Failed to convert JSON string to data")
            throw QuizGenerationError.invalidJSONFormat
        }

        do {
            let decoded = try JSONDecoder().decode(QuizGeneration.self, from: jsonData)
            logger.info("✅ Successfully decoded quiz with \(decoded.questions.count) questions")
            return decoded
        } catch {
            // If JSON parsing fails, throw an error instead of using fallback
            logger.error("❌ JSON parsing failed: \(error.localizedDescription)")
            throw QuizGenerationError.parsingFailed(error.localizedDescription)
        }
    }

    // Removed fallback quiz - we now show proper error messages instead

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Timeout Utility

struct TimeoutError: Error {
    let seconds: Int

    var localizedDescription: String {
        return "Operation timed out after \(seconds) seconds"
    }
}

func withTimeout<T>(seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(seconds: seconds)
        }

        // Return the first completed task and cancel the other
        guard let result = try await group.next() else {
            throw TimeoutError(seconds: seconds)
        }
        group.cancelAll()
        return result
    }
}
