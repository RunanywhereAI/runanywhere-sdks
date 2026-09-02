/**
 * @file rac_ocr_service.h
 * @brief Optical character recognition (`RAC_PRIMITIVE_OCR`) — an image in, text plus geometry out.
 *
 * A SEPARATE primitive from `RAC_PRIMITIVE_VLM`, and the reason is the model, not taxonomy. A VLM
 * is image + PROMPT -> free text, generated token by token through an LLM decode loop. The OCR
 * models this serves are neither: nvidia/nemotron-ocr's recognizer is a CTC decoder over an
 * 855-entry charset with no prompt, no tokenizer and no KV cache. Routing it through `vlm_ops`
 * would mean handing it a prompt it cannot read and discarding the box geometry it exists to
 * produce — a contract the engine could only satisfy by lying.
 *
 * Distinct from EMBED_IMAGE too: that is image -> VECTOR for retrieval. This is image -> TEXT.
 *
 * FULL-PAGE OCR IS TWO MODELS, and the split is visible in this API on purpose. A detector finds
 * text regions; a recognizer reads each one. `rac_ocr_recognize` takes an already-cropped line and
 * is the smaller, always-available half; `rac_ocr_read_page` runs detection first and returns one
 * region per line. An engine may serve only the former — `read_page` then returns
 * RAC_ERROR_NOT_SUPPORTED rather than silently treating the whole page as one line, which produces
 * confident garbage.
 */
#ifndef RAC_OCR_SERVICE_H
#define RAC_OCR_SERVICE_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Pixel layout of an image handed to the recognizer. Matches the image-embedding contract:
 *  DECODED pixels only, because decoding is a platform concern and linking an image codec into
 *  every engine is real weight for no benefit. */
typedef enum rac_ocr_format { RAC_OCR_FORMAT_RGB8 = 0 } rac_ocr_format_t;

/** One decoded image: a full page for `read_page`, a single cropped line for `recognize`. */
typedef struct rac_ocr_image {
    rac_ocr_format_t format;
    /** Borrowed pixel buffer; must outlive the call. */
    const uint8_t* pixels;
    uint32_t width;
    uint32_t height;
} rac_ocr_image_t;

/**
 * One recognized text region.
 *
 * The quad is stored as four corner points, NOT an axis-aligned rect: detectors like FOTS emit
 * rotated boxes, and flattening them to a bounding rect at the ABI would throw away the angle
 * before any caller could use it. Points are in source-image pixels, clockwise from top-left.
 */
typedef struct rac_ocr_region {
    /** NUL-terminated UTF-8, owned by the result; released by `rac_ocr_result_free`. */
    char* text;
    /** Mean per-character confidence in [0,1]; negative when the engine does not report one. */
    float confidence;
    /** x0,y0, x1,y1, x2,y2, x3,y3 — clockwise from top-left, in source pixels. */
    float quad[8];
} rac_ocr_region_t;

/** The output of one OCR call. Release with `rac_ocr_result_free`. */
typedef struct rac_ocr_result {
    rac_ocr_region_t* regions;
    size_t num_regions;
    int64_t processing_time_ms;
} rac_ocr_result_t;

/** Engine capabilities. */
typedef struct rac_ocr_info {
    /** RAC_TRUE when the engine has a detector and can serve `read_page`. */
    rac_bool_t supports_page_detection;
    /** Size of the recognizer's charset, or 0 when unknown. */
    int32_t charset_size;
} rac_ocr_info_t;

/** Backend ops table. Occupies `ocr_ops`, promoted from reserved_slot_4 in ABI v11. */
typedef struct rac_ocr_service_ops {
    /** Initialize the service with a model path. */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /** Read ONE already-cropped text line. Every OCR engine must serve this. */
    rac_result_t (*recognize)(void* impl, const rac_ocr_image_t* line,
                              rac_ocr_result_t* out_result);

    /**
     * Detect text regions across a full page and read each one. An engine without a detector
     * returns RAC_ERROR_NOT_SUPPORTED — it must NOT fall back to recognizing the page as a single
     * line, which returns fluent nonsense that no caller can distinguish from a real read.
     */
    rac_result_t (*read_page)(void* impl, const rac_ocr_image_t* page,
                              rac_ocr_result_t* out_result);

    /** Service information. */
    rac_result_t (*get_info)(void* impl, rac_ocr_info_t* out_info);

    /** Cleanup resources (keeps the service alive). */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service. */
    void (*destroy)(void* impl);

    /** Allocate a backend-specific impl. See rac_llm_service_ops_t::create for the semantics. */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_ocr_service_ops_t;

/** Service handle. Mirrors every other feature's handle: ops table, backend impl, owned id. */
typedef struct rac_ocr_service {
    const rac_ocr_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_ocr_service_t;

/* ===========================================================================
 * Public C API — the entry points a platform SDK calls.
 * =========================================================================== */

/** Create an OCR service for `model_id` (a registry id or a local bundle path). */
RAC_API rac_result_t rac_ocr_create(const char* model_id, rac_handle_t* out_handle);

/** Initialize a created service. */
RAC_API rac_result_t rac_ocr_initialize(rac_handle_t handle, const char* model_path);

/** Read one already-cropped text line. */
RAC_API rac_result_t rac_ocr_recognize(rac_handle_t handle, const rac_ocr_image_t* line,
                                       rac_ocr_result_t* out_result);

/** Detect and read every text region on a page. RAC_ERROR_NOT_SUPPORTED without a detector. */
RAC_API rac_result_t rac_ocr_read_page(rac_handle_t handle, const rac_ocr_image_t* page,
                                       rac_ocr_result_t* out_result);

/** Engine capabilities. */
RAC_API rac_result_t rac_ocr_get_info(rac_handle_t handle, rac_ocr_info_t* out_info);

/** Release every buffer owned by `result` and zero it. Safe on an already-freed result. */
RAC_API void rac_ocr_result_free(rac_ocr_result_t* result);

/** Cleanup resources, keeping the handle alive. */
RAC_API rac_result_t rac_ocr_cleanup(rac_handle_t handle);

/** Destroy the service. */
RAC_API void rac_ocr_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_OCR_SERVICE_H */
