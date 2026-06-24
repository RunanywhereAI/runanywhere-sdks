/**
 * Models - list, download, and load on-device model bundles.
 *
 * NOTE: No QHexRT/NPU model bundles are published yet, so the catalog is
 * typically empty until links land in the npu-forge HuggingFace repo. The
 * download/load flow is wired and ready for when they do.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { RootStackParamList } from '../../App';
import { useAppColors, Space, Radius } from '../theme';
import { Screen, SectionCard, PrimaryButton, StatusPill } from '../widgets';
import { RunAnywhere } from '@runanywhere/core';
import { ModelCategory, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';

type Props = NativeStackScreenProps<RootStackParamList, 'Models'>;

interface ModelRow {
  id: string;
  name: string;
  framework?: number;
  isDownloaded?: boolean;
  localPath?: string;
  category?: number;
}

const ModelsScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [loading, setLoading] = useState(true);
  const [models, setModels] = useState<ModelRow[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await RunAnywhere.listModels();
      const list = (res?.models?.models ?? []) as ModelRow[];
      setModels(list);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const act = async (m: ModelRow) => {
    setBusyId(m.id);
    setError(null);
    try {
      if (!m.isDownloaded && !m.localPath) {
        const dl = RunAnywhere.downloadModel(m.id)[Symbol.asyncIterator]();
        let r = await dl.next();
        while (!r.done) r = await dl.next();
      }
      await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({
          modelId: m.id,
          category: m.category ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
        })
      );
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Screen title="Models" onBack={() => navigation.goBack()}>
      <View style={styles.headerRow}>
        <Text style={[styles.count, { color: c.onSurfaceVariant }]}>
          {loading ? 'Loading…' : `${models.length} model${models.length === 1 ? '' : 's'}`}
        </Text>
        <PrimaryButton label="Refresh" onPress={refresh} disabled={loading} />
      </View>

      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}

      {loading ? (
        <ActivityIndicator color={c.primary} style={{ marginTop: Space.xl }} />
      ) : models.length === 0 ? (
        <SectionCard>
          <Text style={{ color: c.onSurfaceVariant, fontSize: 14, lineHeight: 20 }}>
            No model bundles available yet. NPU (QHexRT) bundles will appear here once published.
          </Text>
        </SectionCard>
      ) : (
        models.map((m) => (
          <View key={m.id} style={[styles.row, { backgroundColor: c.surface, borderColor: c.outline }]}>
            <View style={{ flex: 1, paddingRight: Space.md }}>
              <Text style={[styles.name, { color: c.onSurface }]} numberOfLines={1}>
                {m.name || m.id}
              </Text>
              <View style={{ height: 6 }} />
              <StatusPill
                label={m.isDownloaded || m.localPath ? 'Downloaded' : 'Not downloaded'}
                tone={m.isDownloaded || m.localPath ? 'ok' : 'neutral'}
              />
            </View>
            <View style={{ width: 130 }}>
              <PrimaryButton
                label={m.isDownloaded || m.localPath ? 'Load' : 'Download'}
                onPress={() => act(m)}
                busy={busyId === m.id}
              />
            </View>
          </View>
        ))
      )}
    </Screen>
  );
};

const styles = StyleSheet.create({
  headerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: Space.md, marginBottom: Space.lg },
  count: { fontSize: 14, fontWeight: '600' },
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
});

export default ModelsScreen;
