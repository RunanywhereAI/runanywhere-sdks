// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/operator_registry.hpp — T4.7 pluggable operator table.
//
// The PipelineExecutor walks a `PipelineSpec` and asks the registry to
// materialize a concrete pipeline node for every `OperatorSpec`. Each
// operator type (e.g. "transcribe", "generate_text", "embed", "source",
// "sink", "echo") is represented by a factory registered by string name
// and a small port schema used by PipelineExecutor validation.
//
// Keeping operator construction behind this interface means:
//   * The scheduler-build logic is independent of specific engines; the
//     executor works the moment at least one factory is registered for
//     every type appearing in the spec.
//   * Downstream SDKs can inject real VAD/STT/LLM/TTS nodes by plugging
//     their factories in at startup; tests register light-weight echo /
//     source / sink stubs with zero engine dependencies.
//   * The registry ships with a small set of built-in neutral operators
//     ("source", "sink", "echo") so unit tests and examples run out of
//     the box. Engine-backed primitives must register explicit factories
//     before a PipelineSpec that uses them can compile.
//
// Thread-safety: factory (de)registration happens at static-init time or
// from the configuring thread before PipelineExecutor::build() runs.
// Concurrent mutation during build is not supported.
//
// SOLID:
//   * Open/closed: new operator types plug in via register_factory.
//   * Dependency inversion: executor depends on this abstraction, never
//     on concrete STT/LLM/TTS vtables.

#pragma once

#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "rac/graph/pipeline_node.hpp"

// Forward-declare proto types to keep protobuf an implementation
// detail (see CMakeLists.txt: protobuf::libprotobuf is PRIVATE).
namespace runanywhere::v1 {
class OperatorSpec;
}  // namespace runanywhere::v1

namespace rac::solutions {

inline constexpr const char* kPayloadTextUtf8 = "text.utf8";
inline constexpr const char* kPayloadAudioPcmS16Le = "audio.pcm_s16le";
inline constexpr const char* kPayloadImagePng = "image/png";
inline constexpr const char* kPayloadImageJpeg = "image/jpeg";
inline constexpr const char* kPayloadImageWebp = "image/webp";
inline constexpr const char* kPayloadImageRawRgb = "image/raw-rgb";
inline constexpr const char* kPayloadImageRawRgba = "image/raw-rgba";
inline constexpr const char* kPayloadEmbeddingVectorFloat32 = "embedding.vector.float32";
inline constexpr const char* kPayloadControlTerminal = "control.terminal";
inline constexpr const char* kPayloadControlCancellation = "control.cancel";
inline constexpr const char* kPayloadControlError = "control.error";
inline constexpr const char* kPayloadSdkEvent = "sdk.event";
inline constexpr const char* kPayloadVoiceEvent = "voice.event";
inline constexpr const char* kPayloadBodyRawBytes = "bytes.raw";
inline constexpr const char* kPayloadBodyImageBytes = "image.bytes";
inline constexpr const char* kPayloadBodyEmbeddingVector = "embedding.vector";
inline constexpr const char* kPayloadBodyControlSignal = "control.signal";
inline constexpr const char* kPayloadBodySdkEventProto = "proto.runanywhere.v1.SDKEvent";
inline constexpr const char* kPayloadBodyVoiceEventProto = "proto.runanywhere.v1.VoiceEvent";
inline constexpr const char* kPayloadEmbeddingElementFloat32 = "float32";

enum class PayloadBodyKind {
    Invalid,
    RawBytes,
    TextUtf8,
    AudioPcmS16Le,
    ImageBytes,
    EmbeddingVector,
    ControlSignal,
    SdkEventProto,
    VoiceEventProto,
};

enum class PayloadControlSignalKind {
    Invalid,
    Terminal,
    Cancellation,
    Error,
};

struct EmbeddingVectorBody {
    std::string element_type_id{kPayloadEmbeddingElementFloat32};
    std::size_t element_count{0};
    std::vector<float> values{};
};

struct ControlSignalBody {
    PayloadControlSignalKind kind{PayloadControlSignalKind::Invalid};
    int status_code{0};
    std::string reason{};
};

/// Portable edge payload used by the solution executor.
///
/// The graph runtime still moves a single C++ item type so split/merge and
/// scheduler plumbing stay simple, but the item is no longer an unlabelled
/// string. Each item carries a concrete payload type ID and a concrete body
/// kind. Text payloads must use the `text.utf8` body helper, PCM S16LE
/// audio payloads must use the `audio.pcm_s16le` body helper, and image
/// media payloads must use the `image.bytes` body helper. Embedding vectors
/// must use the `embedding.vector` body helper with explicit float32 element
/// metadata. Terminal/control payloads use a typed control signal body, and
/// SDK/voice event payloads carry serialized generated proto messages under
/// explicit proto body IDs rather than raw bytes. Raw bytes remain only a
/// fallback for payload types that do not yet have typed body contracts.
struct Payload {
    std::string type_id;
    std::string bytes;
    EmbeddingVectorBody embedding_vector_body{};
    ControlSignalBody control_signal_body{};
    PayloadBodyKind body_kind{PayloadBodyKind::Invalid};

