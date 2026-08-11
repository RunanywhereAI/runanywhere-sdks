/**
 * Built-in demo tools for the Tools workbench (and Settings' Tools tab later).
 *
 * Every executor answers from something this machine actually knows — clock,
 * runtime, battery, arithmetic — so a successful call is never fabricated.
 * Commons owns the tool loop; the app only registers executors once.
 */
import type { ToolDefinition } from '@runanywhere/electron';

import { evalArithmetic } from './arithmetic';

interface DemoTool {
  readonly definition: ToolDefinition;
  readonly execute: (args: Record<string, unknown>) => Promise<Record<string, unknown>> | Record<string, unknown>;
}

/** Battery Status API is Chromium-only and not in lib.dom yet for every target. */
interface BatteryManager {
  readonly level: number;
  readonly charging: boolean;
}

interface NavigatorWithBattery extends Navigator {
  getBattery?(): Promise<BatteryManager>;
}

const DEMO_TOOLS: readonly DemoTool[] = [
  {
    definition: {
      name: 'get_current_time',
      description: 'Returns the current date, time and timezone on the device.',
      parameters: { type: 'object', properties: {}, required: [] },
    },
    execute: () => {
      const now = new Date();
      return {
        datetime: now.toLocaleString(),
        iso8601: now.toISOString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    },
  },
  {
    definition: {
      name: 'get_device_info',
      description: 'Returns details about the device: platform, browser engine and CPU cores.',
      parameters: { type: 'object', properties: {}, required: [] },
    },
    execute: () => ({
      platform: navigator.platform,
      user_agent: navigator.userAgent,
      language: navigator.language,
      cpu_cores: navigator.hardwareConcurrency,
    }),
  },
  {
    definition: {
      name: 'get_battery_level',
      description: 'Returns the current battery charge level as a percentage.',
      parameters: { type: 'object', properties: {}, required: [] },
    },
    execute: async () => {
      try {
        const getBattery = (navigator as NavigatorWithBattery).getBattery;
        if (getBattery === undefined) return { battery_percent: 'unknown' };
        const battery = await getBattery.call(navigator);
        return {
          battery_percent: `${Math.round(battery.level * 100)}%`,
          charging: battery.charging,
        };
      } catch {
        return { battery_percent: 'unknown' };
      }
    },
  },
  {
    definition: {
      name: 'calculate',
      description: "Evaluates a math expression with + - * / and parentheses, e.g. '(3 + 4) * 2'.",
      parameters: {
        type: 'object',
        properties: {
          expression: {
            type: 'string',
            description: "The expression to evaluate, e.g. '(3 + 4) * 2'.",
          },
        },
        required: ['expression'],
      },
    },
    execute: ({ expression }) => {
      const src = String(expression ?? '');
      if (!/^[\d\s+\-*/().%]+$/.test(src)) {
        return { error: 'unsupported expression (digits and + - * / ( ) only)' };
      }
      try {
        return { result: String(evalArithmetic(src)) };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return { error: `could not evaluate '${src}': ${message}` };
      }
    },
  },
];

let registered = false;

/** Register the four demo tools once. Idempotent. */
export function registerDemoTools(): void {
  if (registered) return;
  for (const tool of DEMO_TOOLS) {
    window.runanywhere.llm.tools.register(tool.definition, (args) => tool.execute(args ?? {}));
  }
  registered = true;
}

export function demoToolNames(): readonly string[] {
  return DEMO_TOOLS.map((tool) => tool.definition.name);
}
