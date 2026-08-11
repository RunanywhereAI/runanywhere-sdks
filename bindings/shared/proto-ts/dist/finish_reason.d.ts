export declare const protobufPackage = "runanywhere.v1";
/**
 * One declared vocabulary, used in every place a finish reason is reported
 * on the LLM generation path (LLMGenerationResult, LLMStreamEvent,
 * ToolCallingResult).
 */
export declare enum FinishReason {
    FINISH_REASON_UNSPECIFIED = 0,
    /** FINISH_REASON_STOP - End-of-turn token. OpenAI "stop" / Anthropic "end_turn". */
    FINISH_REASON_STOP = 1,
    /** FINISH_REASON_LENGTH - Hit max_output_tokens. OpenAI "length" / Anthropic "max_tokens". */
    FINISH_REASON_LENGTH = 2,
    /** FINISH_REASON_STOP_SEQUENCE - One of options.stop_sequences fired; see `stop_sequence`. */
    FINISH_REASON_STOP_SEQUENCE = 3,
    /** FINISH_REASON_TOOL_CALLS - Model wants a tool run before it can continue. */
    FINISH_REASON_TOOL_CALLS = 4,
    /** FINISH_REASON_CANCELLED - Caller cancelled. No cloud analogue. */
    FINISH_REASON_CANCELLED = 5,
    /** FINISH_REASON_CONTEXT_OVERFLOW - Conversation exceeded the allocated context window. */
    FINISH_REASON_CONTEXT_OVERFLOW = 6,
    /** FINISH_REASON_ERROR - Generation failed; see `error`. */
    FINISH_REASON_ERROR = 7,
    UNRECOGNIZED = -1
}
export declare function finishReasonFromJSON(object: any): FinishReason;
export declare function finishReasonToJSON(object: FinishReason): string;
