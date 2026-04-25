/**
 * @file diffusion_coreml_backend.mm
 * @brief Objective-C++ bridge to Apple CoreML for the diffusion engine.
 *
 * Uses Foundation + CoreML directly (no external dependencies). Mirrors
 * the public C ABI declared in diffusion_coreml_backend.h.
 */

#include "diffusion_coreml_backend.h"

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac_runtime_coreml.h"

namespace {
constexpr const char* kLogCat = "Diffusion.CoreML";

char* dup_error_message(const char* msg) {
    if (!msg) return nullptr;
    const size_t n = std::strlen(msg) + 1;
    char* out = static_cast<char*>(std::malloc(n));
    if (out) std::memcpy(out, msg, n);
    return out;
}

rac_result_t set_error(rac_diffusion_result_t* out_result,
                       rac_result_t code,
                       const char* message) {
    if (out_result) {
        out_result->error_code = code;
        out_result->error_message = dup_error_message(message);
    }
    RAC_LOG_ERROR(kLogCat, "%s", message ? message : "CoreML diffusion error");
    return code;
}

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}
}  // namespace

struct CoreMLSDIOConfig {
    std::unordered_map<std::string, std::string> values;

    std::string get(const std::string& key, const std::string& fallback) const {
        auto it = values.find(key);
        return it == values.end() || it->second.empty() ? fallback : it->second;
    }
};

struct rac_diffusion_coreml_impl {
    /// Strong refs to the MLModels loaded during initialize(). Typed as
    /// NSObject* instead of MLModel* so the struct header can be used
    /// from plain C++ via the .h — actual typing lives in this .mm.
    MLModel* text_encoder = nil;
    MLModel* unet         = nil;
    MLModel* vae_decoder  = nil;
    MLModel* safety_checker = nil;  // Optional.

    std::string model_path;
    std::string model_id;
    rac_diffusion_config_t config{};
    CoreMLSDIOConfig io_config;
    std::unordered_map<std::string, int32_t> vocab;
    int32_t bos_token_id = 49406;
    int32_t eos_token_id = 49407;
    int32_t pad_token_id = 49407;
    int32_t max_vocab_id = 49407;
    bool vocab_loaded = false;
    std::atomic<bool> initialized{false};
    std::atomic<bool> cancel_requested{false};
    mutable std::mutex mtx;
};

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

