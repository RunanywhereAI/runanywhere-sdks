/**
 * @file cmd_image.cpp
 * @brief `rcli image generate` — text-to-image via the CoreML diffusion engine.
 *
 * Canonical SDK flow, all heavy lifting in commons (mirrors cmd_run/cmd_embed):
 *   rac_model_lifecycle_load_proto(category=IMAGE_GENERATION, validate=true)
 *     → auto-pulls / resolves the diffusion bundle and loads the coreml engine.
 *   rac_diffusion_generate_lifecycle_proto(DiffusionGenerationRequest)
 *     → resolves the lifecycle-loaded model internally and returns a
 *       DiffusionResult (raw RGBA image_data + width/height).
 * The command only translates argv ↔ proto bytes and writes the decoded image
 * to --out as PNG. Diffusion is Apple/CoreML-only; on other platforms the
 * command returns a clear error rather than crashing.
 *
 * A `--model` that names an existing on-disk path is registered as a local
 * CoreML bundle (directory of compiled .mlmodelc sub-models) and loaded without
 * a download — the reliable path for a pre-fetched Apple SD bundle.
 */

#include "commands/commands.h"

#include <memory>
#include <string>

#include "io/output.h"

#if defined(RCLI_HAS_COREML)
#include <fstream>
#include <ios>
#include <sys/stat.h>

#include "diffusion_options.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "io/image_io.h"
#include "io/proto.h"
#include "progress/progress_bar.h"
#endif

namespace rcli::commands {

namespace {

// Default diffusion model — the built-in CoreML Stable Diffusion 1.5 catalog id
// (see catalog.cpp). Overridable with --model (catalog id / registered id / a
// local path to a compiled CoreML bundle).
constexpr const char* kDefaultDiffusionModel = "stable-diffusion-v1-5-coreml";

struct ImageParams {
    std::string model = kDefaultDiffusionModel;
    std::string prompt;
    std::string negative_prompt;
    std::string out_path;
    int32_t steps = 0;      // 0 = model/variant default
    float guidance = 0.0f;  // 0 = model/variant default
    int64_t seed = -1;      // -1 = random
};

#if defined(RCLI_HAS_COREML)

namespace v1 = runanywhere::v1;

bool path_exists(const std::string& path) {
    struct stat st {};
    return ::stat(path.c_str(), &st) == 0;
}

// Register an already-present local CoreML bundle so the lifecycle loader can
// resolve it by id (no download). Directory resolution is a CLI concern.
bool register_local_bundle(const std::string& path, std::string* out_id, std::string* error) {
    const std::string model_id = "local-diffusion-coreml";
    v1::ModelInfo model;
    model.set_id(model_id);
    model.set_name("Local CoreML Diffusion");
    model.set_category(v1::MODEL_CATEGORY_IMAGE_GENERATION);
    model.set_framework(v1::INFERENCE_FRAMEWORK_COREML);
    model.set_format(v1::MODEL_FORMAT_MLPACKAGE);
    model.set_local_path(path);
    model.set_source(v1::MODEL_SOURCE_LOCAL);

    const std::string bytes = proto::serialize(model);
    const rac_result_t rc = rac_model_registry_register_proto(
        rac_get_model_registry(), reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
    if (rc != RAC_SUCCESS) {
        if (error) {
            *error = "failed to register local model: " + out::describe_result(rc);
        }
        return false;
    }
    *out_id = model_id;
    return true;
}

bool load_diffusion_model(const GlobalOptions& options, const std::string& model_id,
                          bool validate_availability) {
    progress::DownloadProgressScope progress_scope(model_id, !options.no_progress && !options.json);
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    request.set_category(v1::MODEL_CATEGORY_IMAGE_GENERATION);
    request.set_validate_availability(validate_availability);

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                       reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                       &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("diffusion model load failed: " + error);
        return false;
    }
    if (!result.success()) {
        out::error_line("diffusion model load failed: " +
                        (result.error_message().empty() ? "unknown error"
                                                         : result.error_message()));
        return false;
    }
    if (options.verbose) {
        out::status_line("loaded " + result.resolved_path());
    }
    return true;
}

bool write_image(const v1::DiffusionResult& result, const std::string& out_path,
                 std::string* error) {
    const std::string& image = result.image_data();
    if (image.empty()) {
        if (error) {
            *error = "engine returned no image data";
        }
        return false;
    }
    // Every shipped C-ABI diffusion engine emits raw RGBA (image_media_type
    // "image/raw-rgba"); encode it to PNG. A future backend returning an
    // encoded container writes through verbatim.
    const bool is_raw_rgba =
        result.image_media_type() == "image/raw-rgba" ||
        (result.width() > 0 && result.height() > 0 &&
         image.size() == static_cast<size_t>(result.width()) * result.height() * 4);
    if (is_raw_rgba) {
        return image::write_png(out_path, reinterpret_cast<const uint8_t*>(image.data()),
                                result.width(), result.height(), error);
    }
    std::ofstream file(out_path, std::ios::binary);
    file.write(image.data(), static_cast<std::streamsize>(image.size()));
    if (!file.good()) {
        if (error) {
            *error = "cannot write " + out_path;
        }
        return false;
    }
    return true;
}

#endif  // RCLI_HAS_COREML

int run_image_generate(const GlobalOptions& options, const ImageParams& params) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

#if !defined(RCLI_HAS_COREML)
    (void)params;
    out::error_line("image generation (diffusion) is only supported on Apple/CoreML platforms");
    return 1;
#else
    if (params.prompt.empty()) {
        out::error_line("--prompt is required");
        return 2;
    }
    if (params.out_path.empty()) {
        out::error_line("--out is required");
        return 2;
    }

