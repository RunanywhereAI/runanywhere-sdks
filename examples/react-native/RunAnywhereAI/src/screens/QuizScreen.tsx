/**
 * QuizScreen - Quiz Generation Feature
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Quiz/QuizView.swift
 *
 * Features:
 * - Input view for educational content
 * - Swipe-based quiz cards
 * - Results with statistics
 * - Streaming generation progress
 */

import React, { useEffect, useCallback, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TextInput,
  TouchableOpacity,
  Animated,
  PanResponder,
  Dimensions,
  Modal,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography, FontWeight } from '../theme/typography';
import { Spacing, BorderRadius, Padding, IconSize } from '../theme/spacing';
import { useQuizStore, getStoreQuizScore, getStoreQuizPercentage } from '../stores/quizStore';
import {
  QuizViewState,
  SwipeDirection,
  QUIZ_CONSTANTS,
  QuizQuestion,
  QuizResults,
} from '../types/quiz';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

/**
 * Main Quiz Screen Component
 */
export const QuizScreen: React.FC = () => {
  const {
    viewState,
    error,
    showGenerationProgress,
    generationText,
    clearError,
    cancelGeneration,
  } = useQuizStore();

  // Show error alert
  useEffect(() => {
    if (error) {
      Alert.alert('Error', error.message, [
        { text: 'OK', onPress: clearError },
      ]);
    }
  }, [error, clearError]);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Quiz Generator</Text>
        <View style={styles.experimentalBadge}>
          <Icon name="warning" size={12} color={Colors.primaryOrange} />
          <Text style={styles.experimentalText}>EXPERIMENTAL</Text>
        </View>
      </View>

      {/* Main Content */}
      <View style={styles.content}>
        {viewState === QuizViewState.Input && <QuizInputView />}
        {viewState === QuizViewState.Generating && <QuizGeneratingView />}
        {viewState === QuizViewState.Quiz && <QuizSwipeView />}
        {viewState === QuizViewState.Results && <QuizResultsView />}
      </View>

      {/* Generation Progress Overlay */}
      <Modal
        visible={showGenerationProgress}
        transparent
        animationType="fade"
        onRequestClose={cancelGeneration}
      >
        <View style={styles.overlay}>
          <View style={styles.progressCard}>
            <Text style={styles.progressTitle}>Generating Quiz...</Text>
            <ActivityIndicator size="large" color={Colors.primaryAccent} />
            <ScrollView style={styles.progressTextContainer}>
              <Text style={styles.progressText}>{generationText}</Text>
            </ScrollView>
            <TouchableOpacity
              style={styles.cancelButton}
              onPress={cancelGeneration}
            >
              <Text style={styles.cancelButtonText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
};

/**
 * Quiz Input View - Enter educational content
 */
const QuizInputView: React.FC = () => {
  const {
    inputText,
    setInputText,
    isModelLoaded,
    loadedModelName,
    canGenerateQuiz,
    inputCharacterCount,
    estimatedQuestionCount,
    generateQuiz,
  } = useQuizStore();

  const maxChars = QUIZ_CONSTANTS.MAX_INPUT_CHARACTERS;
  const isOverLimit = inputCharacterCount > maxChars;

  return (
    <ScrollView style={styles.inputContainer} keyboardShouldPersistTaps="handled">
      {/* Header Section */}
      <View style={styles.inputHeader}>
        <Icon name="brain" size={40} color={Colors.primaryAccent} />
        <View style={styles.inputHeaderText}>
          <Text style={styles.inputTitle}>Create a Quiz</Text>
          <Text style={styles.inputSubtitle}>
            Paste educational content to generate questions
          </Text>
        </View>
      </View>

      {/* Input Section */}
      <View style={styles.inputSection}>
        <View style={styles.inputLabelRow}>
          <Text style={styles.inputLabel}>Educational Content</Text>
          <View style={styles.inputStats}>
            <Text style={[styles.charCount, isOverLimit && styles.charCountError]}>
              {inputCharacterCount} / {maxChars}
            </Text>
            <Text style={styles.questionEstimate}>
              ~{estimatedQuestionCount} questions
            </Text>
          </View>
        </View>

        <TextInput
          style={styles.textArea}
          value={inputText}
          onChangeText={setInputText}
          placeholder="Paste your lesson, article, or educational content here..."
          placeholderTextColor={Colors.textTertiary}
          multiline
          textAlignVertical="top"
        />

        {isOverLimit && (
          <View style={styles.errorRow}>
            <Icon name="warning" size={14} color={Colors.primaryRed} />
            <Text style={styles.errorText}>
              Content is too long. Please reduce to under {maxChars} characters.
            </Text>
          </View>
        )}
      </View>

      {/* Model Status */}
      <View style={styles.modelStatusCard}>
        <Icon
          name={isModelLoaded ? 'checkmark-circle' : 'information-circle'}
          size={20}
          color={isModelLoaded ? Colors.statusGreen : Colors.statusOrange}
        />
        <Text style={styles.modelStatusText}>
          {isModelLoaded
            ? `Using: ${loadedModelName || 'Unknown'}`
            : 'Please load a model from the Settings tab'}
        </Text>
      </View>

      {/* Generate Button */}
      <TouchableOpacity
        style={[
          styles.generateButton,
          !canGenerateQuiz && styles.generateButtonDisabled,
        ]}
        onPress={generateQuiz}
        disabled={!canGenerateQuiz}
      >
        <Icon name="sparkles" size={20} color={Colors.textWhite} />
        <Text style={styles.generateButtonText}>Generate Quiz</Text>
      </TouchableOpacity>

      {/* Tips Section */}
      <View style={styles.tipsCard}>
        <View style={styles.tipsHeader}>
          <Icon name="bulb" size={18} color={Colors.primaryAccent} />
          <Text style={styles.tipsTitle}>Tips for better results:</Text>
        </View>
        <View style={styles.tipsList}>
          <BulletPoint text="Use educational content like lessons or articles" />
          <BulletPoint text="Longer content generates more questions (up to 10)" />
          <BulletPoint text="Questions test understanding, not memorization" />
          <BulletPoint text="Each question includes an explanation" />
        </View>
      </View>
    </ScrollView>
  );
};

/**
 * Bullet point component for tips
 */
const BulletPoint: React.FC<{ text: string }> = ({ text }) => (
  <View style={styles.bulletPoint}>
    <View style={styles.bullet} />
    <Text style={styles.bulletText}>{text}</Text>
  </View>
);

/**
 * Quiz Generating View - Loading state
 */
const QuizGeneratingView: React.FC = () => {
  const rotation = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const animation = Animated.loop(
      Animated.timing(rotation, {
        toValue: 1,
        duration: 2000,
        useNativeDriver: true,
      })
    );
    animation.start();
    return () => animation.stop();
  }, [rotation]);

  const rotateInterpolate = rotation.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  return (
    <View style={styles.generatingContainer}>
      <Animated.View style={{ transform: [{ rotate: rotateInterpolate }] }}>
        <Icon name="brain" size={60} color={Colors.primaryAccent} />
      </Animated.View>
      <Text style={styles.generatingTitle}>Generating Quiz...</Text>
      <Text style={styles.generatingSubtitle}>
        Analyzing your content and creating questions
      </Text>
      <ActivityIndicator
        size="large"
        color={Colors.primaryAccent}
        style={styles.generatingSpinner}
      />
    </View>
  );
};

