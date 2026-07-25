/**
 * @file test_segmentation_generic.cpp
 * @brief Proves the ONNX segmentation provider DERIVES its parameters from the
 *        bundle sidecars + the model output tensor, rather than falling back to
 *        its file-local SegFormer defaults.
 *
 * The sibling target test_segmentation_onnx exercises a bundle whose 150
 * classes, 512x512 input, ImageNet mean/std/rescale, and "class_<id>" labels
 * ALL collide with the provider's hardcoded defaults / synthesis fallback -- so
 * nothing there can distinguish "derived from sidecars" from "hardcoded". This
 * target closes that blind spot two ways:
 *
 *   (1) WHITE-BOX: the provider .cpp is #included directly so the file-local
 *       (anonymous-namespace) helpers derive_labels() / apply_preprocessor() /
 *       load_bundle() / label_for() and the ModelParams struct are reachable.
 *       Every asserted value is chosen to DIFFER from kDefaultInputSize (512),
 *       kDefaultMean/Std (ImageNet), kDefaultRescale (1/255), do_normalize/
 *       do_rescale (true), and the "class_<id>" synthesis -- so a regression
 *       that silently keeps a default is observable. No ORT session is created.
 *
 *   (2) END-TO-END: a generated tiny ONNX graph with N=4 classes, a 256x256
 *       input, and 64x64 logits (all != SegFormer 150 / 512 / 128) is driven
 *       through the real service op-table g_onnx_segmentation_ops. Its
 *       class_bias makes channel 2 the argmax at every pixel, and id2label names
 *       channel 2 "person" -- proving the class count + logits HxW come from the
 *       output tensor and the label comes from config.json id2label, not the
 *       fallback.
 *
 * Build shape mirrors test_diarization_onnx: the test TU #includes the provider
 * .cpp (white-box helpers) and the service-vtable adapter
 * (rac_onnx_segmentation_register.cpp) is compiled as a sibling TU to expose
 * g_onnx_segmentation_ops. Neither links rac_backend_onnx, so the provider's
 * symbols (and g_onnx_segmentation_ops) are defined exactly once.
 */

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>
#include <vector>

// The production provider TU. Included (not linked) so the anonymous-namespace
// derivation helpers derive_labels / apply_preprocessor / load_bundle /
// label_for and the ModelParams struct + kDefault* constants live in this TU.
#include "onnx_segmentation_provider.cpp"  // NOLINT(bugprone-suspicious-include)

#include "rac/core/rac_error.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/segmentation/rac_segmentation_types.h"

// The service-vtable adapter, compiled as a sibling TU.
extern "C" const rac_segmentation_service_ops_t g_onnx_segmentation_ops;

#ifndef RAC_SEGMENTATION_GENERIC_FIXTURE_DIR
#error "RAC_SEGMENTATION_GENERIC_FIXTURE_DIR must name the generated generic ONNX bundle"
#endif
#ifndef RAC_SEGMENTATION_SEGFORMER_FIXTURE_DIR
#error "RAC_SEGMENTATION_SEGFORMER_FIXTURE_DIR must name the committed SegFormer fixture bundle"
#endif

// Reach the provider's file-local helpers, ModelParams, and kDefault* constants.
using namespace runanywhere::segmentation;

namespace {

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

bool almost_equal(float a, float b) { return std::fabs(a - b) < 1e-5f; }

bool array_close(const std::array<float, 3>& value, float x, float y, float z) {
    return almost_equal(value[0], x) && almost_equal(value[1], y) && almost_equal(value[2], z);
}

bool write_text_file(const std::filesystem::path& path, const std::string& contents) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return false;
    }
    out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    return static_cast<bool>(out);
}

std::filesystem::path make_unique_temp_dir(const char* tag) {
    static int counter = 0;
    std::error_code ec;
    auto dir = std::filesystem::temp_directory_path(ec) /
               (std::string("rac_seg_") + tag + "_" + std::to_string(counter++));
    std::filesystem::remove_all(dir, ec);
    std::filesystem::create_directories(dir, ec);
    return dir;
}

void remove_dir_quietly(const std::filesystem::path& dir) {
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);
}

