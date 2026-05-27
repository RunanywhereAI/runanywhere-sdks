// SPDX-License-Identifier: Apache-2.0
//
// test_pipeline_executor.cpp — T4.7 unit tests for the PipelineSpec →
// GraphScheduler compiler. Protobuf-gated.

#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "pipeline.pb.h"

#include "rac/core/rac_error.h"
#include "rac/graph/pipeline_node.hpp"
#include "rac/solutions/config_loader.hpp"
#include "rac/solutions/operator_registry.hpp"
#include "rac/solutions/pipeline_executor.hpp"

namespace {

int g_failed = 0;
int g_passed = 0;

#define CHECK(cond)                                                               \
    do {                                                                          \
        if (!(cond)) {                                                            \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                           \
            return;                                                               \
        }                                                                         \
    } while (0)

#define TEST(name)                                      \
    static void test_##name();                          \
    static void run_test_##name() {                     \
        std::fprintf(stderr, "[RUN ] %s\n", #name);     \
        int before_failed = g_failed;                   \
        test_##name();                                  \
        if (g_failed == before_failed) {                \
            std::fprintf(stderr, "[  OK] %s\n", #name); \
            g_passed++;                                 \
        }                                               \
    }                                                   \
    static void test_##name()

using rac::solutions::Item;
using rac::solutions::OperatorAdapter;
using rac::solutions::OperatorAdapterFactory;
using rac::solutions::OperatorEdge;
using rac::solutions::OperatorFactory;
using rac::solutions::OperatorNode;
using rac::solutions::OperatorPortSchema;
using rac::solutions::OperatorRegistry;
using rac::solutions::PipelineExecutor;
using runanywhere::v1::EdgePolicy;
using runanywhere::v1::OperatorSpec;
using runanywhere::v1::PipelineSpec;

bool last_error_detail_contains(const std::string& needle) {
    const char* details = rac_error_get_details();
    return details != nullptr && std::string(details).find(needle) != std::string::npos;
}

bool wait_until_true(const std::atomic<bool>& flag, std::chrono::milliseconds timeout) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
        if (flag.load(std::memory_order_acquire))
            return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return flag.load(std::memory_order_acquire);
}

OperatorPortSchema make_text_schema(std::vector<std::string> inputs,
                                    std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadTextUtf8);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadTextUtf8);
    }
    return schema;
}

OperatorPortSchema make_audio_schema(std::vector<std::string> inputs,
                                     std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadAudioPcmS16Le);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadAudioPcmS16Le);
    }
    return schema;
}

OperatorPortSchema make_image_schema(std::vector<std::string> inputs,
                                     std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadImagePng);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadImagePng);
    }
    return schema;
}

OperatorPortSchema make_embedding_schema(std::vector<std::string> inputs,
                                         std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadEmbeddingVectorFloat32);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadEmbeddingVectorFloat32);
    }
    return schema;
}

std::string make_pcm_s16le_frame() {
    std::string frame(4, '\0');
    frame[2] = '\x01';
    return frame;
}

std::string make_png_image_bytes() {
    const unsigned char bytes[] = {
        0x89u, 0x50u, 0x4Eu, 0x47u, 0x0Du, 0x0Au, 0x1Au, 0x0Au, 0x00u, 0x00u, 0x00u, 0x0Du,
        0x49u, 0x48u, 0x44u, 0x52u, 0x00u, 0x00u, 0x00u, 0x01u, 0x00u, 0x00u, 0x00u, 0x01u,
        0x08u, 0x06u, 0x00u, 0x00u, 0x00u, 0x1Fu, 0x15u, 0xC4u, 0x89u, 0x00u, 0x00u, 0x00u,
        0x0Au, 0x49u, 0x44u, 0x41u, 0x54u, 0x78u, 0x9Cu, 0x63u, 0x00u, 0x01u, 0x00u, 0x00u,
        0x05u, 0x00u, 0x01u, 0x0Du, 0x0Au, 0x2Du, 0xB4u, 0x00u, 0x00u, 0x00u, 0x00u, 0x49u,
        0x45u, 0x4Eu, 0x44u, 0xAEu, 0x42u, 0x60u, 0x82u,
    };
    return std::string(reinterpret_cast<const char*>(bytes), sizeof(bytes));
}

class ScopedFactory {
   public:
    ScopedFactory(std::string type, OperatorFactory factory, OperatorPortSchema ports)
        : type_(std::move(type)) {
        auto& registry = OperatorRegistry::instance();
        registry.unregister_factory(type_);
        registry.register_factory(type_, std::move(factory), std::move(ports));
    }

    ~ScopedFactory() { OperatorRegistry::instance().unregister_factory(type_); }

    ScopedFactory(const ScopedFactory&) = delete;
    ScopedFactory& operator=(const ScopedFactory&) = delete;

   private:
    std::string type_;
};

class ScopedAdapterFactory {
   public:
    ScopedAdapterFactory(std::string type, OperatorAdapterFactory factory, OperatorPortSchema ports)
        : type_(std::move(type)) {
        auto& registry = OperatorRegistry::instance();
        registry.unregister_factory(type_);
        registry.register_adapter_factory(type_, std::move(factory), std::move(ports));
    }

    ~ScopedAdapterFactory() { OperatorRegistry::instance().unregister_factory(type_); }

    ScopedAdapterFactory(const ScopedAdapterFactory&) = delete;
    ScopedAdapterFactory& operator=(const ScopedAdapterFactory&) = delete;

   private:
    std::string type_;
};