/**
 * Quiz Swipe View - Interactive quiz cards
 */
const QuizSwipeView: React.FC = () => {
  const {
    currentQuestionIndex,
    progressText,
    progressPercentage,
    visibleQuestions,
    handleSwipe,
    completeSwipe,
    answerCurrentQuestion,
    swipeDirection,
    resetQuiz,
  } = useQuizStore();

  const [showInstructions, setShowInstructions] = React.useState(true);
  const pan = useRef(new Animated.ValueXY()).current;

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderMove: (_, gestureState) => {
        pan.setValue({ x: gestureState.dx, y: 0 });
        handleSwipe({ x: gestureState.dx, y: gestureState.dy });
      },
      onPanResponderRelease: () => {
        completeSwipe();
        Animated.spring(pan, {
          toValue: { x: 0, y: 0 },
          useNativeDriver: true,
        }).start();
      },
    })
  ).current;

  const handleAnswer = useCallback(
    (answer: boolean) => {
      answerCurrentQuestion(answer);
    },
    [answerCurrentQuestion]
  );

  return (
    <View style={styles.swipeContainer}>
      {/* Progress Header */}
      <View style={styles.progressHeader}>
        <Text style={styles.progressHeaderText}>{progressText}</Text>
        <TouchableOpacity onPress={resetQuiz}>
          <Icon name="close-circle" size={28} color={Colors.textSecondary} />
        </TouchableOpacity>
      </View>

      {/* Progress Bar */}
      <View style={styles.progressBarContainer}>
        <View style={styles.progressBarBg} />
        <Animated.View
          style={[
            styles.progressBarFill,
            { width: `${progressPercentage * 100}%` },
          ]}
        />
      </View>

      {/* Cards Area */}
      <View style={styles.cardsArea}>
        {showInstructions ? (
          <InstructionsOverlay onDismiss={() => setShowInstructions(false)} />
        ) : (
          visibleQuestions.map((question, index) => (
            <QuizCardView
              key={question.id}
              question={question}
              index={index}
              pan={index === 0 ? pan : undefined}
              panResponder={index === 0 ? panResponder : undefined}
              swipeDirection={index === 0 ? swipeDirection : SwipeDirection.None}
            />
          )).reverse()
        )}
      </View>

      {/* Bottom Controls */}
      <View style={styles.bottomControls}>
        <TouchableOpacity
          style={[
            styles.answerButton,
            styles.falseButton,
            swipeDirection === SwipeDirection.Left && styles.answerButtonActive,
          ]}
          onPress={() => handleAnswer(false)}
        >
          <Icon name="close-circle" size={50} color={Colors.primaryRed} />
          <Text style={styles.answerButtonLabel}>False</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[
            styles.answerButton,
            styles.trueButton,
            swipeDirection === SwipeDirection.Right && styles.answerButtonActive,
          ]}
          onPress={() => handleAnswer(true)}
        >
          <Icon name="checkmark-circle" size={50} color={Colors.statusGreen} />
          <Text style={styles.answerButtonLabel}>True</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

