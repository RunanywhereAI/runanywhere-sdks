/// Supported NPU chipsets for on-device Genie model inference.
///
/// Each chip has an [identifier] used to construct dynamic download URLs
/// for chipset-specific NPU model binaries.
///
/// Example:
/// ```dart
/// final chip = RunAnywhere.getChip();
/// if (chip != null) {
///   final url = chip.downloadUrl('qwen');
///   // → https://huggingface.co/Void2377/npu-models/resolve/main/qwen-gen1.zip?download=true
/// }
/// ```
enum NPUChip {
  snapdragon8Elite('gen1', 'Snapdragon 8 Elite', 'SM8750'),
  snapdragon8EliteGen5('gen2', 'Snapdragon 8 Elite Gen 5', 'SM8850');

  final String identifier;
  final String displayName;
  final String socModel;

  const NPUChip(this.identifier, this.displayName, this.socModel);

  /// Base URL for NPU model downloads on HuggingFace.
  static const baseUrl =
      'https://huggingface.co/Void2377/npu-models/resolve/main/';

  /// Build a HuggingFace download URL for this chip.
  /// [modelName] is the model prefix (e.g. "qwen") → produces "qwen-gen1.zip"
  String downloadUrl(String modelName) =>
      '$baseUrl$modelName-$identifier.zip?download=true';

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