std::vector<uint8_t> make_solid_rgb_bytes(uint32_t width, uint32_t height) {
    std::vector<uint8_t> rgb(static_cast<size_t>(width) * height * 3);
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const size_t offset = (static_cast<size_t>(y) * width + x) * 3;
            rgb[offset] = static_cast<uint8_t>((x * 7U + y * 3U) % 256U);
            rgb[offset + 1] = static_cast<uint8_t>((x * 11U + y * 5U + 17U) % 256U);
            rgb[offset + 2] = static_cast<uint8_t>((x * 13U + y * 19U + 29U) % 256U);
        }
    }
    return rgb;
}

// ---- (1) WHITE-BOX derivation, no ORT session ----------------------------

void run_white_box_tests() {
    // apply_preprocessor: size.width/height, non-ImageNet mean/std, a non-1/255
    // rescale, and do_normalize/do_rescale=false ALL round-trip from the sidecar.
    {
        auto dir = make_unique_temp_dir("pre_wh");
        write_text_file(dir / kPreprocessorFileName,
                        "{\"do_normalize\": false, \"do_rescale\": false, "
                        "\"rescale_factor\": 0.5, \"image_mean\": [0.10, 0.20, 0.30], "
                        "\"image_std\": [0.40, 0.50, 0.60], "
                        "\"size\": {\"width\": 321, \"height\": 123}}");
        ModelParams params;
        apply_preprocessor(dir / kPreprocessorFileName, &params);
        CHECK(params.input_width == 321 && params.input_height == 123,
              "preprocessor size.width/height set input dims (321x123, not the 512 default)");
        CHECK(!params.do_normalize && !params.do_rescale,
              "do_normalize/do_rescale=false round-trip (defaults are true)");
        CHECK(almost_equal(params.rescale, 0.5f),
              "rescale_factor derived (0.5, not the 1/255 default)");
        CHECK(array_close(params.mean, 0.10f, 0.20f, 0.30f),
              "image_mean derived from the sidecar (not ImageNet)");
        CHECK(array_close(params.stddev, 0.40f, 0.50f, 0.60f),
              "image_std derived from the sidecar (not ImageNet)");
        remove_dir_quietly(dir);
    }

    // apply_preprocessor: size.shortest_edge sets BOTH dims; untouched fields
    // keep the SegFormer defaults.
    {
        auto dir = make_unique_temp_dir("pre_se");
        write_text_file(dir / kPreprocessorFileName, "{\"size\": {\"shortest_edge\": 384}}");
        ModelParams params;
        apply_preprocessor(dir / kPreprocessorFileName, &params);
        CHECK(params.input_width == 384 && params.input_height == 384,
              "size.shortest_edge sets BOTH input dims (384x384)");
        CHECK(almost_equal(params.rescale, kDefaultRescale) && params.do_normalize &&
                  params.do_rescale &&
                  array_close(params.mean, kDefaultMean[0], kDefaultMean[1], kDefaultMean[2]),
              "preprocessor fields absent from the sidecar keep SegFormer defaults");
        remove_dir_quietly(dir);
    }

    // apply_preprocessor: absent file early-returns, leaving every default intact.
    {
        ModelParams params;
        apply_preprocessor("/rac-nonexistent/preprocessor_config.json", &params);
        CHECK(params.input_width == kDefaultInputSize && params.input_height == kDefaultInputSize,
              "missing preprocessor -> default 512 input");
        CHECK(array_close(params.mean, kDefaultMean[0], kDefaultMean[1], kDefaultMean[2]) &&
                  array_close(params.stddev, kDefaultStd[0], kDefaultStd[1], kDefaultStd[2]) &&
                  almost_equal(params.rescale, kDefaultRescale) && params.do_normalize &&
                  params.do_rescale,
              "missing preprocessor early-return keeps all SegFormer defaults");
    }

    // derive_labels: a dense 0..N-1 id2label becomes ordered real labels.
    {
        auto dir = make_unique_temp_dir("cfg_dense");
        write_text_file(dir / kConfigFileName,
                        "{\"id2label\": {\"0\": \"background\", \"1\": \"road\", "
                        "\"2\": \"person\", \"3\": \"sky\"}}");
        const auto labels = derive_labels(dir / kConfigFileName);
        CHECK(labels.size() == 4 && labels[0] == "background" && labels[1] == "road" &&
                  labels[2] == "person" && labels[3] == "sky",
              "dense id2label parsed into ordered labels (real names, not class_<id>)");
        remove_dir_quietly(dir);
    }

    // derive_labels: non-dense / missing / absent all fall back to empty
    // (runtime synthesis path).
    {
        auto dir = make_unique_temp_dir("cfg_fallback");
        write_text_file(dir / kConfigFileName, "{\"id2label\": {\"0\": \"a\", \"2\": \"c\"}}");
        CHECK(derive_labels(dir / kConfigFileName).empty(),
              "non-dense id2label (missing index 1) -> empty labels (synthesis fallback)");
        write_text_file(dir / kConfigFileName, "{\"model_type\": \"segformer\"}");
        CHECK(derive_labels(dir / kConfigFileName).empty(),
              "config.json without id2label -> empty labels");
        CHECK(derive_labels(dir / "does_not_exist.json").empty(),
              "absent config.json -> empty labels");
        remove_dir_quietly(dir);
    }

    // label_for: synthesis when empty, derived label when present, synthesis for
    // out-of-range ids.
    {
        ModelParams params;
        CHECK(label_for(params, 7) == "class_7",
              "label_for synthesizes class_<id> when labels are empty");
        params.labels = {"background", "road", "person"};
        CHECK(label_for(params, 2) == "person",
              "label_for returns the derived label when present");
        CHECK(label_for(params, 9) == "class_9",
              "label_for synthesizes for out-of-range class ids");
    }

    // load_bundle: a directory with model.onnx + both sidecars wires config +
    // preprocessor into ModelParams (a 0-byte model.onnx is enough -- load_bundle
    // only is_regular_file-checks it and never opens ORT).
    {
        auto dir = make_unique_temp_dir("bundle_ok");
        write_text_file(dir / kModelFileName, "");
        write_text_file(dir / kConfigFileName,
                        "{\"id2label\": {\"0\": \"background\", \"1\": \"road\", "
                        "\"2\": \"person\", \"3\": \"sky\"}}");
        write_text_file(dir / kPreprocessorFileName,
                        "{\"do_normalize\": false, \"rescale_factor\": 0.25, "
                        "\"size\": {\"width\": 200, \"height\": 100}}");
        std::filesystem::path model;
        ModelParams params;
        std::string error;
        const bool ok = load_bundle(dir, &model, &params, &error);
        CHECK(ok, "load_bundle accepts a directory holding model.onnx + sidecars");
        CHECK(ok && model == dir / kModelFileName, "load_bundle resolves <dir>/model.onnx");
        CHECK(ok && params.labels.size() == 4 && params.labels[2] == "person",
              "load_bundle wires config.json id2label into ModelParams.labels");
        CHECK(ok && params.input_width == 200 && params.input_height == 100,
              "load_bundle wires preprocessor size into ModelParams input dims");
        CHECK(ok && !params.do_normalize && almost_equal(params.rescale, 0.25f),
              "load_bundle wires preprocessor do_normalize/rescale_factor");
        remove_dir_quietly(dir);
    }

    // load_bundle: a directory without model.onnx is rejected with a message.
    {
        auto dir = make_unique_temp_dir("bundle_nomodel");
        write_text_file(dir / kConfigFileName, "{\"id2label\": {\"0\": \"x\"}}");
        std::filesystem::path model;
        ModelParams params;
        std::string error;
        const bool ok = load_bundle(dir, &model, &params, &error);
        CHECK(!ok && !error.empty(),
              "load_bundle rejects a bundle missing model.onnx with an error message");
        remove_dir_quietly(dir);
    }
}

