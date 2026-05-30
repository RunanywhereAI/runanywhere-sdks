/**
 * @file model_lifecycle_resolve.cpp
 * @brief Model-artifact resolution + result/snapshot builders.
 *
 * Extracted from the original `model_lifecycle.cpp`
 * SRP split. Owns the artifact-resolution path that bridges a registered
 * `ModelInfo` (single-file or multi-file) into a primary path + optional
 * mmproj + companion descriptors, plus the helpers that copy that result
 * into ModelLoadResult / ComponentLifecycleSnapshot.
 */

#include "model_lifecycle_internal.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

namespace {

std::string resolved_path_for_model(const runanywhere::v1::ModelInfo& model) {
    if (!model.local_path().empty()) {
        return model.local_path();
    }
    return model.id();
}

std::string basename_of_path(const std::string& path) {
    const size_t pos = path.find_last_of("/\\");
    return pos == std::string::npos ? path : path.substr(pos + 1);
}

std::string lowercase_ascii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

bool path_has_extension(const std::string& path, const char* extension) {
    if (!extension) {
        return false;
    }
    const std::string lower_path = lowercase_ascii(path);
    const std::string lower_extension = "." + lowercase_ascii(extension);
    return lower_path.size() >= lower_extension.size() &&
           lower_path.compare(lower_path.size() - lower_extension.size(), lower_extension.size(),
                              lower_extension) == 0;
}

bool path_matches_proto_format(const std::string& path, runanywhere::v1::ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_GGUF:
            return path_has_extension(path, "gguf");
        case runanywhere::v1::MODEL_FORMAT_GGML:
            return path_has_extension(path, "ggml");
        case runanywhere::v1::MODEL_FORMAT_ONNX:
            return path_has_extension(path, "onnx");
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return path_has_extension(path, "ort");
        case runanywhere::v1::MODEL_FORMAT_BIN:
        case runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT:
            return path_has_extension(path, "bin");
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
            return path_has_extension(path, "mlmodel");
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return path_has_extension(path, "mlpackage");
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
            return path_has_extension(path, "tflite");
        case runanywhere::v1::MODEL_FORMAT_SAFETENSORS:
            return path_has_extension(path, "safetensors");
        case runanywhere::v1::MODEL_FORMAT_ZIP:
            return path_has_extension(path, "zip");
        case runanywhere::v1::MODEL_FORMAT_COREML:
            return path_has_extension(path, "mlmodelc") || path_has_extension(path, "mlmodel") ||
                   path_has_extension(path, "mlpackage");
        case runanywhere::v1::MODEL_FORMAT_UNSPECIFIED:
        case runanywhere::v1::MODEL_FORMAT_UNKNOWN:
        default:
            return path_has_extension(path, "gguf") || path_has_extension(path, "ggml") ||
                   path_has_extension(path, "onnx") || path_has_extension(path, "ort") ||
                   path_has_extension(path, "bin") || path_has_extension(path, "mlmodel") ||
                   path_has_extension(path, "mlpackage") || path_has_extension(path, "mlmodelc") ||
                   path_has_extension(path, "tflite") || path_has_extension(path, "safetensors") ||
                   path_has_extension(path, "zip");
    }
}

bool path_is_absolute(const std::string& path) {
    return !path.empty() && (path[0] == '/' || path[0] == '\\' ||
                             (path.size() > 1 &&
                              std::isalpha(static_cast<unsigned char>(path[0])) && path[1] == ':'));
}

std::string join_model_path(const std::string& root, const std::string& relative_or_absolute) {
    if (relative_or_absolute.empty()) {
        return "";
    }
    if (path_is_absolute(relative_or_absolute) || root.empty()) {
        return relative_or_absolute;
    }
    if (root.back() == '/' || root.back() == '\\') {
        return root + relative_or_absolute;
    }
    return root + "/" + relative_or_absolute;
}

std::string descriptor_relative_path(const runanywhere::v1::ModelFileDescriptor& file) {
    if (file.has_destination_path() && !file.destination_path().empty()) {
        return file.destination_path();
    }
    if (file.has_relative_path() && !file.relative_path().empty()) {
        return file.relative_path();
    }
    if (!file.filename().empty()) {
        return file.filename();
    }
    return "";
}

bool descriptor_is_mmproj(const runanywhere::v1::ModelFileDescriptor& file) {
    if (file.role() == runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR) {
        return true;
    }
    const std::string name = lowercase_ascii(descriptor_relative_path(file));
    return name.find("mmproj") != std::string::npos || name.find("mm-proj") != std::string::npos ||
           name.find("vision-projector") != std::string::npos ||
           name.find("vision_projector") != std::string::npos ||
           name.find("multimodal_projector") != std::string::npos ||
           name.find("multi-modal-projector") != std::string::npos;
}

