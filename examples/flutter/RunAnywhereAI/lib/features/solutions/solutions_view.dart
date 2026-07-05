// solutions_view.dart — demo for
// `RunAnywhere.solutions.run(yaml: ...)`.
//
// Two buttons run the canonical voice_agent.yaml + rag.yaml solutions. The
// YAML payloads come from `lib/generated/solutions_yaml.dart`, emitted by
// `scripts/examples/flutter/sync-solutions-yamls.sh` from the canonical
// `sdk/runanywhere-commons/examples/solutions/*.yaml` — no inline copies,
// no drift (mirrors the iOS / React Native example sync scripts).

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/generated/solutions_yaml.dart';

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
    _append('$name: creating solution from YAML…');
    try {
      final handle = await RunAnywhere.solutions.run(yaml: yaml);
      _append('$name: handle created. Calling start()…');
      handle.start();
      _append('$name: started. Tearing down (demo).');
      handle.destroy();
      _append('$name: destroyed.');
    } catch (e) {
      _append('$name: $e');
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
                        : () =>
                            _runSolution('Voice Agent', SolutionsYaml.voiceAgent),
                    child: const Text('Voice Agent'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRunning
                        ? null
                        : () => _runSolution('RAG', SolutionsYaml.rag),
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
