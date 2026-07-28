// chat-template.ts — format a conversation the way the model was trained to read.
//
// WHY THIS EXISTS
// Instruct models are fine-tuned on a specific turn markup (ChatML, Llama-3
// headers, Gemma turns, Mistral [INST]). If you hand them a hand-rolled
// "User: …\nAssistant: …" transcript instead, they are doing raw text completion
// outside their trained format — and small models respond by ignoring the
// conversation and emitting a generic greeting. That is a *memory* bug from the
// user's point of view ("it forgot my name") but really a formatting bug.
//
// The llama.cpp backend passes a prompt through verbatim when it already
// contains turn markup, and otherwise wraps the WHOLE string as a single user
// message — which is exactly how a multi-turn transcript collapses into one turn.
// So the correct prompt has to be built here.

export type ChatTemplate = 'chatml' | 'llama3' | 'gemma' | 'mistral';

export interface ChatTurn {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

/** Drop a reasoning block so old <think> text is never replayed as context. */
function withoutThinking(text: string): string {
  return text.replace(/<(think|thinking)>[\s\S]*?<\/\1>/gi, '').replace(/<(think|thinking)>[\s\S]*$/i, '').trim();
}

/**
 * Render `turns` into the prompt string for `template`, ending with the opening
 * assistant marker so the model continues as the assistant.
 *
 * A `system` turn is merged per the family's convention (Gemma has no system
 * role, so it is folded into the first user turn).
 */
export interface FormatOptions {
  /**
   * Open the assistant turn with an EMPTY reasoning block so a thinking model
   * answers immediately.
   *
   * Reasoning models (Qwen3.5 and friends) otherwise spend the whole token
   * budget deliberating and the reply never arrives — measured on device: with
   * 256 tokens the answer was empty, with this prefill it was correct in 586ms.
   * Only meaningful for ChatML-style models.
   */
  suppressThinking?: boolean;
}

export function formatChat(
  turns: ChatTurn[],
  template: ChatTemplate = 'chatml',
  opts: FormatOptions = {}
): string {
  const clean = turns
    .map((t) => ({ role: t.role, content: t.role === 'assistant' ? withoutThinking(t.content) : (t.content || '').trim() }))
    .filter((t) => t.content.length > 0);

  const system = clean.find((t) => t.role === 'system');
  const body = clean.filter((t) => t.role !== 'system');

  switch (template) {
    case 'llama3': {
      let s = '<|begin_of_text|>';
      const head = (role: string): string => `<|start_header_id|>${role}<|end_header_id|>\n\n`;
      if (system) s += head('system') + system.content + '<|eot_id|>';
      for (const t of body) s += head(t.role) + t.content + '<|eot_id|>';
      return s + head('assistant');
    }
    case 'gemma': {
      // Gemma has no system role: the system text rides on the first user turn.
      let s = '';
      let pending = system ? system.content : '';
      for (const t of body) {
        const role = t.role === 'assistant' ? 'model' : 'user';
        const content = role === 'user' && pending ? `${pending}\n\n${t.content}` : t.content;
        if (role === 'user') pending = '';
        s += `<start_of_turn>${role}\n${content}<end_of_turn>\n`;
      }
      return s + '<start_of_turn>model\n';
    }
    case 'mistral': {
      // Mistral wraps each user turn in [INST]…[/INST]; the system rides on the first.
      let s = '<s>';
      let pending = system ? system.content : '';
      for (const t of body) {
        if (t.role === 'user') {
          const content = pending ? `${pending}\n\n${t.content}` : t.content;
          pending = '';
          s += `[INST] ${content} [/INST]`;
        } else {
          s += ` ${t.content}</s>`;
        }
      }
      return s;
    }
    case 'chatml':
    default: {
      let s = '';
      if (system) s += `<|im_start|>system\n${system.content}<|im_end|>\n`;
      for (const t of body) s += `<|im_start|>${t.role}\n${t.content}<|im_end|>\n`;
      s += '<|im_start|>assistant\n';
      // A pre-closed reasoning block is the documented way to get a direct answer
      // out of a thinking model instead of spending the budget deliberating.
      if (opts.suppressThinking) s += '<think>\n\n</think>\n\n';
      return s;
    }
  }
}

/**
 * True when `prompt` already carries turn markup the llama.cpp backend
 * recognises and will therefore pass through without re-wrapping.
 *
 * NOTE: the backend does NOT currently detect Gemma's `<start_of_turn>`, so a
 * Gemma-formatted prompt is re-wrapped unless the engine is updated to match.
 */
export function hasTurnMarkup(prompt: string): boolean {
  return (
    prompt.includes('<|im_start|>') ||
    prompt.includes('<|begin_of_text|>') ||
    prompt.includes('[INST]') ||
    prompt.includes('<start_of_turn>')
  );
}