void append_synthesized_artifact(const runanywhere::v1::ModelFileDescriptor& source,
                                 const std::string& root,
                                 std::vector<runanywhere::v1::ModelFileDescriptor>* artifacts) {
    if (!artifacts) {
        return;
    }
    const std::string rel = descriptor_relative_path(source);
    if (rel.empty()) {
        return;
    }
    const std::string absolute = join_model_path(root, rel);
    for (const runanywhere::v1::ModelFileDescriptor& existing : *artifacts) {
        if (existing.has_local_path() && existing.local_path() == absolute) {
            return;
        }
    }

    runanywhere::v1::ModelFileDescriptor descriptor;
    descriptor.CopyFrom(source);
    if (!descriptor.has_relative_path() || descriptor.relative_path().empty()) {
        descriptor.set_relative_path(rel);
    }
    if (!descriptor.has_destination_path() || descriptor.destination_path().empty()) {
        descriptor.set_destination_path(rel);
    }
    if (descriptor.filename().empty()) {
        descriptor.set_filename(basename_of_path(rel));
    }
    descriptor.set_local_path(absolute);
    artifacts->push_back(std::move(descriptor));
}

void synthesize_artifact_resolution_from_descriptors(const runanywhere::v1::ModelInfo& model,
                                                     const std::string& artifact_root,
                                                     ModelArtifactResolution* out) {
    if (!out || artifact_root.empty()) {
        return;
    }
    const bool can_set_primary = out->resolved_path.empty() || out->resolved_path == artifact_root;

    auto visit_descriptor = [&](const runanywhere::v1::ModelFileDescriptor& file) {
        append_synthesized_artifact(file, artifact_root, &out->artifacts);
        const std::string rel = descriptor_relative_path(file);
        if (rel.empty()) {
            return;
        }
        const std::string absolute = join_model_path(artifact_root, rel);
        if (file.role() == runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL && can_set_primary) {
            out->resolved_path = absolute;
        }
        if (descriptor_is_mmproj(file) && out->mmproj_path.empty()) {
            out->mmproj_path = absolute;
        }
    };

    if (model.has_multi_file()) {
        for (const runanywhere::v1::ModelFileDescriptor& file : model.multi_file().files()) {
            visit_descriptor(file);
        }
    }
    if (model.has_expected_files()) {
        for (const runanywhere::v1::ModelFileDescriptor& file : model.expected_files().files()) {
            visit_descriptor(file);
        }
    }

    if (can_set_primary && out->resolved_path == artifact_root) {
        auto select_primary_candidate = [&](const runanywhere::v1::ModelFileDescriptor& file) {
            if (descriptor_is_mmproj(file)) {
                return;
            }
            const std::string rel = descriptor_relative_path(file);
            if (!rel.empty() && path_matches_proto_format(rel, model.format())) {
                out->resolved_path = join_model_path(artifact_root, rel);
            }
        };
        if (model.has_multi_file()) {
            for (const runanywhere::v1::ModelFileDescriptor& file : model.multi_file().files()) {
                if (out->resolved_path != artifact_root) {
                    break;
                }
                select_primary_candidate(file);
            }
        }
        if (out->resolved_path == artifact_root && model.has_expected_files()) {
            for (const runanywhere::v1::ModelFileDescriptor& file :
                 model.expected_files().files()) {
                if (out->resolved_path != artifact_root) {
                    break;
                }
                select_primary_candidate(file);
            }
        }
    }
}

struct ProtoModelPathBridge {
    rac_model_info_t model{};
    rac_expected_model_files_t expected_files{};
    rac_model_artifact_info_t artifact{};
    std::vector<std::string> required_patterns;
    std::vector<std::string> optional_patterns;
    std::vector<const char*> required_pattern_ptrs;
    std::vector<const char*> optional_pattern_ptrs;
    std::vector<std::string> descriptor_relative_paths;
    std::vector<std::string> descriptor_destination_paths;
    std::vector<rac_model_file_descriptor_t> descriptors;

    explicit ProtoModelPathBridge(const runanywhere::v1::ModelInfo& proto) {
        model.id = const_cast<char*>(proto.id().c_str());
        model.name = const_cast<char*>(proto.name().c_str());
        model.category = c_category_from_proto(proto.category());
        model.format = c_format_from_proto(proto.format());
        model.framework = c_framework_from_proto(proto.framework());
        model.local_path = const_cast<char*>(proto.local_path().c_str());
        model.download_url = const_cast<char*>(proto.download_url().c_str());
        model.artifact_info = {};
        model.artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;

        populate_expected_files(proto);
        populate_descriptors(proto);
        populate_artifact_kind(proto);
    }

