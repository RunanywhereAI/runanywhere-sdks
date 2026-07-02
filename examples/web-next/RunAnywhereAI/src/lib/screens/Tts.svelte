<script lang="ts">
  import { IconChevronLeft, IconPlayerPlayFilled, IconPlayerStopFilled, IconVolume } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Button from '../components/Button.svelte';
  import Icon from '../components/Icon.svelte';
  import IconButton from '../components/IconButton.svelte';
  import ModelChip from '../components/ModelChip.svelte';
  import ModelList from '../components/ModelList.svelte';
  import { catalog } from '../catalog';
  import { models } from '../stores/models.svelte';
  import { router } from '../stores/router.svelte';
  import { sheet } from '../stores/sheet.svelte';
  import { tts } from '../stores/tts.svelte';

  let text = $state('Hello! This speech is generated entirely on your device.');

  const modelLabel = $derived(
    catalog.tts.find((m) => m.id === tts.loadedModelId)?.name ?? 'Select voice',
  );

  function openModels(): void {
    sheet.show('Voices', ModelList, {
      items: models.tts,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => tts.load(id),
    });
  }
</script>

<div class="screen">
  <AppBar title="Text to Speech">
    {#snippet leading()}
      <IconButton icon={IconChevronLeft} label="Back" size={34} onclick={() => router.go('more')} />
    {/snippet}
    {#snippet actions()}<ModelChip label={modelLabel} onclick={openModels} />{/snippet}
  </AppBar>

  <div class="body">
    {#if !tts.ready}
      <div class="empty">
        <div class="orb"><Icon icon={IconVolume} size={32} stroke={1.6} /></div>
        <h2>Speak any text</h2>
        <p>Load a voice to synthesize natural speech — fully on-device, nothing leaves your browser.</p>
        <Button icon={IconVolume} loading={tts.busy} onclick={openModels}>Choose a voice</Button>
      </div>
    {:else}
      <div class="pane">
        <textarea bind:value={text} rows="5" placeholder="Type something to speak…"></textarea>
        {#if tts.speaking}
          <Button icon={IconPlayerStopFilled} variant="soft" onclick={() => tts.stop()}>Stop</Button>
        {:else}
          <Button icon={IconPlayerPlayFilled} disabled={text.trim().length === 0} onclick={() => tts.speak(text)}>
            Speak
          </Button>
        {/if}
      </div>
    {/if}

    {#if tts.error}
      <p class="err">{tts.error}</p>
    {/if}
  </div>
</div>

<style>
  .screen { display: flex; flex-direction: column; min-height: 100dvh; }
  .body {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 16px;
    max-width: 640px;
    width: 100%;
    margin: 0 auto;
  }
  .empty {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    gap: 12px;
    padding: 40px 28px;
  }
  .orb {
    width: 72px;
    height: 72px;
    display: grid;
    place-items: center;
    border-radius: var(--r-lg);
    color: var(--accent);
    background: var(--accent-soft);
    margin-bottom: 6px;
  }
  h2 { font-size: 20px; font-weight: 700; letter-spacing: -0.02em; }
  p { color: var(--muted); font-size: 14px; max-width: 32ch; }

  .pane { display: flex; flex-direction: column; gap: 12px; }
  .pane textarea {
    border: 1px solid var(--line-strong);
    border-radius: var(--r);
    background: var(--surface);
    color: var(--ink);
    font: inherit;
    font-size: 15px;
    line-height: 1.55;
    padding: 12px 14px;
    resize: vertical;
    outline: none;
  }
  .pane textarea::placeholder { color: var(--muted-2); }
  .pane :global(button) { align-self: flex-start; }

  .err { color: var(--danger, #e5484d); font-size: 13px; }
</style>