namespace {

NSString* ns(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string to_std(NSString* value) {
    return value ? std::string([value UTF8String]) : std::string();
}

void insert_config_value(CoreMLSDIOConfig& config, NSString* key, id value) {
    if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
        return;
    }
    config.values[to_std(key)] = to_std(static_cast<NSString*>(value));
}

void load_config_dict(CoreMLSDIOConfig& config, NSDictionary* dict, NSString* prefix = nil) {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return;
    }
    for (id raw_key in dict) {
        id value = [dict objectForKey:raw_key];
        if (![raw_key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString* key = prefix
            ? [NSString stringWithFormat:@"%@.%@", prefix, static_cast<NSString*>(raw_key)]
            : static_cast<NSString*>(raw_key);
        if ([value isKindOfClass:[NSDictionary class]]) {
            load_config_dict(config, static_cast<NSDictionary*>(value), key);
        } else {
            insert_config_value(config, key, value);
        }
    }
}

void load_json_config(CoreMLSDIOConfig& config, NSString* model_dir) {
    NSArray<NSString*>* candidates = @[
        @"diffusion_coreml_config.json",
        @"coreml_config.json",
        @"model_config.json"
    ];
    for (NSString* filename in candidates) {
        NSString* path = [model_dir stringByAppendingPathComponent:filename];
        NSData* data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            continue;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            load_config_dict(config, static_cast<NSDictionary*>(json));
            RAC_LOG_INFO(kLogCat, "Loaded CoreML diffusion IO config: %s",
                         [path UTF8String]);
        }
    }
}

void load_model_metadata_config(CoreMLSDIOConfig& config, MLModel* model) {
    NSDictionary* metadata = model.modelDescription.metadata;
    for (id raw_key in metadata) {
        id value = [metadata objectForKey:raw_key];
        if (![raw_key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString* key = static_cast<NSString*>(raw_key);
        if ([value isKindOfClass:[NSDictionary class]]) {
            load_config_dict(config, static_cast<NSDictionary*>(value), key);
        } else {
            insert_config_value(config, key, value);
        }
        NSString* prefix = @"runanywhere.diffusion.";
        if ([key hasPrefix:prefix]) {
            NSString* stripped = [key substringFromIndex:[prefix length]];
            insert_config_value(config, stripped, value);
        }
    }
}

NSDictionary<NSString*, MLFeatureDescription*>* descriptions(MLModel* model, bool input) {
    return input ? model.modelDescription.inputDescriptionsByName
                 : model.modelDescription.outputDescriptionsByName;
}

MLFeatureDescription* feature_desc(MLModel* model, bool input, NSString* name) {
    return [descriptions(model, input) objectForKey:name];
}

NSString* resolve_feature_name(MLModel* model,
                               bool input,
                               const CoreMLSDIOConfig& config,
                               const std::vector<std::string>& config_keys,
                               const std::vector<std::string>& candidates,
                               MLFeatureType expected_type,
                               NSUInteger fallback_index = 0) {
    NSDictionary<NSString*, MLFeatureDescription*>* descs = descriptions(model, input);
    for (const std::string& key : config_keys) {
        std::string configured = config.get(key, "");
        if (!configured.empty()) {
            NSString* name = ns(configured);
            MLFeatureDescription* desc = [descs objectForKey:name];
            if (desc && (expected_type == MLFeatureTypeInvalid || desc.type == expected_type)) {
                return name;
            }
        }
    }

    for (const std::string& candidate : candidates) {
        NSString* name = ns(candidate);
        MLFeatureDescription* desc = [descs objectForKey:name];
        if (desc && (expected_type == MLFeatureTypeInvalid || desc.type == expected_type)) {
            return name;
        }
    }

    NSUInteger seen = 0;
    for (NSString* name in descs) {
        MLFeatureDescription* desc = [descs objectForKey:name];
        if (expected_type != MLFeatureTypeInvalid && desc.type != expected_type) {
            continue;
        }
        if (seen == fallback_index) {
            return name;
        }
        ++seen;
    }
    return nil;
}

std::vector<NSInteger> ns_shape_to_vector(NSArray<NSNumber*>* shape) {
    std::vector<NSInteger> out;
    for (NSNumber* dim in shape) {
        NSInteger value = [dim integerValue];
        out.push_back(value > 0 ? value : 1);
    }
    return out;
}

std::vector<NSInteger> multiarray_shape(MLFeatureDescription* desc,
                                        const std::vector<NSInteger>& fallback) {
    if (!desc || desc.type != MLFeatureTypeMultiArray || !desc.multiArrayConstraint) {
        return fallback;
    }
    std::vector<NSInteger> shape = ns_shape_to_vector(desc.multiArrayConstraint.shape);
    return shape.empty() ? fallback : shape;
}

MLMultiArrayDataType multiarray_data_type(MLFeatureDescription* desc,
                                          MLMultiArrayDataType fallback) {
    if (!desc || desc.type != MLFeatureTypeMultiArray || !desc.multiArrayConstraint) {
        return fallback;
    }
    return desc.multiArrayConstraint.dataType;
}

NSArray<NSNumber*>* make_shape(const std::vector<NSInteger>& shape) {
    NSMutableArray<NSNumber*>* out = [NSMutableArray arrayWithCapacity:shape.size()];
    for (NSInteger dim : shape) {
        [out addObject:@(std::max<NSInteger>(1, dim))];
    }
    return out;
}

size_t shape_count(const std::vector<NSInteger>& shape) {
    size_t count = 1;
    for (NSInteger dim : shape) {
        count *= static_cast<size_t>(std::max<NSInteger>(1, dim));
    }
    return count;
}

MLMultiArray* make_multiarray(const std::vector<NSInteger>& shape,
                              MLMultiArrayDataType data_type) {
    NSError* err = nil;
    MLMultiArray* array = [[MLMultiArray alloc] initWithShape:make_shape(shape)
                                                     dataType:data_type
                                                        error:&err];
    if (!array) {
        RAC_LOG_ERROR(kLogCat, "MLMultiArray allocation failed: %s",
                      err ? [[err localizedDescription] UTF8String] : "unknown");
    }
    return array;
}

float array_get(MLMultiArray* array, size_t index) {
    if (!array || index >= static_cast<size_t>(array.count)) {
        return 0.0f;
    }
    return [[array objectAtIndexedSubscript:index] floatValue];
}

void array_set(MLMultiArray* array, size_t index, float value) {
    if (!array || index >= static_cast<size_t>(array.count)) {
        return;
    }
    [array setObject:@(value) atIndexedSubscript:index];
}

void array_set_int(MLMultiArray* array, size_t index, int32_t value) {
    if (!array || index >= static_cast<size_t>(array.count)) {
        return;
    }
    [array setObject:@(value) atIndexedSubscript:index];
}

bool run_prediction(MLModel* model,
                    NSDictionary<NSString*, MLFeatureValue*>* features,
                    id<MLFeatureProvider>* out_provider,
                    std::string* out_error) {
    NSError* err = nil;
    MLDictionaryFeatureProvider* provider =
        [[MLDictionaryFeatureProvider alloc] initWithDictionary:features error:&err];
    if (!provider) {
        if (out_error) {
            *out_error = err ? [[err localizedDescription] UTF8String]
                             : "failed to create feature provider";
        }
        return false;
    }

    id<MLFeatureProvider> prediction = [model predictionFromFeatures:provider error:&err];
    if (!prediction) {
        if (out_error) {
            *out_error = err ? [[err localizedDescription] UTF8String]
                             : "CoreML prediction failed";
        }
        return false;
    }
    *out_provider = prediction;
    return true;
}

MLMultiArray* output_multiarray(id<MLFeatureProvider> provider,
                               MLModel* model,
                               const CoreMLSDIOConfig& config,
                               const std::vector<std::string>& config_keys,
                               const std::vector<std::string>& candidates) {
    NSString* name = resolve_feature_name(model, /*input=*/false, config, config_keys,
                                          candidates, MLFeatureTypeMultiArray);
    if (!name) {
        return nil;
    }
    MLFeatureValue* value = [provider featureValueForName:name];
    return value.type == MLFeatureTypeMultiArray ? value.multiArrayValue : nil;
}

std::string lowercase(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return text;
}

uint32_t fnv1a(const std::string& value) {
    uint32_t hash = 2166136261u;
    for (unsigned char c : value) {
        hash ^= c;
        hash *= 16777619u;
    }
    return hash;
}

void load_vocab(rac_diffusion_coreml_impl* impl, NSString* model_dir) {
    NSArray<NSString*>* candidates = @[
        [model_dir stringByAppendingPathComponent:@"vocab.json"],
        [[model_dir stringByAppendingPathComponent:@"tokenizer"]
            stringByAppendingPathComponent:@"vocab.json"]
    ];
    NSString* vocab_path = nil;
    for (NSString* path in candidates) {
        if (rac_coreml_file_exists(path)) {
            vocab_path = path;
            break;
        }
    }
    if (!vocab_path) {
        RAC_LOG_WARNING(kLogCat,
                        "vocab.json not found; using deterministic fallback prompt tokens");
        return;
    }

    NSData* data = [NSData dataWithContentsOfFile:vocab_path];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        RAC_LOG_WARNING(kLogCat, "Could not parse vocab.json: %s", [vocab_path UTF8String]);
        return;
    }

    NSDictionary* dict = static_cast<NSDictionary*>(json);
    for (id raw_key in dict) {
        id raw_value = [dict objectForKey:raw_key];
        if (![raw_key isKindOfClass:[NSString class]] || ![raw_value isKindOfClass:[NSNumber class]]) {
            continue;
        }
        int32_t token_id = [static_cast<NSNumber*>(raw_value) intValue];
        impl->vocab[to_std(static_cast<NSString*>(raw_key))] = token_id;
        impl->max_vocab_id = std::max(impl->max_vocab_id, token_id);
    }

    auto find_special = [&](const char* token, int32_t fallback) {
        auto it = impl->vocab.find(token);
        return it == impl->vocab.end() ? fallback : it->second;
    };
    impl->bos_token_id = find_special("<|startoftext|>", impl->bos_token_id);
    impl->eos_token_id = find_special("<|endoftext|>", impl->eos_token_id);
    impl->pad_token_id = impl->eos_token_id;
    impl->vocab_loaded = !impl->vocab.empty();
    RAC_LOG_INFO(kLogCat, "Loaded diffusion tokenizer vocab: %s (%zu tokens)",
                 [vocab_path UTF8String], impl->vocab.size());
}

std::vector<std::string> split_prompt_words(const char* prompt) {
    std::vector<std::string> words;
    std::string current;
    const std::string text = prompt ? prompt : "";
    for (unsigned char c : text) {
        if (std::isalnum(c)) {
            current.push_back(static_cast<char>(std::tolower(c)));
        } else {
            if (!current.empty()) {
                words.push_back(current);
                current.clear();
            }
            if (!std::isspace(c)) {
                words.emplace_back(1, static_cast<char>(c));
            }
        }
    }
    if (!current.empty()) {
        words.push_back(current);
    }
    return words;
}

int32_t lookup_token(const rac_diffusion_coreml_impl* impl,
                     const std::string& token,
                     bool end_of_word) {
    if (impl->vocab_loaded) {
        const std::string lower = lowercase(token);
        const std::string eow = lower + "</w>";
        auto it = end_of_word ? impl->vocab.find(eow) : impl->vocab.find(lower);
        if (it != impl->vocab.end()) {
            return it->second;
        }
        it = impl->vocab.find(lower);
        if (it != impl->vocab.end()) {
            return it->second;
        }
    }

    const uint32_t span = static_cast<uint32_t>(std::max(1, impl->max_vocab_id - 2));
    return 2 + static_cast<int32_t>(fnv1a(token) % span);
}

std::vector<int32_t> encode_prompt_tokens(const rac_diffusion_coreml_impl* impl,
                                          const char* prompt,
                                          size_t token_count) {
    std::vector<int32_t> ids(token_count, impl->pad_token_id);
    if (token_count == 0) {
        return ids;
    }
    ids[0] = impl->bos_token_id;
    size_t cursor = 1;
    for (const std::string& word : split_prompt_words(prompt)) {
        if (cursor + 1 >= token_count) {
            break;
        }
        ids[cursor++] = lookup_token(impl, word, /*end_of_word=*/true);
    }
    if (cursor < token_count) {
        ids[cursor] = impl->eos_token_id;
    }
    return ids;
}

rac_result_t encode_text(rac_diffusion_coreml_impl* impl,
                         const char* prompt,
                         MLMultiArray** out_embeddings,
                         rac_diffusion_result_t* out_result) {
    NSString* string_input = resolve_feature_name(
        impl->text_encoder, /*input=*/true, impl->io_config,
        {"text_encoder.prompt", "text.prompt", "prompt"},
        {"prompt", "text"}, MLFeatureTypeString);

    NSMutableDictionary<NSString*, MLFeatureValue*>* features = [NSMutableDictionary dictionary];
    if (string_input) {
        [features setObject:[MLFeatureValue featureValueWithString:ns(prompt ? prompt : "")]
                     forKey:string_input];
    } else {
        NSString* ids_name = resolve_feature_name(
            impl->text_encoder, /*input=*/true, impl->io_config,
            {"text_encoder.input_ids", "text.input_ids", "input_ids"},
            {"input_ids"}, MLFeatureTypeMultiArray);
        if (!ids_name) {
            return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                             "Unsupported TextEncoder layout: no prompt string or input_ids input");
        }
        MLFeatureDescription* ids_desc = feature_desc(impl->text_encoder, true, ids_name);
        std::vector<NSInteger> ids_shape = multiarray_shape(ids_desc, {1, 77});
        const size_t ids_count = shape_count(ids_shape);
        const size_t seq_len = ids_shape.empty() ? ids_count : static_cast<size_t>(ids_shape.back());
        MLMultiArray* ids_array =
            make_multiarray(ids_shape, multiarray_data_type(ids_desc, MLMultiArrayDataTypeInt32));
        if (!ids_array) {
            return set_error(out_result, RAC_ERROR_OUT_OF_MEMORY,
                             "Could not allocate TextEncoder input_ids");
        }

        std::vector<int32_t> token_ids = encode_prompt_tokens(impl, prompt, seq_len);
        const size_t batches = seq_len == 0 ? 1 : ids_count / seq_len;
        for (size_t b = 0; b < batches; ++b) {
            for (size_t i = 0; i < seq_len; ++i) {
                array_set_int(ids_array, b * seq_len + i, token_ids[i]);
            }
        }
        [features setObject:[MLFeatureValue featureValueWithMultiArray:ids_array] forKey:ids_name];

        NSString* mask_name = resolve_feature_name(
            impl->text_encoder, /*input=*/true, impl->io_config,
            {"text_encoder.attention_mask", "text.attention_mask", "attention_mask"},
            {"attention_mask"}, MLFeatureTypeMultiArray);
        if (mask_name) {
            MLFeatureDescription* mask_desc = feature_desc(impl->text_encoder, true, mask_name);
            std::vector<NSInteger> mask_shape = multiarray_shape(mask_desc, ids_shape);
            MLMultiArray* mask_array =
                make_multiarray(mask_shape, multiarray_data_type(mask_desc, MLMultiArrayDataTypeInt32));
            if (!mask_array) {
                return set_error(out_result, RAC_ERROR_OUT_OF_MEMORY,
                                 "Could not allocate TextEncoder attention_mask");
            }
            for (size_t i = 0; i < static_cast<size_t>(mask_array.count); ++i) {
                array_set_int(mask_array, i, token_ids[i % seq_len] == impl->pad_token_id ? 0 : 1);
            }
            [features setObject:[MLFeatureValue featureValueWithMultiArray:mask_array]
                         forKey:mask_name];
        }
    }

    id<MLFeatureProvider> prediction = nil;
    std::string error;
    if (!run_prediction(impl->text_encoder, features, &prediction, &error)) {
        return set_error(out_result, RAC_ERROR_INFERENCE_FAILED,
                         ("TextEncoder prediction failed: " + error).c_str());
    }
    MLMultiArray* embeddings = output_multiarray(
        prediction, impl->text_encoder, impl->io_config,
        {"text_encoder.output", "text.output"},
        {"last_hidden_state", "hidden_states", "encoder_hidden_states", "text_embeddings"});
    if (!embeddings) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "Unsupported TextEncoder layout: no multi-array embeddings output");
    }
    *out_embeddings = embeddings;
    return RAC_SUCCESS;
}

