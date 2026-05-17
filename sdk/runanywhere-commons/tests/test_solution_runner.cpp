// SPDX-License-Identifier: Apache-2.0
//
// test_solution_runner.cpp — T4.7 lifecycle + C ABI tests.

#include <cstdio>
#include <cstring>

#if defined(RAC_HAVE_PROTOBUF)
#include "pipeline.pb.h"
#include "sdk_events.pb.h"
#include "solutions.pb.h"
#include "voice_events.pb.h"

#include "rac/core/rac_error.h"
#include "rac/graph/pipeline_node.hpp"
#include "rac/solutions/config_loader.hpp"
#include "rac/solutions/operator_registry.hpp"
#include "rac/solutions/rac_solution.h"
#include "rac/solutions/solution_converter.hpp"
#include "rac/solutions/solution_runner.hpp"

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
using rac::solutions::OperatorFactory;
using rac::solutions::OperatorNode;
using rac::solutions::OperatorPortSchema;
using rac::solutions::OperatorRegistry;
using rac::solutions::SolutionRunner;
using runanywhere::v1::OperatorSpec;
using runanywhere::v1::PipelineSpec;
using runanywhere::v1::SolutionConfig;

bool last_error_detail_contains(const std::string& needle) {
    const char* details = rac_error_get_details();
    return details != nullptr && std::string(details).find(needle) != std::string::npos;
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

OperatorPortSchema make_terminal_schema(std::vector<std::string> inputs,
                                        std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadControlTerminal);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadControlTerminal);
    }
    return schema;
}

OperatorPortSchema make_sdk_event_schema(std::vector<std::string> inputs,
                                         std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadSdkEvent);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadSdkEvent);
    }
    return schema;
}

OperatorPortSchema make_voice_event_schema(std::vector<std::string> inputs,
                                           std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, rac::solutions::kPayloadVoiceEvent);
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, rac::solutions::kPayloadVoiceEvent);
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

std::string make_sdk_event_bytes() {
    runanywhere::v1::SDKEvent event;
    event.set_id("evt-03e");
    event.set_timestamp_ms(1);
    event.set_category(runanywhere::v1::EVENT_CATEGORY_INITIALIZATION);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.mutable_initialization()->set_stage(runanywhere::v1::INITIALIZATION_STAGE_STARTED);
    std::string bytes;
    if (!event.SerializeToString(&bytes))
        return {};
    return bytes;
}

std::string make_voice_event_bytes() {
    runanywhere::v1::VoiceEvent event;
    event.set_seq(1);
    event.set_timestamp_us(1);
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    event.mutable_state()->set_previous(runanywhere::v1::PIPELINE_STATE_IDLE);
    event.mutable_state()->set_current(runanywhere::v1::PIPELINE_STATE_STOPPED);
    std::string bytes;
    if (!event.SerializeToString(&bytes))
        return {};
    return bytes;
}

class ForwardNode final : public OperatorNode {
   public:
    explicit ForwardNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        out.push(std::move(item), this->cancel_token());
    }
};

class RawBytesTextEmitterNode final : public OperatorNode {
   public:
    explicit RawBytesTextEmitterNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadTextUtf8, item.text()),
                 this->cancel_token());
    }
};

class RawBytesAudioEmitterNode final : public OperatorNode {
   public:
    explicit RawBytesAudioEmitterNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadAudioPcmS16Le, make_pcm_s16le_frame()),
                 this->cancel_token());
    }
};

class RawBytesImageEmitterNode final : public OperatorNode {
   public:
    explicit RawBytesImageEmitterNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadImagePng, make_png_image_bytes()),
                 this->cancel_token());
    }
};

class RawBytesEmbeddingEmitterNode final : public OperatorNode {
   public:
    explicit RawBytesEmbeddingEmitterNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(
            Item::typed_bytes(rac::solutions::kPayloadEmbeddingVectorFloat32, "raw-float32-bytes"),
            this->cancel_token());
    }
};

class RawBytesSdkEventEmitterNode final : public OperatorNode {
   public:
    explicit RawBytesSdkEventEmitterNode(std::string name) : PipelineNode(std::move(name)) {}

   protected:
    void process(Item /*item*/, OutputEdge& out) override {
        out.push(Item::typed_bytes(rac::solutions::kPayloadSdkEvent, make_sdk_event_bytes()),
                 this->cancel_token());
    }
};

class CountingSinkNode final : public OperatorNode {
   public:
    CountingSinkNode(std::string name, std::shared_ptr<std::atomic<int>> count)
        : PipelineNode(std::move(name)), count_(std::move(count)) {}

