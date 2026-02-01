/**
 * @file qnn_device_detector.cpp
 * @brief QNN Device Detection for Qualcomm SoC and NPU capabilities
 *
 * Detects Qualcomm SoC information and NPU (HTP) availability on Android devices.
 * Uses system properties and /proc/cpuinfo to identify the SoC.
 */

#include "rac/backends/rac_qnn_config.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#include <android/log.h>
#define QNN_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "QNN_Detect", __VA_ARGS__)
#define QNN_LOGW(...) __android_log_print(ANDROID_LOG_WARN, "QNN_Detect", __VA_ARGS__)
#define QNN_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "QNN_Detect", __VA_ARGS__)
#else
#define QNN_LOGI(...) printf("[QNN_Detect] " __VA_ARGS__); printf("\n")
#define QNN_LOGW(...) printf("[QNN_Detect WARN] " __VA_ARGS__); printf("\n")
#define QNN_LOGE(...) fprintf(stderr, "[QNN_Detect ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#endif

#define LOG_CAT "QNN"

namespace {

// =============================================================================
// KNOWN QUALCOMM SOC DATABASE
// =============================================================================

struct SoCEntry {
    int32_t soc_id;
    const char* name;
    const char* marketing_name;
    int32_t hexagon_arch;
    float htp_tops;
    bool htp_available;
};

// Known Qualcomm SoCs with HTP/NPU support
// Source: Qualcomm QNN documentation
static const SoCEntry KNOWN_SOCS[] = {
    // === Snapdragon 8 Elite / Gen 4 Series (2024-2025) ===
    // Snapdragon 8 Elite (SM8750) - V81 Hexagon - Samsung S25 Ultra, etc.
    {69, "SM8750", "Snapdragon 8 Elite", 81, 75.0f, true},
    // Alternative SoC IDs that might be reported for SM8750
    {614, "SM8750", "Snapdragon 8 Elite", 81, 75.0f, true},
    {615, "SM8750", "Snapdragon 8 Elite", 81, 75.0f, true},

    // === Snapdragon 8 Gen 3 Series ===
    // Snapdragon 8 Gen 3 (SM8650) - V75 Hexagon
    {57, "SM8650", "Snapdragon 8 Gen 3", 75, 45.0f, true},
    // Alternative SoC IDs for SM8650
    {557, "SM8650", "Snapdragon 8 Gen 3", 75, 45.0f, true},
    // Snapdragon 8s Gen 3 (SM8635) - V73 Hexagon
    {63, "SM8635", "Snapdragon 8s Gen 3", 73, 36.0f, true},

    // === Snapdragon 8 Gen 2 Series ===
    // Snapdragon 8 Gen 2 (SM8550) - V73 Hexagon
    {53, "SM8550", "Snapdragon 8 Gen 2", 73, 36.0f, true},
    // Alternative SoC IDs for SM8550
    {519, "SM8550", "Snapdragon 8 Gen 2", 73, 36.0f, true},

    // === Snapdragon 8 Gen 1 Series ===
    // Snapdragon 8+ Gen 1 (SM8475) - V69 Hexagon
    {43, "SM8475", "Snapdragon 8+ Gen 1", 69, 27.0f, true},
    // Snapdragon 8 Gen 1 (SM8450) - V69 Hexagon
    {36, "SM8450", "Snapdragon 8 Gen 1", 69, 27.0f, true},
    // Alternative SoC IDs for SM8450
    {457, "SM8450", "Snapdragon 8 Gen 1", 69, 27.0f, true},

    // === Snapdragon 7 Series ===
    // Snapdragon 7+ Gen 3 (SM7550) - V73 Hexagon
    {62, "SM7550", "Snapdragon 7+ Gen 3", 73, 24.0f, true},
    // Snapdragon 7+ Gen 2 (SM7475) - V69 Hexagon
    {54, "SM7475", "Snapdragon 7+ Gen 2", 69, 18.0f, true},

    // === Snapdragon 888 Series ===
    // Snapdragon 888+ (SM8350) - V68 Hexagon
    {30, "SM8350", "Snapdragon 888+", 68, 26.0f, true},
    // Snapdragon 888 (SM8350) - V68 Hexagon
    {24, "SM8350-AB", "Snapdragon 888", 68, 26.0f, true},

    // Terminator
    {0, nullptr, nullptr, 0, 0.0f, false},
};

// Minimum supported Hexagon architecture for QNN HTP
constexpr int32_t MIN_HEXAGON_ARCH = 68;

// Platform codename to SoC mapping
// Qualcomm uses internal codenames for ro.board.platform
struct PlatformCodename {
    const char* codename;
    int32_t soc_id;
    const char* marketing_name;
};

static const PlatformCodename PLATFORM_CODENAMES[] = {
    // Snapdragon 8 Elite (SM8750) - "sun" codename
    {"sun", 69, "Snapdragon 8 Elite"},

    // Snapdragon 8 Gen 3 (SM8650) - "pineapple" codename
    {"pineapple", 57, "Snapdragon 8 Gen 3"},

    // Snapdragon 8 Gen 2 (SM8550) - "kalama" codename
    {"kalama", 53, "Snapdragon 8 Gen 2"},

    // Snapdragon 8 Gen 1 (SM8450) - "waipio" codename
    {"waipio", 36, "Snapdragon 8 Gen 1"},

    // Snapdragon 8+ Gen 1 (SM8475) - "cape" codename
    {"cape", 43, "Snapdragon 8+ Gen 1"},

    // Snapdragon 888 (SM8350) - "lahaina" codename
    {"lahaina", 24, "Snapdragon 888"},

    // Snapdragon 7+ Gen 3 (SM7550)
    {"crow", 62, "Snapdragon 7+ Gen 3"},

    // Terminator
    {nullptr, 0, nullptr},
};

#ifdef __ANDROID__

/**
 * @brief Get Android system property
 */
std::string get_system_property(const char* name) {
    char value[PROP_VALUE_MAX] = {0};
    int len = __system_property_get(name, value);
    if (len > 0) {
        return std::string(value, len);
    }
    return "";
}

/**
 * @brief Detect SoC ID from Android system properties
 */
int32_t detect_soc_id_from_properties() {
    QNN_LOGI("detect_soc_id_from_properties() called");

    // Try various property names used by different Android versions/OEMs
    static const char* SOC_ID_PROPS[] = {
        "ro.soc.id",
        "ro.board.platform",
        "ro.hardware.chipname",
        "ro.hardware",
        nullptr,
    };

    for (const char** prop = SOC_ID_PROPS; *prop != nullptr; ++prop) {
        std::string value = get_system_property(*prop);
        QNN_LOGI("  Property %s = '%s'", *prop, value.c_str());
        if (!value.empty()) {
            // Try to parse as numeric SoC ID
            int soc_id = 0;
            if (sscanf(value.c_str(), "%d", &soc_id) == 1 && soc_id > 0) {
                QNN_LOGI("  -> Detected numeric SoC ID %d from property %s", soc_id, *prop);
                RAC_LOG_DEBUG(LOG_CAT, "Detected SoC ID %d from property %s", soc_id, *prop);
                return soc_id;
            }

            // Try to match by name (e.g., "sm8650", "kona", etc.)
            for (const SoCEntry* entry = KNOWN_SOCS; entry->name != nullptr; ++entry) {
                // Case-insensitive comparison
                std::string lower_value = value;
                for (auto& c : lower_value) {
                    c = static_cast<char>(tolower(c));
                }
                std::string lower_name = entry->name;
                for (auto& c : lower_name) {
                    c = static_cast<char>(tolower(c));
                }

                if (lower_value.find(lower_name) != std::string::npos) {
                    QNN_LOGI("  -> Matched SoC name: %s (ID %d)", entry->name, entry->soc_id);
                    RAC_LOG_DEBUG(LOG_CAT, "Detected SoC %s (ID %d) from property %s=%s",
                                  entry->name, entry->soc_id, *prop, value.c_str());
                    return entry->soc_id;
                }
            }

            // Try to match by platform codename (e.g., "sun" = Snapdragon 8 Elite)
            for (const PlatformCodename* pc = PLATFORM_CODENAMES; pc->codename != nullptr; ++pc) {
                std::string lower_value = value;
                for (auto& c : lower_value) {
                    c = static_cast<char>(tolower(c));
                }
                std::string lower_codename = pc->codename;
                for (auto& c : lower_codename) {
                    c = static_cast<char>(tolower(c));
                }

                if (lower_value == lower_codename) {
                    QNN_LOGI("  -> Matched platform codename '%s' = %s (SoC ID %d)",
                             pc->codename, pc->marketing_name, pc->soc_id);
                    RAC_LOG_DEBUG(LOG_CAT, "Detected SoC from platform codename %s=%s (ID %d)",
                                  *prop, value.c_str(), pc->soc_id);
                    return pc->soc_id;
                }
            }
        }
    }

    return 0;  // Unknown
}

/**
 * @brief Detect SoC from /proc/cpuinfo
 */
int32_t detect_soc_from_cpuinfo() {
    std::ifstream cpuinfo("/proc/cpuinfo");
    if (!cpuinfo.is_open()) {
        return 0;
    }

    std::string line;
    while (std::getline(cpuinfo, line)) {
        // Look for "Hardware" line
        if (line.find("Hardware") != std::string::npos) {
            // Convert to lowercase for matching
            std::string lower_line = line;
            for (auto& c : lower_line) {
                c = static_cast<char>(tolower(c));
            }

            // Check against known SoCs
            for (const SoCEntry* entry = KNOWN_SOCS; entry->name != nullptr; ++entry) {
                std::string lower_name = entry->name;
                for (auto& c : lower_name) {
                    c = static_cast<char>(tolower(c));
                }

                if (lower_line.find(lower_name) != std::string::npos) {
                    RAC_LOG_DEBUG(LOG_CAT, "Detected SoC %s (ID %d) from cpuinfo: %s", entry->name,
                                  entry->soc_id, line.c_str());
                    return entry->soc_id;
                }
            }
        }
    }

    return 0;  // Unknown
}

/**
 * @brief Check if QNN libraries are available
 */
bool check_qnn_libraries_available() {
    QNN_LOGI("check_qnn_libraries_available() called");

    // Check for HTP library existence
    static const char* QNN_LIB_PATHS[] = {
        "/vendor/lib64/libQnnHtp.so",
        "/system/lib64/libQnnHtp.so",
        "/data/local/tmp/libQnnHtp.so",
        nullptr,
    };

    for (const char** path = QNN_LIB_PATHS; *path != nullptr; ++path) {
        std::ifstream lib(*path);
        bool found = lib.good();
        QNN_LOGI("  Checking %s: %s", *path, found ? "FOUND" : "not found");
        if (found) {
            RAC_LOG_DEBUG(LOG_CAT, "Found QNN HTP library at: %s", *path);
            return true;
        }
    }

    // QNN libraries might be bundled with the app - assume available if on supported SoC
    QNN_LOGI("  No system QNN libs found, assuming app-bundled libs available");
    return true;
}

#else  // Non-Android platforms

int32_t detect_soc_id_from_properties() {
    return 0;  // Not supported
}

int32_t detect_soc_from_cpuinfo() {
    return 0;  // Not supported
}

bool check_qnn_libraries_available() {
    return false;  // QNN is Android-only
}

#endif  // __ANDROID__

/**
 * @brief Look up SoC entry by ID
 */
const SoCEntry* lookup_soc_by_id(int32_t soc_id) {
    for (const SoCEntry* entry = KNOWN_SOCS; entry->name != nullptr; ++entry) {
        if (entry->soc_id == soc_id) {
            return entry;
        }
    }
    return nullptr;
}

/**
 * @brief Cached SoC detection result
 */
struct CachedSoCInfo {
    bool initialized = false;
    bool available = false;
    rac_soc_info_t info = {};
};

CachedSoCInfo& get_cached_info() {
    static CachedSoCInfo cache;
    return cache;
}

void detect_soc_info(CachedSoCInfo& cache) {
    if (cache.initialized) {
        return;
    }

    cache.initialized = true;
    cache.available = false;

    // Initialize with unknown values
    memset(&cache.info, 0, sizeof(cache.info));
    strncpy(cache.info.name, "Unknown", sizeof(cache.info.name) - 1);
    strncpy(cache.info.marketing_name, "Unknown", sizeof(cache.info.marketing_name) - 1);

#if RAC_QNN_AVAILABLE
    // Try to detect SoC ID
    int32_t soc_id = detect_soc_id_from_properties();
    if (soc_id == 0) {
        soc_id = detect_soc_from_cpuinfo();
    }

    QNN_LOGI("=== QNN Device Detection ===");
    QNN_LOGI("Detected SoC ID: %d", soc_id);
    RAC_LOG_INFO(LOG_CAT, "=== QNN Device Detection ===");
    RAC_LOG_INFO(LOG_CAT, "Detected SoC ID: %d", soc_id);

    if (soc_id > 0) {
        const SoCEntry* entry = lookup_soc_by_id(soc_id);
        if (entry != nullptr) {
            cache.info.soc_id = entry->soc_id;
            strncpy(cache.info.name, entry->name, sizeof(cache.info.name) - 1);
            strncpy(cache.info.marketing_name, entry->marketing_name,
                    sizeof(cache.info.marketing_name) - 1);
            cache.info.hexagon_arch = entry->hexagon_arch;
            cache.info.htp_available = entry->htp_available;
            cache.info.htp_tops = entry->htp_tops;

            QNN_LOGI("Matched known SoC: %s (%s), Hexagon V%d",
                     entry->name, entry->marketing_name, entry->hexagon_arch);
            RAC_LOG_INFO(LOG_CAT, "Matched known SoC: %s (%s), Hexagon V%d",
                         entry->name, entry->marketing_name, entry->hexagon_arch);

            // Check if Hexagon architecture is supported
            if (entry->hexagon_arch >= MIN_HEXAGON_ARCH && check_qnn_libraries_available()) {
                cache.available = true;
                QNN_LOGI("QNN HTP AVAILABLE: %s (%s), Hexagon V%d, %.1f TOPS",
                         entry->name, entry->marketing_name, entry->hexagon_arch,
                         entry->htp_tops);
                RAC_LOG_INFO(LOG_CAT, "QNN HTP AVAILABLE: %s (%s), Hexagon V%d, %.1f TOPS",
                             entry->name, entry->marketing_name, entry->hexagon_arch,
                             entry->htp_tops);
            } else {
                QNN_LOGI("QNN HTP not available: Hexagon V%d < V%d minimum",
                         entry->hexagon_arch, MIN_HEXAGON_ARCH);
                RAC_LOG_INFO(LOG_CAT, "QNN HTP not available: Hexagon V%d < V%d minimum",
                             entry->hexagon_arch, MIN_HEXAGON_ARCH);
            }
        } else {
            // Unknown SoC ID - try to enable QNN anyway for modern Qualcomm chips
            cache.info.soc_id = soc_id;
            snprintf(cache.info.name, sizeof(cache.info.name), "Qualcomm-SoC-%d", soc_id);
            strncpy(cache.info.marketing_name, "Unknown Qualcomm SoC",
                    sizeof(cache.info.marketing_name) - 1);

            QNN_LOGW("Unknown SoC ID %d - not in database", soc_id);
            RAC_LOG_WARNING(LOG_CAT, "Unknown SoC ID %d - not in database", soc_id);

            // For unknown Qualcomm SoCs, assume modern Hexagon (V75+) and try QNN
            // This handles new chips not yet in the database
            if (check_qnn_libraries_available()) {
                cache.info.hexagon_arch = 75;  // Assume modern
                cache.info.htp_available = true;
                cache.info.htp_tops = 30.0f;  // Conservative estimate
                cache.available = true;
                QNN_LOGI("QNN HTP ENABLED for unknown SoC %d (assuming modern Hexagon)", soc_id);
                RAC_LOG_INFO(LOG_CAT, "QNN HTP ENABLED for unknown SoC %d (assuming modern Hexagon)", soc_id);
            } else {
                QNN_LOGW("QNN libraries not found for unknown SoC %d", soc_id);
                RAC_LOG_WARNING(LOG_CAT, "QNN libraries not found for unknown SoC %d", soc_id);
            }
        }
    } else {
        QNN_LOGI("Could not detect Qualcomm SoC (soc_id=0) - QNN not available");
        RAC_LOG_INFO(LOG_CAT, "Could not detect Qualcomm SoC - QNN not available");
    }
#else
    RAC_LOG_DEBUG(LOG_CAT, "QNN support not compiled in (RAC_QNN_AVAILABLE=0)");
#endif
}

}  // namespace

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_bool_t rac_qnn_is_available(void) {
    QNN_LOGI("=== rac_qnn_is_available() called ===");
#if RAC_QNN_AVAILABLE
    QNN_LOGI("RAC_QNN_AVAILABLE=1 (QNN compiled in)");
    CachedSoCInfo& cache = get_cached_info();
    detect_soc_info(cache);
    rac_bool_t result = cache.available ? RAC_TRUE : RAC_FALSE;
    QNN_LOGI("rac_qnn_is_available() returning %d (cache.available=%d)", result, cache.available ? 1 : 0);
    return result;
#else
    QNN_LOGW("RAC_QNN_AVAILABLE=0 (QNN NOT compiled in)");
    return RAC_FALSE;
#endif
}