struct LatentShape {
    NSInteger batch = 1;
    NSInteger channels = 4;
    NSInteger height = 64;
    NSInteger width = 64;
};

LatentShape resolve_latent_shape(MLFeatureDescription* sample_desc,
                                 int32_t image_width,
                                 int32_t image_height) {
    std::vector<NSInteger> shape =
        multiarray_shape(sample_desc, {1, 4, std::max<int32_t>(1, image_height / 8),
                                       std::max<int32_t>(1, image_width / 8)});
    LatentShape out;
    if (shape.size() >= 4) {
        out.batch = shape[shape.size() - 4];
        out.channels = shape[shape.size() - 3];
        out.height = shape[shape.size() - 2];
        out.width = shape[shape.size() - 1];
    }
    if (out.batch <= 0) out.batch = 1;
    if (out.channels <= 0) out.channels = 4;
    if (out.height <= 0) out.height = std::max<int32_t>(1, image_height / 8);
    if (out.width <= 0) out.width = std::max<int32_t>(1, image_width / 8);
    return out;
}

double standard_normal(uint64_t& state) {
    auto next_u32 = [&]() {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        return static_cast<uint32_t>((state * 2685821657736338717ULL) >> 32);
    };
    const double u1 = (static_cast<double>(next_u32()) + 1.0) /
                      (static_cast<double>(std::numeric_limits<uint32_t>::max()) + 2.0);
    const double u2 = (static_cast<double>(next_u32()) + 1.0) /
                      (static_cast<double>(std::numeric_limits<uint32_t>::max()) + 2.0);
    return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * M_PI * u2);
}

