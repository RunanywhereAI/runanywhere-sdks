/**
 * @file test_memory.cpp
 * @brief Standalone test for the memory/vector search layer.
 *
 * Build & run:
 *   cd sdk/runanywhere-commons
 *   cmake -B build -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_MEMORY=ON -DRAC_BUILD_TESTS=ON
 *   cmake --build build --target test_memory
 *   ./build/tests/test_memory
 */

#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/memory/rac_memory_service.h"
#include "rac/features/memory/rac_memory_types.h"

// ============================================================================
// Test helpers
// ============================================================================

static int tests_run = 0;
static int tests_passed = 0;

#define TEST(name)                                          \
    do {                                                    \
        tests_run++;                                        \
        printf("  [%02d] %-40s ", tests_run, name);         \
        fflush(stdout);                                     \
    } while (0)

#define PASS()                          \
    do {                                \
        tests_passed++;                 \
        printf("\033[32mPASS\033[0m\n");\
    } while (0)

#define FAIL(msg)                                           \
    do {                                                    \
        printf("\033[31mFAIL\033[0m  %s\n", msg);           \
        return;                                             \
    } while (0)

#define EXPECT_OK(expr)                                     \
    do {                                                    \
        rac_result_t _r = (expr);                           \
        if (_r != RAC_SUCCESS) {                            \
            char _buf[128];                                 \
            snprintf(_buf, sizeof(_buf),                    \
                     #expr " returned %d", (int)_r);        \
            FAIL(_buf);                                     \
        }                                                   \
    } while (0)

// ============================================================================
// Flat backend tests
// ============================================================================

static void test_flat_create_and_destroy() {
    TEST("Flat: create + destroy");

    rac_memory_config_t config = {};
    config.dimension = 8;
    config.metric = RAC_DISTANCE_COSINE;
    config.index_type = RAC_INDEX_FLAT;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));
    if (!handle) FAIL("handle is null");

    rac_memory_destroy(handle);
    PASS();
}

static void test_flat_add_and_search() {
    TEST("Flat: add + search");

    rac_memory_config_t config = {};
    config.dimension = 4;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_FLAT;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    // Add 3 vectors
    float vectors[] = {
        1.0f, 0.0f, 0.0f, 0.0f,  // id=10
        0.0f, 1.0f, 0.0f, 0.0f,  // id=20
        0.7f, 0.7f, 0.0f, 0.0f,  // id=30
    };
    uint64_t ids[] = {10, 20, 30};
    const char* meta[] = {"{\"a\":1}", "{\"b\":2}", nullptr};

    EXPECT_OK(rac_memory_add(handle, vectors, ids, meta, 3));

    // Search for nearest to [1,0,0,0]
    float query[] = {1.0f, 0.0f, 0.0f, 0.0f};
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(handle, query, 2, &results));

    if (results.count < 1) {
        rac_memory_destroy(handle);
        FAIL("no results");
    }
    if (results.results[0].id != 10) {
        char buf[64];
        snprintf(buf, sizeof(buf), "expected id=10, got id=%llu",
                 (unsigned long long)results.results[0].id);
        rac_memory_search_results_free(&results);
        rac_memory_destroy(handle);
        FAIL(buf);
    }

    printf("(top: id=%llu, score=%.4f) ",
           (unsigned long long)results.results[0].id, results.results[0].score);

    rac_memory_search_results_free(&results);
    rac_memory_destroy(handle);
    PASS();
}

