/**
 * @file cmd_segment.cpp
 * @brief `rcli segment <image.ppm> --model <path>` — semantic segmentation via
 *        the commons segmentation service (image-in → per-class mask summary).
 *
 * Mirrors cmd_image's structure (bootstrap → resolve model → one commons path →
 * render) but consumes an image instead of producing one. The model lifecycle
 * is the standard service handle sequence the C ABI exposes:
 *   rac_segmentation_create(model)  → route to the ONNX SegFormer provider
 *     → rac_segmentation_initialize(model_path)  → load the ONNX bundle
 *     → rac_segmentation_segment(image, …, &result)  → source-sized class mask
 *       + per-class summaries
 *     → rac_segmentation_result_free / rac_segmentation_destroy
 * A `--model` naming an on-disk path is used verbatim; otherwise it is a
 * catalog id resolved + auto-pulled through commons. Input is a binary PPM
 * (P6); it is the dependency-free image format the CLI can decode without
 * libpng/libjpeg
 * (`magick in.png out.ppm`). All preprocessing/inference lives in the engine.
 */

#include <cstdio>
#include <filesystem>
#include <memory>
#include <string>
#include <system_error>
#include <vector>

#include "commands/commands.h"
#include "commands/model_setup.h"
#include "io/image_io.h"
#include "io/output.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/segmentation/rac_segmentation_types.h"

namespace rcli::commands {

namespace {

// Resolve `ref` to a local model path: an existing on-disk path is used as-is;
// otherwise it is a catalog/registry id resolved + auto-pulled through commons.
int resolve_model_path(const GlobalOptions& options, const std::string& ref,
                       std::string* out_path) {
    std::error_code ec;
    if (std::filesystem::exists(ref, ec)) {
        *out_path = ref;
        return 0;
    }
    ResolvedModelPaths model;
    const int setup = ensure_model_ready(options, ref, &model);
    if (setup != 0) {
        return setup;
    }
    *out_path = model.primary_path;
    return 0;
}

void print_result(const GlobalOptions& options, const std::string& model_ref,
                  const rac_segmentation_result_t& result) {
    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", result.model_id ? result.model_id : model_ref)
            .field("width", static_cast<int64_t>(result.width))
            .field("height", static_cast<int64_t>(result.height))
            .field("class_count", static_cast<int64_t>(result.class_summary_count))
            .field("processing_time_ms", static_cast<int64_t>(result.processing_time_ms));
        json.begin_array("classes");
        for (size_t i = 0; i < result.class_summary_count; ++i) {
            const rac_segmentation_class_summary_t& cls = result.class_summaries[i];
            json.begin_array_object()
                .field("class_id", static_cast<int64_t>(cls.class_id))
                .field("label", cls.label ? cls.label : "")
                .field("pixel_count", static_cast<int64_t>(cls.pixel_count))
                .field("fraction", static_cast<double>(cls.fraction))
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return;
    }

    out::result_line("size\t" + std::to_string(result.width) + "x" + std::to_string(result.height));
    if (result.class_summary_count == 0) {
        out::result_line("(no classes)");
    } else {
        std::vector<std::vector<std::string>> rows;
        rows.reserve(result.class_summary_count);
        for (size_t i = 0; i < result.class_summary_count; ++i) {
            const rac_segmentation_class_summary_t& cls = result.class_summaries[i];
            char pct[16];
            std::snprintf(pct, sizeof(pct), "%.1f%%", static_cast<double>(cls.fraction) * 100.0);
            rows.push_back({std::to_string(cls.class_id), cls.label ? cls.label : "",
                            std::to_string(cls.pixel_count), pct});
        }
        out::table({"class_id", "label", "pixels", "coverage"}, rows);
    }
    if (options.verbose) {
        out::status_line("(" + std::to_string(result.processing_time_ms) + " ms)");
    }
}

int run_segment(const GlobalOptions& options, const std::string& image_path,
                const std::string& model_ref) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (model_ref.empty()) {
        out::error_line("--model is required (a segmentation model id or on-disk path)");
        return 2;
    }

    std::string model_path;
    const int resolve = resolve_model_path(options, model_ref, &model_path);
    if (resolve != 0) {
        return resolve;
    }

    image::RgbImage decoded;
    std::string error;
    if (!image::read_ppm(image_path, &decoded, &error)) {
        out::error_line(error);
        return 1;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_segmentation_create(model_path.c_str(), &handle);
    if (rc != RAC_SUCCESS || handle == nullptr) {
        out::error_line("failed to create segmentation service: " + out::describe_result(rc));
        return 1;
    }

    rc = rac_segmentation_initialize(handle, model_path.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load segmentation model: " + out::describe_result(rc));
        rac_segmentation_destroy(handle);
        return 1;
    }

    rac_segmentation_image_t image = {};
    image.data = decoded.rgb.data();
    image.data_size = decoded.rgb.size();
    image.width = decoded.width;
    image.height = decoded.height;
    image.stride_bytes = static_cast<size_t>(decoded.width) * 3;
    image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;

    rac_segmentation_options_t seg_options = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    rac_segmentation_result_t result = {};
    rc = rac_segmentation_segment(handle, &image, &seg_options, &result);
    if (rc != RAC_SUCCESS) {
        out::error_line("segmentation failed: " + out::describe_result(rc));
        rac_segmentation_result_free(&result);
        rac_segmentation_cleanup(handle);
        rac_segmentation_destroy(handle);
        return 1;
    }

    print_result(options, model_ref, result);

    rac_segmentation_result_free(&result);
    rac_segmentation_cleanup(handle);
    rac_segmentation_destroy(handle);
    return 0;
}

}  // namespace

void register_segment(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd =
        app.add_subcommand("segment", "Semantic segmentation of an image (per-class mask summary)");
    auto image_path = std::make_shared<std::string>();
    auto model = std::make_shared<std::string>();
    cmd->add_option("image", *image_path, "Input image (binary PPM / P6)")
        ->required()
        ->check(CLI::ExistingFile);
    cmd->add_option("--model,-m", *model, "Segmentation model id or on-disk path")->required();
    cmd->callback([&options, image_path, model]() {
        const int exit_code = run_segment(options, *image_path, *model);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
