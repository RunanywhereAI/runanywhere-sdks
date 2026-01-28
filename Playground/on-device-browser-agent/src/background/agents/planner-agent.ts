/**
 * Planner Agent
 *
 * Strategic planning agent that analyzes tasks and creates high-level execution plans.
 * The planner considers:
 * - Task requirements and constraints
 * - Common web navigation patterns
 * - Success criteria for task completion
 */

import { BaseAgent } from './base-agent';
import type { PlannerOutput, AgentContext } from '../../shared/types';

// ============================================================================
// Planner Agent
// ============================================================================

export class PlannerAgent extends BaseAgent<PlannerOutput> {
  protected systemPrompt = `You are a web automation planner. Create step-by-step plans for browser tasks.

Example plans:
- AMAZON SHOPPING: 1) Navigate to amazon.com 2) Type search query 3) Press enter 4) Click first product 5) Click Add to Cart 6) Done
- GOOGLE SEARCH: 1) Navigate to google.com 2) Type search query 3) Press enter 4) Click result 5) Done

Create 3-6 clear steps. Be specific about what to click/type.`;

  protected outputSchema = `{"current_state":{"analysis":"User wants to buy toilet paper from Amazon","memory":["Need to search Amazon","Add item to cart"]},"plan":{"thought":"Standard Amazon shopping flow","steps":["Navigate to amazon.com","Type toilet paper in search box","Press enter to search","Click first product result","Click Add to Cart button","Report success"],"success_criteria":"Item added to cart"}}`;

  constructor() {
    super('Planner');
  }

  /**
   * Create an initial plan for a new task
   */
  async createPlan(task: string): Promise<PlannerOutput> {
    const prompt = `Create a plan for the following web automation task:

TASK: ${task}

Analyze this task and provide a strategic plan with clear steps.
Consider what web pages you'll need to visit and what actions you'll need to take.`;

    return this.invoke(prompt);
  }

  /**
   * Create a revised plan after the previous approach failed
   */
  async replan(context: AgentContext, failureReason: string): Promise<PlannerOutput> {
    // Build history summary
    const historyStr =
      context.history.length > 0
        ? context.history
            .map(
              (h, i) =>
                `Step ${i + 1}: ${h.action.action_type}(${JSON.stringify(h.action.parameters)}) -> ${
                  h.result.success ? 'SUCCESS' : 'FAILED: ' + h.result.error
                }`
            )
            .join('\n')
        : 'No actions were taken yet.';

    // Build previous plan summary
    const prevPlanStr = context.plan
      ? `Previous Plan:\n${context.plan.plan.steps.map((s, i) => `${i + 1}. ${s}`).join('\n')}`
      : 'No previous plan.';

    const prompt = `The previous plan encountered an issue. Please create a revised plan.

ORIGINAL TASK: ${context.task}

${prevPlanStr}

ACTIONS TAKEN:
${historyStr}

FAILURE REASON: ${failureReason}

Create a new plan that:
1. Addresses the issue that caused the failure
2. Builds on any progress made so far
3. Uses an alternative approach if the original one is blocked`;

    // Clear history for fresh planning
    this.reset();
    return this.invoke(prompt);
  }
}
