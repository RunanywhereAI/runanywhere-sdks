/**
 * grammar_jni.cpp - Grammar-Based Constrained Generation for Tool Calling
 *
 * ⚠️ DEPRECATED - This implementation is no longer used in production
 *
 * STATUS: Preserved for reference, switched to prompt-based approach
 * REASON: llama.cpp grammar bugs causing SIGABRT crashes
 * SEE: GRAMMAR_IMPLEMENTATION_NOTES.md for full investigation details
 *
 * WHAT THIS FILE DOES:
 * - Converts JSON schemas to GBNF (Grammar-Based Natural Format) rules
 * - Creates grammar samplers that constrain LLM output to valid JSON
 * - Builds sampler chains with grammar as the final constraint
 *
 * WHY IT DIDN'T WORK:
 * 1. llama.cpp grammar stack bugs (unfixed as of Oct 2025)
 * 2. Chat template interference with Qwen2 models
 * 3. Missing additionalProperties: false in schemas
 * 4. Complex C++ debugging for mobile crashes
 *
 * WHAT WE LEARNED:
 * - Grammar guarantees valid JSON but crashes make it unusable in production
 * - Prompt-based approaches with few-shot examples are more reliable
 * - Production reliability > theoretical guarantees
 * - Small models (0.5B) work better with few-shot examples than grammar rules
 *
 * OWNERSHIP SEMANTICS (CRITICAL):
 * - Grammar sampler created by createGrammar()
 * - Passed to new_sampler_with_grammar()
 * - Added to chain via llama_sampler_chain_add()
 * - ⚠️ CHAIN TAKES OWNERSHIP - do not free grammar separately!
 * - When chain is freed, it automatically frees all child samplers
 * - Double-free causes SIGSEGV crash
 *
 * PRESERVED FOR: Reference, future llama.cpp improvements, research
 */

#include <android/log.h>
#include <jni.h>
#include <string>
#include <vector>
#include <cstring>
#include "llama.h"
#include "json-schema-to-grammar.h"

#define TAG "grammar-jni"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// JNI: Convert JSON schema to GBNF grammar
extern "C"
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_GrammarBridge_jsonSchemaToGBNF(
    JNIEnv* env,
    jobject /* this */,
    jstring j_schema
) {
    if (!j_schema) {
        env->ThrowNew(
            env->FindClass("java/lang/IllegalArgumentException"),
            "JSON schema cannot be null"
        );
        return nullptr;
    }

    const char* schema = env->GetStringUTFChars(j_schema, nullptr);
    if (!schema) {
        return nullptr;
    }

    try {
        LOGi("Converting JSON schema to GBNF...");

        // Use llama.cpp's json_schema_to_grammar function
        auto schema_str = json_schema_to_grammar(nlohmann::json::parse(schema));

        env->ReleaseStringUTFChars(j_schema, schema);

        LOGi("GBNF conversion successful, rules length: %zu", schema_str.size());

        return env->NewStringUTF(schema_str.c_str());

    } catch (const std::exception& e) {
        env->ReleaseStringUTFChars(j_schema, schema);

        LOGe("Error converting schema to GBNF: %s", e.what());

        jclass exceptionClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exceptionClass, e.what());

        return nullptr;
    }
}

