package com.runanywhere.sdk.models.enums

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Supported archive formats for model packaging
 * Matches iOS ArchiveType exactly
 */
@Serializable
enum class ArchiveType(val fileExtension: String) {
    @SerialName("zip")
    ZIP("zip"),

    @SerialName("tar.bz2")
    TAR_BZ2("tar.bz2"),

    @SerialName("tar.gz")
    TAR_GZ("tar.gz"),

    @SerialName("tar.xz")
    TAR_XZ("tar.xz");

    companion object {
        /**
         * Detect archive type from URL or file path
         * Matches iOS ArchiveType.from(url:) exactly
         */
        fun fromPath(path: String): ArchiveType? {
            val lowercasedPath = path.lowercase()
            return when {
                lowercasedPath.endsWith(".tar.bz2") || lowercasedPath.endsWith(".tbz2") -> TAR_BZ2
                lowercasedPath.endsWith(".tar.gz") || lowercasedPath.endsWith(".tgz") -> TAR_GZ
                lowercasedPath.endsWith(".tar.xz") || lowercasedPath.endsWith(".txz") -> TAR_XZ
                lowercasedPath.endsWith(".zip") -> ZIP
                else -> null
            }
        }
    }
}

/**
 * Describes the internal structure of an archive after extraction
 * Matches iOS ArchiveStructure exactly
 */
@Serializable
enum class ArchiveStructure {
    /**
     * Archive contains a single model file at root or nested in one directory
     */
    @SerialName("singleFileNested")
    SINGLE_FILE_NESTED,

    /**
     * Archive extracts to a directory containing multiple files
     */
    @SerialName("directoryBased")
    DIRECTORY_BASED,

    /**
     * Archive has a subdirectory structure (e.g., extracts to subfolder)
     */
    @SerialName("nestedDirectory")
    NESTED_DIRECTORY,

    /**
     * Unknown structure - will be detected after extraction
     */
    @SerialName("unknown")
    UNKNOWN,
}

/**
 * Describes what files are expected after model extraction/download
 * Used for validation and to understand model requirements
 * Matches iOS ExpectedModelFiles exactly
 */
@Serializable
data class ExpectedModelFiles(
    /**
     * File patterns that must be present (e.g., "*.onnx", "encoder*.onnx")
     */
    val requiredPatterns: List<String> = emptyList(),
    /**
     * File patterns that may be present but are optional
     */
    val optionalPatterns: List<String> = emptyList(),
    /**
     * Description of the model files for documentation
     */
    val description: String? = null,
) {
    companion object {
        /**
         * No specific file expectations
         */
        val NONE = ExpectedModelFiles()
    }
}

/**
 * Describes a file that needs to be downloaded as part of a multi-file model
 * Matches iOS ModelFileDescriptor exactly
 */
@Serializable
data class ModelFileDescriptor(
    /**
     * Relative path from base URL to this file
     */
    val relativePath: String,
    /**
     * Destination path relative to model folder
     */
    val destinationPath: String,
    /**
     * Whether this file is required (vs optional)
     */
    val isRequired: Boolean = true,
)

/**
 * Describes how a model is packaged and what processing is needed after download.
 * This is set during model registration and drives the download/extraction behavior.
 * Matches iOS ModelArtifactType exactly
 */
@Serializable
sealed class ModelArtifactType {
    /**
     * A single model file (e.g., .gguf, .onnx, .mlmodel)
     * No extraction needed - just download and use
     */
    @Serializable
    @SerialName("singleFile")
    data class SingleFile(
        override val expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
    ) : ModelArtifactType()

    /**
     * An archive that needs extraction
     * @property archiveType The archive format (zip, tar.bz2, etc.)
     * @property structure What's inside the archive
     * @property expectedFiles What files to expect after extraction
     */
    @Serializable
    @SerialName("archive")
    data class Archive(
        val archiveType: ArchiveType,
        val structure: ArchiveStructure,
        override val expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
    ) : ModelArtifactType()

    /**
     * Multiple files that need to be downloaded separately
     */
    @Serializable
    @SerialName("multiFile")
    data class MultiFile(
        val files: List<ModelFileDescriptor>,
    ) : ModelArtifactType()

    /**
     * Use a custom download strategy identified by string
     */
    @Serializable
    @SerialName("custom")
    data class Custom(
        val strategyId: String,
    ) : ModelArtifactType()

    /**
     * Built-in model that doesn't require download
     */
    @Serializable
    @SerialName("builtIn")
    data object BuiltIn : ModelArtifactType()

    // =========================================================================
    // MARK: - Computed Properties
    // =========================================================================

    /**
     * Whether this artifact type requires extraction after download
     */
    val requiresExtraction: Boolean
        get() = this is Archive

    /**
     * Whether this artifact type requires downloading
     */
    val requiresDownload: Boolean
        get() = this !is BuiltIn

    /**
     * Get the expected files for this artifact type
     * Open property to be overridden by SingleFile and Archive
     */
    open val expectedFiles: ExpectedModelFiles
        get() = ExpectedModelFiles.NONE

    /**
     * Human-readable description
     */
    val displayName: String
        get() =
            when (this) {
                is SingleFile -> "Single File"
                is Archive -> "${archiveType.fileExtension.uppercase()} Archive"
                is MultiFile -> "Multi-File (${files.size} files)"
                is Custom -> "Custom ($strategyId)"
                is BuiltIn -> "Built-in"
            }

    companion object {
        // =========================================================================
        // MARK: - Factory Methods (matching iOS)
        // =========================================================================

        /**
         * Infer artifact type from download URL
         * Matches iOS ModelArtifactType.infer(from:format:)
         */
        fun infer(url: String?, format: ModelFormat): ModelArtifactType {
            if (url == null) {
                return SingleFile()
            }

            val archiveType = ArchiveType.fromPath(url)
            return if (archiveType != null) {
                Archive(
                    archiveType = archiveType,
                    structure = ArchiveStructure.UNKNOWN,
                    expectedFiles = ExpectedModelFiles.NONE,
                )
            } else {
                SingleFile()
            }
        }

        /**
         * Create a ZIP archive type
         */
        fun zipArchive(
            structure: ArchiveStructure = ArchiveStructure.DIRECTORY_BASED,
            expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
        ): ModelArtifactType =
            Archive(
                archiveType = ArchiveType.ZIP,
                structure = structure,
                expectedFiles = expectedFiles,
            )

        /**
         * Create a tar.bz2 archive type
         */
        fun tarBz2Archive(
            structure: ArchiveStructure = ArchiveStructure.NESTED_DIRECTORY,
            expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
        ): ModelArtifactType =
            Archive(
                archiveType = ArchiveType.TAR_BZ2,
                structure = structure,
                expectedFiles = expectedFiles,
            )

        /**
         * Create a tar.gz archive type
         */
        fun tarGzArchive(
            structure: ArchiveStructure = ArchiveStructure.NESTED_DIRECTORY,
            expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
        ): ModelArtifactType =
            Archive(
                archiveType = ArchiveType.TAR_GZ,
                structure = structure,
                expectedFiles = expectedFiles,
            )

        /**
         * Create a single file type
         */
        fun singleFile(expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE): ModelArtifactType = SingleFile(expectedFiles)

        /**
         * Create a built-in type
         */
        fun builtIn(): ModelArtifactType = BuiltIn
    }
}
