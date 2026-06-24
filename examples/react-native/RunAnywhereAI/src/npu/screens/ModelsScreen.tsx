/**
 * Models - the curated NPU (QHexRT) catalog from `runanywhere/genie-npu-models`
 * (Hugging Face, npu-tagged). Lists only NPU Hexagon bundles — not the generic
 * SDK registry — and wires download + load through the core SDK.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space, Radius } from '../theme';
import { Screen, PrimaryButton, StatusPill } from '../widgets';
import { NPU_MODELS, formatBytes, type NpuModel } from '../npuCatalog';
import { RunAnywhere } from '@runanywhere/core';
import { ModelCategory, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';

type Props = NativeStackScreenProps<NpuStackParamList, 'Models'>;

// QHexRT framework wire value (proto INFERENCE_FRAMEWORK_QHEXRT = 24). Passed
// numerically because @runanywhere/proto-ts is not yet regenerated with the
// QHEXRT enum member.
const FRAMEWORK_QHEXRT = 24;

const ModelsScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [downloaded, setDownloaded] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await RunAnywhere.listModels();
      const list = (res?.models?.models ?? []) as Array<{
        id: string;
        isDownloaded?: boolean;
        localPath?: string;
      }>;
      const have = new Set(list.filter((m) => m.isDownloaded || m.localPath).map((m) => m.id));
      setDownloaded(have);
    } catch {
      // Registry not reachable — the catalog still renders as "not downloaded".
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const act = async (m: NpuModel) => {
    setBusyId(m.id);
    setError(null);
    try {
      if (!downloaded.has(m.id)) {
        await RunAnywhere.registerModel({
          id: m.id,
          name: m.name,
          url: m.url,
          framework: FRAMEWORK_QHEXRT,
          memoryRequirement: m.sizeBytes,
        });
        const dl = RunAnywhere.downloadModel(m.id)[Symbol.asyncIterator]();
        let r = await dl.next();
        while (!r.done) r = await dl.next();
      }
      await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({ modelId: m.id, category: ModelCategory.MODEL_CATEGORY_LANGUAGE })
      );
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Screen title="NPU Models" onBack={() => navigation.goBack()}>
      <View style={styles.headerRow}>
        <Text style={[styles.count, { color: c.onSurfaceVariant }]}>
          {NPU_MODELS.length} NPU bundles · runanywhere/genie-npu-models
        </Text>
        {loading ? <ActivityIndicator color={c.primary} /> : null}
      </View>

      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}

      {NPU_MODELS.map((m) => {
        const have = downloaded.has(m.id);
        return (
          <View key={m.id} style={[styles.row, { backgroundColor: c.surface, borderColor: c.outline }]}>
            <View style={{ flex: 1, paddingRight: Space.md }}>
              <Text style={[styles.name, { color: c.onSurface }]} numberOfLines={1}>
                {m.name}
              </Text>
              <Text style={[styles.detail, { color: c.onSurfaceVariant }]} numberOfLines={1}>
                {m.detail} · {formatBytes(m.sizeBytes)}
              </Text>
              <View style={{ height: 6 }} />
              <StatusPill label={have ? 'Downloaded' : 'NPU'} tone={have ? 'ok' : 'neutral'} />
            </View>
            <View style={{ width: 130 }}>
              <PrimaryButton
                label={have ? 'Load' : 'Download'}
                onPress={() => act(m)}
                busy={busyId === m.id}
              />
            </View>
          </View>
        );
      })}
    </Screen>
  );
};

const styles = StyleSheet.create({
  headerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: Space.md, marginBottom: Space.lg },
  count: { fontSize: 13, fontWeight: '600', flex: 1 },
  error: { fontSize: 13, marginBottom: Space.md },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: Radius.lg,
    padding: Space.lg,
    marginBottom: Space.md,
  },
  name: { fontSize: 15, fontWeight: '700' },
  detail: { fontSize: 12, marginTop: 2 },
});

export default ModelsScreen;
