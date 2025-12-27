# Phase 4: Testing & Validation

**Duration**: 2 weeks
**Objective**: End-to-end testing, binary size validation, performance benchmarking, and documentation.

---

## ⚠️ Key Testing Considerations

### 1. Dual Registry Validation
Since we have two parallel registries (Swift `ServiceRegistry` + C++ commons registry), tests must validate both paths work correctly.

### 2. Error Code Mapping
Tests must verify that C++ commons error codes (`RAC_*`) are correctly mapped to Swift `SDKError` types.

### 3. Platform Adapter Verification
Validate that Swift platform adapter callbacks are correctly invoked from C++ commons layer.

### 4. Binary Size Tracking
Automated size tracking to catch regressions and validate the modular architecture delivers size savings.

---

## Tasks Overview

| Task ID | Description | Effort | Dependencies |
|---------|-------------|--------|--------------|
| 4.1 | Unit tests for commons C++ layer | 2 days | Phase 2 |
| 4.2 | E2E Testing - All backend combinations | 3 days | Phase 3 |
| 4.3 | Platform adapter integration tests | 2 days | 4.2 |
| 4.4 | Binary size optimization & tracking | 2 days | 4.1 |
| 4.5 | Performance benchmarking | 2 days | 4.2 |
| 4.6 | Documentation & migration guide | 2 days | All above |
| 4.7 | CI/CD updates for release | 1 day | All above |

---

## Task 4.1: C++ Commons Unit Tests

### Test File Structure

```
runanywhere-commons/
├── tests/
│   ├── CMakeLists.txt
│   ├── test_module_registry.cpp
│   ├── test_service_registry.cpp
│   ├── test_event_publisher.cpp
│   ├── test_error_codes.cpp
│   └── test_platform_adapter.cpp
```

### Module Registry Tests

```cpp
// tests/test_module_registry.cpp

#include <gtest/gtest.h>
#include "rac_core.h"
#include "rac_types.h"

class ModuleRegistryTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Initialize with mock platform adapter
        rac_platform_adapter_t adapter = {};
        adapter.now_ms = [](void*) -> uint64_t { return 1234567890; };
        rac_set_platform_adapter(&adapter);

        rac_config_t config = {};
        rac_config_init(&config);
        config.environment = RAC_ENV_DEVELOPMENT;
        rac_init(&config);
    }

    void TearDown() override {
        rac_shutdown();
    }
};

TEST_F(ModuleRegistryTest, RegisterModule) {
    rac_module_info_t info = {
        .id = "test_module",
        .name = "Test Module",
        .version = "1.0.0",
        .priority = 100,
        .capabilities = RAC_CAPABILITY_LLM
    };

    rac_result_t result = rac_module_register(&info);
    ASSERT_EQ(result, RAC_SUCCESS);

    // Verify registration
    bool registered = false;
    result = rac_module_is_registered("test_module", &registered);
    ASSERT_EQ(result, RAC_SUCCESS);
    ASSERT_TRUE(registered);
}

TEST_F(ModuleRegistryTest, RegisterDuplicateFails) {
    rac_module_info_t info = {
        .id = "dup_module",
        .name = "Dup Module",
        .version = "1.0.0"
    };

    ASSERT_EQ(rac_module_register(&info), RAC_SUCCESS);
    ASSERT_EQ(rac_module_register(&info), RAC_ERROR_MODULE_ALREADY_REGISTERED);
}

TEST_F(ModuleRegistryTest, UnregisterModule) {
    rac_module_info_t info = { .id = "remove_me" };
    rac_module_register(&info);

    rac_result_t result = rac_module_unregister("remove_me");
    ASSERT_EQ(result, RAC_SUCCESS);

    bool registered = true;
    rac_module_is_registered("remove_me", &registered);
    ASSERT_FALSE(registered);
}

TEST_F(ModuleRegistryTest, GetModulesForCapability) {
    // Register LLM module
    rac_module_info_t llm_info = {
        .id = "llm_backend",
        .capabilities = RAC_CAPABILITY_LLM
    };
    rac_module_register(&llm_info);

    // Register STT module
    rac_module_info_t stt_info = {
        .id = "stt_backend",
        .capabilities = RAC_CAPABILITY_STT
    };
    rac_module_register(&stt_info);

    // Query for LLM
    rac_module_info_t* modules = nullptr;
    size_t count = 0;
    rac_result_t result = rac_module_get_by_capability(RAC_CAPABILITY_LLM, &modules, &count);

    ASSERT_EQ(result, RAC_SUCCESS);
    ASSERT_EQ(count, 1);
    ASSERT_STREQ(modules[0].id, "llm_backend");

    rac_module_info_free(modules, count);
}
```

