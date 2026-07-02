<script lang="ts">
  import { IconArrowUp, IconPlayerStopFilled, IconSparkles, IconTool } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Button from '../components/Button.svelte';
  import Icon from '../components/Icon.svelte';
  import IconButton from '../components/IconButton.svelte';
  import Markdown from '../components/Markdown.svelte';
  import ModelChip from '../components/ModelChip.svelte';
  import ModelList from '../components/ModelList.svelte';
  import PromptSuggestions from '../components/PromptSuggestions.svelte';
  import ThinkToggle from '../components/ThinkToggle.svelte';
  import ThinkingBlock from '../components/ThinkingBlock.svelte';
  import { catalog } from '../catalog';
  import { chat } from '../stores/chat.svelte';
  import { models } from '../stores/models.svelte';
  import { sheet } from '../stores/sheet.svelte';

  let draft = $state('');
  let thread = $state<HTMLDivElement | null>(null);

  const modelLabel = $derived(
    catalog.llm.find((m) => m.id === models.loadedLlmId)?.name ?? 'Select model',
  );

  function openModels(): void {
    sheet.show('Language models', ModelList, {
      items: models.llm,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => models.load(id),
    });
  }

  async function submit(): Promise<void> {
    const text = draft;
    draft = '';
    await chat.send(text);
  }

  function onKey(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void submit();
    }
  }

  $effect(() => {
    void chat.messages.length;
    void chat.messages.at(-1)?.text;
    thread?.scrollTo({ top: thread.scrollHeight });
  });
</script>

<div class="screen">
  <AppBar title="Chat">
    {#snippet actions()}
      {#if chat.supportsThinking}
        <ThinkToggle active={chat.thinkingEnabled} onToggle={() => (chat.thinkingEnabled = !chat.thinkingEnabled)} />
      {/if}
      <ModelChip label={modelLabel} onclick={openModels} />
    {/snippet}
  </AppBar>

  {#if !chat.ready && chat.messages.length === 0}
    <div class="empty">
      <div class="orb"><Icon icon={IconSparkles} size={32} stroke={1.6} /></div>
      <h2>Start a conversation</h2>
      <p>Load a language model to chat — fully on-device, nothing leaves your browser.</p>
      <Button icon={IconSparkles} onclick={openModels}>Choose a model</Button>
    </div>
  {:else}
    <div class="thread" bind:this={thread}>
      <div class="inner">
        {#if chat.messages.length === 0}
          <div class="hint">
            <Icon icon={IconSparkles} size={22} stroke={1.7} />
            <span>Ask anything — it stays on your device.</span>
          </div>
        {/if}
        {#each chat.messages as m, i (i)}
          {#if m.role === 'assistant'}
            <div class="msg assistant">
              <div class="acol">
                {#if (m.thinking ?? '').length > 0}
                  <ThinkingBlock text={m.thinking ?? ''} live={m.pending && m.text.length === 0} />
                {/if}
                {#if (m.tools ?? []).length > 0}
                  <div class="tools">
                    {#each m.tools ?? [] as t, ti (ti)}
                      <span class="toolchip"><Icon icon={IconTool} size={12} stroke={2} />{t}</span>
                    {/each}
                  </div>
                {/if}
                {#if m.text.trimStart().length > 0}
                  <div class="bubble"><Markdown text={m.text.trimStart()} />{#if m.pending}<span class="caret"></span>{/if}</div>
                {:else if m.pending && (m.thinking ?? '').length === 0}
                  <div class="bubble"><span class="caret"></span></div>
                {/if}
              </div>
            </div>
          {:else}
            <div class="msg user"><div class="bubble">{m.text}</div></div>
          {/if}
        {/each}
      </div>
    </div>
  {/if}

  <div class="composer">
    {#if chat.ready && chat.messages.length === 0}
      <PromptSuggestions tools={chat.toolsEnabled} onSelect={(p) => chat.send(p)} />
    {/if}
    <div class="box" class:disabled={!chat.ready}>
      <IconButton
        icon={IconTool}
        label={chat.toolsEnabled ? 'Tools on' : 'Tools off'}
        size={36}
        variant={chat.toolsEnabled ? 'accent' : 'default'}
        disabled={!chat.ready}
        onclick={() => (chat.toolsEnabled = !chat.toolsEnabled)}
      />
      <textarea
        bind:value={draft}
        onkeydown={onKey}
        rows="1"
        placeholder={chat.ready ? 'Message…' : 'Load a model to start'}
        disabled={!chat.ready}
      ></textarea>
      {#if chat.generating}
        <IconButton icon={IconPlayerStopFilled} label="Stop" size={36} variant="accent" onclick={() => chat.cancel()} />
      {:else}
        <IconButton
          icon={IconArrowUp}
          label="Send"
          size={36}
          variant="accent"
          disabled={!chat.ready || draft.trim().length === 0}
          onclick={submit}
        />
      {/if}
    </div>
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
  p { color: var(--muted); font-size: 14px; max-width: 30ch; }

  .thread {
    flex: 1;
    overflow-y: auto;
    padding: 12px 16px 20px;
  }
  .inner {
    max-width: 640px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 100%;
  }
  .hint {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    text-align: center;
    color: var(--muted-2);
    font-size: 13.5px;
  }
  .msg { display: flex; }
  .msg.user { justify-content: flex-end; }
  .acol {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 6px;
    max-width: 82%;
  }
  .acol .bubble { max-width: 100%; }
  .tools { display: flex; flex-wrap: wrap; gap: 6px; }
  .toolchip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 9px;
    border-radius: var(--r-full);
    background: var(--accent-soft);
    color: var(--accent);
    font-size: 11.5px;
    font-weight: 600;
    font-family: var(--font-mono);
  }
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

  .composer {
    flex: none;
    padding: 8px 16px calc(var(--nav) + env(safe-area-inset-bottom) + 18px);
  }
  .box {
    display: flex;
    align-items: flex-end;
    gap: 4px;
    max-width: 640px;
    margin: 0 auto;
    padding: 5px;
    background: var(--surface);
    border: 1px solid var(--line-strong);
    border-radius: 22px;
  }
  .box textarea { padding-left: 4px; }
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
  @media (prefers-reduced-motion: reduce) {
    .caret { animation: none; }
  }
</style>
