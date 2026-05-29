/**
 * chatSampleTools - Shared demo tool definitions for the RunAnywhere RN example.
 *
 * Registration is owned exclusively by SettingsScreen (Tool Settings section),
 * matching iOS ToolSettingsView and Android/Flutter ToolSettingsViewModel.
 * ChatScreen only reads the registered tool count via RunAnywhere.getRegisteredTools().
 */

import { RunAnywhere } from '@runanywhere/core';
import {
  ToolDefinition,
  ToolParameterType,
  type ToolValue,
} from '@runanywhere/proto-ts/tool_calling';
import { safeEvaluateExpression } from './mathParser';

/**
 * Register the three demo tools (weather, time, calculator).
 * Clears any pre-existing tools before registering.
 * Called only from SettingsScreen when the user taps "Add Demo Tools".
 */
export const registerDemoTools = async (): Promise<void> => {
  await RunAnywhere.clearTools();

  // Weather tool - Real API (wttr.in - no key needed)
  await RunAnywhere.registerTool(
    ToolDefinition.fromPartial({
      name: 'get_weather',
      description: 'Gets the current weather for a city or location',
      parameters: [
        {
          name: 'location',
          type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
          description:
            'City name or location (e.g., "Tokyo", "New York", "London")',
          required: true,
          enumValues: [],
        },
      ],
    }),
    async (args: Record<string, ToolValue>): Promise<Record<string, ToolValue>> => {
      const location = args.location?.stringValue || 'San Francisco';
      try {
        // SAMPLE_HTTP_CARVE_OUT: external weather-tool demo call, not SDK auth/download traffic.
        const response = await fetch(
          `https://wttr.in/${encodeURIComponent(location)}?format=j1`
        );
        const data = await response.json();
        const current = data.current_condition?.[0];
        return {
          location: { stringValue: location },
          temperature_c: { stringValue: current?.temp_C || 'N/A' },
          temperature_f: { stringValue: current?.temp_F || 'N/A' },
          condition: { stringValue: current?.weatherDesc?.[0]?.value || 'Unknown' },
          humidity: { stringValue: current?.humidity || 'N/A' },
          wind_kph: { stringValue: current?.windspeedKmph || 'N/A' },
        };
      } catch (error) {
        return { error: { stringValue: `Failed to get weather: ${error}` } };
      }
    }
  );

  // Current time tool
  await RunAnywhere.registerTool(
    ToolDefinition.fromPartial({
      name: 'get_current_time',
      description: 'Gets the current date, time, and timezone information',
      parameters: [],
    }),
    async (): Promise<Record<string, ToolValue>> => {
      const now = new Date();
      return {
        datetime: { stringValue: now.toLocaleString() },
        time: { stringValue: now.toLocaleTimeString() },
        timestamp: { stringValue: now.toISOString() },
        timezone: { stringValue: Intl.DateTimeFormat().resolvedOptions().timeZone },
      };
    }
  );

  // Calculator tool - Math evaluation
  await RunAnywhere.registerTool(
    ToolDefinition.fromPartial({
      name: 'calculate',
      description:
        'Performs math calculations. Supports +, -, *, /, and parentheses',
      parameters: [
        {
          name: 'expression',
          type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
          description: 'Math expression (e.g., "2 + 2 * 3", "(10 + 5) / 3")',
          required: true,
          enumValues: [],
        },
      ],
    }),
    async (args: Record<string, ToolValue>): Promise<Record<string, ToolValue>> => {
      const expression = args.expression?.stringValue || '0';
      try {
        const result = safeEvaluateExpression(expression);
        return {
          expression: { stringValue: expression },
          result: { numberValue: result },
        };
      } catch (error) {
        return { error: { stringValue: `Failed to calculate: ${error}` } };
      }
    }
  );
};
