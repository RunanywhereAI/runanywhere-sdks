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
        case .language:
            return RAC_MODEL_CATEGORY_LANGUAGE
        case .speechRecognition:
            return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
        case .speechSynthesis:
            return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
        case .vision:
            return RAC_MODEL_CATEGORY_VISION
        case .imageGeneration:
            return RAC_MODEL_CATEGORY_IMAGE_GENERATION
        case .multimodal:
            return RAC_MODEL_CATEGORY_MULTIMODAL
        case .audio:
            return RAC_MODEL_CATEGORY_AUDIO
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
        default:
            self = .audio  // Default fallback
        }
    }
}

// MARK: - ModelFormat C++ Conversion

extension ModelFormat {
    /// Convert to C++ model format type
    func toC() -> rac_model_format_t {
        switch self {
        case .onnx:
            return RAC_MODEL_FORMAT_ONNX
        case .ort:
            return RAC_MODEL_FORMAT_ORT
        case .gguf:
            return RAC_MODEL_FORMAT_GGUF
        case .bin:
            return RAC_MODEL_FORMAT_BIN
        case .unknown:
            return RAC_MODEL_FORMAT_UNKNOWN
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
        default:
            self = .unknown
        }
    }
}

// MARK: - InferenceFramework C++ Conversion

extension InferenceFramework {
    /// Convert to C++ inference framework type
    func toC() -> rac_inference_framework_t {
        switch self {
        case .onnx:
            return RAC_FRAMEWORK_ONNX
        case .llamaCpp:
            return RAC_FRAMEWORK_LLAMACPP
        case .foundationModels:
            return RAC_FRAMEWORK_FOUNDATION_MODELS
        case .systemTTS:
            return RAC_FRAMEWORK_SYSTEM_TTS
        case .fluidAudio:
            return RAC_FRAMEWORK_FLUID_AUDIO
        case .coreml:
            return RAC_FRAMEWORK_COREML
        case .builtIn:
            return RAC_FRAMEWORK_BUILTIN
        case .none:
            return RAC_FRAMEWORK_NONE
        case .unknown:
            return RAC_FRAMEWORK_UNKNOWN
        }
    }

    /// Initialize from C++ inference framework type
    init(from cFramework: rac_inference_framework_t) {
        switch cFramework {
        case RAC_FRAMEWORK_ONNX:
            self = .onnx
        case RAC_FRAMEWORK_LLAMACPP:
            self = .llamaCpp
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            self = .foundationModels
        case RAC_FRAMEWORK_SYSTEM_TTS:
            self = .systemTTS
        case RAC_FRAMEWORK_FLUID_AUDIO:
            self = .fluidAudio
        case RAC_FRAMEWORK_COREML:
            self = .coreml
        case RAC_FRAMEWORK_BUILTIN:
            self = .builtIn
        case RAC_FRAMEWORK_NONE:
            self = .none
        default:
            self = .unknown
        }
    }
}

// MARK: - ModelArtifactType C++ Conversion

extension ModelArtifactType {
    /// Convert to C++ artifact info struct
    func toCInfo() -> rac_model_artifact_info_t {
        var info = rac_model_artifact_info_t()

        switch self {
        case .singleFile:
            info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN

        case .archive(let archiveType, let structure, _):
            info.kind = RAC_ARTIFACT_KIND_ARCHIVE
            info.archive_type = archiveType.toC()
            info.archive_structure = structure.toC()

        case .multiFile:
            info.kind = RAC_ARTIFACT_KIND_MULTI_FILE
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN

        case .custom(let strategyId):
            info.kind = RAC_ARTIFACT_KIND_CUSTOM
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
            info.strategy_id = UnsafePointer(strdup(strategyId))

        case .builtIn:
            info.kind = RAC_ARTIFACT_KIND_BUILT_IN
            info.archive_type = RAC_ARCHIVE_TYPE_NONE
            info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }

        return info
    }

    /// Initialize from C++ artifact info
    init(from cArtifact: rac_model_artifact_info_t) {
        switch cArtifact.kind {
        case RAC_ARTIFACT_KIND_SINGLE_FILE:
            self = .singleFile(expectedFiles: .none)

        case RAC_ARTIFACT_KIND_ARCHIVE:
            // Map archive type - use ArchiveType initializer from CppBridge+Strategy.swift
            let archiveType = ArchiveType(from: cArtifact.archive_type) ?? .zip
            let structure = ArchiveStructure(from: cArtifact.archive_structure)
            self = .archive(archiveType, structure: structure, expectedFiles: .none)

        case RAC_ARTIFACT_KIND_MULTI_FILE:
            self = .multiFile([])

        case RAC_ARTIFACT_KIND_CUSTOM:
            self = .custom(strategyId: cArtifact.strategy_id.map { String(cString: $0) } ?? "")

        case RAC_ARTIFACT_KIND_BUILT_IN:
            self = .builtIn

        default:
            self = .singleFile(expectedFiles: .none)
        }
    }
}

// MARK: - ModelSource C++ Conversion

extension ModelSource {
    /// Convert to C++ model source type
    func toC() -> rac_model_source_t {
        switch self {
        case .remote:
            return RAC_MODEL_SOURCE_REMOTE
        case .local:
            return RAC_MODEL_SOURCE_LOCAL
        }
    }