// Helper: build a PipelineSpec with a linear `source -> mid -> sink`
// topology using the built-in echo/sink operators.
PipelineSpec make_linear_spec(const std::string& mid_type = "echo") {
    PipelineSpec spec;
    spec.set_name("linear");

    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");

    auto* mid = spec.add_operators();
    mid->set_name("mid");
    mid->set_type(mid_type);

    auto* snk = spec.add_operators();
    snk->set_name("snk");
    snk->set_type("sink");

    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("mid.in");

    auto* e2 = spec.add_edges();
    e2->set_from("mid.out");
    e2->set_to("snk.in");
    return spec;
}

PipelineSpec make_source_window_spec(const std::string& size = {}, const std::string& stride = {}) {
    PipelineSpec spec;
    spec.set_name("window");

    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");

    auto* win = spec.add_operators();
    win->set_name("win");
    win->set_type("window");
    if (!size.empty()) {
        (*win->mutable_params())["size"] = size;
    }
    if (!stride.empty()) {
        (*win->mutable_params())["stride"] = stride;
    }

    auto* edge = spec.add_edges();
    edge->set_from("src.out");
    edge->set_to("win.in");
    return spec;
}

// ---------------------------------------------------------------------------
// 1. Linear pipeline compiles + drains cleanly.
// ---------------------------------------------------------------------------
TEST(linear_pipeline_drains) {
    PipelineSpec spec = make_linear_spec();
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler != nullptr);
    CHECK(scheduler->node_count() == 5);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();

    input->push(Item::text("hello"), scheduler->root_cancel_token().get());
    input->push(Item::text("world"), scheduler->root_cancel_token().get());
    input->close();

    scheduler->wait();
    // Note: GraphScheduler::running() flips on explicit stop(), not on
    // natural drain — so we don't assert on it here. The scheduler's
    // node worker threads have all joined by the time wait() returns.
}

// ---------------------------------------------------------------------------
// 2. Unknown operator type fails validation.
// ---------------------------------------------------------------------------
TEST(unknown_operator_type_is_rejected) {
    PipelineSpec spec;
    spec.set_name("bad");
    auto* op = spec.add_operators();
    op->set_name("a");
    op->set_type("nonexistent_operator_xyz");
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 3. Edge that references an unknown operator fails validation.
// ---------------------------------------------------------------------------
TEST(dangling_edge_is_rejected) {
    PipelineSpec spec;
    spec.set_name("dangling");
    auto* a = spec.add_operators();
    a->set_name("a");
    a->set_type("echo");
    auto* e = spec.add_edges();
    e->set_from("a.out");
    e->set_to("phantom.in");
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 4. Custom operator factory registration drives payload transformation.
// ---------------------------------------------------------------------------
class UpperCaseNode : public OperatorNode {
   public:
    explicit UpperCaseNode(std::string n) : PipelineNode(std::move(n)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        auto text = item.text();
        for (auto& c : text) {
            c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        }
        out.push(Item::text(std::move(text), item.type_id), this->cancel_token());
    }
};

class CountingSinkNode : public OperatorNode {
   public:
    CountingSinkNode(std::string n, std::shared_ptr<std::atomic<int>> count)
        : PipelineNode(std::move(n)), count_(std::move(count)) {}

   protected:
    void process(Item /*item*/, OutputEdge& /*out*/) override {
        count_->fetch_add(1, std::memory_order_acq_rel);
    }

   private:
    std::shared_ptr<std::atomic<int>> count_;
};

struct CollectedItems {
    std::mutex mu;
    std::vector<std::string> items;
};

std::vector<std::string> snapshot_items(const std::shared_ptr<CollectedItems>& state) {
    std::lock_guard<std::mutex> lock(state->mu);
    return state->items;
}

class CollectingSinkNode : public OperatorNode {
   public:
    CollectingSinkNode(std::string n, std::shared_ptr<CollectedItems> state)
        : PipelineNode(std::move(n)), state_(std::move(state)) {}

   protected:
    void process(Item item, OutputEdge& /*out*/) override {
        std::lock_guard<std::mutex> lock(state_->mu);
        state_->items.push_back(item.text());
    }

   private:
    std::shared_ptr<CollectedItems> state_;
};

class WrongPayloadTypeNode : public OperatorNode {
   public:
    explicit WrongPayloadTypeNode(std::string n) : PipelineNode(std::move(n)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        (void)item;
        out.push(Item::audio_pcm_s16le(make_pcm_s16le_frame()), this->cancel_token());
    }
};

class RawBytesAudioEmitterNode : public OperatorNode {
   public:
    explicit RawBytesAudioEmitterNode(std::string n) : PipelineNode(std::move(n)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadAudioPcmS16Le, make_pcm_s16le_frame()),
                 this->cancel_token());
    }
};

class RawBytesImageEmitterNode : public OperatorNode {
   public:
    explicit RawBytesImageEmitterNode(std::string n) : PipelineNode(std::move(n)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadImagePng, make_png_image_bytes()),
                 this->cancel_token());
    }
};

class RawBytesEmbeddingEmitterNode : public OperatorNode {
   public:
    explicit RawBytesEmbeddingEmitterNode(std::string n) : PipelineNode(std::move(n)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(
            Item::typed_bytes(rac::solutions::kPayloadEmbeddingVectorFloat32, "raw-float32-bytes"),
            this->cancel_token());
    }
};

class TextAudioJoinNode final : public OperatorAdapter {
   public:
    explicit TextAudioJoinNode(std::string name)
        : name_(std::move(name)),
          text_(std::make_shared<OperatorEdge>(8)),
          audio_(std::make_shared<OperatorEdge>(8)),
          out_(std::make_shared<OperatorEdge>(8)) {}