static void test_flat_stats() {
    TEST("Flat: get_stats");

    rac_memory_config_t config = {};
    config.dimension = 4;
    config.metric = RAC_DISTANCE_COSINE;
    config.index_type = RAC_INDEX_FLAT;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    float vecs[] = {1, 0, 0, 0, 0, 1, 0, 0};
    uint64_t ids[] = {1, 2};
    EXPECT_OK(rac_memory_add(handle, vecs, ids, nullptr, 2));

    rac_memory_stats_t stats = {};
    EXPECT_OK(rac_memory_get_stats(handle, &stats));

    if (stats.num_vectors != 2) {
        rac_memory_destroy(handle);
        FAIL("expected 2 vectors");
    }
    if (stats.dimension != 4) {
        rac_memory_destroy(handle);
        FAIL("expected dim=4");
    }

    printf("(vectors=%llu, dim=%u, mem=%lluB) ",
           (unsigned long long)stats.num_vectors, stats.dimension,
           (unsigned long long)stats.memory_usage_bytes);

    rac_memory_destroy(handle);
    PASS();
}

static void test_flat_remove() {
    TEST("Flat: remove");

    rac_memory_config_t config = {};
    config.dimension = 4;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_FLAT;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    float vecs[] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
    uint64_t ids[] = {1, 2, 3};
    EXPECT_OK(rac_memory_add(handle, vecs, ids, nullptr, 3));

    // Remove id=2
    uint64_t remove_ids[] = {2};
    EXPECT_OK(rac_memory_remove(handle, remove_ids, 1));

    rac_memory_stats_t stats = {};
    EXPECT_OK(rac_memory_get_stats(handle, &stats));
    if (stats.num_vectors != 2) {
        rac_memory_destroy(handle);
        FAIL("expected 2 after remove");
    }

    // Search should not return id=2
    float query[] = {0, 1, 0, 0};
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(handle, query, 3, &results));

    for (uint32_t i = 0; i < results.count; i++) {
        if (results.results[i].id == 2) {
            rac_memory_search_results_free(&results);
            rac_memory_destroy(handle);
            FAIL("id=2 should not appear after remove");
        }
    }

    rac_memory_search_results_free(&results);
    rac_memory_destroy(handle);
    PASS();
}

static void test_flat_save_load() {
    TEST("Flat: save + load");

    rac_memory_config_t config = {};
    config.dimension = 4;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_FLAT;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    float vecs[] = {1, 0, 0, 0, 0, 1, 0, 0};
    uint64_t ids[] = {100, 200};
    const char* meta[] = {"{\"x\":1}", "{\"y\":2}"};
    EXPECT_OK(rac_memory_add(handle, vecs, ids, meta, 2));

    const char* path = "/tmp/rac_test_flat.racm";
    EXPECT_OK(rac_memory_save(handle, path));
    rac_memory_destroy(handle);

    // Load into new handle
    rac_handle_t loaded = nullptr;
    EXPECT_OK(rac_memory_load(path, &loaded));

    rac_memory_stats_t stats = {};
    EXPECT_OK(rac_memory_get_stats(loaded, &stats));
    if (stats.num_vectors != 2) {
        rac_memory_destroy(loaded);
        FAIL("expected 2 vectors after load");
    }

    // Search should work
    float query[] = {1, 0, 0, 0};
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(loaded, query, 1, &results));
    if (results.count < 1 || results.results[0].id != 100) {
        rac_memory_search_results_free(&results);
        rac_memory_destroy(loaded);
        FAIL("search after load gave wrong result");
    }

    // Check metadata survived
    if (results.results[0].metadata) {
        printf("(meta=%s) ", results.results[0].metadata);
    }

    rac_memory_search_results_free(&results);
    rac_memory_destroy(loaded);
    remove(path);
    PASS();
}

// ============================================================================
// HNSW backend tests
// ============================================================================

static void test_hnsw_create_and_destroy() {
    TEST("HNSW: create + destroy");

    rac_memory_config_t config = {};
    config.dimension = 16;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_HNSW;
    config.hnsw_m = 16;
    config.hnsw_ef_construction = 100;
    config.hnsw_ef_search = 50;
    config.max_elements = 1000;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));
    if (!handle) FAIL("handle is null");

    rac_memory_destroy(handle);
    PASS();
}

