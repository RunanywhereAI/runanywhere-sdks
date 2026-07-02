<script lang="ts">
  import { IconLayoutGrid, IconMessage2, IconMicrophone, IconSettings } from '@tabler/icons-svelte';
  import type { IconComponent } from '../icon';
  import { router, type Route } from '../stores/router.svelte';
  import Icon from './Icon.svelte';

  const items: { route: Route; label: string; icon: IconComponent }[] = [
    { route: 'chat', label: 'Chat', icon: IconMessage2 },
    { route: 'voice', label: 'Voice', icon: IconMicrophone },
    { route: 'more', label: 'More', icon: IconLayoutGrid },
    { route: 'settings', label: 'Settings', icon: IconSettings },
  ];
</script>

<nav class="bar">
  {#each items as it (it.route)}
    <button
      class="item"
      class:active={router.active === it.route}
      onclick={() => router.go(it.route)}
      aria-label={it.label}
      aria-current={router.active === it.route ? 'page' : undefined}
    >
      <Icon icon={it.icon} size={21} stroke={router.active === it.route ? 2.2 : 1.8} />
      <span class="lbl">{it.label}</span>
    </button>
  {/each}
</nav>

<style>
  .bar {
    position: fixed;
    left: 50%;
    transform: translateX(-50%);
    bottom: calc(env(safe-area-inset-bottom) + 14px);
    z-index: 30;
    display: flex;
    gap: 2px;
    padding: 6px;
    background: color-mix(in srgb, var(--surface) 90%, transparent);
    backdrop-filter: blur(22px);
    border: 1px solid var(--line);
    border-radius: var(--r-full);
    box-shadow: var(--shadow-lg);
  }
  .item {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    width: 68px;
    padding: 8px 0 6px;
    border: none;
    background: none;
    color: var(--muted-2);
    cursor: pointer;
    border-radius: var(--r-lg);
    transition: color 180ms ease, background 220ms var(--ease);
  }
  .item:hover { color: var(--ink); }
  .item.active {
    color: var(--accent);
    background: var(--accent-soft);
  }
  .lbl {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.01em;
  }
  @media (prefers-reduced-motion: reduce) {
    .item { transition: none; }
  }
</style>
