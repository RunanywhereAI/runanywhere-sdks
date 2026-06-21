/**
 * SolutionsScreen — demo for `RunAnywhere.solutions.run({ yaml })`.
 *
 * Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
 * shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
 * synced from the commons sources via `scripts/sync-solutions-yamls.js`
 * (runs on postinstall + before typecheck), so this screen never embeds
 * a hand-edited YAML literal. Each lifecycle transition is appended to a
 * simple scrolling log.
 */
import React, { useState, useCallback } from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { RunAnywhere } from '@runanywhere/core';
import { Icon, useTheme } from '../theme/system';
import type { IconName } from '../theme/system/icons';
import { VOICE_AGENT_YAML, RAG_YAML } from '../generated/solutionsYaml';

export const SolutionsScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();
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

  const s = styles(colors, typography, dimens);

  return (
    <View style={[s.container, { paddingTop: insets.top + 16 }]}>
      <Text style={s.intro}>
        Run a prepackaged pipeline (voice agent or RAG) by handing a YAML config
        to RunAnywhere.solutions.run.
      </Text>

      <View style={s.buttonRow}>
        <RunButton
          label="Voice Agent"
          icon="voice"
          enabled={!isRunning}
          colors={colors}
          typography={typography}
          dimens={dimens}
          onPress={() => runSolution('Voice Agent', VOICE_AGENT_YAML)}
        />
        <RunButton
          label="RAG"
          icon="rag"
          enabled={!isRunning}
          colors={colors}
          typography={typography}
          dimens={dimens}
          onPress={() => runSolution('RAG', RAG_YAML)}
        />
      </View>

      <View style={s.logCard}>
        <ScrollView
          contentContainerStyle={s.logContent}
          showsVerticalScrollIndicator={false}
        >
          {log.map((line, i) => (
            <Text key={i} style={s.logLine}>
              {line}
            </Text>
          ))}
        </ScrollView>
      </View>
    </View>
  );
};

interface RunButtonProps {
  label: string;
  icon: IconName;
  enabled: boolean;
  colors: ReturnType<typeof useTheme>['colors'];
  typography: ReturnType<typeof useTheme>['typography'];
  dimens: ReturnType<typeof useTheme>['dimens'];
  onPress: () => void;
}

const RunButton: React.FC<RunButtonProps> = ({
  label,
  icon,
  enabled,
  colors,
  typography,
  dimens,
  onPress,
}) => (
  <TouchableOpacity
    onPress={onPress}
    disabled={!enabled}
    activeOpacity={0.75}
    style={[
      btnStyles.base,
      { backgroundColor: colors.primary, borderRadius: dimens.radius.md },
      !enabled && btnStyles.disabled,
    ]}
  >
    <Icon name={icon} size={18} color={colors.onPrimary} />
    <Text style={[typography.labelLarge, { color: colors.onPrimary, marginLeft: 6 }]}>
      {label}
    </Text>
  </TouchableOpacity>
);

const btnStyles = StyleSheet.create({
  base: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
  },
  disabled: {
    opacity: 0.4,
  },
});

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
const styles = (
  colors: ReturnType<typeof useTheme>['colors'],
  typography: ReturnType<typeof useTheme>['typography'],
  dimens: ReturnType<typeof useTheme>['dimens']
) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.background,
      paddingHorizontal: 16,
      paddingBottom: 16,
      gap: 16,
    },
    intro: {
      ...(typography.bodyMedium as object),
      color: colors.onSurfaceVariant,
    },
    buttonRow: {
      flexDirection: 'row',
      gap: 12,
    },
    logCard: {
      flex: 1,
      backgroundColor: colors.surfaceContainerHigh,
      borderRadius: dimens.radius.lg,
      overflow: 'hidden',
    },
    logContent: {
      padding: 12,
      gap: 2,
    },
    logLine: {
      ...(typography.codeSmall as object),
      color: colors.onSurface,
    },
  });

export default SolutionsScreen;
