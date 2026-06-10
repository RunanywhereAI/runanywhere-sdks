#include "catalog/url_registry.h"

#include <filesystem>
#include <fstream>
#include <system_error>

#include "rac/core/rac_core.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "io/output.h"

namespace rcli::url_registry {

namespace {

namespace fs = std::filesystem;

// <storage root>/Registry — sibling of Models/, derived through the same
// commons base-dir logic so --home/RUNANYWHERE_HOME move it together.
fs::path registry_dir() {
    char base[1024] = {};
    if (rac_model_paths_get_base_directory(base, sizeof(base)) != RAC_SUCCESS) {
        return {};
    }
    return fs::path(base) / "Registry";
}

// Same conservative charset as the secure store: ids are registry keys, not
// trusted filenames.
std::string sanitize_id(const std::string& model_id) {
    std::string safe;
    safe.reserve(model_id.size());
    for (const char c : model_id) {
        const bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                        (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
        safe.push_back(ok ? c : '_');
    }
    return safe;
}

}  // namespace

void register_all_persisted() {
    const fs::path dir = registry_dir();
    if (dir.empty()) {
        return;
    }
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) {
        return;
    }
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (ec || !entry.is_regular_file() || entry.path().extension() != ".binpb") {
            continue;
        }
        std::ifstream file(entry.path(), std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(file)),
                          std::istreambuf_iterator<char>());
        if (bytes.empty()) {
            continue;
        }
        rac_proto_buffer_t saved;
        rac_proto_buffer_init(&saved);
        const rac_result_t rc = rac_model_registry_register_proto_buffer(
            rac_get_model_registry(), reinterpret_cast<const uint8_t*>(bytes.data()),
            bytes.size(), &saved);
        if (rc != RAC_SUCCESS || saved.status != RAC_SUCCESS) {
            out::status_line("warning: failed to re-register persisted model " +
                             entry.path().filename().string());
        }
        rac_proto_buffer_free(&saved);
    }
}

void persist(const std::string& model_id, const std::string& model_info_bytes) {
    const fs::path dir = registry_dir();
    if (dir.empty() || model_id.empty() || model_info_bytes.empty()) {
        return;
    }
    std::error_code ec;
    fs::create_directories(dir, ec);
    const fs::path path = dir / (sanitize_id(model_id) + ".binpb");
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file.write(model_info_bytes.data(),
               static_cast<std::streamsize>(model_info_bytes.size()));
    if (!file.good()) {
        out::status_line("warning: could not persist registration for " + model_id);
    }
}

void forget(const std::string& model_id) {
    const fs::path dir = registry_dir();
    if (dir.empty()) {
        return;
    }
    std::error_code ec;
    fs::remove(dir / (sanitize_id(model_id) + ".binpb"), ec);
}

}  // namespace rcli::url_registry
