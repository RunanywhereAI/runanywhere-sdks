package com.runanywhere.runanywhereai.presentation.quiz

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Quiz screen matching iOS QuizView functionality
 * Supports quiz generation from text, swipeable cards, and results
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuizScreen(
    viewModel: QuizViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Quiz Generator") },
                actions = {
                    // Model selection button
                    IconButton(
                        onClick = { /* TODO: Show model selection */ }
                    ) {
                        Icon(
                            Icons.Default.Science,
                            contentDescription = "Select Model"
                        )
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Main content based on view state
            when (uiState.viewState) {
                QuizViewState.INPUT -> {
                    QuizInputView(
                        inputText = uiState.inputText,
                        onInputChange = viewModel::updateInput,
                        onGenerateClick = {
                            scope.launch {
                                viewModel.generateQuiz()
                            }
                        },
                        isModelLoaded = uiState.isModelLoaded,
                        canGenerate = uiState.canGenerateQuiz
                    )
                }

                QuizViewState.GENERATING -> {
                    QuizGeneratingView()
                }

                is QuizViewState.QUIZ -> {
                    QuizSwipeView(
                        session = uiState.viewState.session,
                        currentQuestionIndex = uiState.currentQuestionIndex,
                        dragOffset = uiState.dragOffset,
                        swipeDirection = uiState.swipeDirection,
                        onSwipe = viewModel::handleSwipe,
                        onSwipeComplete = viewModel::completeSwipe
                    )
                }

                is QuizViewState.RESULTS -> {
                    QuizResultsView(
                        results = uiState.viewState.results,
                        onNewQuiz = viewModel::startNewQuiz,
                        onRetry = {
                            scope.launch {
                                viewModel.retryQuiz()
                            }
                        }
                    )
                }
            }

            // Generation progress overlay
            AnimatedVisibility(
                visible = uiState.showGenerationProgress,
                enter = fadeIn() + scaleIn(),
                exit = fadeOut() + scaleOut()
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.5f)),
                    contentAlignment = Alignment.Center
                ) {
                    GenerationProgressCard(
                        generationText = uiState.generationText,
                        onCancel = viewModel::cancelGeneration
                    )
                }
            }

            // Error dialog
            uiState.error?.let { error ->
                AlertDialog(
                    onDismissRequest = { viewModel.clearError() },
                    title = { Text("Error") },
                    text = { Text(error) },
                    confirmButton = {
                        TextButton(onClick = { viewModel.clearError() }) {
                            Text("OK")
                        }
                    }
                )
            }
        }
    }
}

/**
 * Quiz input view for entering content to generate quiz from
 */
@Composable
fun QuizInputView(
    inputText: String,
    onInputChange: (String) -> Unit,
    onGenerateClick: () -> Unit,
    isModelLoaded: Boolean,
    canGenerate: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Instructions card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    Icons.Default.Quiz,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    "Create an AI Quiz",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "Enter any text or topic below and AI will generate an interactive quiz for you!",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }

        // Input field
        OutlinedTextField(
            value = inputText,
            onValueChange = onInputChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 200.dp),
            label = { Text("Enter content or topic") },
            placeholder = {
                Text("Paste an article, enter a topic, or describe what you want to learn...")
            },
            supportingText = {
                Text("${inputText.length} / 12000 characters")
            },
            maxLines = 15
        )

        // Model status
        if (!isModelLoaded) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error
                    )
                    Text(
                        "No model loaded. Please load a model first.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }

        // Generate button
        Button(
            onClick = onGenerateClick,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            enabled = canGenerate
        ) {
            Icon(
                Icons.Default.AutoAwesome,
                contentDescription = null,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(8.dp))
            Text("Generate Quiz", fontSize = 18.sp)
        }
    }
}

/**
 * Quiz generating view with animation
 */
@Composable
fun QuizGeneratingView() {
    var rotation by remember { mutableStateOf(0f) }

    LaunchedEffect(Unit) {
        animate(
            initialValue = 0f,
            targetValue = 360f,
            animationSpec = infiniteRepeatable(
                animation = tween(2000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart
            )
        ) { value, _ ->
            rotation = value
        }
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.Psychology,
            contentDescription = null,
            modifier = Modifier
                .size(80.dp)
                .rotate(rotation),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(Modifier.height(24.dp))

        Text(
            "Generating Quiz...",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold
        )

        Spacer(Modifier.height(8.dp))

        Text(
            "Analyzing your content and creating questions",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 32.dp)
        )

        Spacer(Modifier.height(32.dp))

        CircularProgressIndicator(
            modifier = Modifier.size(48.dp)
        )
    }
}

/**
 * Swipeable quiz cards view
 */
