// SPDX-License-Identifier: Apache-2.0
//
// operator_registry.cpp — T4.7 factory table + built-in neutral ops.

#include "rac/solutions/operator_registry.hpp"

#include "pipeline.pb.h"
#include "sdk_events.pb.h"
#include "voice_events.pb.h"

#include <charconv>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <system_error>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

#include "rac/graph/pipeline_node.hpp"

namespace rac::solutions {

namespace {

using rac::graph::OverflowPolicy;
using rac::graph::PipelineNode;

const std::string& default_payload_type() {
    static const std::string kType = kPayloadTextUtf8;
    return kType;
}

bool is_valid_utf8(const std::string& value) {
    std::uint32_t remaining = 0;
    std::uint32_t min_codepoint = 0;
    std::uint32_t codepoint = 0;

    for (unsigned char c : value) {
        if (remaining == 0) {
            if ((c & 0x80u) == 0) {
                continue;
            }
            if ((c & 0xE0u) == 0xC0u) {
                remaining = 1;
                min_codepoint = 0x80u;
                codepoint = c & 0x1Fu;
            } else if ((c & 0xF0u) == 0xE0u) {
                remaining = 2;
                min_codepoint = 0x800u;
                codepoint = c & 0x0Fu;
            } else if ((c & 0xF8u) == 0xF0u) {
                remaining = 3;
                min_codepoint = 0x10000u;
                codepoint = c & 0x07u;
            } else {
                return false;
            }
            continue;
        }

        if ((c & 0xC0u) != 0x80u)
            return false;
        codepoint = (codepoint << 6u) | (c & 0x3Fu);
        --remaining;
        if (remaining == 0) {
            if (codepoint < min_codepoint)
                return false;
            if (codepoint > 0x10FFFFu)
                return false;
            if (codepoint >= 0xD800u && codepoint <= 0xDFFFu)
                return false;
        }
    }

    return remaining == 0;
}

bool is_image_bytes_payload_type(const std::string& type_id) {
    return type_id == kPayloadImagePng || type_id == kPayloadImageJpeg ||
           type_id == kPayloadImageWebp || type_id == kPayloadImageRawRgb ||
           type_id == kPayloadImageRawRgba;
}

bool is_embedding_vector_payload_type(const std::string& type_id) {
    return type_id == kPayloadEmbeddingVectorFloat32;
}

bool is_control_signal_payload_type(const std::string& type_id) {
    return type_id == kPayloadControlTerminal || type_id == kPayloadControlCancellation ||
           type_id == kPayloadControlError;
}

const char* control_payload_type_for(PayloadControlSignalKind kind) {
    switch (kind) {
        case PayloadControlSignalKind::Terminal:
            return kPayloadControlTerminal;
        case PayloadControlSignalKind::Cancellation:
            return kPayloadControlCancellation;
        case PayloadControlSignalKind::Error:
            return kPayloadControlError;
        case PayloadControlSignalKind::Invalid:
        default:
            return "";
    }
}

bool is_typed_event_payload_type(const std::string& type_id) {
    return type_id == kPayloadSdkEvent || type_id == kPayloadVoiceEvent;
}

bool has_prefix(const std::string& value, const unsigned char* expected,
                std::size_t expected_size) {
    if (value.size() < expected_size)
        return false;
    for (std::size_t i = 0; i < expected_size; ++i) {
        if (static_cast<unsigned char>(value[i]) != expected[i])
            return false;
    }
    return true;
}

bool has_ascii_at(const std::string& value, std::size_t offset, const char* expected,
                  std::size_t expected_size) {
    if (value.size() < offset + expected_size)
        return false;
    for (std::size_t i = 0; i < expected_size; ++i) {
        if (value[offset + i] != expected[i])
            return false;
    }
    return true;
}

bool has_png_signature(const std::string& value) {
    const unsigned char kSignature[] = {
        0x89u, 'P', 'N', 'G', 0x0Du, 0x0Au, 0x1Au, 0x0Au,
    };
    return has_prefix(value, kSignature, sizeof(kSignature));
}

bool has_jpeg_signature(const std::string& value) {
    return value.size() >= 4 && static_cast<unsigned char>(value[0]) == 0xFFu &&
           static_cast<unsigned char>(value[1]) == 0xD8u &&
           static_cast<unsigned char>(value[value.size() - 2]) == 0xFFu &&
           static_cast<unsigned char>(value[value.size() - 1]) == 0xD9u;
}

bool has_webp_signature(const std::string& value) {
    return value.size() >= 12 && has_ascii_at(value, 0, "RIFF", 4) &&
           has_ascii_at(value, 8, "WEBP", 4);
}

bool replace_all(std::string& value, const std::string& needle, const std::string& replacement) {
    if (needle.empty())
        return false;

    bool replaced = false;
    std::size_t pos = 0;
    while ((pos = value.find(needle, pos)) != std::string::npos) {
        value.replace(pos, needle.size(), replacement);
        pos += replacement.size();
        replaced = true;
    }
    return replaced;
}

// Built-in operator nodes. These handle the "glue" topology that every
// non-trivial pipeline needs — a source to inject items, a sink to
// silently drain them, and an echo that forwards whatever it receives.
// Real engines register richer operators ("transcribe", "generate_text",
// …) explicitly before specs using them can compile.

class EchoNode final : public OperatorNode {
   public:
    explicit EchoNode(std::string name)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        // Identity forward. StreamEdge::push returns false on cancel;
        // we honour that by short-circuiting the loop upstream via the
        // cancel token wired into the node base class.
        out.push(std::move(item), this->cancel_token());
    }
};

class WindowNode final : public OperatorNode {
   public:
    WindowNode(std::string name, std::size_t size, std::size_t stride)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          size_(size),
          stride_(stride) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        if (skip_remaining_ > 0) {
            --skip_remaining_;
            return;
        }

