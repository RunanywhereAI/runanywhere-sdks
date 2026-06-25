/**
 * Models - the NPU (QHexRT) catalog. Each entry is a Google-Drive-hosted ZIP
 * bundle; Download registers it as a ZIP archive and the SDK downloads +
 * extracts it into the standard model dir, then loads it like any other model.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space, Radius } from '../theme';
import { Screen, PrimaryButton, StatusPill } from '../widgets';
import { NPU_MODELS, driveZipUrl, type NpuModel } from '../npuCatalog';
import { RunAnywhere } from '@runanywhere/core';
import {
  ArchiveType,
  ArchiveStructure,
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';

type Props = NativeStackScreenProps<NpuStackParamList, 'Models'>;

// QHexRT framework wire value (proto INFERENCE_FRAMEWORK_QHEXRT = 24); passed
// numerically because @runanywhere/proto-ts is not yet regenerated with it.
const FRAMEWORK_QHEXRT = 24;

const modalityCategory = (m: NpuModel): ModelCategory =>
  m.modality === 'vlm' ? ModelCategory.MODEL_CATEGORY_MULTIMODAL : ModelCategory.MODEL_CATEGORY_LANGUAGE;

const ModelsScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [downloaded, setDownloaded] = useState<Set<string>>(new Set());
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await RunAnywhere.listModels();
      const list = (res?.models?.models ?? []) as Array<{ id: string; isDownloaded?: boolean; localPath?: string }>;
      setDownloaded(new Set(list.filter((m) => m.isDownloaded || m.localPath).map((m) => m.id)));
    } catch {
      /* registry unreachable — rows render as not-downloaded */
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const act = async (m: NpuModel) => {
    if (!m.driveId) {
      setError(`${m.name}: download link not configured yet.`);
      return;
    }
    setBusyId(m.id);
    setError(null);
    try {
      if (!downloaded.has(m.id)) {
        await RunAnywhere.registerArchiveModel({
          id: m.id,
          name: m.name,
          url: driveZipUrl(m.driveId),
          framework: FRAMEWORK_QHEXRT,
          modality: modalityCategory(m),
          archiveType: ArchiveType.ARCHIVE_TYPE_ZIP,
          structure: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
        });
        const dl = RunAnywhere.downloadModel(m.id)[Symbol.asyncIterator]();
        let r = await dl.next();
        while (!r.done) r = await dl.next();
      }
      await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({ modelId: m.id, category: modalityCategory(m) })
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
      <Text style={[styles.count, { color: c.onSurfaceVariant }]}>
        {NPU_MODELS.length} NPU bundles
      </Text>

      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}

      {NPU_MODELS.map((m) => {
        const have = downloaded.has(m.id);
        const pending = !m.driveId;
        return (
          <View key={m.id} style={[styles.row, { backgroundColor: c.surface, borderColor: c.outline }]}>
            <View style={{ flex: 1, paddingRight: Space.md }}>
              <Text style={[styles.name, { color: c.onSurface }]} numberOfLines={1}>
                {m.name}
              </Text>
              <Text style={[styles.detail, { color: c.onSurfaceVariant }]} numberOfLines={1}>
                {m.detail}
              </Text>
              <View style={{ height: 6 }} />
              <StatusPill
                label={have ? 'Downloaded' : pending ? 'Link pending' : m.modality.toUpperCase()}
                tone={have ? 'ok' : pending ? 'warn' : 'neutral'}
              />
            </View>
            <View style={{ width: 130 }}>
              <PrimaryButton
                label={have ? 'Load' : 'Download'}
                onPress={() => act(m)}
                busy={busyId === m.id}
                disabled={pending}
              />
            </View>
          </View>
        );
      })}
    </Screen>
  );
};

const styles = StyleSheet.create({
  count: { fontSize: 13, fontWeight: '600', marginBottom: Space.lg },
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
