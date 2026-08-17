/**
 * @file commands.h
 * @brief Subcommand registration — one function per command file.
 *
 * The command surface mirrors the SDK public API spec
 * (thoughts/shared/plans/public_api_spec.md): a namespace per modality and the
 * spec's verb under it (`rcli llm generate`, `rcli models download`, …), with
 * option names in kebab-case (`--max-output-tokens`, `--top-p`).
 *
 * Each register_* attaches a CLI11 subcommand whose callback performs:
 * parse → bootstrap() → ONE commons entry point → render. Inference and
 * lifecycle logic stay in commons per the repo layering rule; command files
 * only translate between argv and the rac_* C ABI.
 *
 * The terminal-friendly top-level names (`run`, `chat`, `list`, `pull`, `rm`,
 * `show`) are aliases: one configure_* function wires the options and callback,
 * and it is attached both under the namespace and at the top level, so there is
 * never a second implementation to keep in sync.
 *
 * Callbacks throw CLI::RuntimeError(exit_code) on failure; main.cpp maps that
 * to the process exit code (0 ok, 1 runtime error, 2 usage error).
 */

#ifndef RCLI_COMMANDS_COMMANDS_H
#define RCLI_COMMANDS_COMMANDS_H

#include <CLI11.hpp>

#include "bootstrap.h"

namespace rcli::commands {

// --- Feature namespaces (spec verb grammar) --------------------------------
void register_llm(CLI::App& app, GlobalOptions& options);
void register_vlm(CLI::App& app, GlobalOptions& options);
void register_tool(CLI::App& app, GlobalOptions& options);  // llm tool-call (attaches to `llm`)
void register_stt(CLI::App& app, GlobalOptions& options);
void register_tts(CLI::App& app, GlobalOptions& options);
void register_vad(CLI::App& app, GlobalOptions& options);
void register_embed(CLI::App& app, GlobalOptions& options);
void register_rerank(CLI::App& app, GlobalOptions& options);
void register_image(CLI::App& app, GlobalOptions& options);
void register_diarize(CLI::App& app, GlobalOptions& options);
void register_segment(CLI::App& app, GlobalOptions& options);
void register_voice(CLI::App& app, GlobalOptions& options);
void register_rag(CLI::App& app, GlobalOptions& options);
void register_models(CLI::App& app, GlobalOptions& options);
void register_lora(CLI::App& app, GlobalOptions& options);

// --- Top-level aliases of namespaced verbs ---------------------------------
void register_llm_aliases(CLI::App& app, GlobalOptions& options);     // run, chat
void register_models_aliases(CLI::App& app, GlobalOptions& options);  // list, pull, rm, show

// --- Infrastructure --------------------------------------------------------
void register_version(CLI::App& app, GlobalOptions& options);
void register_info(CLI::App& app, GlobalOptions& options);
void register_backends(CLI::App& app, GlobalOptions& options);
void register_serve(CLI::App& app, GlobalOptions& options);
void register_bench(CLI::App& app, GlobalOptions& options);
void register_auth(CLI::App& app, GlobalOptions& options);
void register_telemetry(CLI::App& app, GlobalOptions& options);

/**
 * Which llm/vlm entry point a configured command drives.
 *   Generate — one unary result, rendered once it completes.
 *   Stream   — tokens printed as they arrive.
 *   Chat     — Stream, falling back to the REPL when no prompt is given.
 */
enum class LlmVerb { Generate, Stream, Chat };

/** Where the model comes from: a `--model` option or the first positional. */
enum class ModelArg { Option, Positional };

void configure_llm(CLI::App* cmd, GlobalOptions& options, LlmVerb verb, ModelArg model_arg);
void configure_vlm_generate(CLI::App* cmd, GlobalOptions& options);

// Model-lifecycle verbs, shared by the `models` namespace and its aliases.
void configure_models_list(CLI::App* cmd, GlobalOptions& options);
void configure_models_get(CLI::App* cmd, GlobalOptions& options);
void configure_models_download(CLI::App* cmd, GlobalOptions& options);
void configure_models_delete(CLI::App* cmd, GlobalOptions& options);

/**
 * Shared pull flow (plan → start → progress → terminal state) for an
 * already-registered model id. Used by cmd_pull and by commands that need an
 * ensure-downloaded step (stt/tts/vad/voice). Returns 0 / 1 / 130 (cancel).
 */
int pull_model_flow(const GlobalOptions& options, const std::string& model_id);

/**
 * Transcribe an audio file and hand back the text instead of rendering it, so
 * the chat REPL can turn `/audio <file>` into an ordinary user turn. Downloads
 * and loads the STT model if needed. Returns 0 / 1 / 2 like a command callback.
 */
int transcribe_to_text(const GlobalOptions& options, const std::string& model_ref,
                       const std::string& audio_path, std::string* out_text);

/**
 * Speak `text` into a WAV file, so the chat REPL's `/say` can voice a reply.
 * Commons has no playback path (`tts speak` is unimplemented), so the file is
 * the deliverable and the caller prints where it landed.
 */
int synthesize_to_file(const GlobalOptions& options, const std::string& voice_ref,
                       const std::string& text, const std::string& output_path);

/**
 * Attach the spec verb name to a namespace whose options live on the namespace
 * itself (`rcli stt transcribe --input a.wav` and `rcli stt --input a.wav` are
 * the same command). The verb is a grammar marker: CLI11 fallthrough hands its
 * options to the parent, and the parent owns the single callback.
 */
inline CLI::App* add_verb_alias(CLI::App* ns, const std::string& verb,
                                const std::string& description) {
    CLI::App* verb_app = ns->add_subcommand(verb, description);
    verb_app->fallthrough(true);
    return verb_app;
}

}  // namespace rcli::commands

#endif  // RCLI_COMMANDS_COMMANDS_H
