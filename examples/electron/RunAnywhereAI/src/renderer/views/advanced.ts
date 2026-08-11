/**
 * Advanced hub — grid of secondary capabilities.
 *
 * Mirrors `ConsumerAdvancedHubView` (macOS order) plus Electron-only rows
 * (Diarization, Segmentation, Knowledge demos, Storage) that the desktop
 * facade can actually run. Connect / Computer Use stay deferred.
 */
import { icon, type IconName } from '../components/icons';
import type { ViewFactory } from '../shell/app';
import { Route, ROUTE_META } from '../shell/routes';

interface HubItem {
  readonly route: Route;
  readonly title: string;
  readonly subtitle: string;
  readonly icon: IconName;
}

interface HubSection {
  readonly title: string;
  readonly items: readonly HubItem[];
  readonly footer?: string;
}

const SECTIONS: readonly HubSection[] = [
  {
    title: 'Voice Utilities',
    items: [
      {
        route: Route.Transcribe,
        title: 'Transcribe',
        subtitle: 'Turn a recording into text',
        icon: ROUTE_META[Route.Transcribe].icon,
      },
      {
        route: Route.Speak,
        title: 'Read Aloud',
        subtitle: 'Hear any text spoken on this device',
        icon: ROUTE_META[Route.Speak].icon,
      },
      {
        route: Route.Vad,
        title: 'Voice Activity',
        subtitle: 'See when speech starts and stops',
        icon: ROUTE_META[Route.Vad].icon,
      },
      {
        route: Route.Diarization,
        title: 'Diarization',
        subtitle: 'See who spoke when in a recording',
        icon: ROUTE_META[Route.Diarization].icon,
      },
    ],
  },
  {
    title: 'Vision Utilities',
    items: [
      {
        route: Route.Segmentation,
        title: 'Segmentation',
        subtitle: 'Split a photo into labelled regions',
        icon: ROUTE_META[Route.Segmentation].icon,
      },
    ],
  },
  {
    title: 'Agents',
    items: [
      {
        route: Route.Voice,
        title: 'Talk',
        subtitle: 'Hands-free voice conversation, all on this device',
        icon: ROUTE_META[Route.Voice].icon,
      },
    ],
  },
  {
    title: 'Workbench',
    items: [
      {
        route: Route.Knowledge,
        title: 'Knowledge',
        subtitle: 'Add documents, then ask questions answered only from them',
        icon: ROUTE_META[Route.Knowledge].icon,
      },
      {
        route: Route.Embeddings,
        title: 'Embeddings',
        subtitle: 'Semantic similarity between two texts',
        icon: ROUTE_META[Route.Embeddings].icon,
      },
      {
        route: Route.Structured,
        title: 'Structured',
        subtitle: 'Extract typed JSON that always parses',
        icon: ROUTE_META[Route.Structured].icon,
      },
      {
        route: Route.Tools,
        title: 'Tools',
        subtitle: 'The model picks a tool and fills its arguments',
        icon: ROUTE_META[Route.Tools].icon,
      },
    ],
  },
  {
    title: 'Management',
    items: [
      {
        route: Route.Benchmarks,
        title: 'Benchmarks',
        subtitle: 'Measure local model performance',
        icon: ROUTE_META[Route.Benchmarks].icon,
      },
      {
        route: Route.Storage,
        title: 'Storage',
        subtitle: 'What is on disk, and how to free it',
        icon: ROUTE_META[Route.Storage].icon,
      },
    ],
    footer: 'Storage and tool calling also live in Settings and Manage Models.',
  },
];

function rowHtml(item: HubItem): string {
  return (
    `<button type="button" class="ra-hub-row" data-route="${item.route}">` +
    `<span class="ra-hub-row-icon">${icon(item.icon, { size: 18 })}</span>` +
    `<span class="ra-hub-row-copy">` +
    `<strong>${item.title}</strong>` +
    `<small>${item.subtitle}</small>` +
    `</span>` +
    `${icon('chevron.right', { size: 14, className: 'ra-hub-row-chevron' })}` +
    `</button>`
  );
}

export const createAdvancedView: ViewFactory = ({ root, navigate }) => {
  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-hub';
  scroll.innerHTML = SECTIONS.map((section) => {
    const footer =
      section.footer === undefined
        ? ''
        : `<p class="ra-hub-footer">${section.footer}</p>`;
    return (
      `<section class="ra-hub-section">` +
      `<h2 class="ra-hub-section-title">${section.title}</h2>` +
      `<div class="ra-hub-list">${section.items.map(rowHtml).join('')}</div>` +
      footer +
      `</section>`
    );
  }).join('');

  scroll.addEventListener('click', (event) => {
    const target = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-route]');
    if (target === null) return;
    const route = target.dataset.route as Route | undefined;
    if (route === undefined) return;
    navigate(route);
  });

  root.append(scroll);
  return {};
};
