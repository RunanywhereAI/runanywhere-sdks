/**
 * Vision Navigator Agent
 *
 * Alternative navigator that uses screenshot-based page understanding via VLM.
 * Instead of parsing the DOM, it analyzes screenshots to identify elements
 * and determine the next action.
 */

import { BaseAgent } from './base-agent';
import type { NavigatorOutput, AgentContext, VisionState } from '../../shared/types';

// ============================================================================
// Vision Navigator Agent
// ============================================================================

export class VisionNavigatorAgent extends BaseAgent<NavigatorOutput> {
  protected systemPrompt = `You are a tactical web navigation agent that executes browser actions based on visual analysis.

Your role is to:
1. Understand the page from the visual description provided
2. Choose the next best action to progress toward the goal
3. Describe elements by their visual position and labels

AVAILABLE ACTIONS:
- navigate: Go to a URL
  Parameters: {"url": "https://example.com"}

- click: Click an element (describe by text/position)
  Parameters: {"selector": "text:Search", "description": "Click the Search button"}

- type: Type text into an input field
  Parameters: {"selector": "input:search", "text": "query", "description": "Type in the search box"}

- extract: Extract information from the page
  Parameters: {"selector": "visible", "description": "What to extract"}

- scroll: Scroll the page
  Parameters: {"direction": "down", "amount": "500"}

- wait: Wait for the page to change
  Parameters: {"timeout": "2000"}

- done: Task is complete
  Parameters: {"result": "The extracted information or confirmation of completion"}

- fail: Cannot continue with task
  Parameters: {"reason": "Explanation of why the task cannot be completed"}

GUIDELINES FOR SELECTORS:
- Use "text:Label" to click elements by their visible text (e.g., "text:Sign In")
- Use "input:name" to target input fields by their placeholder/label (e.g., "input:email")
- Use "link:text" to click links by their text (e.g., "link:Learn More")
- Use position hints like "first", "second" when multiple similar elements exist
- The content script will interpret these semantic selectors

GUIDELINES:
- Focus on the visual description to understand page state
- Describe elements by what you SEE (labels, positions, colors)
- If an element isn't visible, try scrolling first
- Call "done" with the result when you have achieved the task goal
- Call "fail" when the task cannot be completed`;

  protected outputSchema = `{
  "current_state": {
    "page_summary": "string - What you see on the current page",
    "relevant_elements": ["string - Elements you've identified that are relevant"],
    "progress": "string - Progress toward completing the task"
  },
  "action": {
    "thought": "string - Your reasoning for choosing this action",
    "action_type": "navigate | click | type | extract | scroll | wait | done | fail",
    "parameters": {
      "key": "value - Parameters for the action",
      "description": "string - Human-readable description of what to do"
    }
  }
}`;

  constructor() {
    super('VisionNavigator');
  }

  /**
   * Get the next action based on visual analysis of the page
   */
  async getNextAction(context: AgentContext, visionState: VisionState): Promise<NavigatorOutput> {
    // Format the plan if available
    const planStr = context.plan
      ? `CURRENT PLAN:
${context.plan.plan.steps.map((s, i) => `${i + 1}. ${s}`).join('\n')}

Success Criteria: ${context.plan.plan.success_criteria}`
      : 'No plan available - proceed based on the task.';

    // Format recent action history
    const historyStr =
      context.history.length > 0
        ? `RECENT ACTIONS:
${context.history
  .slice(-5)
  .map(
    (h) =>
      `- ${h.action.action_type}(${h.action.parameters.description || JSON.stringify(h.action.parameters)}) -> ${
        h.result.success ? 'OK' + (h.result.data ? ': ' + h.result.data.slice(0, 100) : '') : 'FAILED: ' + h.result.error
      }`
  )
  .join('\n')}`
        : 'No actions taken yet.';

    const prompt = `TASK: ${context.task}

${planStr}

${historyStr}

CURRENT PAGE STATE:
URL: ${visionState.url}
Title: ${visionState.title}

VISUAL ANALYSIS OF PAGE:
${visionState.visionAnalysis}

Based on what you can see in the visual analysis, determine the next action to take.
Use semantic selectors (text:, input:, link:) to identify elements by their visible labels.
If you have achieved the goal, use the "done" action with the result.`;

    return this.invoke(prompt);
  }
}
