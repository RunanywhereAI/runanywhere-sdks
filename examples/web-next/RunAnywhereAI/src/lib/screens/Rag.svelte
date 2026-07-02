<script lang="ts">
  import {
    IconArrowUp,
    IconChevronDown,
    IconChevronLeft,
    IconChevronRight,
    IconChevronUp,
    IconDatabase,
    IconFileText,
    IconMessageCircle,
    IconPlus,
  } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Icon from '../components/Icon.svelte';
  import IconButton from '../components/IconButton.svelte';
  import Markdown from '../components/Markdown.svelte';
  import ModelList from '../components/ModelList.svelte';
  import { catalog } from '../catalog';
  import { models } from '../stores/models.svelte';
  import { rag } from '../stores/rag.svelte';
  import { router } from '../stores/router.svelte';
  import { sheet } from '../stores/sheet.svelte';

  let question = $state('');
  let setupExpanded = $state(true);
  let expandedSources = $state<Record<number, boolean>>({});
  let fileInput: HTMLInputElement | null = $state(null);
  let thread = $state<HTMLDivElement | null>(null);

  const embeddingName = $derived(catalog.embedding.find((m) => m.id === models.loadedEmbeddingId)?.name ?? null);
  const llmName = $derived(catalog.llm.find((m) => m.id === models.loadedLlmId)?.name ?? null);
  const collapsible = $derived(rag.ready && rag.hasDocuments);
  const showFullSetup = $derived(setupExpanded || !collapsible);

  // Fold the setup card into the compact bar the moment both models and a
  // document are ready; leaves the user free to expand it again afterwards.
  let wasReady = false;
  $effect(() => {
    const c = rag.ready && rag.hasDocuments;
    if (c && !wasReady) setupExpanded = false;
    wasReady = c;
  });

  $effect(() => {
    void rag.messages.length;
    void rag.messages.at(-1)?.text;
    thread?.scrollTo({ top: thread.scrollHeight });
  });

  function openEmbedding(): void {
    sheet.show('Embedding models', ModelList, {
      items: models.embedding,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => models.load(id),
    });
  }

  function openLlm(): void {
    sheet.show('Language models', ModelList, {
      items: models.llm,
      loadable: true,
      onDownload: (id: string) => models.download(id),
      onLoad: (id: string) => models.load(id),
    });
  }

  async function onFiles(e: Event): Promise<void> {
    const input = e.currentTarget as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    input.value = '';
    for (const file of files) {
      const text = await file.text();
      await rag.ingest(file.name, text);
    }
  }

  async function ask(): Promise<void> {
    const q = question;
    question = '';
    await rag.ask(q);
  }

  function onKey(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void ask();
    }
  }
</script>

