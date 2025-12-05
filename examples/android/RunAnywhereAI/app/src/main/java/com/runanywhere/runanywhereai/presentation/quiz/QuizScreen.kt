package com.runanywhere.runanywhereai.presentation.quiz

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
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
                        canGenerate = uiState.canGenerateQuiz,
                        loadedModelName = uiState.loadedModelName,
                        estimatedQuestionCount = uiState.estimatedQuestionCount
                    )
                }

                QuizViewState.GENERATING -> {
                    QuizGeneratingView()
                }

                is QuizViewState.QUIZ -> {
                    QuizSwipeView(
                        session = (uiState.viewState as QuizViewState.QUIZ).session,
                        currentQuestionIndex = uiState.currentQuestionIndex,
                        dragOffset = uiState.dragOffset,
                        swipeDirection = uiState.swipeDirection,
                        onSwipe = viewModel::handleSwipe,
                        onSwipeComplete = viewModel::completeSwipe,
                        onAnswerFalse = { viewModel.answerWithButton(false) },
                        onAnswerTrue = { viewModel.answerWithButton(true) },
                        onExit = viewModel::resetQuiz
                    )
                }

                is QuizViewState.RESULTS -> {
                    QuizResultsView(
                        results = (uiState.viewState as QuizViewState.RESULTS).results,
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
 * Aligned with iOS QuizInputView
 */
@Composable
fun QuizInputView(
    inputText: String,
    onInputChange: (String) -> Unit,
    onGenerateClick: () -> Unit,
    isModelLoaded: Boolean,
    canGenerate: Boolean,
    loadedModelName: String? = null,
    estimatedQuestionCount: Int = 3
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header - matching iOS QuizInputView
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top
        ) {
            Icon(
                Icons.Default.Psychology,
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Spacer(Modifier.width(12.dp))

            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    "Create a Quiz",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "Paste educational content to generate questions",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Experimental badge - matching iOS
            Column(
                horizontalAlignment = Alignment.End
            ) {
                Row(
                    modifier = Modifier
                        .background(
                            Color(0xFFFF9800).copy(alpha = 0.15f),
                            RoundedCornerShape(8.dp)
                        )
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        modifier = Modifier.size(12.dp),
                        tint = Color(0xFFFF9800)
                    )
                    Text(
                        "EXPERIMENTAL",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFFFF9800)
                    )
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    "🚧 In Development",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
                )
            }
        }

        // Input Section - matching iOS layout
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Header with character count
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom
            ) {
                Text(
                    "Educational Content",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )

                Column(
                    horizontalAlignment = Alignment.End
                ) {
                    Text(
                        "${inputText.length} / 12000",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (inputText.length > 12000)
                            MaterialTheme.colorScheme.error
                        else
                            MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        "~$estimatedQuestionCount questions",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
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
                placeholder = {
                    Text("Paste your lesson, article, or educational content here...")
                },
                maxLines = 15,
                shape = RoundedCornerShape(12.dp)
            )

            // Character limit warning
            if (inputText.length > 12000) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.error
                    )
                    Text(
                        "Content is too long. Please reduce to under 12,000 characters.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }

        // Model status - matching iOS layout
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(12.dp)
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (isModelLoaded) Icons.Default.CheckCircle else Icons.Default.Info,
                    contentDescription = null,
                    tint = if (isModelLoaded) Color(0xFF4CAF50) else Color(0xFFFF9800),
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    if (isModelLoaded) "Using: ${loadedModelName ?: "Unknown"}"
                    else "Please load a model from the Models tab",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Generate button - matching iOS styling
        Button(
            onClick = onGenerateClick,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            enabled = canGenerate,
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
                disabledContainerColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
            )
        ) {
            Icon(
                Icons.Default.AutoAwesome,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "Generate Quiz",
                fontWeight = FontWeight.SemiBold
            )
        }

        // Tips section - matching iOS
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        Icons.Default.Lightbulb,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        "Tips for better results:",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }

                BulletPointItem("Use educational content like lessons or articles")
                BulletPointItem("Longer content generates more questions (up to 10)")
                BulletPointItem("Questions test understanding, not memorization")
                BulletPointItem("Each question includes an explanation")
            }
        }

        Spacer(Modifier.height(16.dp))
    }
}

/**
 * Bullet point item matching iOS BulletPoint view
 */
