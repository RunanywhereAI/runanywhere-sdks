/**
 * @file lora_import.cpp
 * @brief Retired: canonical user-file LoRA adapter import ABI entry point.
 *
 * idl/lora_options.proto deleted LoraAdapterImportRequest/Result and
 * LoraAdapterDownloadCompletedRequest/Result outright (the
 * "lora-delete-download-import-bookkeeping" API-simplification edit):
 * adapter files are now acquired through the models domain's download and
 * import verbs (rac_model_registry_import_proto / the download orchestrator),
 * and this LoRA domain carries no download/import state of its own. A
 * non-empty LoraAdapterCatalogEntry.local_path is the only "downloaded"
 * signal that survives.
 *
 * rac_lora_adapter_import_proto has no request/result proto shape left to
 * parse into, so it is retired to a stub rather than removed outright (the
 * C ABI symbol is still declared in rac_lora_service.h and called from the
 * JNI bridge; dropping the symbol is a coordinated cross-binding change
 * outside this pass).
 */

#include <cstdint>

#include "rac/core/rac_error.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/foundation/rac_proto_buffer.h"

extern "C" RAC_API rac_result_t rac_lora_adapter_import_proto(rac_lora_registry_handle_t registry,
                                                              const uint8_t* request_proto_bytes,
                                                              size_t request_proto_size,
                                                              rac_proto_buffer_t* out_result) {
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(
        out_result, RAC_ERROR_NOT_IMPLEMENTED,
        "rac_lora_adapter_import_proto is retired -- LoRA adapter files are acquired through "
        "the models domain's download/import verbs");
}