<div class="screen">
  <AppBar title="RAG">
    {#snippet leading()}
      <IconButton icon={IconChevronLeft} label="Back" size={34} onclick={() => router.go('more')} />
    {/snippet}
  </AppBar>

  <input
    bind:this={fileInput}
    type="file"
    accept=".txt,.md,.markdown,.csv,.json,.text,text/plain"
    multiple
    hidden
    onchange={onFiles}
  />

  <div class="body" bind:this={thread}>
    {#if showFullSetup}
      <section class="card">
        {#if collapsible}
          <button class="collapse" onclick={() => (setupExpanded = false)}>
            <span>Setup</span>
            <Icon icon={IconChevronUp} size={16} stroke={1.8} />
          </button>
          <div class="hr"></div>
        {/if}

        <button class="row" onclick={openEmbedding}>
          <span class="lead" class:on={!!embeddingName}><Icon icon={IconDatabase} size={20} stroke={1.7} /></span>
          <span class="rcol">
            <span class="rlabel">Embedding model</span>
            <span class="rvalue" class:placeholder={!embeddingName}>{embeddingName ?? 'Tap to select'}</span>
          </span>
          <span class="trail"><Icon icon={IconChevronRight} size={16} stroke={1.8} /></span>
        </button>
        <div class="hr"></div>

        <button class="row" onclick={openLlm}>
          <span class="lead" class:on={!!llmName}><Icon icon={IconMessageCircle} size={20} stroke={1.7} /></span>
          <span class="rcol">
            <span class="rlabel">Language model</span>
            <span class="rvalue" class:placeholder={!llmName}>{llmName ?? 'Tap to select'}</span>
          </span>
          <span class="trail"><Icon icon={IconChevronRight} size={16} stroke={1.8} /></span>
        </button>
        <div class="hr"></div>

        <div class="docs">
          <div class="dhead">
            <span>
              {#if rag.documents.length === 0}
                Documents
              {:else}
                {rag.documents.length} document{rag.documents.length === 1 ? '' : 's'} · {rag.chunkCount} chunks
              {/if}
            </span>
            {#if rag.documents.length > 0}
              <button class="clear" onclick={() => rag.clearAll()}>Clear</button>
            {/if}
          </div>

          {#each rag.documents as name (name)}
            <div class="doc"><span class="lead on"><Icon icon={IconFileText} size={15} stroke={1.7} /></span><span>{name}</span></div>
          {/each}

          <button
            class="add"
            disabled={!rag.ready || rag.busy}
            onclick={() => fileInput?.click()}
          >
            {#if rag.busy}
              <span class="spin"></span><span>Reading…</span>
            {:else}
              <Icon icon={IconPlus} size={15} stroke={2} />
              <span>{rag.ready ? (rag.documents.length === 0 ? 'Add document' : 'Add another') : 'Pick models first'}</span>
            {/if}
          </button>
        </div>
      </section>
    {:else}
      <button class="bar" onclick={() => (setupExpanded = true)}>
        <span class="lead on"><Icon icon={IconFileText} size={16} stroke={1.7} /></span>
        <span class="bartext">{rag.documents.length} document{rag.documents.length === 1 ? '' : 's'} · {rag.chunkCount} chunks</span>
        {#if rag.busy}
          <span class="spin"></span>
        {:else}
          <span
            class="baradd"
            role="button"
            tabindex="0"
            onclick={(e) => { e.stopPropagation(); fileInput?.click(); }}
            onkeydown={(e) => { if (e.key === 'Enter') { e.stopPropagation(); fileInput?.click(); } }}
          >
            <Icon icon={IconPlus} size={18} stroke={2} />
          </span>
        {/if}
        <span class="trail"><Icon icon={IconChevronDown} size={16} stroke={1.8} /></span>
      </button>
    {/if}

    <div class="convo">
      {#if rag.messages.length === 0}
        <div class="hint">
          <div class="orb"><Icon icon={IconDatabase} size={28} stroke={1.6} /></div>
          <p>
            {#if !rag.ready}
              Pick an embedding model and a language model to begin
            {:else if !rag.hasDocuments}
              Add a document, then ask a question about it
            {:else}
              Ask a question about your documents
            {/if}
          </p>
        </div>
      {:else}
        {#each rag.messages as m (m.id)}
          {#if m.isUser}
            <div class="msg user"><div class="bubble">{m.text}</div></div>
          {:else}
            <div class="msg assistant">
              <div class="acol">
                {#if m.text.trimStart().length > 0}
                  <div class="bubble"><Markdown text={m.text.trimStart()} />{#if m.pending}<span class="caret"></span>{/if}</div>
                {:else if m.pending}
                  <div class="bubble"><span class="caret"></span></div>
                {/if}
                {#if m.sources.length > 0}
                  <div class="sources">
                    <button class="stoggle" onclick={() => (expandedSources = { ...expandedSources, [m.id]: !expandedSources[m.id] })}>
                      <Icon icon={expandedSources[m.id] ? IconChevronUp : IconChevronDown} size={14} stroke={1.8} />
                      <span>{m.sources.length} source{m.sources.length === 1 ? '' : 's'}{m.elapsedMs > 0 ? ` · ${(m.elapsedMs / 1000).toFixed(1)}s` : ''}</span>
                    </button>
                    {#if expandedSources[m.id]}
                      <div class="scards">
                        {#each m.sources as s, si (si)}
                          <div class="scard">
                            <div class="shead">
                              <span class="sdoc">{s.document}</span>
                              <span class="sscore">{(s.score * 100).toFixed(0)}%</span>
                            </div>
                            <span class="stext">{s.text}</span>
                          </div>
                        {/each}
                      </div>
                    {/if}
                  </div>
                {/if}
              </div>
            </div>
          {/if}
        {/each}
      {/if}
    </div>

    {#if rag.error}
      <p class="err">{rag.error}</p>
    {/if}
  </div>

  <div class="composer">
    <div class="box" class:disabled={!rag.hasDocuments || rag.generating}>
      <textarea
        bind:value={question}
        onkeydown={onKey}
        rows="1"
        placeholder={rag.hasDocuments ? 'Ask about your documents…' : 'Add a document first'}
        disabled={!rag.hasDocuments || rag.generating}
      ></textarea>
      <IconButton
        icon={IconArrowUp}
        label="Ask"
        size={36}
        variant="accent"
        disabled={!rag.canQuery || question.trim().length === 0}
        onclick={ask}
      />
    </div>
  </div>
</div>

<style>
  .screen { display: flex; flex-direction: column; height: 100dvh; }
  .body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    max-width: 640px;
    width: 100%;
    margin: 0 auto;
  }

  .card {
    border: 1px solid var(--line);
    border-radius: var(--r-lg);
    background: var(--surface);
    overflow: hidden;
  }
  .hr { height: 1px; background: var(--line); }
  .collapse,
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    background: none;
    border: none;
    color: var(--ink);
    text-align: left;
    cursor: pointer;
    font: inherit;
  }
  .collapse {
    justify-content: space-between;
    padding: 10px 16px;
    color: var(--muted);
    font-size: 12px;
  }
  .row { padding: 12px 16px; }
  .lead { display: flex; color: var(--muted-2); flex: none; }
  .lead.on { color: var(--accent); }
  .trail { display: flex; color: var(--muted-2); flex: none; }
  .rcol { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .rlabel { font-size: 12px; color: var(--muted); }
  .rvalue { font-size: 15px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .rvalue.placeholder { color: var(--muted-2); }

  .docs { display: flex; flex-direction: column; gap: 8px; padding: 14px 16px; }
  .dhead { display: flex; align-items: center; justify-content: space-between; font-size: 12px; color: var(--muted); }
  .clear {
    background: none;
    border: none;
    color: var(--accent);
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    padding: 2px 4px;
  }
  .doc { display: flex; align-items: center; gap: 8px; font-size: 14px; }
  .doc :global(.on) { color: var(--accent); flex: none; }
  .doc span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .add {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    padding: 11px;
    border: none;
    border-radius: var(--r-sm);
    background: var(--surface-2);
    color: var(--accent);
    font: inherit;
    font-size: 14px;
    cursor: pointer;
  }
  .add:disabled { color: var(--muted-2); cursor: default; }

  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    padding: 12px 16px;
    border: 1px solid var(--line);
    border-radius: var(--r-lg);
    background: var(--surface);
    color: var(--ink);
    cursor: pointer;
    font: inherit;
  }
  .bar :global(.on) { color: var(--accent); flex: none; }
  .bartext { flex: 1; text-align: left; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .baradd { display: grid; place-items: center; color: var(--accent); cursor: pointer; }
  .bar :global(svg:last-child) { color: var(--muted-2); }

  .convo { display: flex; flex-direction: column; gap: 12px; }
  .hint {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
    padding: 32px 24px;
    color: var(--muted);
  }
  .orb {
    width: 60px;
    height: 60px;
    display: grid;
    place-items: center;
    border-radius: var(--r-lg);
    color: var(--accent);
    background: var(--accent-soft);
  }
  .hint p { font-size: 14.5px; max-width: 28ch; }

  .msg { display: flex; }
  .msg.user { justify-content: flex-end; }
  .acol { display: flex; flex-direction: column; align-items: flex-start; gap: 6px; max-width: 90%; }
  .bubble {
    max-width: 82%;
    padding: 10px 14px;
    border-radius: 18px;
    font-size: 14.5px;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .msg.user .bubble { background: var(--accent); color: var(--on-accent); border-bottom-right-radius: 6px; }
  .msg.assistant .bubble { background: var(--surface-2); color: var(--ink); border-bottom-left-radius: 6px; max-width: 100%; }

  .sources { display: flex; flex-direction: column; gap: 8px; padding-left: 2px; }
  .stoggle {
    display: flex;
    align-items: center;
    gap: 5px;
    background: none;
    border: none;
    color: var(--muted);
    font: inherit;
    font-size: 12.5px;
    cursor: pointer;
    padding: 0;
  }
  .scards { display: flex; flex-direction: column; gap: 8px; }
  .scard { padding: 10px 12px; border-radius: var(--r-sm); background: var(--surface); border: 1px solid var(--line); }
  .shead { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 4px; }
  .sdoc { font-size: 12px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sscore { font-family: var(--font-mono); font-weight: 700; font-size: 12px; color: var(--accent); flex: none; }
  .stext { font-size: 13px; line-height: 1.5; color: var(--muted); white-space: pre-wrap; word-break: break-word; display: -webkit-box; -webkit-line-clamp: 4; line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }

  .err { color: var(--danger, #e5484d); font-size: 13px; }

  .caret {
    display: inline-block;
    width: 7px; height: 15px; margin-left: 2px; vertical-align: -2px;
    background: currentColor; border-radius: 1px;
    animation: blink 1s steps(2, start) infinite;
  }
  @keyframes blink { 0%, 50% { opacity: 1; } 50.01%, 100% { opacity: 0; } }
  .spin {
    width: 15px; height: 15px; flex: none;
    border: 2px solid var(--line-strong);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

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
  .box textarea {
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
  .box textarea::placeholder { color: var(--muted-2); }
  @media (prefers-reduced-motion: reduce) { .caret, .spin { animation: none; } }
</style>