static void test_hnsw_add_and_search() {
    TEST("HNSW: add 100 + search top-5");

    rac_memory_config_t config = {};
    config.dimension = 32;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_HNSW;
    config.hnsw_m = 16;
    config.hnsw_ef_construction = 200;
    config.hnsw_ef_search = 50;
    config.max_elements = 200;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    // Generate 100 random vectors
    srand(42);
    const int N = 100;
    const int D = 32;
    std::vector<float> all_vecs(N * D);
    std::vector<uint64_t> all_ids(N);

    for (int i = 0; i < N; i++) {
        all_ids[i] = i + 1;
        for (int j = 0; j < D; j++) {
            all_vecs[i * D + j] = (float)rand() / RAND_MAX * 2.0f - 1.0f;
        }
    }

    EXPECT_OK(rac_memory_add(handle, all_vecs.data(), all_ids.data(), nullptr, N));

    // Search for the first vector — should get id=1 as top result
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(handle, all_vecs.data(), 5, &results));

    if (results.count < 1) {
        rac_memory_destroy(handle);
        FAIL("no results");
    }

    // Top result should be id=1 (exact match)
    if (results.results[0].id != 1) {
        char buf[64];
        snprintf(buf, sizeof(buf), "expected top id=1, got %llu",
                 (unsigned long long)results.results[0].id);
        rac_memory_search_results_free(&results);
        rac_memory_destroy(handle);
        FAIL(buf);
    }

    printf("(top5: ");
    for (uint32_t i = 0; i < results.count && i < 5; i++) {
        printf("%llu ", (unsigned long long)results.results[i].id);
    }
    printf(") ");

    rac_memory_search_results_free(&results);
    rac_memory_destroy(handle);
    PASS();
}

static void test_hnsw_remove() {
    TEST("HNSW: remove (mark-delete)");

    rac_memory_config_t config = {};
    config.dimension = 4;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_HNSW;
    config.hnsw_m = 8;
    config.hnsw_ef_construction = 50;
    config.hnsw_ef_search = 50;
    config.max_elements = 100;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    float vecs[] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
    uint64_t ids[] = {10, 20, 30};
    EXPECT_OK(rac_memory_add(handle, vecs, ids, nullptr, 3));

    uint64_t rm[] = {20};
    EXPECT_OK(rac_memory_remove(handle, rm, 1));

    // Search for [0,1,0,0] — id=20 was deleted, should not be top result
    float query[] = {0, 1, 0, 0};
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(handle, query, 3, &results));

    for (uint32_t i = 0; i < results.count; i++) {
        if (results.results[i].id == 20) {
            rac_memory_search_results_free(&results);
            rac_memory_destroy(handle);
            FAIL("deleted id=20 should not appear");
        }
    }

    rac_memory_search_results_free(&results);
    rac_memory_destroy(handle);
    PASS();
}