/**
 * Quiz Card View - Individual question card
 */
interface QuizCardViewProps {
  question: QuizQuestion;
  index: number;
  pan?: Animated.ValueXY;
  panResponder?: ReturnType<typeof PanResponder.create>;
  swipeDirection: SwipeDirection;
}

const QuizCardView: React.FC<QuizCardViewProps> = ({
  question,
  index,
  pan,
  panResponder,
  swipeDirection,
}) => {
  const scale = 1 - index * 0.05;
  const translateY = index * 10;

  const cardStyle = pan
    ? {
        transform: [
          { translateX: pan.x },
          { translateY },
          { scale },
          {
            rotate: pan.x.interpolate({
              inputRange: [-200, 0, 200],
              outputRange: ['-10deg', '0deg', '10deg'],
            }),
          },
        ],
        opacity: index === 0 ? 1 : 0.8,
      }
    : {
        transform: [{ translateY }, { scale }],
        opacity: 0.8,
      };

  return (
    <Animated.View
      style={[styles.quizCard, cardStyle]}
      {...(panResponder?.panHandlers || {})}
    >
      {/* Swipe Overlay */}
      {index === 0 && swipeDirection !== SwipeDirection.None && (
        <View
          style={[
            styles.swipeOverlay,
            swipeDirection === SwipeDirection.Left
              ? styles.swipeOverlayFalse
              : styles.swipeOverlayTrue,
          ]}
        >
          <Icon
            name={
              swipeDirection === SwipeDirection.Left
                ? 'close-circle'
                : 'checkmark-circle'
            }
            size={80}
            color={
              swipeDirection === SwipeDirection.Left
                ? Colors.primaryRed
                : Colors.statusGreen
            }
          />
          <Text
            style={[
              styles.swipeOverlayText,
              swipeDirection === SwipeDirection.Left
                ? styles.swipeOverlayTextFalse
                : styles.swipeOverlayTextTrue,
            ]}
          >
            {swipeDirection === SwipeDirection.Left ? 'FALSE' : 'TRUE'}
          </Text>
        </View>
      )}

      {/* Card Content */}
      <View style={styles.cardHeader}>
        <Text style={styles.cardLabel}>Question</Text>
      </View>

      <ScrollView style={styles.cardContent}>
        <Text style={styles.questionText}>{question.question}</Text>
      </ScrollView>

      <View style={styles.cardFooter}>
        <View style={styles.swipeHint}>
          <Icon name="arrow-back" size={16} color={Colors.primaryRed} />
          <Text style={styles.swipeHintTextFalse}>FALSE</Text>
        </View>
        <View style={styles.swipeHint}>
          <Text style={styles.swipeHintTextTrue}>TRUE</Text>
          <Icon name="arrow-forward" size={16} color={Colors.statusGreen} />
        </View>
      </View>
    </Animated.View>
  );
};