rac_result_t rac_qnn_get_soc_info(rac_soc_info_t* out_info) {
    QNN_LOGI("=== rac_qnn_get_soc_info() called ===");
    if (out_info == nullptr) {
        QNN_LOGE("NULL pointer for out_info");
        return RAC_ERROR_NULL_POINTER;
    }

#if RAC_QNN_AVAILABLE
    CachedSoCInfo& cache = get_cached_info();
    detect_soc_info(cache);

    *out_info = cache.info;
    QNN_LOGI("rac_qnn_get_soc_info() returning: soc_id=%d, name=%s, hexagon_arch=%d, htp_available=%d",
             out_info->soc_id, out_info->name, out_info->hexagon_arch, out_info->htp_available ? 1 : 0);
    return RAC_SUCCESS;
#else
    memset(out_info, 0, sizeof(*out_info));
    strncpy(out_info->name, "Not Available", sizeof(out_info->name) - 1);
    strncpy(out_info->marketing_name, "QNN not compiled", sizeof(out_info->marketing_name) - 1);
    QNN_LOGW("QNN not compiled, returning RAC_ERROR_QNN_NOT_AVAILABLE");
    return RAC_ERROR_QNN_NOT_AVAILABLE;
#endif
}

rac_result_t rac_qnn_get_soc_info_json(char* out_json, size_t json_size) {
    if (out_json == nullptr || json_size == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_soc_info_t info;
    rac_result_t result = rac_qnn_get_soc_info(&info);

    // Always return JSON, even if QNN not available
    int written = snprintf(out_json, json_size,
                           "{"
                           "\"name\":\"%s\","
                           "\"soc_id\":%d,"
                           "\"hexagon_arch\":%d,"
                           "\"marketing_name\":\"%s\","
                           "\"htp_available\":%s,"
                           "\"htp_tops\":%.1f"
                           "}",
                           info.name, info.soc_id, info.hexagon_arch, info.marketing_name,
                           info.htp_available ? "true" : "false", info.htp_tops);

    if (written < 0 || static_cast<size_t>(written) >= json_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    return result;
}

void rac_qnn_config_init_default(rac_qnn_config_t* config) {
    if (config == nullptr) {
        return;
    }

    config->backend = RAC_QNN_BACKEND_HTP;
    config->performance_mode = RAC_HTP_PERF_BURST;
    config->precision = RAC_HTP_PRECISION_INT8;
    config->vtcm_mb = 8;
    config->disable_cpu_fallback = RAC_FALSE;  // Hybrid mode for Kokoro
    config->enable_context_cache = RAC_TRUE;
    config->context_cache_path = nullptr;
    config->num_htp_threads = 0;  // Auto-detect
    config->enable_profiling = RAC_FALSE;
    config->soc_id = 0;  // Auto-detect
    config->strategy = RAC_NPU_STRATEGY_HYBRID;
}

void rac_split_model_config_init(rac_split_model_config_t* config, const char* encoder_path,
                                 const char* vocoder_path) {
    if (config == nullptr) {
        return;
    }

    config->encoder_path = encoder_path;
    config->vocoder_path = vocoder_path;
    config->encoder_is_quantized = RAC_TRUE;
    config->encoder_output_names = nullptr;
    config->vocoder_input_names = nullptr;
}

rac_result_t rac_qnn_get_supported_ops(char* out_ops, size_t ops_size) {
    if (out_ops == nullptr || ops_size == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    // List of ONNX operators supported on QNN HTP (from official documentation)
    static const char* SUPPORTED_OPS =
        "Conv,MatMul,LayerNormalization,Gelu,BatchNormalization,ConvTranspose,"
        "Relu,Sigmoid,Tanh,Softmax,Add,Sub,Mul,Div,Concat,Split,Reshape,Transpose,"
        "Squeeze,Unsqueeze,Gather,Slice,Pad,MaxPool,AveragePool,GlobalAveragePool,"
        "ReduceMean,ReduceSum,Gemm,Cast,Clip,LeakyRelu,PRelu,Sqrt,Pow,Exp,Log,"
        "Sin,Cos,Erf,Where,Less,Greater,Equal,And,Or,Not,Expand,Tile,Flatten,"
        "InstanceNormalization,LRN,Resize,Upsample,DepthToSpace,SpaceToDepth";

    size_t len = strlen(SUPPORTED_OPS);
    if (len >= ops_size) {
        strncpy(out_ops, SUPPORTED_OPS, ops_size - 1);
        out_ops[ops_size - 1] = '\0';
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    strcpy(out_ops, SUPPORTED_OPS);
    return RAC_SUCCESS;
}

}  // extern "C"