### Error Code Tests

```cpp
// tests/test_error_codes.cpp

#include <gtest/gtest.h>
#include "rac_error.h"

TEST(ErrorCodes, AllCodesHaveMessages) {
    // Verify all error codes have descriptive messages
    const rac_result_t codes[] = {
        RAC_SUCCESS,
        RAC_ERROR_NULL_POINTER,
        RAC_ERROR_NOT_INITIALIZED,
        RAC_ERROR_ALREADY_INITIALIZED,
        RAC_ERROR_INVALID_ARGUMENT,
        RAC_ERROR_BACKEND_NOT_FOUND,
        RAC_ERROR_MODEL_NOT_LOADED,
        RAC_ERROR_MODEL_LOAD_FAILED,
        RAC_ERROR_COMPONENT_FAILED,
        RAC_ERROR_OUT_OF_MEMORY,
        RAC_ERROR_CANCELLED,
        RAC_ERROR_FILE_READ_FAILED,
        RAC_ERROR_FILE_WRITE_FAILED,
        RAC_ERROR_FILE_NOT_FOUND,
        RAC_ERROR_MODULE_ALREADY_REGISTERED,
        RAC_ERROR_NOT_SUPPORTED,
        RAC_ERROR_BUFFER_TOO_SMALL,
    };

    for (auto code : codes) {
        const char* msg = rac_error_message(code);
        ASSERT_NE(msg, nullptr);
        ASSERT_GT(strlen(msg), 0);
        // Ensure not just "Unknown error"
        if (code != RAC_ERROR_UNKNOWN) {
            ASSERT_STRNE(msg, "Unknown error");
        }
    }
}

TEST(ErrorCodes, ErrorDetailsCanBeSet) {
    rac_set_last_error_details("Test error detail");
    const char* details = rac_get_last_error_details();
    ASSERT_STREQ(details, "Test error detail");
}

TEST(ErrorCodes, CommonsCodesDoNotOverlapWithCore) {
    // Commons codes are -100 to -999
    // Core codes are 0 (success) and -1 to -99
    ASSERT_LT(RAC_ERROR_NULL_POINTER, -100);
    ASSERT_GT(RAC_ERROR_NULL_POINTER, -1000);
}
```

---

## Task 4.2: E2E Backend Combination Testing

### Test Matrix

| Test Scenario | RACommons | LlamaCPP | ONNX | Expected |
|---------------|-----------|----------|------|----------|
| Commons only | ✓ | ✗ | ✗ | Init works, no backends |
| LLM only | ✓ | ✓ | ✗ | LLM works, STT/TTS fail gracefully |
| STT/TTS only | ✓ | ✗ | ✓ | STT/TTS work, LLM fails gracefully |
| Full suite | ✓ | ✓ | ✓ | All capabilities work |

### Swift Integration Tests

