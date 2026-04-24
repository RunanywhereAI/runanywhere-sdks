/**
 * @file diffusion_coreml_backend.mm
 * @brief Objective-C++ bridge to Apple CoreML for the diffusion engine.
 *
 * GAP 06 T5.3. Uses Foundation + CoreML directly (no external
 * dependencies). Mirrors the public C ABI declared in
 * diffusion_coreml_backend.h.
 *
 * Design note: we deliberately avoid pulling Apple's
 * ml-stable-diffusion Swift package. Integrating it would either (a)
 * require a Swift dependency from C++ via a Swift package bridge (heavy
 * CMake rewrite) or (b) duplicate the denoising loop in C++ (weeks of
 * work). T5.3 scope is the engine shell + MLModel lifecycle. Concrete
 * SD inference lands in a follow-up phase — the `generate()` entry
 * returns `RAC_ERROR_NOT_SUPPORTED` until then, which is the error
 * surface the rac_diffusion_service router already propagates cleanly
 * to Flutter/RN/Swift frontends.
 */

#include "diffusion_coreml_backend.h"

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/rac_logger.h"

namespace {
constexpr const char* kLogCat = "Diffusion.CoreML";

/// Duplicate a const string into a heap buffer compatible with free()
/// so callers can use rac_diffusion_result_free() to release it.
char* dup_error_message(const char* msg) {
    if (!msg) return nullptr;
    const size_t n = std::strlen(msg) + 1;
    char* out = static_cast<char*>(std::malloc(n));
    if (out) std::memcpy(out, msg, n);
    return out;
}
}  // namespace

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
    std::atomic<bool> initialized{false};
    std::atomic<bool> cancel_requested{false};
    mutable std::mutex mtx;
};

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

namespace {

// Load an MLModel from `<dir>/<name>.mlmodelc`. Returns nil if the bundle
// is missing. Logs a warning on load failure, but caller decides if the
// model is required vs optional.
MLModel* load_mlmodel(NSString* dir, NSString* name, bool required) {
    NSString* path = [dir stringByAppendingPathComponent:
                        [name stringByAppendingString:@".mlmodelc"]];
    NSURL* url = [NSURL fileURLWithPath:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (required) {
            RAC_LOG_ERROR(kLogCat, "Required MLModel missing: %s",
                          [path UTF8String]);
        }
        return nil;
    }

    NSError* err = nil;
    MLModelConfiguration* cfg = [[MLModelConfiguration alloc] init];
    cfg.computeUnits = MLComputeUnitsAll;  // CPU + GPU + ANE.

    MLModel* model = [MLModel modelWithContentsOfURL:url
                                        configuration:cfg
                                                error:&err];
    if (!model) {
        RAC_LOG_ERROR(kLogCat, "MLModel load failed (%s): %s",
                      [name UTF8String],
                      err ? [[err localizedDescription] UTF8String] : "unknown");
        return nil;
    }
    return model;
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

    std::lock_guard<std::mutex> lock(impl->mtx);

    @autoreleasepool {
        NSString* dir = [NSString stringWithUTF8String:model_path];
        BOOL is_dir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir
                                                isDirectory:&is_dir]
            || !is_dir) {
            RAC_LOG_ERROR(kLogCat, "Model path missing / not a directory: %s",
                          model_path);
            return RAC_ERROR_MODEL_NOT_FOUND;
        }

        impl->text_encoder   = load_mlmodel(dir, @"TextEncoder",   /*required=*/true);
        impl->unet           = load_mlmodel(dir, @"Unet",          /*required=*/true);
        impl->vae_decoder    = load_mlmodel(dir, @"VAEDecoder",    /*required=*/true);
        impl->safety_checker = load_mlmodel(dir, @"SafetyChecker", /*required=*/false);

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

        impl->model_path = model_path;
        if (config) impl->config = *config;
        impl->initialized.store(true, std::memory_order_release);

        RAC_LOG_INFO(kLogCat,
                     "Initialized CoreML diffusion at %s "
                     "(safety_checker=%s)",
                     model_path,
                     impl->safety_checker ? "present" : "absent");
    }
    return RAC_SUCCESS;
}

// -----------------------------------------------------------------------------
// Inference (shell — see file-level note for scope)
// -----------------------------------------------------------------------------

rac_result_t rac_diffusion_coreml_generate(rac_diffusion_coreml_impl_t* impl,
                                           const rac_diffusion_options_t* options,
                                           rac_diffusion_result_t* out_result) {
    if (!impl || !options || !out_result) return RAC_ERROR_NULL_POINTER;
    if (!impl->initialized.load(std::memory_order_acquire)) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    std::memset(out_result, 0, sizeof(*out_result));
    out_result->error_code = RAC_ERROR_NOT_SUPPORTED;
    out_result->error_message = dup_error_message(
        "CoreML diffusion engine shell (T5.3): MLModel assets loaded but "
        "the full Stable Diffusion denoising loop is scheduled for phase 2. "
        "Integrate Apple's ml-stable-diffusion Swift package or port its "
        "scheduler to C++ to complete this path.");
    RAC_LOG_WARNING(kLogCat, "generate() called on CoreML diffusion shell — "
                             "returning RAC_ERROR_NOT_SUPPORTED (phase 2 work)");
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t rac_diffusion_coreml_generate_with_progress(
    rac_diffusion_coreml_impl_t* impl,
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn /*progress_cb*/,
    void* /*user_data*/,
    rac_diffusion_result_t* out_result) {
    return rac_diffusion_coreml_generate(impl, options, out_result);
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
