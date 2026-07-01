/**
 * Chat (LLM) - streaming text generation on the NPU.
 */
import React, { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, SectionCard, Field, PrimaryButton, MetricStrip } from '../widgets';
import NpuModelBar from '../NpuModelBar';
import { RunAnywhere } from '@runanywhere/core';
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';

type Props = NativeStackScreenProps<NpuStackParamList, 'Llm'>;

const LlmScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [prompt, setPrompt] = useState('Explain what an NPU is in one sentence.');
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tps, setTps] = useState('—');
  const [ttft, setTtft] = useState('—');
  const [modelLoaded, setModelLoaded] = useState(false);

  const generate = async () => {
    setRunning(true);
    setError(null);
    setOutput('');
    setTps('—');
    setTtft('—');
    try {
      const events = RunAnywhere.generateStream(
        prompt,
        LLMGenerationOptions.fromPartial({ maxTokens: 256, temperature: 0.7 })
      );
      const result = await RunAnywhere.aggregateStream(prompt, events, async (transcript: string) => {
        setOutput(transcript);
      });
      setOutput(result.text || '(no output)');
      if (typeof result.tokensPerSecond === 'number') setTps(result.tokensPerSecond.toFixed(1));
      if (typeof result.ttftMs === 'number') setTtft(`${Math.round(result.ttftMs)} ms`);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  };

  return (
    <Screen title="Chat" onBack={() => navigation.goBack()}>
      <NpuModelBar modality="llm" onLoadedChange={(id) => setModelLoaded(!!id)} />
      <Field
        value={prompt}
        onChangeText={setPrompt}
        editable={!running}
        multiline
        numberOfLines={3}
        placeholder="Prompt"
        style={styles.prompt}
      />
      <PrimaryButton
        label={running ? 'Generating…' : modelLoaded ? 'Generate' : 'Load a model to generate'}
        onPress={generate}
        busy={running}
        disabled={!modelLoaded}
      />
      <View style={{ height: Space.lg }} />
      <MetricStrip items={[['tokens/s', tps], ['ttft', ttft]]} />
      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
      <SectionCard title="Response">
        <Text style={{ color: output ? c.onSurface : c.onSurfaceVariant, fontSize: 15, lineHeight: 22 }}>
          {output || (running ? '…' : 'Output appears here. Load an NPU LLM model above first.')}
        </Text>
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  prompt: { minHeight: 90, textAlignVertical: 'top', marginBottom: Space.lg },
  error: { fontSize: 13, marginTop: Space.md },
});

export default LlmScreen;
