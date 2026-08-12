import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/thinking_tag_pattern.pb.dart'
    show ReasoningOptions;
import 'package:runanywhere/generated/thinking_tag_pattern.pbenum.dart'
    show ReasoningMode;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCallingOptions, ToolDefinition;

/// The generation path selected after tool/model compatibility preflight.
enum ToolCallingRoute { standardGeneration, toolGeneration, blocked }

class ToolCallingAvailability {
  const ToolCallingAvailability({required this.isAvailable, this.message});

  final bool isAvailable;
  final String? message;
}

class ToolCallingPreflight {
  const ToolCallingPreflight({required this.route, required this.availability});

  final ToolCallingRoute route;
  final ToolCallingAvailability availability;
}

class ToolCallingExecutionPlan {
  const ToolCallingExecutionPlan({
    required this.generationOptions,
    required this.toolOptions,
  });

  final LLMGenerationOptions generationOptions;
  final ToolCallingOptions toolOptions;
}

/// App-level production gate for tool calling.
///
/// Tool definitions, format instructions, the user prompt, and follow-up tool
/// results all share the model context window. The built-in catalog currently
/// produces an initial tools prompt just over 512 tokens, so 512-token models
/// fail before decoding. A published 1K window is the minimum supported tool
/// configuration; a separate execution budget below bounds output and loop
/// duration so that compatible small models remain responsive.
abstract final class ToolCallingModelPolicy {
  static const int minimumContextTokens = 1024;

  static ToolCallingAvailability evaluate(ModelInfo? model) {
    if (model == null) {
      return _unavailable('Choose a chat model before enabling Web & tools.');
    }
    final modelName = model.name.isNotEmpty
        ? model.name
        : (model.id.isNotEmpty ? model.id : 'The current model');
    final contextLength = model.contextLength;
    if (contextLength <= 0) {
      return _unavailable(
        '$modelName does not publish a context-window capability. '
        'Choose a model with at least 1,024 tokens for Web & tools.',
      );
    }
    if (contextLength < minimumContextTokens) {
      return _unavailable(
        '$modelName has a $contextLength-token context window. '
        'Web & tools require at least 1,024 tokens. Choose a larger-context model.',
      );
    }
    return const ToolCallingAvailability(isAvailable: true);
  }

  static ToolCallingPreflight preflight({
    required bool toolsRequested,
    required int registeredToolCount,
    required ModelInfo? model,
  }) {
    if (!toolsRequested || registeredToolCount <= 0) {
      return ToolCallingPreflight(
        route: ToolCallingRoute.standardGeneration,
        availability: evaluate(model),
      );
    }
    final availability = evaluate(model);
    return ToolCallingPreflight(
      route: availability.isAvailable
          ? ToolCallingRoute.toolGeneration
          : ToolCallingRoute.blocked,
      availability: availability,
    );
  }

  static ToolCallingAvailability _unavailable(String message) =>
      ToolCallingAvailability(isAvailable: false, message: message);
}

/// Tool-only limits applied after the normal chat response-budget policy.
abstract final class ToolCallingExecutionPolicy {
  // The shared native loop stops the forced decision at the tool-call closing
  // marker with an independent 192-token safety ceiling. Final synthesis
  // remains concise while retaining enough room for an answer and source URL.
  static const int maxFinalResponseTokens = 96;
  static const int maxToolCalls = 2;
  static const int timeoutMillis = 45000;
  static const String progressMessage = 'Using web & tools…';

  static LLMGenerationOptions generationOptions(LLMGenerationOptions base) {
    final requested = base.maxOutputTokens;
    base
      ..maxOutputTokens =
          (requested >= 1 && requested <= maxFinalResponseTokens)
          ? requested
          : maxFinalResponseTokens
      // Tool decisions must be reproducible. The native tool loop preserves
      // temperature=0 as greedy instead of treating it as an unset value and
      // falling back to sampling.
      ..temperature = 0
      ..topP = 1
      ..reasoning = ReasoningOptions(mode: ReasoningMode.REASONING_MODE_OFF);
    return base;
  }

  static ToolCallingExecutionPlan plan(
    LLMGenerationOptions base,
    List<ToolDefinition> registeredTools,
  ) {
    final generation = generationOptions(base);
    return ToolCallingExecutionPlan(
      generationOptions: generation,
      // Commons recognizes an unambiguous explicit tool name in the prompt and
      // narrows the native decision there, so every SDK gets the same behavior
      // without app-side routing heuristics.
      toolOptions: _toolOptions(registeredTools),
    );
  }

  // `ToolCallingOptions.maxTokens`/`.temperature` were deleted as redundant
  // with the parent `LLMGenerationOptions` (idl/tool_calling.proto) — the
  // native tool loop reads the final-response budget and temperature from
  // `generationOptions()` above (which already pins both), so there is
  // nothing left to set here.
  static ToolCallingOptions _toolOptions(List<ToolDefinition> tools) =>
      ToolCallingOptions(
        tools: tools,
        maxToolCalls: maxToolCalls,
        autoExecute: true,
        keepToolsAvailable: false,
        disableThinking: true,
        // Match the iOS/Android examples: one model turn may request
        // multiple tools (e.g. weather + time) and get them all executed
        // before a single follow-up reply.
        parallelToolCalls: true,
      );
}
