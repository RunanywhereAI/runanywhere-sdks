/**
 * @file output.h
 * @brief Output discipline helpers + minimal JSON emission.
 *
 * Contract (see sdk/runanywhere-cli/AGENTS.md):
 *   - command RESULTS go to stdout;
 *   - logs, progress, banners, prompts go to stderr;
 *   - --json mode prints exactly ONE JSON document on stdout.
 */

#ifndef RCLI_IO_OUTPUT_H
#define RCLI_IO_OUTPUT_H

#include <cstdint>
#include <string>
#include <vector>

#include "rac/core/rac_types.h"

namespace rcli::out {

/** JSON-escape a UTF-8 string (quotes not included). */
std::string json_escape(const std::string& value);

/**
 * Minimal JSON document builder — enough for rcli's flat objects/arrays
 * without pulling a JSON dependency into the CLI.
 */
class JsonWriter {
   public:
    JsonWriter& begin_object();
    JsonWriter& end_object();
    JsonWriter& begin_array(const std::string& key = "");
    JsonWriter& end_array();
    JsonWriter& field(const std::string& key, const std::string& value);
    JsonWriter& field(const std::string& key, const char* value);
    JsonWriter& field(const std::string& key, int64_t value);
    JsonWriter& field(const std::string& key, double value);
    JsonWriter& field(const std::string& key, bool value);
    JsonWriter& value(const std::string& value);
    JsonWriter& value(const char* value);
    JsonWriter& value(int64_t value);
    JsonWriter& value(double value);
    JsonWriter& value(bool value);
    /** Object element inside an array. */
    JsonWriter& begin_array_object();

    [[nodiscard]] const std::string& str() const { return buffer_; }

   private:
    void comma();

    std::string buffer_;
    std::vector<bool> first_in_scope_;
};

/** Print a result line to stdout (newline appended). */
void result_line(const std::string& line);

/** Print a status/notice line to stderr (newline appended). */
void status_line(const std::string& line);

/** Print an error to stderr as "error: <message>". */
void error_line(const std::string& message);

/** Human message for a rac_result_t (falls back to the numeric code). */
std::string describe_result(rac_result_t result);

/** "1.4 GB" / "532 MB" style size formatting. */
std::string human_bytes(uint64_t bytes);

/** Simple left-aligned column table rendered to stdout. */
void table(const std::vector<std::string>& header,
           const std::vector<std::vector<std::string>>& rows);

}  // namespace rcli::out

#endif  // RCLI_IO_OUTPUT_H
