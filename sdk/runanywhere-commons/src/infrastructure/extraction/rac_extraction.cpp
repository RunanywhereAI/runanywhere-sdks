/**
 * @file rac_extraction.cpp
 * @brief Native archive extraction implementation using libarchive.
 *
 * Streaming extraction with constant memory usage regardless of archive size.
 * Supports ZIP, TAR.GZ, TAR.BZ2, TAR.XZ with auto-detection via magic bytes.
 */

#include "rac/infrastructure/extraction/rac_extraction.h"

#include <archive.h>
#include <archive_entry.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32
#include <direct.h>  // for _mkdir
#endif

#include "rac/core/rac_logger.h"

static const char* kLogTag = "Extraction";

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

/**
 * Security: Check for path traversal (zip-slip attack).
 * Rejects absolute paths and paths containing ".." components.
 */
static bool is_path_safe(const char* pathname) {
    if (!pathname || pathname[0] == '\0') return false;

    // Reject absolute paths
    if (pathname[0] == '/') return false;

    // Reject paths containing ".." components
    const char* p = pathname;
    while (*p) {
        if (p[0] == '.' && p[1] == '.') {
            // ".." at start, after "/" , or at end
            if ((p == pathname || *(p - 1) == '/') && (p[2] == '/' || p[2] == '\0')) {
                return false;
            }
        }
        p++;
    }
    return true;
}

/**
 * Check if an entry should be skipped (macOS resource forks, etc.).
 */
static bool should_skip_entry(const char* pathname, rac_bool_t skip_macos) {
    if (!pathname || pathname[0] == '\0') return true;

    if (skip_macos) {
        // Skip __MACOSX/ directory and its contents
        if (strstr(pathname, "__MACOSX") != nullptr) return true;

        // Skip ._ resource fork files
        const char* basename = strrchr(pathname, '/');
        basename = basename ? basename + 1 : pathname;
        if (basename[0] == '.' && basename[1] == '_') return true;
    }
    return false;
}

/**
 * Create a directory and all intermediate directories.
 * Equivalent to `mkdir -p`.
 */