// ---- (2) END-TO-END through g_onnx_segmentation_ops ----------------------

// A non-default generic bundle (N=4, 256x256 input, 64x64 logits, id2label with
// real names, class 2 as the argmax) proves class count + logits HxW are read
// from the output tensor and the label comes from id2label.
void run_generic_end_to_end() {
    void* impl = nullptr;
    CHECK(g_onnx_segmentation_ops.create("generic-seg", nullptr, &impl) == RAC_SUCCESS &&
              impl != nullptr,
          "generic ops.create allocates an impl");
    if (!impl) {
        return;
    }
    const rac_result_t init_rc =
        g_onnx_segmentation_ops.initialize(impl, RAC_SEGMENTATION_GENERIC_FIXTURE_DIR);
    CHECK(init_rc == RAC_SUCCESS,
          "generic 4-class / 256-input bundle initializes a real ORT session");
    if (init_rc == RAC_SUCCESS) {
        const uint32_t width = 8;
        const uint32_t height = 6;
        const auto rgb = make_solid_rgb_bytes(width, height);
        rac_segmentation_image_t image{};
        image.data = rgb.data();
        image.data_size = rgb.size();
        image.width = width;
        image.height = height;
        image.stride_bytes = static_cast<size_t>(width) * 3;
        image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
        rac_segmentation_options_t options{};
        options.include_diagnostic_rgba = RAC_FALSE;
        rac_segmentation_result_t result{};
        const rac_result_t seg_rc =
            g_onnx_segmentation_ops.segment(impl, &image, &options, &result);
        CHECK(seg_rc == RAC_SUCCESS, "generic segment runs the 4-class graph to a mask");
        CHECK(result.width == width && result.height == height &&
                  result.class_mask_count == static_cast<size_t>(width) * height &&
                  result.class_mask != nullptr,
              "mask is source-dimensioned (8x6)");
        bool all_two = result.class_mask != nullptr;
        for (size_t i = 0; i < static_cast<size_t>(width) * height && all_two; ++i) {
            all_two = result.class_mask[i] == 2;
        }
        CHECK(all_two,
              "argmax is class 2 at every pixel (class count=4 + logits 64x64 read from the "
              "model output tensor, not pinned to SegFormer 150/128)");
        CHECK(result.class_summary_count == 1, "exactly one present class is summarized");
        CHECK(result.class_summary_count == 1 && result.class_summaries != nullptr &&
                  result.class_summaries[0].class_id == 2 &&
                  result.class_summaries[0].pixel_count == static_cast<uint64_t>(width) * height,
              "the single summary is class 2 over all 48 pixels");
        CHECK(result.class_summary_count == 1 && result.class_summaries != nullptr &&
                  result.class_summaries[0].label != nullptr &&
                  std::string(result.class_summaries[0].label) == "person",
              "winning label is the id2label string \"person\", not the class_<id> fallback");
        rac_segmentation_result_free(&result);
    }
    (void)g_onnx_segmentation_ops.cleanup(impl);
    g_onnx_segmentation_ops.destroy(impl);
}