static void test_hnsw_save_load() {
    TEST("HNSW: save + load");

    rac_memory_config_t config = {};
    config.dimension = 8;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_HNSW;
    config.hnsw_m = 16;
    config.hnsw_ef_construction = 100;
    config.hnsw_ef_search = 50;
    config.max_elements = 100;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    // Add 10 vectors
    const int N = 10;
    const int D = 8;
    std::vector<float> vecs(N * D);
    std::vector<uint64_t> ids(N);
    srand(123);
    for (int i = 0; i < N; i++) {
        ids[i] = i + 1;
        for (int j = 0; j < D; j++) {
            vecs[i * D + j] = (float)rand() / RAND_MAX;
        }
    }
    EXPECT_OK(rac_memory_add(handle, vecs.data(), ids.data(), nullptr, N));

    const char* path = "/tmp/rac_test_hnsw.racm";
    EXPECT_OK(rac_memory_save(handle, path));
    rac_memory_destroy(handle);

    // Load
    rac_handle_t loaded = nullptr;
    EXPECT_OK(rac_memory_load(path, &loaded));

    rac_memory_stats_t stats = {};
    EXPECT_OK(rac_memory_get_stats(loaded, &stats));
    if (stats.num_vectors != 10) {
        char buf[64];
        snprintf(buf, sizeof(buf), "expected 10 vectors, got %llu",
                 (unsigned long long)stats.num_vectors);
        rac_memory_destroy(loaded);
        FAIL(buf);
    }

    // Search should work
    rac_memory_search_results_t results = {};
    EXPECT_OK(rac_memory_search(loaded, vecs.data(), 3, &results));
    if (results.count < 1 || results.results[0].id != 1) {
        rac_memory_search_results_free(&results);
        rac_memory_destroy(loaded);
        FAIL("search after load wrong");
    }

    printf("(loaded %llu vectors) ", (unsigned long long)stats.num_vectors);

    rac_memory_search_results_free(&results);
    rac_memory_destroy(loaded);

    // Cleanup
    remove(path);
    std::string hnsw_path = std::string(path) + ".hnsw";
    std::string meta_path = std::string(path) + ".meta";
    remove(hnsw_path.c_str());
    remove(meta_path.c_str());

    PASS();
}

// ============================================================================
// Performance benchmark
// ============================================================================

static void test_hnsw_perf_10k() {
    TEST("HNSW: perf 10K add + 100 searches");

    rac_memory_config_t config = {};
    config.dimension = 128;
    config.metric = RAC_DISTANCE_L2;
    config.index_type = RAC_INDEX_HNSW;
    config.hnsw_m = 16;
    config.hnsw_ef_construction = 100;
    config.hnsw_ef_search = 50;
    config.max_elements = 12000;

    rac_handle_t handle = nullptr;
    EXPECT_OK(rac_memory_create(&config, &handle));

    const int N = 10000;
    const int D = 128;
    std::vector<float> vecs(N * D);
    std::vector<uint64_t> ids(N);
    srand(99);
    for (int i = 0; i < N; i++) {
        ids[i] = i + 1;
        for (int j = 0; j < D; j++) {
            vecs[i * D + j] = (float)rand() / RAND_MAX * 2.0f - 1.0f;
        }
    }

    // Benchmark add
    auto t0 = std::chrono::high_resolution_clock::now();
    EXPECT_OK(rac_memory_add(handle, vecs.data(), ids.data(), nullptr, N));
    auto t1 = std::chrono::high_resolution_clock::now();
    double add_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    // Benchmark 100 searches
    auto t2 = std::chrono::high_resolution_clock::now();
    for (int q = 0; q < 100; q++) {
        rac_memory_search_results_t results = {};
        rac_memory_search(handle, &vecs[q * D], 10, &results);
        rac_memory_search_results_free(&results);
    }
    auto t3 = std::chrono::high_resolution_clock::now();
    double search_ms = std::chrono::duration<double, std::milli>(t3 - t2).count();

    printf("(add=%.0fms, 100 searches=%.1fms, avg=%.2fms/q) ",
           add_ms, search_ms, search_ms / 100.0);

    rac_memory_destroy(handle);
    PASS();
}

// ============================================================================
// Main
// ============================================================================

int main() {
    printf("\n=== RunAnywhere Memory Layer Tests ===\n\n");
    printf("--- Flat Backend ---\n");
    test_flat_create_and_destroy();
    test_flat_add_and_search();
    test_flat_stats();
    test_flat_remove();
    test_flat_save_load();

    printf("\n--- HNSW Backend ---\n");
    test_hnsw_create_and_destroy();
    test_hnsw_add_and_search();
    test_hnsw_remove();
    test_hnsw_save_load();

    printf("\n--- Performance ---\n");
    test_hnsw_perf_10k();

    printf("\n==============================\n");
    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    printf("==============================\n\n");

    return (tests_passed == tests_run) ? 0 : 1;
}
