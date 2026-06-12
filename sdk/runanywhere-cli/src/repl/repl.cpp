#include "repl/repl.h"

#include <filesystem>
#include <system_error>

extern "C" {
#include <linenoise.h>
}

namespace rcli::repl {

LineEditor::LineEditor(std::string history_path) : history_path_(std::move(history_path)) {
    if (!history_path_.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(
            std::filesystem::path(history_path_).parent_path(), ec);
        linenoiseHistoryLoad(history_path_.c_str());
        linenoiseHistorySetMaxLen(512);
    }
}

LineEditor::~LineEditor() {
    if (!history_path_.empty()) {
        linenoiseHistorySave(history_path_.c_str());
    }
}

bool LineEditor::read_line(const std::string& prompt, std::string* out_line) {
    char* raw = linenoise(prompt.c_str());
    if (raw == nullptr) {
        return false;  // EOF / Ctrl-D (Ctrl-C inside linenoise returns NULL too)
    }
    *out_line = raw;
    linenoiseFree(raw);
    return true;
}

void LineEditor::add_history(const std::string& line) {
    if (!line.empty()) {
        linenoiseHistoryAdd(line.c_str());
    }
}

}  // namespace rcli::repl