```swift
// Tests/IntegrationTests/BackendCombinationTests.swift

import XCTest
@testable import RunAnywhere
import CRACommons

final class BackendCombinationTests: XCTestCase {

    override func tearDown() async throws {
        // Reset both Swift AND C++ registries
        await MainActor.run {
            RunAnywhere.reset()
        }
    }

    // MARK: - Commons Only

    func testCommonsOnlyInitialization() async throws {
        // Given: No backends registered

        // When
        try RunAnywhere.initialize(environment: .development)

        // Then
        XCTAssertTrue(RunAnywhere.isSDKInitialized)

        // Verify C++ layer is initialized
        XCTAssertTrue(rac_is_initialized())

        await MainActor.run {
            XCTAssertTrue(ModuleRegistry.shared.modules.isEmpty)
        }
    }

    func testCommonsOnlyLLMFailsGracefully() async throws {
        // Given: No backends
        try RunAnywhere.initialize(environment: .development)

        // When/Then
        do {
            _ = try await RunAnywhere.generate("Hello")
            XCTFail("Should throw")
        } catch let error as SDKError {
            // Verify we get a proper capability error, not a crash
            XCTAssertTrue(error.localizedDescription.contains("No LLM service available"))
        }
    }

    // MARK: - Dual Registry Validation

    func testDualRegistration() async throws {
        // Given
        await MainActor.run {
            // This should register with BOTH Swift and C++ registries
            LlamaCPP.register()
        }

        // Verify Swift registry
        await MainActor.run {
            let swiftModules = ModuleRegistry.shared.modules
            XCTAssertEqual(swiftModules.count, 1)
            XCTAssertEqual(swiftModules.first?.moduleId, "llamacpp")
        }

        // Verify C++ registry
        var registered = false
        let result = rac_module_is_registered("llamacpp", &registered)
        XCTAssertEqual(result, RAC_SUCCESS)
        XCTAssertTrue(registered)
    }

    // MARK: - LlamaCPP Only

    func testLlamaCPPOnlyInitialization() async throws {
        // Given
        await MainActor.run {
            LlamaCPP.register()
        }

        // When
        try RunAnywhere.initialize(environment: .development)

        // Then
        XCTAssertTrue(RunAnywhere.isSDKInitialized)
        await MainActor.run {
            XCTAssertEqual(ModuleRegistry.shared.modules.count, 1)
            XCTAssertTrue(ModuleRegistry.shared.modules.first?.capabilities.contains(.llm) ?? false)
        }
    }

    func testLlamaCPPGeneration() async throws {
        // Given
        await MainActor.run { LlamaCPP.register() }
        try RunAnywhere.initialize(environment: .development)

        // Load test model (requires actual model file)
        guard let modelPath = Bundle.module.path(forResource: "test-tiny", ofType: "gguf") else {
            throw XCTSkip("Test model not available")
        }

        try await RunAnywhere.loadModel(modelPath)

        // When
        let result = try await RunAnywhere.generate(
            "Say hello",
            options: LLMGenerationOptions(maxTokens: 10)
        )

        // Then
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.completionTokens, 0)
    }

    func testLlamaCPPStreaming() async throws {
        // Given
        await MainActor.run { LlamaCPP.register() }
        try RunAnywhere.initialize(environment: .development)

        guard let modelPath = Bundle.module.path(forResource: "test-tiny", ofType: "gguf") else {
            throw XCTSkip("Test model not available")
        }
        try await RunAnywhere.loadModel(modelPath)

        // When
        var tokens: [String] = []
        let stream = try await RunAnywhere.generateStream("Hello")

        for try await token in stream.stream {
            tokens.append(token)
            if tokens.count >= 5 { break }
        }

        // Then
        XCTAssertGreaterThan(tokens.count, 0)
    }

    // MARK: - ONNX Only

    func testONNXOnlySTT() async throws {
        // Given
        await MainActor.run { ONNX.register() }
        try RunAnywhere.initialize(environment: .development)

        // When: Try to create STT service
        let sttService = try await ServiceRegistry.shared.createSTT(config: STTConfiguration())

        // Then
        XCTAssertNotNil(sttService)
    }

    func testONNXOnlyLLMFails() async throws {
        // Given: Only ONNX (no LLM capability)
        await MainActor.run { ONNX.register() }
        try RunAnywhere.initialize(environment: .development)

        // When/Then
        do {
            _ = try await RunAnywhere.generate("Hello")
            XCTFail("Should throw - ONNX doesn't provide LLM")
        } catch let error as SDKError {
            XCTAssertTrue(error.localizedDescription.contains("No LLM service"))
        }
    }

    // MARK: - Full Suite

    func testFullSuiteAllCapabilities() async throws {
        // Given: All backends
        await MainActor.run {
            LlamaCPP.register()
            ONNX.register()
        }
        try RunAnywhere.initialize(environment: .development)

        // When: Query capabilities
        await MainActor.run {
            let capabilities = ModuleRegistry.shared.allCapabilities
            XCTAssertTrue(capabilities.contains(.llm))
            XCTAssertTrue(capabilities.contains(.stt))
            XCTAssertTrue(capabilities.contains(.tts))
            XCTAssertTrue(capabilities.contains(.vad))
        }
    }
}
```

