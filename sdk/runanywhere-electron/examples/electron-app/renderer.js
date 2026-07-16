// Runs in the page (contextIsolation: true, no Node). Uses only the safe
// window.runanywhere bridge the preload exposed. Inference happens in the utility
// process; tokens stream back here over the MessagePort.
(async () => {
  const ra = window.runanywhere;
  const t = window.runanywhereTest;
  const out = document.getElementById('out');
  const log = (s) => {
    out.textContent += s;
    t.log(String(s));
  };

  try {
    const model = new URLSearchParams(location.search).get('model');
    await ra.ready();
    log('[renderer] MessagePort connected; commons version ' + (await ra.version()) + '\n');
    await ra.initialize();
    log('[renderer] initialized; loading LLM: ' + model + '\n');

    const h = await ra.loadLLM(model);
    log('[renderer] LLM handle=' + h + '; streaming generation over the port:\n');

    let text = '';
    await ra.generate(h, 'What is the capital of France? Answer in one word.', (tok) => {
      text += tok;
      log('  <token> ' + JSON.stringify(tok) + '\n');
    });
    log('[renderer] FULL RESPONSE: ' + text.trim() + '\n');

    await ra.unloadLLM(h);
    await ra.shutdown();
    log('[renderer] SUCCESS — renderer <- MessagePort <- utilityProcess <- .node streaming works.\n');
    t.done(true);
  } catch (e) {
    log('[renderer] FAILURE: ' + (e && e.message ? e.message : String(e)) + '\n');
    t.done(false);
  }
})();
