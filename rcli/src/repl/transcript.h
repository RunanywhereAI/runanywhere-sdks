/**
 * @file transcript.h
 * @brief The conversation a chat session remembers.
 *
 * Commons takes the whole conversation per request: LLMGenerateRequest carries
 * `repeated ChatMessage messages`, oldest first, ending with the turn the model
 * must answer (idl/llm_service.proto). The single `prompt` and `history` fields
 * are reserved. So a chat session's only state is the ordered list of turns,
 * and this owns it.
 *
 * The system prompt is NOT a turn. It rides in LLMGenerationOptions and commons
 * drops system messages when it flattens the array for engines
 * (llm_module.cpp), so keeping it here would send it twice.
 */

#ifndef RCLI_REPL_TRANSCRIPT_H
#define RCLI_REPL_TRANSCRIPT_H

#include <cstddef>
#include <string>
#include <vector>

namespace runanywhere::v1 {
class LLMGenerateRequest;
}

namespace rcli::repl {

enum class Role { User, Assistant };

struct Turn {
    Role role;
    std::string content;
};

/**
 * Ordered conversation turns, capped so a long session cannot outgrow the
 * model's context window.
 *
 * The cap mirrors the voice agent's policy (voice_agent_d7_abi.cpp), which
 * erases oldest-first once the history exceeds its bound. Turns are counted
 * rather than tokens because no engine reports a window size through the ABI;
 * `/context` therefore shows turns, not a percentage.
 */
class Transcript {
   public:
    static constexpr std::size_t kDefaultMaxTurns = 40;

    explicit Transcript(std::size_t max_turns = kDefaultMaxTurns);

    void add(Role role, std::string content);
    void clear();

    const std::vector<Turn>& turns() const { return turns_; }
    std::size_t size() const { return turns_.size(); }
    bool empty() const { return turns_.empty(); }
    std::size_t max_turns() const { return max_turns_; }

    /** True once a turn has been dropped, so `/context` can say so. */
    bool trimmed() const { return trimmed_; }

   private:
    void trim();

    std::vector<Turn> turns_;
    std::size_t max_turns_;
    bool trimmed_ = false;
};

/**
 * Fill the request's message array: prior turns oldest first, then the turn the
 * model must answer. `history` may be null for a single-turn generation.
 *
 * The system prompt is deliberately absent; it belongs in
 * LLMGenerationOptions.system_prompt, and commons drops system messages when it
 * flattens this array.
 */
void fill_messages(runanywhere::v1::LLMGenerateRequest* request, const Transcript* history,
                   const std::string& prompt);

}  // namespace rcli::repl

#endif  // RCLI_REPL_TRANSCRIPT_H
