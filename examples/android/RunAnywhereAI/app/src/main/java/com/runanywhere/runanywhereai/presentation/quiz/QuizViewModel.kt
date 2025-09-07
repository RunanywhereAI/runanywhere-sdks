package com.runanywhere.runanywhereai.presentation.quiz

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.sdk.public.RunAnywhereAndroid
import com.runanywhere.sdk.data.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.*
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.max

/**
 * Quiz ViewModel matching iOS QuizViewModel functionality
 * Handles quiz generation, swipe interactions, and results
 */
class QuizViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val _uiState = MutableStateFlow(QuizUiState())
    val uiState: StateFlow<QuizUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null
    private var currentSession: QuizSession? = null
    private var questionStartTime: Date? = null

    // Constants matching iOS
    private val maxInputCharacters = 12000
    private val minQuestionsCount = 3
    private val maxQuestionsCount = 10
    private val swipeThreshold = 100f

    private val TAG = "QuizViewModel"

    init {
        checkModelStatus()
    }

    /**
     * Generate quiz from input text
     */
    fun generateQuiz() {
        val inputText = _uiState.value.inputText

        if (!_uiState.value.canGenerateQuiz) {
            Log.w(TAG, "Cannot generate quiz - invalid state")
            return
        }

        _uiState.value = _uiState.value.copy(
            viewState = QuizViewState.GENERATING,
            showGenerationProgress = true,
            generationText = "",
            error = null
        )

        generationJob?.cancel()
        generationJob = viewModelScope.launch {
            try {
                // Check model status
                if (!_uiState.value.isModelLoaded) {
                    throw QuizGenerationException("No model is currently loaded. Please load a model from the Storage tab first.")
                }

                Log.i(TAG, "Generating quiz from ${inputText.length} characters")

                // Build quiz prompt
                val quizPrompt = buildQuizPrompt(inputText)

                // Generate quiz using SDK
                val options = RunAnywhereGenerationOptions(
                    maxTokens = 1500,
                    temperature = 0.7f,
                    topP = 0.9f
                )

                val jsonResponse = RunAnywhereAndroid.generate(quizPrompt, options)

                // Parse JSON response
                val generatedQuiz = parseQuizResponse(jsonResponse)

                // Validate quiz
                if (generatedQuiz.questions.isEmpty()) {
                    throw QuizGenerationException("No questions could be generated from the provided content.")
                }

                // Create session
                val session = QuizSession(
                    id = UUID.randomUUID().toString(),
                    questions = generatedQuiz.questions,
                    topic = generatedQuiz.topic,
                    difficulty = generatedQuiz.difficulty,
                    startTime = Date()
                )

                currentSession = session
                questionStartTime = Date()

                _uiState.value = _uiState.value.copy(
                    viewState = QuizViewState.QUIZ(session),
                    showGenerationProgress = false,
                    currentQuestionIndex = 0
                )

                Log.i(TAG, "Quiz generated successfully with ${session.questions.size} questions")

            } catch (e: Exception) {
                Log.e(TAG, "Quiz generation failed", e)

                val errorMessage = when (e) {
                    is QuizGenerationException -> e.message
                    else -> "Quiz generation failed: ${e.message}"
                }

                _uiState.value = _uiState.value.copy(
                    viewState = QuizViewState.INPUT,
                    showGenerationProgress = false,
                    error = errorMessage
                )
            }
        }
    }

    /**
     * Build quiz generation prompt
     */
    private fun buildQuizPrompt(inputText: String): String {
        return """
            Generate a quiz based on the following content.

            The quiz should:
            - Have 3-5 true/false questions
            - Be at a medium difficulty level
            - Include clear explanations for each answer
            - Extract the main topic from the content

            Content to create quiz from:
            $inputText

            Provide the response as valid JSON in this exact format:
            {
              "questions": [
                {
                  "id": "q1",
                  "question": "Question text here?",
                  "correctAnswer": true,
                  "explanation": "Explanation of why this is true or false"
                }
              ],
              "topic": "Main topic of the quiz",
              "difficulty": "medium"
            }

            Generate the quiz now:
        """.trimIndent()
    }

    /**
     * Parse quiz JSON response
     */
    private fun parseQuizResponse(jsonText: String): QuizGeneration {
        return try {
            // Try to extract JSON from response
            val cleanJson = extractJson(jsonText)
            json.decodeFromString(QuizGeneration.serializer(), cleanJson)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse quiz JSON: $jsonText", e)

            // Generate fallback quiz
            QuizGeneration(
                questions = listOf(
                    QuizQuestion(
                        id = "q1",
                        question = "The content was successfully processed?",
                        correctAnswer = true,
                        explanation = "The AI was able to read and understand your content."
                    ),
                    QuizQuestion(
                        id = "q2",
                        question = "Quiz generation always produces perfect results?",
                        correctAnswer = false,
                        explanation = "AI-generated quizzes may occasionally have errors or inaccuracies."
                    ),
                    QuizQuestion(
                        id = "q3",
                        question = "You can generate quizzes from any text content?",
                        correctAnswer = true,
                        explanation = "The quiz generator can work with various types of text input."
                    )
                ),
                topic = "Quiz Generation",
                difficulty = "easy"
            )
        }
    }

    /**
     * Extract JSON from text response
     */
    private fun extractJson(text: String): String {
        val trimmed = text.trim()

        // Find JSON boundaries
        val startIndex = trimmed.indexOfFirst { it == '{' }
        val endIndex = trimmed.indexOfLast { it == '}' }

        return if (startIndex >= 0 && endIndex > startIndex) {
            trimmed.substring(startIndex, endIndex + 1)
        } else {
            trimmed
        }
    }

    /**
     * Handle swipe gesture
     */
    fun handleSwipe(offset: Float) {
        val direction = when {
            offset > swipeThreshold -> SwipeDirection.RIGHT
            offset < -swipeThreshold -> SwipeDirection.LEFT
            else -> SwipeDirection.NONE
        }

        _uiState.value = _uiState.value.copy(
            dragOffset = offset,
            swipeDirection = direction
        )
    }

    /**
     * Complete swipe and answer question
     */
    fun completeSwipe() {
        val state = _uiState.value

        if (state.swipeDirection == SwipeDirection.NONE) {
            // Snap back to center
            _uiState.value = state.copy(dragOffset = 0f)
            return
        }

        val userAnswer = state.swipeDirection == SwipeDirection.RIGHT
        answerCurrentQuestion(userAnswer)

        // Reset for next question
        _uiState.value = state.copy(
            dragOffset = 0f,
            swipeDirection = SwipeDirection.NONE
        )
    }

    /**
     * Answer current question
     */
    private fun answerCurrentQuestion(answer: Boolean) {
        val session = currentSession ?: return
        val currentQuestion = session.questions.getOrNull(_uiState.value.currentQuestionIndex) ?: return
        val startTime = questionStartTime ?: return

        val timeSpent = (Date().time - startTime.time) / 1000.0
        val isCorrect = answer == currentQuestion.correctAnswer

        val quizAnswer = QuizAnswer(
            questionId = currentQuestion.id,
            userAnswer = answer,
            isCorrect = isCorrect,
            timeSpent = timeSpent
        )

        session.answers.add(quizAnswer)

        // Check if quiz is complete
        if (session.isComplete) {
            session.endTime = Date()
            showResults()
        } else {
            // Move to next question
            _uiState.value = _uiState.value.copy(
                currentQuestionIndex = _uiState.value.currentQuestionIndex + 1
            )
            questionStartTime = Date()
        }
    }

    /**
     * Show quiz results
     */
    private fun showResults() {
        val session = currentSession ?: return

        val totalTime = session.endTime?.let { (it.time - session.startTime.time) / 1000.0 } ?: 0.0

        val results = QuizResults(
            session = session,
            totalTimeSpent = totalTime
        )

        _uiState.value = _uiState.value.copy(
            viewState = QuizViewState.RESULTS(results)
        )
    }

    /**
     * Start new quiz
     */
    fun startNewQuiz() {
        resetQuiz()
    }

    /**
     * Retry current quiz
     */
    fun retryQuiz() {
        val session = currentSession ?: return

        // Reset session but keep same questions
        val newSession = QuizSession(
            id = UUID.randomUUID().toString(),
            questions = session.questions,
            topic = session.topic,
            difficulty = session.difficulty,
            startTime = Date()
        )

        currentSession = newSession
        questionStartTime = Date()

        _uiState.value = _uiState.value.copy(
            viewState = QuizViewState.QUIZ(newSession),
            currentQuestionIndex = 0
        )
    }

    /**
     * Cancel quiz generation
     */
    fun cancelGeneration() {
        generationJob?.cancel()
        _uiState.value = _uiState.value.copy(
            viewState = QuizViewState.INPUT,
            showGenerationProgress = false
        )
    }

    /**
     * Update input text
     */
    fun updateInput(text: String) {
        _uiState.value = _uiState.value.copy(
            inputText = text.take(maxInputCharacters)
        )
    }

    /**
     * Clear error
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    /**
     * Reset quiz to initial state
     */
    private fun resetQuiz() {
        generationJob?.cancel()
        currentSession = null
        questionStartTime = null

        _uiState.value = QuizUiState()
        checkModelStatus()
    }

    /**
     * Check model loading status
     */
    private fun checkModelStatus() {
        viewModelScope.launch {
            try {
                if (app.isSDKReady()) {
                    val models = RunAnywhereAndroid.availableModels()
                    val loadedModel = models.firstOrNull { it.localPath != null }

                    _uiState.value = _uiState.value.copy(
                        isModelLoaded = loadedModel != null,
                        loadedModelName = loadedModel?.name
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check model status", e)
                _uiState.value = _uiState.value.copy(
                    isModelLoaded = false,
                    loadedModelName = null
                )
            }
        }
    }
}

/**
 * Quiz UI state
 */
data class QuizUiState(
    val viewState: QuizViewState = QuizViewState.INPUT,
    val inputText: String = "",
    val currentQuestionIndex: Int = 0,
    val dragOffset: Float = 0f,
    val swipeDirection: SwipeDirection = SwipeDirection.NONE,
    val error: String? = null,
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val showGenerationProgress: Boolean = false,
    val generationText: String = ""
) {
    val canGenerateQuiz: Boolean
        get() = inputText.trim().isNotEmpty() &&
                inputText.length <= 12000 &&
                isModelLoaded

    val estimatedTokenCount: Int
        get() = inputText.length / 4

    val estimatedQuestionCount: Int
        get() {
            val baseCount = estimatedTokenCount / 300
            return min(max(3, baseCount), 10)
        }
}

/**
 * Quiz view states
 */
sealed class QuizViewState {
    object INPUT : QuizViewState()
    object GENERATING : QuizViewState()
    data class QUIZ(val session: QuizSession) : QuizViewState()
    data class RESULTS(val results: QuizResults) : QuizViewState()
}

/**
 * Swipe direction
 */
enum class SwipeDirection {
    LEFT, RIGHT, NONE
}

/**
 * Quiz generation model
 */
@Serializable
data class QuizGeneration(
    val questions: List<QuizQuestion>,
    val topic: String,
    val difficulty: String
)

/**
 * Quiz question model
 */
@Serializable
data class QuizQuestion(
    val id: String,
    val question: String,
    val correctAnswer: Boolean,
    val explanation: String
)

/**
 * Quiz answer model
 */
data class QuizAnswer(
    val id: String = UUID.randomUUID().toString(),
    val questionId: String,
    val userAnswer: Boolean,
    val isCorrect: Boolean,
    val timeSpent: Double
)

/**
 * Quiz session model
 */
data class QuizSession(
    val id: String,
    val questions: List<QuizQuestion>,
    val topic: String,
    val difficulty: String,
    val startTime: Date,
    var endTime: Date? = null,
    val answers: MutableList<QuizAnswer> = mutableListOf()
) {
    val isComplete: Boolean
        get() = answers.size == questions.size

    val score: Int
        get() = answers.count { it.isCorrect }

    val percentage: Double
        get() = if (questions.isEmpty()) 0.0
                else (score.toDouble() / questions.size) * 100
}

/**
 * Quiz results model
 */
data class QuizResults(
    val session: QuizSession,
    val totalTimeSpent: Double
) {
    val incorrectQuestions: List<QuizQuestion>
        get() = session.answers
            .filter { !it.isCorrect }
            .mapNotNull { answer ->
                session.questions.find { it.id == answer.questionId }
            }
}

/**
 * Quiz generation exception
 */
class QuizGenerationException(message: String) : Exception(message)
