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
  SafeAreaView,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, BorderRadius, Padding } from '../../theme/spacing';
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
  const [showSheet, setShowSheet] = useState(false);

  const backgroundColor = toolCallInfo.success
    ? Colors.primaryBlue + '1A' // 10% opacity
    : Colors.primaryOrange + '1A';

  const borderColor = toolCallInfo.success
    ? Colors.primaryBlue + '4D' // 30% opacity
    : Colors.primaryOrange + '4D';

  const iconColor = toolCallInfo.success
    ? Colors.primaryBlue
    : Colors.primaryOrange;

  return (
    <>
      <TouchableOpacity
        style={[
          styles.badge,
          { backgroundColor, borderColor, borderWidth: 0.5 },
        ]}
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
                  ? Colors.statusGreen + '1A'
                  : Colors.statusRed + '1A',
              },
            ]}
          >
            <Icon
              name={
                toolCallInfo.success
                  ? 'checkmark-circle'
                  : 'close-circle'
              }
              size={24}
              color={
                toolCallInfo.success ? Colors.statusGreen : Colors.statusRed
              }
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
            <DetailSection
              title="Error"
              content={toolCallInfo.error}
              isError
            />
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
}) => (
  <View style={styles.section}>
    <Text style={styles.sectionTitle}>{title}</Text>
    <Text
      style={[styles.sectionContent, isError && styles.errorText]}
    >
      {content}
    </Text>
  </View>
);

interface CodeSectionProps {
  title: string;
  code: string;
}

const CodeSection: React.FC<CodeSectionProps> = ({ title, code }) => {
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
  return (
    <View style={styles.toolCallingBadge}>
      <Icon name="build-outline" size={12} color={Colors.primaryBlue} />
      <Text style={styles.toolCallingBadgeText}>
        Tools enabled ({toolCount})
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  // Badge styles
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
    marginBottom: Spacing.small,
    alignSelf: 'flex-start',
  },
  badgeText: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },

  // Sheet styles
  sheetContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  sheetHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  sheetTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  closeButton: {
    paddingHorizontal: Padding.padding12,
    paddingVertical: Padding.padding8,
  },
  closeButtonText: {
    ...Typography.body,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  sheetContent: {
    flex: 1,
  },
  sheetContentContainer: {
    padding: Padding.padding16,
    gap: 20,
  },

  // Status section
  statusSection: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    padding: Padding.padding16,
    borderRadius: BorderRadius.regular,
  },
  statusText: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },

  // Detail section
  section: {
    gap: Spacing.small,
  },
  sectionTitle: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  sectionContent: {
    ...Typography.body,
    color: Colors.textPrimary,
  },
  errorText: {
    color: Colors.statusRed,
  },

  // Code section
  codeContainer: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding12,
  },
  codeText: {
    ...Typography.footnote,
    fontFamily: 'Menlo',
    color: Colors.textPrimary,
  },

  // Tool calling badge (above input)
  toolCallingBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingHorizontal: Padding.padding12,
    paddingVertical: Padding.padding8,
    backgroundColor: Colors.primaryBlue + '1A',
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
  },
  toolCallingBadgeText: {
    ...Typography.caption,
    color: Colors.primaryBlue,
    fontWeight: '500',
  },
});

export default ToolCallIndicator;
