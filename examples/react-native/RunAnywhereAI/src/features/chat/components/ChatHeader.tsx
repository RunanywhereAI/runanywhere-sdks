/**
 * ChatHeader — top bar for the chat screen. The title is a tappable model card
 * (icon + name + a status dot: Ready / Generating… / Tap to choose) that opens
 * the model picker; right-side actions are LoRA, analytics, history and new chat.
 * Inspired by the Android app's ChatTopBar, themed for light/dark and safe-area
 * aware so it sits correctly under the iOS notch / Android status bar.
 */
import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon, useTheme } from '../../../theme/system';

interface ChatHeaderProps {
  modelName?: string | null;
  ready: boolean;
  generating: boolean;
  hasMessages: boolean;
  onModelPress: () => void;
  onAnalytics: () => void;
  onHistory: () => void;
  onNewChat: () => void;
}

export const ChatHeader: React.FC<ChatHeaderProps> = ({
  modelName,
  ready,
  generating,
  hasMessages,
  onModelPress,
  onAnalytics,
  onHistory,
  onNewChat,
}) => {
  const { colors, typography } = useTheme();
  const insets = useSafeAreaInsets();

  const status = generating
    ? 'Generating…'
    : ready
      ? 'Ready'
      : modelName
        ? 'Not loaded'
        : 'Tap to choose';
  const dotColor = generating
    ? colors.primary
    : ready
      ? colors.success
      : colors.onSurfaceVariant;

  return (
    <View
      style={[
        styles.bar,
        {
          paddingTop: insets.top,
          backgroundColor: colors.surface,
          borderBottomColor: colors.outlineVariant,
        },
      ]}
    >
      <View style={styles.row}>
        <TouchableOpacity
          style={[
            styles.modelCard,
            { backgroundColor: colors.surfaceContainerHigh },
          ]}
          onPress={onModelPress}
          activeOpacity={0.7}
        >
          <View
            style={[styles.modelIcon, { backgroundColor: colors.surfaceVariant }]}
          >
            <Icon name="cpu" size={18} color={colors.onSurfaceVariant} />
          </View>
          <View style={styles.modelText}>
            <Text
              numberOfLines={1}
              style={[
                typography.titleSmall,
                styles.bold,
                { color: colors.onSurface },
              ]}
            >
              {modelName ?? 'Select model'}
            </Text>
            <View style={styles.statusRow}>
              <View style={[styles.dot, { backgroundColor: dotColor }]} />
              <Text
                style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
              >
                {status}
              </Text>
            </View>
          </View>
        </TouchableOpacity>

        <View style={styles.actions}>
          <TouchableOpacity
            style={styles.iconBtn}
            onPress={onAnalytics}
            disabled={!hasMessages}
            hitSlop={8}
          >
            <Icon
              name="info"
              size={21}
              color={hasMessages ? colors.onSurfaceVariant : colors.outlineVariant}
            />
          </TouchableOpacity>
          <TouchableOpacity style={styles.iconBtn} onPress={onHistory} hitSlop={8}>
            <Icon name="history" size={21} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.iconBtn} onPress={onNewChat} hitSlop={8}>
            <Icon name="plus" size={22} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  bar: {
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  modelCard: {
    flexShrink: 1,
    maxWidth: 220,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 5,
    paddingLeft: 5,
    paddingRight: 12,
    borderRadius: 12,
  },
  modelIcon: {
    width: 32,
    height: 32,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modelText: {
    flex: 1,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 1,
  },
  dot: {
    width: 7,
    height: 7,
    borderRadius: 999,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconBtn: {
    padding: 7,
  },
  bold: {
    fontWeight: '700',
  },
});

export default ChatHeader;