    Payload() = default;
    Payload(std::string payload_type, std::string payload_bytes)
        : Payload(std::move(payload_type), std::move(payload_bytes), PayloadBodyKind::RawBytes) {}

    static Payload text(std::string value, std::string payload_type = kPayloadTextUtf8);
    static Payload audio_pcm_s16le(std::string payload_bytes,
                                   std::string payload_type = kPayloadAudioPcmS16Le);
    static Payload image_bytes(std::string payload_bytes,
                               std::string payload_type = kPayloadImagePng);
    static Payload embedding_vector(std::vector<float> values,
                                    std::string payload_type = kPayloadEmbeddingVectorFloat32);
    static Payload control_signal(PayloadControlSignalKind kind, std::string reason = {},
                                  int status_code = 0, std::string payload_type = {});
    static Payload terminal_control(std::string reason = {}, int status_code = 0,
                                    std::string payload_type = kPayloadControlTerminal);
    static Payload sdk_event_proto(std::string serialized_event,
                                   std::string payload_type = kPayloadSdkEvent);
    static Payload voice_event_proto(std::string serialized_event,
                                     std::string payload_type = kPayloadVoiceEvent);
    static Payload typed_bytes(std::string payload_type, std::string payload_bytes);

    const std::string& text() const noexcept { return bytes; }
    const std::vector<float>& embedding_values() const noexcept {
        return embedding_vector_body.values;
    }
    const ControlSignalBody& control_signal() const noexcept { return control_signal_body; }
    std::string& mutable_bytes() noexcept { return bytes; }
    std::vector<float>& mutable_embedding_values() noexcept { return embedding_vector_body.values; }
    std::size_t size() const noexcept;
    const char* body_type_id() const noexcept;
    bool is_text() const noexcept { return body_kind == PayloadBodyKind::TextUtf8; }
    bool is_audio_pcm_s16le() const noexcept { return body_kind == PayloadBodyKind::AudioPcmS16Le; }
    bool is_image_bytes() const noexcept { return body_kind == PayloadBodyKind::ImageBytes; }
    bool is_embedding_vector() const noexcept {
        return body_kind == PayloadBodyKind::EmbeddingVector;
    }
    bool is_control_signal() const noexcept { return body_kind == PayloadBodyKind::ControlSignal; }
    bool is_sdk_event_proto() const noexcept { return body_kind == PayloadBodyKind::SdkEventProto; }
    bool is_voice_event_proto() const noexcept {
        return body_kind == PayloadBodyKind::VoiceEventProto;
    }
    bool validate_body_contract(std::string* err = nullptr) const;