        buffer_.push_back(std::move(item));
        if (buffer_.size() < size_)
            return;

        // The portable window payload is the text form joined with '\n'.
        if (!out.push(Item::text(join_window()), this->cancel_token())) {
            return;
        }
        advance_window();
    }

   private:
    std::string join_window() const {
        std::size_t bytes = size_ > 0 ? size_ - 1 : 0;
        for (std::size_t i = 0; i < size_; ++i) {
            bytes += buffer_[i].text().size();
        }

        std::string joined;
        joined.reserve(bytes);
        for (std::size_t i = 0; i < size_; ++i) {
            if (i > 0)
                joined.push_back('\n');
            joined.append(buffer_[i].text());
        }
        return joined;
    }

    void advance_window() {
        std::size_t remaining = stride_;
        while (remaining > 0 && !buffer_.empty()) {
            buffer_.pop_front();
            --remaining;
        }
        skip_remaining_ = remaining;
    }

    std::deque<Item> buffer_;
    std::size_t size_;
    std::size_t stride_;
    std::size_t skip_remaining_{0};
};

class ContextBuildNode final : public OperatorNode {
   public:
    ContextBuildNode(std::string name, std::string prompt_template)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          prompt_template_(std::move(prompt_template)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!out.push(Item::text(build_prompt(item.text())), this->cancel_token())) {
            return;
        }
    }

   private:
    std::string build_prompt(const std::string& input) const {
        if (prompt_template_.empty())
            return input;

        std::string prompt = prompt_template_;
        bool replaced = false;
        replaced |= replace_all(prompt, "{context}", input);
        replaced |= replace_all(prompt, "{input}", input);
        replaced |= replace_all(prompt, "{question}", input);
        if (replaced)
            return prompt;
        return prompt + "\n\n" + input;
    }

    std::string prompt_template_;
};

/// Terminal drain — pops, discards, never forwards.
class SinkNode final : public OperatorNode {
   public:
    explicit SinkNode(std::string name)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 1, OverflowPolicy::BlockProducer) {}

   protected:
    void process(Item /*item*/, OutputEdge& /*out*/) override {
        // Intentionally empty — the sink absorbs the item. We leave
        // the output edge in place (and it stays closed on drain) so
        // the scheduler's "every node has an output" invariant holds.
    }
};

OperatorFactory make_echo_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec) -> std::shared_ptr<OperatorNode> {
        return std::make_shared<EchoNode>(spec.name());
    };
}

OperatorFactory make_sink_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec) -> std::shared_ptr<OperatorNode> {
        return std::make_shared<SinkNode>(spec.name());
    };
}

int positive_int_param_or_default(const runanywhere::v1::OperatorSpec& spec, const char* key,
                                  int fallback) {
    auto it = spec.params().find(key);
    if (it == spec.params().end())
        return fallback;

    int value = fallback;
    const auto& text = it->second;
    const char* first = text.data();
    const char* last = first + text.size();
    auto [ptr, ec] = std::from_chars(first, last, value);
    if (ec != std::errc{} || ptr != last || value <= 0)
        return fallback;
    return value;
}

