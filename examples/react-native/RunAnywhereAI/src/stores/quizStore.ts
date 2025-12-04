/**
 * Quiz Store - Zustand state management for Quiz feature
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Quiz/QuizViewModel.swift
 */

import { create } from 'zustand';
import {
  QuizQuestion,
  QuizGeneration,
  QuizAnswer,
  QuizSession,
  QuizResults,
  QuizViewState,
  SwipeDirection,
  QuizGenerationError,
  QuizGenerationErrorType,
  QUIZ_CONSTANTS,
  isQuizComplete,
  getQuizScore,
  getQuizPercentage,
  estimateQuestionCount,
} from '../types/quiz';

/**
 * Quiz store state interface
 */
interface QuizState {
  // View state
  viewState: QuizViewState;

  // Input state
  inputText: string;

  // Quiz state
  currentQuestionIndex: number;
  currentSession: QuizSession | null;
  quizResults: QuizResults | null;

  // Interaction state
  dragOffset: { x: number; y: number };
  swipeDirection: SwipeDirection;

  // Generation state
  showGenerationProgress: boolean;
  generationText: string;
  streamingTokens: string[];

  // Model state
  isModelLoaded: boolean;
  loadedModelName: string | null;

  // Error state
  error: QuizGenerationError | null;

  // Timing state
  questionStartTime: number | null;

  // Computed properties
  readonly estimatedTokenCount: number;
  readonly estimatedQuestionCount: number;
  readonly inputCharacterCount: number;
  readonly isInputValid: boolean;
  readonly canGenerateQuiz: boolean;
  readonly currentQuestion: QuizQuestion | null;
  readonly progressText: string;
  readonly progressPercentage: number;
  readonly visibleQuestions: QuizQuestion[];
}

/**
 * Quiz store actions interface
 */
interface QuizActions {
  // Input actions
  setInputText: (text: string) => void;

  // Model actions
  setModelLoaded: (loaded: boolean, modelName?: string) => void;

  // Quiz generation
  generateQuiz: () => Promise<void>;
  cancelGeneration: () => void;

  // Quiz interaction
  handleSwipe: (translation: { x: number; y: number }) => void;
  completeSwipe: () => void;
  answerCurrentQuestion: (answer: boolean) => void;

  // Navigation
  startNewQuiz: () => void;
  retryQuiz: () => void;

  // Reset
  resetQuiz: () => void;

  // Error handling
  clearError: () => void;
  setError: (error: QuizGenerationError | null) => void;
}

/**
 * Combined store type
 */
type QuizStore = QuizState & QuizActions;

/**
 * Initial state values
 */
const initialState: Omit<QuizState, 'estimatedTokenCount' | 'estimatedQuestionCount' | 'inputCharacterCount' | 'isInputValid' | 'canGenerateQuiz' | 'currentQuestion' | 'progressText' | 'progressPercentage' | 'visibleQuestions'> = {
  viewState: QuizViewState.Input,
  inputText: '',
  currentQuestionIndex: 0,
  currentSession: null,
  quizResults: null,
  dragOffset: { x: 0, y: 0 },
  swipeDirection: SwipeDirection.None,
  showGenerationProgress: false,
  generationText: '',
  streamingTokens: [],
  isModelLoaded: false,
  loadedModelName: null,
  error: null,
  questionStartTime: null,
};

/**
 * Create the quiz store
 */
