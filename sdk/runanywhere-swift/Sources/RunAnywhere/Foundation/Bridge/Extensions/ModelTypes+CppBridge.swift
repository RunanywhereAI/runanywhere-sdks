//
//  ModelTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  Conversion extensions for Swift model types to C++ model types.
//  Used by CppBridge.ModelRegistry to convert between Swift and C++ types.
//

import CRACommons

// MARK: - ModelCategory C++ Conversion

extension ModelCategory {
    /// Convert to C++ model category type.
    /// Delegates to commons' `rac_model_category_from_proto`.
    func toC() -> rac_model_category_t {
        var out: rac_model_category_t = RAC_MODEL_CATEGORY_UNKNOWN
        _ = rac_model_category_from_proto(Int32(self.rawValue), &out)
        return out
    }

    /// Initialize from C++ model category type.
    /// Delegates to commons' `rac_model_category_to_proto`.
    init(from cCategory: rac_model_category_t) {
        var protoValue: Int32 = 0
        guard rac_model_category_to_proto(cCategory, &protoValue) == RAC_SUCCESS else {
            self = .unspecified
            return
        }
        self = ModelCategory(rawValue: Int(protoValue)) ?? .unspecified
    }
}

// MARK: - ModelFormat C++ Conversion

extension ModelFormat {
    /// Convert to C++ model format type.
    /// Delegates to commons' `rac_model_format_from_proto`.
    func toC() -> rac_model_format_t {
        var out: rac_model_format_t = RAC_MODEL_FORMAT_UNKNOWN
        _ = rac_model_format_from_proto(Int32(self.rawValue), &out)
        return out
    }

    /// Initialize from C++ model format type.
    /// Delegates to commons' `rac_model_format_to_proto`.
    init(from cFormat: rac_model_format_t) {
        var protoValue: Int32 = 0
        guard rac_model_format_to_proto(cFormat, &protoValue) == RAC_SUCCESS else {
            self = .unknown
            return
        }
        self = ModelFormat(rawValue: Int(protoValue)) ?? .unknown
    }
}

// MARK: - InferenceFramework C++ Conversion

extension InferenceFramework {
    /// Initialize from C++ inference framework type.
    /// Delegates to the shared `fromCFramework(_:)` defined in `ModelTypes.swift`.
    init(from cFramework: rac_inference_framework_t) {
        self = InferenceFramework.fromCFramework(cFramework)
    }
}

// MARK: - ModelSource C++ Conversion

extension ModelSource {
    /// Initialize from C++ model source type.
    /// Delegates to commons' `rac_model_source_to_proto`.
    init(from cSource: rac_model_source_t) {
        var protoValue: Int32 = 0
        guard rac_model_source_to_proto(cSource, &protoValue) == RAC_SUCCESS else {
            self = .local
            return
        }
        self = ModelSource(rawValue: Int(protoValue)) ?? .local
    }
}

// MARK: - Generated Model Metadata C++ Conversion

extension RAModelInfo {
    /// Initialize from C++ model info struct
    init(from cModel: rac_model_info_t) {
        self.init()
        id = cModel.id.map { String(cString: $0) } ?? ""
        name = cModel.name.map { String(cString: $0) } ?? ""
        category = ModelCategory(from: cModel.category)
        format = ModelFormat(from: cModel.format)
        framework = InferenceFramework(from: cModel.framework)
        downloadURL = cModel.download_url.map { String(cString: $0) } ?? ""
        localPath = cModel.local_path.map { String(cString: $0) } ?? ""
        downloadSizeBytes = cModel.download_size
        contextLength = cModel.context_length
        supportsThinking = cModel.supports_thinking == RAC_TRUE
        if supportsThinking {
            thinkingPattern = .defaultPattern
        }
        description_p = cModel.description.map { String(cString: $0) } ?? ""
        source = ModelSource(from: cModel.source)
        createdAtUnixMs = cModel.created_at * 1_000
        updatedAtUnixMs = cModel.updated_at * 1_000
        apply(cArtifact: cModel.artifact_info)
        isDownloaded = isDownloadedOnDisk
        isAvailable = isAvailableForUse
    }

    private mutating func apply(cArtifact: rac_model_artifact_info_t) {
        switch cArtifact.kind {
        case RAC_ARTIFACT_KIND_SINGLE_FILE:
            setArtifact(.singleFile(RASingleFileArtifact()))

        case RAC_ARTIFACT_KIND_ARCHIVE:
            var archive = RAArchiveArtifact()
            archive.type = ArchiveType(from: cArtifact.archive_type) ?? .zip
            archive.structure = ArchiveStructure(from: cArtifact.archive_structure)
            setArtifact(.archive(archive))

        case RAC_ARTIFACT_KIND_MULTI_FILE:
            setArtifact(.multiFile(RAMultiFileArtifact()))

        case RAC_ARTIFACT_KIND_CUSTOM:
            setArtifact(.customStrategyID(cArtifact.strategy_id.map { String(cString: $0) } ?? ""))

        case RAC_ARTIFACT_KIND_BUILT_IN:
            setArtifact(.builtIn(true))

        default:
            setArtifact(.singleFile(RASingleFileArtifact()))
        }
    }
}
