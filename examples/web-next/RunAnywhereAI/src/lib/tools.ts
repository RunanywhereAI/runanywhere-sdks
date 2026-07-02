import { ToolDefinition, ToolParameter, ToolParameterType } from '@runanywhere/proto-ts/tool_calling';
import type { HostTool } from '@runanywhere/web';

const STRING = ToolParameterType.TOOL_PARAMETER_TYPE_STRING;

function stringParam(name: string, description: string, required = true): ToolParameter {
  return ToolParameter.fromPartial({ name, type: STRING, description, required });
}

function evalArithmetic(expression: string): number {
  const cleaned = expression.replace(/\s+/g, '');
  if (!/^[0-9+\-*/().%]+$/.test(cleaned)) {
    throw new Error('expression may only contain numbers and + - * / ( ) % .');
  }
  const value = Function(`"use strict"; return (${cleaned});`)() as unknown;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('expression did not evaluate to a number');
  return value;
}

const WEATHER_CODES: Record<number, string> = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast',
  45: 'fog', 48: 'rime fog', 51: 'light drizzle', 53: 'drizzle', 55: 'dense drizzle',
  61: 'light rain', 63: 'rain', 65: 'heavy rain', 71: 'light snow', 73: 'snow', 75: 'heavy snow',
  80: 'rain showers', 81: 'rain showers', 82: 'violent rain showers', 95: 'thunderstorm',
};

async function fetchJson(url: string): Promise<Record<string, unknown>> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return (await response.json()) as Record<string, unknown>;
}

export const tools: HostTool[] = [
  {
    definition: ToolDefinition.fromPartial({
      name: 'get_current_time',
      description: 'Get the current local date and time.',
      parameters: [],
    }),
    execute() {
      const now = new Date();
      return {
        iso: now.toISOString(),
        local: now.toLocaleString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    },
  },
  {
    definition: ToolDefinition.fromPartial({
      name: 'calculate',
      description: 'Evaluate a basic arithmetic expression (supports + - * / % and parentheses).',
      parameters: [stringParam('expression', 'The arithmetic expression to evaluate, e.g. "0.15 * 240".')],
    }),
    execute(args) {
      const result = evalArithmetic(String(args.expression ?? ''));
      return { result };
    },
  },
  {
    definition: ToolDefinition.fromPartial({
      name: 'get_weather',
      description: 'Get the current weather for a city or place name.',
      parameters: [stringParam('location', 'City or place name, e.g. "Tokyo".')],
    }),
    async execute(args) {
      const location = String(args.location ?? '').trim();
      if (!location) throw new Error('location is required');
      const geo = await fetchJson(
        `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1`,
      );
      const place = (geo.results as Array<Record<string, unknown>> | undefined)?.[0];
      if (!place) throw new Error(`could not find location "${location}"`);
      const lat = place.latitude as number;
      const lon = place.longitude as number;
      const forecast = await fetchJson(
        `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code`,
      );
      const current = forecast.current as Record<string, unknown> | undefined;
      const code = Number(current?.weather_code ?? -1);
      return {
        location: `${place.name ?? location}${place.country ? `, ${place.country}` : ''}`,
        temperature_c: current?.temperature_2m ?? null,
        conditions: WEATHER_CODES[code] ?? 'unknown',
      };
    },
  },
  {
    definition: ToolDefinition.fromPartial({
      name: 'get_battery',
      description: "Get the device's current battery level and charging status.",
      parameters: [],
    }),
    async execute() {
      const nav = navigator as Navigator & { getBattery?: () => Promise<{ level: number; charging: boolean }> };
      if (!nav.getBattery) throw new Error('battery status is not available in this browser');
      const battery = await nav.getBattery();
      return { level_percent: Math.round(battery.level * 100), charging: battery.charging };
    },
  },
];
