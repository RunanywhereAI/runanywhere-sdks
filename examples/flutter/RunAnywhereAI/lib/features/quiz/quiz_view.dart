import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

/// Quiz View - Generate quizzes using structured output
class QuizView extends StatefulWidget {
  const QuizView({super.key});

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  final TextEditingController _topicController = TextEditingController();
  List<QuizQuestion> _questions = [];
  bool _isGenerating = false;
  String? _error;

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _generateQuiz() async {
    if (_topicController.text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
      _questions = [];
    });

    try {
      // Generate quiz using structured output
      final prompt = '''
Generate a quiz about ${_topicController.text} with 5 multiple choice questions.
Each question should have 4 options and one correct answer.
''';

      // For now, we'll use a simple approach
      // In production, you'd use generateStructuredOutput with a Quiz class
      final result = await RunAnywhere.generate(
        prompt,
        options: RunAnywhereGenerationOptions(
          maxTokens: 1000,
          temperature: 0.7,
        ),
      );

      // Parse the result (simplified - in production use proper structured output)
      final questions = _parseQuizFromText(result.text);
      setState(() {
        _questions = questions;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  List<QuizQuestion> _parseQuizFromText(String text) {
    // Simplified parsing - in production, use structured output
    final questions = <QuizQuestion>[];
    final lines = text.split('\n');

    String? currentQuestion;
    List<String> currentOptions = [];
    int? correctAnswer;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      if (line.trim().startsWith(RegExp(r'^\d+\.'))) {
        // New question
        if (currentQuestion != null && currentOptions.length >= 2) {
          questions.add(QuizQuestion(
            question: currentQuestion,
            options: currentOptions,
            correctAnswer: correctAnswer ?? 0,
          ));
        }
        currentQuestion = line.trim().substring(line.trim().indexOf('.') + 1).trim();
        currentOptions = [];
        correctAnswer = null;
      } else if (line.trim().startsWith(RegExp(r'^[a-dA-D][\.\)]'))) {
        // Option
        final option = line.trim().substring(2).trim();
        currentOptions.add(option);
        if (line.toLowerCase().contains('correct') || line.toLowerCase().contains('answer')) {
          correctAnswer = currentOptions.length - 1;
        }
      }
    }

    // Add last question
    if (currentQuestion != null && currentOptions.length >= 2) {
      questions.add(QuizQuestion(
        question: currentQuestion,
        options: currentOptions,
        correctAnswer: correctAnswer ?? 0,
      ));
    }

    return questions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Generator'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.padding16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicController,
                    decoration: const InputDecoration(
                      hintText: 'Enter quiz topic...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.padding8),
                ElevatedButton(
                  onPressed: _isGenerating ? null : _generateQuiz,
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Generate'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.padding16),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.padding16),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                ),
                child: Text(
                  'Error: $_error',
                  style: AppTypography.body(context).copyWith(color: AppColors.primaryRed),
                ),
              ),
            ),
          Expanded(
            child: _questions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.quiz,
                          size: AppSpacing.iconXXLarge,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(height: AppSpacing.large),
                        Text(
                          'Generate a Quiz',
                          style: AppTypography.title2(context),
                        ),
                        const SizedBox(height: AppSpacing.padding8),
                        Text(
                          'Enter a topic and generate a quiz',
                          style: AppTypography.body(context).copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.padding16),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      return _QuizQuestionCard(
                        question: _questions[index],
                        questionNumber: index + 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctAnswer;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
  });
}

class _QuizQuestionCard extends StatefulWidget {
  final QuizQuestion question;
  final int questionNumber;

  const _QuizQuestionCard({
    required this.question,
    required this.questionNumber,
  });

  @override
  State<_QuizQuestionCard> createState() => _QuizQuestionCardState();
}

class _QuizQuestionCardState extends State<_QuizQuestionCard> {
  int? _selectedAnswer;
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.padding16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.padding16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${widget.questionNumber}',
              style: AppTypography.headlineSemibold(context),
            ),
            const SizedBox(height: AppSpacing.padding8),
            Text(
              widget.question.question,
              style: AppTypography.body(context),
            ),
            const SizedBox(height: AppSpacing.padding16),
            ...widget.question.options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final isCorrect = index == widget.question.correctAnswer;
              final isSelected = _selectedAnswer == index;

              Color? backgroundColor;
              if (_showAnswer && isCorrect) {
                backgroundColor = AppColors.primaryGreen.withValues(alpha: 0.2);
              } else if (isSelected && !isCorrect && _showAnswer) {
                backgroundColor = AppColors.primaryRed.withValues(alpha: 0.2);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.padding8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedAnswer = index;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.padding12),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.separator(context),
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${String.fromCharCode(65 + index)}.',
                          style: AppTypography.body(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.padding8),
                        Expanded(
                          child: Text(
                            option,
                            style: AppTypography.body(context),
                          ),
                        ),
                        if (_showAnswer && isCorrect)
                          const Icon(Icons.check_circle, color: AppColors.primaryGreen),
                        if (_showAnswer && isSelected && !isCorrect)
                          const Icon(Icons.cancel, color: AppColors.primaryRed),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.padding16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _showAnswer = true;
                });
              },
              child: const Text('Show Answer'),
            ),
          ],
        ),
      ),
    );
  }
}
