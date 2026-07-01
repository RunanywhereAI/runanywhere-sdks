/**
 * RunAnywhere NPU - shared UI widgets
 *
 * Responsive on every screen: content is centered and capped at
 * CONTENT_MAX_WIDTH so tablets / landscape / split-screen stay readable.
 */
import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  TextInputProps,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppColors, useAppColors, Radius, Space, CONTENT_MAX_WIDTH } from './theme';

export const Screen: React.FC<{
  title: string;
  onBack?: () => void;
  children: React.ReactNode;
}> = ({ title, onBack, children }) => {
  const c = useAppColors();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: c.background }}>
      <View
        style={[
          styles.appBar,
          { paddingTop: insets.top + Space.sm, borderBottomColor: c.outline, backgroundColor: c.surface },
        ]}
      >
        {onBack ? (
          <TouchableOpacity onPress={onBack} hitSlop={12} style={styles.backBtn}>
            <Text style={[styles.backGlyph, { color: c.primary }]}>‹</Text>
          </TouchableOpacity>
        ) : (
          <View style={styles.backBtn} />
        )}
        <Text numberOfLines={1} style={[styles.appBarTitle, { color: c.onSurface }]}>
          {title}
        </Text>
        <View style={styles.backBtn} />
      </View>
      <ScrollView
        contentContainerStyle={[styles.scrollContent, { paddingBottom: insets.bottom + Space.xl }]}
        keyboardShouldPersistTaps="handled"
      >
        <View style={[styles.centered, { maxWidth: CONTENT_MAX_WIDTH }]}>{children}</View>
      </ScrollView>
    </View>
  );
};

export const SectionCard: React.FC<{
  title?: string;
  children: React.ReactNode;
}> = ({ title, children }) => {
  const c = useAppColors();
  return (
    <View style={[styles.card, { backgroundColor: c.surface, borderColor: c.outline }]}>
      {title ? <Text style={[styles.cardTitle, { color: c.onSurfaceVariant }]}>{title}</Text> : null}
      {children}
    </View>
  );
};

export const StatusPill: React.FC<{ label: string; tone: 'ok' | 'warn' | 'error' | 'neutral' }> = ({
  label,
  tone,
}) => {
  const c = useAppColors();
  const map: Record<string, string> = {
    ok: c.success,
    warn: c.warning,
    error: c.error,
    neutral: c.onSurfaceVariant,
  };
  const color = map[tone];
  return (
    <View style={[styles.pill, { borderColor: color, backgroundColor: color + '1A' }]}>
      <View style={[styles.dot, { backgroundColor: color }]} />
      <Text style={[styles.pillText, { color }]}>{label}</Text>
    </View>
  );
};

export const MetricRow: React.FC<{ label: string; value: string }> = ({ label, value }) => {
  const c = useAppColors();
  return (
    <View style={styles.metricRow}>
      <Text style={[styles.metricLabel, { color: c.onSurfaceVariant }]}>{label}</Text>
      <Text style={[styles.metricValue, { color: c.onSurface }]}>{value}</Text>
    </View>
  );
};

export const MetricStrip: React.FC<{ items: [string, string][] }> = ({ items }) => {
  const c = useAppColors();
  return (
    <View style={[styles.strip, { borderColor: c.outline, backgroundColor: c.surfaceVariant }]}>
      {items.map(([label, value], i) => (
        <View key={label} style={[styles.stripItem, i > 0 && { borderLeftWidth: 1, borderLeftColor: c.outline }]}>
          <Text style={[styles.stripValue, { color: c.primary }]}>{value}</Text>
          <Text style={[styles.stripLabel, { color: c.onSurfaceVariant }]}>{label}</Text>
        </View>
      ))}
    </View>
  );
};

export const PrimaryButton: React.FC<{
  label: string;
  onPress: () => void;
  disabled?: boolean;
  busy?: boolean;
}> = ({ label, onPress, disabled, busy }) => {
  const c = useAppColors();
  const off = disabled || busy;
  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={off}
      activeOpacity={0.85}
      style={[styles.button, { backgroundColor: off ? c.outline : c.primary }]}
    >
      {busy ? (
        <ActivityIndicator color={c.onPrimary} />
      ) : (
        <Text style={[styles.buttonText, { color: off ? c.onSurfaceVariant : c.onPrimary }]}>{label}</Text>
      )}
    </TouchableOpacity>
  );
};

export const NavTile: React.FC<{
  title: string;
  subtitle: string;
  onPress: () => void;
}> = ({ title, subtitle, onPress }) => {
  const c = useAppColors();
  return (
    <TouchableOpacity
      onPress={onPress}
      activeOpacity={0.85}
      style={[styles.tile, { backgroundColor: c.surface, borderColor: c.outline }]}
    >
      <View style={{ flex: 1 }}>
        <Text style={[styles.tileTitle, { color: c.onSurface }]}>{title}</Text>
        <Text style={[styles.tileSub, { color: c.onSurfaceVariant }]}>{subtitle}</Text>
      </View>
      <Text style={[styles.tileChevron, { color: c.primary }]}>›</Text>
    </TouchableOpacity>
  );
};

export const Field: React.FC<TextInputProps & { colors?: AppColors }> = (props) => {
  const c = useAppColors();
  return (
    <TextInput
      placeholderTextColor={c.onSurfaceVariant}
      {...props}
      style={[
        styles.field,
        { color: c.onSurface, borderColor: c.outline, backgroundColor: c.surface },
        props.style,
      ]}
    />
  );
};

const styles = StyleSheet.create({
  appBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Space.sm,
    paddingBottom: Space.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  backBtn: { width: 44, height: 32, alignItems: 'center', justifyContent: 'center' },
  backGlyph: { fontSize: 34, lineHeight: 34, fontWeight: '300' },
  appBarTitle: { flex: 1, textAlign: 'center', fontSize: 18, fontWeight: '700' },
  scrollContent: { padding: Space.lg, alignItems: 'center' },
  centered: { width: '100%', alignSelf: 'center' },
  card: { borderRadius: Radius.lg, borderWidth: 1, padding: Space.lg, marginBottom: Space.lg },
  cardTitle: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: Space.md,
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: Space.md,
    paddingVertical: 5,
    gap: 6,
  },
  dot: { width: 8, height: 8, borderRadius: 4 },
  pillText: { fontSize: 13, fontWeight: '700' },
  metricRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 6 },
  metricLabel: { fontSize: 14 },
  metricValue: { fontSize: 14, fontWeight: '600', fontVariant: ['tabular-nums'] },
  strip: { flexDirection: 'row', borderWidth: 1, borderRadius: Radius.md, overflow: 'hidden' },
  stripItem: { flex: 1, alignItems: 'center', paddingVertical: Space.md },
  stripValue: { fontSize: 18, fontWeight: '700', fontVariant: ['tabular-nums'] },
  stripLabel: { fontSize: 11, marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.5 },
  button: { height: 52, borderRadius: Radius.md, alignItems: 'center', justifyContent: 'center' },
  buttonText: { fontSize: 16, fontWeight: '700' },
  tile: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: Radius.lg,
    borderWidth: 1,
    padding: Space.lg,
    marginBottom: Space.md,
  },
  tileTitle: { fontSize: 16, fontWeight: '700' },
  tileSub: { fontSize: 13, marginTop: 2 },
  tileChevron: { fontSize: 28, fontWeight: '300' },
  field: {
    borderWidth: 1,
    borderRadius: Radius.md,
    paddingHorizontal: Space.md,
    paddingVertical: Space.md,
    fontSize: 15,
    minHeight: 48,
  },
});
