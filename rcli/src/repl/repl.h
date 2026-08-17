/**
 * @file repl.h
 * @brief Thin RAII wrapper over vendored linenoise (history + line input).
 */

#ifndef RCLI_REPL_REPL_H
#define RCLI_REPL_REPL_H

#include <string>
#include <utility>

namespace rcli::repl {

/**
 * Split a slash-command argument string into its first word and the remainder,
 * e.g. "  shot.png what is this" -> {"shot.png", "what is this"}. Both halves
 * are empty when there is nothing but whitespace, which is how the REPL detects
 * a command invoked without its required argument.
 */
std::pair<std::string, std::string> split_first_word(const std::string& text);

class LineEditor {
   public:
    /** history_path may be empty (no persistence, e.g. RUNANYWHERE_NOHISTORY). */
    explicit LineEditor(std::string history_path);
    ~LineEditor();

    /** False on EOF (Ctrl-D). Empty lines are returned as empty strings. */
    bool read_line(const std::string& prompt, std::string* out_line);

    /** Record a line in history (skips empties/duplicates of last entry). */
    void add_history(const std::string& line);

   private:
    std::string history_path_;
};

}  // namespace rcli::repl

#endif  // RCLI_REPL_REPL_H