// A bundle with config.json but NO preprocessor_config.json must fall back to the
// 512/ImageNet defaults and still segment end-to-end (exercises the same
// is_regular_file-guarded early-return through a real ORT run).
void run_defaults_when_preprocessor_absent() {
    auto dir = make_unique_temp_dir("defaults");
    std::error_code ec;
    std::filesystem::copy_file(
        std::filesystem::path(RAC_SEGMENTATION_SEGFORMER_FIXTURE_DIR) / kModelFileName,
        dir / kModelFileName, ec);
    std::filesystem::copy_file(
        std::filesystem::path(RAC_SEGMENTATION_SEGFORMER_FIXTURE_DIR) / kConfigFileName,
        dir / kConfigFileName, ec);
    CHECK(!ec, "staged a SegFormer bundle without preprocessor_config.json");

    void* impl = nullptr;
    CHECK(g_onnx_segmentation_ops.create("defaults-seg", nullptr, &impl) == RAC_SUCCESS &&
              impl != nullptr,
          "defaults ops.create allocates an impl");
    if (impl) {
        const rac_result_t init_rc =
            g_onnx_segmentation_ops.initialize(impl, dir.string().c_str());
        CHECK(init_rc == RAC_SUCCESS,
              "bundle lacking preprocessor_config.json still initializes (512 default matches "
              "the 512-input graph)");
        if (init_rc == RAC_SUCCESS) {
            const uint32_t width = 5;
            const uint32_t height = 4;
            const auto rgb = make_solid_rgb_bytes(width, height);
            rac_segmentation_image_t image{};
            image.data = rgb.data();
            image.data_size = rgb.size();
            image.width = width;
            image.height = height;
            image.stride_bytes = static_cast<size_t>(width) * 3;
            image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
            rac_segmentation_options_t options{};
            options.include_diagnostic_rgba = RAC_FALSE;
            rac_segmentation_result_t result{};
            const rac_result_t seg_rc =
                g_onnx_segmentation_ops.segment(impl, &image, &options, &result);
            CHECK(seg_rc == RAC_SUCCESS && result.class_mask != nullptr &&
                      result.class_summary_count == 1,
                  "missing-preprocessor default path segments a valid mask without crashing");
            CHECK(seg_rc == RAC_SUCCESS && result.class_summary_count == 1 &&
                      result.class_summaries[0].class_id == 149,
                  "the arange-bias SegFormer graph argmaxes to class 149 through the default "
                  "preprocessing");
            rac_segmentation_result_free(&result);
        }
        (void)g_onnx_segmentation_ops.cleanup(impl);
        g_onnx_segmentation_ops.destroy(impl);
    }
    remove_dir_quietly(dir);
}

