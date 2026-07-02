<script lang="ts">
  import { IconChevronLeft, IconMicrophone, IconPlayerStopFilled } from '@tabler/icons-svelte';
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
  import { stt } from '../stores/stt.svelte';

  const modelLabel = $derived(
    catalog.stt.find((m) => m.id === stt.loadedModelId)?.name ?? 'Select model',
  );

  function openModels(): void {
    sheet.show('Speech models', ModelList, {
      items: models.stt,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => stt.load(id),
    });
  }
</script>

<div class="screen">
  <AppBar title="Speech to Text">
    {#snippet leading()}
      <IconButton icon={IconChevronLeft} label="Back" size={34} onclick={() => router.go('more')} />
    {/snippet}
    {#snippet actions()}<ModelChip label={modelLabel} onclick={openModels} />{/snippet}
  </AppBar>

  <div class="body">
    {#if !stt.ready}
      <div class="empty">
        <div class="orb"><Icon icon={IconMicrophone} size={32} stroke={1.6} /></div>
        <h2>Transcribe your voice</h2>
        <p>Load a model to turn speech into text — fully on-device, nothing leaves your browser.</p>
        <Button icon={IconMicrophone} loading={stt.busy} onclick={openModels}>Load a model</Button>
      </div>
    {:else}
      <div class="pane">
        <div class="rec">
          {#if stt.recording}
            <Button icon={IconPlayerStopFilled} variant="soft" onclick={() => stt.stop()}>Stop</Button>
          {:else}
            <Button icon={IconMicrophone} loading={stt.transcribing} onclick={() => stt.record()}>
              {stt.transcribing ? 'Transcribing…' : 'Record'}
            </Button>
          {/if}
          {#if stt.recording}<span class="dot" aria-hidden="true"></span><span class="hint">Listening…</span>{/if}
        </div>
        <div class="out" class:muted={!stt.transcript}>
          {stt.transcript || 'Press Record and speak. Your transcript will appear here.'}
        </div>
      </div>
    {/if}

    {#if stt.error}
      <p class="err">{stt.error}</p>
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
  .rec { display: flex; align-items: center; gap: 10px; }
  .rec :global(button) { align-self: flex-start; }
  .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--danger, #e5484d);
    animation: pulse 1.1s ease-in-out infinite;
  }
  .hint { color: var(--muted); font-size: 13px; }
  .out {
    min-height: 140px;
    border: 1px solid var(--line-strong);
    border-radius: var(--r);
    background: var(--surface);
    color: var(--ink);
    font-size: 15px;
    line-height: 1.55;
    padding: 12px 14px;
    white-space: pre-wrap;
  }
  .out.muted { color: var(--muted-2); }

  .err { color: var(--danger, #e5484d); font-size: 13px; }

  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }
  @media (prefers-reduced-motion: reduce) { .dot { animation: none; } }
</style>