   protected:
    void process(Item /*item*/, OutputEdge& /*out*/) override {
        count_->fetch_add(1, std::memory_order_acq_rel);
    }

   private:
    std::shared_ptr<std::atomic<int>> count_;
};

class TextCaptureSinkNode final : public OperatorNode {
   public:
    TextCaptureSinkNode(std::string name, std::shared_ptr<std::string> last)
        : PipelineNode(std::move(name)), last_(std::move(last)) {}

   protected:
    void process(Item item, OutputEdge& /*out*/) override { *last_ = item.text(); }

   private:
    std::shared_ptr<std::string> last_;
};

OperatorFactory make_forward_factory() {
    return [](const OperatorSpec& spec) { return std::make_shared<ForwardNode>(spec.name()); };
}

void cleanup_solution_standins() {
    const char* const kTypes[] = {
        "anomaly_detect", "detect_voice", "embed",      "generate_text",
        "retrieve",       "synthesize",   "transcribe",
    };
    auto& registry = OperatorRegistry::instance();
    for (const char* type : kTypes) {
        registry.unregister_factory(type);
    }
    // `retrieve` ships as a built-in tagged stand-in (see
    // register_builtin_operators). Re-register the built-in so subsequent
    // tests can rely on `has_factory("retrieve") == true`, while any
    // engine-backed or test-time override has been cleared above.
    rac::solutions::register_builtin_operators(registry);
}

class ScopedSolutionStandins {
   public:
    ScopedSolutionStandins() {
        cleanup_solution_standins();

        auto& registry = OperatorRegistry::instance();
        registry.register_factory("detect_voice", make_forward_factory(),
                                  make_text_schema({"in"}, {"out"}));
        registry.register_factory("transcribe", make_forward_factory(),
                                  make_text_schema({"in"}, {"final"}));
        registry.register_factory("generate_text", make_forward_factory(),
                                  make_text_schema({"in"}, {"token"}));
        registry.register_factory("synthesize", make_forward_factory(),
                                  make_text_schema({"in"}, {"out"}));
        registry.register_factory("embed", make_forward_factory(),
                                  make_text_schema({"in"}, {"vec"}));
        registry.register_factory("retrieve", make_forward_factory(),
                                  make_text_schema({"in"}, {"results"}));
    }

    ~ScopedSolutionStandins() { cleanup_solution_standins(); }

    ScopedSolutionStandins(const ScopedSolutionStandins&) = delete;
    ScopedSolutionStandins& operator=(const ScopedSolutionStandins&) = delete;
};

class ScopedTimeSeriesStandins {
   public:
    ScopedTimeSeriesStandins() {
        cleanup_solution_standins();

        auto& registry = OperatorRegistry::instance();
        registry.register_factory("anomaly_detect", make_forward_factory(),
                                  make_text_schema({"in"}, {"out"}));
        registry.register_factory("generate_text", make_forward_factory(),
                                  make_text_schema({"in"}, {"token"}));
    }

    ~ScopedTimeSeriesStandins() { cleanup_solution_standins(); }

    ScopedTimeSeriesStandins(const ScopedTimeSeriesStandins&) = delete;
    ScopedTimeSeriesStandins& operator=(const ScopedTimeSeriesStandins&) = delete;
};

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

PipelineSpec make_linear_spec() {
    PipelineSpec spec;
    spec.set_name("run_linear");
    auto* a = spec.add_operators();
    a->set_name("src");
    a->set_type("source");
    auto* b = spec.add_operators();
    b->set_name("mid");
    b->set_type("echo");
    auto* c = spec.add_operators();
    c->set_name("snk");
    c->set_type("sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("mid.in");
    auto* e2 = spec.add_edges();
    e2->set_from("mid.out");
    e2->set_to("snk.in");
    return spec;
}

// ---------------------------------------------------------------------------
// 1. Full lifecycle: start + feed + close + wait.
// ---------------------------------------------------------------------------
TEST(start_feed_close_lifecycle) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("hello")) == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("world")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
    CHECK(!runner.running());
}

// ---------------------------------------------------------------------------
// 2. Double-start returns ALREADY_INITIALIZED.
// ---------------------------------------------------------------------------
TEST(double_start_is_rejected) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.start() == RAC_ERROR_ALREADY_INITIALIZED);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 3. cancel() fires mid-stream and the scheduler joins.
// ---------------------------------------------------------------------------
TEST(cancel_mid_stream_joins) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);

    // Feed a few items but never close — the runner should only exit
    // because we cancel.
    for (int i = 0; i < 4; ++i) {
        CHECK(runner.feed(Item::text("item")) == RAC_SUCCESS);
    }
    runner.cancel();

    // Wait should return within a bounded time (cancellation deadline
    // in the graph runtime is ~50ms).
    auto start = std::chrono::steady_clock::now();
    runner.wait();
    auto elapsed = std::chrono::steady_clock::now() - start;
    CHECK(elapsed < std::chrono::seconds(5));
    CHECK(!runner.running());
}