---

## Task 4.3: Platform Adapter Integration Tests

```swift
// Tests/IntegrationTests/PlatformAdapterTests.swift

import XCTest
@testable import RunAnywhere
import CRACommons

final class PlatformAdapterTests: XCTestCase {

    override func setUp() async throws {
        try RunAnywhere.initialize(environment: .development)
    }

    override func tearDown() async throws {
        await MainActor.run { RunAnywhere.reset() }
    }

    // MARK: - File System

    func testFileWriteReadDelete() async throws {
        let testPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).txt").path
        let testContent = "Hello from C++ through Swift adapter!"

        // Write via C++ commons
        var result = testContent.withCString { contentPtr in
            rac_test_file_write(testPath, contentPtr)
        }
        XCTAssertEqual(result, RAC_SUCCESS)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: testPath))

        // Read via C++ commons
        var content: UnsafePointer<CChar>?
        var length: Int = 0
        result = rac_test_file_read(testPath, &content, &length)
        XCTAssertEqual(result, RAC_SUCCESS)

        if let content = content {
            let readContent = String(cString: content)
            XCTAssertEqual(readContent, testContent)
        }

        // Delete via C++ commons
        result = rac_test_file_delete(testPath)
        XCTAssertEqual(result, RAC_SUCCESS)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPath))
    }

    // MARK: - HTTP (Should Fail)

    func testHTTPReturnsNotSupported() {
        // HTTP operations should return RAC_ERROR_NOT_SUPPORTED
        // because we handle HTTP in Swift SDK directly

        var req = rac_http_request_t()
        var resp = rac_http_response_t()

        let result = rac_test_http_request(&req, &resp)
        XCTAssertEqual(result, RAC_ERROR_NOT_SUPPORTED)

        // Verify error details are set
        let details = String(cString: rac_get_last_error_details())
        XCTAssertTrue(details.contains("HTTP"))
    }

    // MARK: - Logging

    func testLoggingFromCPP() async throws {
        // Capture log output
        var capturedLogs: [String] = []

        // Set up log capture (implementation depends on SDKLogger)
        let logExpectation = expectation(description: "Log received")

        // Trigger a log from C++ layer
        rac_test_log(RAC_LOG_INFO, "TestTag", "Test message from C++")

        // Verify it was logged (check SDKLogger output)
        // This is typically done by checking console output or a log capture mechanism
        logExpectation.fulfill()

        await fulfillment(of: [logExpectation], timeout: 1)
    }

    // MARK: - Clock

    func testClockTimestamp() {
        let before = UInt64(Date().timeIntervalSince1970 * 1000)
        let commonsTime = rac_test_get_time_ms()
        let after = UInt64(Date().timeIntervalSince1970 * 1000)

        // C++ layer's time should be within our range
        XCTAssertGreaterThanOrEqual(commonsTime, before)
        XCTAssertLessThanOrEqual(commonsTime, after)
    }

    // MARK: - Memory Info

    func testMemoryInfo() {
        var memInfo = rac_memory_info_t()
        let result = rac_test_get_memory_info(&memInfo)

        XCTAssertEqual(result, RAC_SUCCESS)
        XCTAssertGreaterThan(memInfo.total_bytes, 0)
        XCTAssertGreaterThan(memInfo.used_bytes, 0)
    }
}
```

