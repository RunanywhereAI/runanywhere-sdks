/**
 * NPU (QHexRT) — Qualcomm Hexagon NPU detection + status.
 *
 * Runs the pre-flight capability probe (no QNN load), shows whether the device
 * is supported (Hexagon v79/v81), reports backend registration, and links into
 * the existing modality screens — which route through QHexRT once a QHexRT
 * model is loaded.
 */
import React, { useEffect, useState } from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  ActivityIndicator,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, useTheme } from '../theme/system';
import type { IconName } from '../theme/system/icons';
import { ROUTES } from '../navigation/routes';
import type { RootStackParamList } from '../navigation/navigation.types';

import {
  QHexRT,
  HexagonArch,
  hexagonArchName,
  UNKNOWN_NPU_INFO,
  type NpuInfo,
} from '@runanywhere/qhexrt';

type Nav = NativeStackNavigationProp<RootStackParamList>;

const MODALITIES: { label: string; description: string; icon: IconName; route: keyof RootStackParamList }[] = [
  { label: 'Chat (LLM)', description: 'Text generation on the NPU', icon: 'chat', route: ROUTES.Chat },
  { label: 'Vision (VLM)', description: 'Describe images', icon: 'vision', route: ROUTES.Vlm },
  { label: 'Speech to Text', description: 'Transcribe audio', icon: 'transcribe', route: ROUTES.Transcribe },
  { label: 'Text to Speech', description: 'Synthesize speech', icon: 'speak', route: ROUTES.Speak },
];

export const NpuScreen: React.FC = () => {
  const navigation = useNavigation<Nav>();
  const { colors, typography } = useTheme();
  const insets = useSafeAreaInsets();

  const [loading, setLoading] = useState(true);
  const [npu, setNpu] = useState<NpuInfo>(UNKNOWN_NPU_INFO);
  const [registered, setRegistered] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [probed, reg] = await Promise.all([QHexRT.probeNpu(), QHexRT.isRegistered()]);
        if (!alive) return;
        setNpu(probed);
        setRegistered(reg);
      } finally {
        if (alive) setLoading(false);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const supported = npu.qhexrtSupported;
  const archName = hexagonArchName(npu.hexagonArch);
  const pill = (label: string, ok: boolean) => (
    <View
      style={[
        styles.pill,
        { borderColor: ok ? colors.success : colors.error, backgroundColor: (ok ? colors.success : colors.error) + '1A' },
      ]}
    >
      <View style={[styles.dot, { backgroundColor: ok ? colors.success : colors.error }]} />
      <Text style={[typography.labelMedium, { color: ok ? colors.success : colors.error }]}>{label}</Text>
    </View>
  );

  const row = (label: string, value: string) => (
    <View style={styles.metricRow}>
      <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>{label}</Text>
      <Text style={[typography.bodyMedium, { color: colors.onSurface, fontWeight: '600' }]}>{value}</Text>
    </View>
  );

  return (
    <ScrollView
      style={[styles.root, { backgroundColor: colors.background }]}
      contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 24 }]}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.centered}>
        {/* Device / NPU card */}
        <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
          <View style={styles.pillRow}>
            {pill(supported ? 'NPU supported' : 'Unsupported', supported)}
            {pill(registered ? 'QHexRT ready' : 'QHexRT off', registered)}
          </View>

          {loading ? (
            <ActivityIndicator color={colors.primary} style={{ marginTop: 16 }} />
          ) : (
            <View style={{ marginTop: 14 }}>
              {row('SoC model', npu.socModel || 'Unknown SoC')}
              {row('Hexagon arch', npu.hexagonArch === HexagonArch.Unknown ? 'unknown' : archName)}
              {row('SoC id', npu.socId >= 0 ? String(npu.socId) : '—')}
            </View>
          )}

          {!loading && !supported && (
            <View style={[styles.warn, { backgroundColor: colors.error + '14', borderColor: colors.error }]}>
              <Text style={[typography.bodySmall, { color: colors.error }]}>
                QHexRT requires a Hexagon v79 or v81 NPU (Snapdragon 8 Elite / 8 Gen 3 class). This
                device reports {archName === 'unknown' ? 'an unknown part' : archName} — NPU inference
                may be unavailable; the SDK falls back to other backends.
              </Text>
            </View>
          )}
        </View>

        <Text style={[typography.titleMedium, { color: colors.onSurface, marginBottom: 8, marginTop: 8 }]}>
          Run on the NPU
        </Text>
        <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant, marginBottom: 12 }]}>
          Load a QHexRT model, then use any modality below — it routes through the NPU backend.
        </Text>

        {MODALITIES.map((m) => (
          <TouchableOpacity
            key={m.label}
            style={[styles.card, styles.navCard, { backgroundColor: colors.surfaceContainerHigh }]}
            activeOpacity={0.7}
            onPress={() => navigation.navigate(m.route)}
          >
            <Icon name={m.icon} size={24} color={colors.primary} />
            <View style={styles.textBlock}>
              <Text style={[typography.bodyLarge, { color: colors.onSurface }]} numberOfLines={1}>
                {m.label}
              </Text>
              <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]} numberOfLines={1}>
                {m.description}
              </Text>
            </View>
            <Icon name="chevronRight" size={20} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
        ))}
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { paddingHorizontal: 16, paddingTop: 16, gap: 8, alignItems: 'center' },
  centered: { width: '100%', maxWidth: 640 },
  card: { borderRadius: 16, padding: 16, marginBottom: 10 },
  navCard: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  pillRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 5,
  },
  dot: { width: 8, height: 8, borderRadius: 4 },
  metricRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 5 },
  warn: { marginTop: 14, borderWidth: 1, borderRadius: 12, padding: 12 },
  textBlock: { flex: 1 },
});

export default NpuScreen;