@Composable
private fun BulletPointItem(text: String) {
    Row(
        modifier = Modifier.padding(start = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            "•",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
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
 * Swipeable quiz cards view - aligned with iOS QuizSwipeView
 */
@Composable
fun QuizSwipeView(
    session: QuizSession,
    currentQuestionIndex: Int,
    dragOffset: Float,
    swipeDirection: SwipeDirection,
    onSwipe: (Float) -> Unit,
    onSwipeComplete: () -> Unit,
    onAnswerFalse: () -> Unit = {},
    onAnswerTrue: () -> Unit = {},
    onExit: () -> Unit = {}
) {
    var showInstructions by remember { mutableStateOf(true) }
    val progressPercentage = if (session.questions.isNotEmpty()) {
        currentQuestionIndex.toFloat() / session.questions.size
    } else 0f

    // Get visible questions (up to 3 stacked)
    val visibleQuestions = session.questions.drop(currentQuestionIndex).take(3)

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Progress Header - matching iOS
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "${currentQuestionIndex + 1} of ${session.questions.size}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            IconButton(onClick = onExit) {
                Icon(
                    Icons.Default.Cancel,
                    contentDescription = "Exit Quiz",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(28.dp)
                )
            }
        }

        // Progress Bar - matching iOS
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .padding(horizontal = 16.dp)
        ) {
            // Background
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        MaterialTheme.colorScheme.surfaceVariant,
                        RoundedCornerShape(2.dp)
                    )
            )
            // Progress
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progressPercentage)
                    .background(
                        MaterialTheme.colorScheme.primary,
                        RoundedCornerShape(2.dp)
                    )
            )
        }

        // Cards Area - stacked cards matching iOS
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(16.dp),
            contentAlignment = Alignment.Center
        ) {
            // Instructions overlay - matching iOS InstructionsOverlay
            if (showInstructions) {
                InstructionsOverlay(
                    onDismiss = { showInstructions = false }
                )
            } else {
                // Stacked cards (back to front)
                visibleQuestions.asReversed().forEachIndexed { reversedIndex, question ->
                    val index = visibleQuestions.size - 1 - reversedIndex
                    val cardScale = 1f - (index * 0.05f)
                    val cardOffsetY = (index * 10).dp
                    val cardOpacity = if (index == 0) 1f else 0.8f

                    QuizCard(
                        question = question,
                        offset = if (index == 0) dragOffset else 0f,
                        swipeDirection = if (index == 0) swipeDirection else SwipeDirection.NONE,
                        modifier = Modifier
                            .fillMaxWidth()
                            .fillMaxHeight(0.7f)
                            .offset(y = cardOffsetY)
                            .scale(cardScale)
                            .alpha(cardOpacity)
                            .then(
                                if (index == 0) {
                                    Modifier
                                        .offset { IntOffset(dragOffset.roundToInt(), 0) }
                                        .rotate(dragOffset / 20f)
                                        .pointerInput(Unit) {
                                            detectDragGestures(
                                                onDragEnd = { onSwipeComplete() }
                                            ) { _, dragAmount ->
                                                onSwipe(dragOffset + dragAmount.x)
                                            }
                                        }
                                } else Modifier
                            )
                    )
                }
            }
        }

        // Bottom Controls - matching iOS with False/True buttons
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 30.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // False button
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                IconButton(
                    onClick = onAnswerFalse,
                    modifier = Modifier
                        .size(60.dp)
                        .alpha(if (swipeDirection == SwipeDirection.LEFT) 1f else 0.6f)
                        .scale(if (swipeDirection == SwipeDirection.LEFT) 1.1f else 1f)
                ) {
                    Icon(
                        Icons.Default.Cancel,
                        contentDescription = "False",
                        modifier = Modifier.size(50.dp),
                        tint = MaterialTheme.colorScheme.error
                    )
                }
                Text(
                    "False",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // True button
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                IconButton(
                    onClick = onAnswerTrue,
                    modifier = Modifier
                        .size(60.dp)
                        .alpha(if (swipeDirection == SwipeDirection.RIGHT) 1f else 0.6f)
                        .scale(if (swipeDirection == SwipeDirection.RIGHT) 1.1f else 1f)
                ) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "True",
                        modifier = Modifier.size(50.dp),
                        tint = Color(0xFF4CAF50)
                    )
                }
                Text(
                    "True",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

/**
 * Instructions overlay - matching iOS InstructionsOverlay
 */
@Composable
fun InstructionsOverlay(
    onDismiss: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth(0.85f)
            .padding(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 20.dp),
        shape = RoundedCornerShape(20.dp)
    ) {
        Column(
            modifier = Modifier.padding(30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                "How to Play",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )

            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = null,
                        modifier = Modifier
                            .size(32.dp)
                            .background(
                                MaterialTheme.colorScheme.error.copy(alpha = 0.1f),
                                CircleShape
                            )
                            .padding(4.dp),
                        tint = MaterialTheme.colorScheme.error
                    )
                    Text("Swipe left or tap ✗ for False")
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        modifier = Modifier
                            .size(32.dp)
                            .background(
                                Color(0xFF4CAF50).copy(alpha = 0.1f),
                                CircleShape
                            )
                            .padding(4.dp),
                        tint = Color(0xFF4CAF50)
                    )
                    Text("Swipe right or tap ✓ for True")
                }
            }

            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text("Got it!")
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
 * Quiz results view - aligned with iOS QuizResultsView
 */
