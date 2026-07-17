#include "repl/repl.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <system_error>

#if !defined(RCLI_NO_LINENOISE)
extern "C" {
#include <linenoise.h>
}
#endif

namespace rcli::repl {

LineEditor::LineEditor(std::string history_path) : history_path_(std::move(history_path)) {
    if (!history_path_.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(
            std::filesystem::path(history_path_).parent_path(), ec);
#if !defined(RCLI_NO_LINENOISE)
        linenoiseHistoryLoad(history_path_.c_str());
        linenoiseHistorySetMaxLen(512);
#endif
    }
}

LineEditor::~LineEditor() {
#if !defined(RCLI_NO_LINENOISE)
    if (!history_path_.empty()) {
        linenoiseHistorySave(history_path_.c_str());
    }
#endif
}

bool LineEditor::read_line(const std::string& prompt, std::string* out_line) {
#if defined(RCLI_NO_LINENOISE)
    std::cerr << prompt;
    std::cerr.flush();
    return static_cast<bool>(std::getline(std::cin, *out_line));
#else
    char* raw = linenoise(prompt.c_str());
    if (raw == nullptr) {
        return false;  // EOF / Ctrl-D (Ctrl-C inside linenoise returns NULL too)
    }
    *out_line = raw;
    linenoiseFree(raw);
    return true;
#endif
}

void LineEditor::add_history(const std::string& line) {
    if (!line.empty()) {
#if defined(RCLI_NO_LINENOISE)
        if (!history_path_.empty()) {
            std::ofstream history(history_path_, std::ios::app);
            history << line << '\n';
        }
#else
        linenoiseHistoryAdd(line.c_str());
#endif
    }
}

}  // namespace rcli::repl
