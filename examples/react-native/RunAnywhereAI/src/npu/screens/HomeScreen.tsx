/**
 * NPU Home - device / NPU capability + modality navigation.
 *
 * Self-contained: probes the NPU directly (the section is reached from the
 * app's More hub, so there is no shared app-init context to read from).
 */
import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, SectionCard, StatusPill, MetricRow, NavTile } from '../widgets';
import { QHexRT, hexagonArchName, HexagonArch, UNKNOWN_NPU_INFO, type NpuInfo } from '@runanywhere/qhexrt';

type Props = NativeStackScreenProps<NpuStackParamList, 'Home'>;

const HomeScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [npu, setNpu] = useState<NpuInfo>(UNKNOWN_NPU_INFO);
  const [registered, setRegistered] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      const [probed, reg] = await Promise.all([QHexRT.probeNpu(), QHexRT.isRegistered()]);
      if (!alive) return;
      setNpu(probed);
      setRegistered(reg);
    })();
    return () => {
      alive = false;
    };
  }, []);

  const supported = npu.qhexrtSupported;
  const archName = hexagonArchName(npu.hexagonArch);

  return (
    <Screen title="RunAnywhere NPU" onBack={() => navigation.goBack()}>
      <Text style={[styles.headline, { color: c.onSurface }]}>On-device AI on the Qualcomm Hexagon NPU</Text>
      <Text style={[styles.sub, { color: c.onSurfaceVariant }]}>
        LLM · VLM · Speech-to-Text · Text-to-Speech, accelerated by QHexRT.
      </Text>

      <View style={{ height: Space.lg }} />

      <SectionCard title="Device">
        <View style={styles.pillRow}>
          <StatusPill label={supported ? 'NPU supported' : 'Unsupported'} tone={supported ? 'ok' : 'warn'} />
          <StatusPill
            label={registered ? 'QHexRT ready' : 'QHexRT unavailable'}
            tone={registered ? 'ok' : 'neutral'}
          />
        </View>
        <View style={{ height: Space.md }} />
        <MetricRow label="SoC model" value={npu.socModel || 'Unknown SoC'} />
        <MetricRow label="Hexagon arch" value={npu.hexagonArch === HexagonArch.Unknown ? 'unknown' : archName} />
        <MetricRow label="SoC id" value={npu.socId >= 0 ? String(npu.socId) : '—'} />

        {!supported && (
          <View style={[styles.warn, { backgroundColor: c.warning + '1A', borderColor: c.warning }]}>
            <Text style={[styles.warnText, { color: c.warning }]}>
              QHexRT requires a Hexagon v79 or v81 NPU (Snapdragon 8 Elite / 8 Gen 3 class). This
              device reports {archName === 'unknown' ? 'an unknown part' : archName} — NPU inference
              may be unavailable.
            </Text>
          </View>
        )}
      </SectionCard>

      <SectionCard title="Modalities">
        <NavTile title="Chat (LLM)" subtitle="Text generation on the NPU" onPress={() => navigation.navigate('Llm')} />
        <NavTile title="Vision (VLM)" subtitle="Ask about an image" onPress={() => navigation.navigate('Vlm')} />
        <NavTile title="Speech-to-Text" subtitle="Transcribe audio" onPress={() => navigation.navigate('Stt')} />
        <NavTile title="Text-to-Speech" subtitle="Synthesize speech" onPress={() => navigation.navigate('Tts')} />
        <NavTile title="Models" subtitle="Download & manage NPU bundles" onPress={() => navigation.navigate('Models')} />
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  headline: { fontSize: 22, fontWeight: '800', lineHeight: 28 },
  sub: { fontSize: 14, marginTop: Space.sm, lineHeight: 20 },
  pillRow: { flexDirection: 'row', flexWrap: 'wrap', gap: Space.sm },
  warn: { marginTop: Space.md, borderWidth: 1, borderRadius: 12, padding: Space.md },
  warnText: { fontSize: 13, lineHeight: 19 },
});

export default HomeScreen;
