/**
 * @file result_free.cpp
 * @brief Result free function implementations
 *
 * Implements memory management for result structures.
 * These are weak symbols that can be overridden by backend implementations.
 */

#include <cstdlib>

#include "rac/features/embeddings/rac_embeddings_types.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_types.h"

// MSVC does not support __attribute__((weak)). On MSVC this whole file is
// excluded from the build via CMakeLists.txt, and each service translation
// unit provides its own strong definition of `rac_*_result_free`. On other
// compilers the weak attribute lets backend-specific .cpp files override
// these fallback definitions at link time.
#ifdef _MSC_VER
#define RAC_WEAK_SYMBOL
#else
#define RAC_WEAK_SYMBOL __attribute__((weak))
#endif

extern "C" {

RAC_WEAK_SYMBOL void rac_llm_result_free(rac_llm_result_t* result) {
    if (result) {
        if (result->text) {
            free(const_cast<char*>(result->text));
            result->text = nullptr;
        }
    }
}

RAC_WEAK_SYMBOL void rac_stt_result_free(rac_stt_result_t* result) {
    if (result) {
        if (result->text) {
            free(const_cast<char*>(result->text));
            result->text = nullptr;
        }
        if (result->detected_language) {
            free(result->detected_language);
            result->detected_language = nullptr;
        }
        if (result->words) {
            // Free individual word allocations
            for (size_t i = 0; i < result->num_words; i++) {
                if (result->words[i].text) {
                    free(const_cast<char*>(result->words[i].text));
                }
            }
            free(result->words);
            result->words = nullptr;
            result->num_words = 0;
        }
    }
}

RAC_WEAK_SYMBOL void rac_tts_result_free(rac_tts_result_t* result) {
    if (result) {
        if (result->audio_data) {
            free(result->audio_data);
            result->audio_data = nullptr;
        }
        result->audio_size = 0;
    }
}

RAC_WEAK_SYMBOL void rac_embeddings_result_free(rac_embeddings_result_t* result) {
    if (result) {
        if (result->embeddings) {
            for (size_t i = 0; i < result->num_embeddings; i++) {
                if (result->embeddings[i].data) {
                    free(result->embeddings[i].data);
                    result->embeddings[i].data = nullptr;
                }
            }
            free(result->embeddings);
            result->embeddings = nullptr;
        }
        result->num_embeddings = 0;
        result->dimension = 0;
    }
}

}  // extern "C"