OperatorFactory make_window_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec) -> std::shared_ptr<OperatorNode> {
        const int size = positive_int_param_or_default(spec, "size", 1);
        const int stride = positive_int_param_or_default(spec, "stride", 1);
        return std::make_shared<WindowNode>(spec.name(), static_cast<std::size_t>(size),
                                            static_cast<std::size_t>(stride));
    };
}

OperatorFactory make_context_build_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec) -> std::shared_ptr<OperatorNode> {
        std::string prompt_template;
        auto it = spec.params().find("prompt_template");
        if (it != spec.params().end()) {
            prompt_template = it->second;
        }
        return std::make_shared<ContextBuildNode>(spec.name(), std::move(prompt_template));
    };
}

OperatorPortSchema make_schema(std::vector<std::string> inputs, std::vector<std::string> outputs) {
    OperatorPortSchema schema;
    schema.input_ports = std::move(inputs);
    schema.output_ports = std::move(outputs);
    for (const auto& port : schema.input_ports) {
        schema.input_port_types.emplace(port, default_payload_type());
    }
    for (const auto& port : schema.output_ports) {
        schema.output_port_types.emplace(port, default_payload_type());
    }
    return schema;
}

OperatorPortSchema default_schema() {
    return make_schema({"in"}, {"out"});
}

bool contains_port(const std::vector<std::string>& ports, const std::string& port) {
    for (const auto& candidate : ports) {
        if (candidate == port)
            return true;
    }
    return false;
}

const std::vector<std::string>& empty_ports() {
    static const std::vector<std::string> kEmpty;
    return kEmpty;
}

const std::string& empty_payload_type() {
    static const std::string kEmpty;
    return kEmpty;
}

const std::string&
payload_type_or_empty(const std::unordered_map<std::string, std::string>& port_types,
                      const std::string& port) {
    auto it = port_types.find(port);
    if (it == port_types.end() || it->second.empty())
        return empty_payload_type();
    return it->second;
}

class SinglePortOperatorAdapter final : public OperatorAdapter {
   public:
    SinglePortOperatorAdapter(std::shared_ptr<OperatorNode> node, OperatorPortSchema schema)
        : node_(std::move(node)),
          input_ports_(std::move(schema.input_ports)),
          output_ports_(std::move(schema.output_ports)) {}

    void start(std::shared_ptr<rac::graph::CancelToken> parent_cancel) override {
        node_->start(std::move(parent_cancel));
    }

    void stop() override { node_->stop(); }

    void join() override { node_->join(); }

    const char* name() const noexcept override { return node_->name(); }

    std::shared_ptr<OperatorEdge> input(const std::string& port) const noexcept override {
        if (!can_reference_input(port))
            return nullptr;
        return node_->input();
    }

    std::shared_ptr<OperatorEdge> output(const std::string& port) const noexcept override {
        if (!can_reference_output(port))
            return nullptr;
        return node_->output();
    }

    bool set_input(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        try {
            if (!can_bind_input(port))
                return false;
            if (bound_input_ && *bound_input_ != port)
                return false;
            bound_input_ = port;
            node_->set_input(std::move(edge));
            return true;
        } catch (...) {
            return false;
        }
    }

    bool set_output(const std::string& port, std::shared_ptr<OperatorEdge> edge) noexcept override {
        try {
            if (!can_bind_output(port))
                return false;
            if (bound_output_ && *bound_output_ != port)
                return false;
            bound_output_ = port;
            node_->set_output(std::move(edge));
            return true;
        } catch (...) {
            return false;
        }
    }

   private:
    bool can_bind_input(const std::string& port) const noexcept {
        if (input_ports_.empty())
            return false;
        return contains_port(input_ports_, port);
    }

    bool can_bind_output(const std::string& port) const noexcept {
        if (output_ports_.empty())
            return false;
        return contains_port(output_ports_, port);
    }

    bool can_reference_input(const std::string& port) const noexcept {
        return can_bind_input(port);
    }

    bool can_reference_output(const std::string& port) const noexcept {
        return can_bind_output(port);
    }

    std::shared_ptr<OperatorNode> node_;
    std::vector<std::string> input_ports_;
    std::vector<std::string> output_ports_;
    std::optional<std::string> bound_input_;
    std::optional<std::string> bound_output_;
};

