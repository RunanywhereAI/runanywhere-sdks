#ifndef RUNANYWHERE_GENIE_BACKEND_H
#define RUNANYWHERE_GENIE_BACKEND_H

/**
 * @file genie_backend.h
 * @brief Shell header for the Qualcomm Genie / NPU engine plugin.
 *
 * GAP 06 T5.2. The public surface is intentionally minimal until the
 * Qualcomm Genie C API is wired. Without the Qualcomm SDK, the plugin shell
 * stays buildable but rejects registration so the router cannot advertise it
 * as a functional LLM backend.
 *
 * ### Qualcomm Genie C API brief
 *
 * The Genie SDK (part of Qualcomm QAIRT / QNN distribution) exposes a C
 * API whose core types live in `<GenieCommon.h>` / `<GenieDialog.h>`:
 *
 *   - `GenieDialogConfig_Handle_t`  — parsed JSON config handle
 *                                     (built from a Genie JSON manifest).
 *   - `GenieDialog_Handle_t`        — LLM dialog session running on HTP.
 *   - `Genie_Status_t`              — return code enum
 *                                     (GENIE_STATUS_SUCCESS etc.).
 *   - `Genie_Log_Handle_t`          — logging sink.
 *
 * Typical lifecycle:
 *   GenieDialogConfig_createFromJson(json_text, &cfg);
 *   GenieDialog_create(cfg, &dialog);
 *   GenieDialog_query(dialog, prompt, GENIE_DIALOG_SENTENCE_END,
 *                     token_cb, user_data);
 *   GenieDialog_free(dialog);
 *   GenieDialogConfig_free(cfg);
 *
 * None of those types are referenced here because the repo does not
 * vendor the Qualcomm headers. Phase 2 introduces a translation unit
 * gated on `RAC_GENIE_SDK_AVAILABLE=1` that owns the real C API handles.
 */

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Marker returned by genie_backend_build_info().
 *
 * Lets tests assert the shell compiled against the expected SDK
 * visibility without pulling any Qualcomm headers.
 */
const char* genie_backend_build_info(void);

/**
 * @brief Shared helper used by every llm_ops stub to produce a
 *        consistent "plugin compiled without the Genie SDK" error.
 *
 * Callers MUST propagate this value; it is the contractually-defined
 * error for a missing engine implementation per
 * `rac/core/rac_error.h::RAC_ERROR_BACKEND_UNAVAILABLE`.
 */
rac_result_t genie_backend_unavailable(void);

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_GENIE_BACKEND_H