std::vector<float> initial_latents(size_t count, int64_t seed) {
    uint64_t state = seed >= 0 ? static_cast<uint64_t>(seed) : 0x9e3779b97f4a7c15ULL;
    if (state == 0) {
        state = 0x6a09e667f3bcc909ULL;
    }
    std::vector<float> latents(count);
    for (float& value : latents) {
        value = static_cast<float>(standard_normal(state));
    }
    return latents;
}

std::vector<double> build_alpha_cumprod() {
    std::vector<double> alpha(1000);
    double product = 1.0;
    const double beta_start = 0.00085;
    const double beta_end = 0.012;
    for (size_t i = 0; i < alpha.size(); ++i) {
        const double t = static_cast<double>(i) / static_cast<double>(alpha.size() - 1);
        const double beta = std::pow(std::sqrt(beta_start) +
                                     t * (std::sqrt(beta_end) - std::sqrt(beta_start)), 2.0);
        product *= (1.0 - beta);
        alpha[i] = product;
    }
    return alpha;
}

MLFeatureValue* timestep_feature(MLFeatureDescription* desc, int32_t timestep) {
    if (desc && desc.type == MLFeatureTypeInt64) {
        return [MLFeatureValue featureValueWithInt64:timestep];
    }
    if (desc && desc.type == MLFeatureTypeDouble) {
        return [MLFeatureValue featureValueWithDouble:static_cast<double>(timestep)];
    }

    std::vector<NSInteger> shape = multiarray_shape(desc, {1});
    MLMultiArray* array = make_multiarray(shape, multiarray_data_type(desc, MLMultiArrayDataTypeInt32));
    if (!array) {
        return nil;
    }
    for (size_t i = 0; i < static_cast<size_t>(array.count); ++i) {
        array_set(array, i, static_cast<float>(timestep));
    }
    return [MLFeatureValue featureValueWithMultiArray:array];
}

MLMultiArray* make_batched_latents(const std::vector<float>& latents,
                                   const LatentShape& latent_shape,
                                   NSInteger batch,
                                   MLFeatureDescription* sample_desc) {
    std::vector<NSInteger> shape = multiarray_shape(sample_desc, {
        batch, latent_shape.channels, latent_shape.height, latent_shape.width
    });
    if (shape.size() >= 4) {
        shape[shape.size() - 4] = batch;
        shape[shape.size() - 3] = latent_shape.channels;
        shape[shape.size() - 2] = latent_shape.height;
        shape[shape.size() - 1] = latent_shape.width;
    }
    MLMultiArray* array = make_multiarray(shape, multiarray_data_type(sample_desc, MLMultiArrayDataTypeFloat32));
    if (!array) {
        return nil;
    }
    const size_t per_batch = latents.size();
    for (NSInteger b = 0; b < batch; ++b) {
        for (size_t i = 0; i < per_batch; ++i) {
            array_set(array, static_cast<size_t>(b) * per_batch + i, latents[i]);
        }
    }
    return array;
}

MLMultiArray* make_batched_embeddings(MLMultiArray* negative,
                                      MLMultiArray* positive,
                                      NSInteger batch,
                                      MLFeatureDescription* hidden_desc) {
    if (batch <= 1) {
        return positive;
    }
    std::vector<NSInteger> base_shape =
        multiarray_shape(hidden_desc, ns_shape_to_vector(positive.shape));
    if (!base_shape.empty()) {
        base_shape[0] = batch;
    }
    MLMultiArray* out = make_multiarray(base_shape,
        multiarray_data_type(hidden_desc, positive.dataType));
    if (!out) {
        return nil;
    }
    const size_t src_count = static_cast<size_t>(positive.count);
    if (src_count == 0) {
        return out;
    }
    for (NSInteger b = 0; b < batch; ++b) {
        MLMultiArray* source = (b == 0 && negative) ? negative : positive;
        for (size_t i = 0; i < src_count; ++i) {
            array_set(out, static_cast<size_t>(b) * src_count + i, array_get(source, i));
        }
    }
    return out;
}

