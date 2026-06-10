#include "io/output.h"

#include <cinttypes>
#include <cstdio>

#include "rac/core/rac_error.h"

namespace rcli::out {

std::string json_escape(const std::string& value) {
    std::string escaped;
    escaped.reserve(value.size() + 8);
    for (const char c : value) {
        switch (c) {
            case '"':
                escaped += "\\\"";
                break;
            case '\\':
                escaped += "\\\\";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    escaped += buf;
                } else {
                    escaped += c;
                }
        }
    }
    return escaped;
}

void JsonWriter::comma() {
    if (!first_in_scope_.empty()) {
        if (!first_in_scope_.back()) {
            buffer_ += ',';
        }
        first_in_scope_.back() = false;
    }
}

JsonWriter& JsonWriter::begin_object() {
    comma();
    buffer_ += '{';
    first_in_scope_.push_back(true);
    return *this;
}

JsonWriter& JsonWriter::end_object() {
    buffer_ += '}';
    if (!first_in_scope_.empty()) {
        first_in_scope_.pop_back();
    }
    return *this;
}

JsonWriter& JsonWriter::begin_array(const std::string& key) {
    comma();
    if (!key.empty()) {
        buffer_ += '"' + json_escape(key) + "\":";
    }
    buffer_ += '[';
    first_in_scope_.push_back(true);
    return *this;
}

JsonWriter& JsonWriter::end_array() {
    buffer_ += ']';
    if (!first_in_scope_.empty()) {
        first_in_scope_.pop_back();
    }
    return *this;
}

JsonWriter& JsonWriter::begin_array_object() {
    return begin_object();
}

JsonWriter& JsonWriter::field(const std::string& key, const std::string& value) {
    comma();
    buffer_ += '"' + json_escape(key) + "\":\"" + json_escape(value) + '"';
    return *this;
}

JsonWriter& JsonWriter::field(const std::string& key, const char* value) {
    return field(key, std::string(value ? value : ""));
}

JsonWriter& JsonWriter::field(const std::string& key, int64_t value) {
    comma();
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%" PRId64, value);
    buffer_ += '"' + json_escape(key) + "\":" + buf;
    return *this;
}

JsonWriter& JsonWriter::field(const std::string& key, double value) {
    comma();
    char buf[48];
    std::snprintf(buf, sizeof(buf), "%g", value);
    buffer_ += '"' + json_escape(key) + "\":" + buf;
    return *this;
}

JsonWriter& JsonWriter::field(const std::string& key, bool value) {
    comma();
    buffer_ += '"' + json_escape(key) + "\":" + (value ? "true" : "false");
    return *this;
}

void result_line(const std::string& line) {
    std::fprintf(stdout, "%s\n", line.c_str());
    std::fflush(stdout);
}

void status_line(const std::string& line) {
    std::fprintf(stderr, "%s\n", line.c_str());
}

void error_line(const std::string& message) {
    std::fprintf(stderr, "error: %s\n", message.c_str());
}

std::string describe_result(rac_result_t result) {
    const char* message = rac_error_message(result);
    if (message && message[0] != '\0') {
        return std::string(message) + " (" + std::to_string(result) + ")";
    }
    return "rac error " + std::to_string(result);
}

std::string human_bytes(uint64_t bytes) {
    constexpr const char* kUnits[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    size_t unit = 0;
    while (value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }
    char buf[32];
    if (unit == 0) {
        std::snprintf(buf, sizeof(buf), "%" PRIu64 " B", bytes);
    } else {
        std::snprintf(buf, sizeof(buf), "%.1f %s", value, kUnits[unit]);
    }
    return buf;
}

void table(const std::vector<std::string>& header,
           const std::vector<std::vector<std::string>>& rows) {
    std::vector<size_t> widths(header.size(), 0);
    for (size_t c = 0; c < header.size(); ++c) {
        widths[c] = header[c].size();
    }
    for (const auto& row : rows) {
        for (size_t c = 0; c < row.size() && c < widths.size(); ++c) {
            widths[c] = std::max(widths[c], row[c].size());
        }
    }

    const auto print_row = [&](const std::vector<std::string>& row) {
        std::string line;
        for (size_t c = 0; c < widths.size(); ++c) {
            const std::string& cell = (c < row.size()) ? row[c] : std::string();
            line += cell;
            if (c + 1 < widths.size()) {
                line.append(widths[c] - cell.size() + 4, ' ');
            }
        }
        result_line(line);
    };

    print_row(header);
    for (const auto& row : rows) {
        print_row(row);
    }
}

}  // namespace rcli::out