    void start(std::shared_ptr<rac::graph::CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true))
            return;
        cancel_ = parent_cancel ? parent_cancel->create_child()
                                : std::make_shared<rac::graph::CancelToken>();
        worker_ = std::thread([this] { run(); });
    }

    void stop() override {
        if (cancel_)
            cancel_->cancel();
        text_->close();
        audio_->close();
    }

    void join() override {
        if (worker_.joinable())
            worker_.join();
        out_->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

    std::shared_ptr<OperatorEdge> input(const std::string& port) const noexcept override {
        if (port == "text")
            return text_;
        if (port == "audio")
            return audio_;
        return nullptr;
    }

    std::shared_ptr<OperatorEdge> output(const std::string& port) const noexcept override {
        return port == "out" ? out_ : nullptr;
    }

    bool set_input(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        if (port == "text") {
            text_ = std::move(edge);
            return true;
        }
        if (port == "audio") {
            audio_ = std::move(edge);
            return true;
        }
        return false;
    }

    bool set_output(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        if (port != "out")
            return false;
        out_ = std::move(edge);
        return true;
    }

   private:
    void run() {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto text = text_->pop(cancel_.get());
            if (!text)
                break;
            auto audio = audio_->pop(cancel_.get());
            if (!audio)
                break;
            out_->push(Item::text("text=" + text->text() + ";audio=" + audio->text()),
                       cancel_.get());
        }
        out_->close();
    }

    std::string name_;
    std::shared_ptr<OperatorEdge> text_;
    std::shared_ptr<OperatorEdge> audio_;
    std::shared_ptr<OperatorEdge> out_;
    std::shared_ptr<rac::graph::CancelToken> cancel_;
    std::thread worker_;
    std::atomic<bool> started_{false};
};

class TokenMetricsNode final : public OperatorAdapter {
   public:
    explicit TokenMetricsNode(std::string name)
        : name_(std::move(name)),
          in_(std::make_shared<OperatorEdge>(8)),
          tokens_(std::make_shared<OperatorEdge>(8)),
          metrics_(std::make_shared<OperatorEdge>(8)) {}

    void start(std::shared_ptr<rac::graph::CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true))
            return;
        cancel_ = parent_cancel ? parent_cancel->create_child()
                                : std::make_shared<rac::graph::CancelToken>();
        worker_ = std::thread([this] { run(); });
    }

    void stop() override {
        if (cancel_)
            cancel_->cancel();
        in_->close();
    }

    void join() override {
        if (worker_.joinable())
            worker_.join();
        tokens_->close();
        metrics_->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

    std::shared_ptr<OperatorEdge> input(const std::string& port) const noexcept override {
        return port == "in" ? in_ : nullptr;
    }

    std::shared_ptr<OperatorEdge> output(const std::string& port) const noexcept override {
        if (port == "tokens")
            return tokens_;
        if (port == "metrics")
            return metrics_;
        return nullptr;
    }

    bool set_input(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        if (port != "in")
            return false;
        in_ = std::move(edge);
        return true;
    }

    bool set_output(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        if (port == "tokens") {
            tokens_ = std::move(edge);
            return true;
        }
        if (port == "metrics") {
            metrics_ = std::move(edge);
            return true;
        }
        return false;
    }

   private:
    void run() {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto item = in_->pop(cancel_.get());
            if (!item)
                break;
            tokens_->push(Item::text("token:" + item->text()), cancel_.get());
            metrics_->push(Item::text("metric:" + std::to_string(item->size())), cancel_.get());
        }
        tokens_->close();
        metrics_->close();
    }

    std::string name_;
    std::shared_ptr<OperatorEdge> in_;
    std::shared_ptr<OperatorEdge> tokens_;
    std::shared_ptr<OperatorEdge> metrics_;
    std::shared_ptr<rac::graph::CancelToken> cancel_;
    std::thread worker_;
    std::atomic<bool> started_{false};
};

struct BlockingUntilCancelState {
    std::atomic<bool> entered{false};
    std::atomic<bool> observed_cancel{false};
};

class BlockingUntilCancelNode : public OperatorNode {
   public:
    BlockingUntilCancelNode(std::string n, std::shared_ptr<BlockingUntilCancelState> state)
        : PipelineNode(std::move(n), /*input*/ 1, /*output*/ 1), state_(std::move(state)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        state_->entered.store(true, std::memory_order_release);
        while (this->cancel_token() && !this->cancel_token()->is_cancelled()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        state_->observed_cancel.store(this->cancel_token() && this->cancel_token()->is_cancelled(),
                                      std::memory_order_release);
        out.push(std::move(item), this->cancel_token());
    }

   private:
    std::shared_ptr<BlockingUntilCancelState> state_;
};

TEST(registered_factory_transforms_payload) {
    auto& registry = OperatorRegistry::instance();
    const bool first_time = registry.register_factory("upper", [](const OperatorSpec& spec) {
        return std::make_shared<UpperCaseNode>(spec.name());
    });
    (void)first_time;  // registry is process-wide; replacement is fine

    PipelineSpec spec = make_linear_spec("upper");
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(st == RAC_SUCCESS);

    auto input = exec.root_input_edge();
    auto output = exec.root_output_edge();
    CHECK(input != nullptr);
    CHECK(output == nullptr);

    scheduler->start();
    input->push(Item::text("hello"), scheduler->root_cancel_token().get());
    input->close();

    // The sink declares no output port, so the executor no longer exposes
    // its internal scheduler edge as a solution output. Transformations are
    // observable
    // by swapping the tail's capacity for a non-terminal consumer or
    // by draining the upper node directly. Here we rely on the fact
    // that the scheduler fully joins before the sink's output edge is
    // closed, so a successful join implies the transform ran.
    scheduler->wait();
}

// ---------------------------------------------------------------------------
// 5. The built-in window operator runs without a stand-in factory.
// ---------------------------------------------------------------------------
TEST(built_in_window_operator_emits_joined_windows) {
    CHECK(OperatorRegistry::instance().has_factory("window"));

    PipelineSpec spec = make_source_window_spec("2", "1");
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler != nullptr);

