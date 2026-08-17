#include "repl/transcript.h"

#include <utility>

#include "chat.pb.h"
#include "llm_service.pb.h"

namespace rcli::repl {

Transcript::Transcript(std::size_t max_turns)
    : max_turns_(max_turns > 0 ? max_turns : kDefaultMaxTurns) {}

void Transcript::add(Role role, std::string content) {
    if (content.empty()) {
        return;
    }
    turns_.push_back(Turn{role, std::move(content)});
    trim();
}

void Transcript::clear() {
    turns_.clear();
    trimmed_ = false;
}

void Transcript::trim() {
    if (turns_.size() > max_turns_) {
        turns_.erase(turns_.begin(),
                     turns_.begin() + static_cast<std::ptrdiff_t>(turns_.size() - max_turns_));
        trimmed_ = true;
    }
    // Commons skips a leading assistant turn when it flattens the array
    // (llm_module.cpp), so a window starting on one would report a turn the
    // model never sees. Drop it here instead, and keep the two counts equal.
    if (!turns_.empty() && turns_.front().role == Role::Assistant) {
        turns_.erase(turns_.begin());
        trimmed_ = true;
    }
}

void fill_messages(runanywhere::v1::LLMGenerateRequest* request, const Transcript* history,
                   const std::string& prompt) {
    namespace v1 = runanywhere::v1;
    if (history != nullptr) {
        for (const Turn& turn : history->turns()) {
            v1::ChatMessage* prior = request->add_messages();
            prior->set_role(turn.role == Role::User ? v1::MESSAGE_ROLE_USER
                                                    : v1::MESSAGE_ROLE_ASSISTANT);
            prior->set_content(turn.content);
        }
    }
    v1::ChatMessage* current = request->add_messages();
    current->set_role(v1::MESSAGE_ROLE_USER);
    current->set_content(prompt);
}

}  // namespace rcli::repl