@Composable
fun QuizResultsView(
    results: QuizResults,
    onNewQuiz: () -> Unit,
    onRetry: () -> Unit
) {
    var showingIncorrectAnswers by remember { mutableStateOf(false) }
    val percentage = results.session.percentage
    val scoreColor = when {
        percentage >= 80 -> Color(0xFF4CAF50) // Green
        percentage >= 60 -> Color(0xFFFF9800) // Orange
        else -> MaterialTheme.colorScheme.error // Red
    }
    val performanceMessage = when {
        percentage == 100.0 -> "Perfect Score! 🎉"
        percentage >= 80 -> "Great Job! 👏"
        percentage >= 60 -> "Good Effort! 💪"
        else -> "Keep Practicing! 📚"
    }
    val avgTimePerQuestion = if (results.session.questions.isNotEmpty()) {
        results.totalTimeSpent / results.session.questions.size
    } else 0.0

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        Spacer(Modifier.height(24.dp))

        // Circular Score - matching iOS
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(200.dp)
        ) {
            // Background circle
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawArc(
                    color = Color.Gray.copy(alpha = 0.2f),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = 20.dp.toPx(), cap = StrokeCap.Round)
                )
            }
            // Progress circle
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawArc(
                    color = scoreColor,
                    startAngle = -90f,
                    sweepAngle = (percentage / 100f * 360f).toFloat(),
                    useCenter = false,
                    style = Stroke(width = 20.dp.toPx(), cap = StrokeCap.Round)
                )
            }
            // Score text
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "${results.session.score}",
                    style = MaterialTheme.typography.displayLarge,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "out of ${results.session.questions.size}",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "${percentage.toInt()}%",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = scoreColor
                )
            }
        }

        // Performance Message - matching iOS
        Text(
            performanceMessage,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center
        )

        // Statistics - matching iOS StatRow pattern
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatRow(
                    icon = Icons.Default.Timer,
                    label = "Time Spent",
                    value = formatTime(results.totalTimeSpent),
                    color = MaterialTheme.colorScheme.primary
                )
                StatRow(
                    icon = Icons.Default.CheckCircle,
                    label = "Correct Answers",
                    value = "${results.session.score}",
                    color = Color(0xFF4CAF50)
                )
                StatRow(
                    icon = Icons.Default.Cancel,
                    label = "Incorrect Answers",
                    value = "${results.incorrectQuestions.size}",
                    color = MaterialTheme.colorScheme.error
                )
                StatRow(
                    icon = Icons.Default.Schedule,
                    label = "Avg. Time per Question",
                    value = formatTime(avgTimePerQuestion),
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }

        // Collapsible Review Section - matching iOS
        if (results.incorrectQuestions.isNotEmpty()) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(16.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    // Collapsible header
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .pointerInput(Unit) {
                                detectTapGestures {
                                    showingIncorrectAnswers = !showingIncorrectAnswers
                                }
                            },
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Warning,
                                contentDescription = null,
                                tint = Color(0xFFFF9800)
                            )
                            Text(
                                "Review Incorrect Answers",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium
                            )
                        }
                        Icon(
                            if (showingIncorrectAnswers) Icons.Default.KeyboardArrowUp
                            else Icons.Default.KeyboardArrowDown,
                            contentDescription = "Toggle"
                        )
                    }

                    // Expandable content
                    AnimatedVisibility(visible = showingIncorrectAnswers) {
                        Column(
                            modifier = Modifier.padding(top = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            results.incorrectQuestions.forEach { question ->
                                IncorrectAnswerCard(
                                    question = question,
                                    userAnswer = getUserAnswer(results, question.id)
                                )
                            }
                        }
                    }
                }
            }
        }

        // Action buttons - matching iOS styling
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = onRetry,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Retry Quiz")
            }

            OutlinedButton(
                onClick = onNewQuiz,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("New Quiz")
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

/**
 * Get user answer for a question - matching iOS helper
 */
private fun getUserAnswer(results: QuizResults, questionId: String): Boolean {
    return results.session.answers.find { it.questionId == questionId }?.userAnswer ?: false
}

/**
 * Stat row component - matching iOS StatRow
 */
@Composable
private fun StatRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    color: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(24.dp)
            )
            Text(
                label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

/**
 * Incorrect answer card - matching iOS IncorrectAnswerCard
 */
@Composable
private fun IncorrectAnswerCard(
    question: QuizQuestion,
    userAnswer: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                question.question,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Cancel,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.error
                    )
                    Text(
                        "Your answer: ${if (userAnswer) "True" else "False"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = Color(0xFF4CAF50)
                    )
                    Text(
                        "Correct: ${if (question.correctAnswer) "True" else "False"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFF4CAF50)
                    )
                }
            }

            Text(
                "Explanation:",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Text(
                question.explanation,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
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