    // Resolve the model: an existing on-disk path is a local CoreML bundle;
    // otherwise fall through to the catalog / registry / URL resolver.
    std::string model_id;
    bool validate_availability = true;
    std::string error;
    if (path_exists(params.model)) {
        if (!register_local_bundle(params.model, &model_id, &error)) {
            out::error_line(error);
            return 1;
        }
        validate_availability = false;  // already on disk
    } else {
        model_ref::ResolveOptions resolve_options;
        resolve_options.has_category = true;
        resolve_options.category = v1::MODEL_CATEGORY_IMAGE_GENERATION;
        resolve_options.has_framework = true;
        resolve_options.framework = v1::INFERENCE_FRAMEWORK_COREML;
        model_ref::Resolved resolved;
        if (model_ref::resolve(params.model, &resolved, &error, &resolve_options) != RAC_SUCCESS) {
            out::error_line(error);
            return 1;
        }
        model_id = resolved.model_id;
    }

    if (!load_diffusion_model(options, model_id, validate_availability)) {
        return 1;
    }

    v1::DiffusionGenerationRequest request;
    request.set_model_id(model_id);
    v1::DiffusionGenerationOptions* gen = request.mutable_options();
    gen->set_prompt(params.prompt);
    if (!params.negative_prompt.empty()) {
        gen->set_negative_prompt(params.negative_prompt);
    }
    if (params.steps > 0) {
        gen->set_num_inference_steps(params.steps);
    }
    if (params.guidance > 0.0f) {
        gen->set_guidance_scale(params.guidance);
    }
    gen->set_seed(params.seed);

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    v1::DiffusionResult result;
    if (rac_diffusion_generate_lifecycle_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                               bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("image generation failed: " + error);
        return 1;
    }
    if (result.error_code() != 0 || !result.error_message().empty()) {
        out::error_line("image generation failed: " +
                        (result.error_message().empty() ? std::to_string(result.error_code())
                                                         : result.error_message()));
        return 1;
    }

    if (!write_image(result, params.out_path, &error)) {
        out::error_line("failed to write image: " + error);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", model_id)
            .field("output", params.out_path)
            .field("width", static_cast<int64_t>(result.width()))
            .field("height", static_cast<int64_t>(result.height()))
            .field("seed", static_cast<int64_t>(result.seed_used()))
            .field("total_ms", static_cast<int64_t>(result.total_time_ms()))
            .end_object();
        out::result_line(json.str());
    } else {
        out::result_line(params.out_path);
        if (options.verbose) {
            out::status_line("(" + std::to_string(result.width()) + "x" +
                             std::to_string(result.height()) + ", seed " +
                             std::to_string(result.seed_used()) + ", " +
                             std::to_string(result.total_time_ms()) + " ms)");
        }
    }
    return 0;
#endif
}

}  // namespace

void register_image(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("image", "Generate images (CoreML diffusion, Apple only)");
    cmd->require_subcommand(1);

    CLI::App* generate = cmd->add_subcommand("generate", "Text-to-image generation");
    auto params = std::make_shared<ImageParams>();
    generate
        ->add_option("--model,-m", params->model,
                     "Diffusion model id, a registered id, or a local CoreML bundle path "
                     "(default: " +
                         std::string(kDefaultDiffusionModel) + ")")
        ->default_val(kDefaultDiffusionModel);
    generate->add_option("--prompt,-p", params->prompt, "Text prompt")->required();
    generate->add_option("--negative", params->negative_prompt, "Negative prompt");
    generate->add_option("--steps", params->steps, "Number of denoising steps (0 = model default)");
    generate->add_option("--guidance", params->guidance,
                         "Classifier-free guidance scale (0 = model default)");
    generate->add_option("--seed", params->seed, "RNG seed (-1 = random)");
    generate->add_option("--out,-o", params->out_path, "Output image path (.png)")->required();
    generate->callback([&options, params]() {
        const int exit_code = run_image_generate(options, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