---

## Task 4.4: Binary Size Optimization & Tracking

### Size Analysis Script

```bash
#!/bin/bash
# scripts/analyze-binary-size.sh

set -e

DIST_DIR="${1:-dist}"
OUTPUT_FILE="${2:-size-report.json}"

echo "=== XCFramework Size Analysis ==="
echo ""

# JSON output
echo "{" > "$OUTPUT_FILE"
echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",' >> "$OUTPUT_FILE"
echo '  "commit": "'$(git rev-parse HEAD 2>/dev/null || echo "unknown")'",' >> "$OUTPUT_FILE"
echo '  "frameworks": {' >> "$OUTPUT_FILE"

first=true
for xcframework in "$DIST_DIR"/*.xcframework; do
    [ -e "$xcframework" ] || continue

    name=$(basename "$xcframework" .xcframework)

    # Get total size in bytes
    total_bytes=$(du -sk "$xcframework" | cut -f1)
    total_mb=$(echo "scale=2; $total_bytes / 1024" | bc)

    echo "📦 $name: ${total_mb}MB"

    if [ "$first" = false ]; then
        echo "," >> "$OUTPUT_FILE"
    fi
    first=false

    echo -n '    "'$name'": { "size_mb": '$total_mb >> "$OUTPUT_FILE"

    # Per-architecture breakdown
    echo ', "architectures": {' >> "$OUTPUT_FILE"
    arch_first=true
    for arch_dir in "$xcframework"/*/; do
        [ -d "$arch_dir" ] || continue
        arch=$(basename "$arch_dir")
        arch_bytes=$(du -sk "$arch_dir" | cut -f1)
        arch_mb=$(echo "scale=2; $arch_bytes / 1024" | bc)

        echo "   └── $arch: ${arch_mb}MB"

        if [ "$arch_first" = false ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        arch_first=false
        echo -n '      "'$arch'": '$arch_mb >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
    echo '    } }' >> "$OUTPUT_FILE"
    echo ""
done

echo "  }" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

echo ""
echo "Report saved to: $OUTPUT_FILE"
```

### Size Targets & CI Validation

```yaml
# .github/workflows/size-check.yml

name: Binary Size Check

on:
  pull_request:
    paths:
      - 'runanywhere-commons/**'
      - 'runanywhere-core/**'

jobs:
  size-check:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build XCFrameworks
        run: |
          cd runanywhere-commons
          ./build-xcframeworks.sh release

      - name: Analyze Size
        run: |
          ./scripts/analyze-binary-size.sh dist size-report.json

      - name: Check Size Limits
        run: |
          # Size limits in MB
          MAX_COMMONS=2
          MAX_LLAMACPP=25
          MAX_ONNX=70

          commons_size=$(jq '.frameworks.RACommons.size_mb' size-report.json)
          llamacpp_size=$(jq '.frameworks.RABackendLlamaCPP.size_mb' size-report.json)
          onnx_size=$(jq '.frameworks.RABackendONNX.size_mb' size-report.json)

          echo "RACommons: ${commons_size}MB (limit: ${MAX_COMMONS}MB)"
          echo "RABackendLlamaCPP: ${llamacpp_size}MB (limit: ${MAX_LLAMACPP}MB)"
          echo "RABackendONNX: ${onnx_size}MB (limit: ${MAX_ONNX}MB)"

          # Check limits
          if (( $(echo "$commons_size > $MAX_COMMONS" | bc -l) )); then
            echo "❌ RACommons exceeds size limit!"
            exit 1
          fi

          if (( $(echo "$llamacpp_size > $MAX_LLAMACPP" | bc -l) )); then
            echo "❌ RABackendLlamaCPP exceeds size limit!"
            exit 1
          fi

          if (( $(echo "$onnx_size > $MAX_ONNX" | bc -l) )); then
            echo "❌ RABackendONNX exceeds size limit!"
            exit 1
          fi

          echo "✅ All frameworks within size limits"

      - name: Upload Size Report
        uses: actions/upload-artifact@v4
        with:
          name: size-report
          path: size-report.json
```