// JNI: Create grammar sampler from GBNF string
// Note: The new llama.cpp API uses samplers for grammar, not separate grammar objects
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_GrammarBridge_createGrammar(
    JNIEnv* env,
    jobject /* this */,
    jlong model_pointer,
    jstring j_gbnf
) {
    if (!j_gbnf) {
        env->ThrowNew(
            env->FindClass("java/lang/IllegalArgumentException"),
            "GBNF rules cannot be null"
        );
        return 0;
    }

    const char* gbnf = env->GetStringUTFChars(j_gbnf, nullptr);
    if (!gbnf) {
        return 0;
    }

    try {
        auto model = reinterpret_cast<llama_model*>(model_pointer);
        if (!model) {
            env->ReleaseStringUTFChars(j_gbnf, gbnf);
            env->ThrowNew(
                env->FindClass("java/lang/IllegalArgumentException"),
                "Model cannot be null"
            );
            return 0;
        }

        LOGi("Creating grammar sampler from GBNF rules...");

        // Use the new sampler API for grammar
        // This creates a sampler that constrains output to the grammar
        llama_sampler* grammar_sampler = llama_sampler_init_grammar(
            model,
            gbnf,
            "root"  // Grammar root rule
        );

        env->ReleaseStringUTFChars(j_gbnf, gbnf);

        if (!grammar_sampler) {
            LOGe("Failed to create grammar sampler");
            env->ThrowNew(
                env->FindClass("java/lang/RuntimeException"),
                "Failed to create grammar sampler from GBNF rules"
            );
            return 0;
        }

        LOGi("Grammar sampler created successfully");

        return reinterpret_cast<jlong>(grammar_sampler);

    } catch (const std::exception& e) {
        env->ReleaseStringUTFChars(j_gbnf, gbnf);

        LOGe("Error creating grammar sampler: %s", e.what());

        jclass exceptionClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exceptionClass, e.what());

        return 0;
    }
}

// JNI: Free grammar sampler
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_GrammarBridge_freeGrammar(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong grammar_pointer
) {
    auto grammar_sampler = reinterpret_cast<llama_sampler*>(grammar_pointer);
    if (grammar_sampler) {
        LOGi("Freeing grammar sampler");
        llama_sampler_free(grammar_sampler);
    }
}

// JNI: Create sampler chain WITH grammar
// IMPORTANT: The grammar sampler is ADDED TO THE CHAIN and the chain TAKES OWNERSHIP
// - When llama_sampler_chain_add() is called, the chain takes ownership of the sampler
// - When the chain is freed, it automatically frees all samplers added to it
// - DO NOT call llama_sampler_free() on the grammar separately - it will cause double-free!
// - The Kotlin code must NOT call grammar.close() after creating the chain
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_new_1sampler_1with_1grammar(
    JNIEnv* /* env */,
    jobject /* this */,
    jfloat temperature,
    jfloat min_p,
    jint top_k,
    jlong grammar_pointer
) {
    auto grammar_sampler = reinterpret_cast<llama_sampler*>(grammar_pointer);

    LOGi("Creating sampler chain with grammar: temp=%.2f, min_p=%.2f, top_k=%d, grammar=%p",
         temperature, min_p, top_k, grammar_sampler);

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler* chain = llama_sampler_chain_init(sparams);

    // Add sampling strategies based on parameters
    // IMPORTANT: Grammar sampler must be LAST in the chain!
    // Order: temp -> min_p -> top_k -> dist/greedy -> GRAMMAR
    if (temperature > 0.0f) {
        // Temperature-based sampling
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));

        // Add min-P sampling if specified
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(min_p, 1));
        }

        // Add top-K sampling if specified
        if (top_k > 0) {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(top_k));
        }

        // Distribution sampler for probabilistic selection
        llama_sampler_chain_add(chain, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

        // Add grammar constraints LAST (after distribution sampler)
        // CRITICAL: Grammar must be last to properly constrain token selection
        // Chain takes ownership! Do not free grammar separately after this!
        if (grammar_sampler) {
            llama_sampler_chain_add(chain, grammar_sampler);
            LOGi("Grammar sampler added to chain as LAST sampler (ownership transferred)");
        }

    } else {
        // Greedy sampling (deterministic)
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());

        // Add grammar AFTER greedy sampler
        if (grammar_sampler) {
            llama_sampler_chain_add(chain, grammar_sampler);
            LOGi("Grammar sampler added to greedy chain as LAST sampler (ownership transferred)");
        }
    }

    LOGi("Sampler chain created with %d samplers", grammar_sampler ? 1 : 0);

    return reinterpret_cast<jlong>(chain);
}