   private:
    void add_pattern(std::vector<std::string>* storage, const std::string& pattern) {
        if (!storage || pattern.empty()) {
            return;
        }
        storage->push_back(pattern);
    }

    void finalize_patterns() {
        required_pattern_ptrs.clear();
        optional_pattern_ptrs.clear();
        required_pattern_ptrs.reserve(required_patterns.size());
        optional_pattern_ptrs.reserve(optional_patterns.size());
        for (const std::string& pattern : required_patterns) {
            required_pattern_ptrs.push_back(pattern.c_str());
        }
        for (const std::string& pattern : optional_patterns) {
            optional_pattern_ptrs.push_back(pattern.c_str());
        }
        if (!required_pattern_ptrs.empty() || !optional_pattern_ptrs.empty()) {
            expected_files.required_patterns = required_pattern_ptrs.data();
            expected_files.required_pattern_count = required_pattern_ptrs.size();
            expected_files.optional_patterns = optional_pattern_ptrs.data();
            expected_files.optional_pattern_count = optional_pattern_ptrs.size();
            model.artifact_info.expected_files = &expected_files;
        }
    }

    void add_expected_from_message(const runanywhere::v1::ExpectedModelFiles& expected) {
        for (const std::string& pattern : expected.required_patterns()) {
            add_pattern(&required_patterns, pattern);
        }
        for (const std::string& pattern : expected.optional_patterns()) {
            add_pattern(&optional_patterns, pattern);
        }
    }

    void populate_expected_files(const runanywhere::v1::ModelInfo& proto) {
        if (proto.has_expected_files()) {
            add_expected_from_message(proto.expected_files());
        } else if (proto.has_single_file() && proto.single_file().has_expected_files()) {
            add_expected_from_message(proto.single_file().expected_files());
        } else if (proto.has_archive() && proto.archive().has_expected_files()) {
            add_expected_from_message(proto.archive().expected_files());
        } else if (proto.has_single_file()) {
            for (const std::string& pattern : proto.single_file().required_patterns()) {
                add_pattern(&required_patterns, pattern);
            }
            for (const std::string& pattern : proto.single_file().optional_patterns()) {
                add_pattern(&optional_patterns, pattern);
            }
        } else if (proto.has_archive()) {
            for (const std::string& pattern : proto.archive().required_patterns()) {
                add_pattern(&required_patterns, pattern);
            }
            for (const std::string& pattern : proto.archive().optional_patterns()) {
                add_pattern(&optional_patterns, pattern);
            }
        }
        finalize_patterns();
    }

    void add_descriptor(const runanywhere::v1::ModelFileDescriptor& file) {
        std::string relative = file.has_relative_path() && !file.relative_path().empty()
                                   ? file.relative_path()
                                   : (!file.url().empty() ? file.url() : file.filename());
        std::string destination = file.has_destination_path() && !file.destination_path().empty()
                                      ? file.destination_path()
                                      : file.filename();
        if (relative.empty()) {
            relative = destination;
        }
        if (destination.empty()) {
            destination = relative;
        }
        descriptor_relative_paths.push_back(relative);
        descriptor_destination_paths.push_back(destination);
    }

    void populate_descriptors(const runanywhere::v1::ModelInfo& proto) {
        int descriptor_count = proto.has_multi_file() ? proto.multi_file().files_size() : 0;
        if (proto.has_expected_files()) {
            descriptor_count += proto.expected_files().files_size();
        }
        descriptor_relative_paths.reserve(static_cast<size_t>(descriptor_count));
        descriptor_destination_paths.reserve(static_cast<size_t>(descriptor_count));
        descriptors.reserve(static_cast<size_t>(descriptor_count));

        if (proto.has_multi_file()) {
            for (const runanywhere::v1::ModelFileDescriptor& file : proto.multi_file().files()) {
                add_descriptor(file);
                rac_model_file_descriptor_t descriptor{};
                descriptor.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                descriptor.role = c_file_role_from_proto(file.role());
                descriptors.push_back(descriptor);
            }
        }
        if (proto.has_expected_files()) {
            for (const runanywhere::v1::ModelFileDescriptor& file :
                 proto.expected_files().files()) {
                add_descriptor(file);
                rac_model_file_descriptor_t descriptor{};
                descriptor.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                descriptor.role = c_file_role_from_proto(file.role());
                descriptors.push_back(descriptor);
            }
        }
        for (size_t i = 0; i < descriptors.size(); ++i) {
            descriptors[i].relative_path = descriptor_relative_paths[i].empty()
                                               ? nullptr
                                               : descriptor_relative_paths[i].c_str();
            descriptors[i].destination_path = descriptor_destination_paths[i].empty()
                                                  ? nullptr
                                                  : descriptor_destination_paths[i].c_str();
        }
        if (!descriptors.empty()) {
            artifact.file_descriptors = descriptors.data();
            artifact.file_descriptor_count = descriptors.size();
            model.artifact_info.file_descriptors = descriptors.data();
            model.artifact_info.file_descriptor_count = descriptors.size();
        }
    }

