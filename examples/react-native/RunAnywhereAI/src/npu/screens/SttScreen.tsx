/**
 * Speech-to-Text - transcribe audio on the NPU.
 *
 * Live microphone capture is intentionally out of scope for this demo; the
 * screen exercises the transcription path on a generated 1-second test clip so
 * the SDK round-trip is real. Until an NPU STT model is loaded this surfaces a
 * graceful "no model" error rather than a transcript.
 */
import React, { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, SectionCard, PrimaryButton } from '../widgets';
import { RunAnywhere } from '@runanywhere/core';

type Props = NativeStackScreenProps<NpuStackParamList, 'Stt'>;

/** Build a 1-second 16 kHz mono 16-bit PCM WAV of silence. */
function silentWav(seconds = 1, sampleRate = 16000): Uint8Array {
  const samples = seconds * sampleRate;
  const dataLen = samples * 2;
  const buf = new ArrayBuffer(44 + dataLen);
  const v = new DataView(buf);
  const w = (off: number, s: string) => {
    for (let i = 0; i < s.length; i++) v.setUint8(off + i, s.charCodeAt(i));
  };
  w(0, 'RIFF');
  v.setUint32(4, 36 + dataLen, true);
  w(8, 'WAVE');
  w(12, 'fmt ');
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, sampleRate, true);
  v.setUint32(28, sampleRate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  w(36, 'data');
  v.setUint32(40, dataLen, true);
  return new Uint8Array(buf);
}

const SttScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [running, setRunning] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);

  const transcribe = async () => {
    setRunning(true);
    setError(null);
    setTranscript('');
    try {
      const result = await RunAnywhere.transcribe(silentWav());
      setTranscript(result?.text || '(no speech detected)');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  };

  return (
    <Screen title="Speech-to-Text" onBack={() => navigation.goBack()}>
      <SectionCard title="About">
        <Text style={{ color: c.onSurfaceVariant, fontSize: 14, lineHeight: 20 }}>
          Transcribes audio with an NPU STT model. This demo runs a 1-second test clip through the
          SDK; load an STT bundle from the Models screen for real transcription.
        </Text>
      </SectionCard>
      <PrimaryButton label={running ? 'Transcribing…' : 'Transcribe test clip'} onPress={transcribe} busy={running} />
      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
      <View style={{ height: Space.lg }} />
      <SectionCard title="Transcript">
        <Text style={{ color: transcript ? c.onSurface : c.onSurfaceVariant, fontSize: 15, lineHeight: 22 }}>
          {transcript || (running ? '…' : 'Transcript appears here.')}
        </Text>
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  error: { fontSize: 13, marginTop: Space.md },
});

export default SttScreen;
