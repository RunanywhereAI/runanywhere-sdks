import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../npu_catalog.dart';
import '../npu_model_bar.dart';
import '../widgets.dart';

class LlmScreen extends StatefulWidget {
  const LlmScreen({super.key});

  @override
  State<LlmScreen> createState() => _LlmScreenState();
}

class _LlmScreenState extends State<LlmScreen> {
  final _controller = TextEditingController(text: 'Explain what an NPU is in one sentence.');
  String _output = '';
  bool _running = false;
  String? _error;
  String _tps = '—';
  String _ttft = '—';
  String _total = '—';
  bool _modelLoaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _output = '';
      _error = null;
      _running = true;
    });
    try {
      final opts = ra.LLMGenerationOptions(maxTokens: 256, temperature: 0.7);
      await for (final e in RunAnywhere.llm.generateStream(_controller.text, opts)) {
        if (e.token.isNotEmpty) {
          setState(() => _output += e.token);
        }
        if (e.isFinal) {
          final r = e.result;
          setState(() {
            _tps = r.tokensPerSecond.toStringAsFixed(1);
            _ttft = '${r.timeToFirstTokenMs} ms';
            _total = '${r.totalTimeMs} ms';
          });
        }
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NpuModelBar(
              modality: NpuModality.llm,
              onLoadedChange: (id) => setState(() => _modelLoaded = id != null),
            ),
            TextField(
              controller: _controller,
              enabled: !_running,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Prompt', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_running || !_modelLoaded) ? null : _generate,
                child: Text(
                  _running
                      ? 'Generating…'
                      : _modelLoaded
                          ? 'Generate'
                          : 'Load a model above',
                ),
              ),
            ),
            const SizedBox(height: 16),
            MetricStrip([('tokens/s', _tps), ('ttft', _ttft), ('total', _total)]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: 'Response',
              child: Text(
                _output.isEmpty ? (_running ? '…' : 'Output appears here.') : _output,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _output.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