    void populate_artifact_kind(const runanywhere::v1::ModelInfo& proto) {
        if (proto.has_archive()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
        } else if (proto.has_multi_file() || !descriptors.empty()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
        } else if (proto.has_custom_strategy_id()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_CUSTOM;
        } else if (proto.has_built_in() && proto.built_in()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_BUILT_IN;
        } else {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
        }
    }
};

runanywhere::v1::ModelFileDescriptor
descriptor_from_resolved_file(const rac_resolved_model_file_t& file) {
    runanywhere::v1::ModelFileDescriptor descriptor;
    if (file.relative_path) {
        descriptor.set_relative_path(file.relative_path);
        descriptor.set_destination_path(file.relative_path);
    }
    if (file.path) {
        descriptor.set_local_path(file.path);
        descriptor.set_filename(basename_of_path(file.path));
    }
    descriptor.set_is_required(file.is_required == RAC_TRUE);
    descriptor.set_role(proto_file_role_from_resolved(file.role));
    return descriptor;
}

}  // namespace

void add_artifacts_to_result(
    const std::vector<runanywhere::v1::ModelFileDescriptor>& artifacts,
    google::protobuf::RepeatedPtrField<runanywhere::v1::ModelFileDescriptor>* out) {
    if (!out) {
        return;
    }
    for (const runanywhere::v1::ModelFileDescriptor& artifact : artifacts) {
        out->Add()->CopyFrom(artifact);
    }
}

ModelArtifactResolution resolve_model_artifacts(const runanywhere::v1::ModelInfo& model) {
    ModelArtifactResolution out;
    out.resolved_path = resolved_path_for_model(model);
    if (out.resolved_path.empty()) {
        return out;
    }
    // Fast-path: when the registered ModelInfo already declares a single-file
    // local artifact (non-empty local_path, no multi-file/expected-files
    // descriptors), trust the registered path and skip the artifact-root scan.
    // The scan is only needed when the registry entry is multi-file or when
    // the auto-download path has just landed bytes whose final layout the
    // resolver needs to discover. Calling rac_model_paths_resolve_artifact on
    // an already-declared single-file local path would otherwise rewrite
    // resolved_path based on directory contents that may not match the
    // declared filename (e.g. tests using synthetic /tmp paths).
    //
    // EXCEPTION: directory-based frameworks (Sherpa-ONNX STT/TTS, ONNX,
    // CoreML, ...) MUST always run rac_model_paths_resolve_artifact even
    // when local_path is a plain folder with no multi-file/expected-files
    // descriptors. Their archives ship as a single top-level nested dir
    // (`<id>/<files>`) so extraction into `Models/Sherpa/<id>/` yields
    // `Models/Sherpa/<id>/<id>/<files>`. The registry self-heal stores the
    // OUTER folder as local_path; the loader (engines/sherpa load_model)
    // does a non-recursive scan for `*encoder*.onnx`/`tokens.txt` and so
    // needs the resolved path to point at the INNER directory that actually
    // contains the artifacts. rac_model_paths_resolve_artifact ->
    // effective_model_root() collapses that single nested level. Skipping it
    // here returned the outer folder and broke STT/TTS/voice-agent load.
    //
    // EXCEPTION 2 (archive artifacts): a model registered as an archive
    // (has_archive(), e.g. the SmolVLM `*.tar.gz` VLM) extracts to a
    // DIRECTORY which the download orchestrator records as local_path
    // (download_orchestrator.cpp sets completion_local_path =
    // model_folder_path for archive-extracted entries). Such an entry has
    // NO multi_file/expected_files descriptors and — for llama.cpp VLMs —
    // a framework that is NOT directory-based, so without this guard it hit
    // the single-file fast path and returned the extracted FOLDER as the
    // primary path with mmproj_path EMPTY. The llama.cpp VLM loader then
    // got a directory (not the `.gguf`) and no vision projector, failing
    // the multimodal load before the native backend even ran. Archives must
    // always run rac_model_paths_resolve_artifact so the folder scan +
    // infer_file_role() recover the primary `.gguf` AND the `mmproj`
    // projector. Cross-platform: the same commons path backs iOS/Android/
    // Flutter/RN VLM loads.
    if (!model.local_path().empty() && !model.has_multi_file() && !model.has_expected_files() &&
        !model.has_archive() &&
        rac_framework_uses_directory_based_models(c_framework_from_proto(model.framework())) !=
            RAC_TRUE) {
        return out;
    }
    // Registry local_path may point at a single file (legacy self-heal picked
    // mmproj first). Scan the containing folder so primary + companions resolve.
    std::string artifact_root = out.resolved_path;
    if (path_has_extension(artifact_root, "gguf") || path_has_extension(artifact_root, "onnx") ||
        path_has_extension(artifact_root, "bin") || path_has_extension(artifact_root, "ort")) {
        const size_t sep = artifact_root.find_last_of("/\\");
        if (sep != std::string::npos) {
            artifact_root = artifact_root.substr(0, sep);
        }
    }

    ProtoModelPathBridge bridge(model);
    rac_model_path_resolution_t resolution = {};
    const char* checksum = model.has_checksum_sha256() && !model.checksum_sha256().empty()
                               ? model.checksum_sha256().c_str()
                               : nullptr;
    const rac_result_t rc = rac_model_paths_resolve_artifact(&bridge.model, artifact_root.c_str(),
                                                             checksum, &resolution);
    if ((rc == RAC_SUCCESS || resolution.primary_model_path || resolution.file_count > 0) &&
        resolution.primary_model_path) {
        out.resolved_path = resolution.primary_model_path;
    }
    if (resolution.mmproj_path) {
        out.mmproj_path = resolution.mmproj_path;
    }
    for (size_t i = 0; i < resolution.file_count; ++i) {
        out.artifacts.push_back(descriptor_from_resolved_file(resolution.files[i]));
    }
    rac_model_path_resolution_free(&resolution);

    if (model.has_multi_file() || model.has_expected_files()) {
        synthesize_artifact_resolution_from_descriptors(model, artifact_root, &out);
    }
    return out;
}

