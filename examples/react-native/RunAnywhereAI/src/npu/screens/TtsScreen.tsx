/**
 * Text-to-Speech - synthesize speech on the NPU.
 */
import React, { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, SectionCard, Field, PrimaryButton } from '../widgets';
import NpuModelBar from '../NpuModelBar';
import { RunAnywhere } from '@runanywhere/core';

type Props = NativeStackScreenProps<NpuStackParamList, 'Tts'>;

const TtsScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [text, setText] = useState('Hello from the Hexagon NPU.');
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [modelLoaded, setModelLoaded] = useState(false);

  const speak = async () => {
    setRunning(true);
    setError(null);
    setStatus(null);
    try {
      await RunAnywhere.speak(text);
      setStatus('Playback finished.');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  };

  const stop = async () => {
    try {
      await RunAnywhere.stopSpeaking();
    } catch {
      // ignore
    }
  };

  return (
    <Screen title="Text-to-Speech" onBack={() => navigation.goBack()}>
      <NpuModelBar modality="tts" onLoadedChange={(id) => setModelLoaded(!!id)} />
      <Field
        value={text}
        onChangeText={setText}
        editable={!running}
        multiline
        numberOfLines={3}
        placeholder="Text to speak"
        style={styles.input}
      />
      <PrimaryButton
        label={running ? 'Speaking…' : modelLoaded ? 'Speak' : 'Load a model to speak'}
        onPress={speak}
        busy={running}
        disabled={!modelLoaded}
      />
      <View style={{ height: Space.sm }} />
      <PrimaryButton label="Stop" onPress={stop} disabled={!running} />
      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
      <View style={{ height: Space.lg }} />
      <SectionCard title="Status">
        <Text style={{ color: c.onSurfaceVariant, fontSize: 14, lineHeight: 20 }}>
          {status || 'Load an NPU TTS model above, then synthesize speech.'}
        </Text>
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  input: { minHeight: 90, textAlignVertical: 'top', marginBottom: Space.lg },
  error: { fontSize: 13, marginTop: Space.md },
});

export default TtsScreen;
