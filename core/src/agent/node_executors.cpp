// SPDX-License-Identifier: Apache-2.0

#include "node_executors.h"

#include "chat.pb.h"
#include "diarization.pb.h"
#include "embeddings_options.pb.h"
#include "host_callbacks.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "pack_store.h"
#include "rag.pb.h"
#include "rerank.pb.h"
#include "segmentation.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#include "vlm_options.pb.h"
#include "workflow_store.h"
#include "workflow_validator.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <mutex>
#include <nlohmann/json.hpp>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "features/llm/tool_provider_dispatch.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#if defined(RAC_HAVE_RAG)
#include "rac/features/rag/rac_rag.h"
#endif
#include "rac/features/rerank/rac_rerank_component.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace rac::agent {
namespace {

using nlohmann::json;
using runanywhere::v1::WorkflowBinary;
using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowItem;
using runanywhere::v1::WorkflowNode;

WorkflowItem text_item(const json& body) {
    WorkflowItem item;
    item.set_json(body.dump());
    return item;
}

/// Every executor resolves its own expression fields, so this keeps the
/// resolve-or-fail shape in one place.
bool resolve(const std::string& expression, const ExpressionContext& context, std::string* out,
             std::string* out_error) {
    return resolve_expression(expression, context, out, out_error);
}

json parse_or_empty(const std::string& text) {
    json parsed = json::parse(text, nullptr, false);
    if (parsed.is_discarded())
        return json::object();
    return parsed;
}

/// Serialize a request, hand it to a proto-byte ABI entry point, parse the
/// result — the shape every rac_*_proto call below shares. @p fn receives
/// (bytes, size, out_buffer).
template <typename Request, typename Result, typename Fn>
rac_result_t call_proto_abi(Fn&& fn, const Request& request, Result* out_result,
                            const char* failure_message, std::string* out_error) {
    const std::string encoded = request.SerializeAsString();

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t status =
        fn(reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size(), &buffer);
    if (status != RAC_SUCCESS) {
        *out_error = buffer.error_message != nullptr ? buffer.error_message : failure_message;
        rac_proto_buffer_free(&buffer);
        return status;
    }

    const bool parsed = out_result->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    if (!parsed) {
        *out_error = std::string(failure_message) + ": unreadable result";
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

/// First attachment matching @p key across the incoming items, or the first
/// attachment at all when @p key is empty. @p out_owner receives the item the
/// attachment rides on, for executors that also read fields off its body.
const WorkflowBinary* find_binary(const std::vector<WorkflowItem>& items, const std::string& key,
                                  const WorkflowItem** out_owner = nullptr) {
    for (const WorkflowItem& item : items) {
        if (!key.empty()) {
            auto found = item.binary().find(key);
            if (found != item.binary().end()) {
                if (out_owner != nullptr)
                    *out_owner = &item;
                return &found->second;
            }
        } else if (!item.binary().empty()) {
            if (out_owner != nullptr)
                *out_owner = &item;
            return &item.binary().begin()->second;
        }
    }
    return nullptr;
}

struct WavPcm {
    runanywhere::v1::AudioEncoding encoding = runanywhere::v1::AUDIO_ENCODING_UNSPECIFIED;
    int32_t sample_rate = 0;
    int32_t channels = 0;
    size_t data_offset = 0;
    size_t data_size = 0;
};

/// The VAD and diarization ABIs take raw PCM and reject container bytes, so a
/// WAV attachment has to be split into its format and its samples here.
/// Accepts the two layouts those ABIs accept: 16-bit integer and 32-bit float.
bool parse_wav(const std::string& bytes, WavPcm* out) {
    const auto* raw = reinterpret_cast<const uint8_t*>(bytes.data());
    const auto read_u16 = [raw](size_t at) {
        return static_cast<uint16_t>(raw[at] | (raw[at + 1] << 8));
    };
    const auto read_u32 = [raw](size_t at) {
        return static_cast<uint32_t>(raw[at]) | (static_cast<uint32_t>(raw[at + 1]) << 8) |
               (static_cast<uint32_t>(raw[at + 2]) << 16) |
               (static_cast<uint32_t>(raw[at + 3]) << 24);
    };

    if (bytes.size() < 44 || !bytes.starts_with("RIFF") || bytes.compare(8, 4, "WAVE") != 0)
        return false;

    uint16_t format_tag = 0;
    uint16_t bits_per_sample = 0;
    bool have_format = false;
    size_t cursor = 12;
    while (cursor + 8 <= bytes.size()) {
        const uint32_t declared = read_u32(cursor + 4);
        const size_t body = cursor + 8;
        const size_t available = std::min<size_t>(declared, bytes.size() - body);
        if (bytes.compare(cursor, 4, "fmt ") == 0 && available >= 16) {
            format_tag = read_u16(body);
            out->channels = read_u16(body + 2);
            out->sample_rate = static_cast<int32_t>(read_u32(body + 4));
            bits_per_sample = read_u16(body + 14);
            have_format = true;
        } else if (bytes.compare(cursor, 4, "data") == 0) {
            out->data_offset = body;
            out->data_size = available;
        }
        cursor = body + declared + (declared & 1);
    }

    if (!have_format || out->data_size == 0)
        return false;
    if (format_tag == 1 && bits_per_sample == 16) {
        out->encoding = runanywhere::v1::AUDIO_ENCODING_PCM_S16_LE;
    } else if (format_tag == 3 && bits_per_sample == 32) {
        out->encoding = runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE;
    } else {
        return false;
    }
    return true;
}

std::string sniff_image_mime(const std::string& bytes) {
    if (bytes.size() >= 8 && bytes.starts_with("\x89PNG\r\n\x1a\n"))
        return "image/png";
    if (bytes.size() >= 3 && static_cast<uint8_t>(bytes[0]) == 0xFF &&
        static_cast<uint8_t>(bytes[1]) == 0xD8 && static_cast<uint8_t>(bytes[2]) == 0xFF)
        return "image/jpeg";
    if (bytes.size() >= 12 && bytes.starts_with("RIFF") && bytes.compare(8, 4, "WEBP") == 0)
        return "image/webp";
    return "";
}

std::string url_encode(const std::string& text) {
    static const char* const kHex = "0123456789ABCDEF";
    std::string encoded;
    encoded.reserve(text.size());
    for (const unsigned char character : text) {
        if (std::isalnum(character) != 0 || character == '-' || character == '.' ||
            character == '_' || character == '~') {
            encoded.push_back(static_cast<char>(character));
        } else {
            encoded.push_back('%');
            encoded.push_back(kHex[character >> 4]);
            encoded.push_back(kHex[character & 0xF]);
        }
    }
    return encoded;
}

void append_query_parameter(std::string* url, const std::string& name, const std::string& value) {
    const size_t fragment = url->find('#');
    const std::string prefix =
        url->substr(0, fragment == std::string::npos ? url->size() : fragment);
    const std::string suffix = fragment == std::string::npos ? "" : url->substr(fragment);
    const char separator = prefix.find('?') == std::string::npos ? '?' : '&';
    *url = prefix + separator + url_encode(name) + "=" + url_encode(value) + suffix;
}

rac_result_t seed_trigger_items(const std::string& raw, NodeExecution* out,
                                std::string* out_error) {
    if (raw.empty()) {
        // A trigger with nothing configured still fires once, so a workflow
        // that takes no input is runnable.
        out->items.push_back(text_item(json::object()));
        return RAC_SUCCESS;
    }

    json parsed = json::parse(raw, nullptr, false);
    if (parsed.is_discarded()) {
        *out_error = "trigger initial_items_json is not valid JSON";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    if (parsed.is_array()) {
        for (const json& entry : parsed)
            out->items.push_back(text_item(entry));
    } else {
        out->items.push_back(text_item(parsed));
    }
    return RAC_SUCCESS;
}

rac_result_t run_manual_trigger(const WorkflowNode& node, NodeExecution* out,
                                std::string* out_error) {
    return seed_trigger_items(node.manual_trigger().initial_items_json(), out, out_error);
}

// The firing clock is host-side; when a run reaches the node it seeds items
// exactly like Manual Trigger.
rac_result_t run_schedule_trigger(const WorkflowNode& node, NodeExecution* out,
                                  std::string* out_error) {
    return seed_trigger_items(node.schedule_trigger().initial_items_json(), out, out_error);
}

rac_result_t run_set_transform(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                               const ExpressionContext& context, NodeExecution* out,
                               std::string* out_error) {
    const auto& config = node.set_transform();

    for (const WorkflowItem& input : inputs) {
        json body = config.keep_only_assigned() ? json::object() : parse_or_empty(input.json());

        for (const auto& assignment : config.assignments()) {
            std::string value;
            if (!resolve(assignment.value(), context, &value, out_error))
                return RAC_ERROR_INVALID_CONFIGURATION;

            // A resolved value that is itself JSON keeps its type; anything
            // else lands as a string. Without this every number reaching a
            // later numeric comparison would arrive quoted.
            json parsed = json::parse(value, nullptr, false);
            body[assignment.field()] = parsed.is_discarded() ? json(value) : parsed;
        }

        WorkflowItem item = input;
        item.set_json(body.dump());
        out->items.push_back(std::move(item));
    }
    return RAC_SUCCESS;
}

bool compare(const std::string& left, runanywhere::v1::ComparisonOperator op,
             const std::string& right) {
    using runanywhere::v1::ComparisonOperator;

    const auto numeric = [](const std::string& text, double* value) {
        char* end = nullptr;
        *value = std::strtod(text.c_str(), &end);
        return end != text.c_str() && *end == '\0';
    };

    switch (op) {
        case ComparisonOperator::COMPARISON_OPERATOR_EQUALS:
            return left == right;
        case ComparisonOperator::COMPARISON_OPERATOR_NOT_EQUALS:
            return left != right;
        case ComparisonOperator::COMPARISON_OPERATOR_CONTAINS:
            return left.find(right) != std::string::npos;
        case ComparisonOperator::COMPARISON_OPERATOR_IS_EMPTY:
            return left.empty();
        case ComparisonOperator::COMPARISON_OPERATOR_GREATER_THAN:
        case ComparisonOperator::COMPARISON_OPERATOR_LESS_THAN: {
            double a = 0.0;
            double b = 0.0;
            // Fall back to lexicographic order when either side is not a
            // number, so comparing two strings is defined rather than false.
            if (!numeric(left, &a) || !numeric(right, &b)) {
                return op == ComparisonOperator::COMPARISON_OPERATOR_GREATER_THAN ? left > right
                                                                                  : left < right;
            }
            return op == ComparisonOperator::COMPARISON_OPERATOR_GREATER_THAN ? a > b : a < b;
        }
        default:
            return false;
    }
}

rac_result_t run_condition(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                           const ExpressionContext& context, NodeExecution* out,
                           std::string* out_error) {
    std::string left;
    std::string right;
    if (!resolve(node.condition().left(), context, &left, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (!resolve(node.condition().right(), context, &right, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    out->port = compare(left, node.condition().operator_(), right) ? "true" : "false";
    out->items = inputs;
    return RAC_SUCCESS;
}

rac_result_t run_merge(const WorkflowNode& node, const NodeInputs& inputs, NodeExecution* out) {
    const auto& config = node.merge();
    const uint32_t count = config.input_count() > 0 ? config.input_count() : 2;

    std::unordered_set<std::string> seen;
    for (uint32_t index = 1; index <= count; ++index) {
        auto port = inputs.by_port.find("in" + std::to_string(index));
        if (port == inputs.by_port.end())
            continue;
        for (const WorkflowItem& item : port->second) {
            if (config.deduplicate() && !seen.insert(item.json()).second)
                continue;
            out->items.push_back(item);
        }
    }
    return RAC_SUCCESS;
}

rac_result_t run_filter(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                        const ExpressionContext& context, NodeExecution* out,
                        std::string* out_error) {
    const auto& config = node.filter();
    out->port = "true";
    out->secondary_port = "false";

    for (const WorkflowItem& item : inputs) {
        ExpressionContext bound = context;
        bound.has_current_item = true;
        bound.current_item_json = item.json();

        std::string left;
        std::string right;
        if (!resolve(config.left(), bound, &left, out_error))
            return RAC_ERROR_INVALID_CONFIGURATION;
        if (!resolve(config.right(), bound, &right, out_error))
            return RAC_ERROR_INVALID_CONFIGURATION;

        if (compare(left, config.operator_(), right)) {
            out->items.push_back(item);
        } else {
            out->secondary_items.push_back(item);
        }
    }
    return RAC_SUCCESS;
}

rac_result_t run_split_out(const WorkflowNode& node, const ExpressionContext& context,
                           NodeExecution* out, std::string* out_error) {
    std::string resolved;
    if (!resolve(node.split_out().field(), context, &resolved, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    json parsed = json::parse(resolved, nullptr, false);
    if (parsed.is_discarded() || !parsed.is_array()) {
        *out_error = "Split Out field did not resolve to a list";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    for (const json& entry : parsed)
        out->items.push_back(text_item(entry));
    return RAC_SUCCESS;
}

rac_result_t run_aggregate(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                           const ExpressionContext& context, NodeExecution* out,
                           std::string* out_error) {
    std::string field;
    if (!resolve(node.aggregate().field(), context, &field, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (field.empty())
        field = "items";

    json collected = json::array();
    WorkflowItem merged;
    for (const WorkflowItem& item : inputs) {
        collected.push_back(parse_or_empty(item.json()));
        for (const auto& [key, binary] : item.binary())
            (*merged.mutable_binary())[key] = binary;
    }

    json body;
    body[field] = collected;
    merged.set_json(body.dump());
    out->items.push_back(std::move(merged));
    return RAC_SUCCESS;
}

rac_result_t run_wait(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                      const std::atomic<bool>* cancelled, NodeExecution* out) {
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(node.wait().seconds());
    // Sliced sleep so a cancel takes effect within one slice, not after the
    // full wait.
    while (std::chrono::steady_clock::now() < deadline) {
        if (cancelled != nullptr && cancelled->load(std::memory_order_relaxed))
            break;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    out->items = inputs;
    return RAC_SUCCESS;
}

rac_result_t run_file_read(const WorkflowNode& node, const ExpressionContext& context,
                           NodeExecution* out, std::string* out_error) {
    const auto& config = node.file_read();

    std::string path;
    if (!resolve(config.path(), context, &path, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (path.empty()) {
        *out_error = "File Read path resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::string bytes;
    const rac_result_t read = adapter_read_file(path, &bytes);
    if (read != RAC_SUCCESS) {
        *out_error = "could not read '" + path + "': " + rac_error_message(read);
        return read;
    }

    const size_t slash = path.find_last_of('/');
    const std::string file_name = slash == std::string::npos ? path : path.substr(slash + 1);

    WorkflowItem item;
    json body;
    body["path"] = path;
    if (config.binary()) {
        const std::string key = config.binary_key().empty() ? "data" : config.binary_key();
        WorkflowBinary& binary = (*item.mutable_binary())[key];
        binary.set_data(bytes);
        binary.set_mime_type(config.mime_type());
        binary.set_file_name(file_name);
        body["size"] = bytes.size();
    } else {
        body["text"] = bytes;
    }
    item.set_json(body.dump());
    out->items.push_back(std::move(item));
    return RAC_SUCCESS;
}

rac_result_t run_file_write(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                            const ExpressionContext& context, NodeExecution* out,
                            std::string* out_error) {
    const auto& config = node.file_write();

    std::string path;
    if (!resolve(config.path(), context, &path, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (path.empty()) {
        *out_error = "File Write path resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::string content;
    if (!config.binary_key().empty()) {
        const WorkflowBinary* binary = find_binary(inputs, config.binary_key());
        if (binary == nullptr) {
            *out_error = "no attachment named '" + config.binary_key() + "' on the incoming items";
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        content = binary->data();
    } else if (!resolve(config.content(), context, &content, out_error)) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    if (config.append() && adapter_file_exists(path)) {
        // The platform adapter has no append primitive, so append is
        // read-concatenate-write. Failing to read an existing file aborts
        // rather than silently overwriting it.
        std::string existing;
        const rac_result_t read = adapter_read_file(path, &existing);
        if (read != RAC_SUCCESS) {
            *out_error = "could not append to '" + path +
                         "': existing content is unreadable: " + rac_error_message(read);
            return read;
        }
        content.insert(0, existing);
    }

    const rac_result_t written = adapter_write_file(path, content);
    if (written != RAC_SUCCESS) {
        *out_error = "could not write '" + path + "': " + rac_error_message(written);
        return written;
    }

    json body;
    body["path"] = path;
    body["bytes_written"] = content.size();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

/// Make sure the model a node names is the one loaded for @p category.
///
/// A workflow is authored once and run later, possibly after the user has
/// loaded something else in the app, so a node that names a model has to be
/// able to bring it up rather than silently running with whatever happens to
/// be resident. An empty model_id means the node takes the current model on
/// purpose, and nothing is touched.
rac_result_t ensure_model_loaded(const std::string& model_id,
                                 runanywhere::v1::ModelCategory category, std::string* out_error) {
    if (model_id.empty())
        return RAC_SUCCESS;

    if (category != runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED) {
        runanywhere::v1::CurrentModelRequest current_request;
        current_request.set_category(category);
        const std::string current_encoded = current_request.SerializeAsString();

        rac_proto_buffer_t current_buffer;
        rac_proto_buffer_init(&current_buffer);
        if (rac_model_lifecycle_current_model_proto(
                reinterpret_cast<const uint8_t*>(current_encoded.data()), current_encoded.size(),
                &current_buffer) == RAC_SUCCESS) {
            runanywhere::v1::CurrentModelResult current;
            const bool parsed =
                current.ParseFromArray(current_buffer.data, static_cast<int>(current_buffer.size));
            rac_proto_buffer_free(&current_buffer);
            if (parsed && current.found() && current.model_id() == model_id)
                return RAC_SUCCESS;
        } else {
            rac_proto_buffer_free(&current_buffer);
        }
    }

    runanywhere::v1::ModelLoadRequest load_request;
    load_request.set_model_id(model_id);
    if (category != runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED)
        load_request.set_category(category);
    const std::string load_encoded = load_request.SerializeAsString();

    rac_proto_buffer_t load_buffer;
    rac_proto_buffer_init(&load_buffer);
    const rac_result_t result = rac_model_lifecycle_load_proto(
        rac_get_model_registry(), reinterpret_cast<const uint8_t*>(load_encoded.data()),
        load_encoded.size(), &load_buffer);
    if (result != RAC_SUCCESS) {
        // The ABI reports argument-level refusals (no registry, unparseable
        // request) only through the buffer, so dropping that text leaves every
        // one of them looking like a missing model.
        *out_error = load_buffer.error_message != nullptr
                         ? std::string(load_buffer.error_message)
                         : "could not load model '" + model_id + "'";
        rac_proto_buffer_free(&load_buffer);
        return result;
    }

    runanywhere::v1::ModelLoadResult load_result;
    const bool parsed =
        load_result.ParseFromArray(load_buffer.data, static_cast<int>(load_buffer.size));
    rac_proto_buffer_free(&load_buffer);

    if (!parsed) {
        *out_error = "could not read the model load result";
        return RAC_ERROR_DECODING_ERROR;
    }
    // ModelLoadResult reports a semantic failure by carrying an error rather
    // than by a success flag.
    if (load_result.has_error()) {
        *out_error = load_result.error().message().empty()
                         ? "could not load model '" + model_id + "'"
                         : load_result.error().message();
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    return RAC_SUCCESS;
}

rac_result_t run_llm_generate(const WorkflowNode& node, const ExpressionContext& context,
                              NodeExecution* out, std::string* out_error) {
    const auto& config = node.llm_generate();

    std::string prompt;
    if (!resolve(config.prompt(), context, &prompt, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (prompt.empty()) {
        *out_error = "LLM prompt resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded =
        ensure_model_loaded(config.model_id(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::LLMGenerateRequest request;
    request.set_model_id(config.model_id());
    if (config.has_generation())
        *request.mutable_options() = config.generation();

    if (config.has_system_prompt()) {
        std::string system_prompt;
        if (!resolve(config.system_prompt(), context, &system_prompt, out_error))
            return RAC_ERROR_INVALID_CONFIGURATION;
        request.mutable_options()->set_system_prompt(system_prompt);
    }

    runanywhere::v1::ChatMessage* turn = request.add_messages();
    turn->set_role(runanywhere::v1::MESSAGE_ROLE_USER);
    turn->set_content(prompt);

    runanywhere::v1::LLMGenerationResult generation;
    const rac_result_t status = call_proto_abi(rac_llm_generate_proto, request, &generation,
                                               "LLM generation failed", out_error);
    if (status != RAC_SUCCESS)
        return status;

    json body;
    body["text"] = generation.text();
    body["model"] = generation.model_used();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_llm_structured(const WorkflowNode& node, const ExpressionContext& context,
                                NodeExecution* out, std::string* out_error) {
    const auto& config = node.llm_structured();

    std::string prompt;
    if (!resolve(config.prompt(), context, &prompt, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (prompt.empty()) {
        *out_error = "LLM prompt resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (config.json_schema().empty()) {
        *out_error = "Structured Output node has no JSON schema";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded =
        ensure_model_loaded(config.model_id(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::LLMGenerateRequest request;
    request.set_model_id(config.model_id());
    if (config.has_generation())
        *request.mutable_options() = config.generation();
    request.mutable_options()->mutable_structured_output()->set_schema(config.json_schema());

    if (config.has_system_prompt()) {
        std::string system_prompt;
        if (!resolve(config.system_prompt(), context, &system_prompt, out_error))
            return RAC_ERROR_INVALID_CONFIGURATION;
        request.mutable_options()->set_system_prompt(system_prompt);
    }

    runanywhere::v1::ChatMessage* turn = request.add_messages();
    turn->set_role(runanywhere::v1::MESSAGE_ROLE_USER);
    turn->set_content(prompt);

    runanywhere::v1::LLMGenerationResult generation;
    const rac_result_t status = call_proto_abi(rac_llm_generate_proto, request, &generation,
                                               "structured LLM generation failed", out_error);
    if (status != RAC_SUCCESS)
        return status;

    // The item body IS the parsed answer, so downstream expressions address
    // its fields directly instead of digging through a wrapper.
    const std::string& raw =
        generation.json_output().empty() ? generation.text() : generation.json_output();
    json parsed = json::parse(raw, nullptr, false);
    if (parsed.is_discarded()) {
        *out_error = "the model's answer is not valid JSON";
        return RAC_ERROR_DECODING_ERROR;
    }
    out->items.push_back(text_item(parsed));
    return RAC_SUCCESS;
}

rac_result_t run_vision(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                        const ExpressionContext& context, NodeExecution* out,
                        std::string* out_error) {
    const auto& config = node.vision();

    std::string prompt;
    if (!resolve(config.prompt(), context, &prompt, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (prompt.empty()) {
        *out_error = "Vision prompt resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const WorkflowBinary* image = find_binary(inputs, config.binary_key());
    if (image == nullptr) {
        *out_error =
            config.binary_key().empty()
                ? "Vision node needs an image attachment on the incoming item"
                : "no attachment named '" + config.binary_key() + "' on the incoming items";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_MULTIMODAL, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::VLMGenerationRequest request;
    request.set_prompt(prompt);
    if (!config.model_id().empty())
        request.set_model_id(config.model_id());
    if (config.has_generation())
        *request.mutable_options() = config.generation();

    runanywhere::v1::VLMImage* request_image = request.add_images();
    request_image->set_data(image->data());
    const std::string mime =
        image->mime_type().empty() ? sniff_image_mime(image->data()) : image->mime_type();
    if (mime.empty()) {
        *out_error = "the image attachment has no mime type and its format is not recognizable";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    request_image->set_media_type(mime);

    runanywhere::v1::VLMResult result;
    const rac_result_t status = call_proto_abi(rac_vlm_generate_proto, request, &result,
                                               "vision generation failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (result.has_error()) {
        *out_error = result.error().message().empty() ? "vision generation failed"
                                                      : result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json body;
    body["text"] = result.text();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_embed(const WorkflowNode& node, const ExpressionContext& context,
                       NodeExecution* out, std::string* out_error) {
    const auto& config = node.embed();

    std::string resolved;
    if (!resolve(config.text(), context, &resolved, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (resolved.empty()) {
        *out_error = "Embed text resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_EMBEDDING, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::EmbeddingsRequest request;
    // A resolved JSON list embeds as a batch; anything else is one text.
    json parsed = json::parse(resolved, nullptr, false);
    if (!parsed.is_discarded() && parsed.is_array()) {
        for (const json& entry : parsed)
            request.add_texts(entry.is_string() ? entry.get<std::string>() : entry.dump());
    } else {
        request.add_texts(resolved);
    }
    if (!config.model_id().empty())
        request.set_model_id(config.model_id());

    runanywhere::v1::EmbeddingsResult result;
    const rac_result_t status = call_proto_abi(rac_embeddings_embed_batch_lifecycle_proto, request,
                                               &result, "embedding failed", out_error);
    if (status != RAC_SUCCESS)
        return status;

    json vectors = json::array();
    for (const auto& vector : result.vectors()) {
        json values = json::array();
        for (const float value : vector.values())
            values.push_back(value);
        vectors.push_back(std::move(values));
    }

    json body;
    body["dimension"] = result.dimension();
    body["vectors"] = vectors;
    if (vectors.size() == 1)
        body["embedding"] = vectors.front();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_rerank(const WorkflowNode& node, const ExpressionContext& context,
                        NodeExecution* out, std::string* out_error) {
    const auto& config = node.rerank();

    std::string query;
    if (!resolve(config.query(), context, &query, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (query.empty()) {
        *out_error = "Rerank query resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::string documents_json;
    if (!resolve(config.documents(), context, &documents_json, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    json parsed = json::parse(documents_json, nullptr, false);
    if (parsed.is_discarded() || !parsed.is_array()) {
        *out_error = "Rerank documents did not resolve to a list";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    std::vector<std::string> documents;
    documents.reserve(parsed.size());
    for (const json& entry : parsed)
        documents.push_back(entry.is_string() ? entry.get<std::string>() : entry.dump());

    // Rerank models are deliberately outside the category-routed lifecycle
    // (see model_lifecycle_translation.cpp), so the node drives the component
    // directly: resolve the on-disk artifact, load, score, tear down.
    if (config.model_id().empty()) {
        *out_error = "Rerank node needs a model_id";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    runanywhere::v1::ModelLoadRequest resolve_request;
    resolve_request.set_model_id(config.model_id());
    runanywhere::v1::ModelLoadResult resolved;
    rac_result_t status = call_proto_abi(
        [](const uint8_t* bytes, size_t size, rac_proto_buffer_t* buffer) {
            return rac_model_lifecycle_resolve_paths_proto(rac_get_model_registry(), bytes,
                                                            size, buffer);
        },
        resolve_request, &resolved, "could not resolve the reranker model", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (resolved.has_error() || resolved.resolved_path().empty()) {
        *out_error = resolved.has_error() && !resolved.error().message().empty()
                         ? resolved.error().message()
                         : "reranker model '" + config.model_id() + "' is not downloaded";
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    rac_handle_t reranker = nullptr;
    status = rac_rerank_component_create(&reranker);
    if (status != RAC_SUCCESS) {
        *out_error = "could not create the rerank component";
        return status;
    }
    status = rac_rerank_component_load_model(reranker, resolved.resolved_path().c_str(),
                                             config.model_id().c_str(), config.model_id().c_str());
    if (status != RAC_SUCCESS) {
        rac_rerank_component_destroy(reranker);
        *out_error =
            "could not load reranker '" + config.model_id() + "': " + rac_error_message(status);
        return status;
    }

    runanywhere::v1::RerankRequest request;
    request.set_query(query);
    for (const std::string& document : documents)
        request.add_documents(document);
    if (config.top_n() > 0)
        request.mutable_options()->set_top_n(config.top_n());

    runanywhere::v1::RerankResult result;
    status = call_proto_abi(
        [reranker](const uint8_t* bytes, size_t size, rac_proto_buffer_t* buffer) {
            return rac_rerank_component_rerank_proto(reranker, bytes, size, buffer);
        },
        request, &result, "rerank failed", out_error);
    rac_rerank_component_destroy(reranker);
    if (status != RAC_SUCCESS)
        return status;

    for (const auto& item : result.items()) {
        json body;
        body["index"] = item.index();
        body["score"] = item.relevance_score();
        if (item.index() < documents.size())
            body["text"] = documents[item.index()];
        out->items.push_back(text_item(body));
    }
    return RAC_SUCCESS;
}

rac_result_t run_transcribe(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                            NodeExecution* out, std::string* out_error) {
    const auto& config = node.transcribe();

    const WorkflowBinary* audio_binary = find_binary(inputs, config.binary_key());
    if (audio_binary == nullptr) {
        *out_error =
            config.binary_key().empty()
                ? "Transcribe node needs an audio attachment on the incoming item"
                : "no attachment named '" + config.binary_key() + "' on the incoming items";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::STTTranscriptionRequest request;
    runanywhere::v1::STTAudioSource* audio = request.mutable_audio();
    audio->set_audio_data(audio_binary->data());
    // The STT engines decode WAV containers themselves; everything else is
    // handed over as raw PCM.
    WavPcm wav;
    if (parse_wav(audio_binary->data(), &wav)) {
        audio->set_audio_format(runanywhere::v1::AUDIO_FORMAT_WAV);
        audio->set_sample_rate(wav.sample_rate);
        audio->set_channels(wav.channels);
    } else {
        audio->set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM);
    }
    if (config.has_language() && !config.language().empty())
        request.mutable_options()->set_language(config.language());

    runanywhere::v1::STTOutput output;
    const rac_result_t status = call_proto_abi(rac_stt_transcribe_lifecycle_proto, request, &output,
                                               "transcription failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (output.has_error()) {
        *out_error =
            output.error().message().empty() ? "transcription failed" : output.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json body;
    body["text"] = output.text();
    if (output.has_language())
        body["language"] = output.language();
    body["duration_ms"] = output.duration_ms();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_speak(const WorkflowNode& node, const ExpressionContext& context,
                       NodeExecution* out, std::string* out_error) {
    const auto& config = node.speak();

    std::string text;
    if (!resolve(config.text(), context, &text, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (text.empty()) {
        *out_error = "Speak text resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    if (config.play()) {
        // Commons has no audio output path on any platform; playback lives in
        // the host SDK, like capture does.
        *out_error =
            "audio playback is not available inside the workflow runner; "
            "run Speak with play off and play the returned audio attachment in the app";
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::TTSSynthesisRequest request;
    request.set_text(text);
    request.mutable_options()->set_audio_format(runanywhere::v1::AUDIO_FORMAT_WAV);
    if (config.has_voice() && !config.voice().empty())
        request.mutable_options()->set_voice(config.voice());

    runanywhere::v1::TTSOutput output;
    const rac_result_t status = call_proto_abi(rac_tts_synthesize_lifecycle_proto, request, &output,
                                               "speech synthesis failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (output.has_error()) {
        *out_error =
            output.error().message().empty() ? "speech synthesis failed" : output.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    WorkflowItem item;
    const std::string key = config.binary_key().empty() ? "audio" : config.binary_key();
    WorkflowBinary& binary = (*item.mutable_binary())[key];
    binary.set_data(output.audio_data());
    binary.set_mime_type(output.audio_format() == runanywhere::v1::AUDIO_FORMAT_WAV ? "audio/wav"
                                                                                    : "audio/pcm");

    json body;
    body["duration_ms"] = output.duration_ms();
    body["sample_rate"] = output.sample_rate();
    item.set_json(body.dump());
    out->items.push_back(std::move(item));
    return RAC_SUCCESS;
}

rac_result_t run_detect_voice(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                              NodeExecution* out, std::string* out_error) {
    const auto& config = node.detect_voice();

    const WorkflowBinary* audio_binary = find_binary(inputs, config.binary_key());
    if (audio_binary == nullptr) {
        *out_error =
            config.binary_key().empty()
                ? "Detect Voice node needs an audio attachment on the incoming item"
                : "no attachment named '" + config.binary_key() + "' on the incoming items";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    runanywhere::v1::VADProcessRequest request;
    runanywhere::v1::VADAudioSource* audio = request.mutable_audio();
    WavPcm wav;
    if (parse_wav(audio_binary->data(), &wav)) {
        if (wav.channels > 1) {
            *out_error = "Detect Voice needs mono audio";
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        audio->set_audio_data(audio_binary->data().substr(wav.data_offset, wav.data_size));
        audio->set_encoding(wav.encoding);
        audio->set_sample_rate(wav.sample_rate);
    } else {
        audio->set_audio_data(audio_binary->data());
        audio->set_encoding(runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE);
    }
    if (config.has_threshold())
        request.mutable_options()->set_activation_threshold(config.threshold());

    runanywhere::v1::VADResult result;
    const rac_result_t status = call_proto_abi(rac_vad_process_lifecycle_proto, request, &result,
                                               "voice detection failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (result.has_error()) {
        *out_error =
            result.error().message().empty() ? "voice detection failed" : result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json body;
    body["is_speech"] = result.is_speech();
    body["probability"] = result.probability();
    body["energy"] = result.energy();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_diarize(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                         NodeExecution* out, std::string* out_error) {
    const auto& config = node.diarize();

    const WorkflowBinary* audio_binary = find_binary(inputs, config.binary_key());
    if (audio_binary == nullptr) {
        *out_error =
            config.binary_key().empty()
                ? "Diarize node needs an audio attachment on the incoming item"
                : "no attachment named '" + config.binary_key() + "' on the incoming items";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::DiarizationRequest request;
    // The diarization ABI rejects container bytes outright, so a WAV
    // attachment is stripped to its sample data here.
    WavPcm wav;
    if (parse_wav(audio_binary->data(), &wav)) {
        if (wav.channels > 1) {
            *out_error = "Diarize needs mono audio";
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        request.set_audio_data(audio_binary->data().substr(wav.data_offset, wav.data_size));
        request.mutable_options()->set_encoding(wav.encoding);
        request.mutable_options()->set_sample_rate(wav.sample_rate);
    } else {
        request.set_audio_data(audio_binary->data());
    }
    if (config.has_speaker_count() && config.speaker_count() > 0)
        request.mutable_options()->set_max_speakers(static_cast<int32_t>(config.speaker_count()));

    runanywhere::v1::DiarizationResult result;
    const rac_result_t status = call_proto_abi(rac_diarization_diarize_lifecycle_proto, request,
                                               &result, "diarization failed", out_error);
    if (status != RAC_SUCCESS)
        return status;

    json segments = json::array();
    for (const auto& segment : result.segments()) {
        json entry;
        entry["start_ms"] = segment.start_ms();
        entry["end_ms"] = segment.end_ms();
        entry["speaker_index"] = segment.speaker_index();
        entry["speaker_id"] = segment.speaker_id();
        segments.push_back(std::move(entry));
    }

    json body;
    body["speaker_count"] = result.speaker_count();
    body["segments"] = segments;
    body["audio_duration_ms"] = result.audio_duration_ms();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_segment(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                         const ExpressionContext& context, NodeExecution* out,
                         std::string* out_error) {
    const auto& config = node.segment();

    // SegmentConfig carries no binary_key field; its `text` expression names
    // the attachment holding the raw pixels (empty = first attachment), and
    // the owning item's body must carry `width` and `height` since the
    // segmentation ABI takes raw pixel data, not an encoded image.
    std::string key;
    if (!resolve(config.text(), context, &key, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    const WorkflowItem* owner = nullptr;
    const WorkflowBinary* image = find_binary(inputs, key, &owner);
    if (image == nullptr) {
        *out_error = key.empty() ? "Segment node needs an image attachment on the incoming item"
                                 : "no attachment named '" + key + "' on the incoming items";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const json body_fields = parse_or_empty(owner->json());
    const uint32_t width = body_fields.value("width", 0u);
    const uint32_t height = body_fields.value("height", 0u);
    if (width == 0 || height == 0) {
        *out_error = "Segment needs `width` and `height` fields on the item carrying the pixels";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const size_t pixel_count = static_cast<size_t>(width) * height;
    runanywhere::v1::SegmentationPixelFormat pixel_format;
    if (image->data().size() == pixel_count * 3) {
        pixel_format = runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8;
    } else if (image->data().size() == pixel_count * 4) {
        pixel_format = runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGBA8;
    } else {
        *out_error = "Segment needs raw RGB8 or RGBA8 pixels matching width x height";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t loaded = ensure_model_loaded(
        config.model_id(), runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::SegmentationRequest request;
    request.mutable_image()->set_data(image->data());
    request.mutable_image()->set_width(width);
    request.mutable_image()->set_height(height);
    request.mutable_image()->set_pixel_format(pixel_format);
    if (config.has_model_id() && !config.model_id().empty())
        request.set_model_id(config.model_id());

    runanywhere::v1::SegmentationResult result;
    const rac_result_t status = call_proto_abi(rac_segmentation_segment_lifecycle_proto, request,
                                               &result, "segmentation failed", out_error);
    if (status != RAC_SUCCESS)
        return status;

    json classes = json::array();
    for (const auto& summary : result.class_summaries()) {
        json entry;
        entry["class_id"] = summary.class_id();
        entry["label"] = summary.label();
        entry["pixel_count"] = summary.pixel_count();
        classes.push_back(std::move(entry));
    }

    WorkflowItem item;
    WorkflowBinary& mask = (*item.mutable_binary())["mask"];
    mask.set_data(result.class_mask_u16_le());
    mask.set_mime_type("application/octet-stream");

    json body;
    body["width"] = result.width();
    body["height"] = result.height();
    body["classes"] = classes;
    item.set_json(body.dump());
    out->items.push_back(std::move(item));
    return RAC_SUCCESS;
}

#if defined(RAC_HAVE_RAG)

/// One session per model pair, kept for the process lifetime. The session owns
/// the index, so destroying it after each node would throw away everything a
/// Rag Ingest node just added before a later Rag Query could read it.
rac_handle_t rag_session_for(const std::string& embedding_model_id, const std::string& llm_model_id,
                             std::string* out_error) {
    static std::mutex mutex;
    static std::unordered_map<std::string, rac_handle_t> sessions;

    const std::string session_key = embedding_model_id + "\x1f" + llm_model_id;
    std::lock_guard<std::mutex> lock(mutex);
    auto found = sessions.find(session_key);
    if (found != sessions.end())
        return found->second;

    runanywhere::v1::RAGConfiguration configuration;
    configuration.set_embedding_model_id(embedding_model_id);
    configuration.set_llm_model_id(llm_model_id);
    const std::string encoded = configuration.SerializeAsString();

    rac_handle_t session = nullptr;
    const rac_result_t status = rac_rag_session_create_proto(
        reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size(), &session);
    if (status != RAC_SUCCESS || session == nullptr) {
        *out_error = "could not create the RAG session: " + std::string(rac_error_message(status));
        return nullptr;
    }
    sessions.emplace(session_key, session);
    return session;
}

rac_result_t run_rag_query(const WorkflowNode& node, const ExpressionContext& context,
                           NodeExecution* out, std::string* out_error) {
    const auto& config = node.rag_query();

    std::string question;
    if (!resolve(config.question(), context, &question, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (question.empty()) {
        *out_error = "RAG question resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (config.embedding_model_id().empty()) {
        *out_error = "RAG Query node needs an embedding_model_id";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    rac_handle_t session =
        rag_session_for(config.embedding_model_id(), config.llm_model_id(), out_error);
    if (session == nullptr)
        return RAC_ERROR_PROCESSING_FAILED;

    runanywhere::v1::RAGQueryOptions options;
    options.set_query(question);
    if (config.top_k() > 0)
        options.mutable_retrieval()->set_top_k(static_cast<int32_t>(config.top_k()));

    runanywhere::v1::RAGResult result;
    const rac_result_t status = call_proto_abi(
        [session](const uint8_t* bytes, size_t size, rac_proto_buffer_t* buffer) {
            return rac_rag_query_proto(session, bytes, size, buffer);
        },
        options, &result, "RAG query failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (result.has_error()) {
        *out_error =
            result.error().message().empty() ? "RAG query failed" : result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json chunks = json::array();
    for (const auto& chunk : result.retrieved_chunks()) {
        json entry;
        entry["text"] = chunk.text();
        entry["score"] = chunk.score();
        if (chunk.has_source_document())
            entry["source"] = chunk.source_document();
        chunks.push_back(std::move(entry));
    }

    json body;
    body["answer"] = result.answer();
    body["chunks"] = chunks;
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_rag_ingest(const WorkflowNode& node, const ExpressionContext& context,
                            NodeExecution* out, std::string* out_error) {
    const auto& config = node.rag_ingest();

    std::string text;
    if (!resolve(config.text(), context, &text, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (text.empty()) {
        *out_error = "RAG Ingest text resolved to empty text";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (config.embedding_model_id().empty()) {
        *out_error = "RAG Ingest node needs an embedding_model_id";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    rac_handle_t session =
        rag_session_for(config.embedding_model_id(), config.llm_model_id(), out_error);
    if (session == nullptr)
        return RAC_ERROR_PROCESSING_FAILED;

    runanywhere::v1::RAGDocument document;
    document.set_text(text);
    if (!config.document_id().empty())
        document.set_id(config.document_id());

    runanywhere::v1::RAGStatistics statistics;
    const rac_result_t status = call_proto_abi(
        [session](const uint8_t* bytes, size_t size, rac_proto_buffer_t* buffer) {
            return rac_rag_ingest_proto(session, bytes, size, buffer);
        },
        document, &statistics, "RAG ingest failed", out_error);
    if (status != RAC_SUCCESS)
        return status;
    if (statistics.has_error()) {
        *out_error = statistics.error().message().empty() ? "RAG ingest failed"
                                                          : statistics.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json body;
    if (!config.document_id().empty())
        body["document_id"] = config.document_id();
    body["indexed_documents"] = statistics.indexed_documents();
    body["indexed_chunks"] = statistics.indexed_chunks();
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

#else  // RAC_HAVE_RAG

rac_result_t run_rag_query(const WorkflowNode&, const ExpressionContext&, NodeExecution*,
                           std::string* out_error) {
    *out_error = "RAG Query node requires the RAG backend; rebuild with -DRAC_BACKEND_RAG=ON";
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t run_rag_ingest(const WorkflowNode&, const ExpressionContext&, NodeExecution*,
                            std::string* out_error) {
    *out_error = "RAG Ingest node requires the RAG backend; rebuild with -DRAC_BACKEND_RAG=ON";
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

#endif  // RAC_HAVE_RAG

rac_result_t run_load_model(const WorkflowNode& node, NodeExecution* out, std::string* out_error) {
    const auto& config = node.load_model();
    if (config.model_id().empty()) {
        *out_error = "Load Model node needs a model_id";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const runanywhere::v1::ModelCategory category =
        config.has_category() ? config.category() : runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
    const rac_result_t loaded = ensure_model_loaded(config.model_id(), category, out_error);
    if (loaded != RAC_SUCCESS)
        return loaded;

    json body;
    body["model_id"] = config.model_id();
    body["loaded"] = true;
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_http_request(const WorkflowNode& node, const ExpressionContext& context,
                              NodeExecution* out, std::string* out_error) {
    const auto& config = node.http_request();

    std::string url;
    if (!resolve(config.url(), context, &url, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;
    if (!url.starts_with("http://") && !url.starts_with("https://")) {
        *out_error = "HTTP node needs an absolute http:// or https:// URL";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    static const char* const kMethods[] = {"GET", "GET", "POST", "PUT", "PATCH", "DELETE"};
    const int method_index = static_cast<int>(config.method());
    const char* method = (method_index >= 0 && method_index < 6) ? kMethods[method_index] : "GET";

    std::vector<std::string> header_storage;
    std::vector<rac_http_header_kv_t> headers;
    header_storage.reserve((config.headers_size() + 1) * 2);
    for (const auto& [name, value_expression] : config.headers()) {
        std::string value;
        if (!resolve(value_expression, context, &value, out_error))
            return RAC_ERROR_INVALID_CONFIGURATION;
        header_storage.push_back(name);
        header_storage.push_back(value);
    }

    // Auth values are credentials, taken verbatim — never expression-resolved,
    // so a secret containing braces cannot be mangled or leak into an error.
    if (config.has_auth()) {
        const auto& auth = config.auth();
        switch (auth.kind()) {
            case runanywhere::v1::HTTP_AUTH_KIND_BEARER:
                header_storage.push_back("Authorization");
                header_storage.push_back("Bearer " + auth.secret());
                break;
            case runanywhere::v1::HTTP_AUTH_KIND_HEADER:
                if (auth.name().empty()) {
                    *out_error = "HTTP header auth needs a header name";
                    return RAC_ERROR_INVALID_CONFIGURATION;
                }
                header_storage.push_back(auth.name());
                header_storage.push_back(auth.secret());
                break;
            case runanywhere::v1::HTTP_AUTH_KIND_QUERY:
                if (auth.name().empty()) {
                    *out_error = "HTTP query auth needs a parameter name";
                    return RAC_ERROR_INVALID_CONFIGURATION;
                }
                append_query_parameter(&url, auth.name(), auth.secret());
                break;
            default:
                break;
        }
    }
    for (size_t i = 0; i + 1 < header_storage.size(); i += 2)
        headers.push_back({header_storage[i].c_str(), header_storage[i + 1].c_str()});

    std::string body;
    if (config.has_body() && !resolve(config.body(), context, &body, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    rac_http_client_t* client = nullptr;
    rac_result_t result = rac_http_client_create(&client);
    if (result != RAC_SUCCESS) {
        *out_error = "no HTTP transport is registered";
        return result;
    }

    rac_http_request_t request{};
    request.method = method;
    request.url = url.c_str();
    request.headers = headers.empty() ? nullptr : headers.data();
    request.header_count = headers.size();
    request.body_bytes = body.empty() ? nullptr : reinterpret_cast<const uint8_t*>(body.data());
    request.body_len = body.size();
    request.timeout_ms = static_cast<int32_t>(config.timeout_ms());
    request.follow_redirects = RAC_TRUE;

    rac_http_response_t response{};
    result = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    if (result != RAC_SUCCESS) {
        *out_error = "HTTP request failed: " + std::string(rac_error_message(result));
        rac_http_response_free(&response);
        return result;
    }

    std::string response_body;
    if (response.body_bytes != nullptr && response.body_len > 0)
        response_body.assign(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    const int32_t status = response.status;
    rac_http_response_free(&response);

    json body_value = json::parse(response_body, nullptr, false);

    json result_body;
    result_body["status"] = status;
    // Hand back parsed JSON when the response is JSON so a downstream
    // expression can address fields, and the raw text otherwise.
    result_body["body"] = body_value.is_discarded() ? json(response_body) : body_value;
    out->items.push_back(text_item(result_body));

    if (status < 200 || status >= 300) {
        *out_error = "HTTP request returned status " + std::to_string(status);
        return RAC_ERROR_NETWORK_ERROR;
    }
    return RAC_SUCCESS;
}

/// Shared shape for the two host-delegated node types: serialize a request,
/// hand it to the callback, read a result that carries either a payload or an
/// SDKError.
template <typename Invocation, typename Result, typename Callback>
rac_result_t invoke_host(Callback callback, void* user_data, const Invocation& invocation,
                         Result* out_result, const char* missing_message, std::string* out_error) {
    if (callback == nullptr) {
        *out_error = missing_message;
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }

    const std::string encoded = invocation.SerializeAsString();

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t result = callback(reinterpret_cast<const uint8_t*>(encoded.data()),
                                         encoded.size(), &buffer, user_data);
    if (result != RAC_SUCCESS) {
        *out_error =
            buffer.error_message != nullptr ? buffer.error_message : "host callback failed";
        rac_proto_buffer_free(&buffer);
        return result;
    }

    const bool parsed = out_result->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    if (!parsed) {
        *out_error = "host callback returned an unreadable result";
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

/// Shared by kToolCall and kPackNode: a wired port wins over a configured
/// expression, and a required port with neither is an error. Arguments
/// configured under names outside the declared ports still resolve, which
/// keeps documents saved before ports existed running.
bool resolve_port_arguments(
    const google::protobuf::RepeatedPtrField<runanywhere::v1::ToolArgumentPort>& ports,
    const google::protobuf::Map<std::string, std::string>& configured,
    const std::map<std::string, std::vector<WorkflowItem>>& by_port,
    const ExpressionContext& context, json* out_arguments, std::string* out_error) {
    json& arguments = *out_arguments;

    const auto assign_expression = [&](const std::string& name,
                                       const std::string& expression) -> bool {
        std::string value;
        if (!resolve(expression, context, &value, out_error))
            return false;
        json parsed = json::parse(value, nullptr, false);
        arguments[name] = parsed.is_discarded() ? json(value) : parsed;
        return true;
    };

    for (const auto& port : ports) {
        auto fed = by_port.find(port.name());
        if (fed != by_port.end() && !fed->second.empty()) {
            if (fed->second.size() == 1) {
                arguments[port.name()] = parse_or_empty(fed->second.front().json());
            } else {
                json list = json::array();
                for (const WorkflowItem& item : fed->second)
                    list.push_back(parse_or_empty(item.json()));
                arguments[port.name()] = std::move(list);
            }
            continue;
        }

        auto fallback = configured.find(port.name());
        if (fallback != configured.end()) {
            if (!assign_expression(port.name(), fallback->second))
                return false;
        } else if (port.required()) {
            *out_error = "argument '" + port.name() + "' has no connection and no configured value";
            return false;
        }
    }

    for (const auto& [name, expression] : configured) {
        if (arguments.contains(name))
            continue;
        bool declared = false;
        for (const auto& port : ports) {
            if (port.name() == name) {
                declared = true;
                break;
            }
        }
        if (declared)
            continue;
        if (!assign_expression(name, expression))
            return false;
    }
    return true;
}

rac_result_t run_tool_call(const WorkflowNode& node, const NodeInputs& inputs,
                           const ExpressionContext& context, const std::string& run_id,
                           NodeExecution* out, std::string* out_error) {
    const auto& config = node.tool_call();
    json arguments = json::object();
    if (!resolve_port_arguments(config.ports(), config.arguments(), inputs.by_port, context,
                                &arguments, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    runanywhere::v1::ToolInvocation invocation;
    invocation.set_run_id(run_id);
    invocation.set_node_id(node.id());
    invocation.set_tool_name(config.tool_name());
    invocation.set_arguments_json(arguments.dump());

    // A tool registered in commons is answered here, exactly as the
    // tool-calling run loop does it. Without this the host callback is the only
    // path, and that callback reaches a binding's own registry — so a native
    // provider like web_research is dispatchable from chat and invisible from a
    // workflow, which is the same tool failing in one place and not the other.
    runanywhere::v1::ToolInvocationResult result;
    bool handled_by_provider = false;
    if (rac::llm::tool_calling::provider_owns(config.tool_name())) {
        runanywhere::v1::ToolCall call;
        call.set_id(node.id());
        call.set_name(config.tool_name());
        call.set_arguments_json(invocation.arguments_json());

        runanywhere::v1::ToolResult tool_result;
        if (rac::llm::tool_calling::execute_via_provider(call, 0, nullptr, {}, std::string(),
                                                         &tool_result)) {
            if (tool_result.is_error()) {
                *out_error = tool_result.error();
                return RAC_ERROR_PROCESSING_FAILED;
            }
            result.set_result_json(tool_result.result_json());
            handled_by_provider = true;
        }
    }

    // Keyed on whether a provider answered, not on whether the payload is
    // non-empty: a tool that legitimately returns nothing would otherwise fall
    // through and fail against a host callback that was never meant to see it.
    if (!handled_by_provider) {
        const rac_agent_host_callbacks_t callbacks = host_callbacks();
        const rac_result_t status =
            invoke_host(callbacks.invoke_tool, callbacks.user_data, invocation, &result,
                        "no tool callback is registered, so Tool Call nodes cannot run", out_error);
        if (status != RAC_SUCCESS)
            return status;
    }

    if (result.has_error()) {
        *out_error = result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json body = parse_or_empty(result.result_json());
    out->items.push_back(text_item(body));
    return RAC_SUCCESS;
}

rac_result_t run_code(const WorkflowNode& node, const std::vector<WorkflowItem>& inputs,
                      const std::string& run_id, NodeExecution* out, std::string* out_error) {
    json input_items = json::array();
    for (const WorkflowItem& item : inputs)
        input_items.push_back(parse_or_empty(item.json()));

    runanywhere::v1::CodeInvocation invocation;
    invocation.set_run_id(run_id);
    invocation.set_node_id(node.id());
    invocation.set_source(node.code().source());
    invocation.set_input_items_json(input_items.dump());

    const rac_agent_host_callbacks_t callbacks = host_callbacks();
    runanywhere::v1::CodeInvocationResult result;
    const rac_result_t status =
        invoke_host(callbacks.evaluate_code, callbacks.user_data, invocation, &result,
                    "no code callback is registered, so Code nodes cannot run", out_error);
    if (status != RAC_SUCCESS)
        return status;

    if (result.has_error()) {
        *out_error = result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json produced = json::parse(result.output_items_json(), nullptr, false);
    if (produced.is_discarded()) {
        *out_error = "Code node did not return valid JSON";
        return RAC_ERROR_DECODING_ERROR;
    }

    if (produced.is_array()) {
        for (const json& entry : produced)
            out->items.push_back(text_item(entry));
    } else {
        out->items.push_back(text_item(produced));
    }
    return RAC_SUCCESS;
}

/// A script pack gains no reach a Code node does not already have: it goes
/// through the exact same host callback, with the pack node's resolved
/// arguments as its one input item instead of the raw incoming item stream.
rac_result_t run_script_pack(const runanywhere::v1::NodePack& pack, const WorkflowNode& node,
                             const json& arguments, const std::string& run_id, NodeExecution* out,
                             std::string* out_error) {
    json input_items = json::array();
    input_items.push_back(arguments);

    runanywhere::v1::CodeInvocation invocation;
    invocation.set_run_id(run_id);
    invocation.set_node_id(node.id());
    invocation.set_source(pack.script().source());
    invocation.set_input_items_json(input_items.dump());

    const rac_agent_host_callbacks_t callbacks = host_callbacks();
    runanywhere::v1::CodeInvocationResult result;
    const rac_result_t status =
        invoke_host(callbacks.evaluate_code, callbacks.user_data, invocation, &result,
                    "no code callback is registered, so script node packs cannot run", out_error);
    if (status != RAC_SUCCESS)
        return status;

    if (result.has_error()) {
        *out_error = result.error().message();
        return RAC_ERROR_PROCESSING_FAILED;
    }

    json produced = json::parse(result.output_items_json(), nullptr, false);
    if (produced.is_discarded()) {
        *out_error = "pack script did not return valid JSON";
        return RAC_ERROR_DECODING_ERROR;
    }

    if (produced.is_array()) {
        for (const json& entry : produced)
            out->items.push_back(text_item(entry));
    } else {
        out->items.push_back(text_item(produced));
    }
    return RAC_SUCCESS;
}

/// Runs a composite pack's subgraph inline, the way the runner's loop body
/// runs: each node executes in the subgraph's own topological order, wired
/// through the subgraph's own edges. The entry node's output is seeded with
/// the pack node's resolved arguments rather than whatever that node would
/// normally produce; the exit node's output becomes the pack node's output.
rac_result_t run_composite_pack(const runanywhere::v1::NodePack& pack, const WorkflowNode& node,
                                const json& arguments, const std::string& run_id,
                                const std::atomic<bool>* cancelled, NodeExecution* out,
                                std::string* out_error, std::vector<std::string>* pack_stack) {
    const auto& composite = pack.composite();
    const WorkflowDocument& graph = composite.graph();
    const std::string& pack_id = node.pack_node().pack_id();

    const std::vector<std::string> order = topological_order(graph);
    if (order.empty() && graph.nodes_size() > 0) {
        *out_error = "pack '" + pack_id + "' subgraph contains a cycle";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::string entry_id = composite.entry_node_id();
    if (entry_id.empty()) {
        for (const WorkflowNode& candidate : graph.nodes()) {
            if (is_trigger(candidate)) {
                entry_id = candidate.id();
                break;
            }
        }
    }
    if (entry_id.empty() && graph.nodes_size() > 0) {
        *out_error = "pack '" + pack_id + "' composite subgraph has no entry point";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::string exit_id = composite.exit_node_id();
    if (exit_id.empty() && !order.empty())
        exit_id = order.back();

    WorkflowItem seed;
    seed.set_json(arguments.dump());
    const std::vector<WorkflowItem> carried = {seed};

    ExpressionContext local_context;
    std::unordered_map<std::string, std::vector<WorkflowItem>> port_outputs;

    for (const std::string& node_id : order) {
        if (cancelled != nullptr && cancelled->load(std::memory_order_relaxed)) {
            *out_error = "pack '" + pack_id + "' execution was cancelled";
            return RAC_ERROR_CANCELLED;
        }

        const WorkflowNode* current = nullptr;
        for (const WorkflowNode& candidate : graph.nodes()) {
            if (candidate.id() == node_id) {
                current = &candidate;
                break;
            }
        }
        if (current == nullptr)
            continue;

        NodeExecution execution;
        if (node_id == entry_id) {
            execution.items = carried;
        } else {
            NodeInputs subgraph_inputs;
            for (const auto& edge : graph.edges()) {
                if (edge.to_node() != node_id)
                    continue;
                auto found = port_outputs.find(edge.from_node() + ":" + edge.from_port());
                if (found == port_outputs.end())
                    continue;
                subgraph_inputs.items.insert(subgraph_inputs.items.end(), found->second.begin(),
                                             found->second.end());
                auto& per_port = subgraph_inputs.by_port[edge.to_port()];
                per_port.insert(per_port.end(), found->second.begin(), found->second.end());
            }

            std::string node_error;
            const rac_result_t status =
                execute_node(*current, subgraph_inputs, local_context, run_id, cancelled,
                             &execution, &node_error, pack_stack);
            if (status != RAC_SUCCESS) {
                *out_error =
                    "pack '" + pack_id + "' subgraph node '" + node_id + "' failed: " + node_error;
                return status;
            }
        }

        port_outputs[node_id + ":" + execution.port] = execution.items;
        if (!execution.secondary_port.empty())
            port_outputs[node_id + ":" + execution.secondary_port] = execution.secondary_items;
        if (!current->name().empty()) {
            std::vector<std::string> bodies;
            bodies.reserve(execution.items.size());
            for (const WorkflowItem& item : execution.items)
                bodies.push_back(item.json());
            local_context.node_outputs[current->name()] = bodies;
        }

        if (node_id == exit_id)
            out->items = execution.items;
    }

    return RAC_SUCCESS;
}

rac_result_t run_pack_node(const WorkflowNode& node, const NodeInputs& inputs,
                           const ExpressionContext& context, const std::string& run_id,
                           const std::atomic<bool>* cancelled, NodeExecution* out,
                           std::string* out_error, std::vector<std::string>* pack_stack) {
    const auto& config = node.pack_node();
    if (config.missing()) {
        *out_error = "pack '" + config.pack_id() + "' is not installed on this machine";
        return RAC_ERROR_NOT_FOUND;
    }

    std::vector<std::string> local_stack;
    if (pack_stack == nullptr)
        pack_stack = &local_stack;

    if (pack_recursion_would_occur(*pack_stack, config.pack_id())) {
        *out_error = "pack '" + config.pack_id() +
                     "' recursively references itself through a composite subgraph";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    runanywhere::v1::NodePack pack;
    const rac_result_t loaded = store_load_pack(config.pack_id(), &pack);
    if (loaded != RAC_SUCCESS) {
        *out_error = "pack '" + config.pack_id() + "' could not be loaded";
        return loaded;
    }

    json arguments = json::object();
    if (!resolve_port_arguments(config.ports(), config.arguments(), inputs.by_port, context,
                                &arguments, out_error))
        return RAC_ERROR_INVALID_CONFIGURATION;

    pack_stack->push_back(config.pack_id());
    rac_result_t status;
    if (pack.has_script()) {
        status = run_script_pack(pack, node, arguments, run_id, out, out_error);
    } else if (pack.has_composite()) {
        status = run_composite_pack(pack, node, arguments, run_id, cancelled, out, out_error,
                                    pack_stack);
    } else {
        *out_error = "pack '" + config.pack_id() + "' declares no implementation";
        status = RAC_ERROR_INVALID_CONFIGURATION;
    }
    pack_stack->pop_back();

    if (status == RAC_SUCCESS)
        out->port = config.outputs_size() > 0 ? config.outputs(0) : "out";
    return status;
}

}  // namespace

bool pack_recursion_would_occur(const std::vector<std::string>& pack_stack,
                                const std::string& pack_id) {
    if (pack_stack.size() >= kMaxPackDepth)
        return true;
    return std::find(pack_stack.begin(), pack_stack.end(), pack_id) != pack_stack.end();
}

rac_result_t execute_node(const WorkflowNode& node, const NodeInputs& inputs,
                          const ExpressionContext& context, const std::string& run_id,
                          const std::atomic<bool>* cancelled, NodeExecution* out_execution,
                          std::string* out_error, std::vector<std::string>* pack_stack) {
    switch (node.config_case()) {
        case WorkflowNode::kManualTrigger:
            return run_manual_trigger(node, out_execution, out_error);
        case WorkflowNode::kScheduleTrigger:
            return run_schedule_trigger(node, out_execution, out_error);
        case WorkflowNode::kSetTransform:
            return run_set_transform(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kCondition:
            return run_condition(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kMerge:
            return run_merge(node, inputs, out_execution);
        case WorkflowNode::kFilter:
            return run_filter(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kSplitOut:
            return run_split_out(node, context, out_execution, out_error);
        case WorkflowNode::kAggregate:
            return run_aggregate(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kWait:
            return run_wait(node, inputs.items, cancelled, out_execution);
        case WorkflowNode::kFileRead:
            return run_file_read(node, context, out_execution, out_error);
        case WorkflowNode::kFileWrite:
            return run_file_write(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kLlmGenerate:
            return run_llm_generate(node, context, out_execution, out_error);
        case WorkflowNode::kLlmStructured:
            return run_llm_structured(node, context, out_execution, out_error);
        case WorkflowNode::kVision:
            return run_vision(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kEmbed:
            return run_embed(node, context, out_execution, out_error);
        case WorkflowNode::kRerank:
            return run_rerank(node, context, out_execution, out_error);
        case WorkflowNode::kTranscribe:
            return run_transcribe(node, inputs.items, out_execution, out_error);
        case WorkflowNode::kSpeak:
            return run_speak(node, context, out_execution, out_error);
        case WorkflowNode::kDetectVoice:
            return run_detect_voice(node, inputs.items, out_execution, out_error);
        case WorkflowNode::kDiarize:
            return run_diarize(node, inputs.items, out_execution, out_error);
        case WorkflowNode::kSegment:
            return run_segment(node, inputs.items, context, out_execution, out_error);
        case WorkflowNode::kRagQuery:
            return run_rag_query(node, context, out_execution, out_error);
        case WorkflowNode::kRagIngest:
            return run_rag_ingest(node, context, out_execution, out_error);
        case WorkflowNode::kLoadModel:
            return run_load_model(node, out_execution, out_error);
        case WorkflowNode::kHttpRequest:
            return run_http_request(node, context, out_execution, out_error);
        case WorkflowNode::kToolCall:
            return run_tool_call(node, inputs, context, run_id, out_execution, out_error);
        case WorkflowNode::kCode:
            return run_code(node, inputs.items, run_id, out_execution, out_error);
        case WorkflowNode::kPackNode:
            return run_pack_node(node, inputs, context, run_id, cancelled, out_execution, out_error,
                                 pack_stack);
        case WorkflowNode::kLoopOverItems:
            *out_error = "loop nodes are scheduled by the runner, not executed directly";
            return RAC_ERROR_INVALID_ARGUMENT;
        case WorkflowNode::CONFIG_NOT_SET:
            *out_error = "node has no configuration set";
            return RAC_ERROR_INVALID_CONFIGURATION;
    }
    *out_error = "unknown node type";
    return RAC_ERROR_INVALID_CONFIGURATION;
}

}  // namespace rac::agent
