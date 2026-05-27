/**
 * SolutionsScreen — Wave 3 Step 3.3 (G-E6) demo for
 * `RunAnywhere.solutions.run({ yaml })`.
 *
 * Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
 * shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
 * synced from the commons sources via `scripts/sync-solutions-yamls.js`
 * (runs on postinstall + before typecheck), so this screen never embeds
 * a hand-edited YAML literal. Each lifecycle transition is appended to a
 * simple scrolling log.
 */
import React, { useState, useCallback } from 'react';
import { View, Text, Button, ScrollView, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { RunAnywhere } from '@runanywhere/core';
import {
  VOICE_AGENT_YAML,
  RAG_YAML,
} from '../generated/solutionsYaml';

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
    [isRunning, append]
  );

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.intro}>
        Run a prepackaged pipeline (voice agent or RAG) by handing a YAML config
        to RunAnywhere.solutions.run.
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
      <ScrollView
        style={styles.logBox}
        contentContainerStyle={styles.logContent}
      >
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
