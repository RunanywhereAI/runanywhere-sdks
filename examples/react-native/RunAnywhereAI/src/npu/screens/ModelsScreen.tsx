/**
 * Models — the NPU (QHexRT) catalog of public HuggingFace multi-file bundles.
 *
 * Rows are filtered to the Hexagon architecture probed on the device (a v81
 * phone only sees v81 bundles), then grouped by modality. Download registers a
 * multi-file model with the QHexRT framework and streams the bundle; Load pulls
 * it into memory for the matching modality screen.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, PrimaryButton, StatusPill, SectionCard } from '../widgets';
import {
  NPU_MODELS,
  modalityCategory,
  modalityLabel,
  type NpuModel,
  type NpuModality,
} from '../npuCatalog';
import { RunAnywhere } from '@runanywhere/core';
import { InferenceFramework, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
import {
  QHexRT,
  hexagonArchName,
  HexagonArch,
  UNKNOWN_NPU_INFO,
  type NpuInfo,
} from '@runanywhere/qhexrt';

type Props = NativeStackScreenProps<NpuStackParamList, 'Models'>;

const MODALITY_ORDER: NpuModality[] = ['llm', 'vlm', 'stt', 'tts'];

const ModelsScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [npu, setNpu] = useState<NpuInfo>(UNKNOWN_NPU_INFO);
  const [downloaded, setDownloaded] = useState<Set<string>>(new Set());
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await RunAnywhere.listModels();
      const list = (res?.models?.models ?? []) as Array<{
        id: string;
        isDownloaded?: boolean;
        localPath?: string;
      }>;
      setDownloaded(new Set(list.filter((m) => m.isDownloaded || m.localPath).map((m) => m.id)));
    } catch {
      /* registry unreachable — rows render as not-downloaded */
    }
  }, []);

  useEffect(() => {
    let alive = true;
    (async () => {
      const probed = await QHexRT.probeNpu();
      if (!alive) return;
      setNpu(probed);
    })();
    refresh();
    return () => {
      alive = false;
    };
  }, [refresh]);

  const act = async (m: NpuModel) => {
    setBusyId(m.id);
    setError(null);
    try {
      if (!downloaded.has(m.id)) {
        const info = await RunAnywhere.registerMultiFileModel({
          id: m.id,
          name: m.name,
          files: m.files.map((f) => ({ url: f.url, filename: f.filename, isRequired: true })),
          framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
          modality: modalityCategory(m.modality),
        });
        await RunAnywhere.downloadModel(info);
      }
      await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({ modelId: m.id, category: modalityCategory(m.modality) })
      );
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  };

  // Arch filtering: a QHexRT bundle is compiled for an exact Hexagon arch, so
  // only show bundles that match the probed device. When the probe is unknown
  // (non-Snapdragon / unsupported), show everything so the catalog is still
  // browsable.
  const archName = hexagonArchName(npu.hexagonArch);
  const archKnown = npu.hexagonArch !== HexagonArch.Unknown;
  const visible = archKnown ? NPU_MODELS.filter((m) => m.arch === archName) : NPU_MODELS;

  return (
    <Screen title="NPU Models" onBack={() => navigation.goBack()}>
      <Text style={[styles.count, { color: c.onSurfaceVariant }]}>
        {visible.length} bundles{archKnown ? ` for Hexagon ${archName}` : ' (all architectures)'}
      </Text>

      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}

      {MODALITY_ORDER.map((modality) => {
        const rows = visible.filter((m) => m.modality === modality);
        if (rows.length === 0) return null;
        return (
          <SectionCard key={modality} title={modalityLabel(modality)}>
            {rows.map((m) => {
              const have = downloaded.has(m.id);
              return (
                <View
                  key={m.id}
                  style={[styles.row, { borderColor: c.outline }]}
                >
                  <View style={{ flex: 1, paddingRight: Space.md }}>
                    <Text style={[styles.name, { color: c.onSurface }]} numberOfLines={1}>
                      {m.name}
                    </Text>
                    <Text style={[styles.detail, { color: c.onSurfaceVariant }]} numberOfLines={1}>
                      {m.detail}
                    </Text>
                    <View style={{ height: 6 }} />
                    <StatusPill
                      label={have ? 'Downloaded' : m.modality.toUpperCase()}
                      tone={have ? 'ok' : 'neutral'}
                    />
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
          </SectionCard>
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
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingVertical: Space.md,
  },
  name: { fontSize: 15, fontWeight: '700' },
  detail: { fontSize: 12, marginTop: 2 },
});

export default ModelsScreen;
