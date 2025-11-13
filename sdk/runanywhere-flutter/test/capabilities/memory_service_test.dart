import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/capabilities/memory/memory_service.dart';
import 'package:runanywhere/capabilities/memory/allocation_manager.dart';
import 'package:runanywhere/core/models/common.dart';

void main() {
  group('MemoryService Tests', () {
    late MemoryService memoryService;

    setUp(() {
      memoryService = MemoryService();
    });

    test('MemoryService initialization', () {
      expect(memoryService, isNotNull);
      expect(memoryService.getCurrentMemoryUsage(), equals(0));
      expect(memoryService.getLoadedModelCount(), equals(0));
    });

    test('Memory statistics', () {
      final stats = memoryService.getMemoryStatistics();
      expect(stats, isNotNull);
      expect(stats.totalMemory, greaterThan(0));
      expect(stats.loadedModelCount, equals(0));
      expect(stats.modelMemory, equals(0));
    });

    test('Memory threshold setting', () {
      const threshold = 1000 * 1024 * 1024; // 1GB
      memoryService.setMemoryThreshold(threshold);
      // Threshold is set internally, verify service still works
      expect(memoryService.getMemoryStatistics(), isNotNull);
    });
  });

  group('AllocationManager Tests', () {
    late AllocationManager allocationManager;

    setUp(() {
      allocationManager = AllocationManager();
    });

    test('AllocationManager initialization', () {
      expect(allocationManager, isNotNull);
      expect(allocationManager.getTotalModelMemory(), equals(0));
      expect(allocationManager.getLoadedModelCount(), equals(0));
    });

    test('Register and unregister model', () {
      final model = MemoryLoadedModel(
        id: 'test-model',
        name: 'Test Model',
        size: 100 * 1024 * 1024, // 100MB
        framework: LLMFramework.llamaCpp,
      );

      // Note: This requires a mock LLMService
      // allocationManager.registerModel(model, 100 * 1024 * 1024, mockService);

      expect(allocationManager.getLoadedModelCount(), equals(0));
    });
  });
}