/**
 * Instructions Overlay
 */
interface InstructionsOverlayProps {
  onDismiss: () => void;
}

const InstructionsOverlay: React.FC<InstructionsOverlayProps> = ({
  onDismiss,
}) => (
  <View style={styles.instructionsOverlay}>
    <Text style={styles.instructionsTitle}>How to Play</Text>

    <View style={styles.instructionsRow}>
      <Icon name="arrow-back-circle" size={32} color={Colors.primaryRed} />
      <Text style={styles.instructionsText}>Swipe left or tap X for False</Text>
    </View>

    <View style={styles.instructionsRow}>
      <Icon name="arrow-forward-circle" size={32} color={Colors.statusGreen} />
      <Text style={styles.instructionsText}>
        Swipe right or tap check for True
      </Text>
    </View>

    <TouchableOpacity style={styles.gotItButton} onPress={onDismiss}>
      <Text style={styles.gotItButtonText}>Got it!</Text>
    </TouchableOpacity>
  </View>
);

/**
 * Quiz Results View
 */
const QuizResultsView: React.FC = () => {
  const { quizResults, currentSession, retryQuiz, startNewQuiz } =
    useQuizStore();

  const [showIncorrect, setShowIncorrect] = React.useState(false);

  if (!quizResults || !currentSession) return null;

  const score = getStoreQuizScore(currentSession);
  const percentage = getStoreQuizPercentage(currentSession);
  const totalQuestions = currentSession.generatedQuiz.questions.length;

  const getScoreColor = () => {
    if (percentage >= 80) return Colors.statusGreen;
    if (percentage >= 60) return Colors.primaryOrange;
    return Colors.primaryRed;
  };

  const getPerformanceMessage = () => {
    if (percentage === 100) return 'Perfect Score! ';
    if (percentage >= 80) return 'Great Job! ';
    if (percentage >= 60) return 'Good Effort! ';
    return 'Keep Practicing! ';
  };

  const formatTime = (ms: number) => {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds.toFixed(1)}s`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}m ${remainingSeconds}s`;
  };

  const avgTimePerQuestion = quizResults.totalTimeSpent / totalQuestions;

  return (
    <ScrollView style={styles.resultsContainer}>
      {/* Score Circle */}
      <View style={styles.scoreCircleContainer}>
        <View style={[styles.scoreCircle, { borderColor: getScoreColor() }]}>
          <Text style={styles.scoreNumber}>{score}</Text>
          <Text style={styles.scoreOutOf}>out of {totalQuestions}</Text>
          <Text style={[styles.scorePercentage, { color: getScoreColor() }]}>
            {Math.round(percentage)}%
          </Text>
        </View>
      </View>

      {/* Performance Message */}
      <Text style={styles.performanceMessage}>{getPerformanceMessage()}</Text>

      {/* Statistics */}
      <View style={styles.statsCard}>
        <StatRow
          icon="time"
          label="Time Spent"
          value={formatTime(quizResults.totalTimeSpent)}
          color={Colors.primaryAccent}
        />
        <StatRow
          icon="checkmark-circle"
          label="Correct Answers"
          value={`${score}`}
          color={Colors.statusGreen}
        />
        <StatRow
          icon="close-circle"
          label="Incorrect Answers"
          value={`${quizResults.incorrectQuestions.length}`}
          color={Colors.primaryRed}
        />
        <StatRow
          icon="timer"
          label="Avg. Time per Question"
          value={formatTime(avgTimePerQuestion)}
          color={Colors.primaryAccent}
        />
      </View>

      {/* Incorrect Answers Review */}
      {quizResults.incorrectQuestions.length > 0 && (
        <View style={styles.reviewSection}>
          <TouchableOpacity
            style={styles.reviewHeader}
            onPress={() => setShowIncorrect(!showIncorrect)}
          >
            <Icon name="warning" size={20} color={Colors.primaryOrange} />
            <Text style={styles.reviewTitle}>Review Incorrect Answers</Text>
            <Icon
              name={showIncorrect ? 'chevron-up' : 'chevron-down'}
              size={20}
              color={Colors.textSecondary}
            />
          </TouchableOpacity>

          {showIncorrect && (
            <View style={styles.incorrectList}>
              {quizResults.incorrectQuestions.map(question => {
                const userAnswer = currentSession.answers.find(
                  a => a.questionId === question.id
                )?.userAnswer;
                return (
                  <IncorrectAnswerCard
                    key={question.id}
                    question={question}
                    userAnswer={userAnswer ?? false}
                  />
                );
              })}
            </View>
          )}
        </View>
      )}

      {/* Action Buttons */}
      <View style={styles.resultActions}>
        <TouchableOpacity style={styles.retryButton} onPress={retryQuiz}>
          <Icon name="refresh" size={20} color={Colors.textWhite} />
          <Text style={styles.retryButtonText}>Retry Quiz</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.newQuizButton} onPress={startNewQuiz}>
          <Icon name="add-circle" size={20} color={Colors.textPrimary} />
          <Text style={styles.newQuizButtonText}>New Quiz</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
};

