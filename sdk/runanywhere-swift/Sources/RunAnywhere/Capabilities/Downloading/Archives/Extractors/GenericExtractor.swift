import Foundation

/// Generic extractor for unknown archive formats
public class GenericExtractor: BaseArchiveExtractor {

    public init() {
        super.init(category: "GenericExtractor")
    }

    public override func extract(archive: URL) async throws -> URL {
        logger.info("Attempting generic extraction for: \(archive.lastPathComponent)")

        // For non-archive files, just return the file itself
        if !needsExtraction(archive) {
            logger.info("File does not appear to be an archive, returning as-is")
            return archive
        }

        // Try to determine format and extract
        throw DownloadError.extractionFailed("Unknown archive format: \(archive.pathExtension)")
    }

    // MARK: - Private Methods

    private func needsExtraction(_ url: URL) -> Bool {
        let archiveExtensions = ["zip", "gz", "gzip", "tgz", "tar", "bz2", "bzip2", "tbz2", "xz", "txz", "7z", "rar"]
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }
}
