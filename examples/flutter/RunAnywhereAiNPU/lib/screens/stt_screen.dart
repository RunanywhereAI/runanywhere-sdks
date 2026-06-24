import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../widgets.dart';

class SttScreen extends StatefulWidget {
  const SttScreen({super.key});

  @override
  State<SttScreen> createState() => _SttScreenState();
}

class _SttScreenState extends State<SttScreen> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _running = false;
  String _text = '';
  String? _error;
  String _conf = '—';
  String? _path;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      setState(() => _recording = false);
      final path = await _recorder.stop();
      if (path != null) await _transcribe(path);
      return;
    }
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission denied');
      return;
    }
    _path = '${Directory.systemTemp.path}/stt_${DateTime.now().millisecondsSinceEpoch}.pcm';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      path: _path!,
    );
    setState(() {
      _error = null;
      _recording = true;
    });
  }

  Future<void> _transcribe(String path) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final out = await RunAnywhere.stt.transcribe(bytes, ra.STTOptions(sampleRate: 16000));
      setState(() {
        _text = out.text;
        _conf = '${(out.confidence * 100).toStringAsFixed(0)}%';
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
      appBar: AppBar(title: const Text('Speech to Text')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _running ? null : _toggle,
                child: Text(_recording
                    ? 'Stop & transcribe'
                    : _running
                        ? 'Transcribing…'
                        : 'Record'),
              ),
            ),
            const SizedBox(height: 16),
            MetricStrip([('confidence', _conf), ('sample rate', '16 kHz')]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: 'Transcript',
              child: Text(
                _text.isEmpty ? (_recording ? 'Listening…' : 'Tap Record and speak.') : _text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _text.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