/**
 * Statistics Row
 */
interface StatRowProps {
  icon: string;
  label: string;
  value: string;
  color: string;
}

const StatRow: React.FC<StatRowProps> = ({ icon, label, value, color }) => (
  <View style={styles.statRow}>
    <Icon name={icon} size={20} color={color} style={styles.statIcon} />
    <Text style={styles.statLabel}>{label}</Text>
    <Text style={styles.statValue}>{value}</Text>
  </View>
);

/**
 * Incorrect Answer Card
 */
interface IncorrectAnswerCardProps {
  question: QuizQuestion;
  userAnswer: boolean;
}

const IncorrectAnswerCard: React.FC<IncorrectAnswerCardProps> = ({
  question,
  userAnswer,
}) => (
  <View style={styles.incorrectCard}>
    <Text style={styles.incorrectQuestion}>{question.question}</Text>

    <View style={styles.answerComparison}>
      <View style={styles.answerRow}>
        <Icon name="close-circle" size={16} color={Colors.primaryRed} />
        <Text style={styles.answerLabel}>
          Your answer: {userAnswer ? 'True' : 'False'}
        </Text>
      </View>
      <View style={styles.answerRow}>
        <Icon name="checkmark-circle" size={16} color={Colors.statusGreen} />
        <Text style={styles.answerLabel}>
          Correct: {question.correctAnswer ? 'True' : 'False'}
        </Text>
      </View>
    </View>

    <Text style={styles.explanationLabel}>Explanation:</Text>
    <Text style={styles.explanationText}>{question.explanation}</Text>
  </View>
);