export const useQuizStore = create<QuizStore>((set, get) => ({
  // Initial state
  ...initialState,

  // Computed properties (read-only getters)
  get estimatedTokenCount() {
    return Math.floor(get().inputText.length / 4);
  },

  get estimatedQuestionCount() {
    return estimateQuestionCount(get().inputText);
  },

  get inputCharacterCount() {
    return get().inputText.length;
  },

  get isInputValid() {
    const { inputText } = get();
    return (
      inputText.trim().length > 0 &&
      inputText.length <= QUIZ_CONSTANTS.MAX_INPUT_CHARACTERS
    );
  },

  get canGenerateQuiz() {
    const state = get();
    return state.isInputValid && state.isModelLoaded;
  },

  get currentQuestion() {
    const { currentSession, currentQuestionIndex } = get();
    if (!currentSession) return null;
    const questions = currentSession.generatedQuiz.questions;
    if (currentQuestionIndex >= questions.length) return null;
    return questions[currentQuestionIndex];
  },

  get progressText() {
    const { currentSession, currentQuestionIndex } = get();
    if (!currentSession) return '';
    return `${currentQuestionIndex + 1} of ${currentSession.generatedQuiz.questions.length}`;
  },

  get progressPercentage() {
    const { currentSession, currentQuestionIndex } = get();
    if (!currentSession || currentSession.generatedQuiz.questions.length === 0) {
      return 0;
    }
    return currentQuestionIndex / currentSession.generatedQuiz.questions.length;
  },

  get visibleQuestions() {
    const { currentSession, currentQuestionIndex } = get();
    if (!currentSession) return [];
    const questions = currentSession.generatedQuiz.questions;
    const startIndex = currentQuestionIndex;
    const endIndex = Math.min(startIndex + 3, questions.length);
    return questions.slice(startIndex, endIndex);
  },

  // Actions
  setInputText: (text: string) => {
    set({ inputText: text });
  },

  setModelLoaded: (loaded: boolean, modelName?: string) => {
    set({
      isModelLoaded: loaded,
      loadedModelName: modelName || null,
    });
  },

  generateQuiz: async () => {
    const state = get();

    if (!state.isInputValid) {
      return;
    }

    set({
      viewState: QuizViewState.Generating,
      showGenerationProgress: true,
      generationText: '',
      streamingTokens: [],
      error: null,
    });

    try {
      // Check if model is loaded
      if (!state.isModelLoaded) {
        throw {
          type: QuizGenerationErrorType.NoModelLoaded,
          message: 'No model is currently loaded. Please load a model from the Settings tab first.',
        } as QuizGenerationError;
      }

      /**
       * TODO: Implement actual SDK structured output generation
       * When the React Native SDK supports generateStructuredStream, use:
       *
       * const streamResult = RunAnywhere.generateStructuredStream(
       *   QuizGeneration,
       *   state.inputText,
       *   { maxTokens: 1500, temperature: 0.7, topP: 0.9 }
       * );
       *
       * for await (const token of streamResult.tokenStream) {
       *   set(s => ({
       *     generationText: s.generationText + token.text,
       *     streamingTokens: [...s.streamingTokens, token.text],
       *   }));
       * }
       *
       * const generatedQuiz = await streamResult.result;
       */

      // Mock generation for now - simulate streaming
      const mockQuiz = await generateMockQuiz(
        state.inputText,
        (token: string) => {
          set(s => ({
            generationText: s.generationText + token,
            streamingTokens: [...s.streamingTokens, token],
          }));
        }
      );

      if (mockQuiz.questions.length === 0) {
        throw {
          type: QuizGenerationErrorType.NoQuestionsGenerated,
          message: 'No questions could be generated from the provided content.',
        } as QuizGenerationError;
      }

      // Create session
      const session: QuizSession = {
        id: generateUUID(),
        generatedQuiz: mockQuiz,
        answers: [],
        startTime: new Date(),
      };

      set({
        currentSession: session,
        currentQuestionIndex: 0,
        questionStartTime: Date.now(),
        showGenerationProgress: false,
        viewState: QuizViewState.Quiz,
      });
    } catch (err) {
      const error = err as QuizGenerationError;
      console.error('Quiz generation failed:', error);

      set({
        error: error.type
          ? error
          : {
              type: QuizGenerationErrorType.SDKGenerationFailed,
              message: `Quiz generation failed: ${(err as Error).message || 'Unknown error'}`,
            },
        showGenerationProgress: false,
        viewState: QuizViewState.Input,
      });
    }
  },

  cancelGeneration: () => {
    set({
      showGenerationProgress: false,
      viewState: QuizViewState.Input,
    });
  },

  handleSwipe: (translation: { x: number; y: number }) => {
    let direction = SwipeDirection.None;
    if (translation.x > QUIZ_CONSTANTS.SWIPE_THRESHOLD) {
      direction = SwipeDirection.Right;
    } else if (translation.x < -QUIZ_CONSTANTS.SWIPE_THRESHOLD) {
      direction = SwipeDirection.Left;
    }

    set({
      dragOffset: translation,
      swipeDirection: direction,
    });
  },

  completeSwipe: () => {
    const { swipeDirection } = get();

    if (swipeDirection === SwipeDirection.None) {
      set({ dragOffset: { x: 0, y: 0 } });
      return;
    }

    const userAnswer = swipeDirection === SwipeDirection.Right;
    get().answerCurrentQuestion(userAnswer);

    set({
      dragOffset: { x: 0, y: 0 },
      swipeDirection: SwipeDirection.None,
    });
  },

  answerCurrentQuestion: (answer: boolean) => {
    const state = get();
    const { currentSession, currentQuestionIndex, questionStartTime } = state;

    if (!currentSession || !questionStartTime) return;

    const question = currentSession.generatedQuiz.questions[currentQuestionIndex];
    if (!question) return;

    const timeSpent = Date.now() - questionStartTime;
    const isCorrect = answer === question.correctAnswer;

    const quizAnswer: QuizAnswer = {
      id: generateUUID(),
      questionId: question.id,
      userAnswer: answer,
      isCorrect,
      timeSpent,
    };

    const updatedSession: QuizSession = {
      ...currentSession,
      answers: [...currentSession.answers, quizAnswer],
    };

    // Check if quiz is complete
    if (isQuizComplete(updatedSession)) {
      updatedSession.endTime = new Date();

      const totalTimeSpent = updatedSession.endTime.getTime() - updatedSession.startTime.getTime();
      const incorrectQuestions = updatedSession.answers
        .filter(a => !a.isCorrect)
        .map(a => updatedSession.generatedQuiz.questions.find(q => q.id === a.questionId))
        .filter((q): q is QuizQuestion => q !== undefined);

      const results: QuizResults = {
        session: updatedSession,
        totalTimeSpent,
        incorrectQuestions,
      };

      set({
        currentSession: updatedSession,
        quizResults: results,
        viewState: QuizViewState.Results,
      });
    } else {
      // Move to next question
      set({
        currentSession: updatedSession,
        currentQuestionIndex: currentQuestionIndex + 1,
        questionStartTime: Date.now(),
      });
    }
  },

  startNewQuiz: () => {
    set({
      ...initialState,
      isModelLoaded: get().isModelLoaded,
      loadedModelName: get().loadedModelName,
    });
  },

  retryQuiz: () => {
    const { currentSession } = get();
    if (!currentSession) return;

    // Reset session but keep the same questions
    const newSession: QuizSession = {
      id: generateUUID(),
      generatedQuiz: currentSession.generatedQuiz,
      answers: [],
      startTime: new Date(),
    };

    set({
      currentSession: newSession,
      currentQuestionIndex: 0,
      questionStartTime: Date.now(),
      quizResults: null,
      viewState: QuizViewState.Quiz,
    });
  },

  resetQuiz: () => {
    set({
      ...initialState,
      isModelLoaded: get().isModelLoaded,
      loadedModelName: get().loadedModelName,
    });
  },

  clearError: () => {
    set({ error: null });
  },

  setError: (error: QuizGenerationError | null) => {
    set({ error });
  },
}));