rac_result_t predict_noise(rac_diffusion_coreml_impl* impl,
                           const std::vector<float>& latents,
                           const LatentShape& latent_shape,
                           int32_t timestep,
                           float guidance_scale,
                           MLMultiArray* prompt_embeddings,
                           MLMultiArray* negative_embeddings,
                           NSString* sample_name,
                           NSString* timestep_name,
                           NSString* hidden_name,
                           NSString* output_name,
                           std::vector<float>& out_noise,
                           rac_diffusion_result_t* out_result) {
    MLFeatureDescription* sample_desc = feature_desc(impl->unet, true, sample_name);
    MLFeatureDescription* timestep_desc = feature_desc(impl->unet, true, timestep_name);
    MLFeatureDescription* hidden_desc = feature_desc(impl->unet, true, hidden_name);

    const NSInteger batch = std::max<NSInteger>(1, latent_shape.batch);
    if (batch != 1 && batch != 2) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "Unsupported Unet layout: sample batch must be 1 or 2");
    }

    auto run_once = [&](MLMultiArray* embeddings, std::vector<float>& noise) -> rac_result_t {
        MLMultiArray* sample_array = make_batched_latents(latents, latent_shape, 1, sample_desc);
        MLMultiArray* hidden_array = make_batched_embeddings(nil, embeddings, 1, hidden_desc);
        MLFeatureValue* timestep_value = timestep_feature(timestep_desc, timestep);
        if (!sample_array || !hidden_array || !timestep_value) {
            return set_error(out_result, RAC_ERROR_OUT_OF_MEMORY,
                             "Could not allocate Unet inputs");
        }
        NSDictionary<NSString*, MLFeatureValue*>* features = @{
            sample_name: [MLFeatureValue featureValueWithMultiArray:sample_array],
            timestep_name: timestep_value,
            hidden_name: [MLFeatureValue featureValueWithMultiArray:hidden_array],
        };
        id<MLFeatureProvider> prediction = nil;
        std::string error;
        if (!run_prediction(impl->unet, features, &prediction, &error)) {
            return set_error(out_result, RAC_ERROR_INFERENCE_FAILED,
                             ("Unet prediction failed: " + error).c_str());
        }
        MLFeatureValue* value = [prediction featureValueForName:output_name];
        MLMultiArray* output = value.type == MLFeatureTypeMultiArray ? value.multiArrayValue : nil;
        if (!output) {
            return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                             "Unsupported Unet layout: output is not a multi-array");
        }
        noise.resize(latents.size());
        for (size_t i = 0; i < noise.size(); ++i) {
            noise[i] = array_get(output, i);
        }
        return RAC_SUCCESS;
    };

    if (batch == 1) {
        std::vector<float> cond;
        rac_result_t rc = run_once(prompt_embeddings, cond);
        if (rc != RAC_SUCCESS || guidance_scale <= 1.0f || !negative_embeddings) {
            out_noise = std::move(cond);
            return rc;
        }
        std::vector<float> uncond;
        rc = run_once(negative_embeddings, uncond);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
        out_noise.resize(cond.size());
        for (size_t i = 0; i < cond.size(); ++i) {
            out_noise[i] = uncond[i] + guidance_scale * (cond[i] - uncond[i]);
        }
        return RAC_SUCCESS;
    }

    MLMultiArray* sample_array = make_batched_latents(latents, latent_shape, batch, sample_desc);
    MLMultiArray* hidden_array =
        make_batched_embeddings(negative_embeddings, prompt_embeddings, batch, hidden_desc);
    MLFeatureValue* timestep_value = timestep_feature(timestep_desc, timestep);
    if (!sample_array || !hidden_array || !timestep_value) {
        return set_error(out_result, RAC_ERROR_OUT_OF_MEMORY,
                         "Could not allocate batched Unet inputs");
    }
    NSDictionary<NSString*, MLFeatureValue*>* features = @{
        sample_name: [MLFeatureValue featureValueWithMultiArray:sample_array],
        timestep_name: timestep_value,
        hidden_name: [MLFeatureValue featureValueWithMultiArray:hidden_array],
    };
    id<MLFeatureProvider> prediction = nil;
    std::string error;
    if (!run_prediction(impl->unet, features, &prediction, &error)) {
        return set_error(out_result, RAC_ERROR_INFERENCE_FAILED,
                         ("Unet prediction failed: " + error).c_str());
    }
    MLFeatureValue* value = [prediction featureValueForName:output_name];
    MLMultiArray* output = value.type == MLFeatureTypeMultiArray ? value.multiArrayValue : nil;
    if (!output || static_cast<size_t>(output.count) < latents.size() * 2) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "Unsupported Unet layout: batched output shape is incompatible");
    }
    out_noise.resize(latents.size());
    const size_t offset = latents.size();
    for (size_t i = 0; i < out_noise.size(); ++i) {
        const float uncond = array_get(output, i);
        const float cond = array_get(output, offset + i);
        out_noise[i] = uncond + guidance_scale * (cond - uncond);
    }
    return RAC_SUCCESS;
}

void ddim_step(std::vector<float>& latents,
               const std::vector<float>& noise,
               int32_t timestep,
               int32_t previous_timestep,
               const std::vector<double>& alpha_cumprod) {
    const double alpha_t = alpha_cumprod[std::clamp(timestep, 0, 999)];
    const double alpha_prev = previous_timestep >= 0
        ? alpha_cumprod[std::clamp(previous_timestep, 0, 999)]
        : 1.0;
    const double sqrt_alpha_t = std::sqrt(alpha_t);
    const double sqrt_one_minus_alpha_t = std::sqrt(1.0 - alpha_t);
    const double sqrt_alpha_prev = std::sqrt(alpha_prev);
    const double sqrt_one_minus_alpha_prev = std::sqrt(1.0 - alpha_prev);

    for (size_t i = 0; i < latents.size(); ++i) {
        const double predicted_original =
            (static_cast<double>(latents[i]) - sqrt_one_minus_alpha_t * noise[i]) /
            std::max(1e-8, sqrt_alpha_t);
        latents[i] = static_cast<float>(
            sqrt_alpha_prev * predicted_original + sqrt_one_minus_alpha_prev * noise[i]);
    }
}

MLMultiArray* make_vae_latents(const std::vector<float>& latents,
                               const LatentShape& latent_shape,
                               MLFeatureDescription* latent_desc) {
    std::vector<NSInteger> shape = multiarray_shape(latent_desc, {
        1, latent_shape.channels, latent_shape.height, latent_shape.width
    });
    if (shape.size() >= 4) {
        shape[shape.size() - 4] = 1;
        shape[shape.size() - 3] = latent_shape.channels;
        shape[shape.size() - 2] = latent_shape.height;
        shape[shape.size() - 1] = latent_shape.width;
    }
    MLMultiArray* array = make_multiarray(shape, multiarray_data_type(latent_desc, MLMultiArrayDataTypeFloat32));
    if (!array) {
        return nil;
    }
    for (size_t i = 0; i < latents.size(); ++i) {
        array_set(array, i, latents[i] / 0.18215f);
    }
    return array;
}