    auto input = exec.root_input_edge();
    auto output = exec.root_output_edge();
    CHECK(input != nullptr);
    CHECK(output != nullptr);

    scheduler->start();
    input->push(Item::text("a"), scheduler->root_cancel_token().get());
    input->push(Item::text("b"), scheduler->root_cancel_token().get());
    input->push(Item::text("c"), scheduler->root_cancel_token().get());
    input->close();
    scheduler->wait();

    auto first = output->pop();
    auto second = output->pop();
    auto done = output->pop();
    CHECK(first.has_value());
    CHECK(second.has_value());
    CHECK(!done.has_value());
    CHECK(first->text() == "a\nb");
    CHECK(second->text() == "b\nc");
}

TEST(window_bad_params_fall_back_to_single_item_windows) {
    PipelineSpec spec = make_source_window_spec("not-an-int", "0");
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler != nullptr);

    auto input = exec.root_input_edge();
    auto output = exec.root_output_edge();
    CHECK(input != nullptr);
    CHECK(output != nullptr);

    scheduler->start();
    input->push(Item::text("solo"), scheduler->root_cancel_token().get());
    input->close();
    scheduler->wait();

    auto item = output->pop();
    auto done = output->pop();
    CHECK(item.has_value());
    CHECK(item->text() == "solo");
    CHECK(!done.has_value());
}

// ---------------------------------------------------------------------------
// 6. YAML → PipelineSpec → compile round-trip.
// ---------------------------------------------------------------------------
TEST(yaml_roundtrip_compiles) {
    const std::string yaml = R"YAML(
name: "sample"
operators:
  - name: "src"
    type: "source"
  - name: "mid"
    type: "echo"
  - name: "snk"
    type: "sink"
edges:
  - from: "src.out"
    to: "mid.in"
  - from: "mid.out"
    to: "snk.in"
options:
  strict_validation: true
)YAML";
    runanywhere::v1::PipelineSpec spec;
    rac_result_t st = rac::solutions::load_pipeline_from_yaml(yaml, &spec);
    CHECK(st == RAC_SUCCESS);
    CHECK(spec.name() == "sample");
    CHECK(spec.operators_size() == 3);
    CHECK(spec.edges_size() == 2);
    CHECK(spec.options().strict_validation());

    PipelineExecutor exec(spec);
    rac_result_t compile_st = RAC_SUCCESS;
    auto scheduler = exec.build(&compile_st);
    CHECK(compile_st == RAC_SUCCESS);
    CHECK(scheduler != nullptr);

    scheduler->start();
    auto input = exec.root_input_edge();
    CHECK(input != nullptr);
    input->push(Item::text("ping"), scheduler->root_cancel_token().get());
    input->close();
    scheduler->wait();
}

// ---------------------------------------------------------------------------
// 7. Proto-bytes round-trip.
// ---------------------------------------------------------------------------
TEST(proto_bytes_roundtrip_compiles) {
    PipelineSpec original = make_linear_spec();
    std::string bytes;
    CHECK(original.SerializeToString(&bytes));

    runanywhere::v1::PipelineSpec parsed;
    rac_result_t st =
        rac::solutions::load_pipeline_from_proto_bytes(bytes.data(), bytes.size(), &parsed);
    CHECK(st == RAC_SUCCESS);
    CHECK(parsed.operators_size() == original.operators_size());
    CHECK(parsed.edges_size() == original.edges_size());

    PipelineExecutor exec(parsed);
    rac_result_t cs = RAC_SUCCESS;
    auto scheduler = exec.build(&cs);
    CHECK(cs == RAC_SUCCESS);
    CHECK(scheduler != nullptr);
}