    /// Initialize from C++ model source type
    init(from cSource: rac_model_source_t) {
        switch cSource {
        case RAC_MODEL_SOURCE_REMOTE:
            self = .remote
        case RAC_MODEL_SOURCE_LOCAL:
            self = .local
        default:
            self = .local
        }
    }
}

// MARK: - ModelInfo C++ Conversion

extension ModelInfo {
    /// Convert to C++ model info struct
    /// Note: The returned struct contains allocated strings that must be freed
    func toCModelInfo() -> rac_model_info_t {
        var cModel = rac_model_info_t()

        cModel.id = strdup(id)
        cModel.name = strdup(name)
        cModel.category = category.toC()
        cModel.format = format.toC()
        cModel.framework = framework.toC()
        cModel.download_url = downloadURL.map { strdup($0.absoluteString) }
        cModel.local_path = localPath.map { strdup($0.path) }
        cModel.artifact_info = artifactType.toCInfo()  // Use full conversion including archive_type
        cModel.download_size = downloadSize ?? 0
        cModel.context_length = Int32(contextLength ?? 0)
        cModel.supports_thinking = supportsThinking ? RAC_TRUE : RAC_FALSE
        cModel.description = description.map { strdup($0) }
        cModel.source = source.toC()
        cModel.created_at = Int64(createdAt.timeIntervalSince1970)
        cModel.updated_at = Int64(updatedAt.timeIntervalSince1970)

        return cModel
    }

    /// Initialize from C++ model info struct
    init(from cModel: rac_model_info_t) {
        self.id = cModel.id.map { String(cString: $0) } ?? ""
        self.name = cModel.name.map { String(cString: $0) } ?? ""
        self.category = ModelCategory(from: cModel.category)
        self.format = ModelFormat(from: cModel.format)
        self.framework = InferenceFramework(from: cModel.framework)

        if let urlStr = cModel.download_url.map({ String(cString: $0) }), !urlStr.isEmpty {
            self.downloadURL = URL(string: urlStr)
        } else {
            self.downloadURL = nil
        }

        if let pathStr = cModel.local_path.map({ String(cString: $0) }), !pathStr.isEmpty {
            self.localPath = URL(fileURLWithPath: pathStr)
        } else {
            self.localPath = nil
        }

        self.artifactType = ModelArtifactType(from: cModel.artifact_info)
        self.downloadSize = cModel.download_size > 0 ? cModel.download_size : nil
        self.contextLength = cModel.context_length > 0 ? Int(cModel.context_length) : nil
        self.supportsThinking = cModel.supports_thinking == RAC_TRUE
        self.thinkingPattern = supportsThinking ? .defaultPattern : nil
        self.description = cModel.description.map { String(cString: $0) }
        self.source = ModelSource(from: cModel.source)
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(cModel.created_at))
        self.updatedAt = Date(timeIntervalSince1970: TimeInterval(cModel.updated_at))
    }
}

// MARK: - DownloadStage C++ Conversion

extension DownloadStage {
    /// Initialize from C++ download stage
    init(from cStage: rac_download_stage_t) {
        switch cStage {
        case RAC_DOWNLOAD_STAGE_DOWNLOADING:
            self = .downloading
        case RAC_DOWNLOAD_STAGE_EXTRACTING:
            self = .extracting
        case RAC_DOWNLOAD_STAGE_VALIDATING:
            self = .validating
        case RAC_DOWNLOAD_STAGE_COMPLETED:
            self = .completed
        default:
            self = .downloading
        }
    }
}

// MARK: - DownloadState C++ Conversion

extension DownloadState {
    /// Initialize from C++ download state and progress
    init(from cState: rac_download_state_t, cProgress: rac_download_progress_t) {
        switch cState {
        case RAC_DOWNLOAD_STATE_PENDING:
            self = .pending
        case RAC_DOWNLOAD_STATE_DOWNLOADING:
            self = .downloading
        case RAC_DOWNLOAD_STATE_EXTRACTING:
            self = .extracting
        case RAC_DOWNLOAD_STATE_RETRYING:
            self = .retrying(attempt: Int(cProgress.retry_attempt))
        case RAC_DOWNLOAD_STATE_COMPLETED:
            self = .completed
        case RAC_DOWNLOAD_STATE_FAILED:
            let errorMessage = cProgress.error_message.map { String(cString: $0) } ?? "Download failed"
            self = .failed(SDKError.download(.downloadFailed, errorMessage))
        case RAC_DOWNLOAD_STATE_CANCELLED:
            self = .cancelled
        default:
            self = .pending
        }
    }
}

// MARK: - DownloadProgress C++ Conversion

extension DownloadProgress {
    /// Initialize from C++ download progress struct
    init(from cProgress: rac_download_progress_t) {
        self.init(
            stage: DownloadStage(from: cProgress.stage),
            bytesDownloaded: cProgress.bytes_downloaded,
            totalBytes: cProgress.total_bytes,
            stageProgress: cProgress.stage_progress,
            speed: cProgress.speed > 0 ? cProgress.speed : nil,
            estimatedTimeRemaining: cProgress.estimated_time_remaining >= 0 ? cProgress.estimated_time_remaining : nil,
            state: DownloadState(from: cProgress.state, cProgress: cProgress)
        )
    }
}