// ---------------------------------------------------------------------------
// 4. feed() before start is a user error.
// ---------------------------------------------------------------------------
TEST(feed_before_start_fails) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.feed(Item::text("x")) == RAC_ERROR_COMPONENT_NOT_READY);
}

// ---------------------------------------------------------------------------
// 5. feed() enforces the root input payload type metadata.
// ---------------------------------------------------------------------------
TEST(feed_payload_type_mismatch_is_rejected) {
    OperatorPortSchema audio_ports;
    audio_ports.input_ports = {"in"};
    audio_ports.output_ports = {"out"};
    audio_ports.input_port_types.emplace("in", rac::solutions::kPayloadAudioPcmS16Le);
    audio_ports.output_port_types.emplace("out", rac::solutions::kPayloadAudioPcmS16Le);

    ScopedFactory audio("cpp_graph_02a_audio_forward", make_forward_factory(),
                        std::move(audio_ports));

    PipelineSpec spec;
    spec.set_name("audio_feed_contract");
    auto* op = spec.add_operators();
    op->set_name("audio");
    op->set_type("cpp_graph_02a_audio_forward");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("not-audio")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("root input payload type"));
    CHECK(runner.feed(Item::text("mislabeled-audio", rac::solutions::kPayloadAudioPcmS16Le)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("payload body contract"));
    CHECK(runner.feed(Item::typed_bytes(rac::solutions::kPayloadAudioPcmS16Le,
                                        make_pcm_s16le_frame())) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(runner.feed(Item::audio_pcm_s16le(std::string(1, '\0'))) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("partial 16-bit sample"));
    CHECK(runner.feed(Item::audio_pcm_s16le(make_pcm_s16le_frame())) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

TEST(feed_image_payload_body_contract_is_enforced) {
    ScopedFactory image("cpp_graph_03c_image_forward", make_forward_factory(),
                        make_image_schema({"in"}, {"out"}));

    PipelineSpec spec;
    spec.set_name("image_feed_contract");
    auto* op = spec.add_operators();
    op->set_name("image");
    op->set_type("cpp_graph_03c_image_forward");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("not-image")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("root input payload type"));
    CHECK(runner.feed(Item::text("mislabeled-image", rac::solutions::kPayloadImagePng)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("payload body contract"));
    CHECK(last_error_detail_contains("text.utf8"));
    CHECK(runner.feed(Item::typed_bytes(rac::solutions::kPayloadImagePng,
                                        make_png_image_bytes())) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(runner.feed(Item::image_bytes(std::string{})) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("image.bytes"));
    CHECK(runner.feed(Item::image_bytes("not-a-png")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("PNG signature"));
    CHECK(
        runner.feed(Item::image_bytes(make_png_image_bytes(), rac::solutions::kPayloadTextUtf8)) ==
        RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("image.bytes"));
    CHECK(last_error_detail_contains("text.utf8"));
    CHECK(runner.feed(Item::image_bytes(make_png_image_bytes())) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

TEST(feed_text_payload_requires_text_body) {
    SolutionRunner runner(make_linear_spec());
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::typed_bytes(rac::solutions::kPayloadTextUtf8, "raw bytes")) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("payload body contract"));
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

TEST(feed_embedding_payload_body_contract_is_enforced) {
    ScopedFactory embedding("cpp_graph_03d_embedding_forward", make_forward_factory(),
                            make_embedding_schema({"in"}, {"vec"}));

    PipelineSpec spec;
    spec.set_name("embedding_feed_contract");
    auto* op = spec.add_operators();
    op->set_name("embed");
    op->set_type("cpp_graph_03d_embedding_forward");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("not-embedding")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("root input payload type"));
    CHECK(runner.feed(
              Item::text("mislabeled-embedding", rac::solutions::kPayloadEmbeddingVectorFloat32)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("payload body contract"));
    CHECK(last_error_detail_contains("text.utf8"));
    CHECK(runner.feed(Item::typed_bytes(rac::solutions::kPayloadEmbeddingVectorFloat32,
                                        "raw-float32-bytes")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(runner.feed(Item::embedding_vector(std::vector<float>{})) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("embedding.vector"));
    CHECK(last_error_detail_contains("empty"));

    auto misaligned = Item::embedding_vector(std::vector<float>{0.1f, 0.2f});
    misaligned.embedding_vector_body.element_count = 3;
    CHECK(runner.feed(std::move(misaligned)) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("misaligned"));
    CHECK(last_error_detail_contains("element count"));

    auto wrong_element_type = Item::embedding_vector(std::vector<float>{0.1f});
    wrong_element_type.embedding_vector_body.element_type_id = "float16";
    CHECK(runner.feed(std::move(wrong_element_type)) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("element type"));
    CHECK(last_error_detail_contains("float16"));

    CHECK(runner.feed(
              Item::embedding_vector(std::vector<float>{0.1f}, rac::solutions::kPayloadTextUtf8)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("embedding.vector"));
    CHECK(last_error_detail_contains("text.utf8"));

    CHECK(runner.feed(Item::embedding_vector(std::vector<float>{0.1f, -0.2f, 0.3f})) ==
          RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

TEST(feed_terminal_control_payload_body_contract_is_enforced) {
    ScopedFactory terminal("cpp_graph_03e_terminal_forward", make_forward_factory(),
                           make_terminal_schema({"in"}, {"out"}));

    PipelineSpec spec;
    spec.set_name("terminal_feed_contract");
    auto* op = spec.add_operators();
    op->set_name("terminal");
    op->set_type("cpp_graph_03e_terminal_forward");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("not-terminal")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("root input payload type"));
    CHECK(runner.feed(Item::text("mislabeled-terminal", rac::solutions::kPayloadControlTerminal)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("payload body contract"));
    CHECK(last_error_detail_contains("text.utf8"));
    CHECK(runner.feed(Item::typed_bytes(rac::solutions::kPayloadControlTerminal, "done")) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(runner.feed(Item::control_signal(rac::solutions::PayloadControlSignalKind::Cancellation,
                                           "cancel", 0, rac::solutions::kPayloadControlTerminal)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("control.signal"));
    CHECK(last_error_detail_contains(rac::solutions::kPayloadControlCancellation));
    CHECK(runner.feed(Item::terminal_control("done")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

TEST(feed_event_payload_body_contracts_are_enforced) {
    const std::string sdk_event = make_sdk_event_bytes();
    const std::string voice_event = make_voice_event_bytes();
    CHECK(!sdk_event.empty());
    CHECK(!voice_event.empty());

    ScopedFactory sdk_forward("cpp_graph_03e_sdk_event_forward", make_forward_factory(),
                              make_sdk_event_schema({"in"}, {"out"}));
    PipelineSpec sdk_spec;
    sdk_spec.set_name("sdk_event_feed_contract");
    auto* sdk_op = sdk_spec.add_operators();
    sdk_op->set_name("event");
    sdk_op->set_type("cpp_graph_03e_sdk_event_forward");

    SolutionRunner sdk_runner(sdk_spec);
    CHECK(sdk_runner.start() == RAC_SUCCESS);
    CHECK(sdk_runner.feed(Item::typed_bytes(rac::solutions::kPayloadSdkEvent, sdk_event)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(sdk_runner.feed(Item::sdk_event_proto("not-proto")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("SDKEvent"));
    CHECK(last_error_detail_contains("decode"));

    runanywhere::v1::SDKEvent no_oneof;
    no_oneof.set_id("evt-no-oneof");
    std::string no_oneof_bytes;
    CHECK(no_oneof.SerializeToString(&no_oneof_bytes));
    CHECK(sdk_runner.feed(Item::sdk_event_proto(no_oneof_bytes)) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("no SDKEvent oneof payload"));

    CHECK(sdk_runner.feed(Item::sdk_event_proto(sdk_event, rac::solutions::kPayloadVoiceEvent)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("proto.runanywhere.v1.SDKEvent"));
    CHECK(last_error_detail_contains(rac::solutions::kPayloadVoiceEvent));
    CHECK(sdk_runner.feed(Item::sdk_event_proto(sdk_event)) == RAC_SUCCESS);
    sdk_runner.close_input();
    sdk_runner.wait();

    ScopedFactory voice_forward("cpp_graph_03e_voice_event_forward", make_forward_factory(),
                                make_voice_event_schema({"in"}, {"out"}));
    PipelineSpec voice_spec;
    voice_spec.set_name("voice_event_feed_contract");
    auto* voice_op = voice_spec.add_operators();
    voice_op->set_name("event");
    voice_op->set_type("cpp_graph_03e_voice_event_forward");

    SolutionRunner voice_runner(voice_spec);
    CHECK(voice_runner.start() == RAC_SUCCESS);
    CHECK(voice_runner.feed(Item::typed_bytes(rac::solutions::kPayloadVoiceEvent, voice_event)) ==
          RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("bytes.raw"));
    CHECK(voice_runner.feed(Item::voice_event_proto("not-proto")) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("VoiceEvent"));
    CHECK(last_error_detail_contains("decode"));
    CHECK(voice_runner.feed(Item::voice_event_proto(
              voice_event, rac::solutions::kPayloadSdkEvent)) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(last_error_detail_contains("proto.runanywhere.v1.VoiceEvent"));
    CHECK(last_error_detail_contains(rac::solutions::kPayloadSdkEvent));
    CHECK(voice_runner.feed(Item::voice_event_proto(voice_event)) == RAC_SUCCESS);
    voice_runner.close_input();
    voice_runner.wait();
}

TEST(operator_emitted_text_type_with_raw_bytes_body_is_rejected) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory bad(
        "cpp_graph_03a_raw_bytes_text_emitter",
        [](const OperatorSpec& spec) {
            return std::make_shared<RawBytesTextEmitterNode>(spec.name());
        },
        make_text_schema({"in"}, {"out"}));
    ScopedFactory sink(
        "cpp_graph_03a_counting_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("operator_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad_op = spec.add_operators();
    bad_op->set_name("bad");
    bad_op->set_type("cpp_graph_03a_raw_bytes_text_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_graph_03a_counting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.out");
    e2->set_to("sink.in");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(seen->load(std::memory_order_acquire) == 0);
}

TEST(operator_emitted_audio_type_with_raw_bytes_body_is_rejected) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory bad(
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
    ScopedFactory sink(
        "cpp_graph_03b_audio_counting_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_audio_schema({"audio"}, {}));

    PipelineSpec spec;
    spec.set_name("operator_audio_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad_op = spec.add_operators();
    bad_op->set_name("bad");
    bad_op->set_type("cpp_graph_03b_raw_bytes_audio_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_graph_03b_audio_counting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.audio");
    e2->set_to("sink.audio");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(seen->load(std::memory_order_acquire) == 0);
}

TEST(operator_emitted_image_type_with_raw_bytes_body_is_rejected) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory bad(
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
    ScopedFactory sink(
        "cpp_graph_03c_image_counting_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_image_schema({"image"}, {}));

    PipelineSpec spec;
    spec.set_name("operator_image_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad_op = spec.add_operators();
    bad_op->set_name("bad");
    bad_op->set_type("cpp_graph_03c_raw_bytes_image_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_graph_03c_image_counting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.image");
    e2->set_to("sink.image");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(seen->load(std::memory_order_acquire) == 0);
}

TEST(operator_emitted_embedding_type_with_raw_bytes_body_is_rejected) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory bad(
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
    ScopedFactory sink(
        "cpp_graph_03d_embedding_counting_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_embedding_schema({"vec"}, {}));

    PipelineSpec spec;
    spec.set_name("operator_embedding_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad_op = spec.add_operators();
    bad_op->set_name("bad");
    bad_op->set_type("cpp_graph_03d_raw_bytes_embedding_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_graph_03d_embedding_counting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.vec");
    e2->set_to("sink.vec");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(seen->load(std::memory_order_acquire) == 0);
}

TEST(operator_emitted_sdk_event_type_with_raw_bytes_body_is_rejected) {
    auto seen = std::make_shared<std::atomic<int>>(0);
    ScopedFactory bad(
        "cpp_graph_03e_raw_bytes_sdk_event_emitter",
        [](const OperatorSpec& spec) {
            return std::make_shared<RawBytesSdkEventEmitterNode>(spec.name());
        },
        OperatorPortSchema{
            {"in"},
            {"event"},
            {{"in", rac::solutions::kPayloadTextUtf8}},
            {{"event", rac::solutions::kPayloadSdkEvent}},
        });
    ScopedFactory sink(
        "cpp_graph_03e_sdk_event_counting_sink",
        [seen](const OperatorSpec& spec) {
            return std::make_shared<CountingSinkNode>(spec.name(), seen);
        },
        make_sdk_event_schema({"event"}, {}));

    PipelineSpec spec;
    spec.set_name("operator_sdk_event_body_contract");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* bad_op = spec.add_operators();
    bad_op->set_name("bad");
    bad_op->set_type("cpp_graph_03e_raw_bytes_sdk_event_emitter");
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_graph_03e_sdk_event_counting_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("bad.in");
    auto* e2 = spec.add_edges();
    e2->set_from("bad.event");
    e2->set_to("sink.event");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("typed text")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(seen->load(std::memory_order_acquire) == 0);
}

// ---------------------------------------------------------------------------
// 6. SolutionConfig (VoiceAgent) exposes missing real operator factories.
// ---------------------------------------------------------------------------
TEST(voice_agent_solution_without_real_factories_is_unavailable) {
    cleanup_solution_standins();

    SolutionConfig cfg;
    auto* va = cfg.mutable_voice_agent();
    va->set_llm_model_id("qwen3-4b");
    va->set_stt_model_id("whisper");
    va->set_tts_model_id("kokoro");
    va->set_vad_model_id("silero");

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    CHECK(last_error_detail_contains("detect_voice"));
    CHECK(last_error_detail_contains("explicit stand-in factory"));
}

// ---------------------------------------------------------------------------
// 6. SolutionConfig (RAG) exposes missing real operator factories.
// ---------------------------------------------------------------------------
TEST(rag_solution_without_real_factories_is_unavailable) {
    cleanup_solution_standins();

    SolutionConfig cfg;
    auto* rag = cfg.mutable_rag();
    rag->set_embed_model_id("bge-small");
    rag->set_llm_model_id("qwen3-4b");
    rag->set_retrieve_k(12);

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    // RAG solution graph now expands to: query(source) → retrieve →
    // context_build → llm(generate_text). `retrieve` and `context_build` are
    // built-in stand-ins (so they have factories), `generate_text` is the
    // first engine-backed operator with no real or stand-in factory after
    // cleanup_solution_standins(), so it surfaces the FEATURE_NOT_AVAILABLE
    // diagnostic.
    CHECK(last_error_detail_contains("generate_text"));
    CHECK(last_error_detail_contains("explicit stand-in factory"));
}

// ---------------------------------------------------------------------------
// 7. SolutionConfig (TimeSeries) reaches anomaly_detect after built-in window.
// ---------------------------------------------------------------------------
TEST(time_series_solution_without_anomaly_factory_reaches_anomaly_detect) {
    cleanup_solution_standins();

    SolutionConfig cfg;
    auto* ts = cfg.mutable_time_series();
    ts->set_anomaly_model_id("isolation-forest");
    ts->set_llm_model_id("qwen3-4b");
    ts->set_window_size(3);
    ts->set_stride(1);

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    CHECK(last_error_detail_contains("anomaly_detect"));
    CHECK(last_error_detail_contains("explicit stand-in factory"));
    CHECK(!last_error_detail_contains("window"));
}

// ---------------------------------------------------------------------------
// 8. SolutionConfig (TimeSeries) compiles/runs without a window stand-in.
// ---------------------------------------------------------------------------
TEST(time_series_solution_compiles_with_builtin_window) {
    ScopedTimeSeriesStandins standins;

    SolutionConfig cfg;
    auto* ts = cfg.mutable_time_series();
    ts->set_anomaly_model_id("isolation-forest");
    ts->set_llm_model_id("qwen3-4b");
    ts->set_window_size(2);
    ts->set_stride(1);

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_SUCCESS);
    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 5);
    CHECK(spec.edges_size() == 4);
    CHECK(runner.feed(Item::text("1")) == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("2")) == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("3")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 8.1. Portable RAG prompt assembly has a real built-in context_build op.
// ---------------------------------------------------------------------------
TEST(context_build_builtin_applies_prompt_template) {
    auto captured = std::make_shared<std::string>();
    ScopedFactory capture(
        "cpp_solution_context_capture_sink",
        [captured](const OperatorSpec& spec) {
            return std::make_shared<TextCaptureSinkNode>(spec.name(), captured);
        },
        make_text_schema({"in"}, {}));

    PipelineSpec spec;
    spec.set_name("context_build_builtin");
    auto* src = spec.add_operators();
    src->set_name("src");
    src->set_type("source");
    auto* ctx = spec.add_operators();
    ctx->set_name("context");
    ctx->set_type("context_build");
    (*ctx->mutable_params())["prompt_template"] = "Context:\n{context}\nQuestion:{question}";
    auto* snk = spec.add_operators();
    snk->set_name("sink");
    snk->set_type("cpp_solution_context_capture_sink");
    auto* e1 = spec.add_edges();
    e1->set_from("src.out");
    e1->set_to("context.in");
    auto* e2 = spec.add_edges();
    e2->set_from("context.out");
    e2->set_to("sink.in");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("retrieved chunk")) == RAC_SUCCESS);
    runner.close_input();
    runner.wait();

    CHECK(*captured == "Context:\nretrieved chunk\nQuestion:retrieved chunk");
}

// ---------------------------------------------------------------------------
// 9. SolutionConfig (VoiceAgent) expands + compiles with explicit stand-ins.
// ---------------------------------------------------------------------------
TEST(voice_agent_solution_compiles) {
    ScopedSolutionStandins standins;

    SolutionConfig cfg;
    auto* va = cfg.mutable_voice_agent();
    va->set_llm_model_id("qwen3-4b");
    va->set_stt_model_id("whisper");
    va->set_tts_model_id("kokoro");
    va->set_vad_model_id("silero");

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_SUCCESS);
    // Confirm the expanded spec has the expected topology.
    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 4);
    CHECK(spec.edges_size() == 3);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 10. SolutionConfig (RAG) expands + compiles with explicit stand-ins.
//     Topology: query (source) → retrieve → context → llm. The retrieve
//     operator owns the embedding lookup via the host-supplied RAG
//     session handle, so the L5 graph carries 4 operators + 3 edges.
// ---------------------------------------------------------------------------
TEST(rag_solution_compiles) {
    ScopedSolutionStandins standins;

    SolutionConfig cfg;
    auto* rag = cfg.mutable_rag();
    rag->set_embed_model_id("bge-small");
    rag->set_llm_model_id("qwen3-4b");
    rag->set_retrieve_k(12);

    SolutionRunner runner(cfg);
    CHECK(runner.start() == RAC_SUCCESS);
    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 4);
    CHECK(spec.edges_size() == 3);
    runner.close_input();
    runner.wait();
}

// ---------------------------------------------------------------------------
// 11. C ABI end-to-end: proto-bytes path.
// ---------------------------------------------------------------------------
TEST(c_abi_proto_bytes_lifecycle) {
    ScopedSolutionStandins standins;

    SolutionConfig cfg;
    auto* rag = cfg.mutable_rag();
    rag->set_embed_model_id("bge-small");
    rag->set_llm_model_id("qwen3-4b");
    rag->set_retrieve_k(8);

    std::string buf;
    CHECK(cfg.SerializeToString(&buf));

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_proto(buf.data(), buf.size(), &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(h != nullptr);

    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    CHECK(rac_solution_feed(h, "why is the sky blue?") == RAC_SUCCESS);
    CHECK(rac_solution_close_input(h) == RAC_SUCCESS);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 12. C ABI end-to-end: YAML path (SolutionConfig shape).
// ---------------------------------------------------------------------------
TEST(c_abi_yaml_solution_lifecycle) {
    ScopedSolutionStandins standins;

    const char* yaml =
        "voice_agent:\n"
        "  llm_model_id: \"qwen3-4b\"\n"
        "  stt_model_id: \"whisper\"\n"
        "  tts_model_id: \"kokoro\"\n"
        "  vad_model_id: \"silero\"\n"
        "  sample_rate_hz: 16000\n";

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_yaml(yaml, &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(h != nullptr);

    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    rac_solution_cancel(h);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 13. C ABI YAML path — raw PipelineSpec shape (top-level `operators`).
// ---------------------------------------------------------------------------
TEST(c_abi_yaml_pipeline_lifecycle) {
    const char* yaml =
        "name: \"inline\"\n"
        "operators:\n"
        "  - name: \"src\"\n"
        "    type: \"source\"\n"
        "  - name: \"snk\"\n"
        "    type: \"sink\"\n"
        "edges:\n"
        "  - from: \"src.out\"\n"
        "    to: \"snk.in\"\n";

    rac_solution_handle_t h = nullptr;
    rac_result_t st = rac_solution_create_from_yaml(yaml, &h);
    CHECK(st == RAC_SUCCESS);
    CHECK(rac_solution_start(h) == RAC_SUCCESS);
    CHECK(rac_solution_feed(h, "tick") == RAC_SUCCESS);
    CHECK(rac_solution_close_input(h) == RAC_SUCCESS);
    rac_solution_destroy(h);
}

// ---------------------------------------------------------------------------
// 13.5. Engine-backed retrieve operator: verifies the schema contract
//       (text.utf8 in → text.utf8 out on port "results") and the
//       honest-failure path when the host did not stamp `session_handle_id`
//       into OperatorSpec.params. The operator must refuse to run rather
//       than silently emit mock context.
// ---------------------------------------------------------------------------
TEST(retrieve_without_session_handle_fails_honestly) {
    using rac::solutions::OperatorRegistry;

    auto& registry = OperatorRegistry::instance();
    // Snapshot the current `retrieve` factory (the built-in tagged stand-in)
    // so the test does not bleed real engine-backed wiring into siblings.
    const bool had_retrieve_before = registry.has_factory("retrieve");
    CHECK(had_retrieve_before);  // Built-in stand-in is always present.

    const std::size_t registered = rac::solutions::register_engine_backed_operators(registry);
    // generate_text + transcribe + synthesize + detect_voice + embed +
    // retrieve = 6 factories.
    CHECK(registered == 6);

    // Schema contract: text.utf8 in → text.utf8 out, output port "results".
    const auto& in_ports = registry.input_ports("retrieve");
    const auto& out_ports = registry.output_ports("retrieve");
    CHECK(in_ports.size() == 1);
    CHECK(in_ports[0] == "in");
    CHECK(out_ports.size() == 1);
    CHECK(out_ports[0] == "results");
    CHECK(registry.input_port_type("retrieve", "in") == rac::solutions::kPayloadTextUtf8);
    CHECK(registry.output_port_type("retrieve", "results") == rac::solutions::kPayloadTextUtf8);

    // Build a pipeline that drives retrieve without a session handle. The
    // operator must cancel on the first input — never silently produce a
    // mock answer.
    PipelineSpec spec;
    spec.set_name("retrieve_missing_handle");
    auto* src = spec.add_operators();
    src->set_name("query");
    src->set_type("source");
    auto* retrieve = spec.add_operators();
    retrieve->set_name("retrieve");
    retrieve->set_type("retrieve");
    auto* sink = spec.add_operators();
    sink->set_name("ctx");
    sink->set_type("sink");
    auto* e1 = spec.add_edges();
    e1->set_from("query.out");
    e1->set_to("retrieve.in");
    auto* e2 = spec.add_edges();
    e2->set_from("retrieve.results");
    e2->set_to("ctx.in");

    SolutionRunner runner(spec);
    CHECK(runner.start() == RAC_SUCCESS);
    CHECK(runner.feed(Item::text("why is the sky blue?")) == RAC_SUCCESS);
    runner.wait();
    const char* details = rac_error_get_details();
    CHECK(details != nullptr);
    CHECK(std::string(details).find("session_handle_id") != std::string::npos);

    // Restore the built-in stand-in factory so subsequent tests are not
    // affected by the engine-backed override.
    registry.unregister_factory("retrieve");
    rac::solutions::register_builtin_operators(registry);
}

// ---------------------------------------------------------------------------
// 14. Null / invalid handle paths.
// ---------------------------------------------------------------------------
TEST(null_handle_paths) {
    CHECK(rac_solution_start(nullptr) == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_stop(nullptr) == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_cancel(nullptr) == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_feed(nullptr, "x") == RAC_ERROR_INVALID_HANDLE);
    CHECK(rac_solution_close_input(nullptr) == RAC_ERROR_INVALID_HANDLE);
    rac_solution_destroy(nullptr);  // no-op; must not crash

    rac_solution_handle_t h = nullptr;
    CHECK(rac_solution_create_from_yaml(nullptr, &h) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(rac_solution_create_from_proto(nullptr, 10, &h) == RAC_ERROR_INVALID_ARGUMENT);
}

}  // namespace

int main() {
    run_test_start_feed_close_lifecycle();
    run_test_double_start_is_rejected();
    run_test_cancel_mid_stream_joins();
    run_test_feed_before_start_fails();
    run_test_feed_payload_type_mismatch_is_rejected();
    run_test_feed_image_payload_body_contract_is_enforced();
    run_test_feed_text_payload_requires_text_body();
    run_test_feed_embedding_payload_body_contract_is_enforced();
    run_test_feed_terminal_control_payload_body_contract_is_enforced();
    run_test_feed_event_payload_body_contracts_are_enforced();
    run_test_operator_emitted_text_type_with_raw_bytes_body_is_rejected();
    run_test_operator_emitted_audio_type_with_raw_bytes_body_is_rejected();
    run_test_operator_emitted_image_type_with_raw_bytes_body_is_rejected();
    run_test_operator_emitted_embedding_type_with_raw_bytes_body_is_rejected();
    run_test_operator_emitted_sdk_event_type_with_raw_bytes_body_is_rejected();
    run_test_voice_agent_solution_without_real_factories_is_unavailable();
    run_test_rag_solution_without_real_factories_is_unavailable();
    run_test_time_series_solution_without_anomaly_factory_reaches_anomaly_detect();
    run_test_time_series_solution_compiles_with_builtin_window();
    run_test_context_build_builtin_applies_prompt_template();
    run_test_voice_agent_solution_compiles();
    run_test_rag_solution_compiles();
    run_test_c_abi_proto_bytes_lifecycle();
    run_test_c_abi_yaml_solution_lifecycle();
    run_test_c_abi_yaml_pipeline_lifecycle();
    run_test_retrieve_without_session_handle_fails_honestly();
    run_test_null_handle_paths();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
