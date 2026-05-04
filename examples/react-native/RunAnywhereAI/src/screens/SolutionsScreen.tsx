/**
 * SolutionsScreen — Wave 3 Step 3.3 (G-E6) demo for
 * `RunAnywhere.solutions.run({ yaml })`.
 *
 * Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
 * shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
 * embedded inline as string constants (no asset-bundling churn). Each
 * lifecycle transition is appended to a simple scrolling log.
 */
import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  Button,
  ScrollView,
  StyleSheet,
  SafeAreaView,
} from 'react-native';
import { RunAnywhere } from '@runanywhere/core';

const VOICE_AGENT_YAML = `voice_agent:
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
`;

const RAG_YAML = `rag:
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
`;

export const SolutionsScreen: React.FC = () => {
  const [log, setLog] = useState<string[]>([]);
  const [isRunning, setIsRunning] = useState(false);

  const append = useCallback((line: string) => {
    setLog((prev) => [...prev, line]);
  }, []);

  const runSolution = useCallback(
    async (name: string, yaml: string) => {
      if (isRunning) return;
      setIsRunning(true);
      append(`-> ${name}: creating solution from YAML...`);
      try {
        const handle = await RunAnywhere.solutions.run({ yaml });
        append(`OK ${name}: handle created. Calling start()...`);
        await handle.start();
        append(`OK ${name}: started. Tearing down (demo).`);
        await handle.destroy();
        append(`OK ${name}: destroyed.`);
      } catch (err) {
        append(`ERR ${name}: ${(err as Error).message}`);
      } finally {
        setIsRunning(false);
      }
    },
    [isRunning, append],
  );

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.intro}>
        Run a prepackaged pipeline (voice agent or RAG) by handing a YAML
        config to RunAnywhere.solutions.run.
      </Text>
      <View style={styles.buttonRow}>
        <View style={styles.buttonWrap}>
          <Button
            title="Voice Agent"
            disabled={isRunning}
            onPress={() => runSolution('Voice Agent', VOICE_AGENT_YAML)}
          />
        </View>
        <View style={styles.buttonWrap}>
          <Button
            title="RAG"
            disabled={isRunning}
            onPress={() => runSolution('RAG', RAG_YAML)}
          />
        </View>
      </View>
      <ScrollView style={styles.logBox} contentContainerStyle={styles.logContent}>
        {log.map((line, i) => (
          <Text key={i} style={styles.logLine}>
            {line}
          </Text>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  intro: { fontSize: 14, marginBottom: 16 },
  buttonRow: { flexDirection: 'row', gap: 12, marginBottom: 16 },
  buttonWrap: { flex: 1 },
  logBox: { flex: 1, backgroundColor: '#f4f4f4', borderRadius: 8 },
  logContent: { padding: 8 },
  logLine: { fontFamily: 'Menlo', fontSize: 12 },
});

export default SolutionsScreen;
