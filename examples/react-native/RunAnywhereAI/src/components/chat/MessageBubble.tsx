/**
 * MessageBubble — a single chat message, Claude/ChatGPT-style and themed for
 * light/dark.
 *
 * Assistant turns render flat and full-width (no bubble): a subtle framework
 * label, the response text on the page background, an expandable thinking
 * section, tool-call indicator, a thin streaming cursor and a muted tok/s meta.
 * User turns render as a compact right-aligned bubble. Empty content (a turn
 * that only ran tools, or one mid-stream) renders no text line.
 */
import React, { useEffect, useRef, useState } from 'react';
import {
  Animated,
  LayoutAnimation,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { Icon, useTheme } from '../../theme/system';
import type { Message } from '../../types/chat';
import { MessageRole } from '../../types/chat';
import { ToolCallIndicator } from './ToolCallIndicator';

interface MessageBubbleProps {
  message: Message;
  maxWidthFraction?: number;
}

const formatTPS = (tps: number): string =>
  tps >= 100 ? `${Math.round(tps)} tok/s` : `${tps.toFixed(1)} tok/s`;

/** Three softly-pulsing dots shown while an assistant turn streams its first token. */
const TypingDots: React.FC<{ color: string }> = ({ color }) => {
  const progress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(progress, {
        toValue: 3,
        duration: 1050,
        useNativeDriver: true,
      })
    );
    loop.start();
    return () => loop.stop();
  }, [progress]);

  return (
    <View style={styles.dots}>
      {[0, 1, 2].map((i) => (
        <Animated.View
          key={i}
          style={[
            styles.dot,
            {
              backgroundColor: color,
              opacity: progress.interpolate({
                inputRange: [i, i + 0.5, i + 1],
                outputRange: [0.3, 1, 0.3],
                extrapolate: 'clamp',
              }),
            },
          ]}
        />
      ))}
    </View>
  );
};

export const MessageBubble: React.FC<MessageBubbleProps> = ({
  message,
  maxWidthFraction = 0.84,
}) => {
  const { colors, typography } = useTheme();
  const [showThinking, setShowThinking] = useState(false);
  const isUser = message.role === MessageRole.User;
  const isAssistant = message.role === MessageRole.Assistant;
  const hasThinking = !!message.thinkingContent;
  const hasContent = !!message.content?.trim();
  const tps = message.analytics?.performance.throughputTokensPerSec ?? 0;

  const toggleThinking = () => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setShowThinking(!showThinking);
  };

  // User: compact right-aligned bubble.
  if (isUser) {
    return (
      <View style={[styles.row, styles.alignEnd]}>
        <View
          style={[
            styles.userBubble,
            { backgroundColor: colors.primary, maxWidth: `${maxWidthFraction * 100}%` },
          ]}
        >
          {hasContent && (
            <Text style={[typography.bodyLarge, { color: colors.onPrimary }]}>
              {message.content}
            </Text>
          )}
        </View>
      </View>
    );
  }

  // Assistant: flat, full-width.
  return (
    <View style={styles.assistant}>
      {message.modelInfo?.frameworkDisplayName && (
        <View style={styles.label}>
          <Icon name="cpu" size={12} color={colors.onSurfaceVariant} />
          <Text
            style={[
              typography.labelSmall,
              styles.bold,
              { color: colors.onSurfaceVariant },
            ]}
          >
            {message.modelInfo.frameworkDisplayName}
          </Text>
        </View>
      )}

      {message.toolCallInfo && (
        <ToolCallIndicator toolCallInfo={message.toolCallInfo} />
      )}

      {hasThinking && (
        <TouchableOpacity
          style={styles.thinkingHeader}
          onPress={toggleThinking}
          activeOpacity={0.7}
        >
          <Icon
            name={showThinking ? 'chevronDown' : 'chevronRight'}
            size={14}
            color={colors.onSurfaceVariant}
          />
          <Text
            style={[
              typography.labelMedium,
              styles.bold,
              { color: colors.onSurfaceVariant },
            ]}
          >
            Thinking
          </Text>
          {!!message.analytics?.thinkingTime && (
            <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
              {(message.analytics.thinkingTime / 1000).toFixed(1)}s
            </Text>
          )}
        </TouchableOpacity>
      )}

      {showThinking && !!message.thinkingContent && (
        <View
          style={[
            styles.thinkingContent,
            { backgroundColor: colors.surfaceContainerHigh },
          ]}
        >
          <Text
            style={[
              typography.bodySmall,
              styles.italic,
              { color: colors.onSurfaceVariant },
            ]}
          >
            {message.thinkingContent}
          </Text>
        </View>
      )}

      {hasContent ? (
        <Text style={[typography.bodyLarge, styles.body, { color: colors.onSurface }]}>
          {message.content}
        </Text>
      ) : (
        message.isStreaming && <TypingDots color={colors.onSurfaceVariant} />
      )}

      {hasContent && message.isStreaming && (
        <View style={[styles.cursor, { backgroundColor: colors.primary }]} />
      )}

      {tps > 0 && (
        <Text style={[typography.labelSmall, styles.meta, { color: colors.onSurfaceVariant }]}>
          {formatTPS(tps)}
        </Text>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  row: {
    paddingHorizontal: 16,
    marginVertical: 4,
  },
  alignEnd: {
    alignItems: 'flex-end',
  },
  userBubble: {
    borderRadius: 18,
    borderBottomRightRadius: 6,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  assistant: {
    paddingHorizontal: 16,
    marginTop: 6,
    marginBottom: 10,
    gap: 6,
  },
  label: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  body: {
    lineHeight: 24,
  },
  thinkingHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  thinkingContent: {
    borderRadius: 10,
    padding: 10,
  },
  cursor: {
    width: 7,
    height: 15,
    borderRadius: 2,
    opacity: 0.7,
  },
  dots: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingVertical: 4,
  },
  dot: {
    width: 7,
    height: 7,
    borderRadius: 999,
  },
  meta: {
    opacity: 0.7,
    marginTop: 2,
  },
  bold: {
    fontWeight: '700',
  },
  italic: {
    fontStyle: 'italic',
  },
});

export default MessageBubble;