bool convert_decoded_image(MLMultiArray* image,
                           uint8_t** out_rgba,
                           size_t* out_size,
                           int32_t* out_width,
                           int32_t* out_height) {
    if (!image || !out_rgba || !out_size || !out_width || !out_height) {
        return false;
    }
    std::vector<NSInteger> shape = ns_shape_to_vector(image.shape);
    if (shape.size() < 3) {
        return false;
    }

    bool nchw = false;
    NSInteger channels = 3;
    NSInteger height = 0;
    NSInteger width = 0;
    if (shape.size() == 4 && (shape[1] == 3 || shape[1] == 4)) {
        nchw = true;
        channels = shape[1];
        height = shape[2];
        width = shape[3];
    } else if (shape.size() == 4 && (shape[3] == 3 || shape[3] == 4)) {
        nchw = false;
        height = shape[1];
        width = shape[2];
        channels = shape[3];
    } else if (shape.size() == 3 && (shape[0] == 3 || shape[0] == 4)) {
        nchw = true;
        channels = shape[0];
        height = shape[1];
        width = shape[2];
    } else if (shape.size() == 3 && (shape[2] == 3 || shape[2] == 4)) {
        nchw = false;
        height = shape[0];
        width = shape[1];
        channels = shape[2];
    } else {
        return false;
    }

    const size_t rgba_size = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    uint8_t* rgba = static_cast<uint8_t*>(std::malloc(rgba_size));
    if (!rgba) {
        return false;
    }

    auto read_pixel = [&](NSInteger y, NSInteger x, NSInteger c) {
        size_t idx = 0;
        if (shape.size() == 4) {
            idx = nchw
                ? static_cast<size_t>((c * height + y) * width + x)
                : static_cast<size_t>((y * width + x) * channels + c);
        } else {
            idx = nchw
                ? static_cast<size_t>((c * height + y) * width + x)
                : static_cast<size_t>((y * width + x) * channels + c);
        }
        return array_get(image, idx);
    };

    for (NSInteger y = 0; y < height; ++y) {
        for (NSInteger x = 0; x < width; ++x) {
            const size_t dst = static_cast<size_t>(y * width + x) * 4;
            for (NSInteger c = 0; c < 3; ++c) {
                float value = read_pixel(y, x, c);
                if (value < 0.0f) {
                    value = (value + 1.0f) * 0.5f;
                }
                value = std::clamp(value, 0.0f, 1.0f);
                rgba[dst + static_cast<size_t>(c)] =
                    static_cast<uint8_t>(std::lround(value * 255.0f));
            }
            rgba[dst + 3] = 255;
        }
    }

    *out_rgba = rgba;
    *out_size = rgba_size;
    *out_width = static_cast<int32_t>(width);
    *out_height = static_cast<int32_t>(height);
    return true;
}

rac_result_t decode_latents(rac_diffusion_coreml_impl* impl,
                            const std::vector<float>& latents,
                            const LatentShape& latent_shape,
                            MLMultiArray** out_decoded,
                            rac_diffusion_result_t* out_result) {
    NSString* latent_name = resolve_feature_name(
        impl->vae_decoder, true, impl->io_config,
        {"vae_decoder.latent", "vae.latent", "vae_decoder.input", "vae.input"},
        {"z", "latent", "latents", "sample"}, MLFeatureTypeMultiArray);
    NSString* image_name = resolve_feature_name(
        impl->vae_decoder, false, impl->io_config,
        {"vae_decoder.output", "vae.output", "vae_decoder.image", "vae.image"},
        {"image", "images", "decoded", "sample"}, MLFeatureTypeMultiArray);
    if (!latent_name || !image_name) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "Unsupported VAEDecoder layout");
    }

    MLFeatureDescription* latent_desc = feature_desc(impl->vae_decoder, true, latent_name);
    MLMultiArray* latent_array = make_vae_latents(latents, latent_shape, latent_desc);
    if (!latent_array) {
        return set_error(out_result, RAC_ERROR_OUT_OF_MEMORY,
                         "Could not allocate VAEDecoder latent input");
    }
    NSDictionary<NSString*, MLFeatureValue*>* features = @{
        latent_name: [MLFeatureValue featureValueWithMultiArray:latent_array]
    };
    id<MLFeatureProvider> prediction = nil;
    std::string error;
    if (!run_prediction(impl->vae_decoder, features, &prediction, &error)) {
        return set_error(out_result, RAC_ERROR_INFERENCE_FAILED,
                         ("VAEDecoder prediction failed: " + error).c_str());
    }
    MLFeatureValue* value = [prediction featureValueForName:image_name];
    MLMultiArray* image = value.type == MLFeatureTypeMultiArray ? value.multiArrayValue : nil;
    if (!image) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "Unsupported VAEDecoder layout: image output is not a multi-array");
    }
    *out_decoded = image;
    return RAC_SUCCESS;
}

bool run_safety_checker(rac_diffusion_coreml_impl* impl, MLMultiArray* decoded_image) {
    if (!impl->safety_checker || !decoded_image ||
        impl->config.enable_safety_checker != RAC_TRUE) {
        return false;
    }

    NSDictionary<NSString*, MLFeatureDescription*>* input_descs =
        impl->safety_checker.modelDescription.inputDescriptionsByName;
    NSMutableDictionary<NSString*, MLFeatureValue*>* features = [NSMutableDictionary dictionary];
    for (NSString* input_name in input_descs) {
        MLFeatureDescription* desc = [input_descs objectForKey:input_name];
        if (desc.type == MLFeatureTypeMultiArray &&
            ([[input_name lowercaseString] containsString:@"image"] ||
             input_descs.count == 1)) {
            [features setObject:[MLFeatureValue featureValueWithMultiArray:decoded_image]
                         forKey:input_name];
        }
    }
    if (features.count != input_descs.count) {
        RAC_LOG_WARNING(kLogCat,
                        "Skipping SafetyChecker: required CLIP/image inputs are not available");
        return false;
    }

    id<MLFeatureProvider> prediction = nil;
    std::string error;
    if (!run_prediction(impl->safety_checker, features, &prediction, &error)) {
        RAC_LOG_WARNING(kLogCat, "SafetyChecker prediction failed: %s", error.c_str());
        return false;
    }

    for (NSString* output_name in impl->safety_checker.modelDescription.outputDescriptionsByName) {
        MLFeatureValue* value = [prediction featureValueForName:output_name];
        if (value.type == MLFeatureTypeInt64 && value.int64Value != 0) {
            return true;
        }
        if (value.type == MLFeatureTypeDouble && value.doubleValue > 0.5) {
            return true;
        }
        if (value.type == MLFeatureTypeMultiArray) {
            for (NSInteger i = 0; i < value.multiArrayValue.count; ++i) {
                if (array_get(value.multiArrayValue, static_cast<size_t>(i)) > 0.5f) {
                    return true;
                }
            }
        }
    }
    return false;
}