/**
 * Helper function to get score from store
 */
export function getStoreQuizScore(session: QuizSession | null): number {
  if (!session) return 0;
  return getQuizScore(session);
}

/**
 * Helper function to get percentage from store
 */
export function getStoreQuizPercentage(session: QuizSession | null): number {
  if (!session) return 0;
  return getQuizPercentage(session);
}

/**
 * Mock quiz generation for UI development
 * TODO: Replace with actual SDK integration when available
 */
async function generateMockQuiz(
  inputText: string,
  onToken: (token: string) => void
): Promise<QuizGeneration> {
  // Simulate streaming tokens
  const generatingMessage = 'Generating quiz questions based on your content...\n\n';
  for (const char of generatingMessage) {
    onToken(char);
    await sleep(20);
  }

  // Generate mock questions based on content length
  const questionCount = estimateQuestionCount(inputText);
  const mockQuestions: QuizQuestion[] = [];

  for (let i = 0; i < questionCount; i++) {
    const question: QuizQuestion = {
      id: `q${i + 1}`,
      question: getMockQuestion(i, inputText),
      correctAnswer: Math.random() > 0.5,
      explanation: `This is the explanation for question ${i + 1}. The answer is based on the content you provided.`,
    };
    mockQuestions.push(question);

    // Simulate token streaming for each question
    onToken(`\nQuestion ${i + 1}: ${question.question.substring(0, 30)}...`);
    await sleep(100);
  }

  onToken('\n\nQuiz generation complete!');

  return {
    questions: mockQuestions,
    topic: extractTopic(inputText),
    difficulty: 'medium',
  };
}

/**
 * Get a mock question based on index
 */
function getMockQuestion(index: number, _inputText: string): string {
  const mockQuestions = [
    'The content discusses important concepts that are fundamental to understanding this topic.',
    'According to the text, the main idea is supported by multiple examples.',
    'The information presented suggests a relationship between different elements.',
    'Based on the content, the primary purpose is to inform and educate readers.',
    'The text implies that understanding context is essential for comprehension.',
    'The material covers topics that are relevant to modern applications.',
    'According to the passage, there are multiple perspectives to consider.',
    'The content suggests that practical experience complements theoretical knowledge.',
    'Based on the information provided, this concept has broad applications.',
    'The text indicates that continued learning is important in this field.',
  ];

  return mockQuestions[index % mockQuestions.length];
}

/**
 * Extract a topic from input text
 */
function extractTopic(inputText: string): string {
  // Simple extraction - take first few words
  const words = inputText.trim().split(/\s+/).slice(0, 5);
  return words.join(' ') + '...';
}

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Generate a simple UUID v4-like string
 * Uses crypto.getRandomValues when available, falls back to Math.random
 */
function generateUUID(): string {
  // Use a simple timestamp + random approach for uniqueness
  const timestamp = Date.now().toString(36);
  const randomPart = Math.random().toString(36).substring(2, 9);
  const randomPart2 = Math.random().toString(36).substring(2, 9);
  return `${timestamp}-${randomPart}-${randomPart2}`;
}

export default useQuizStore;
