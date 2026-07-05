/**
 * @file hf_resolver.cpp
 * @brief Hugging Face reference resolution (see hf_resolver.h).
 *
 * Selection logic mirrors llama.cpp's battle-tested `-hf` flag: a quant tag
 * matches case-insensitively against GGUF basenames at a `[.-]` boundary, the
 * no-tag default chain is Q4_K_M -> Q8_0 -> first model GGUF, `mmproj` /
 * `imatrix` files are excluded from primary selection, the mmproj sibling is
 * auto-paired for vision repos, and sharded `-NNNNN-of-NNNNN.gguf` sets are
 * expanded so the whole split set downloads together (llama.cpp loads splits
 * natively from the first shard).
 */

#include "hf_resolver.h"

#include <algorithm>
#include <cctype>
#include <map>
#include <nlohmann/json.hpp>
#include <regex>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace rac::infra::model_management::hf {

namespace {

constexpr const char* LOG_CAT = "HFResolver";
constexpr int32_t kTreeRequestTimeoutMs = 30000;

const char* const kRefPrefixes[] = {
    "hf://",           "https://hf.co/",          "http://hf.co/",
    "hf.co/",          "https://huggingface.co/", "http://huggingface.co/",
    "huggingface.co/",
};

std::string lowercase_copy(const std::string& value) {
    std::string out = value;
    std::ranges::transform(out, out.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

std::string basename_of(const std::string& path) {
    const size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string trim_trailing_slashes(std::string path) {
    while (!path.empty() && path.back() == '/') {
        path.pop_back();
    }
    return path;
}

bool has_extension(const std::string& path, const char* ext) {
    if (ext == nullptr || ext[0] == '\0') {
        return false;
    }
    return lowercase_copy(path).ends_with(lowercase_copy(ext));
}

bool is_arch_segment(const std::string& segment) {
    if (segment.size() < 2 || segment[0] != 'v') {
        return false;
    }
    return std::ranges::all_of(segment.begin() + 1, segment.end(),
                               [](unsigned char c) { return std::isdigit(c) != 0; });
}

bool path_starts_with_arch(const std::string& path) {
    const size_t slash = path.find('/');
    const std::string first = slash == std::string::npos ? path : path.substr(0, slash);
    return is_arch_segment(first);
}

std::string query_value(const std::string& query, const std::string& key) {
    size_t start = 0;
    while (start <= query.size()) {
        const size_t end = query.find('&', start);
        const std::string part =
            query.substr(start, end == std::string::npos ? std::string::npos : end - start);
        const size_t eq = part.find('=');
        if (eq != std::string::npos && part.substr(0, eq) == key) {
            return part.substr(eq + 1);
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return {};
}

// Strip a recognized HF prefix; returns "" when none matches.
std::string strip_prefix(const std::string& ref) {
    for (const char* prefix : kRefPrefixes) {
        if (ref.starts_with(prefix)) {
            return ref.substr(std::string(prefix).size());
        }
    }
    return {};
}

struct ParsedRef {
    std::string org;
    std::string repo;
    std::string tag;        // optional quant tag or exact filename
    std::string file_path;  // non-empty for explicit org/repo/path/file refs
};

bool parse_ref(const std::string& ref, ParsedRef* out) {
    std::string rest = strip_prefix(ref);
    if (rest.empty()) {
        return false;
    }
    // Already a concrete file URL fragment — caller handles via
    // normalize_explicit_file_ref.
    const size_t org_end = rest.find('/');
    if (org_end == std::string::npos || org_end == 0) {
        return false;
    }
    out->org = rest.substr(0, org_end);
    std::string after_org = rest.substr(org_end + 1);
    const size_t repo_end = after_org.find('/');
    if (repo_end == std::string::npos) {
        // org/repo[:tag]
        const size_t colon = after_org.find(':');
        if (colon == std::string::npos) {
            out->repo = after_org;
        } else {
            out->repo = after_org.substr(0, colon);
            out->tag = after_org.substr(colon + 1);
        }
        return !out->repo.empty();
    }
    out->repo = after_org.substr(0, repo_end);
    out->file_path = after_org.substr(repo_end + 1);
    return !out->repo.empty() && !out->file_path.empty();
}

std::string sanitize_model_id(const std::string& raw) {
    std::string id;
    id.reserve(raw.size());
    for (const char c : lowercase_copy(raw)) {
        const bool ok =
            (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
        id.push_back(ok ? c : '-');
    }
    return id;
}

struct TreeFile {
    std::string path;
    std::string basename_lower;
    int64_t size_bytes = 0;
    std::string sha256;
};

// One selectable unit: a standalone GGUF or a complete shard set.
struct Candidate {
    std::vector<TreeFile> parts;   // ordered; first part is the load entry point
    std::string match_name_lower;  // basename used for tag matching
};

bool tag_matches_basename(const std::string& tag_lower, const std::string& basename_lower) {
    if (tag_lower.empty()) {
        return false;
    }
    if (tag_lower == basename_lower) {
        return true;  // exact filename as tag
    }
    // llama.cpp boundary rule: "{tag}." or "{tag}-" inside the basename.
    for (const char boundary : {'.', '-'}) {
        const std::string needle = tag_lower + boundary;
        if (basename_lower.find(needle) != std::string::npos) {
            return true;
        }
    }
    return false;
}

const Candidate* select_candidate(const std::vector<Candidate>& candidates,
                                  const std::string& tag_lower) {
    if (candidates.empty()) {
        return nullptr;
    }
    if (!tag_lower.empty()) {
        for (const Candidate& candidate : candidates) {
            if (tag_matches_basename(tag_lower, candidate.match_name_lower)) {
                return &candidate;
            }
        }
        return nullptr;
    }
    for (const char* preferred : {"q4_k_m", "q8_0"}) {
        for (const Candidate& candidate : candidates) {
            if (tag_matches_basename(preferred, candidate.match_name_lower)) {
                return &candidate;
            }
        }
    }
    return &candidates.front();
}

rac_result_t fetch_repo_tree(const std::string& org, const std::string& repo, std::string* out_body,
                             int32_t* out_status, std::string* error_message) {
    const std::string url =
        "https://huggingface.co/api/models/" + org + "/" + repo + "/tree/main?recursive=true";

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || !client) {
        *error_message =
            "Hugging Face resolution needs an HTTP transport, but none is registered yet "
            "(initialize the SDK first)";
        return rc == RAC_SUCCESS ? RAC_ERROR_NOT_INITIALIZED : rc;
    }

    rac_http_request_t request = {};
    request.method = "GET";
    request.url = url.c_str();
    request.timeout_ms = kTreeRequestTimeoutMs;
    request.follow_redirects = RAC_TRUE;

    rac_http_response_t response = {};
    rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);
    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&response);
        *error_message =
            "failed to reach huggingface.co (" + std::string(rac_error_message(rc)) + ")";
        return rc;
    }
    *out_status = response.status;
    if (response.body_bytes && response.body_len > 0) {
        out_body->assign(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    } else {
        out_body->clear();
    }
    rac_http_response_free(&response);
    return RAC_SUCCESS;
}

}  // namespace

bool is_hf_ref(const std::string& ref) {
    const std::string rest = strip_prefix(ref);
    if (rest.empty()) {
        return false;
    }
    const size_t org_end = rest.find('/');
    return org_end != std::string::npos && org_end > 0 && org_end + 1 < rest.size();
}

bool is_folder_ref(const std::string& ref, const char* manifest_leaf_ext) {
    const std::string rest = strip_prefix(ref);
    if (rest.empty() || rest.find("/resolve/") != std::string::npos ||
        rest.find("/blob/") != std::string::npos) {
        return false;
    }
    ParsedRef parsed;
    if (!parse_ref(ref, &parsed) || parsed.file_path.empty()) {
        return false;
    }
    std::string path = trim_trailing_slashes(parsed.file_path);
    if (path.empty()) {
        return false;
    }
    const std::string leaf = basename_of(path);
    if (leaf.find('.') == std::string::npos) {
        return true;
    }
    return has_extension(leaf, manifest_leaf_ext);
}

namespace {

bool logical_arch_folder_parts(const std::string& ref, const char* manifest_leaf_ext,
                               ParsedRef* parsed_out, std::string* manifest_out) {
    std::string rest = strip_prefix(ref);
    if (rest.empty() || rest.find("/resolve/") != std::string::npos ||
        rest.find("/blob/") != std::string::npos) {
        return false;
    }

    std::string query;
    const size_t query_pos = rest.find('?');
    if (query_pos != std::string::npos) {
        query = rest.substr(query_pos + 1);
        rest = rest.substr(0, query_pos);
    }

    ParsedRef parsed;
    if (!parse_ref("hf.co/" + rest, &parsed)) {
        return false;
    }

    std::string manifest = query_value(query, "manifest");
    if (!parsed.file_path.empty()) {
        const std::string path = trim_trailing_slashes(parsed.file_path);
        if (path.empty() || path_starts_with_arch(path)) {
            return false;
        }
        if (path.find('/') != std::string::npos || !has_extension(path, manifest_leaf_ext)) {
            return false;
        }
        if (!manifest.empty() && manifest != path) {
            return false;
        } else if (manifest.empty()) {
            manifest = path;
        }
    }

    if (!manifest.empty()) {
        manifest = trim_trailing_slashes(manifest);
        if (manifest.find('/') != std::string::npos || !has_extension(manifest, manifest_leaf_ext)) {
            return false;
        }
    }

    if (parsed_out != nullptr) {
        *parsed_out = parsed;
    }
    if (manifest_out != nullptr) {
        *manifest_out = manifest;
    }
    return true;
}

}  // namespace

bool is_logical_arch_folder_ref(const std::string& ref, const char* manifest_leaf_ext) {
    return logical_arch_folder_parts(ref, manifest_leaf_ext, nullptr, nullptr);
}

bool make_arch_folder_ref(const std::string& ref, const std::string& arch,
                          const char* manifest_leaf_ext, std::string* out_ref) {
    if (out_ref == nullptr || arch.empty() || arch == "unknown" || !is_arch_segment(arch)) {
        return false;
    }

    ParsedRef parsed;
    std::string manifest;
    if (!logical_arch_folder_parts(ref, manifest_leaf_ext, &parsed, &manifest)) {
        return false;
    }

    *out_ref = "https://huggingface.co/" + parsed.org + "/" + parsed.repo + "/" + arch;
    if (!manifest.empty()) {
        *out_ref += "/" + manifest;
    }
    return true;
}

std::string normalize_explicit_file_ref(const std::string& ref) {
    const std::string rest = strip_prefix(ref);
    if (rest.empty()) {
        return {};
    }
    // Full /resolve/ (or /blob/) URL on an hf host: re-host on huggingface.co.
    if (rest.find("/resolve/") != std::string::npos) {
        return "https://huggingface.co/" + rest;
    }
    ParsedRef parsed;
    if (!parse_ref(ref, &parsed) || parsed.file_path.empty()) {
        return {};
    }
    return "https://huggingface.co/" + parsed.org + "/" + parsed.repo + "/resolve/main/" +
           parsed.file_path;
}

rac_result_t resolve_repo(const std::string& ref, ResolvedModel* out, std::string* error_message) {
    std::string local_error;
    std::string* error = error_message ? error_message : &local_error;
    if (!out) {
        *error = "output model is required";
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ParsedRef parsed;
    if (!parse_ref(ref, &parsed) || !parsed.file_path.empty()) {
        *error = "not a repo-level Hugging Face reference: " + ref;
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string body;
    int32_t status = 0;
    rac_result_t rc = fetch_repo_tree(parsed.org, parsed.repo, &body, &status, error);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (status == 401 || status == 403) {
        *error = "Hugging Face repo " + parsed.org + "/" + parsed.repo +
                 " is gated or private (HTTP " + std::to_string(status) +
                 "); gated-repo tokens are not wired up yet — download the file manually or use "
                 "a public repo";
        return RAC_ERROR_PERMISSION_DENIED;
    }
    if (status == 404) {
        *error = "Hugging Face repo not found: " + parsed.org + "/" + parsed.repo;
        return RAC_ERROR_NOT_FOUND;
    }
    if (status != 200) {
        *error = "Hugging Face tree listing failed for " + parsed.org + "/" + parsed.repo +
                 " (HTTP " + std::to_string(status) + ")";
        return RAC_ERROR_NETWORK_ERROR;
    }

    const nlohmann::json tree = nlohmann::json::parse(body, nullptr, /*allow_exceptions=*/false);
    if (tree.is_discarded() || !tree.is_array()) {
        *error = "unexpected response from the Hugging Face tree API";
        return RAC_ERROR_DECODING_ERROR;
    }

    // Collect GGUF files with size + checksum.
    std::vector<TreeFile> ggufs;
    for (const nlohmann::json& entry : tree) {
        if (!entry.is_object() || entry.value("type", "") != "file") {
            continue;
        }
        TreeFile file;
        file.path = entry.value("path", "");
        file.basename_lower = lowercase_copy(basename_of(file.path));
        if (!file.basename_lower.ends_with(".gguf")) {
            continue;
        }
        if (entry.contains("lfs") && entry["lfs"].is_object()) {
            file.sha256 = entry["lfs"].value("oid", "");
            file.size_bytes = entry["lfs"].value("size", static_cast<int64_t>(0));
        }
        if (file.size_bytes == 0) {
            file.size_bytes = entry.value("size", static_cast<int64_t>(0));
        }
        ggufs.push_back(std::move(file));
    }
    if (ggufs.empty()) {
        *error = "no GGUF files in " + parsed.org + "/" + parsed.repo +
                 " — pass an explicit file path (hf.co/org/repo/path/to/file) for non-GGUF repos";
        return RAC_ERROR_NOT_FOUND;
    }
    std::ranges::sort(ggufs, {}, &TreeFile::path);

    // Split into primary candidates (standalone or shard sets) and mmproj
    // sidecars; imatrix data is never a load target.
    const std::regex shard_pattern("^(.*)-(\\d{5})-of-(\\d{5})\\.gguf$");
    std::vector<Candidate> candidates;
    std::vector<TreeFile> mmproj_files;
    std::map<std::string, Candidate> shard_sets;
    for (TreeFile& file : ggufs) {
        if (file.basename_lower.find("mmproj") != std::string::npos) {
            mmproj_files.push_back(std::move(file));
            continue;
        }
        if (file.basename_lower.find("imatrix") != std::string::npos) {
            continue;
        }
        std::smatch shard_match;
        if (std::regex_match(file.basename_lower, shard_match, shard_pattern)) {
            // Group shards by their stem; paths were sorted above, so parts
            // arrive in shard order and part[0] is the load entry point.
            Candidate& shard_set = shard_sets[shard_match[1].str()];
            if (shard_set.match_name_lower.empty()) {
                shard_set.match_name_lower = shard_match[1].str() + ".gguf";
            }
            shard_set.parts.push_back(std::move(file));
            continue;
        }
        Candidate single;
        single.match_name_lower = file.basename_lower;
        single.parts.push_back(std::move(file));
        candidates.push_back(std::move(single));
    }
    for (auto& [stem, set] : shard_sets) {
        candidates.push_back(std::move(set));
    }
    std::ranges::sort(candidates, {}, &Candidate::match_name_lower);

    const std::string tag_lower = lowercase_copy(parsed.tag);
    const Candidate* selected = select_candidate(candidates, tag_lower);
    if (!selected) {
        std::string available;
        for (size_t i = 0; i < candidates.size() && i < 10; ++i) {
            available += (i ? ", " : "") + candidates[i].match_name_lower;
        }
        *error = "no GGUF in " + parsed.org + "/" + parsed.repo + " matches tag '" + parsed.tag +
                 "' — available: " + available;
        return RAC_ERROR_NOT_FOUND;
    }

    out->files.clear();
    out->total_size_bytes = 0;
    const std::string url_base =
        "https://huggingface.co/" + parsed.org + "/" + parsed.repo + "/resolve/main/";
    for (const TreeFile& part : selected->parts) {
        ResolvedFile file;
        file.url = url_base + part.path;
        file.filename = basename_of(part.path);
        file.size_bytes = part.size_bytes;
        file.sha256 = part.sha256;
        out->files.push_back(std::move(file));
        out->total_size_bytes += part.size_bytes;
    }
    if (!mmproj_files.empty()) {
        // Deterministic pairing: first sorted mmproj (repos virtually always
        // ship exactly one per precision; sorted order prefers f16 < f32 < q8).
        const TreeFile& mmproj = mmproj_files.front();
        ResolvedFile file;
        file.url = url_base + mmproj.path;
        file.filename = basename_of(mmproj.path);
        file.size_bytes = mmproj.size_bytes;
        file.sha256 = mmproj.sha256;
        file.is_vision_projector = true;
        out->files.push_back(std::move(file));
        out->total_size_bytes += mmproj.size_bytes;
        out->has_vision_projector = true;
    }

    out->model_id = sanitize_model_id(parsed.repo + (parsed.tag.empty() ? "" : "-" + parsed.tag));
    out->display_name =
        parsed.org + "/" + parsed.repo + (parsed.tag.empty() ? "" : " (" + parsed.tag + ")");

    RAC_LOG_INFO(LOG_CAT, "Resolved %s -> %zu file(s), %lld bytes%s", ref.c_str(),
                 out->files.size(), static_cast<long long>(out->total_size_bytes),
                 out->has_vision_projector ? " (with vision projector)" : "");
    return RAC_SUCCESS;
}

namespace {

// Repo housekeeping entries excluded from folder bundles.
bool is_repo_housekeeping(const std::string& path) {
    const std::string base_lower = lowercase_copy(basename_of(path));
    if (base_lower.ends_with(".md")) {
        return true;
    }
    // Any dotfile path segment (.gitattributes, .cache/...).
    size_t start = 0;
    while (start < path.size()) {
        if (path[start] == '.') {
            return true;
        }
        const size_t slash = path.find('/', start);
        if (slash == std::string::npos) {
            break;
        }
        start = slash + 1;
    }
    return false;
}

}  // namespace

rac_result_t resolve_folder_from_tree_json(const std::string& tree_json_body,
                                           const std::string& org, const std::string& repo,
                                           const std::string& subdir,
                                           const std::string& primary_rel,
                                           rac_bundle_manifest_predicate_fn is_manifest,
                                           ResolvedModel* out, std::string* error_message) {
    std::string local_error;
    std::string* error = error_message ? error_message : &local_error;
    if (!out) {
        *error = "output model is required";
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const nlohmann::json tree =
        nlohmann::json::parse(tree_json_body, nullptr, /*allow_exceptions=*/false);
    if (tree.is_discarded() || !tree.is_array()) {
        *error = "unexpected response from the Hugging Face tree API";
        return RAC_ERROR_DECODING_ERROR;
    }

    const std::string prefix = subdir.empty() ? "" : subdir + "/";
    std::vector<TreeFile> bundle;  // TreeFile.path holds the SUBDIR-RELATIVE path
    const TreeFile* root_config = nullptr;
    TreeFile root_config_storage;
    for (const nlohmann::json& entry : tree) {
        if (!entry.is_object() || entry.value("type", "") != "file") {
            continue;
        }
        TreeFile file;
        const std::string full_path = entry.value("path", "");
        if (entry.contains("lfs") && entry["lfs"].is_object()) {
            file.sha256 = entry["lfs"].value("oid", "");
            file.size_bytes = entry["lfs"].value("size", static_cast<int64_t>(0));
        }
        if (file.size_bytes == 0) {
            file.size_bytes = entry.value("size", static_cast<int64_t>(0));
        }
        if (!prefix.empty() && full_path == "config.json") {
            file.path = full_path;
            file.basename_lower = "config.json";
            root_config_storage = std::move(file);
            root_config = &root_config_storage;
            continue;
        }
        if (!full_path.starts_with(prefix) || full_path.size() <= prefix.size() ||
            is_repo_housekeeping(full_path)) {
            continue;
        }
        file.path = full_path.substr(prefix.size());
        file.basename_lower = lowercase_copy(basename_of(file.path));
        bundle.push_back(std::move(file));
    }
    if (bundle.empty()) {
        *error = "no files under '" + subdir + "' in " + org + "/" + repo;
        return RAC_ERROR_NOT_FOUND;
    }
    std::ranges::sort(bundle, {}, &TreeFile::path);
    const bool bundle_has_top_level_config =
        std::ranges::any_of(bundle, [](const TreeFile& file) { return file.path == "config.json"; });

    // Pick the primary: the manifest named by the ref, else the
    // alphabetically-first file the framework's bundle policy recognizes as a
    // manifest. Commons carries no per-framework manifest heuristics.
    size_t primary_index = bundle.size();
    if (!primary_rel.empty()) {
        for (size_t i = 0; i < bundle.size(); ++i) {
            if (bundle[i].path == primary_rel) {
                primary_index = i;
                break;
            }
        }
        if (primary_index == bundle.size()) {
            *error = "manifest '" + primary_rel + "' not found under '" + subdir + "' in " + org +
                     "/" + repo;
            return RAC_ERROR_NOT_FOUND;
        }
    } else if (is_manifest != nullptr) {
        for (size_t i = 0; i < bundle.size(); ++i) {
            if (is_manifest(bundle[i].path.c_str()) == RAC_TRUE) {
                primary_index = i;
                break;
            }
        }
    }
    if (primary_index == bundle.size()) {
        *error = "cannot choose a primary file under '" + subdir + "' in " + org + "/" + repo +
                 " — name the manifest explicitly in the ref (hf.co/" + org + "/" + repo + "/" +
                 (subdir.empty() ? "" : subdir + "/") +
                 "<manifest>), or register the engine backend for this framework first (it "
                 "installs the bundle policy)";
        return RAC_ERROR_NOT_FOUND;
    }

    out->files.clear();
    out->has_vision_projector = false;
    out->total_size_bytes = 0;
    const std::string url_base = "https://huggingface.co/" + org + "/" + repo + "/resolve/main/";
    std::vector<std::string> emitted_filenames;
    auto append = [&](const TreeFile& part, const std::string& full_path) {
        if (std::ranges::find(emitted_filenames, part.path) != emitted_filenames.end()) {
            return;
        }
        emitted_filenames.push_back(part.path);
        ResolvedFile file;
        file.url = url_base + full_path;
        file.filename = part.path;
        file.size_bytes = part.size_bytes;
        file.sha256 = part.sha256;
        out->files.push_back(std::move(file));
        out->total_size_bytes += part.size_bytes;
    };
    append(bundle[primary_index], prefix + bundle[primary_index].path);
    for (size_t i = 0; i < bundle.size(); ++i) {
        if (i != primary_index) {
            append(bundle[i], prefix + bundle[i].path);
        }
    }
    if (root_config && !bundle_has_top_level_config) {
        append(*root_config, root_config->path);
    }

    out->model_id = sanitize_model_id(repo + (subdir.empty() ? "" : "-" + subdir));
    out->display_name = org + "/" + repo + (subdir.empty() ? "" : " (" + subdir + ")");
    return RAC_SUCCESS;
}

rac_result_t resolve_repo_folder(const std::string& ref, const char* manifest_leaf_ext,
                                 rac_bundle_manifest_predicate_fn is_manifest, ResolvedModel* out,
                                 std::string* error_message) {
    std::string local_error;
    std::string* error = error_message ? error_message : &local_error;
    if (!out) {
        *error = "output model is required";
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ParsedRef parsed;
    if (!parse_ref(ref, &parsed) || parsed.file_path.empty()) {
        *error = "not a folder-level Hugging Face reference: " + ref;
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::string path = parsed.file_path;
    while (!path.empty() && path.back() == '/') {
        path.pop_back();
    }
    std::string subdir = path;
    std::string primary_rel;
    if (manifest_leaf_ext != nullptr && manifest_leaf_ext[0] != '\0' &&
        lowercase_copy(basename_of(path)).ends_with(lowercase_copy(manifest_leaf_ext))) {
        const size_t slash = path.find_last_of('/');
        subdir = slash == std::string::npos ? "" : path.substr(0, slash);
        primary_rel = basename_of(path);
    }

    std::string body;
    int32_t status = 0;
    rac_result_t rc = fetch_repo_tree(parsed.org, parsed.repo, &body, &status, error);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (status == 401 || status == 403) {
        *error = "Hugging Face repo " + parsed.org + "/" + parsed.repo +
                 " is gated or private (HTTP " + std::to_string(status) +
                 "); set a Hugging Face token or use a public repo";
        return RAC_ERROR_PERMISSION_DENIED;
    }
    if (status == 404) {
        *error = "Hugging Face repo not found: " + parsed.org + "/" + parsed.repo;
        return RAC_ERROR_NOT_FOUND;
    }
    if (status != 200) {
        *error = "Hugging Face tree listing failed for " + parsed.org + "/" + parsed.repo +
                 " (HTTP " + std::to_string(status) + ")";
        return RAC_ERROR_NETWORK_ERROR;
    }

    rc = resolve_folder_from_tree_json(body, parsed.org, parsed.repo, subdir, primary_rel,
                                       is_manifest, out, error);
    if (rc == RAC_SUCCESS) {
        RAC_LOG_INFO(LOG_CAT, "Resolved folder %s -> %zu file(s), %lld bytes", ref.c_str(),
                     out->files.size(), static_cast<long long>(out->total_size_bytes));
    }
    return rc;
}

}  // namespace rac::infra::model_management::hf
