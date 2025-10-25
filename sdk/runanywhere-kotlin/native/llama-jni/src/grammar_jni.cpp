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

// JNI: Create grammar from GBNF string
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

        LOGi("Creating grammar from GBNF rules...");

        // Parse GBNF rules into llama_grammar
        auto parsed_grammar = grammar_parser::parse(gbnf);

        // Create grammar instance
        auto grammar_rules = parsed_grammar.c_rules();

        llama_grammar* grammar = llama_grammar_init(
            grammar_rules.data(),
            grammar_rules.size(),
            parsed_grammar.symbol_ids.at("root")
        );

        env->ReleaseStringUTFChars(j_gbnf, gbnf);

        if (!grammar) {
            LOGe("Failed to create grammar");
            env->ThrowNew(
                env->FindClass("java/lang/RuntimeException"),
                "Failed to create grammar from GBNF rules"
            );
            return 0;
        }

        LOGi("Grammar created successfully");

        return reinterpret_cast<jlong>(grammar);

    } catch (const std::exception& e) {
        env->ReleaseStringUTFChars(j_gbnf, gbnf);

        LOGe("Error creating grammar: %s", e.what());

        jclass exceptionClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exceptionClass, e.what());

        return 0;
    }
}

// JNI: Free grammar
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_GrammarBridge_freeGrammar(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong grammar_pointer
) {
    auto grammar = reinterpret_cast<llama_grammar*>(grammar_pointer);
    if (grammar) {
        LOGi("Freeing grammar");
        llama_grammar_free(grammar);
    }
}

// JNI: Create sampler with grammar constraints
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
    auto grammar = reinterpret_cast<llama_grammar*>(grammar_pointer);

    LOGi("Creating sampler with grammar: temp=%.2f, min_p=%.2f, top_k=%d, grammar=%p",
         temperature, min_p, top_k, grammar);

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler* smpl = llama_sampler_chain_init(sparams);

    // Add sampling strategies based on parameters
    if (temperature > 0.0f) {
        // Temperature-based sampling
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));

        // Add min-P sampling if specified
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(smpl, llama_sampler_init_min_p(min_p, 1));
        }

        // Add top-K sampling if specified
        if (top_k > 0) {
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(top_k));
        }

        // Add grammar constraints BEFORE distribution sampler
        if (grammar) {
            llama_sampler_chain_add(smpl, llama_sampler_init_grammar(
                llama_get_model(nullptr), // We'll use grammar instance directly
                grammar,
                nullptr
            ));
            LOGi("Grammar sampler added to chain");
        }

        // Distribution sampler for probabilistic selection
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    } else {
        // Greedy sampling (deterministic)
        // Even with greedy, apply grammar constraints
        if (grammar) {
            llama_sampler_chain_add(smpl, llama_sampler_init_grammar(
                llama_get_model(nullptr),
                grammar,
                nullptr
            ));
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
        LOGi("Created greedy sampler with grammar");
    }

    return reinterpret_cast<jlong>(smpl);
}