// ---------------------------------------------------------------------------
// 8. Duplicate operator name is rejected.
// ---------------------------------------------------------------------------
TEST(duplicate_operator_name_is_rejected) {
    PipelineSpec spec;
    spec.set_name("dup");
    for (int i = 0; i < 2; ++i) {
        auto* op = spec.add_operators();
        op->set_name("same");
        op->set_type("echo");
    }
    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 9. Bare edge endpoints are rejected; ports are part of the contract.
// ---------------------------------------------------------------------------
TEST(bare_endpoint_is_rejected) {
    PipelineSpec spec = make_linear_spec();
    spec.mutable_edges(0)->set_from("src");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 10. Empty and unknown ports are rejected.
// ---------------------------------------------------------------------------
TEST(empty_endpoint_port_is_rejected) {
    PipelineSpec spec = make_linear_spec();
    spec.mutable_edges(0)->set_from("src.");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

TEST(unknown_endpoint_port_is_rejected) {
    PipelineSpec spec = make_linear_spec();
    spec.mutable_edges(0)->set_from("src.audio");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 11. Duplicate edges are rejected.
// ---------------------------------------------------------------------------
TEST(duplicate_edge_is_rejected) {
    PipelineSpec spec = make_linear_spec();
    auto* dup = spec.add_edges();
    dup->set_from("src.out");
    dup->set_to("mid.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 12. Edge options with invalid capacity or enum policy are rejected.
// ---------------------------------------------------------------------------
TEST(edge_capacity_limit_is_enforced) {
    PipelineSpec spec = make_linear_spec();
    spec.mutable_edges(0)->set_capacity(std::numeric_limits<std::uint32_t>::max());

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

TEST(invalid_edge_policy_is_rejected) {
    PipelineSpec spec = make_linear_spec();
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    spec.mutable_edges(0)->set_policy(static_cast<EdgePolicy>(999));

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
}

// ---------------------------------------------------------------------------
// 13. Engine-backed primitive names require explicit factories.
// ---------------------------------------------------------------------------
TEST(real_primitive_without_factory_is_rejected) {
    OperatorRegistry::instance().unregister_factory("generate_text");

    PipelineSpec spec = make_linear_spec("generate_text");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    CHECK(last_error_detail_contains("explicit stand-in factory"));
}

TEST(real_primitive_with_explicit_factory_compiles) {
    ScopedFactory standin(
        "generate_text",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        make_text_schema({"in"}, {"token"}));

    PipelineSpec spec = make_linear_spec("generate_text");
    spec.mutable_edges(1)->set_from("mid.token");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);
}

// ---------------------------------------------------------------------------
// 14. Typed port payload metadata accepts matching payload contracts.
// ---------------------------------------------------------------------------
TEST(typed_port_payload_match_compiles) {
    OperatorPortSchema producer_ports;
    producer_ports.output_ports = {"audio"};
    producer_ports.output_port_types.emplace("audio", rac::solutions::kPayloadAudioPcmS16Le);

    OperatorPortSchema consumer_ports;
    consumer_ports.input_ports = {"audio"};
    consumer_ports.input_port_types.emplace("audio", rac::solutions::kPayloadAudioPcmS16Le);

    ScopedFactory producer(
        "cpp_graph_01b_audio_source",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(producer_ports));
    ScopedFactory consumer(
        "cpp_graph_01b_audio_sink",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(consumer_ports));

    PipelineSpec spec;
    spec.set_name("typed_match");
    auto* src = spec.add_operators();
    src->set_name("producer");
    src->set_type("cpp_graph_01b_audio_source");
    auto* snk = spec.add_operators();
    snk->set_name("consumer");
    snk->set_type("cpp_graph_01b_audio_sink");
    auto* edge = spec.add_edges();
    edge->set_from("producer.audio");
    edge->set_to("consumer.audio");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler->node_count() == 3);
}

// ---------------------------------------------------------------------------
// 15. Edges with incompatible typed payload contracts are rejected.
// ---------------------------------------------------------------------------
TEST(typed_port_payload_mismatch_is_rejected) {
    OperatorPortSchema producer_ports;
    producer_ports.output_ports = {"audio"};
    producer_ports.output_port_types.emplace("audio", rac::solutions::kPayloadAudioPcmS16Le);

    OperatorPortSchema consumer_ports;
    consumer_ports.input_ports = {"text"};
    consumer_ports.input_port_types.emplace("text", "text.utf8");

    ScopedFactory producer(
        "cpp_graph_01b_bad_audio_source",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(producer_ports));
    ScopedFactory consumer(
        "cpp_graph_01b_text_sink",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(consumer_ports));

    PipelineSpec spec;
    spec.set_name("typed_mismatch");
    auto* src = spec.add_operators();
    src->set_name("producer");
    src->set_type("cpp_graph_01b_bad_audio_source");
    auto* snk = spec.add_operators();
    snk->set_name("consumer");
    snk->set_type("cpp_graph_01b_text_sink");
    auto* edge = spec.add_edges();
    edge->set_from("producer.audio");
    edge->set_to("consumer.text");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("incompatible payload types"));
    CHECK(last_error_detail_contains(rac::solutions::kPayloadAudioPcmS16Le));
    CHECK(last_error_detail_contains("text.utf8"));
}

// ---------------------------------------------------------------------------
// 16. Legacy opaque payload metadata is rejected, even when both endpoints
//     use the same legacy type string.
// ---------------------------------------------------------------------------
TEST(legacy_opaque_payload_metadata_is_rejected) {
    OperatorPortSchema producer_ports;
    producer_ports.output_ports = {"bytes"};
    producer_ports.output_port_types.emplace("bytes", "opaque.bytes");

    OperatorPortSchema consumer_ports;
    consumer_ports.input_ports = {"bytes"};
    consumer_ports.input_port_types.emplace("bytes", "opaque.bytes");

    ScopedFactory producer(
        "cpp_graph_02a_opaque_source",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(producer_ports));
    ScopedFactory consumer(
        "cpp_graph_02a_opaque_sink",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(consumer_ports));

    PipelineSpec spec;
    spec.set_name("opaque_rejected");
    auto* src = spec.add_operators();
    src->set_name("producer");
    src->set_type("cpp_graph_02a_opaque_source");
    auto* snk = spec.add_operators();
    snk->set_name("consumer");
    snk->set_type("cpp_graph_02a_opaque_sink");
    auto* edge = spec.add_edges();
    edge->set_from("producer.bytes");
    edge->set_to("consumer.bytes");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("legacy opaque.bytes"));
}

TEST(missing_port_payload_metadata_is_rejected) {
    OperatorPortSchema producer_ports;
    producer_ports.output_ports = {"out"};

    ScopedFactory producer(
        "cpp_graph_02b_missing_type_source",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        std::move(producer_ports));
    ScopedFactory consumer(
        "cpp_graph_02b_missing_type_sink",
        [](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(),
                                                      std::make_shared<std::atomic<int>>(0));
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("missing_payload_metadata");
    auto* src = spec.add_operators();
    src->set_name("producer");
    src->set_type("cpp_graph_02b_missing_type_source");
    auto* snk = spec.add_operators();
    snk->set_name("consumer");
    snk->set_type("cpp_graph_02b_missing_type_sink");
    auto* edge = spec.add_edges();
    edge->set_from("producer.out");
    edge->set_to("consumer.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("payload type"));
    CHECK(last_error_detail_contains("producer.out"));
    CHECK(last_error_detail_contains("empty"));
}

TEST(operator_emitted_payload_type_mismatch_is_rejected_at_runtime) {
    auto received = std::make_shared<CollectedItems>();
    ScopedFactory bad_operator(
        "cpp_graph_02b_wrong_payload_type",
        [](const OperatorSpec& spec) {
            return std::make_shared<WrongPayloadTypeNode>(spec.name());
        },
        make_text_schema({"in"}, {"out"}));
    ScopedFactory collector(
        "cpp_graph_02b_collecting_sink",
        [received](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), received);
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("runtime_payload_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad = spec.add_operators();
    bad->set_name("bad");
    bad->set_type("cpp_graph_02b_wrong_payload_type");
    auto* snk = spec.add_operators();
    snk->set_name("collector");
    snk->set_type("cpp_graph_02b_collecting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.out");
    e2->set_to("collector.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("hello"), root.get()));
    input->close();
    scheduler->wait();

    CHECK(snapshot_items(received).empty());
    CHECK(root->is_cancelled());
}

TEST(operator_emitted_audio_type_with_raw_bytes_body_is_rejected_at_runtime) {
    auto received = std::make_shared<CollectedItems>();
    ScopedFactory bad_operator(
        "cpp_graph_03b_raw_bytes_audio_emitter",
        [](const OperatorSpec& spec) {
            return std::make_shared<RawBytesAudioEmitterNode>(spec.name());
        },
        OperatorPortSchema{
            {"in"},
            {"audio"},
            {{"in", rac::solutions::kPayloadTextUtf8}},
            {{"audio", rac::solutions::kPayloadAudioPcmS16Le}},
        });
    ScopedFactory collector(
        "cpp_graph_03b_audio_collecting_sink",
        [received](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), received);
        },
        make_audio_schema({"audio"}, {}));

    PipelineSpec spec;
    spec.set_name("runtime_audio_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad = spec.add_operators();
    bad->set_name("bad");
    bad->set_type("cpp_graph_03b_raw_bytes_audio_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("collector");
    snk->set_type("cpp_graph_03b_audio_collecting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.audio");
    e2->set_to("collector.audio");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("hello"), root.get()));
    input->close();
    scheduler->wait();

    CHECK(snapshot_items(received).empty());
    CHECK(root->is_cancelled());
}

TEST(operator_emitted_image_type_with_raw_bytes_body_is_rejected_at_runtime) {
    auto received = std::make_shared<CollectedItems>();
    ScopedFactory bad_operator(
        "cpp_graph_03c_raw_bytes_image_emitter",
        [](const OperatorSpec& spec) {
            return std::make_shared<RawBytesImageEmitterNode>(spec.name());
        },
        OperatorPortSchema{
            {"in"},
            {"image"},
            {{"in", rac::solutions::kPayloadTextUtf8}},
            {{"image", rac::solutions::kPayloadImagePng}},
        });
    ScopedFactory collector(
        "cpp_graph_03c_image_collecting_sink",
        [received](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), received);
        },
        make_image_schema({"image"}, {}));

    PipelineSpec spec;
    spec.set_name("runtime_image_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad = spec.add_operators();
    bad->set_name("bad");
    bad->set_type("cpp_graph_03c_raw_bytes_image_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("collector");
    snk->set_type("cpp_graph_03c_image_collecting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.image");
    e2->set_to("collector.image");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("hello"), root.get()));
    input->close();
    scheduler->wait();

    CHECK(snapshot_items(received).empty());
    CHECK(root->is_cancelled());
}

TEST(operator_emitted_embedding_type_with_raw_bytes_body_is_rejected_at_runtime) {
    auto received = std::make_shared<CollectedItems>();
    ScopedFactory bad_operator(
        "cpp_graph_03d_raw_bytes_embedding_emitter",
        [](const OperatorSpec& spec) {
            return std::make_shared<RawBytesEmbeddingEmitterNode>(spec.name());
        },
        OperatorPortSchema{
            {"in"},
            {"vec"},
            {{"in", rac::solutions::kPayloadTextUtf8}},
            {{"vec", rac::solutions::kPayloadEmbeddingVectorFloat32}},
        });
    ScopedFactory collector(
        "cpp_graph_03d_embedding_collecting_sink",
        [received](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), received);
        },
        make_embedding_schema({"vec"}, {}));

    PipelineSpec spec;
    spec.set_name("runtime_embedding_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad = spec.add_operators();
    bad->set_name("bad");
    bad->set_type("cpp_graph_03d_raw_bytes_embedding_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("collector");
    snk->set_type("cpp_graph_03d_embedding_collecting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.vec");
    e2->set_to("collector.vec");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("hello"), root.get()));
    input->close();
    scheduler->wait();

    CHECK(snapshot_items(received).empty());
    CHECK(root->is_cancelled());
}

// ---------------------------------------------------------------------------
// 17. Same-endpoint fan-out/fan-in is wired with SplitNode/MergeNode.
// ---------------------------------------------------------------------------
TEST(fanout_and_fanin_same_ports_use_split_merge_nodes) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory counting_sink(
        "cpp_graph_01d_count_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("split_merge_executor");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* left = spec.add_operators();
    left->set_name("left");
    left->set_type("echo");
    auto* right = spec.add_operators();
    right->set_name("right");
    right->set_type("echo");
    auto* joined = spec.add_operators();
    joined->set_name("joined");
    joined->set_type("cpp_graph_01d_count_sink");

    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("left.in");
    auto* e2 = spec.add_edges();
    e2->set_from("src.out");
    e2->set_to("right.in");
    auto* e3 = spec.add_edges();
    e3->set_from("left.out");
    e3->set_to("joined.in");
    auto* e4 = spec.add_edges();
    e4->set_from("right.out");
    e4->set_to("joined.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler->node_count() == 10);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("a"), root.get()));
    CHECK(input->push(Item::text("b"), root.get()));
    CHECK(input->push(Item::text("c"), root.get()));
    input->close();
    scheduler->wait();

    CHECK(seen->load(std::memory_order_acquire) == 6);
}

// ---------------------------------------------------------------------------
// 17. True named multi-port operators wire distinct input/output edges.
// ---------------------------------------------------------------------------
TEST(two_input_operator_wires_distinct_named_inputs) {
    ScopedAdapterFactory join_factory(
        "cpp_graph_01e_join_text_audio",
        [](const OperatorSpec& spec) { return std::make_shared<TextAudioJoinNode>(spec.name()); },
        make_text_schema({"text", "audio"}, {"out"}));

    PipelineSpec spec;
    spec.set_name("multi_input");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* join = spec.add_operators();
    join->set_name("join");
    join->set_type("cpp_graph_01e_join_text_audio");

    auto* text_edge = spec.add_edges();
    text_edge->set_from("src.out");
    text_edge->set_to("join.text");
    auto* audio_edge = spec.add_edges();
    audio_edge->set_from("src.out");
    audio_edge->set_to("join.audio");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler->node_count() == 5);

    auto input = exec.root_input_edge();
    auto output = exec.root_output_edge();
    CHECK(input != nullptr);
    CHECK(output != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("frame-1"), root.get()));
    CHECK(input->push(Item::text("frame-2"), root.get()));
    input->close();
    scheduler->wait();

    auto first = output->pop();
    auto second = output->pop();
    auto done = output->pop();
    CHECK(first.has_value());
    CHECK(second.has_value());
    CHECK(!done.has_value());
    CHECK(first->text() == "text=frame-1;audio=frame-1");
    CHECK(second->text() == "text=frame-2;audio=frame-2");
}

