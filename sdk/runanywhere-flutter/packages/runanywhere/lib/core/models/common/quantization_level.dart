/// Quantization level for model weights
/// Matches iOS QuantizationLevel from Core/Models/Common/QuantizationLevel.swift
enum QuantizationLevel {
  full('fp32'),
  f32('f32'),
  half('fp16'),
  f16('f16'),
  int8('int8'),
  q8v0('q8_0'),
  int4('int4'),
  q4v0('q4_0'),
  q4KS('q4_K_S'),
  q4KM('q4_K_M'),
  q5v0('q5_0'),
  q5KS('q5_K_S'),
  q5KM('q5_K_M'),
  q6K('q6_K'),
  q3KS('q3_K_S'),
  q3KM('q3_K_M'),
  q3KL('q3_K_L'),
  q2K('q2_K'),
  int2('int2'),
  mixed('mixed');

  final String rawValue;

  const QuantizationLevel(this.rawValue);

  /// Create from raw string value
  static QuantizationLevel? fromRawValue(String value) {
    return QuantizationLevel.values.cast<QuantizationLevel?>().firstWhere(
          (q) => q?.rawValue == value,
          orElse: () => null,
        );
  }
}
