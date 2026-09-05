/** @file ocr_module.cpp @brief Lifecycle proto ABI for OCR (`RAC_PRIMITIVE_OCR`). */

#include <chrono>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/ocr/rac_ocr_service.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "ocr.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "OCR.Module";

// 8192 rather than segmentation's 4096: a scanned page at 300 DPI is 2550x3300,
// and at 600 DPI it is 5100x6600. Capping an OCR page at 4096 would reject the
// ordinary case this primitive exists for.
constexpr uint32_t kMaxSourceDimension = 8192;
constexpr uint64_t kMaxSourcePixels = 8192ULL * 8192ULL;

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                                   "protobuf support is not compiled in")
                      : RAC_ERROR_NULL_POINTER;
}

size_t pixel_channels(runanywhere::v1::OCRPixelFormat format) {
    switch (format) {
        case runanywhere::v1::OCR_PIXEL_FORMAT_RGB8:
            return 3;
        case runanywhere::v1::OCR_PIXEL_FORMAT_RGBA8:
        case runanywhere::v1::OCR_PIXEL_FORMAT_BGRA8:
            return 4;
        default:
            return 0;
    }
}

/**
 * Narrow the request's layout to the packed RGB8 the OCR C ABI accepts.
 *
 * The proto takes RGBA8 and BGRA8 because that is what a platform's image
 * decoder hands back — CGImage gives BGRA, a canvas gives RGBA — and making
 * every SDK strip the alpha itself is exactly the per-platform logic that
 * belongs down here instead. `rac_ocr_image_t` carries no stride, so the
 * conversion also guarantees tight packing.
 *
 * RGB8 input is borrowed in place: `scratch` stays empty and no copy is made.
 */
rac_result_t to_rgb8(const runanywhere::v1::OCRImage& source, std::vector<uint8_t>* scratch,
                     rac_ocr_image_t* out_image) {
    const size_t channels = pixel_channels(source.pixel_format());
    if (source.width() == 0 || source.height() == 0 || source.width() > kMaxSourceDimension ||
        source.height() > kMaxSourceDimension || channels == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const uint64_t pixels = static_cast<uint64_t>(source.width()) * source.height();
    if (pixels > kMaxSourcePixels || pixels > std::numeric_limits<size_t>::max() / channels) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const size_t pixel_count = static_cast<size_t>(pixels);
    if (source.data().size() != pixel_count * channels) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const auto* src = reinterpret_cast<const uint8_t*>(source.data().data());
    out_image->format = RAC_OCR_FORMAT_RGB8;
    out_image->width = source.width();
    out_image->height = source.height();

    if (source.pixel_format() == runanywhere::v1::OCR_PIXEL_FORMAT_RGB8) {
        scratch->clear();
        out_image->pixels = src;
        return RAC_SUCCESS;
    }

    if (pixel_count > std::numeric_limits<size_t>::max() / 3) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    scratch->resize(pixel_count * 3);
    const bool bgra = source.pixel_format() == runanywhere::v1::OCR_PIXEL_FORMAT_BGRA8;
    for (size_t i = 0; i < pixel_count; ++i) {
        const uint8_t* p = src + i * 4;
        uint8_t* q = scratch->data() + i * 3;
        q[0] = bgra ? p[2] : p[0];
        q[1] = p[1];
        q[2] = bgra ? p[0] : p[2];
    }
    out_image->pixels = scratch->data();
    return RAC_SUCCESS;
}

void region_to_proto(const rac_ocr_region_t& source, runanywhere::v1::OCRRegion* out) {
    out->set_text(source.text ? source.text : "");
    // Negative means "the engine reports no confidence" in the C ABI. Leaving
    // the optional unset preserves that; writing the raw float would publish a
    // negative confidence, and clamping it to 0 would read as "certainly wrong".
    if (source.confidence >= 0.0f) {
        out->set_confidence(source.confidence);
    }
    auto* quad = out->mutable_quad();
    quad->set_x0(source.quad[0]);
    quad->set_y0(source.quad[1]);
    quad->set_x1(source.quad[2]);
    quad->set_y1(source.quad[3]);
    quad->set_x2(source.quad[4]);
    quad->set_y2(source.quad[5]);
    quad->set_x3(source.quad[6]);
    quad->set_y3(source.quad[7]);
}

rac_result_t read_with_service(rac_handle_t service, const char* model_id,
                               const uint8_t* request_bytes, size_t request_size,
                               rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (rac_proto_bytes_validate(request_bytes, request_size) != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "OCRRequest bytes are invalid");
    }
    runanywhere::v1::OCRRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse OCRRequest");
    }
    if (!request.has_image()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "OCRRequest.image is required");
    }

    std::vector<uint8_t> scratch;
    rac_ocr_image_t image = {};
    rac_result_t rc = to_rgb8(request.image(), &scratch, &image);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid OCR image");
    }

    rac_ocr_info_t info = {};
    const bool has_info = rac_ocr_get_info(service, &info) == RAC_SUCCESS;
    const bool line_capable = has_info && info.supports_line_recognition == RAC_TRUE;

    rac_ocr_result_t raw = {};
    const auto started = std::chrono::steady_clock::now();
    if (request.recognize_single_line()) {
        // Refuse here rather than letting the service refuse, so the message
        // names the capability the caller can actually test for on a result.
        if (!line_capable) {
            return rac_proto_buffer_set_error(
                out_result, RAC_ERROR_NOT_SUPPORTED,
                "this OCR model has no standalone line recognizer; its recognizer consumes the "
                "detector's feature map, so read the whole page instead "
                "(OCRResult.supports_line_recognition reports this)");
        }
        rc = rac_ocr_recognize(service, &image, &raw);
    } else {
        rc = rac_ocr_read_page(service, &image, &raw);
    }
    if (rc != RAC_SUCCESS) {
        rac_ocr_result_free(&raw);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();

    runanywhere::v1::OCRResult result;
    // Measured HERE, not taken from raw.processing_time_ms. The C ABI leaves that
    // field to the engine and the one engine that fills ocr_ops never writes it, so
    // forwarding it reported a confident "0 ms" on every single read — a false
    // number is worse than an absent one. Commons owns the call boundary, so
    // commons is what can honestly answer "how long did this take".
    result.set_processing_time_ms(static_cast<int64_t>(elapsed_ms));
    result.set_model_id(model_id ? model_id : "");
    result.set_supports_line_recognition(line_capable);
    for (size_t i = 0; i < raw.num_regions; ++i) {
        region_to_proto(raw.regions[i], result.add_regions());
    }
    rc = rac::proto::copy_message(result, out_result, "failed to serialize OCRResult");
    rac_ocr_result_free(&raw);
    return rc;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

rac_result_t rac_ocr_read_page_lifecycle_proto(const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                                   "protobuf support is not compiled in")
                      : RAC_ERROR_NULL_POINTER;
#else
    rac::lifecycle::LifecycleOcrRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_ocr(&ref);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_DEBUG(kLogCategory, "no OCR model loaded on the lifecycle");
        return out_result ? rac_proto_buffer_set_error(out_result, rc, "OCR model is not loaded")
                          : RAC_ERROR_NULL_POINTER;
    }
    rac_ocr_service_t service{ref.ops, ref.impl, ref.model_id};
    rc = read_with_service(&service, ref.model_id, request_proto_bytes, request_proto_size,
                           out_result);
    rac::lifecycle::release_lifecycle_ocr(&ref);
    return rc;
#endif
}

}  // extern "C"