// Source is identical to Echo at the operator level — the executor
// treats any operator reachable only via outbound edges as a root and
// wires the externally-accessible input edge to the first such node
// it sees.

}  // namespace

Payload Payload::text(std::string value, std::string payload_type) {
    return {std::move(payload_type), std::move(value), PayloadBodyKind::TextUtf8};
}

Payload Payload::audio_pcm_s16le(std::string payload_bytes, std::string payload_type) {
    return {std::move(payload_type), std::move(payload_bytes), PayloadBodyKind::AudioPcmS16Le};
}

Payload Payload::image_bytes(std::string payload_bytes, std::string payload_type) {
    return {std::move(payload_type), std::move(payload_bytes), PayloadBodyKind::ImageBytes};
}

Payload Payload::embedding_vector(std::vector<float> values, std::string payload_type) {
    EmbeddingVectorBody body;
    body.element_type_id = kPayloadEmbeddingElementFloat32;
    body.element_count = values.size();
    body.values = std::move(values);
    return {std::move(payload_type), std::move(body)};
}

Payload Payload::control_signal(PayloadControlSignalKind kind, std::string reason, int status_code,
                                std::string payload_type) {
    ControlSignalBody body;
    body.kind = kind;
    body.status_code = status_code;
    body.reason = std::move(reason);

    if (payload_type.empty()) {
        payload_type = control_payload_type_for(kind);
    }

    return {std::move(payload_type), std::move(body)};
}

Payload Payload::terminal_control(std::string reason, int status_code, std::string payload_type) {
    return control_signal(PayloadControlSignalKind::Terminal, std::move(reason), status_code,
                          std::move(payload_type));
}

Payload Payload::sdk_event_proto(std::string serialized_event, std::string payload_type) {
    return {std::move(payload_type), std::move(serialized_event), PayloadBodyKind::SdkEventProto};
}

Payload Payload::voice_event_proto(std::string serialized_event, std::string payload_type) {
    return {std::move(payload_type), std::move(serialized_event), PayloadBodyKind::VoiceEventProto};
}

Payload Payload::typed_bytes(std::string payload_type, std::string payload_bytes) {
    return {std::move(payload_type), std::move(payload_bytes), PayloadBodyKind::RawBytes};
}

std::size_t Payload::size() const noexcept {
    if (body_kind == PayloadBodyKind::EmbeddingVector) {
        return embedding_vector_body.values.size();
    }
    if (body_kind == PayloadBodyKind::ControlSignal) {
        return 1;
    }
    return bytes.size();
}

const char* Payload::body_type_id() const noexcept {
    switch (body_kind) {
        case PayloadBodyKind::TextUtf8:
            return kPayloadTextUtf8;
        case PayloadBodyKind::AudioPcmS16Le:
            return kPayloadAudioPcmS16Le;
        case PayloadBodyKind::ImageBytes:
            return kPayloadBodyImageBytes;
        case PayloadBodyKind::EmbeddingVector:
            return kPayloadBodyEmbeddingVector;
        case PayloadBodyKind::ControlSignal:
            return kPayloadBodyControlSignal;
        case PayloadBodyKind::SdkEventProto:
            return kPayloadBodySdkEventProto;
        case PayloadBodyKind::VoiceEventProto:
            return kPayloadBodyVoiceEventProto;
        case PayloadBodyKind::RawBytes:
            return kPayloadBodyRawBytes;
        case PayloadBodyKind::Invalid:
        default:
            return "<invalid>";
    }
}

