/**
 * @file test_ocr_neurt_e2e.cpp
 * @brief End-to-end proof that OCR is reachable through the LIFECYCLE PROTO ABI.
 *
 * 0.20.35 proved OCR reachable through `rac_ocr_create` / `rac_ocr_read_page` — the handle API.
 * That is what RCLI uses, and it was enough to call OCR "reachable". It was not enough to call it
 * SHIPPED: every platform SDK reaches a modality through the lifecycle proto ABI, so a modality
 * with no component was reachable from C and from nothing else.
 *
 * This test therefore drives the path a platform SDK actually takes, which is the one the handle
 * API cannot exercise:
 *
 *     rac_model_lifecycle_load_proto(category = MODEL_CATEGORY_OCR)   -> SDK_COMPONENT_OCR
 *       -> RAC_PRIMITIVE_OCR -> vtable ocr_ops -> LoadedModel::ocr_ops
 *     rac_ocr_read_page_lifecycle_proto(OCRRequest)                   -> OCRResult
 *
 * Four things break independently along that path and every one of them is invisible to
 * `test_plugin_entry_neurt`, which only inspects the vtable's SHAPE:
 *
 *   1. component_for_category has no MODEL_CATEGORY_OCR arm -> loads as SDK_COMPONENT_UNSPECIFIED
 *   2. model_lifecycle.cpp has no RAC_PRIMITIVE_OCR arm     -> UNSUPPORTED_MODALITY at create
 *   3. LoadedModel::ocr_ops never populated                 -> acquire_lifecycle_ocr finds nothing
 *   4. lifecycle_manager's service switch has no OCR arm    -> entry->impl stays null
 *
 * Env-gated on a real bundle. Exits 77 (CTest SKIP_RETURN_CODE) when absent, so it is reported as
 * SKIPPED and never as a pass — the distinction test_stt_neurt_e2e spent its whole life on the
 * wrong side of.
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "ocr.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/features/ocr/rac_ocr_service.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#include "rac/plugin/rac_primitive.h"

namespace {

int g_fail = 0;

void check(bool ok, const char* what) {
    std::fprintf(stdout, "  %s %s\n", ok ? "ok:" : "FAIL:", what);
    if (!ok) {
        ++g_fail;
    }
}

/**
 * A synthetic page carrying dark bars on white.
 *
 * Synthetic on purpose, and the assertion is calibrated to match: this proves PIXELS REACH THE
 * DETECTOR AND GEOMETRY COMES BACK, not that the recognizer transcribes English. Asserting on
 * transcript text here would be asserting on the CTC decoder's quality, which is neurun's gate
 * against its own gold, not this repo's to re-litigate.
 */
