//
//  ModelTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  Conversion extensions for Swift model types to C++ model types.
//  Used by CppBridge.ModelRegistry to convert between Swift and C++ types.
//

import CRACommons
import Foundation

// MARK: - ModelCategory C++ Conversion

extension ModelCategory {
    /// Convert to C++ model category type
    func toC() -> rac_model_category_t {
        switch self {
        case .language:                 return RAC_MODEL_CATEGORY_LANGUAGE
        case .speechRecognition:        return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
        case .speechSynthesis:          return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
        case .vision:                   return RAC_MODEL_CATEGORY_VISION
        case .imageGeneration:          return RAC_MODEL_CATEGORY_IMAGE_GENERATION
        case .multimodal:               return RAC_MODEL_CATEGORY_MULTIMODAL
        case .audio:                    return RAC_MODEL_CATEGORY_AUDIO
        case .embedding:                return RAC_MODEL_CATEGORY_EMBEDDING
        case .voiceActivityDetection:   return RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        default:                        return RAC_MODEL_CATEGORY_UNKNOWN
        }
    }

    /// Initialize from C++ model category type
    init(from cCategory: rac_model_category_t) {
        switch cCategory {
        case RAC_MODEL_CATEGORY_LANGUAGE:
            self = .language
        case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION:
            self = .speechRecognition
        case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS:
            self = .speechSynthesis
        case RAC_MODEL_CATEGORY_VISION:
            self = .vision
        case RAC_MODEL_CATEGORY_IMAGE_GENERATION:
            self = .imageGeneration
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            self = .multimodal
        case RAC_MODEL_CATEGORY_AUDIO:
            self = .audio
        case RAC_MODEL_CATEGORY_EMBEDDING:
            self = .embedding
        case RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            self = .voiceActivityDetection
        default:
            self = .unspecified
        }
    }
}

// MARK: - ModelFormat C++ Conversion

extension ModelFormat {
    /// Convert to C++ model format type
    func toC() -> rac_model_format_t {
        switch self {
        case .onnx:     return RAC_MODEL_FORMAT_ONNX
        case .ort:      return RAC_MODEL_FORMAT_ORT
        case .gguf:     return RAC_MODEL_FORMAT_GGUF
        case .bin:      return RAC_MODEL_FORMAT_BIN
        case .coreml, .mlmodel, .mlpackage:
            return RAC_MODEL_FORMAT_COREML
        case .qnnContext:
            return RAC_MODEL_FORMAT_QNN_CONTEXT
        default:        return RAC_MODEL_FORMAT_UNKNOWN
        }
    }

    /// Initialize from C++ model format type
    init(from cFormat: rac_model_format_t) {
        switch cFormat {
        case RAC_MODEL_FORMAT_ONNX:
            self = .onnx
        case RAC_MODEL_FORMAT_ORT:
            self = .ort
        case RAC_MODEL_FORMAT_GGUF:
            self = .gguf
        case RAC_MODEL_FORMAT_BIN:
            self = .bin
        case RAC_MODEL_FORMAT_COREML:
            self = .coreml
        case RAC_MODEL_FORMAT_QNN_CONTEXT:
            self = .qnnContext
        default:
            self = .unknown
        }
    }
}

// MARK: - InferenceFramework C++ Conversion

extension InferenceFramework {
    /// Convert to C++ inference framework type.
    /// Delegates to the shared `toCFramework()` defined in `ModelTypes.swift`.
    func toC() -> rac_inference_framework_t { toCFramework() }

    /// Initialize from C++ inference framework type.
    /// Delegates to the shared `fromCFramework(_:)` defined in `ModelTypes.swift`.
    init(from cFramework: rac_inference_framework_t) {
        self = InferenceFramework.fromCFramework(cFramework)
    }
}

// MARK: - Generated Artifact C++ Conversion

