#include "model_versioning.h"

#include <sstream>

std::string rac_generate_versioned_model_id(const char* model_id,
                                            const char* version) {
    if (!model_id || !version) return "";

    std::stringstream ss;
    ss << model_id << "@" << version;
    return ss.str();
}

rac_bool_t rac_model_version_matches(const char* versioned_id,
                                     const char* expected_version) {
    if (!versioned_id || !expected_version) return RAC_FALSE;

    std::string id(versioned_id);
    size_t pos = id.find("@");
    if (pos == std::string::npos) return RAC_FALSE;

    std::string version = id.substr(pos + 1);
    return (version == expected_version) ? RAC_TRUE : RAC_FALSE;
}

std::string rac_extract_base_model_id(const char* versioned_id) {
    if (!versioned_id) return "";

    std::string id(versioned_id);
    size_t pos = id.find("@");
    if (pos == std::string::npos) return id;

    return id.substr(0, pos);
}

std::string rac_extract_version(const char* versioned_id) {
    if (!versioned_id) return "";

    std::string id(versioned_id);
    size_t pos = id.find("@");
    if (pos == std::string::npos) return "";

    return id.substr(pos + 1);
}

#include <functional>

std::string rac_generate_deterministic_version(const char* download_url) {
    if (!download_url) return "unknown";

    std::hash<std::string> hasher;
    size_t hash = hasher(std::string(download_url));

    std::stringstream ss;
    ss << std::hex << hash;
    return ss.str();
}