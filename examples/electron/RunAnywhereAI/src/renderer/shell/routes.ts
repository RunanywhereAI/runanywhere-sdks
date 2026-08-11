/**
 * Where the detail column can go.
 *
 * The macOS shell has exactly **three** destinations — chat, models, advanced
 * (ContentView.swift:120-126). Everything else the app can do is reached through
 * the Advanced hub, which is why those are routes but not sidebar rows.
 */
import type { IconName } from '../components/icons';

/** The three sidebar destinations, plus the hub's screens. */
export const Route = {
  Chat: 'chat',
  Models: 'models',
  Advanced: 'advanced',
  // Reached from the Advanced hub, mirroring ConsumerAdvancedHubView's grid.
  Voice: 'voice',
  Transcribe: 'transcribe',
  Speak: 'speak',
  Vad: 'vad',
  Diarization: 'diarization',
  Vision: 'vision',
  Segmentation: 'segmentation',
  Knowledge: 'knowledge',
  Embeddings: 'embeddings',
  Structured: 'structured',
  Tools: 'tools',
  Benchmarks: 'benchmarks',
  Storage: 'storage',
} as const;

export type Route = (typeof Route)[keyof typeof Route];

/** Which sidebar row owns a route, so exactly one row highlights per screen. */
export type Scope = 'chat' | 'models' | 'advanced';

export function scopeOf(route: Route): Scope {
  switch (route) {
    case Route.Chat:
      return 'chat';
    case Route.Models:
      return 'models';
    default:
      // Every hub screen keeps Advanced highlighted; the user got there from it.
      return 'advanced';
  }
}

export interface RouteMeta {
  readonly route: Route;
  readonly title: string;
  /** Shown under the title in the unified toolbar. */
  readonly subtitle: string;
  readonly icon: IconName;
}

/** The three sidebar destinations, in order (MacSidebar.swift:121-131). */
export const SIDEBAR_ROUTES: readonly RouteMeta[] = [
  {
    route: Route.Chat,
    title: 'Chat',
    subtitle: 'Ask anything — everything runs privately on your device.',
    icon: 'bubble.left.and.bubble.right',
  },
  {
    route: Route.Models,
    title: 'Models',
    subtitle: 'Download, load, and manage models. Nothing leaves your machine.',
    icon: 'square.stack.3d.up',
  },
  {
    route: Route.Advanced,
    title: 'Advanced',
    subtitle: 'Every on-device capability, one screen each.',
    icon: 'slider.horizontal.3',
  },
];

/** Metadata for every route, including the hub screens. */
export const ROUTE_META: Readonly<Record<Route, RouteMeta>> = {
  [Route.Chat]: SIDEBAR_ROUTES[0] as RouteMeta,
  [Route.Models]: SIDEBAR_ROUTES[1] as RouteMeta,
  [Route.Advanced]: SIDEBAR_ROUTES[2] as RouteMeta,
  [Route.Voice]: {
    route: Route.Voice,
    title: 'Voice',
    subtitle: 'Speech, reasoning and speech-synthesis, all on this device.',
    icon: 'waveform',
  },
  [Route.Transcribe]: {
    route: Route.Transcribe,
    title: 'Transcribe',
    subtitle: 'Speech to text from the microphone or a file.',
    icon: 'mic',
  },
  [Route.Speak]: {
    route: Route.Speak,
    title: 'Speak',
    subtitle: 'Text to speech with on-device voices.',
    icon: 'speaker.wave.2',
  },
  [Route.Vad]: {
    route: Route.Vad,
    title: 'Voice activity',
    subtitle: 'Detect speech and silence as you talk.',
    icon: 'waveform',
  },
  [Route.Diarization]: {
    route: Route.Diarization,
    title: 'Diarization',
    subtitle: 'Label who spoke when, up to four speakers.',
    icon: 'person.2.wave.2',
  },
  [Route.Vision]: {
    route: Route.Vision,
    title: 'Vision',
    subtitle: 'Describe and reason about an image.',
    icon: 'photo',
  },
  [Route.Segmentation]: {
    route: Route.Segmentation,
    title: 'Segmentation',
    subtitle: 'Split an image into semantic regions.',
    icon: 'square.dashed',
  },
  [Route.Knowledge]: {
    route: Route.Knowledge,
    title: 'Knowledge',
    subtitle: 'Add documents, then ask questions answered only from them.',
    icon: 'doc.text',
  },
  [Route.Embeddings]: {
    route: Route.Embeddings,
    title: 'Embeddings',
    subtitle: 'Semantic similarity between two texts.',
    icon: 'curlybraces',
  },
  [Route.Structured]: {
    route: Route.Structured,
    title: 'Structured',
    subtitle: 'Extract typed JSON that always parses.',
    icon: 'curlybraces',
  },
  [Route.Tools]: {
    route: Route.Tools,
    title: 'Tools',
    subtitle: 'The model picks a tool and fills its arguments.',
    icon: 'wrench.and.screwdriver',
  },
  [Route.Benchmarks]: {
    route: Route.Benchmarks,
    title: 'Benchmarks',
    subtitle: 'Measure load time, first token, and throughput.',
    icon: 'chart.bar',
  },
  [Route.Storage]: {
    route: Route.Storage,
    title: 'Storage',
    subtitle: 'What is on disk, and how to free it.',
    icon: 'internaldrive',
  },
};

/** Parse a hash fragment into a route, falling back to Chat. */
export function routeFromHash(hash: string): Route {
  const name = hash.replace(/^#\/?/, '');
  const match = Object.values(Route).find((route) => route === name);
  return match ?? Route.Chat;
}

export function hashForRoute(route: Route): string {
  return `#/${route}`;
}
