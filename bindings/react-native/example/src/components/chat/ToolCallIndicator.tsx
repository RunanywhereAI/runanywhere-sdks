/**
 * ToolCallIndicator Component
 *
 * Displays a tool call badge and detail sheet for messages that used tools.
 * Matches iOS ToolCallViews.swift implementation.
 */

import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../../theme/system';
import type { ToolCallInfo } from '../../types/chat';

interface ToolCallIndicatorProps {
  toolCallInfo: ToolCallInfo;
}

/**
 * Small badge showing tool name that can be tapped to see details
 */
export const ToolCallIndicator: React.FC<ToolCallIndicatorProps> = ({
  toolCallInfo,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  const [showSheet, setShowSheet] = useState(false);

  const backgroundColor = toolCallInfo.success
    ? colors.primary + '1A' // 10% opacity
    : colors.tertiary + '1A';

  const borderColor = toolCallInfo.success
    ? colors.primary + '4D' // 30% opacity
    : colors.tertiary + '4D';

  const iconColor = toolCallInfo.success ? colors.primary : colors.tertiary;

  return (
    <>
      <TouchableOpacity
        style={[styles.badge, { backgroundColor, borderColor }]}
        onPress={() => setShowSheet(true)}
        activeOpacity={0.7}
      >
        <Icon
          name={toolCallInfo.success ? 'build-outline' : 'warning-outline'}
          size={12}
          color={iconColor}
        />
        <Text style={styles.badgeText}>{toolCallInfo.toolName}</Text>
      </TouchableOpacity>

      <ToolCallDetailSheet
        visible={showSheet}
        toolCallInfo={toolCallInfo}
        onClose={() => setShowSheet(false)}
      />
    </>
  );
};

interface ToolCallDetailSheetProps {
  visible: boolean;
  toolCallInfo: ToolCallInfo;
  onClose: () => void;
}

/**
 * Full detail sheet showing tool call arguments and results as JSON
 */
const ToolCallDetailSheet: React.FC<ToolCallDetailSheetProps> = ({
  visible,
  toolCallInfo,
  onClose,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <SafeAreaView style={styles.sheetContainer}>
        {/* Header */}
        <View style={styles.sheetHeader}>
          <Text style={styles.sheetTitle}>Tool Call</Text>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>Done</Text>
          </TouchableOpacity>
        </View>

        <ScrollView
          style={styles.sheetContent}
          contentContainerStyle={styles.sheetContentContainer}
        >
          {/* Status Section */}
          <View
            style={[
              styles.statusSection,
              {
                backgroundColor: toolCallInfo.success
                  ? colors.success + '1A'
                  : colors.error + '1A',
              },
            ]}
          >
            <Icon
              name={toolCallInfo.success ? 'checkmark-circle' : 'close-circle'}
              size={24}
              color={toolCallInfo.success ? colors.success : colors.error}
            />
            <Text style={styles.statusText}>
              {toolCallInfo.success ? 'Success' : 'Failed'}
            </Text>
          </View>

          {/* Tool Name */}
          <DetailSection title="Tool" content={toolCallInfo.toolName} />

          {/* Arguments */}
          <CodeSection title="Arguments" code={toolCallInfo.arguments} />

          {/* Result (if available) */}
          {toolCallInfo.result && (
            <CodeSection title="Result" code={toolCallInfo.result} />
          )}

          {/* Error (if available) */}
          {toolCallInfo.error && (
            <DetailSection title="Error" content={toolCallInfo.error} isError />
          )}
        </ScrollView>
      </SafeAreaView>
    </Modal>
  );
};

interface DetailSectionProps {
  title: string;
  content: string;
  isError?: boolean;
}

const DetailSection: React.FC<DetailSectionProps> = ({
  title,
  content,
  isError = false,
}) => {
  const styles = useThemedStyles(createStyles);
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <Text style={[styles.sectionContent, isError && styles.errorText]}>
        {content}
      </Text>
    </View>
  );
};

interface CodeSectionProps {
  title: string;
  code: string;
}

const CodeSection: React.FC<CodeSectionProps> = ({ title, code }) => {
  const styles = useThemedStyles(createStyles);
  // Try to pretty print JSON
  let formattedCode = code;
  try {
    const parsed = JSON.parse(code);
    formattedCode = JSON.stringify(parsed, null, 2);
  } catch {
    // Keep original if not valid JSON
  }

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <ScrollView horizontal style={styles.codeContainer}>
        <Text style={styles.codeText}>{formattedCode}</Text>
      </ScrollView>
    </View>
  );
};

/**
 * Badge shown in chat to indicate tool calling is enabled
 * Matches iOS toolCallingBadge
 */
interface ToolCallingBadgeProps {
  toolCount: number;
}

export const ToolCallingBadge: React.FC<ToolCallingBadgeProps> = ({
  toolCount,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  return (
    <View style={styles.toolCallingBadge}>
      <Icon name="build-outline" size={12} color={colors.primary} />
      <Text style={styles.toolCallingBadgeText}>
        Tools enabled ({toolCount})
      </Text>
    </View>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    // Badge styles
    badge: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      paddingHorizontal: 10,
      paddingVertical: 6,
      borderRadius: 8,
      borderWidth: 0.5,
      marginBottom: 6,
      alignSelf: 'flex-start',
    },
    badgeText: {
      ...typography.labelSmall,
      color: colors.onSurfaceVariant,
    },

    // Sheet styles
    sheetContainer: {
      flex: 1,
      backgroundColor: colors.surface,
    },
    sheetHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingHorizontal: 16,
      paddingVertical: 12,
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    sheetTitle: {
      ...typography.titleMedium,
      color: colors.onSurface,
    },
    closeButton: {
      paddingHorizontal: 12,
      paddingVertical: 8,
    },
    closeButtonText: {
      ...typography.bodyLarge,
      color: colors.primary,
      fontWeight: '600',
    },
    sheetContent: {
      flex: 1,
    },
    sheetContentContainer: {
      padding: 16,
      gap: 20,
    },

    // Status section
    statusSection: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      padding: 16,
      borderRadius: 8,
    },
    statusText: {
      ...typography.titleMedium,
      color: colors.onSurface,
    },

    // Detail section
    section: {
      gap: 6,
    },
    sectionTitle: {
      ...typography.labelMedium,
      color: colors.onSurfaceVariant,
    },
    sectionContent: {
      ...typography.bodyLarge,
      color: colors.onSurface,
    },
    errorText: {
      color: colors.error,
    },

    // Code section
    codeContainer: {
      backgroundColor: colors.surfaceContainer,
      borderRadius: 8,
      padding: 12,
    },
    codeText: {
      ...typography.codeSmall,
      color: colors.onSurface,
    },

    // Tool calling badge (above input)
    toolCallingBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
      paddingHorizontal: 12,
      paddingVertical: 8,
      backgroundColor: colors.primary + '1A',
      borderTopWidth: 1,
      borderTopColor: colors.outlineVariant,
    },
    toolCallingBadgeText: {
      ...typography.labelMedium,
      color: colors.primary,
    },
  });

export default ToolCallIndicator;
