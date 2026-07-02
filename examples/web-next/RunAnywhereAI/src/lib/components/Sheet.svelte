<script lang="ts">
  import { fade, fly } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';
  import { IconX } from '@tabler/icons-svelte';
  import { sheet } from '../stores/sheet.svelte';
  import IconButton from './IconButton.svelte';

  let drag = $state(0);
  let startY = 0;
  let dragging = false;

  function down(e: PointerEvent): void {
    dragging = true;
    startY = e.clientY;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }
  function move(e: PointerEvent): void {
    if (!dragging) return;
    drag = Math.max(0, e.clientY - startY);
  }
  function up(): void {
    if (!dragging) return;
    dragging = false;
    if (drag > 120) sheet.close();
    drag = 0;
  }
</script>

{#if sheet.open}
  <button class="backdrop" aria-label="Close" transition:fade={{ duration: 220 }} onclick={() => sheet.close()}></button>
  <section
    class="panel"
    style="transform: translateY({drag}px)"
    transition:fly={{ y: 480, duration: 360, easing: cubicOut }}
  >
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="grab" onpointerdown={down} onpointermove={move} onpointerup={up} onpointercancel={up}>
      <span class="bar"></span>
    </div>
    <header>
      <h2>{sheet.title}</h2>
      <IconButton icon={IconX} label="Close" onclick={() => sheet.close()} />
    </header>
    <div class="body">
      {#if sheet.content}
        {@const Content = sheet.content}
        <Content {...sheet.props} />
      {/if}
    </div>
  </section>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    border: none;
    padding: 0;
    cursor: default;
    background: rgba(10, 8, 6, 0.42);
    backdrop-filter: blur(2px);
    z-index: 40;
  }
  .panel {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    width: min(560px, 100%);
    margin: 0 auto;
    max-height: 86dvh;
    display: flex;
    flex-direction: column;
    background: var(--surface);
    border: 1px solid var(--line);
    border-bottom: none;
    border-radius: var(--r-lg) var(--r-lg) 0 0;
    box-shadow: var(--shadow-lg);
    z-index: 41;
    padding-bottom: env(safe-area-inset-bottom);
    touch-action: none;
  }
  .grab {
    display: flex;
    justify-content: center;
    padding: 10px 0 4px;
    cursor: grab;
  }
  .bar {
    width: 40px;
    height: 4px;
    border-radius: var(--r-full);
    background: var(--line-strong);
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 4px 12px 12px 20px;
  }
  h2 {
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  .body {
    overflow-y: auto;
    padding: 0 16px 20px;
  }
</style>
