/**
 * Vision Executor
 *
 * Alternative executor that uses screenshot-based navigation via VLM.
 * Uses VisionNavigator instead of NavigatorAgent for action decisions.
 */

import { PlannerAgent } from './planner-agent';
import { VisionNavigatorAgent } from './vision-navigator';
import { llmEngine } from '../llm-engine';
import { visionEngine } from '../vision-engine';
import type {
  AgentContext,
  VisionState,
  ActionResult,
  AgentStep,
  ExecutorEvent,
} from '../../shared/types';
import { MAX_STEPS, MAX_REPLANS } from '../../shared/constants';

// ============================================================================
// Types
// ============================================================================

type ExecuteActionFn = (actionType: string, params: Record<string, string>) => Promise<ActionResult>;
type GetTabInfoFn = () => Promise<{ url: string; title: string }>;
type EventListener = (event: ExecutorEvent) => void;

// ============================================================================
// Vision Executor
// ============================================================================

export class VisionExecutor {
  private planner = new PlannerAgent();
  private navigator = new VisionNavigatorAgent();
  private context: AgentContext | null = null;
  private eventListeners: Set<EventListener> = new Set();
  private isRunning = false;
  private shouldCancel = false;

  /**
   * Execute a task using vision-based navigation
   */
  async executeTask(
    task: string,
    getTabInfo: GetTabInfoFn,
    executeAction: ExecuteActionFn,
    tabId?: number
  ): Promise<string> {
    if (this.isRunning) {
      throw new Error('VisionExecutor is already running a task');
    }

    this.isRunning = true;
    this.shouldCancel = false;

    try {
      // Phase 1: Initialize LLM
      this.emit({ type: 'INIT_START' });

      const llmUnsubscribe = llmEngine.onProgress((progress) => {
        this.emit({ type: 'INIT_PROGRESS', progress: progress * 0.5 }); // LLM is first 50%
      });

      try {
        await llmEngine.initialize();
        llmUnsubscribe();
        this.emit({ type: 'INIT_COMPLETE' });
      } catch (error) {
        llmUnsubscribe();
        const errorMsg = error instanceof Error ? error.message : String(error);
        this.emit({ type: 'TASK_FAILED', error: `LLM initialization failed: ${errorMsg}` });
        throw error;
      }

      // Phase 1.5: Initialize VLM
      this.emit({ type: 'VLM_INIT_START' });

      const vlmUnsubscribe = visionEngine.onProgress((progress) => {
        this.emit({ type: 'VLM_INIT_PROGRESS', progress });
      });

      try {
        await visionEngine.initialize('tiny'); // Use smallest model for speed
        vlmUnsubscribe();
        this.emit({ type: 'VLM_INIT_COMPLETE' });
      } catch (error) {
        vlmUnsubscribe();
        const errorMsg = error instanceof Error ? error.message : String(error);
        this.emit({ type: 'TASK_FAILED', error: `VLM initialization failed: ${errorMsg}` });
        throw error;
      }

      // Phase 2: Create plan
      this.context = {
        task,
        history: [],
      };

      this.emit({ type: 'PLAN_START' });

      try {
        this.context.plan = await this.planner.createPlan(task);

        const steps = this.context.plan?.plan?.steps;
        if (!steps || !Array.isArray(steps) || steps.length === 0) {
          console.warn('[VisionExecutor] Plan missing steps, using fallback');
          this.context.plan = {
            current_state: {
              analysis: 'Task analysis',
              memory: [],
            },
            plan: {
              thought: 'Executing task directly',
              steps: ['Analyze the current page visually', 'Complete the requested task'],
              success_criteria: 'Task completed successfully',
            },
          };
        }

        this.emit({ type: 'PLAN_COMPLETE', plan: this.context.plan.plan.steps });
        console.log('[VisionExecutor] Plan created:', this.context.plan.plan.steps);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        this.emit({ type: 'TASK_FAILED', error: `Planning failed: ${errorMsg}` });
        throw error;
      }

      // Phase 3: Vision-based execution loop
      let replans = 0;
      let consecutiveFailures = 0;

      for (let step = 0; step < MAX_STEPS; step++) {
        if (this.shouldCancel) {
          throw new Error('Task cancelled by user');
        }

        this.emit({ type: 'STEP_START', stepNumber: step + 1 });

        // Capture screenshot and analyze with VLM
        let visionState: VisionState;
        try {
          const tabInfo = await getTabInfo();

          this.emit({ type: 'SCREENSHOT_CAPTURED' });
          const screenshot = await visionEngine.captureScreenshot(tabId);

          const currentStep = this.context.plan?.plan?.steps[0] || 'Complete the task';
          const analysis = await visionEngine.analyzeForAction(screenshot, task, currentStep);
          this.emit({ type: 'VISION_ANALYSIS_COMPLETE' });

          visionState = {
            url: tabInfo.url,
            title: tabInfo.title,
            screenshot,
            visionAnalysis: analysis,
          };

          console.log('[VisionExecutor] Vision analysis:', analysis.slice(0, 200));
        } catch (error) {
          const errorMsg = error instanceof Error ? error.message : String(error);
          console.error('[VisionExecutor] Failed to get vision state:', errorMsg);

          // Try to continue with minimal state
          const tabInfo = await getTabInfo().catch(() => ({ url: 'unknown', title: 'Error' }));
          visionState = {
            url: tabInfo.url,
            title: tabInfo.title,
            screenshot: '',
            visionAnalysis: 'Failed to analyze page visually. Proceeding based on previous context.',
          };
        }

        // Get next action from vision navigator
        let action;
        try {
          action = await this.navigator.getNextAction(this.context, visionState);
        } catch (error) {
          const errorMsg = error instanceof Error ? error.message : String(error);
          console.error('[VisionExecutor] Navigator error:', errorMsg);

          if (replans < MAX_REPLANS) {
            replans++;
            this.emit({ type: 'REPLAN', reason: `Navigator error: ${errorMsg}` });
            this.navigator.reset();
            this.context.plan = await this.planner.replan(this.context, errorMsg);
            this.emit({ type: 'PLAN_COMPLETE', plan: this.context.plan.plan.steps });
            continue;
          }

          this.emit({ type: 'TASK_FAILED', error: `Navigator error: ${errorMsg}` });
          throw error;
        }

        this.emit({
          type: 'STEP_ACTION',
          action: action.action.action_type,
          params: action.action.parameters,
        });

        console.log(
          `[VisionExecutor] Step ${step + 1}: ${action.action.action_type}`,
          action.action.parameters
        );

        // Handle terminal actions
        if (action.action.action_type === 'done') {
          const result = action.action.parameters.result || 'Task completed successfully';
          this.emit({ type: 'TASK_COMPLETE', result });
          return result;
        }

        if (action.action.action_type === 'fail') {
          const reason = action.action.parameters.reason || 'Unknown failure';

          if (replans < MAX_REPLANS) {
            replans++;
            this.emit({ type: 'REPLAN', reason });
            this.navigator.reset();
            this.context.plan = await this.planner.replan(this.context, reason);
            this.emit({ type: 'PLAN_COMPLETE', plan: this.context.plan.plan.steps });
            consecutiveFailures = 0;
            continue;
          }

          this.emit({ type: 'TASK_FAILED', error: reason });
          throw new Error(reason);
        }

        // Execute the action
        let result: ActionResult;
        try {
          result = await executeAction(action.action.action_type, action.action.parameters);
        } catch (error) {
          result = {
            success: false,
            error: error instanceof Error ? error.message : String(error),
          };
        }

        this.emit({
          type: 'STEP_RESULT',
          success: result.success,
          data: result.data,
        });

        console.log(`[VisionExecutor] Action result:`, result);

        // Record in history
        const historyEntry: AgentStep = {
          action: action.action,
          result,
          timestamp: Date.now(),
        };
        this.context.history.push(historyEntry);

        // Handle action failure
        if (!result.success) {
          consecutiveFailures++;

          if (consecutiveFailures >= 3 && replans < MAX_REPLANS) {
            replans++;
            this.emit({ type: 'REPLAN', reason: result.error || 'Multiple consecutive failures' });
            this.navigator.reset();
            this.context.plan = await this.planner.replan(
              this.context,
              result.error || 'Multiple action failures'
            );
            this.emit({ type: 'PLAN_COMPLETE', plan: this.context.plan.plan.steps });
            consecutiveFailures = 0;
          }
        } else {
          consecutiveFailures = 0;
        }

        // Small delay between steps to allow page to update
        await new Promise((resolve) => setTimeout(resolve, 500));
      }

      // Max steps exceeded
      const error = `Maximum steps (${MAX_STEPS}) exceeded without completing task`;
      this.emit({ type: 'TASK_FAILED', error });
      throw new Error(error);
    } finally {
      this.isRunning = false;
      this.reset();
    }
  }

  /**
   * Cancel the currently running task
   */
  cancel(): void {
    this.shouldCancel = true;
  }

  /**
   * Subscribe to executor events
   */
  onEvent(listener: EventListener): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  private emit(event: ExecutorEvent): void {
    console.log('[VisionExecutor] Event:', event.type);
    this.eventListeners.forEach((listener) => {
      try {
        listener(event);
      } catch (e) {
        console.error('[VisionExecutor] Event listener error:', e);
      }
    });
  }

  /**
   * Reset executor state
   */
  reset(): void {
    this.planner.reset();
    this.navigator.reset();
    this.context = null;
  }
}

// Export singleton instance
export const visionExecutor = new VisionExecutor();
