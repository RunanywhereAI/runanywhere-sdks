import Foundation

/// Factory for creating appropriate archive extractors
public class ArchiveExtractorFactory {

    /// Create an archive extractor based on file extension
    public static func createExtractor(for archive: URL) -> ArchiveExtractor {
        let pathExtension = archive.pathExtension.lowercased()

        switch pathExtension {
        case "zip":
            return ZipExtractor()

        case "tar":
            return TarExtractor()

        case "gz", "gzip":
            if archive.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return TarGzExtractor()
            } else {
                return GzipExtractor()
            }

        case "tgz":
            return TarGzExtractor()

        case "bz2", "bzip2":
            if archive.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return TarBz2Extractor()
            } else {
                return Bzip2Extractor()
            }

        case "tbz2":
            return TarBz2Extractor()

        case "xz":
            if archive.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return TarXzExtractor()
            } else {
                return XzExtractor()
            }

        case "txz":
            return TarXzExtractor()

        default:
            // Return a generic extractor that handles unknown formats
            return GenericExtractor()
        }
    }
}