// A preprocessor size that disagrees with the graph's fixed input dims must
// surface a clean rac_result_t error at run time, not a crash/UB.
void run_input_graph_mismatch() {
    auto dir = make_unique_temp_dir("mismatch");
    std::error_code ec;
    std::filesystem::copy_file(
        std::filesystem::path(RAC_SEGMENTATION_GENERIC_FIXTURE_DIR) / kModelFileName,
        dir / kModelFileName, ec);
    CHECK(!ec, "staged the 256-input generic graph for a mismatch bundle");
    // Claim 128x128 -> the provider feeds [1,3,128,128] to a graph whose input is
    // fixed at [1,3,256,256]; ORT must reject the run gracefully.
    write_text_file(dir / kPreprocessorFileName, "{\"size\": {\"width\": 128, \"height\": 128}}");

    void* impl = nullptr;
    CHECK(g_onnx_segmentation_ops.create("mismatch-seg", nullptr, &impl) == RAC_SUCCESS &&
              impl != nullptr,
          "mismatch ops.create allocates an impl");
    if (impl) {
        const rac_result_t init_rc =
            g_onnx_segmentation_ops.initialize(impl, dir.string().c_str());
        CHECK(init_rc == RAC_SUCCESS,
              "mismatched-size bundle still loads (the shape conflict only surfaces at run)");
        if (init_rc == RAC_SUCCESS) {
            const uint32_t width = 6;
            const uint32_t height = 6;
            const auto rgb = make_solid_rgb_bytes(width, height);
            rac_segmentation_image_t image{};
            image.data = rgb.data();
            image.data_size = rgb.size();
            image.width = width;
            image.height = height;
            image.stride_bytes = static_cast<size_t>(width) * 3;
            image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
            rac_segmentation_options_t options{};
            options.include_diagnostic_rgba = RAC_FALSE;
            rac_segmentation_result_t result{};
            const rac_result_t seg_rc =
                g_onnx_segmentation_ops.segment(impl, &image, &options, &result);
            CHECK(seg_rc != RAC_SUCCESS,
                  "preprocessor/graph input-shape mismatch returns a graceful rac_result_t "
                  "error, not a crash");
            rac_segmentation_result_free(&result);
        }
        (void)g_onnx_segmentation_ops.cleanup(impl);
        g_onnx_segmentation_ops.destroy(impl);
    }
    remove_dir_quietly(dir);
}

}  // namespace

int main() {
    std::fprintf(
        stdout,
        "test_segmentation_generic (sidecar derivation + non-default generic ONNX bundle)\n");
    run_white_box_tests();
    run_generic_end_to_end();
    run_defaults_when_preprocessor_absent();
    run_input_graph_mismatch();
    std::fprintf(stdout, "\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
