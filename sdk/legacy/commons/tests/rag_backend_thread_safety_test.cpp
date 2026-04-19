#include <atomic>
#include <memory>
#include <thread>
#include <vector>

#include <gtest/gtest.h>

#include "rag_backend.h"

namespace runanywhere::rag {

class DummyEmbeddingProvider final : public IEmbeddingProvider {
public:
    explicit DummyEmbeddingProvider(size_t dimension) : dimension_(dimension) {}

    std::vector<float> embed(const std::string&) override {
        return std::vector<float>(dimension_, 0.1f);
    }

    size_t dimension() const noexcept override {
        return dimension_;
    }

    bool is_ready() const noexcept override {
        return true;
    }

    const char* name() const noexcept override {
        return "DummyEmbeddingProvider";
    }

private:
    size_t dimension_;
};

} // namespace runanywhere::rag

TEST(RAGBackendThreadSafety, ConcurrentSearchAndProviderSwap) {
    using namespace runanywhere::rag;

    RAGBackendConfig config;
    config.embedding_dimension = 4;
    config.chunk_size = 8;
    config.chunk_overlap = 0;
    config.top_k = 1;
    config.similarity_threshold = 0.0f;

    RAGBackend backend(
        config,
        std::make_unique<DummyEmbeddingProvider>(config.embedding_dimension)
    );

    bool added = backend.add_document("hello world");
    ASSERT_TRUE(added) << "Failed to add document in setup";

    std::atomic<bool> failed{false};

    std::thread searcher([&]() {
        try {
            for (int i = 0; i < 1000; ++i) {
                auto results = backend.search("hello", 1);
                (void)results;
            }
        } catch (...) {
            failed.store(true);
        }
    });

    std::thread setter([&]() {
        try {
            for (int i = 0; i < 1000; ++i) {
                backend.set_embedding_provider(
                    std::make_unique<DummyEmbeddingProvider>(config.embedding_dimension)
                );
            }
        } catch (...) {
            failed.store(true);
        }
    });

    searcher.join();
    setter.join();

    EXPECT_FALSE(failed.load()) << "Thread-safety test failed";
}
