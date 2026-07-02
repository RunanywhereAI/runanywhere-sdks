<script lang="ts">
  import { IconMicrophone, IconPlayerStopFilled } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Icon from '../components/Icon.svelte';
  import ModelChip from '../components/ModelChip.svelte';
  import ModelList from '../components/ModelList.svelte';
  import { catalog } from '../catalog';
  import { models } from '../stores/models.svelte';
  import { sheet } from '../stores/sheet.svelte';
  import { stt } from '../stores/stt.svelte';
  import { tts } from '../stores/tts.svelte';
  import { voice } from '../stores/voice.svelte';

  let thread = $state<HTMLDivElement | null>(null);

  const sttLabel = $derived(catalog.stt.find((m) => m.id === stt.loadedModelId)?.name ?? 'STT');
  const llmLabel = $derived(catalog.llm.find((m) => m.id === models.loadedLlmId)?.name ?? 'Model');
  const ttsLabel = $derived(catalog.tts.find((m) => m.id === tts.loadedModelId)?.name ?? 'Voice');

  function pickStt(): void {
    sheet.show('Speech to text', ModelList, {
      items: models.stt,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => stt.load(id),
    });
  }

  function pickLlm(): void {
    sheet.show('Language model', ModelList, {
      items: models.llm,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => models.load(id),
    });
  }

  function pickTts(): void {
    sheet.show('Voice', ModelList, {
      items: models.tts,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => tts.load(id),
    });
  }

  function onMic(): void {
    if (voice.busy) {
      voice.stop();
    } else if (voice.listening) {
      void voice.stopAndRespond();
    } else {
      void voice.startListening();
    }
  }

  const status = $derived.by(() => {
    switch (voice.phase) {
      case 'listening':
        return 'Listening… tap to send';
      case 'thinking':
        return 'Thinking…';
      case 'speaking':
        return 'Speaking… tap to stop';
      default:
        return voice.ready ? 'Tap to talk' : 'Load a model for each stage below';
    }
  });

  $effect(() => {
    void voice.turns.length;
    void voice.turns.at(-1)?.text;
    thread?.scrollTo({ top: thread.scrollHeight });
  });
</script>

<div class="screen">
  <AppBar title="Voice">
    {#snippet actions()}
      <ModelChip label={sttLabel} onclick={pickStt} />
      <ModelChip label={llmLabel} onclick={pickLlm} />
      <ModelChip label={ttsLabel} onclick={pickTts} />
    {/snippet}
  </AppBar>

  {#if voice.turns.length === 0}
    <div class="empty">
      <div class="orb"><Icon icon={IconMicrophone} size={32} stroke={1.6} /></div>
      <h2>Talk to your device</h2>
      <p>Load a speech-to-text model, a language model, and a voice — then hold a conversation, fully on-device.</p>
      <div class="stages">
        <span class="stage" class:done={stt.ready}>STT · {sttLabel}</span>
        <span class="stage" class:done={models.loadedLlmId != null}>LLM · {llmLabel}</span>
        <span class="stage" class:done={tts.ready}>TTS · {ttsLabel}</span>
      </div>
    </div>
  {:else}
    <div class="thread" bind:this={thread}>
      <div class="inner">
        {#each voice.turns as t, i (i)}
          <div class="msg {t.role}">
            <div class="bubble">
              {t.text}{#if t.pending}<span class="caret"></span>{/if}
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <div class="controls">
    {#if voice.error}<p class="err">{voice.error}</p>{/if}
    <p class="status" class:muted={!voice.ready}>{status}</p>
    <button
      class="mic"
      class:listening={voice.listening}
      class:busy={voice.busy}
      disabled={!voice.ready && !voice.busy && !voice.listening}
      onclick={onMic}
      aria-label={voice.busy ? 'Stop' : voice.listening ? 'Send' : 'Talk'}
    >
      {#if voice.busy}
        <Icon icon={IconPlayerStopFilled} size={34} stroke={1.7} />
      {:else}
        <Icon icon={IconMicrophone} size={38} stroke={1.7} />
      {/if}
      {#if voice.listening}<span class="ring" aria-hidden="true"></span>{/if}
    </button>
  </div>
</div>

<style>
  .screen { display: flex; flex-direction: column; height: 100dvh; }
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
  .empty p { color: var(--muted); font-size: 14px; max-width: 34ch; }
  .stages {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 8px;
    margin-top: 6px;
  }
  .stage {
    padding: 5px 11px;
    border-radius: var(--r-full);
    border: 1px solid var(--line-strong);
    background: var(--surface);
    color: var(--muted);
    font-size: 12px;
    font-weight: 600;
    max-width: 46vw;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .stage.done { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }

  .thread { flex: 1; overflow-y: auto; padding: 12px 16px 8px; }
  .inner {
    max-width: 640px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .msg { display: flex; }
  .msg.user { justify-content: flex-end; }
  .bubble {
    max-width: 82%;
    padding: 10px 14px;
    border-radius: 18px;
    font-size: 14.5px;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .msg.user .bubble {
    background: var(--accent);
    color: var(--on-accent);
    border-bottom-right-radius: 6px;
  }
  .msg.assistant .bubble {
    background: var(--surface-2);
    color: var(--ink);
    border-bottom-left-radius: 6px;
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

  .controls {
    flex: none;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 12px 16px calc(var(--nav) + env(safe-area-inset-bottom) + 20px);
  }
  .err { color: var(--err, #e5484d); font-size: 13px; text-align: center; }
  .status { font-size: 13px; color: var(--ink); font-weight: 600; }
  .status.muted { color: var(--muted); font-weight: 500; }

  .mic {
    position: relative;
    width: 84px;
    height: 84px;
    border: none;
    border-radius: 50%;
    color: var(--on-accent);
    background: var(--accent);
    display: grid;
    place-items: center;
    cursor: pointer;
    transition: transform 160ms var(--ease), filter 200ms ease, background 200ms ease;
  }
  .mic:hover:not(:disabled) { filter: brightness(1.05); }
  .mic:active:not(:disabled) { transform: scale(0.94); }
  .mic:disabled { opacity: 0.45; cursor: default; }
  .mic.listening { background: var(--err, #e5484d); }
  .mic.busy { background: var(--surface-2); color: var(--ink); }
  .ring {
    position: absolute;
    inset: -6px;
    border-radius: 50%;
    border: 2px solid var(--err, #e5484d);
    opacity: 0.5;
    animation: ping 1.4s ease-out infinite;
  }
  @keyframes ping {
    0% { transform: scale(0.9); opacity: 0.6; }
    100% { transform: scale(1.25); opacity: 0; }
  }
  @media (prefers-reduced-motion: reduce) {
    .mic, .ring { transition: none; animation: none; }
    .caret { animation: none; }
  }
</style>
