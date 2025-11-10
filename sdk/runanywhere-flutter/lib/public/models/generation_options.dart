/// Generation Options
/// Similar to Swift SDK's RunAnywhereGenerationOptions
class RunAnywhereGenerationOptions {
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final bool? collectMetrics;

  RunAnywhereGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.7,
    this.topP,
    this.topK,
    this.frequencyPenalty,
    this.presencePenalty,
    this.collectMetrics = false,
  });
}