rac_result_t generate_internal(rac_diffusion_coreml_impl_t* impl,
                               const rac_diffusion_options_t* options,
                               rac_diffusion_progress_callback_fn progress_cb,
                               void* user_data,
                               rac_diffusion_result_t* out_result) {
    if (!impl || !options || !out_result) return RAC_ERROR_NULL_POINTER;
    if (!impl->initialized.load(std::memory_order_acquire)) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    std::memset(out_result, 0, sizeof(*out_result));
    if (!options->prompt || options->prompt[0] == '\0') {
        return set_error(out_result, RAC_ERROR_EMPTY_INPUT,
                         "Diffusion prompt is required");
    }
    if (options->mode != RAC_DIFFUSION_MODE_TEXT_TO_IMAGE) {
        return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                         "CoreML diffusion currently supports text-to-image only");
    }

    const int64_t started = now_ms();
    impl->cancel_requested.store(false, std::memory_order_release);
    const int32_t width = options->width > 0 ? options->width : 512;
    const int32_t height = options->height > 0 ? options->height : 512;
    const int32_t requested_steps = options->steps > 0 ? options->steps : 20;
    const int32_t steps = std::clamp(requested_steps, 1, 20);
    const float guidance = options->guidance_scale > 0.0f ? options->guidance_scale : 7.5f;
    const int64_t seed = options->seed >= 0 ? options->seed : 0;

    @autoreleasepool {
        MLMultiArray* prompt_embeddings = nil;
        rac_result_t rc = encode_text(impl, options->prompt, &prompt_embeddings, out_result);
        if (rc != RAC_SUCCESS) {
            return rc;
        }

        MLMultiArray* negative_embeddings = nil;
        const char* negative_prompt = options->negative_prompt ? options->negative_prompt : "";
        rc = encode_text(impl, negative_prompt, &negative_embeddings, out_result);
        if (rc != RAC_SUCCESS) {
            return rc;
        }

        NSString* sample_name = resolve_feature_name(
            impl->unet, true, impl->io_config,
            {"unet.sample", "unet.input_sample", "unet.latent"},
            {"sample", "latent_model_input", "latents"}, MLFeatureTypeMultiArray);
        NSString* timestep_name = resolve_feature_name(
            impl->unet, true, impl->io_config,
            {"unet.timestep", "unet.time"},
            {"timestep", "t", "time_step"},
            MLFeatureTypeInvalid);
        NSString* hidden_name = resolve_feature_name(
            impl->unet, true, impl->io_config,
            {"unet.encoder_hidden_states", "unet.hidden", "unet.text_embeddings"},
            {"encoder_hidden_states", "hidden_states", "text_embeds"},
            MLFeatureTypeMultiArray);
        NSString* output_name = resolve_feature_name(
            impl->unet, false, impl->io_config,
            {"unet.output", "unet.noise_pred"},
            {"noise_pred", "out_sample", "sample"}, MLFeatureTypeMultiArray);
        if (!sample_name || !timestep_name || !hidden_name || !output_name) {
            return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                             "Unsupported Unet layout");
        }

        MLFeatureDescription* sample_desc = feature_desc(impl->unet, true, sample_name);
        LatentShape latent_shape = resolve_latent_shape(sample_desc, width, height);
        const size_t latent_count =
            static_cast<size_t>(latent_shape.channels) *
            static_cast<size_t>(latent_shape.height) *
            static_cast<size_t>(latent_shape.width);
        std::vector<float> latents = initial_latents(latent_count, seed);
        const std::vector<double> alpha_cumprod = build_alpha_cumprod();

        for (int32_t step = 0; step < steps; ++step) {
            if (impl->cancel_requested.load(std::memory_order_acquire)) {
                return set_error(out_result, RAC_ERROR_CANCELLED,
                                 "CoreML diffusion generation cancelled");
            }
            const int32_t timestep = steps == 1
                ? 999
                : static_cast<int32_t>(std::lround(999.0 - (999.0 * step) / (steps - 1)));
            const int32_t previous_timestep = (step + 1 < steps)
                ? static_cast<int32_t>(std::lround(999.0 - (999.0 * (step + 1)) / (steps - 1)))
                : -1;

            std::vector<float> noise;
            rc = predict_noise(impl, latents, latent_shape, timestep, guidance,
                               prompt_embeddings, negative_embeddings, sample_name,
                               timestep_name, hidden_name, output_name, noise, out_result);
            if (rc != RAC_SUCCESS) {
                return rc;
            }
            ddim_step(latents, noise, timestep, previous_timestep, alpha_cumprod);

            if (progress_cb) {
                rac_diffusion_progress_t progress{};
                progress.progress = static_cast<float>(step + 1) / static_cast<float>(steps);
                progress.current_step = step + 1;
                progress.total_steps = steps;
                progress.stage = "Denoising";
                if (progress_cb(&progress, user_data) != RAC_TRUE) {
                    return set_error(out_result, RAC_ERROR_CANCELLED,
                                     "CoreML diffusion generation cancelled by progress callback");
                }
            }
        }

        MLMultiArray* decoded = nil;
        rc = decode_latents(impl, latents, latent_shape, &decoded, out_result);
        if (rc != RAC_SUCCESS) {
            return rc;
        }

        uint8_t* rgba = nullptr;
        size_t rgba_size = 0;
        int32_t image_width = 0;
        int32_t image_height = 0;
        if (!convert_decoded_image(decoded, &rgba, &rgba_size, &image_width, &image_height)) {
            return set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                             "Unsupported VAEDecoder image output layout");
        }

        out_result->image_data = rgba;
        out_result->image_size = rgba_size;
        out_result->width = image_width;
        out_result->height = image_height;
        out_result->seed_used = seed;
        out_result->generation_time_ms = now_ms() - started;
        out_result->safety_flagged =
            run_safety_checker(impl, decoded) ? RAC_TRUE : RAC_FALSE;
        out_result->error_code = RAC_SUCCESS;
        out_result->error_message = nullptr;
        return RAC_SUCCESS;
    }
}

}  // namespace