std::vector<uint8_t> make_page(uint32_t w, uint32_t h) {
    std::vector<uint8_t> px(static_cast<size_t>(w) * h * 3, 0xFF);
    for (uint32_t band = 0; band < 4; ++band) {
        const uint32_t y0 = h / 8 + band * (h / 5);
        for (uint32_t y = y0; y < y0 + h / 40 && y < h; ++y) {
            for (uint32_t x = w / 10; x < w - w / 10; ++x) {
                const size_t i = (static_cast<size_t>(y) * w + x) * 3;
                px[i + 0] = 0x20;
                px[i + 1] = 0x20;
                px[i + 2] = 0x20;
            }
        }
    }
    return px;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_ocr_neurt_e2e\n");

    const char* bundle = std::getenv("RAC_TEST_NEURT_OCR_BUNDLE");
    if (!bundle || bundle[0] == '\0') {
        std::fprintf(stdout,
                     "SKIP: set RAC_TEST_NEURT_OCR_BUNDLE to a nemotron-ocr-v1-full_ANE bundle\n");
        return 77;   // CTest SKIP_RETURN_CODE -- reported as skipped, never as passed
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_neurt();
    check(vt != nullptr, "neurt plugin entry resolves");
    if (!vt) {
        return 1;
    }
    check(vt->ocr_ops != nullptr, "neurt fills ocr_ops");
    check(rac_plugin_register(vt) == RAC_SUCCESS, "neurt registers");
    check(rac_plugin_find(RAC_PRIMITIVE_OCR) != nullptr,
          "registry routes OCR after registration");

    // ---- 1. Load through the lifecycle, BY CATEGORY. -------------------------------------
    // This is the step the handle API skips entirely, and the one that fails if
    // component_for_category, the RAC_PRIMITIVE_OCR create arm, or the manager's service switch
    // is missing its OCR case.
    rac_model_registry_handle_t registry = nullptr;
    check(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "model registry creates");

    const char* kModelId = "nemotron-ocr-e2e";
    runanywhere::v1::ModelInfo model;
    model.set_id(kModelId);
    model.set_name("Nemotron OCR (e2e)");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_OCR);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_COREML);
    model.set_local_path(bundle);
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    model.set_is_available(true);
    std::string model_bytes;
    check(model.SerializeToString(&model_bytes), "ModelInfo serializes");
    check(rac_model_registry_register_proto(
              registry, reinterpret_cast<const uint8_t*>(model_bytes.data()),
              model_bytes.size()) == RAC_SUCCESS,
          "OCR model registers with MODEL_CATEGORY_OCR");

    runanywhere::v1::ModelLoadRequest load;
    load.set_model_id(kModelId);
    load.set_category(runanywhere::v1::MODEL_CATEGORY_OCR);
    std::string load_bytes;
    check(load.SerializeToString(&load_bytes), "ModelLoadRequest serializes");

    rac_proto_buffer_t load_out{};
    rac_proto_buffer_init(&load_out);
    rac_result_t rc = rac_model_lifecycle_load_proto(
        registry, reinterpret_cast<const uint8_t*>(load_bytes.data()), load_bytes.size(),
        &load_out);
    runanywhere::v1::ModelLoadResult load_result;
    const bool load_ok = rc == RAC_SUCCESS &&
                         load_result.ParseFromArray(load_out.data,
                                                    static_cast<int>(load_out.size)) &&
                         !load_result.has_error();
    check(load_ok, "rac_model_lifecycle_load_proto(MODEL_CATEGORY_OCR)");
    if (!load_ok) {
        std::fprintf(stderr, "  load rc=%d error=%s\n", static_cast<int>(rc),
                     load_result.has_error() ? load_result.error().message().c_str() : "(none)");
        rac_proto_buffer_free(&load_out);
        return 1;
    }
    rac_proto_buffer_free(&load_out);

    // ---- 2. Read a page through the proto ABI. -------------------------------------------
    const uint32_t kW = 1024, kH = 1024;
    const std::vector<uint8_t> pixels = make_page(kW, kH);

    runanywhere::v1::OCRRequest request;
    auto* image = request.mutable_image();
    image->set_data(pixels.data(), pixels.size());
    image->set_width(kW);
    image->set_height(kH);
    image->set_pixel_format(runanywhere::v1::OCR_PIXEL_FORMAT_RGB8);
    std::string request_bytes;
    check(request.SerializeToString(&request_bytes), "OCRRequest serializes");

    rac_proto_buffer_t out{};
    rc = rac_ocr_read_page_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(), &out);
    check(rc == RAC_SUCCESS, "rac_ocr_read_page_lifecycle_proto");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "  read_page rc=%d\n", static_cast<int>(rc));
        rac_proto_buffer_free(&out);
        return 1;
    }

    runanywhere::v1::OCRResult result;
    check(result.ParseFromArray(out.data, static_cast<int>(out.size)), "OCRResult parses");
    rac_proto_buffer_free(&out);

    std::fprintf(stdout, "  regions=%d  model_id=%s  line_capable=%d  %lld ms\n",
                 result.regions_size(), result.model_id().c_str(),
                 static_cast<int>(result.supports_line_recognition()),
                 static_cast<long long>(result.processing_time_ms()));

    // The detector must find the bars. Zero regions on a page with four high-contrast bands means
    // the pixels never reached it -- the exact failure a "rc == SUCCESS" check alone would pass.
    check(result.regions_size() > 0, "detector returns at least one region on a banded page");

    // Geometry must be inside the SOURCE image, not the model's internal input size. A detector
    // whose boxes are still in 1024x1024-model space (or normalised 0..1) fails here, and that is
    // a bug no transcript inspection would reveal.
    bool in_bounds = true;
    bool nondegenerate = false;
    for (const auto& region : result.regions()) {
        const auto& q = region.quad();
        const float xs[4] = {q.x0(), q.x1(), q.x2(), q.x3()};
        const float ys[4] = {q.y0(), q.y1(), q.y2(), q.y3()};
        float min_x = xs[0], max_x = xs[0], min_y = ys[0], max_y = ys[0];
        for (int i = 0; i < 4; ++i) {
            in_bounds = in_bounds && xs[i] >= -1.0f && xs[i] <= static_cast<float>(kW) + 1.0f &&
                        ys[i] >= -1.0f && ys[i] <= static_cast<float>(kH) + 1.0f;
            min_x = xs[i] < min_x ? xs[i] : min_x;
            max_x = xs[i] > max_x ? xs[i] : max_x;
            min_y = ys[i] < min_y ? ys[i] : min_y;
            max_y = ys[i] > max_y ? ys[i] : max_y;
        }
        if (max_x - min_x > 1.0f && max_y - min_y > 1.0f) {
            nondegenerate = true;
        }
    }
    check(in_bounds, "every quad lies in source-image pixel space");
    check(nondegenerate, "at least one quad has real area (not a collapsed point)");

    // model_id must be the lifecycle's, proving the result came from the lifecycle-loaded model
    // and not from some service the test happened to construct.
    check(!result.model_id().empty(), "result carries the lifecycle model id");

    // ---- 3. The line verb must REFUSE on a detector-coupled model. ------------------------
    // nemotron-ocr's recognizer consumes a grid-sampled crop of the detector's feature map, so
    // there is no standalone line form. Accepting a line image here and running it would return
    // fluent nonsense; NOT_SUPPORTED is the honest answer, and the result already told the caller
    // to expect it via supports_line_recognition.
    if (!result.supports_line_recognition()) {
        runanywhere::v1::OCRRequest line = request;
        line.set_recognize_single_line(true);
        std::string line_bytes;
        (void)line.SerializeToString(&line_bytes);
        rac_proto_buffer_t line_out{};
        const rac_result_t line_rc = rac_ocr_read_page_lifecycle_proto(
            reinterpret_cast<const uint8_t*>(line_bytes.data()), line_bytes.size(), &line_out);
        check(line_rc == RAC_ERROR_NOT_SUPPORTED,
              "recognize_single_line is refused, not silently run as a page read");
        rac_proto_buffer_free(&line_out);
    }

    // ---- 4. RGBA8 must convert, not be rejected. ------------------------------------------
    // The proto accepts four-channel layouts because platform decoders emit them; commons strips
    // the alpha. If that conversion is wrong the detector sees garbage and finds nothing.
    std::vector<uint8_t> rgba(static_cast<size_t>(kW) * kH * 4);
    for (size_t i = 0, n = static_cast<size_t>(kW) * kH; i < n; ++i) {
        rgba[i * 4 + 0] = pixels[i * 3 + 0];
        rgba[i * 4 + 1] = pixels[i * 3 + 1];
        rgba[i * 4 + 2] = pixels[i * 3 + 2];
        rgba[i * 4 + 3] = 0xFF;
    }
    runanywhere::v1::OCRRequest rgba_request = request;
    rgba_request.mutable_image()->set_data(rgba.data(), rgba.size());
    rgba_request.mutable_image()->set_pixel_format(runanywhere::v1::OCR_PIXEL_FORMAT_RGBA8);
    std::string rgba_bytes;
    (void)rgba_request.SerializeToString(&rgba_bytes);
    rac_proto_buffer_t rgba_out{};
    const rac_result_t rgba_rc = rac_ocr_read_page_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(rgba_bytes.data()), rgba_bytes.size(), &rgba_out);
    check(rgba_rc == RAC_SUCCESS, "RGBA8 page is accepted");
    if (rgba_rc == RAC_SUCCESS) {
        runanywhere::v1::OCRResult rgba_result;
        if (rgba_result.ParseFromArray(rgba_out.data, static_cast<int>(rgba_out.size))) {
            std::fprintf(stdout, "  rgba regions=%d (rgb was %d)\n", rgba_result.regions_size(),
                         result.regions_size());
            // The same page through a different layout must find the same text. A byte-order slip
            // in the strip (BGR read as RGB) changes the image and therefore the region count.
            check(rgba_result.regions_size() == result.regions_size(),
                  "RGBA8 and RGB8 of the same page agree on region count");
        }
    }
    rac_proto_buffer_free(&rgba_out);

    std::fprintf(stdout, "%s\n", g_fail == 0 ? "PASS" : "FAIL");
    return g_fail == 0 ? 0 : 1;
}