bool Payload::validate_body_contract(std::string* err) const {
    auto fail = [&](std::string msg) {
        if (err)
            *err = std::move(msg);
        return false;
    };

    if (type_id.empty()) {
        return fail("payload type ID is empty");
    }

    switch (body_kind) {
        case PayloadBodyKind::TextUtf8:
            if (type_id != kPayloadTextUtf8) {
                return fail(
                    "payload body type 'text.utf8' does not match payload "
                    "type '" +
                    type_id + "'");
            }
            if (!is_valid_utf8(bytes)) {
                return fail("payload body type 'text.utf8' contains invalid UTF-8");
            }
            return true;
        case PayloadBodyKind::AudioPcmS16Le:
            if (type_id != kPayloadAudioPcmS16Le) {
                return fail(
                    "payload body type 'audio.pcm_s16le' does not match "
                    "payload type '" +
                    type_id + "'");
            }
            if ((bytes.size() % 2u) != 0u) {
                return fail(
                    "payload body type 'audio.pcm_s16le' contains a "
                    "partial 16-bit sample");
            }
            return true;
        case PayloadBodyKind::ImageBytes:
            if (!is_image_bytes_payload_type(type_id)) {
                return fail(
                    "payload body type 'image.bytes' does not match "
                    "payload type '" +
                    type_id + "'");
            }
            if (bytes.empty()) {
                return fail("payload body type 'image.bytes' is empty");
            }
            if (type_id == kPayloadImagePng && !has_png_signature(bytes)) {
                return fail(
                    "payload body type 'image.bytes' for 'image/png' "
                    "has invalid PNG signature");
            }
            if (type_id == kPayloadImageJpeg && !has_jpeg_signature(bytes)) {
                return fail(
                    "payload body type 'image.bytes' for 'image/jpeg' "
                    "has invalid JPEG signature");
            }
            if (type_id == kPayloadImageWebp && !has_webp_signature(bytes)) {
                return fail(
                    "payload body type 'image.bytes' for 'image/webp' "
                    "has invalid WEBP signature");
            }
            if (type_id == kPayloadImageRawRgb && (bytes.size() % 3u) != 0u) {
                return fail(
                    "payload body type 'image.bytes' for 'image/raw-rgb' "
                    "contains a partial RGB pixel");
            }
            if (type_id == kPayloadImageRawRgba && (bytes.size() % 4u) != 0u) {
                return fail(
                    "payload body type 'image.bytes' for "
                    "'image/raw-rgba' contains a partial RGBA pixel");
            }
            return true;
        case PayloadBodyKind::EmbeddingVector:
            if (!is_embedding_vector_payload_type(type_id)) {
                return fail(
                    "payload body type 'embedding.vector' does not match "
                    "payload type '" +
                    type_id + "'");
            }
            if (embedding_vector_body.element_type_id != kPayloadEmbeddingElementFloat32) {
                return fail(
                    "payload body type 'embedding.vector' has unsupported "
                    "element type '" +
                    embedding_vector_body.element_type_id + "'");
            }
            if (embedding_vector_body.values.empty()) {
                return fail("payload body type 'embedding.vector' is empty");
            }
            if (embedding_vector_body.element_count != embedding_vector_body.values.size()) {
                return fail(
                    "payload body type 'embedding.vector' has misaligned "
                    "element count: declares " +
                    std::to_string(embedding_vector_body.element_count) +
                    " float32 elements but contains " +
                    std::to_string(embedding_vector_body.values.size()));
            }
            return true;
        case PayloadBodyKind::ControlSignal: {
            if (!is_control_signal_payload_type(type_id)) {
                return fail(
                    "payload body type 'control.signal' does not match "
                    "payload type '" +
                    type_id + "'");
            }
            if (control_signal_body.kind == PayloadControlSignalKind::Invalid) {
                return fail(
                    "payload body type 'control.signal' has invalid "
                    "control kind");
            }
            const std::string expected_type = control_payload_type_for(control_signal_body.kind);
            if (type_id != expected_type) {
                return fail(
                    "payload body type 'control.signal' kind requires "
                    "payload type '" +
                    expected_type + "', got '" + type_id + "'");
            }
            return true;
        }
        case PayloadBodyKind::SdkEventProto: {
            if (type_id != kPayloadSdkEvent) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.SDKEvent' "
                    "does not match payload type '" +
                    type_id + "'");
            }
            if (bytes.empty()) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.SDKEvent' "
                    "is empty");
            }
            runanywhere::v1::SDKEvent event;
            if (!event.ParseFromString(bytes)) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.SDKEvent' "
                    "does not decode as SDKEvent");
            }
            if (event.event_case() == runanywhere::v1::SDKEvent::EVENT_NOT_SET) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.SDKEvent' "
                    "has no SDKEvent oneof payload");
            }
            return true;
        }
        case PayloadBodyKind::VoiceEventProto: {
            if (type_id != kPayloadVoiceEvent) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.VoiceEvent' "
                    "does not match payload type '" +
                    type_id + "'");
            }
            if (bytes.empty()) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.VoiceEvent' "
                    "is empty");
            }
            runanywhere::v1::VoiceEvent event;
            if (!event.ParseFromString(bytes)) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.VoiceEvent' "
                    "does not decode as VoiceEvent");
            }
            if (event.payload_case() == runanywhere::v1::VoiceEvent::PAYLOAD_NOT_SET) {
                return fail(
                    "payload body type 'proto.runanywhere.v1.VoiceEvent' "
                    "has no VoiceEvent payload");
            }
            return true;
        }
        case PayloadBodyKind::RawBytes:
            if (type_id == kPayloadTextUtf8) {
                return fail(
                    "payload type 'text.utf8' requires body type "
                    "'text.utf8', got 'bytes.raw'");
            }
            if (type_id == kPayloadAudioPcmS16Le) {
                return fail(
                    "payload type 'audio.pcm_s16le' requires body type "
                    "'audio.pcm_s16le', got 'bytes.raw'");
            }
            if (type_id == kPayloadBodyImageBytes || is_image_bytes_payload_type(type_id)) {
                return fail("payload type '" + type_id +
                            "' requires body type "
                            "'image.bytes', got 'bytes.raw'");
            }
            if (type_id == kPayloadBodyEmbeddingVector ||
                is_embedding_vector_payload_type(type_id)) {
                return fail("payload type '" + type_id +
                            "' requires body type "
                            "'embedding.vector', got 'bytes.raw'");
            }
            if (type_id == kPayloadBodyControlSignal || is_control_signal_payload_type(type_id)) {
                return fail("payload type '" + type_id +
                            "' requires body type "
                            "'control.signal', got 'bytes.raw'");
            }
            if (type_id == kPayloadBodySdkEventProto || type_id == kPayloadSdkEvent) {
                return fail("payload type '" + type_id +
                            "' requires body type "
                            "'proto.runanywhere.v1.SDKEvent', got 'bytes.raw'");
            }
            if (type_id == kPayloadBodyVoiceEventProto || type_id == kPayloadVoiceEvent) {
                return fail("payload type '" + type_id +
                            "' requires body type "
                            "'proto.runanywhere.v1.VoiceEvent', got 'bytes.raw'");
            }
            if (is_typed_event_payload_type(type_id)) {
                return fail("payload type '" + type_id +
                            "' requires a typed event proto body, got 'bytes.raw'");
            }
            return true;
        case PayloadBodyKind::Invalid:
        default:
            return fail("payload body type is unset for payload type '" + type_id + "'");
    }
}

