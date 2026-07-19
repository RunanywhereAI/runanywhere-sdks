/**
 * @file commands.h
 * @brief Subcommand registration — one function per command file.
 *
 * Each register_* attaches a CLI11 subcommand whose callback performs:
 * parse → bootstrap() → ONE commons entry point → render. Inference and
 * lifecycle logic stay in commons per the repo layering rule; command files
 * only translate between argv and the rac_* C ABI.
 *
 * Callbacks throw CLI::RuntimeError(exit_code) on failure; main.cpp maps that
 * to the process exit code (0 ok, 1 runtime error, 2 usage error).
 */

#ifndef RCLI_COMMANDS_COMMANDS_H
#define RCLI_COMMANDS_COMMANDS_H

#include <CLI11.hpp>

#include "bootstrap.h"

namespace rcli::commands {

void register_version(CLI::App& app, GlobalOptions& options);
void register_info(CLI::App& app, GlobalOptions& options);
void register_backends(CLI::App& app, GlobalOptions& options);
void register_list(CLI::App& app, GlobalOptions& options);
void register_pull(CLI::App& app, GlobalOptions& options);
void register_rm(CLI::App& app, GlobalOptions& options);
void register_show(CLI::App& app, GlobalOptions& options);
void register_run(CLI::App& app, GlobalOptions& options);
void register_image(CLI::App& app, GlobalOptions& options);
void register_embed(CLI::App& app, GlobalOptions& options);
void register_stt(CLI::App& app, GlobalOptions& options);
void register_tts(CLI::App& app, GlobalOptions& options);
void register_vad(CLI::App& app, GlobalOptions& options);
void register_voice(CLI::App& app, GlobalOptions& options);
void register_serve(CLI::App& app, GlobalOptions& options);
void register_lora(CLI::App& app, GlobalOptions& options);
void register_rag(CLI::App& app, GlobalOptions& options);
void register_bench(CLI::App& app, GlobalOptions& options);

/**
 * Shared pull flow (plan → start → progress → terminal state) for an
 * already-registered model id. Used by cmd_pull and by commands that need an
 * ensure-downloaded step (stt/tts/vad/voice). Returns 0 / 1 / 130 (cancel).
 */
int pull_model_flow(const GlobalOptions& options, const std::string& model_id);

}  // namespace rcli::commands

#endif  // RCLI_COMMANDS_COMMANDS_H