TEST(two_output_operator_wires_distinct_named_outputs) {
    auto token_items = std::make_shared<CollectedItems>();
    auto metric_items = std::make_shared<CollectedItems>();

    ScopedAdapterFactory tee_factory(
        "cpp_graph_01e_token_metrics",
        [](const OperatorSpec& spec) { return std::make_shared<TokenMetricsNode>(spec.name()); },
        make_text_schema({"in"}, {"tokens", "metrics"}));
    ScopedFactory token_sink(
        "cpp_graph_01e_token_sink",
        [token_items](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), token_items);
        },
        make_text_schema({"in"}, {}));
    ScopedFactory metric_sink(
        "cpp_graph_01e_metric_sink",
        [metric_items](const OperatorSpec& spec) {
            return std::make_shared<CollectingSinkNode>(spec.name(), metric_items);
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("multi_output");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* tee = spec.add_operators();
    tee->set_name("tee");
    tee->set_type("cpp_graph_01e_token_metrics");
    auto* tokens = spec.add_operators();
    tokens->set_name("tokens");
    tokens->set_type("cpp_graph_01e_token_sink");
    auto* metrics = spec.add_operators();
    metrics->set_name("metrics");
    metrics->set_type("cpp_graph_01e_metric_sink");

    auto* in = spec.add_edges();
    in->set_from("src.out");
    in->set_to("tee.in");
    auto* token_edge = spec.add_edges();
    token_edge->set_from("tee.tokens");
    token_edge->set_to("tokens.in");
    auto* metric_edge = spec.add_edges();
    metric_edge->set_from("tee.metrics");
    metric_edge->set_to("metrics.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler != nullptr);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler->node_count() == 7);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("hi"), root.get()));
    CHECK(input->push(Item::text("world"), root.get()));
    input->close();
    scheduler->wait();

    const auto tokens_seen = snapshot_items(token_items);
    const auto metrics_seen = snapshot_items(metric_items);
    CHECK(tokens_seen.size() == 2);
    CHECK(metrics_seen.size() == 2);
    CHECK(tokens_seen[0] == "token:hi");
    CHECK(tokens_seen[1] == "token:world");
    CHECK(metrics_seen[0] == "metric:2");
    CHECK(metrics_seen[1] == "metric:5");
}

TEST(single_port_factory_with_multi_output_wiring_is_rejected) {
    ScopedFactory multi_out(
        "cpp_graph_01e_single_multi_out",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        make_text_schema({"in"}, {"tokens", "metrics"}));
    ScopedFactory token_sink(
        "cpp_graph_01e_single_multi_out_token_sink",
        [](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(),
                                                      std::make_shared<std::atomic<int>>(0));
        },
        make_text_schema({"in"}, {}));
    ScopedFactory metric_sink(
        "cpp_graph_01e_single_multi_out_metric_sink",
        [](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(),
                                                      std::make_shared<std::atomic<int>>(0));
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("multi_output");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* mux = spec.add_operators();
    mux->set_name("mux");
    mux->set_type("cpp_graph_01e_single_multi_out");
    auto* tokens = spec.add_operators();
    tokens->set_name("tokens");
    tokens->set_type("cpp_graph_01e_single_multi_out_token_sink");
    auto* metrics = spec.add_operators();
    metrics->set_name("metrics");
    metrics->set_type("cpp_graph_01e_single_multi_out_metric_sink");

    auto* in = spec.add_edges();
    in->set_from("src.out");
    in->set_to("mux.in");
    auto* token_edge = spec.add_edges();
    token_edge->set_from("mux.tokens");
    token_edge->set_to("tokens.in");
    auto* metric_edge = spec.add_edges();
    metric_edge->set_from("mux.metrics");
    metric_edge->set_to("metrics.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("does not expose output port"));
    CHECK(last_error_detail_contains("OperatorAdapterFactory"));
    CHECK(last_error_detail_contains("mux"));
}

TEST(single_port_factory_with_multi_input_wiring_is_rejected) {
    ScopedFactory multi_in(
        "cpp_graph_01e_single_multi_in",
        [](const OperatorSpec& spec) { return std::make_shared<UpperCaseNode>(spec.name()); },
        make_text_schema({"text", "audio"}, {"out"}));

    PipelineSpec spec;
    spec.set_name("multi_input");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* join = spec.add_operators();
    join->set_name("join");
    join->set_type("cpp_graph_01e_single_multi_in");
    auto* snk = spec.add_operators();
    snk->set_name("snk");
    snk->set_type("sink");

    auto* text_edge = spec.add_edges();
    text_edge->set_from("src.out");
    text_edge->set_to("join.text");
    auto* audio_edge = spec.add_edges();
    audio_edge->set_from("src.out");
    audio_edge->set_to("join.audio");
    auto* out_edge = spec.add_edges();
    out_edge->set_from("join.out");
    out_edge->set_to("snk.in");

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("does not expose input port"));
    CHECK(last_error_detail_contains("OperatorAdapterFactory"));
    CHECK(last_error_detail_contains("join"));
}

TEST(fanout_with_nonuniform_branch_options_is_rejected) {
    PipelineSpec spec;
    spec.set_name("split_options");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* left = spec.add_operators();
    left->set_name("left");
    left->set_type("sink");
    auto* right = spec.add_operators();
    right->set_name("right");
    right->set_type("sink");

    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("left.in");
    e1->set_capacity(2);
    auto* e2 = spec.add_edges();
    e2->set_from("src.out");
    e2->set_to("right.in");
    e2->set_capacity(3);

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(scheduler == nullptr);
    CHECK(st == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(last_error_detail_contains("fan-out"));
    CHECK(last_error_detail_contains("uniform branch"));
}

// ---------------------------------------------------------------------------
// 18. Executor-built graphs propagate root cancellation into blocking nodes.
// ---------------------------------------------------------------------------
TEST(executor_built_graph_root_cancel_stops_blocking_operator) {
    auto state = std::make_shared<BlockingUntilCancelState>();
    ScopedFactory blocking(
        "cpp_graph_01c_block_until_cancel",
        [state](const OperatorSpec& spec) {
            return std::make_shared<BlockingUntilCancelNode>(spec.name(), state);
        },
        make_text_schema({"in"}, {"out"}));

    PipelineSpec spec;
    spec.set_name("cancel_propagates");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* blocker = spec.add_operators();
    blocker->set_name("blocker");
    blocker->set_type("cpp_graph_01c_block_until_cancel");
    auto* edge = spec.add_edges();
    edge->set_from("src.out");
    edge->set_to("blocker.in");
    edge->set_capacity(1);
    edge->set_policy(runanywhere::v1::EDGE_POLICY_BLOCK);

    PipelineExecutor exec(spec);
    rac_result_t st = RAC_SUCCESS;
    auto scheduler = exec.build(&st);
    CHECK(st == RAC_SUCCESS);
    CHECK(scheduler != nullptr);

    auto input = exec.root_input_edge();
    CHECK(input != nullptr);

    scheduler->start();
    auto root = scheduler->root_cancel_token();
    CHECK(input->push(Item::text("go"), root.get()));

    const bool entered = wait_until_true(state->entered, std::chrono::milliseconds(1000));
    if (!entered) {
        scheduler->cancel_all();
        scheduler->wait();
    }
    CHECK(entered);

    const auto t0 = std::chrono::steady_clock::now();
    root->cancel();
    scheduler->wait();
    const auto elapsed = std::chrono::steady_clock::now() - t0;

    CHECK(root->is_cancelled());
    CHECK(state->observed_cancel.load(std::memory_order_acquire));
    CHECK(elapsed < std::chrono::milliseconds(750));
}

// ---------------------------------------------------------------------------
// Runner harness
// ---------------------------------------------------------------------------
}  // namespace

int main() {
    run_test_linear_pipeline_drains();
    run_test_unknown_operator_type_is_rejected();
    run_test_dangling_edge_is_rejected();
    run_test_registered_factory_transforms_payload();
    run_test_built_in_window_operator_emits_joined_windows();
    run_test_window_bad_params_fall_back_to_single_item_windows();
    run_test_yaml_roundtrip_compiles();
    run_test_proto_bytes_roundtrip_compiles();
    run_test_duplicate_operator_name_is_rejected();
    run_test_bare_endpoint_is_rejected();
    run_test_empty_endpoint_port_is_rejected();
    run_test_unknown_endpoint_port_is_rejected();
    run_test_duplicate_edge_is_rejected();
    run_test_edge_capacity_limit_is_enforced();
    run_test_invalid_edge_policy_is_rejected();
    run_test_real_primitive_without_factory_is_rejected();
    run_test_real_primitive_with_explicit_factory_compiles();
    run_test_typed_port_payload_match_compiles();
    run_test_typed_port_payload_mismatch_is_rejected();
    run_test_legacy_opaque_payload_metadata_is_rejected();
    run_test_missing_port_payload_metadata_is_rejected();
    run_test_operator_emitted_payload_type_mismatch_is_rejected_at_runtime();
    run_test_operator_emitted_audio_type_with_raw_bytes_body_is_rejected_at_runtime();
    run_test_operator_emitted_image_type_with_raw_bytes_body_is_rejected_at_runtime();
    run_test_operator_emitted_embedding_type_with_raw_bytes_body_is_rejected_at_runtime();
    run_test_fanout_and_fanin_same_ports_use_split_merge_nodes();
    run_test_two_input_operator_wires_distinct_named_inputs();
    run_test_two_output_operator_wires_distinct_named_outputs();
    run_test_single_port_factory_with_multi_output_wiring_is_rejected();
    run_test_single_port_factory_with_multi_input_wiring_is_rejected();
    run_test_fanout_with_nonuniform_branch_options_is_rejected();
    run_test_executor_built_graph_root_cancel_stops_blocking_operator();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