OperatorRegistry& OperatorRegistry::instance() {
    // Meyers singleton — thread-safe in C++11+.
    static OperatorRegistry* s = [] {
        auto* inst = new OperatorRegistry();
        register_builtin_operators(*inst);
        return inst;
    }();
    return *s;
}

OperatorRegistry::OperatorRegistry() = default;

bool OperatorRegistry::register_factory(const std::string& type, OperatorFactory factory) {
    return register_factory(type, std::move(factory), default_schema());
}

bool OperatorRegistry::register_factory(const std::string& type, OperatorFactory factory,
                                        OperatorPortSchema ports) {
    auto [it, inserted] = factories_.insert_or_assign(type, std::move(factory));
    (void)it;
    adapter_factories_.erase(type);
    port_schemas_.insert_or_assign(type, std::move(ports));
    return inserted;
}

bool OperatorRegistry::register_adapter_factory(const std::string& type,
                                                OperatorAdapterFactory factory,
                                                OperatorPortSchema ports) {
    auto [it, inserted] = adapter_factories_.insert_or_assign(type, std::move(factory));
    (void)it;
    factories_.erase(type);
    port_schemas_.insert_or_assign(type, std::move(ports));
    return inserted;
}

void OperatorRegistry::unregister_factory(const std::string& type) noexcept {
    factories_.erase(type);
    adapter_factories_.erase(type);
    port_schemas_.erase(type);
}

std::shared_ptr<OperatorNode>
OperatorRegistry::create(const runanywhere::v1::OperatorSpec& spec) const {
    auto it = factories_.find(spec.type());
    if (it == factories_.end())
        return nullptr;
    return it->second(spec);
}

std::shared_ptr<OperatorAdapter>
OperatorRegistry::create_adapter(const runanywhere::v1::OperatorSpec& spec) const {
    auto adapter = adapter_factories_.find(spec.type());
    if (adapter != adapter_factories_.end()) {
        return adapter->second(spec);
    }

    auto node = create(spec);
    if (!node)
        return nullptr;

    auto schema = port_schemas_.find(spec.type());
    if (schema == port_schemas_.end()) {
        return std::make_shared<SinglePortOperatorAdapter>(std::move(node), default_schema());
    }
    return std::make_shared<SinglePortOperatorAdapter>(std::move(node), schema->second);
}