### Size Targets

| Framework | Target Size | Max Allowed | Notes |
|-----------|-------------|-------------|-------|
| RACommons.xcframework | < 1.5 MB | 2 MB | Core only, no backends |
| RABackendLlamaCPP.xcframework | < 20 MB | 25 MB | Includes llama.cpp |
| RABackendONNX.xcframework | < 60 MB | 70 MB | Includes ONNX Runtime |

### Optimization Checklist

- [ ] Strip debug symbols: `-s` linker flag for release
- [ ] Size optimization: `-Oz` for all release builds
- [ ] Dead code elimination: `-ffunction-sections -fdata-sections`
- [ ] Linker garbage collection: `-Wl,-dead_strip` (macOS) / `--gc-sections` (Linux)
- [ ] Symbol visibility: Export only public API via export list
- [ ] No `-all_load`: Use `-ObjC` only where needed
- [ ] Verify no duplicate symbols across frameworks
- [ ] LZMA compression for XCFramework ZIPs

---

## Task 4.5: Performance Benchmarking

```swift
// Benchmarks/PerformanceBenchmarks.swift

import XCTest
@testable import RunAnywhere
import CRACommons

final class PerformanceBenchmarks: XCTestCase {

    // MARK: - Initialization Performance

    func testSDKInitializationTime() {
        measure(metrics: [XCTClockMetric()]) {
            let exp = expectation(description: "Init")
            Task { @MainActor in
                RunAnywhere.reset()
                LlamaCPP.register()
                try? RunAnywhere.initialize(environment: .development)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testCommonsInitializationTime() {
        measure(metrics: [XCTClockMetric()]) {
            rac_shutdown()

            var adapter = rac_platform_adapter_t()
            adapter.now_ms = { _ in UInt64(Date().timeIntervalSince1970 * 1000) }
            rac_set_platform_adapter(&adapter)

            var config = rac_config_t()
            rac_config_init(&config)
            config.environment = RAC_ENV_DEVELOPMENT
            _ = rac_init(&config)
        }
    }

    // MARK: - Model Loading

    func testModelLoadTime() {
        guard let modelPath = ProcessInfo.processInfo.environment["TEST_MODEL_PATH"] else {
            return // Skip if no test model
        }

        measure(metrics: [XCTClockMetric()]) {
            let exp = expectation(description: "Load")
            Task {
                try? await RunAnywhere.loadModel(modelPath)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 120)
        }
    }

    // MARK: - Generation Performance

    func testTimeToFirstToken() {
        guard ProcessInfo.processInfo.environment["TEST_MODEL_PATH"] != nil else { return }

        measure(metrics: [XCTClockMetric()]) {
            let exp = expectation(description: "TTFT")
            Task {
                if let stream = try? await RunAnywhere.generateStream("Hello") {
                    for try await _ in stream.stream {
                        exp.fulfill()
                        break
                    }
                }
            }
            wait(for: [exp], timeout: 30)
        }
    }

    func testTokensPerSecond() {
        guard ProcessInfo.processInfo.environment["TEST_MODEL_PATH"] != nil else { return }

        var tokensGenerated = 0
        var duration: TimeInterval = 0

        let exp = expectation(description: "TPS")
        Task {
            let start = Date()
            let result = try? await RunAnywhere.generate(
                "Write a story about a brave knight.",
                options: LLMGenerationOptions(maxTokens: 100)
            )
            duration = Date().timeIntervalSince(start)
            tokensGenerated = result?.completionTokens ?? 0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 60)

        let tps = Double(tokensGenerated) / duration
        print("📊 Tokens/second: \(String(format: "%.1f", tps))")

        // Baseline: 20 t/s on M1
        XCTAssertGreaterThan(tps, 10, "Token generation too slow")
    }

    // MARK: - Memory

    func testMemoryOverhead() {
        let memoryBefore = getMemoryUsage()

        let exp = expectation(description: "Memory")
        Task { @MainActor in
            RunAnywhere.reset()
            LlamaCPP.register()
            ONNX.register()
            try? RunAnywhere.initialize(environment: .development)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)

        let memoryAfter = getMemoryUsage()
        let overhead = Double(memoryAfter - memoryBefore) / 1024.0 / 1024.0

        print("📊 SDK memory overhead: \(String(format: "%.1f", overhead)) MB")
        XCTAssertLessThan(overhead, 50, "SDK memory overhead too high")
    }

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
```

