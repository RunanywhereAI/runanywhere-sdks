/**
 * Single registry of every navigable route. One flat graph: the 3-tab bar is the
 * only container; every other screen is a direct sibling route on the root stack,
 * reachable in one navigate() call. Modals share the same stack via a presentation
 * group. Route names are referenced through ROUTES — never as string literals.
 */
export const ROUTES = {
  // Root container for the bottom tab bar.
  Tabs: 'Tabs',

  // Bottom-tab routes.
  Chat: 'Chat',
  Voice: 'Voice',
  More: 'More',

  // Feature screens — flat siblings on the root stack (index 1, directly navigable).
  Vision: 'Vision',
  Vlm: 'Vlm',
  Transcribe: 'Transcribe',
  Speak: 'Speak',
  Vad: 'Vad',
  Rag: 'Rag',
  Storage: 'Storage',
  Solutions: 'Solutions',
  Benchmarks: 'Benchmarks',
  Settings: 'Settings',

  // Modal routes (presentation group, same root stack).
  ModelSelection: 'ModelSelection',
  Lora: 'Lora',
  ConversationList: 'ConversationList',
  ChatAnalytics: 'ChatAnalytics',
} as const;

export type RouteName = (typeof ROUTES)[keyof typeof ROUTES];
