/**
 * NpuModelBar — inline model picker shown at the top of each NPU modality
 * screen (Chat / Vision / STT / TTS).
 *
 * Mirrors the Android `NpuModelBar`: a compact card that shows the model
 * currently resident in NPU memory for the screen's modality and expands to a
 * list of arch-matching bundles with Download / Load / In-memory states and
 * live download progress. This replaces the standalone Models tab — each
 * modality screen now self-serves its own download + load.
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator } from 'react-native';

import { useAppColors, Space, Radius } from './theme';
import { StatusPill, PrimaryButton } from './widgets';
import {
  NPU_MODELS,
  modalityCategory,
  modalityLabel,
  type NpuModel,
  type NpuModality,
} from './npuCatalog';
import { RunAnywhere } from '@runanywhere/core';
import { InferenceFramework, ModelFileRole, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { QHexRT, hexagonArchName, HexagonArch, UNKNOWN_NPU_INFO, type NpuInfo } from '@runanywhere/qhexrt';

type Props = {
  modality: NpuModality;
  /** Notifies the host screen when a model becomes resident (enables inference). */
  onLoadedChange?: (modelId: string | null) => void;
};

const NpuModelBar: React.FC<Props> = ({ modality, onLoadedChange }) => {
  const c = useAppColors();
  const [npu, setNpu] = useState<NpuInfo>(UNKNOWN_NPU_INFO);
  const [downloaded, setDownloaded] = useState<Set<string>>(new Set());
  const [loadedId, setLoadedId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [progress, setProgress] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);

  // Hold the latest onLoadedChange in a ref so refresh()/act() can notify the
  // host without taking the (per-render, unstable) callback as a dependency —
  // which would otherwise re-fire the mount effect on every parent render.
  const onLoadedChangeRef = useRef(onLoadedChange);
  useEffect(() => {
    onLoadedChangeRef.current = onLoadedChange;
  });

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
    try {
      // Reflect a model already resident in NPU memory for this modality (e.g.
      // loaded in a previous visit) so the host screen enables inference
      // without forcing a redundant Load tap. Mirrors the Android
      // NpuModelsViewModel.reload() loadedByModality probe.
      const current = await RunAnywhere.modelInfoForCategory(modalityCategory(modality));
      const id = current?.id ?? null;
      setLoadedId(id);
      onLoadedChangeRef.current?.(id);
    } catch {
      /* lifecycle unreachable — leave loaded state as-is */
    }
  }, [modality]);

  useEffect(() => {
    let alive = true;
    (async () => {
      const probed = await QHexRT.probeNpu();
      if (alive) setNpu(probed);
    })();
    refresh();
    return () => {
      alive = false;
    };
  }, [refresh]);

  // QHexRT bundles are compiled for an exact Hexagon arch, so only show the
  // bundles that match the probed device. Unknown arch (unsupported device)
  // falls back to showing all so the catalog is still browsable.
  const archName = hexagonArchName(npu.hexagonArch);
  const archKnown = npu.hexagonArch !== HexagonArch.Unknown;
  const models = NPU_MODELS.filter(
    (m) => m.modality === modality && (!archKnown || m.arch === archName)
  );
  const loaded = models.find((m) => m.id === loadedId) ?? null;

  const act = async (m: NpuModel) => {
    setBusyId(m.id);
    setError(null);
    setProgress(0);
    try {
      if (!downloaded.has(m.id)) {
        const info = await RunAnywhere.registerMultiFileModel({
          id: m.id,
          name: m.name,
          // The catalog authors the QHexRT manifest (`.json`) as the first file;
          // pin it as PRIMARY so commons loads it as the entry point (the
          // filename heuristic would otherwise pick a `.bin` weight). Mirrors
          // the Android NpuModelsViewModel registration.
          files: m.files.map((f, idx) => ({
            url: f.url,
            filename: f.filename,
            isRequired: true,
            role:
              idx === 0
                ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                : ModelFileRole.MODEL_FILE_ROLE_COMPANION,
          })),
          framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
          modality: modalityCategory(m.modality),
        });
        await RunAnywhere.downloadModel(info, (p: DownloadProgress) => {
          const pct = p.overallProgress > 0 ? p.overallProgress : p.stageProgress;
          if (typeof pct === 'number') setProgress(pct);
        });
        await refresh();
      }
      await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({ modelId: m.id, category: modalityCategory(m.modality) })
      );
      setLoadedId(m.id);
      onLoadedChangeRef.current?.(m.id);
      setExpanded(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
      setProgress(0);
    }
  };

  return (
    <View style={[styles.card, { backgroundColor: c.surface, borderColor: c.outline }]}>
      <TouchableOpacity activeOpacity={0.85} onPress={() => setExpanded((v) => !v)} style={styles.header}>
        <View style={{ flex: 1, paddingRight: Space.md }}>
          <Text style={[styles.title, { color: c.onSurface }]} numberOfLines={1}>
            {loaded ? loaded.name : 'Select a model'}
          </Text>
          <Text style={[styles.sub, { color: c.onSurfaceVariant }]} numberOfLines={1}>
            {loaded ? loaded.detail : `Tap to download or load a ${modalityLabel(modality)} model`}
          </Text>
        </View>
        <StatusPill label={loaded ? 'Loaded' : 'Choose'} tone={loaded ? 'ok' : 'neutral'} />
      </TouchableOpacity>

      {expanded ? (
        <View style={styles.list}>
          {!archKnown && (
            <Text style={[styles.note, { color: c.onSurfaceVariant }]}>
              NPU not detected — showing all architectures.
            </Text>
          )}
          {models.length === 0 ? (
            <Text style={[styles.note, { color: c.onSurfaceVariant }]}>
              No {modalityLabel(modality)} model available for Hexagon {archName} yet.
            </Text>
          ) : (
            models.map((m) => {
              const have = downloaded.has(m.id);
              const isBusy = busyId === m.id;
              const isLoaded = loadedId === m.id;
              return (
                <View key={m.id} style={[styles.row, { borderTopColor: c.outline }]}>
                  <View style={{ flex: 1, paddingRight: Space.md }}>
                    <Text style={[styles.name, { color: c.onSurface }]} numberOfLines={1}>
                      {m.name}
                    </Text>
                    <Text style={[styles.detail, { color: c.onSurfaceVariant }]} numberOfLines={1}>
                      {m.detail}
                    </Text>
                  </View>
                  <View style={{ width: 120, alignItems: 'flex-end' }}>
                    {isLoaded ? (
                      <Text style={[styles.inMemory, { color: c.success }]}>In memory</Text>
                    ) : isBusy ? (
                      <View style={{ alignItems: 'center' }}>
                        <ActivityIndicator color={c.primary} />
                        {!have ? (
                          <Text style={[styles.pct, { color: c.primary }]}>
                            {Math.round(progress * 100)}%
                          </Text>
                        ) : null}
                      </View>
                    ) : (
                      <PrimaryButton
                        label={have ? 'Load' : 'Download'}
                        onPress={() => act(m)}
                        disabled={busyId !== null}
                      />
                    )}
                  </View>
                </View>
              );
            })
          )}
          {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
        </View>
      ) : null}
    </View>
  );
};

const styles = StyleSheet.create({
  card: { borderRadius: Radius.lg, borderWidth: 1, padding: Space.lg, marginBottom: Space.lg },
  header: { flexDirection: 'row', alignItems: 'center' },
  title: { fontSize: 15, fontWeight: '700' },
  sub: { fontSize: 12, marginTop: 2 },
  list: { marginTop: Space.md },
  note: { fontSize: 13, paddingVertical: Space.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingVertical: Space.md,
  },
  name: { fontSize: 15, fontWeight: '600' },
  detail: { fontSize: 12, marginTop: 2 },
  inMemory: { fontSize: 14, fontWeight: '700' },
  pct: { fontSize: 12, fontWeight: '700', marginTop: 4, fontVariant: ['tabular-nums'] },
  error: { fontSize: 13, marginTop: Space.md },
});

export default NpuModelBar;
