/// Supported NPU chipsets for on-device Genie model inference.
///
/// Each chip has an [identifier] used in model IDs and an [npuSuffix] used
/// to construct download URLs from the HuggingFace model repository.
///
/// Example:
/// ```dart
/// final chip = RunAnywhere.getChip();
/// if (chip != null) {
///   final url = chip.downloadUrl('qwen3-4b');
///   // → https://huggingface.co/runanywhere/genie-npu-models/resolve/main/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz
/// }
/// ```
enum NPUChip {
  snapdragon8Elite('8elite', 'Snapdragon 8 Elite', 'SM8750', '8elite'),
  snapdragon8EliteGen5('8elite-gen5', 'Snapdragon 8 Elite Gen 5', 'SM8850', '8elite-gen5');

  final String identifier;
  final String displayName;
  final String socModel;
  final String npuSuffix;

  const NPUChip(this.identifier, this.displayName, this.socModel, this.npuSuffix);

  /// Base URL for NPU model downloads on HuggingFace.
  static const baseUrl =
      'https://huggingface.co/runanywhere/genie-npu-models/resolve/main/';

  /// Build a HuggingFace download URL for this chip.
  /// [modelSlug] is the model slug (e.g. "qwen3-4b") → produces
  ///   "qwen3-4b-genie-w4a16-8elite-gen5.tar.gz"
  String downloadUrl(String modelSlug) =>
      '$baseUrl$modelSlug-genie-w4a16-$npuSuffix.tar.gz';

  /// Match an NPU chip from a SoC model string (e.g. "SM8750").
  /// Returns null if the SoC is not a supported NPU chipset.
  static NPUChip? fromSocModel(String socModel) {
    final upper = socModel.toUpperCase();
    for (final chip in NPUChip.values) {
      if (upper.contains(chip.socModel)) return chip;
    }
    return null;
  }
}