   private:
    Payload(std::string payload_type, std::string payload_bytes, PayloadBodyKind kind)
        : type_id(std::move(payload_type)), bytes(std::move(payload_bytes)), body_kind(kind) {}
    Payload(std::string payload_type, EmbeddingVectorBody body)
        : type_id(std::move(payload_type)),
          embedding_vector_body(std::move(body)),
          body_kind(PayloadBodyKind::EmbeddingVector) {}
    Payload(std::string payload_type, ControlSignalBody body)
        : type_id(std::move(payload_type)),
          control_signal_body(std::move(body)),
          body_kind(PayloadBodyKind::ControlSignal) {}
};

using Item = Payload;

using OperatorEdge = rac::graph::StreamEdge<Item>;
using OperatorNode = rac::graph::PipelineNode<Item, Item>;

/// Factory signature — called once per OperatorSpec. The factory owns
/// interpretation of `spec.params()` and `spec.model_id()` and returns
/// a fully constructed (but not yet started) pipeline node.
using OperatorFactory =
    std::function<std::shared_ptr<OperatorNode>(const runanywhere::v1::OperatorSpec& spec)>;

/// Named-port adapter consumed by PipelineExecutor. Multi-port operators
/// implement this interface directly so each EdgeSpec endpoint can bind to
/// an independent input/output edge. Single-input/single-output
/// OperatorFactory registrations are wrapped in a single-port adapter.
class OperatorAdapter : public rac::graph::IPipelineNode {
   public:
    ~OperatorAdapter() override = default;

    virtual std::shared_ptr<OperatorEdge> input(const std::string& port) const noexcept = 0;
    virtual std::shared_ptr<OperatorEdge> output(const std::string& port) const noexcept = 0;
    virtual bool set_input(const std::string& port,
                           std::shared_ptr<OperatorEdge> edge) noexcept = 0;
    virtual bool set_output(const std::string& port,
                            std::shared_ptr<OperatorEdge> edge) noexcept = 0;
};

using OperatorAdapterFactory =
    std::function<std::shared_ptr<OperatorAdapter>(const runanywhere::v1::OperatorSpec& spec)>;

/// Declares the named input/output ports accepted by an operator type.
/// The executor validates EdgeSpec endpoints against this schema before
/// constructing nodes. The default register_factory overload uses an
/// explicit conventional single input "in" and single output "out"
/// `text.utf8` shape. Custom schemas must provide concrete payload metadata
/// for every declared port; the executor rejects empty/missing metadata and
/// legacy "opaque.bytes" metadata.
struct OperatorPortSchema {
    std::vector<std::string> input_ports{};
    std::vector<std::string> output_ports{};
    std::unordered_map<std::string, std::string> input_port_types{};
    std::unordered_map<std::string, std::string> output_port_types{};
};

/// Process-wide operator factory table.
class OperatorRegistry {
   public:
    static OperatorRegistry& instance();

    /// Register / replace the factory for an operator type. Returns
    /// true on first registration, false on replacement (mirrors
    /// std::unordered_map::insert_or_assign semantics and is surfaced
    /// so callers can detect duplicate-registration bugs in tests).
    bool register_factory(const std::string& type, OperatorFactory factory);
    bool register_factory(const std::string& type, OperatorFactory factory,
                          OperatorPortSchema ports);
    bool register_adapter_factory(const std::string& type, OperatorAdapterFactory factory,
                                  OperatorPortSchema ports);

    /// Remove a factory. No-op if absent. Used by tests to reset state
    /// between scenarios.
    void unregister_factory(const std::string& type) noexcept;

    /// Build a node for `spec` using the factory registered for
    /// `spec.type()`. Returns nullptr when no factory is registered;
    /// the executor maps that to either invalid configuration or feature
    /// unavailable depending on whether the type is one of the known
    /// engine-backed solution primitives.
    std::shared_ptr<OperatorNode> create(const runanywhere::v1::OperatorSpec& spec) const;
    std::shared_ptr<OperatorAdapter>
    create_adapter(const runanywhere::v1::OperatorSpec& spec) const;

    bool has_factory(const std::string& type) const noexcept;
    bool has_input_port(const std::string& type, const std::string& port) const noexcept;
    bool has_output_port(const std::string& type, const std::string& port) const noexcept;
    const std::vector<std::string>& input_ports(const std::string& type) const noexcept;
    const std::vector<std::string>& output_ports(const std::string& type) const noexcept;
    const std::string& input_port_type(const std::string& type,
                                       const std::string& port) const noexcept;
    const std::string& output_port_type(const std::string& type,
                                        const std::string& port) const noexcept;

