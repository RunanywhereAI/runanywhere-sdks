/// Request priority for operations.
/// Matches iOS RequestPriority enum exactly.
enum RequestPriority implements Comparable<RequestPriority> {
  low(0),
  normal(1),
  high(2),
  critical(3);

  final int rawValue;

  const RequestPriority(this.rawValue);

  @override
  int compareTo(RequestPriority other) => rawValue.compareTo(other.rawValue);

  /// Returns true if this priority is greater than [other].
  bool operator >(RequestPriority other) => rawValue > other.rawValue;

  /// Returns true if this priority is greater than or equal to [other].
  bool operator >=(RequestPriority other) => rawValue >= other.rawValue;

  /// Returns true if this priority is less than [other].
  bool operator <(RequestPriority other) => rawValue < other.rawValue;

  /// Returns true if this priority is less than or equal to [other].
  bool operator <=(RequestPriority other) => rawValue <= other.rawValue;

  /// Creates from raw value, defaults to normal if invalid.
  static RequestPriority fromRawValue(int value) {
    return RequestPriority.values.firstWhere(
      (p) => p.rawValue == value,
      orElse: () => RequestPriority.normal,
    );
  }
}
