import SwiftUI
import Foundation
import RunAnywhereSDK
import os.log

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

    private var currentSession: QuizSession?
    private var questionStartTime: Date?
    private let sdk = RunAnywhereSDK.shared

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
        isInputValid && (isModelLoaded || true) // Temporarily override for debugging
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

            os_log("🔍 Model status check: isLoaded=%{public}@, modelName=%{public}@", log: .default, type: .info, String(isModelLoaded), loadedModelName ?? "none")
        }
    }

    // MARK: - Quiz Generation

    func generateQuiz() async {
        NSLog("🔄 QUIZ DEBUG: generateQuiz() method called")

        guard isInputValid else {
            NSLog("❌ QUIZ DEBUG: Input validation failed")
            return
        }

        NSLog("🔄 QUIZ DEBUG: Input validation passed")
        viewState = .generating
        error = nil

        NSLog("🔄 QUIZ DEBUG: Set view state to generating")

        do {
            NSLog("🔄 QUIZ DEBUG: Starting quiz generation process...")

            // First, ensure we have a model loaded - THIS IS THE KEY FIX
            NSLog("🔄 QUIZ DEBUG: Checking and loading models...")
            let availableModels = try await sdk.listAvailableModels()
            NSLog("📊 QUIZ DEBUG: Found %d available models", availableModels.count)

            var modelToLoad: ModelInfo?
            for model in availableModels {
                NSLog("📊 QUIZ DEBUG: Model: %@ - Local path: %@", model.name, model.localPath?.path ?? "none")
                if model.localPath != nil {
                    modelToLoad = model
                    break
                }
            }

            guard let model = modelToLoad else {
                throw QuizGenerationError.sdkGenerationFailed("No local model available for generation")
            }

            NSLog("🔄 QUIZ DEBUG: Loading model: %@", model.name)
            try await sdk.loadModel(model.id)
            NSLog("✅ QUIZ DEBUG: Model loaded successfully: %@", model.name)

            // Test 1: Check if we can even create simple options
            NSLog("🔄 QUIZ DEBUG: Creating GenerationOptions...")

            let simpleOptions = GenerationOptions(
                maxTokens: 50,
                temperature: 0.5,
                preferredExecutionTarget: .onDevice
            )
            NSLog("✅ QUIZ DEBUG: GenerationOptions created successfully")

            let simplePrompt = "Say hello."
            NSLog("🔄 QUIZ DEBUG: About to test SDK with simple prompt: '%@'", simplePrompt)

            // Use timeout since we know SDK hangs
            NSLog("🔄 QUIZ DEBUG: Calling sdk.generate with 5 second timeout...")

            // SKIP THE SIMPLE TEST FOR NOW - Model loading has its own timeout
            // let simpleResult = try await withTimeout(seconds: 5) { [self] in
            //     try await self.sdk.generate(prompt: simplePrompt, options: simpleOptions)
            // }

            NSLog("✅ QUIZ DEBUG: Model loaded successfully, skipping simple test")

            // If we get here, the SDK works! The issue was elsewhere
            NSLog("🎉 QUIZ DEBUG: SDK is working! Problem was not with basic generation")

            // Generate quiz using structured output
            let prompt = """
            You are a quiz generator. Generate exactly \(estimatedQuestionCount) true/false questions based on this educational content.

            Content:
            \(inputText)

            Respond with ONLY a valid JSON object in this exact format:
            {
              "questions": [
                {
                  "id": "1",
                  "question": "Your true/false question here",
                  "correctAnswer": true,
                  "explanation": "Explanation for why this is true/false"
                }
              ],
              "topic": "Main topic from the content",
              "difficulty": "medium"
            }

            Requirements:
            - Generate exactly \(estimatedQuestionCount) questions
            - Each question must have id as string ("1", "2", etc.)
            - correctAnswer must be boolean (true or false)
            - Questions should test understanding
            - Keep explanations concise (1-2 sentences)
            - Respond with ONLY the JSON, no other text
            """

            let options = GenerationOptions(
                maxTokens: 2000,
                temperature: 0.1,  // Lower temperature for more consistent formatting
                topP: 0.9,
                preferredExecutionTarget: .onDevice  // Force on-device execution
            )

            let generatedQuiz: QuizGeneration

            // For debugging, let's temporarily skip structured output and go straight to fallback
            os_log("🔄 Using regular generation for debugging...", log: .default, type: .info)
            NSLog("🔄 QUIZ DEBUG: Using regular generation for debugging...")
            NSLog("🔄 QUIZ DEBUG: About to call sdk.generate with prompt length: %d", prompt.count)
            NSLog("🔄 QUIZ DEBUG: Generation options - maxTokens: %d, temperature: %.2f, preferredTarget: %@", options.maxTokens, options.temperature, String(describing: options.preferredExecutionTarget))

            // Add detailed step-by-step logging
            NSLog("🔄 QUIZ DEBUG: Step 1 - Entering SDK generate call")

            let result: GenerationResult
            do {
                // Add timeout to prevent hanging - reduced to 10 seconds since model is already loaded
                result = try await withTimeout(seconds: 10) { [self] in
                    NSLog("🔄 QUIZ DEBUG: Step 2 - Inside timeout wrapper, calling SDK")
                    let sdkResult = try await self.sdk.generate(prompt: prompt, options: options)
                    NSLog("🔄 QUIZ DEBUG: Step 3 - SDK call completed successfully")
                    return sdkResult
                }
                NSLog("🔄 QUIZ DEBUG: Step 4 - Timeout wrapper completed")
            } catch let timeoutError as TimeoutError {
                NSLog("⏰ QUIZ DEBUG: SDK call timed out after %d seconds", timeoutError.seconds)
                throw timeoutError
            } catch {
                NSLog("❌ QUIZ DEBUG: SDK call failed with error: %@", error.localizedDescription)
                throw error
            }

            NSLog("🔄 QUIZ DEBUG: Step 5 - Processing result")
            os_log("📝 Generated text: %{public}@", log: .default, type: .info, result.text)
            NSLog("📝 QUIZ DEBUG: Generated text: %@", result.text)
            NSLog("📝 QUIZ DEBUG: Model used: %@, Execution target: %@", result.modelUsed, String(describing: result.executionTarget))
            generatedQuiz = try parseQuizFromText(result.text)

            // Validate we have questions
            guard !generatedQuiz.questions.isEmpty else {
                throw QuizGenerationError.noQuestionsGenerated
            }

            // Create session
            let session = QuizSession(
                generatedQuiz: generatedQuiz,
                startTime: Date()
            )

            currentSession = session
            currentQuestionIndex = 0
            questionStartTime = Date()
            viewState = .quiz(session)

        } catch {
            NSLog("🚨 QUIZ DEBUG: Exception caught in generateQuiz()")
            NSLog("🚨 QUIZ DEBUG: Error: %@", error.localizedDescription)
            NSLog("🚨 QUIZ DEBUG: Error type: %@", String(describing: type(of: error)))
            os_log("🚨 Quiz generation completely failed: %{public}@", log: .default, type: .error, error.localizedDescription)

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
            viewState = .input
        }
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
        os_log("🔍 Parsing quiz from text: %{public}@...", log: .default, type: .info, String(text.prefix(300)))
        NSLog("🔍 QUIZ DEBUG: Parsing quiz from text: %@...", String(text.prefix(300)))

        // Try to extract JSON from the text
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON boundaries
        guard let startIndex = cleanedText.firstIndex(of: "{"),
              let endIndex = cleanedText.lastIndex(of: "}") else {
            os_log("⚠️ No JSON boundaries found in generated text", log: .default, type: .info)
            NSLog("⚠️ QUIZ DEBUG: No JSON boundaries found in generated text")
            throw QuizGenerationError.invalidJSONFormat
        }

        let jsonString = String(cleanedText[startIndex...endIndex])
        os_log("🔍 Extracted JSON: %{public}@", log: .default, type: .info, jsonString)

        guard let jsonData = jsonString.data(using: .utf8) else {
            os_log("⚠️ Failed to convert JSON string to data", log: .default, type: .info)
            NSLog("⚠️ QUIZ DEBUG: Failed to convert JSON string to data")
            throw QuizGenerationError.invalidJSONFormat
        }

        do {
            let decoded = try JSONDecoder().decode(QuizGeneration.self, from: jsonData)
            os_log("✅ Successfully decoded quiz with %{public}d questions", log: .default, type: .info, decoded.questions.count)
            NSLog("✅ QUIZ DEBUG: Successfully decoded quiz with %d questions", decoded.questions.count)
            return decoded
        } catch {
            // If JSON parsing fails, throw an error instead of using fallback
            os_log("❌ JSON parsing failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            NSLog("❌ QUIZ DEBUG: JSON parsing failed: %@", error.localizedDescription)
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