    /// Wipe every factory. Intended for tests only.
    void clear() noexcept;

    OperatorRegistry(const OperatorRegistry&) = delete;
    OperatorRegistry& operator=(const OperatorRegistry&) = delete;

   private:
    OperatorRegistry();

    std::unordered_map<std::string, OperatorFactory> factories_;
    std::unordered_map<std::string, OperatorAdapterFactory> adapter_factories_;
    std::unordered_map<std::string, OperatorPortSchema> port_schemas_;
};

/// Convenience: register the set of always-available neutral
/// operators ("echo", "source", "sink"). Called from
/// OperatorRegistry::instance() on first access — callers rarely need
/// to invoke this directly, but tests use it after clear() to restore
/// a known baseline.
void register_builtin_operators(OperatorRegistry& registry);

/// Register the engine-backed primitive operator factories — one per
/// `RAC_PRIMITIVE_*` value reachable from `SolutionConfig`:
///
///   "generate_text" — dispatches into rac_llm_generate_proto, emits the
///                     final response text on port "token".
///   "transcribe"    — dispatches into rac_stt_transcribe_lifecycle_proto,
///                     emits the final transcript text on port "final".
///   "synthesize"    — dispatches into rac_tts_synthesize_lifecycle_proto,
///                     emits PCM S16 LE audio on port "out".
///   "detect_voice"  — dispatches into rac_vad_process_lifecycle_proto and
///                     forwards the input audio frame on port "out" only
///                     when speech is detected (MVP gate).
///   "embed"         — dispatches into rac_embeddings_embed_batch_lifecycle_proto,
///                     emits an embedding vector on port "vec".
///   "retrieve"      — currently a stub: returns RAC_ERROR_NOT_IMPLEMENTED at
///                     run time because RAG retrieval requires a configured
///                     RAG session that the portable lifecycle ABI does not yet
///                     provide. The operator factory still registers so a
///                     pipeline that uses it compiles, but at runtime the
///                     stub propagates the error and the SolutionRunner
///                     cancels honestly.
///
/// This function is intentionally NOT called from
/// `OperatorRegistry::instance()`; SDKs (Swift / Kotlin / Web / etc.) call
/// it after backend registration so that a pipeline referencing one of the
/// engine-backed types fails with `RAC_ERROR_FEATURE_NOT_AVAILABLE` when the
/// host has not opted in.
///
/// Returns the number of factories registered (between 0 and 6 depending
/// on which proto APIs are linked in this build).
std::size_t register_engine_backed_operators(OperatorRegistry& registry);

/// Cross-thread error-detail capture for solution operator failures.
///
/// `rac_error_set_details` writes to a thread_local buffer. Operators run
/// inside scheduler worker threads, so an error they record there is
/// invisible to the host thread that issued `SolutionRunner::feed`/`wait`.
/// These helpers stash the most recent operator detail in a process-wide
/// mutex-guarded map indexed by writer std::thread::id, so concurrent
/// operator threads no longer race on a single string slot.
/// SolutionRunner::wait() drains the map and promotes the longest
/// observed detail into the calling thread's `rac_error_set_details` so
/// the C ABI `rac_error_get_details()` returns the honest cause of the
/// cancel/failure.
///
/// Thread-safe; safe to call from any operator thread.
///
/// Caveat: cross-runner attribution is not enforced — if a host runs
/// multiple SolutionRunners concurrently, consume() returns whatever
/// detail any worker thread wrote since the last drain. Hosts that
/// require strict per-runner attribution should capture failures inside
/// the operator itself rather than via this slot.
void record_operator_error_detail(const std::string& detail);

/// Drain and return the most informative pending operator error detail
/// (the longest non-empty string across all writer-thread slots; empty
/// string if no operator has written since the last drain).
std::string consume_operator_error_detail();

}  // namespace rac::solutions