runanywhere::v1::ModelLoadResult
make_load_result(bool success, const std::string& model_id, runanywhere::v1::ModelCategory category,
                 runanywhere::v1::InferenceFramework framework, const std::string& resolved_path,
                 const std::vector<runanywhere::v1::ModelFileDescriptor>& artifacts,
                 int64_t loaded_at_ms, const std::string& error) {
    runanywhere::v1::ModelLoadResult result;
    result.set_success(success);
    result.set_model_id(model_id);
    result.set_category(category);
    result.set_framework(framework);
    result.set_resolved_path(resolved_path);
    add_artifacts_to_result(artifacts, result.mutable_resolved_artifacts());
    result.set_loaded_at_unix_ms(loaded_at_ms);
    result.set_error_message(error);
    return result;
}

bool matches_current_filter(const LoadedModel& loaded, bool has_category,
                            runanywhere::v1::ModelCategory category, bool has_framework,
                            runanywhere::v1::InferenceFramework framework) {
    if (has_category && loaded.category != category) {
        return false;
    }
    if (has_framework && loaded.framework != framework) {
        return false;
    }
    return loaded.state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
}

void fill_snapshot(const LoadedModel* loaded, runanywhere::v1::SDKComponent component,
                   runanywhere::v1::ComponentLifecycleSnapshot* out) {
    out->set_component(component);
    out->set_updated_at_ms(now_ms());
    if (!loaded) {
        out->set_state(runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED);
        return;
    }
    out->set_state(loaded->state);
    out->set_model_id(loaded->model_id);
    out->set_updated_at_ms(loaded->updated_at_ms);
    out->set_error_message(loaded->error_message);
    out->set_category(loaded->category);
    out->set_framework(loaded->framework);
    out->set_resolved_path(loaded->resolved_path);
    out->set_loaded_at_unix_ms(loaded->loaded_at_ms);
    out->mutable_model()->CopyFrom(loaded->model);
}

runanywhere::v1::InferenceFramework
preferred_framework_for(const runanywhere::v1::ModelLoadRequest& request,
                        const runanywhere::v1::ModelInfo& model) {
    if (request.has_framework()) {
        return request.framework();
    }
    if (model.has_preferred_framework()) {
        return model.preferred_framework();
    }
    return model.framework();
}

runanywhere::v1::ModelCategory
preferred_category_for(const runanywhere::v1::ModelLoadRequest& request,
                       const runanywhere::v1::ModelInfo& model) {
    if (request.has_category()) {
        return request.category();
    }
    return model.category();
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::core::model_lifecycle::detail
