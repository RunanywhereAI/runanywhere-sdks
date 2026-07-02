import {
  IconBattery,
  IconBook,
  IconBulb,
  IconCalculator,
  IconClock,
  IconCloud,
  IconPencil,
  IconSparkles,
} from '@tabler/icons-svelte';
import type { IconComponent } from './icon';

export interface PromptSuggestion {
  label: string;
  prompt: string;
  icon: IconComponent;
}

export const generalSuggestions: PromptSuggestion[] = [
  { label: 'Explain LLMs', prompt: 'Explain how large language models work, in simple terms.', icon: IconBulb },
  { label: 'Write a poem', prompt: 'Write a short poem about the ocean at night.', icon: IconPencil },
  { label: 'Summarize a story', prompt: 'Summarize Romeo and Juliet in three sentences.', icon: IconBook },
  { label: 'Name ideas', prompt: 'Give me five creative names for a coffee shop.', icon: IconSparkles },
];

export const toolSuggestions: PromptSuggestion[] = [
  { label: 'Weather in Tokyo', prompt: "What's the weather in Tokyo right now?", icon: IconCloud },
  { label: 'Current time', prompt: 'What time is it right now?', icon: IconClock },
  { label: 'Battery level', prompt: "What's my battery level?", icon: IconBattery },
  { label: 'Quick math', prompt: 'What is 15% of 240?', icon: IconCalculator },
];
