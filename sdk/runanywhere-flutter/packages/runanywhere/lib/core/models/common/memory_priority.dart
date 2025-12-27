/// Memory priority levels
/// Matches iOS MemoryPriority from Core/Protocols/Memory/MemoryManager.swift
enum MemoryPriority implements Comparable<MemoryPriority> {
  low(0),
  normal(1),
  high(2),
  critical(3);

  final int value;

  const MemoryPriority(this.value);

  @override
  int compareTo(MemoryPriority other) => value.compareTo(other.value);

  bool operator <(MemoryPriority other) => value < other.value;
  bool operator <=(MemoryPriority other) => value <= other.value;
  bool operator >(MemoryPriority other) => value > other.value;
  bool operator >=(MemoryPriority other) => value >= other.value;
}