bool OperatorRegistry::has_factory(const std::string& type) const noexcept {
    return factories_.find(type) != factories_.end() ||
           adapter_factories_.find(type) != adapter_factories_.end();
}

bool OperatorRegistry::has_input_port(const std::string& type,
                                      const std::string& port) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return false;
    return contains_port(it->second.input_ports, port);
}

bool OperatorRegistry::has_output_port(const std::string& type,
                                       const std::string& port) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return false;
    return contains_port(it->second.output_ports, port);
}

const std::vector<std::string>&
OperatorRegistry::input_ports(const std::string& type) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return empty_ports();
    return it->second.input_ports;
}

const std::vector<std::string>&
OperatorRegistry::output_ports(const std::string& type) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return empty_ports();
    return it->second.output_ports;
}

const std::string& OperatorRegistry::input_port_type(const std::string& type,
                                                     const std::string& port) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return empty_payload_type();
    return payload_type_or_empty(it->second.input_port_types, port);
}

const std::string& OperatorRegistry::output_port_type(const std::string& type,
                                                      const std::string& port) const noexcept {
    auto it = port_schemas_.find(type);
    if (it == port_schemas_.end())
        return empty_payload_type();
    return payload_type_or_empty(it->second.output_port_types, port);
}

void OperatorRegistry::clear() noexcept {
    factories_.clear();
    adapter_factories_.clear();
    port_schemas_.clear();
}

namespace {
// Per-writer-thread operator-error-detail slots. Operators write here from
// scheduler worker threads (each scheduler-owned thread has its own slot);
// SolutionRunner::wait() drains the slots on the host thread and promotes
// the value into the thread_local `rac_error_set_details` slot so the C ABI
// surfaces the honest cause.
//
// Indexing by writer std::thread::id avoids the previous last-writer-wins
// race between concurrent operator threads on a single process-wide string.
// Drain semantics (consume() pops every entry) keep the host-side view
// behaviourally identical to the prior single-slot design for single-runner
// hosts. Multi-runner hosts still observe cross-runner attribution because
// no per-runner token is threaded through the operator factory; that
// remaining limitation is documented on consume_operator_error_detail.
std::mutex& operator_error_detail_mutex() {
    static std::mutex m;
    return m;
}
std::unordered_map<std::thread::id, std::string>& operator_error_detail_slots() {
    static std::unordered_map<std::thread::id, std::string> slots;
    return slots;
}
}  // namespace

void record_operator_error_detail(const std::string& detail) {
    std::lock_guard<std::mutex> lock(operator_error_detail_mutex());
    operator_error_detail_slots()[std::this_thread::get_id()] = detail;
}

std::string consume_operator_error_detail() {
    std::lock_guard<std::mutex> lock(operator_error_detail_mutex());
    auto& slots = operator_error_detail_slots();
    if (slots.empty())
        return {};
    // Return the longest detail string as a heuristic for "most informative",
    // then drain all slots so the next consume() starts from a clean state.
    // We do not attempt to attribute by runner because no token is threaded
    // through the operator factory at construction time.
    std::string out;
    for (auto& [tid, value] : slots) {
        if (value.size() > out.size())
            out = std::move(value);
    }
    slots.clear();
    return out;
}

void register_builtin_operators(OperatorRegistry& registry) {
    // Neutral scaffolding and portable glue types.
    registry.register_factory("source", make_echo_factory(), make_schema({"in"}, {"out"}));
    registry.register_factory("echo", make_echo_factory(), default_schema());
    registry.register_factory("window", make_window_factory(), default_schema());
    registry.register_factory("context_build", make_context_build_factory(), default_schema());
    registry.register_factory("sink", make_sink_factory(), make_schema({"in"}, {}));
    // Tagged stand-in for `retrieve` so RAG solutions can be validated without
    // an engine-backed RAG provider. The real engine-backed factory (from
    // op_engine_backed.cpp::register_engine_backed_operators) overrides this at
    // host registration time. The stand-in echoes the input on port "results"
    // so the L5 graph remains schedulable for unit tests and dry-runs.
    registry.register_factory("retrieve", make_echo_factory(), make_schema({"in"}, {"results"}));
}

}  // namespace rac::solutions