extern "C" {

// -----------------------------------------------------------------------------
// Lifecycle
// -----------------------------------------------------------------------------

rac_result_t rac_diffusion_coreml_create(const char* model_id,
                                         const char* /*config_json*/,
                                         rac_diffusion_coreml_impl_t** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;

    auto* impl = new (std::nothrow) rac_diffusion_coreml_impl();
    if (!impl) return RAC_ERROR_OUT_OF_MEMORY;

    if (model_id) impl->model_id = model_id;
    impl->config = RAC_DIFFUSION_CONFIG_DEFAULT;

    *out_impl = impl;
    RAC_LOG_INFO(kLogCat, "Created CoreML diffusion impl for model=%s",
                 model_id ? model_id : "(none)");
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_coreml_initialize(rac_diffusion_coreml_impl_t* impl,
                                             const char* model_path,
                                             const rac_diffusion_config_t* config) {
    if (!impl) return RAC_ERROR_NULL_POINTER;
    if (!model_path) return RAC_ERROR_INVALID_ARGUMENT;
    rac_result_t runtime_rc = rac_coreml_runtime_require_available();
    if (runtime_rc != RAC_SUCCESS) return runtime_rc;

    std::lock_guard<std::mutex> lock(impl->mtx);

    @autoreleasepool {
        NSString* dir = rac_coreml_find_resource_dir([NSString stringWithUTF8String:model_path],
                                                     @"Unet");
        BOOL is_dir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir
                                                isDirectory:&is_dir]
            || !is_dir) {
            RAC_LOG_ERROR(kLogCat, "Model path missing / not a directory: %s",
                          model_path);
            return RAC_ERROR_MODEL_NOT_FOUND;
        }

        impl->text_encoder =
            rac_coreml_load_model_in_dir(dir, @"TextEncoder", /*required=*/true, kLogCat);
        impl->unet =
            rac_coreml_load_model_in_dir(dir, @"Unet", /*required=*/true, kLogCat);
        impl->vae_decoder =
            rac_coreml_load_model_in_dir(dir, @"VAEDecoder", /*required=*/true, kLogCat);
        impl->safety_checker =
            rac_coreml_load_model_in_dir(dir, @"SafetyChecker", /*required=*/false, kLogCat);

        if (!impl->text_encoder || !impl->unet || !impl->vae_decoder) {
            RAC_LOG_ERROR(kLogCat,
                          "CoreML diffusion initialize failed — missing one of "
                          "TextEncoder.mlmodelc / Unet.mlmodelc / VAEDecoder.mlmodelc");
            impl->text_encoder = nil;
            impl->unet = nil;
            impl->vae_decoder = nil;
            impl->safety_checker = nil;
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }

        impl->model_path = [dir UTF8String];
        if (config) impl->config = *config;
        impl->io_config = CoreMLSDIOConfig{};
        load_json_config(impl->io_config, dir);
        load_model_metadata_config(impl->io_config, impl->text_encoder);
        load_model_metadata_config(impl->io_config, impl->unet);
        load_model_metadata_config(impl->io_config, impl->vae_decoder);
        if (impl->safety_checker) {
            load_model_metadata_config(impl->io_config, impl->safety_checker);
        }
        impl->vocab.clear();
        impl->vocab_loaded = false;
        impl->bos_token_id = 49406;
        impl->eos_token_id = 49407;
        impl->pad_token_id = 49407;
        impl->max_vocab_id = 49407;
        load_vocab(impl, dir);
        impl->initialized.store(true, std::memory_order_release);

        RAC_LOG_INFO(kLogCat,
                     "Initialized CoreML diffusion at %s "
                     "(safety_checker=%s)",
                     [dir UTF8String],
                     impl->safety_checker ? "present" : "absent");
    }
    return RAC_SUCCESS;
}

// -----------------------------------------------------------------------------
// Inference
// -----------------------------------------------------------------------------

rac_result_t rac_diffusion_coreml_generate(rac_diffusion_coreml_impl_t* impl,
                                           const rac_diffusion_options_t* options,
                                           rac_diffusion_result_t* out_result) {
    return generate_internal(impl, options, nullptr, nullptr, out_result);
}

rac_result_t rac_diffusion_coreml_generate_with_progress(
    rac_diffusion_coreml_impl_t* impl,
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_cb,
    void* user_data,
    rac_diffusion_result_t* out_result) {
    return generate_internal(impl, options, progress_cb, user_data, out_result);
}

// -----------------------------------------------------------------------------
// Introspection + lifecycle tail
// -----------------------------------------------------------------------------

rac_result_t rac_diffusion_coreml_get_info(const rac_diffusion_coreml_impl_t* impl,
                                           rac_diffusion_info_t* out_info) {
    if (!impl || !out_info) return RAC_ERROR_NULL_POINTER;
    std::memset(out_info, 0, sizeof(*out_info));

    const bool ready = impl->initialized.load(std::memory_order_acquire);
    out_info->is_ready                = ready ? RAC_TRUE : RAC_FALSE;
    out_info->current_model           = impl->model_id.empty()
                                            ? nullptr
                                            : impl->model_id.c_str();
    out_info->model_variant           = impl->config.model_variant;
    out_info->supports_text_to_image  = RAC_TRUE;
    out_info->supports_image_to_image = RAC_FALSE;
    out_info->supports_inpainting     = RAC_FALSE;
    out_info->safety_checker_enabled  = impl->safety_checker ? RAC_TRUE : RAC_FALSE;
    out_info->max_width               = 1024;
    out_info->max_height              = 1024;
    return RAC_SUCCESS;
}

uint32_t rac_diffusion_coreml_get_capabilities(const rac_diffusion_coreml_impl_t* impl) {
    uint32_t caps = RAC_DIFFUSION_CAP_TEXT_TO_IMAGE;
    if (impl && impl->safety_checker) {
        caps |= RAC_DIFFUSION_CAP_SAFETY_CHECKER;
    }
    return caps;
}

rac_result_t rac_diffusion_coreml_cancel(rac_diffusion_coreml_impl_t* impl) {
    if (!impl) return RAC_ERROR_NULL_POINTER;
    impl->cancel_requested.store(true, std::memory_order_release);
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_coreml_cleanup(rac_diffusion_coreml_impl_t* impl) {
    if (!impl) return RAC_ERROR_NULL_POINTER;
    std::lock_guard<std::mutex> lock(impl->mtx);
    impl->text_encoder = nil;
    impl->unet = nil;
    impl->vae_decoder = nil;
    impl->safety_checker = nil;
    impl->initialized.store(false, std::memory_order_release);
    return RAC_SUCCESS;
}

void rac_diffusion_coreml_destroy(rac_diffusion_coreml_impl_t* impl) {
    if (!impl) return;
    rac_diffusion_coreml_cleanup(impl);
    delete impl;
}

}  // extern "C"
