import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';

import '../widgets.dart';

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final _controller = TextEditingController(text: 'Hello from the RunAnywhere NPU runtime.');
  bool _running = false;
  String? _error;
  String _duration = '—';
  String _rate = '—';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    setState(() {
      _error = null;
      _running = true;
    });
    try {
      final r = await RunAnywhere.tts.speak(_controller.text);
      setState(() {
        _duration = '${r.durationMs} ms';
        _rate = r.sampleRate > 0 ? '${r.sampleRate} Hz' : '—';
      });
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
      appBar: AppBar(title: const Text('Text to Speech')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_running,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Text', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _running ? null : _speak,
                child: Text(_running ? 'Speaking…' : 'Speak'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => RunAnywhere.tts.stopSpeaking(),
                child: const Text('Stop'),
              ),
            ),
            const SizedBox(height: 16),
            MetricStrip([('duration', _duration), ('sample rate', _rate)]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: 'Text to Speech',
              child: Text(
                'Synthesizes on-device and plays through the speaker. MeloTTS on NPU.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
