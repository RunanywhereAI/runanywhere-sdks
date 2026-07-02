<script lang="ts">
  import { IconArrowUp, IconChevronLeft, IconPhoto, IconX } from '@tabler/icons-svelte';
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
  import { vision } from '../stores/vision.svelte';

  let draft = $state('');
  let fileInput = $state<HTMLInputElement | null>(null);

  const modelLabel = $derived(
    catalog.vlm.find((m) => m.id === models.loadedVlmId)?.name ?? 'Select model',
  );

  function openModels(): void {
    sheet.show('Vision models', ModelList, {
      items: models.vlm,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => models.load(id),
    });
  }

  async function onPick(e: Event): Promise<void> {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (file) await vision.setImage(file);
  }

  async function submit(): Promise<void> {
    const text = draft;
    draft = '';
    await vision.run(text);
  }
</script>

<div class="screen">
  <AppBar title="Vision">
    {#snippet leading()}
      <IconButton icon={IconChevronLeft} label="Back" size={34} onclick={() => router.go('more')} />
    {/snippet}
    {#snippet actions()}<ModelChip label={modelLabel} onclick={openModels} />{/snippet}
  </AppBar>

  <input class="hidden" type="file" accept="image/*" bind:this={fileInput} onchange={onPick} />

  <div class="body">
    {#if !vision.ready}
      <div class="empty">
        <div class="orb"><Icon icon={IconPhoto} size={32} stroke={1.6} /></div>
        <h2>Describe & reason over images</h2>
        <p>Load a vision model to analyze photos — fully on-device.</p>
        <Button icon={IconPhoto} onclick={openModels}>Choose a model</Button>
      </div>
    {:else}
      {#if vision.previewUrl}
        <div class="preview">
          <img src={vision.previewUrl} alt="selected" />
          <button class="clear" onclick={() => vision.clear()} aria-label="Remove image">
            <Icon icon={IconX} size={16} stroke={2.2} />
          </button>
        </div>
      {:else}
        <button class="drop" onclick={() => fileInput?.click()}>
          <Icon icon={IconPhoto} size={28} stroke={1.7} />
          <span>Add an image</span>
        </button>
      {/if}

      {#if vision.answer}
        <div class="answer">{vision.answer}{#if vision.generating}<span class="caret"></span>{/if}</div>
      {/if}
    {/if}
  </div>

  {#if vision.ready}
    <div class="composer">
      <div class="box" class:disabled={!vision.hasImage}>
        <textarea
          bind:value={draft}
          rows="1"
          placeholder={vision.hasImage ? 'Ask about the image…' : 'Add an image first'}
          disabled={!vision.hasImage}
        ></textarea>
        <IconButton
          icon={IconArrowUp}
          label="Ask"
          size={36}
          variant="accent"
          disabled={!vision.hasImage || vision.generating || draft.trim().length === 0}
          onclick={submit}
        />
      </div>
    </div>
  {/if}
</div>

<style>
  .screen { display: flex; flex-direction: column; height: 100dvh; }
  .hidden { display: none; }
  .body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 14px;
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
  p { color: var(--muted); font-size: 14px; max-width: 30ch; }

  .drop {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 200px;
    border: 1.5px dashed var(--line-strong);
    border-radius: var(--r);
    background: var(--surface);
    color: var(--muted);
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: border-color 180ms ease, color 180ms ease;
  }
  .drop:hover { border-color: var(--accent); color: var(--accent); }
  .preview {
    position: relative;
    border-radius: var(--r);
    overflow: hidden;
    background: var(--surface-2);
  }
  .preview img { display: block; width: 100%; max-height: 340px; object-fit: contain; }
  .clear {
    position: absolute;
    top: 8px;
    right: 8px;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    border: none;
    border-radius: var(--r-full);
    background: color-mix(in srgb, var(--bg) 70%, transparent);
    backdrop-filter: blur(8px);
    color: var(--ink);
    cursor: pointer;
  }
  .answer {
    padding: 12px 14px;
    border-radius: 14px;
    background: var(--surface-2);
    font-size: 14.5px;
    line-height: 1.55;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .caret {
    display: inline-block;
    width: 7px;
    height: 15px;
    margin-left: 2px;
    vertical-align: -2px;
    background: currentColor;
    border-radius: 1px;
    animation: blink 1s steps(2, start) infinite;
  }
  @keyframes blink { 0%, 50% { opacity: 1; } 50.01%, 100% { opacity: 0; } }

  .composer { flex: none; padding: 8px 16px calc(var(--nav) + env(safe-area-inset-bottom) + 18px); }
  .box {
    display: flex;
    align-items: flex-end;
    gap: 6px;
    max-width: 640px;
    margin: 0 auto;
    padding: 5px 5px 5px 14px;
    background: var(--surface);
    border: 1px solid var(--line-strong);
    border-radius: 22px;
  }
  .box.disabled { opacity: 0.7; }
  textarea {
    flex: 1;
    border: none;
    outline: none;
    resize: none;
    background: none;
    color: var(--ink);
    font: inherit;
    font-size: 15px;
    line-height: 1.4;
    max-height: 120px;
    padding: 6px 0;
  }
  textarea::placeholder { color: var(--muted-2); }
  @media (prefers-reduced-motion: reduce) { .caret { animation: none; } .drop { transition: none; } }
</style>