static rac_result_t create_directories(const std::string& path) {
    if (path.empty()) return RAC_SUCCESS;

    std::string current;
    for (size_t i = 0; i < path.size(); i++) {
        current += path[i];
        if (path[i] == '/' || i == path.size() - 1) {
            if (current == "/") continue;
#ifdef _WIN32
            int ret = _mkdir(current.c_str());
#else
            int ret = mkdir(current.c_str(), 0755);
#endif
            if (ret != 0 && errno != EEXIST) {
                // Check if it already exists as a directory
                struct stat st;
                if (stat(current.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
                    return RAC_ERROR_EXTRACTION_FAILED;
                }
            }
        }
    }
    return RAC_SUCCESS;
}

/**
 * Ensure trailing slash on directory path.
 */
static std::string ensure_trailing_slash(const std::string& path) {
    if (path.empty() || path.back() == '/') return path;
    return path + '/';
}

// =============================================================================
// PUBLIC API - rac_extract_archive_native
// =============================================================================

rac_result_t rac_extract_archive_native(const char* archive_path, const char* destination_dir,
                                         const rac_extraction_options_t* options,
                                         rac_extraction_progress_fn progress_callback,
                                         void* user_data, rac_extraction_result_t* out_result) {
    if (!archive_path || !destination_dir) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Check archive file exists
    struct stat archive_stat;
    if (stat(archive_path, &archive_stat) != 0) {
        RAC_LOG_ERROR(kLogTag, "Archive file not found: %s", archive_path);
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Use defaults if no options provided
    rac_extraction_options_t opts =
        options ? *options : RAC_EXTRACTION_OPTIONS_DEFAULT;

    // Create destination directory
    rac_result_t dir_result = create_directories(destination_dir);
    if (RAC_FAILED(dir_result)) {
        RAC_LOG_ERROR(kLogTag, "Failed to create destination directory: %s", destination_dir);
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    std::string dest_dir = ensure_trailing_slash(destination_dir);

    RAC_LOG_INFO(kLogTag, "Extracting archive: %s -> %s", archive_path, destination_dir);

    // Open archive for reading (streaming)
    struct archive* a = archive_read_new();
    if (!a) {
        RAC_LOG_ERROR(kLogTag, "Failed to allocate archive reader");
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    // Enable all supported formats and filters for auto-detection
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);

    // Open the archive file with 10KB block size (streaming)
    int r = archive_read_open_filename(a, archive_path, 10240);
    if (r != ARCHIVE_OK) {
        const char* err = archive_error_string(a);
        RAC_LOG_ERROR(kLogTag, "Failed to open archive: %s (%s)", archive_path,
                      err ? err : "unknown error");
        archive_read_free(a);
        return RAC_ERROR_UNSUPPORTED_ARCHIVE;
    }

    // Prepare disk writer for extraction
    struct archive* ext = archive_write_disk_new();
    if (!ext) {
        RAC_LOG_ERROR(kLogTag, "Failed to allocate disk writer");
        archive_read_free(a);
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    // Set extraction flags: preserve timestamps and permissions
    int flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM;
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);

    // Extract entries (streaming loop)
    rac_extraction_result_t result = {0, 0, 0, 0};
    struct archive_entry* entry;
    rac_result_t status = RAC_SUCCESS;

    while (true) {
        r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) break;

        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            const char* err = archive_error_string(a);
            RAC_LOG_ERROR(kLogTag, "Error reading archive entry: %s", err ? err : "unknown");
            status = RAC_ERROR_EXTRACTION_FAILED;
            break;
        }

        const char* pathname = archive_entry_pathname(entry);
        if (!pathname) {
            archive_read_data_skip(a);
            continue;
        }

        // Security: zip-slip protection
        if (!is_path_safe(pathname)) {
            RAC_LOG_WARNING(kLogTag, "Skipping unsafe path: %s", pathname);
            result.entries_skipped++;
            archive_read_data_skip(a);
            continue;
        }

        // Skip macOS resource forks
        if (should_skip_entry(pathname, opts.skip_macos_resources)) {
            result.entries_skipped++;
            archive_read_data_skip(a);
            continue;
        }

        // Handle symbolic links
        unsigned int entry_type = archive_entry_filetype(entry);
        if (entry_type == AE_IFLNK) {
            if (opts.skip_symlinks) {
                result.entries_skipped++;
                archive_read_data_skip(a);
                continue;
            }
            // Safety: reject symlinks pointing outside destination
            const char* link_target = archive_entry_symlink(entry);
            if (link_target && (link_target[0] == '/' || strstr(link_target, "..") != nullptr)) {
                RAC_LOG_WARNING(kLogTag, "Skipping unsafe symlink: %s -> %s", pathname,
                                link_target);
                result.entries_skipped++;
                archive_read_data_skip(a);
                continue;
            }
        }

        // Rewrite path to be under destination directory
        std::string full_path = dest_dir + pathname;
        archive_entry_set_pathname(entry, full_path.c_str());

        // Also rewrite hardlink paths if present
        const char* hardlink = archive_entry_hardlink(entry);
        if (hardlink && hardlink[0] != '\0') {
            std::string full_hardlink = dest_dir + hardlink;
            archive_entry_set_hardlink(entry, full_hardlink.c_str());
        }

        // Write entry header (creates file/directory on disk)
        r = archive_write_header(ext, entry);
        if (r != ARCHIVE_OK) {
            const char* err = archive_error_string(ext);
            RAC_LOG_WARNING(kLogTag, "Failed to write header for: %s (%s)", pathname,
                            err ? err : "unknown");
            archive_read_data_skip(a);
            continue;
        }

        // Copy file data (streaming, constant memory)
        if (archive_entry_size(entry) > 0 && entry_type == AE_IFREG) {
            const void* buff;
            size_t size;
            la_int64_t offset;

            while (true) {
                r = archive_read_data_block(a, &buff, &size, &offset);
                if (r == ARCHIVE_EOF) break;
                if (r != ARCHIVE_OK) {
                    const char* err = archive_error_string(a);
                    RAC_LOG_WARNING(kLogTag, "Error reading data for: %s (%s)", pathname,
                                    err ? err : "unknown");
                    break;
                }
                r = archive_write_data_block(ext, buff, size, offset);
                if (r != ARCHIVE_OK) {
                    const char* err = archive_error_string(ext);
                    RAC_LOG_WARNING(kLogTag, "Error writing data for: %s (%s)", pathname,
                                    err ? err : "unknown");
                    break;
                }
                result.bytes_extracted += static_cast<int64_t>(size);
            }
        }

        // Finish entry (sets permissions, timestamps)
        archive_write_finish_entry(ext);

        // Track statistics
        if (entry_type == AE_IFDIR) {
            result.directories_created++;
        } else if (entry_type == AE_IFREG) {
            result.files_extracted++;
        }

        // Progress callback
        if (progress_callback) {
            progress_callback(result.files_extracted, 0 /* total unknown in streaming */,
                              result.bytes_extracted, user_data);
        }
    }

    // Cleanup
    archive_read_free(a);
    archive_write_free(ext);

    // Output result
    if (out_result) {
        *out_result = result;
    }

    if (RAC_SUCCEEDED(status)) {
        RAC_LOG_INFO(kLogTag, "Extraction complete: %d files, %d dirs, %lld bytes, %d skipped",
                     result.files_extracted, result.directories_created,
                     static_cast<long long>(result.bytes_extracted), result.entries_skipped);
    }

    return status;
}

// =============================================================================
// PUBLIC API - rac_detect_archive_type
// =============================================================================

rac_bool_t rac_detect_archive_type(const char* file_path, rac_archive_type_t* out_type) {
    if (!file_path || !out_type) return RAC_FALSE;

    FILE* f = fopen(file_path, "rb");
    if (!f) return RAC_FALSE;

    unsigned char magic[6] = {0};
    size_t bytes_read = fread(magic, 1, sizeof(magic), f);
    fclose(f);

    if (bytes_read < 2) return RAC_FALSE;

    // ZIP: PK\x03\x04
    if (bytes_read >= 4 && magic[0] == 0x50 && magic[1] == 0x4B && magic[2] == 0x03 &&
        magic[3] == 0x04) {
        *out_type = RAC_ARCHIVE_TYPE_ZIP;
        return RAC_TRUE;
    }

    // GZIP (tar.gz): \x1f\x8b
    if (magic[0] == 0x1F && magic[1] == 0x8B) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_GZ;
        return RAC_TRUE;
    }

    // BZIP2 (tar.bz2): BZh
    if (bytes_read >= 3 && magic[0] == 0x42 && magic[1] == 0x5A && magic[2] == 0x68) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_BZ2;
        return RAC_TRUE;
    }

    // XZ (tar.xz): \xFD7zXZ\x00
    if (bytes_read >= 6 && magic[0] == 0xFD && magic[1] == 0x37 && magic[2] == 0x7A &&
        magic[3] == 0x58 && magic[4] == 0x5A && magic[5] == 0x00) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_XZ;
        return RAC_TRUE;
    }

    return RAC_FALSE;
}