### Performance Targets

| Metric | Target | Minimum | Notes |
|--------|--------|---------|-------|
| SDK Init Time | < 50ms | < 100ms | Cold start |
| Commons Init | < 10ms | < 20ms | C++ layer only |
| Model Load (1GB) | < 3s | < 5s | From SSD |
| TTFT | < 300ms | < 500ms | First token |
| Tokens/sec | > 25 | > 15 | Apple Silicon |
| Memory overhead | < 30MB | < 50MB | SDK only |

---

## Task 4.6: Documentation & Migration Guide

### Documentation Checklist

- [ ] Update main `README.md` with new package structure
- [ ] Update `ARCHITECTURE.md` with commons layer diagram
- [ ] Create `MIGRATION.md` for v1.x → v2.0
- [ ] Update inline documentation for all new APIs
- [ ] Add code examples for each backend combination
- [ ] Update `Package.swift` comments

### Migration Guide

See separate file: `MIGRATION_GUIDE.md`

Key migration steps:
1. Update `Package.swift` dependencies (add specific backends)
2. Add `import` statements for backends
3. Add explicit `register()` calls before `initialize()`
4. Update any direct C API calls to new `rac_*` signatures

---

## Task 4.7: CI/CD Updates

### Release Workflow

```yaml
# .github/workflows/release.yml

name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-xcframeworks:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build Commons XCFramework
        run: |
          cd runanywhere-commons
          ./build-xcframeworks.sh release
          ./scripts/package-xcframeworks.sh

      - name: Calculate Checksums
        run: |
          cd runanywhere-commons/dist
          for f in *.zip; do
            shasum -a 256 "$f" >> checksums.txt
          done

      - name: Upload to Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            runanywhere-commons/dist/*.zip
            runanywhere-commons/dist/checksums.txt

  update-swift-package:
    needs: build-xcframeworks
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          repository: RunanywhereAI/runanywhere-swift
          token: ${{ secrets.GH_PAT }}

      - name: Update Checksums
        run: |
          # Download checksums from release
          # Update Package.swift with new checksums
          ./scripts/update-package-checksums.sh ${{ github.ref_name }}

      - name: Create PR
        uses: peter-evans/create-pull-request@v5
        with:
          title: "Update to ${{ github.ref_name }}"
          body: "Automated update of binary checksums"
          branch: "release/${{ github.ref_name }}"
```

---

## Definition of Done

- [ ] C++ unit tests pass (gtest)
- [ ] Swift integration tests pass (XCTest)
- [ ] All backend combinations tested
- [ ] Platform adapter callbacks verified
- [ ] Binary sizes within targets
- [ ] Performance meets targets
- [ ] Size tracking in CI
- [ ] Documentation updated
- [ ] Migration guide complete
- [ ] Release workflow tested

---

*Phase 4 Duration: 2 weeks*
