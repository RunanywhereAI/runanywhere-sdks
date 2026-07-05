import React, { useEffect, useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import { Icon, useTheme } from '../theme/system';

// Optional dependency — same pattern as App.tsx: the package (and its native
// hybrid) only exists on Android arm64 builds. probeNpu() resolves to the
// generated runanywhere.v1.NpuCapability proto message.
type QHexRTModule = {
  probeNpu: () => Promise<{
    socModel: string;
    socId: number;
    archName: string;
    qhexrtSupported: boolean;
  }>;
};
let qhexrt: QHexRTModule | null = null;
try {
  const mod = require('@runanywhere/qhexrt');
  qhexrt = mod.QHexRT as QHexRTModule;
} catch {
  qhexrt = null;
}

/**
 * Slim Hexagon-NPU capability card. NPU models themselves live in the standard
 * model pickers (registered only for the probed arch); this card is the one
 * NPU-specific surface left — it tells the user whether this device runs them.
 */
export const HexagonNpuCard: React.FC = () => {
  const { colors, typography } = useTheme();
  const [visible, setVisible] = useState(Platform.OS === 'android' && qhexrt !== null);
  const [line, setLine] = useState('Detecting…');
  const [supported, setSupported] = useState(false);

  useEffect(() => {
    if (!visible || !qhexrt) return undefined;
    let cancelled = false;
    (async () => {
      let text = 'Requires Hexagon v75+ — NPU models hidden';
      let ok = false;
      if (qhexrt) {
        try {
          const npu = await qhexrt.probeNpu();
          const isUnknownFallback =
            !npu.socModel && npu.socId < 0 && (npu.archName === '' || npu.archName === 'unknown');
          if (isUnknownFallback) {
            if (!cancelled) setVisible(false);
            return;
          }
          ok = npu.qhexrtSupported;
          const soc = npu.socModel || 'Snapdragon';
          text = ok
            ? `${soc} · Hexagon ${npu.archName} — NPU models available`
            : `Requires Hexagon v75+ — NPU models hidden${
                npu.socModel ? ` (${npu.socModel})` : ''
              }`;
        } catch {
          // Keep the unsupported default.
        }
      }
      if (!cancelled) {
        setSupported(ok);
        setLine(text);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [visible]);

  if (!visible) {
    return null;
  }

  return (
    <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
      <Icon
        name="cpu"
        size={24}
        color={supported ? colors.primary : colors.onSurfaceVariant}
      />
      <View style={styles.textBlock}>
        <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
          Hexagon NPU
        </Text>
        <Text
          style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
          numberOfLines={2}
        >
          {line}
        </Text>
      </View>
      {supported ? (
        <Text style={[typography.labelSmall, { color: colors.primary }]}>
          Ready
        </Text>
      ) : null}
    </View>
  );
};

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    borderRadius: 16,
    paddingHorizontal: 18,
    paddingVertical: 16,
  },
  textBlock: {
    flex: 1,
    gap: 2,
  },
});

export default HexagonNpuCard;
