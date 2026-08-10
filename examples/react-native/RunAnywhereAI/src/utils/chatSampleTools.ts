/**
 * chatSampleTools - Shared demo tool definitions for the RunAnywhere RN example.
 *
 * Registration is owned exclusively by SettingsScreen (Tool Settings section),
 * matching iOS ToolSettingsView and Android/Flutter ToolSettingsViewModel.
 * ChatScreen only reads the registered tool count via RunAnywhere.llm.tools.list().
 */

import { RunAnywhere } from '@runanywhere/core';
import { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import { safeEvaluateExpression } from './mathParser';

/**
 * `ToolParameter`/`ToolParameterType` (the proto types) were deleted outright
 * (idl/tool_calling.proto): `ToolDefinition.parameters` is now a single raw
 * JSON Schema object STRING — the same OpenAI `parameters` / Anthropic
 * `input_schema` / MCP `inputSchema` shape every tool-calling API publishes.
 * Mirrors the Swift `ToolParameter.schemaProperty`/`jsonSchema(for:)` helpers
 * (sdk/runanywhere-swift/.../ToolCallingTypes.swift) and Kotlin's equivalent,
 * neither of which the React Native SDK currently exposes — build the schema
 * string directly here.
 */
function jsonSchema(
  parameters: ReadonlyArray<{
    name: string;
    type: 'string' | 'number' | 'integer' | 'boolean' | 'array' | 'object';
    description: string;
    required?: boolean;
  }>
): string {
  if (parameters.length === 0) return '{}';
  const properties: Record<string, { type: string; description: string }> =
    {};
  const required: string[] = [];
  for (const param of parameters) {
    properties[param.name] = {
      type: param.type,
      description: param.description,
    };
    if (param.required ?? true) required.push(param.name);
  }
  return JSON.stringify({
    type: 'object',
    properties,
    ...(required.length > 0 ? { required } : {}),
  });
}

/**
 * Property names declared on a `ToolDefinition.parameters` JSON Schema
 * string, for display (e.g. SettingsScreen's per-tool parameter chips).
 * Tolerates "", "{}", or malformed JSON by returning no names.
 */
export function toolParameterNames(parametersSchema: string): string[] {
  if (!parametersSchema) return [];
  try {
    const parsed = JSON.parse(parametersSchema) as {
      properties?: Record<string, unknown>;
    };
    return Object.keys(parsed.properties ?? {});
  } catch {
    return [];
  }
}

/**
 * Register the three demo tools (weather, time, calculator).
 * Clears any pre-existing tools before registering.
 * Called only from SettingsScreen when the user taps "Add Demo Tools".
 */
export const registerDemoTools = async (): Promise<void> => {
  await RunAnywhere.llm.tools.clear();

  // Weather tool - Real API (wttr.in - no key needed)
  await RunAnywhere.llm.tools.register(
    ToolDefinition.fromPartial({
      name: 'get_weather',
      description: 'Gets the current weather for a city or location',
      parameters: jsonSchema([
        {
          name: 'location',
          type: 'string',
          description:
            'City name or location (e.g., "Tokyo", "New York", "London")',
          required: true,
        },
      ]),
    }),
    async (args) => {
      const location = String(args.location ?? 'San Francisco');
      try {
        // SAMPLE_HTTP_CARVE_OUT: external weather-tool demo call, not SDK auth/download traffic.
        const response = await fetch(
          `https://wttr.in/${encodeURIComponent(location)}?format=j1`
        );
        const data = await response.json();
        const current = data.current_condition?.[0];
        return {
          location,
          temperature_c: current?.temp_C || 'N/A',
          temperature_f: current?.temp_F || 'N/A',
          condition: current?.weatherDesc?.[0]?.value || 'Unknown',
          humidity: current?.humidity || 'N/A',
          wind_kph: current?.windspeedKmph || 'N/A',
        };
      } catch (error) {
        return { error: `Failed to get weather: ${error}` };
      }
    }
  );

  // Current time tool
  await RunAnywhere.llm.tools.register(
    ToolDefinition.fromPartial({
      name: 'get_current_time',
      description: 'Gets the current date, time, and timezone information',
      parameters: jsonSchema([]),
    }),
    async () => {
      const now = new Date();
      return {
        datetime: now.toLocaleString(),
        time: now.toLocaleTimeString(),
        timestamp: now.toISOString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    }
  );

  // Calculator tool - Math evaluation
  await RunAnywhere.llm.tools.register(
    ToolDefinition.fromPartial({
      name: 'calculate',
      description:
        'Performs math calculations. Supports +, -, *, /, and parentheses',
      parameters: jsonSchema([
        {
          name: 'expression',
          type: 'string',
          description: 'Math expression (e.g., "2 + 2 * 3", "(10 + 5) / 3")',
          required: true,
        },
      ]),
    }),
    async (args) => {
      const expression = String(args.expression ?? '0');
      try {
        return { expression, result: safeEvaluateExpression(expression) };
      } catch (error) {
        return { error: `Failed to calculate: ${error}` };
      }
    }
  );
};
