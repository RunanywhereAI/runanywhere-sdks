/**
 * MessageBubble Component
 *
 * Displays a single chat message with role-specific styling.
 *
 * Reference: iOS MessageBubbleView.swift
 */

import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  LayoutAnimation,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import { Spacing, BorderRadius, Padding, Layout } from '../../theme/spacing';
import type { Message } from '../../types/chat';
import { MessageRole } from '../../types/chat';

interface MessageBubbleProps {
  message: Message;
  /** Maximum width as fraction of screen */
  maxWidthFraction?: number;
}

/**
 * Format timestamp to relative or time string
 */
const formatTimestamp = (date: Date): string => {
  const now = new Date();
  const diff = now.getTime() - date.getTime();
  const minutes = Math.floor(diff / 60000);

  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;

  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

/**
 * Format tokens per second
 */
const formatTPS = (tps: number): string => {
  if (tps >= 100) return `${Math.round(tps)} tok/s`;
  return `${tps.toFixed(1)} tok/s`;
};

export const MessageBubble: React.FC<MessageBubbleProps> = ({
  message,
  maxWidthFraction = Layout.messageBubbleMaxWidth,
}) => {
  const [showThinking, setShowThinking] = useState(false);
  const isUser = message.role === MessageRole.User;
  const isAssistant = message.role === MessageRole.Assistant;
  const hasThinking = !!message.thinkingContent;

  const toggleThinking = () => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setShowThinking(!showThinking);
  };

  return (
    <View
      style={[
        styles.container,
        isUser ? styles.userContainer : styles.assistantContainer,
      ]}
    >
      {/* Message Bubble */}
      <View
        style={[
          styles.bubble,
          isUser ? styles.userBubble : styles.assistantBubble,
          { maxWidth: `${maxWidthFraction * 100}%` },
        ]}
      >
        {/* Model Info Badge (for assistant messages) */}
        {isAssistant &&
          message.modelInfo &&
          message.modelInfo.frameworkDisplayName && (
            <View style={styles.modelBadge}>
              <Icon name="cube-outline" size={10} color={Colors.primaryBlue} />
              <Text style={styles.modelBadgeText}>
                {message.modelInfo.frameworkDisplayName}
              </Text>
            </View>
          )}

        {/* Thinking Section (expandable) */}
        {hasThinking && (
          <TouchableOpacity
            style={styles.thinkingHeader}
            onPress={toggleThinking}
            activeOpacity={0.7}
          >
            <Icon
              name={showThinking ? 'chevron-down' : 'chevron-forward'}
              size={14}
              color={Colors.textSecondary}
            />
            <Text style={styles.thinkingLabel}>Thinking</Text>
            {message.analytics?.thinkingTime && (
              <Text style={styles.thinkingTime}>
                {(message.analytics.thinkingTime / 1000).toFixed(1)}s
              </Text>
            )}
          </TouchableOpacity>
        )}

        {showThinking && message.thinkingContent && (
          <View style={styles.thinkingContent}>
            <Text style={styles.thinkingText}>{message.thinkingContent}</Text>
          </View>
        )}

        {/* Message Content */}
        <Text
          style={[
            styles.messageText,
            isUser ? styles.userText : styles.assistantText,
          ]}
        >
          {message.content}
        </Text>

        {/* Streaming Indicator */}
        {message.isStreaming && (
          <View style={styles.streamingIndicator}>
            <View style={styles.cursor} />
          </View>
        )}

        {/* Footer: Timestamp & Analytics */}
        <View style={styles.footer}>
          <Text
            style={[
              styles.timestamp,
              isUser ? styles.userTimestamp : styles.assistantTimestamp,
            ]}
          >
            {formatTimestamp(message.timestamp)}
          </Text>

          {/* Analytics (for assistant messages) */}
          {isAssistant &&
            message.analytics &&
            message.analytics.averageTokensPerSecond != null &&
            message.analytics.averageTokensPerSecond > 0 && (
              <View style={styles.analytics}>
                <Text style={styles.analyticsText}>
                  {formatTPS(message.analytics.averageTokensPerSecond)}
                </Text>
              </View>
            )}
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    marginVertical: Spacing.xSmall,
    paddingHorizontal: Padding.padding16,
  },
  userContainer: {
    alignItems: 'flex-end',
  },
  assistantContainer: {
    alignItems: 'flex-start',
  },
  bubble: {
    borderRadius: BorderRadius.xLarge,
    paddingHorizontal: Padding.padding14,
    paddingVertical: Padding.padding10,
  },
  userBubble: {
    backgroundColor: Colors.primaryBlue,
    borderBottomRightRadius: BorderRadius.small,
  },
  assistantBubble: {
    backgroundColor: Colors.assistantBubbleBg,
    borderBottomLeftRadius: BorderRadius.small,
  },
  modelBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    marginBottom: Spacing.small,
    backgroundColor: Colors.badgeBlue,
    alignSelf: 'flex-start',
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
  modelBadgeText: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  thinkingHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xSmall,
    marginBottom: Spacing.small,
    paddingVertical: Spacing.xSmall,
  },
  thinkingLabel: {
    ...Typography.caption,
    color: Colors.textSecondary,
    fontWeight: '600',
  },
  thinkingTime: {
    ...Typography.caption,
    color: Colors.textTertiary,
  },
  thinkingContent: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding10,
    marginBottom: Spacing.smallMedium,
  },
  thinkingText: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    fontStyle: 'italic',
  },
  messageText: {
    ...Typography.body,
  },
  userText: {
    color: Colors.textWhite,
  },
  assistantText: {
    color: Colors.textPrimary,
  },
  streamingIndicator: {
    marginTop: Spacing.xSmall,
  },
  cursor: {
    width: 8,
    height: 16,
    backgroundColor: Colors.textSecondary,
    opacity: 0.5,
  },
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: Spacing.small,
  },
  timestamp: {
    ...Typography.caption2,
  },
  userTimestamp: {
    color: 'rgba(255, 255, 255, 0.7)',
  },
  assistantTimestamp: {
    color: Colors.textTertiary,
  },
  analytics: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  analyticsText: {
    ...Typography.caption2,
    color: Colors.textTertiary,
  },
});

export default MessageBubble;