/**
 * Styles
 */
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  headerTitle: {
    ...Typography.title2,
  },
  experimentalBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.badgeOrange,
    paddingHorizontal: Padding.padding8,
    paddingVertical: Padding.padding4,
    borderRadius: BorderRadius.regular,
    gap: 4,
  },
  experimentalText: {
    ...Typography.caption2,
    fontWeight: FontWeight.semibold,
    color: Colors.primaryOrange,
  },
  content: {
    flex: 1,
  },

  // Input View Styles
  inputContainer: {
    flex: 1,
    padding: Padding.padding16,
  },
  inputHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: Spacing.large,
    gap: Spacing.medium,
  },
  inputHeaderText: {
    flex: 1,
  },
  inputTitle: {
    ...Typography.title2,
    marginBottom: 4,
  },
  inputSubtitle: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  inputSection: {
    marginBottom: Spacing.large,
  },
  inputLabelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.smallMedium,
  },
  inputLabel: {
    ...Typography.headline,
  },
  inputStats: {
    alignItems: 'flex-end',
  },
  charCount: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  charCountError: {
    color: Colors.primaryRed,
  },
  questionEstimate: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  textArea: {
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.large,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    padding: Padding.padding12,
    minHeight: 200,
    ...Typography.body,
    color: Colors.textPrimary,
  },
  errorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    marginTop: Spacing.smallMedium,
  },
  errorText: {
    ...Typography.caption,
    color: Colors.primaryRed,
  },
  modelStatusCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.large,
    padding: Padding.padding12,
    marginBottom: Spacing.large,
    gap: Spacing.smallMedium,
  },
  modelStatusText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    flex: 1,
  },
  generateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryAccent,
    borderRadius: BorderRadius.large,
    paddingVertical: Padding.padding14,
    marginBottom: Spacing.large,
    gap: Spacing.smallMedium,
  },
  generateButtonDisabled: {
    backgroundColor: Colors.textSecondary,
  },
  generateButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
  tipsCard: {
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.large,
    padding: Padding.padding12,
  },
  tipsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.smallMedium,
  },
  tipsTitle: {
    ...Typography.subheadline,
    fontWeight: FontWeight.semibold,
    color: Colors.primaryAccent,
  },
  tipsList: {
    gap: Spacing.small,
  },
  bulletPoint: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: Spacing.smallMedium,
  },
  bullet: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.textSecondary,
    marginTop: 6,
  },
  bulletText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    flex: 1,
  },

  // Generating View Styles
  generatingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: Padding.padding24,
  },
  generatingTitle: {
    ...Typography.title2,
    marginTop: Spacing.xLarge,
  },
  generatingSubtitle: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginTop: Spacing.smallMedium,
    paddingHorizontal: Padding.padding24,
  },
  generatingSpinner: {
    marginTop: Spacing.xLarge,
  },

  // Overlay Styles
  overlay: {
    flex: 1,
    backgroundColor: Colors.overlayLight,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding24,
  },
  progressCard: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding24,
    width: '100%',
    maxWidth: 400,
    maxHeight: '70%',
  },
  progressTitle: {
    ...Typography.title3,
    textAlign: 'center',
    marginBottom: Spacing.large,
  },
  progressTextContainer: {
    maxHeight: 200,
    marginTop: Spacing.large,
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
  },
  progressText: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  cancelButton: {
    marginTop: Spacing.large,
    alignItems: 'center',
  },
  cancelButtonText: {
    ...Typography.body,
    color: Colors.primaryRed,
  },

  // Swipe View Styles
  swipeContainer: {
    flex: 1,
  },
  progressHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
  },
  progressHeaderText: {
    ...Typography.headline,
  },
  progressBarContainer: {
    height: 4,
    marginHorizontal: Padding.padding16,
    position: 'relative',
  },
  progressBarBg: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
  },
  progressBarFill: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    backgroundColor: Colors.primaryAccent,
    borderRadius: 2,
  },
  cardsArea: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding16,
  },
  quizCard: {
    position: 'absolute',
    width: SCREEN_WIDTH - 32,
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.xLarge,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 8,
    elevation: 5,
    overflow: 'hidden',
  },
  swipeOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 10,
  },
  swipeOverlayFalse: {
    backgroundColor: 'rgba(255, 59, 48, 0.3)',
  },
  swipeOverlayTrue: {
    backgroundColor: 'rgba(52, 199, 89, 0.3)',
  },
  swipeOverlayText: {
    ...Typography.largeTitle,
    marginTop: Spacing.smallMedium,
  },
  swipeOverlayTextFalse: {
    color: Colors.primaryRed,
  },
  swipeOverlayTextTrue: {
    color: Colors.statusGreen,
  },
  cardHeader: {
    paddingHorizontal: Padding.padding16,
    paddingTop: Padding.padding16,
  },
  cardLabel: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  cardContent: {
    padding: Padding.padding16,
    minHeight: 200,
    maxHeight: 300,
  },
  questionText: {
    ...Typography.title3,
    textAlign: 'center',
  },
  cardFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding16,
    backgroundColor: Colors.backgroundGrouped,
  },
  swipeHint: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  swipeHintTextFalse: {
    ...Typography.subheadline,
    fontWeight: FontWeight.bold,
    color: Colors.primaryRed,
  },
  swipeHintTextTrue: {
    ...Typography.subheadline,
    fontWeight: FontWeight.bold,
    color: Colors.statusGreen,
  },
  bottomControls: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: Padding.padding24,
    gap: Spacing.xxxLarge,
  },
  answerButton: {
    alignItems: 'center',
    opacity: 0.6,
  },
  answerButtonActive: {
    opacity: 1,
    transform: [{ scale: 1.1 }],
  },
  falseButton: {},
  trueButton: {},
  answerButtonLabel: {
    ...Typography.headline,
    marginTop: Spacing.smallMedium,
  },

  // Instructions Overlay
  instructionsOverlay: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding30,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.2,
    shadowRadius: 20,
    elevation: 10,
  },
  instructionsTitle: {
    ...Typography.title2,
    marginBottom: Spacing.xLarge,
  },
  instructionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.medium,
    marginBottom: Spacing.large,
  },
  instructionsText: {
    ...Typography.body,
  },
  gotItButton: {
    backgroundColor: Colors.primaryAccent,
    paddingHorizontal: Padding.padding24,
    paddingVertical: Padding.padding12,
    borderRadius: BorderRadius.large,
    marginTop: Spacing.medium,
  },
  gotItButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },

  // Results View Styles
  resultsContainer: {
    flex: 1,
    padding: Padding.padding16,
  },
  scoreCircleContainer: {
    alignItems: 'center',
    marginTop: Spacing.xxxLarge,
  },
  scoreCircle: {
    width: 200,
    height: 200,
    borderRadius: 100,
    borderWidth: 20,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.backgroundPrimary,
  },
  scoreNumber: {
    fontSize: 60,
    fontWeight: FontWeight.bold,
  },
  scoreOutOf: {
    ...Typography.headline,
    color: Colors.textSecondary,
  },
  scorePercentage: {
    ...Typography.title2,
  },
  performanceMessage: {
    ...Typography.title2,
    textAlign: 'center',
    marginTop: Spacing.xLarge,
  },
  statsCard: {
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding16,
    marginTop: Spacing.xLarge,
  },
  statRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Spacing.small,
  },
  statIcon: {
    width: 30,
  },
  statLabel: {
    ...Typography.body,
    color: Colors.textSecondary,
    flex: 1,
  },
  statValue: {
    ...Typography.body,
    fontWeight: FontWeight.semibold,
  },
  reviewSection: {
    backgroundColor: Colors.backgroundGray6,
    borderRadius: BorderRadius.xLarge,
    padding: Padding.padding16,
    marginTop: Spacing.large,
  },
  reviewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
  },
  reviewTitle: {
    ...Typography.body,
    fontWeight: FontWeight.medium,
    flex: 1,
  },
  incorrectList: {
    marginTop: Spacing.large,
    gap: Spacing.large,
  },
  incorrectCard: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.large,
    padding: Padding.padding16,
  },
  incorrectQuestion: {
    ...Typography.body,
    fontWeight: FontWeight.medium,
    marginBottom: Spacing.medium,
  },
  answerComparison: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: Spacing.medium,
  },
  answerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  answerLabel: {
    ...Typography.subheadline,
  },
  explanationLabel: {
    ...Typography.subheadline,
    fontWeight: FontWeight.semibold,
    color: Colors.textSecondary,
    marginBottom: 4,
  },
  explanationText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  resultActions: {
    marginTop: Spacing.xLarge,
    marginBottom: Spacing.xxxLarge,
    gap: Spacing.medium,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryAccent,
    borderRadius: BorderRadius.large,
    paddingVertical: Padding.padding14,
    gap: Spacing.smallMedium,
  },
  retryButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
  newQuizButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.backgroundGray5,
    borderRadius: BorderRadius.large,
    paddingVertical: Padding.padding14,
    gap: Spacing.smallMedium,
  },
  newQuizButtonText: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
});

export default QuizScreen;
