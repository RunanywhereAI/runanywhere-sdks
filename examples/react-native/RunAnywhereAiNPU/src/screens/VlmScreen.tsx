/**
 * Vision (VLM) - ask a question about an image, answered on the NPU.
 */
import React, { useState } from 'react';
import { View, Text, Image, StyleSheet, TouchableOpacity } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { launchImageLibrary } from 'react-native-image-picker';

import { RootStackParamList } from '../../App';
import { useAppColors, Space, Radius } from '../theme';
import { Screen, SectionCard, Field, PrimaryButton } from '../widgets';
import { RunAnywhere } from '@runanywhere/core';
import { VLMGenerationOptions } from '@runanywhere/proto-ts/vlm_options';

type Props = NativeStackScreenProps<RootStackParamList, 'Vlm'>;

const VlmScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [imageUri, setImageUri] = useState<string | null>(null);
  const [prompt, setPrompt] = useState('Describe this image.');
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pickImage = async () => {
    const res = await launchImageLibrary({ mediaType: 'photo', selectionLimit: 1 });
    const uri = res.assets?.[0]?.uri;
    if (uri) {
      setImageUri(uri);
      setOutput('');
      setError(null);
    }
  };

  const describe = async () => {
    if (!imageUri) return;
    setRunning(true);
    setError(null);
    setOutput('');
    try {
      const stream = await RunAnywhere.processImageStream(
        imageUri,
        prompt,
        VLMGenerationOptions.fromPartial({ prompt, maxTokens: 256, streamingEnabled: true })
      );
      const iter = stream[Symbol.asyncIterator]();
      let acc = '';
      let r = await iter.next();
      while (!r.done) {
        const ev = r.value;
        if (ev.token) {
          acc += ev.token;
          setOutput(acc);
        }
        if (ev.result) break;
        r = await iter.next();
      }
      if (!acc) setOutput('(no output)');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  };

  return (
    <Screen title="Vision" onBack={() => navigation.goBack()}>
      <TouchableOpacity
        activeOpacity={0.85}
        onPress={pickImage}
        style={[styles.picker, { borderColor: c.outline, backgroundColor: c.surface }]}
      >
        {imageUri ? (
          <Image source={{ uri: imageUri }} style={styles.image} resizeMode="cover" />
        ) : (
          <Text style={{ color: c.onSurfaceVariant }}>Tap to choose an image</Text>
        )}
      </TouchableOpacity>

      <View style={{ height: Space.lg }} />
      <Field value={prompt} onChangeText={setPrompt} editable={!running} placeholder="Ask about the image" />
      <View style={{ height: Space.lg }} />
      <PrimaryButton
        label={running ? 'Analyzing…' : 'Describe'}
        onPress={describe}
        busy={running}
        disabled={!imageUri}
      />
      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
      <View style={{ height: Space.lg }} />
      <SectionCard title="Answer">
        <Text style={{ color: output ? c.onSurface : c.onSurfaceVariant, fontSize: 15, lineHeight: 22 }}>
          {output || (running ? '…' : 'Pick an image and load an NPU VLM model from the Models screen.')}
        </Text>
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  picker: {
    height: 220,
    borderRadius: Radius.lg,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  image: { width: '100%', height: '100%' },
  error: { fontSize: 13, marginTop: Space.md },
});

export default VlmScreen;
