// solutions_view.dart — Wave 3 Step 3.3 (G-E6) demo for
// `RunAnywhereSDK.instance.solutions.run(yaml: ...)`.
//
// Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
// shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
// embedded inline as string constants — no asset-bundling churn — and
// each lifecycle transition is appended to a simple scrolling log.

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';

const _voiceAgentYaml = '''
voice_agent:
  llm_model_id: "qwen3-4b-q4_k_m"
  stt_model_id: "whisper-base"
  tts_model_id: "kokoro"
  vad_model_id: "silero-v5"

  sample_rate_hz: 16000
  chunk_ms: 20
  audio_source: "microphone"

  enable_barge_in: true
  barge_in_threshold_ms: 200

  system_prompt: "You are a helpful voice assistant. Keep answers concise."
  max_context_tokens: 4096
  temperature: 0.7

  emit_partials: true
  emit_thoughts: false
''';

const _ragYaml = '''
rag:
  embed_model_id: "bge-small-en-v1.5"
  rerank_model_id: "bge-reranker-v2-m3"
  llm_model_id: "qwen3-4b-q4_k_m"

  vector_store: "usearch"
  vector_store_path: "/tmp/ra-rag.usearch"

  retrieve_k: 24
  rerank_top: 6

  bm25_k1: 1.2
  bm25_b: 0.75
  rrf_k: 60

  prompt_template: "Use the context below to answer.\\n\\nContext:\\n{{context}}\\n\\nQuestion: {{query}}"
''';

class SolutionsView extends StatefulWidget {
  const SolutionsView({super.key});

  @override
  State<SolutionsView> createState() => _SolutionsViewState();
}

class _SolutionsViewState extends State<SolutionsView> {
  final List<String> _log = <String>[];
  bool _isRunning = false;

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  Future<void> _runSolution(String name, String yaml) async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _append('→ $name: creating solution from YAML…');
    try {
      final handle = await RunAnywhereSDK.instance.solutions.run(yaml: yaml);
      _append('✓ $name: handle created. Calling start()…');
      handle.start();
      _append('✓ $name: started. Tearing down (demo).');
      handle.destroy();
      _append('✓ $name: destroyed.');
    } catch (e) {
      _append('✗ $name: $e');
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solutions')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Run a prepackaged pipeline (voice agent or RAG) by handing a '
              'YAML config to RunAnywhere.solutions.run.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRunning
                        ? null
                        : () => _runSolution('Voice Agent', _voiceAgentYaml),
                    child: const Text('Voice Agent'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRunning
                        ? null
                        : () => _runSolution('RAG', _ragYaml),
                    child: const Text('RAG'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