@Composable
fun QuizSwipeView(
    session: QuizSession,
    currentQuestionIndex: Int,
    dragOffset: Float,
    swipeDirection: SwipeDirection,
    onSwipe: (Float) -> Unit,
    onSwipeComplete: () -> Unit
) {
    val currentQuestion = session.questions.getOrNull(currentQuestionIndex)
    val density = LocalDensity.current

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Progress indicator
        LinearProgressIndicator(
            progress = (currentQuestionIndex + 1).toFloat() / session.questions.size,
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
        )

        Text(
            "${currentQuestionIndex + 1} of ${session.questions.size}",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(8.dp)
        )

        // Quiz card
        currentQuestion?.let { question ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                contentAlignment = Alignment.Center
            ) {
                QuizCard(
                    question = question,
                    offset = dragOffset,
                    swipeDirection = swipeDirection,
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(0.7f)
                        .offset { IntOffset(dragOffset.roundToInt(), 0) }
                        .pointerInput(Unit) {
                            detectDragGestures(
                                onDragEnd = { onSwipeComplete() }
                            ) { _, dragAmount ->
                                onSwipe(dragOffset + dragAmount.x)
                            }
                        }
                )

                // Swipe indicators
                SwipeIndicators(
                    dragOffset = dragOffset,
                    swipeThreshold = 100f
                )
            }
        }
    }
}

/**
 * Individual quiz card
 */
@Composable
fun QuizCard(
    question: QuizQuestion,
    offset: Float,
    swipeDirection: SwipeDirection,
    modifier: Modifier = Modifier
) {
    val rotation = (offset / 10f).coerceIn(-15f, 15f)
    val scale = 1f - (abs(offset) / 1000f).coerceIn(0f, 0.1f)

    Card(
        modifier = modifier
            .scale(scale)
            .rotate(rotation),
        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = when (swipeDirection) {
                SwipeDirection.LEFT -> MaterialTheme.colorScheme.errorContainer
                SwipeDirection.RIGHT -> MaterialTheme.colorScheme.primaryContainer
                SwipeDirection.NONE -> MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                question.question,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
                fontWeight = FontWeight.Medium
            )

            Spacer(Modifier.height(48.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(32.dp)
            ) {
                // False indicator
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "False",
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.error)
                            .padding(8.dp),
                        tint = MaterialTheme.colorScheme.onError
                    )
                    Text("Swipe Left", style = MaterialTheme.typography.bodySmall)
                }

                // True indicator
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        Icons.Default.Check,
                        contentDescription = "True",
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .padding(8.dp),
                        tint = MaterialTheme.colorScheme.onPrimary
                    )
                    Text("Swipe Right", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

/**
 * Swipe direction indicators
 */
@Composable
fun SwipeIndicators(
    dragOffset: Float,
    swipeThreshold: Float
) {
    val leftAlpha = ((-dragOffset / swipeThreshold).coerceIn(0f, 1f))
    val rightAlpha = ((dragOffset / swipeThreshold).coerceIn(0f, 1f))

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // False indicator
        Box(
            modifier = Modifier
                .alpha(leftAlpha)
                .padding(start = 32.dp)
        ) {
            Icon(
                Icons.Default.Close,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.error
            )
        }

        // True indicator
        Box(
            modifier = Modifier
                .alpha(rightAlpha)
                .padding(end = 32.dp)
        ) {
            Icon(
                Icons.Default.Check,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

/**
 * Quiz results view
 */
@Composable
fun QuizResultsView(
    results: QuizResults,
    onNewQuiz: () -> Unit,
    onRetry: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Score card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Quiz Complete!",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )

                Spacer(Modifier.height(16.dp))

                Text(
                    "${results.session.score} / ${results.session.questions.size}",
                    style = MaterialTheme.typography.displayMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )

                Text(
                    "${results.session.percentage.toInt()}%",
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )

                Spacer(Modifier.height(8.dp))

                Text(
                    "Time: ${formatTime(results.totalTimeSpent)}",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }

        // Incorrect questions
        if (results.incorrectQuestions.isNotEmpty()) {
            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        "Review Incorrect Answers",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )

                    results.incorrectQuestions.forEach { question ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 8.dp)
                        ) {
                            Text(
                                question.question,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Correct: ${if (question.correctAnswer) "True" else "False"}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Text(
                                question.explanation,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Divider(modifier = Modifier.padding(top = 8.dp))
                        }
                    }
                }
            }
        }

        // Action buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedButton(
                onClick = onRetry,
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Retry Quiz")
            }

            Button(
                onClick = onNewQuiz,
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("New Quiz")
            }
        }
    }
}

/**
 * Generation progress card
 */
@Composable
fun GenerationProgressCard(
    generationText: String,
    onCancel: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth(0.9f)
            .padding(16.dp)
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator()

            Spacer(Modifier.height(16.dp))

            Text(
                "Generating Quiz",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold
            )

            if (generationText.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    generationText,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    maxLines = 3
                )
            }

            Spacer(Modifier.height(16.dp))

            TextButton(onClick = onCancel) {
                Text("Cancel")
            }
        }
    }
}

private fun formatTime(seconds: Double): String {
    val minutes = (seconds / 60).toInt()
    val secs = (seconds % 60).toInt()
    return if (minutes > 0) {
        "${minutes}m ${secs}s"
    } else {
        "${secs}s"
    }
}
