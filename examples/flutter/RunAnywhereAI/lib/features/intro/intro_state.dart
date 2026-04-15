class IntroState {
  const IntroState({
    this.progress = 0.0,
    this.statusText = 'Starting up...',
    this.isComplete = false,
  });

  final double progress;
  final String statusText;
  final bool isComplete;

  IntroState copyWith({
    double? progress,
    String? statusText,
    bool? isComplete,
  }) {
    return IntroState(
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