extension RAModelInfo.OneOf_Artifact {
    /// Convert generated artifact oneof to C++ artifact info struct.
    func toCInfo() -> rac_model_artifact_info_t {
        var info = rac_model_artifact_info_t()

        switch self {
        case .singleFile:
            info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN

        case .archive(let archive):
            info.kind = RAC_ARTIFACT_KIND_ARCHIVE
            info.archive_type = archive.type.toC()
            info.archive_structure = archive.structure.toC()

        case .multiFile:
            info.kind = RAC_ARTIFACT_KIND_MULTI_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN

        case .customStrategyID(let strategyId):
            info.kind = RAC_ARTIFACT_KIND_CUSTOM
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
            info.strategy_id = UnsafePointer(strdup(strategyId))

        case .builtIn(let enabled):
            info.kind = enabled ? RAC_ARTIFACT_KIND_BUILT_IN : RAC_ARTIFACT_KIND_SINGLE_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }

        return info
    }
}

extension RAModelArtifactType {
    func toCInfo() -> rac_model_artifact_info_t {
        var info = rac_model_artifact_info_t()
        switch self {
        case .archive, .zipArchive, .tarGzArchive, .tarBz2Archive, .tarXzArchive:
            info.kind = RAC_ARTIFACT_KIND_ARCHIVE
            info.archive_type = archiveTypeForC.toC()
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        case .multiFile, .directory:
            info.kind = RAC_ARTIFACT_KIND_MULTI_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        case .custom:
            info.kind = RAC_ARTIFACT_KIND_CUSTOM
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        case .builtIn:
            info.kind = RAC_ARTIFACT_KIND_BUILT_IN
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        default:
            info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }
        return info
    }

    private var archiveTypeForC: ArchiveType {
        switch self {
        case .tarGzArchive:
            return .tarGz
        case .tarBz2Archive:
            return .tarBz2
        case .tarXzArchive:
            return .tarXz
        default:
            return .zip
        }
    }
}

// MARK: - ModelSource C++ Conversion

extension ModelSource {
    /// Convert to C++ model source type
    func toC() -> rac_model_source_t {
        switch self {
        case .remote:   return RAC_MODEL_SOURCE_REMOTE
        case .local:    return RAC_MODEL_SOURCE_LOCAL
        default:        return RAC_MODEL_SOURCE_LOCAL
        }
    }

    /// Initialize from C++ model source type
    init(from cSource: rac_model_source_t) {
        switch cSource {
        case RAC_MODEL_SOURCE_REMOTE:   self = .remote
        case RAC_MODEL_SOURCE_LOCAL:    self = .local
        default:                        self = .local
        }
    }
}

// MARK: - Generated Model Metadata C++ Conversion

extension RAModelInfo {
    /// Convert to C++ model info struct
    /// Note: The returned struct contains allocated strings that must be freed
    func toCModelInfo() -> rac_model_info_t {
        var cModel = rac_model_info_t()

        cModel.id = strdup(id)
        cModel.name = strdup(name)
        cModel.category = category.toC()
        cModel.format = format.toC()
        cModel.framework = framework.toC()
        cModel.download_url = downloadURL.isEmpty ? nil : strdup(downloadURL)
        cModel.local_path = localPath.isEmpty ? nil : strdup(localPath)
        cModel.artifact_info = artifact?.toCInfo() ?? artifactType.toCInfo()
        cModel.download_size = downloadSizeBytes
        cModel.context_length = contextLength
        cModel.supports_thinking = supportsThinking ? RAC_TRUE : RAC_FALSE
        cModel.description = description_p.isEmpty ? nil : strdup(description_p)
        cModel.source = source.toC()
        cModel.created_at = Self.unixSeconds(fromUnixMillisecondsOrSeconds: createdAtUnixMs)
        cModel.updated_at = Self.unixSeconds(fromUnixMillisecondsOrSeconds: updatedAtUnixMs)

        return cModel
    }

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

    private static func unixSeconds(fromUnixMillisecondsOrSeconds value: Int64) -> Int64 {
        let absolute = value < 0 ? -value : value
        return absolute > 10_000_000_000 ? value / 1_000 : value
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
