/**
 * ChatAnalyticsScreen - Chat Analytics Details
 *
 * Reference: iOS Features/Chat/ChatInterfaceView.swift (ChatDetailsView)
 *
 * Displays comprehensive analytics for a chat conversation including:
 * - Overview: Conversation summary, performance highlights
 * - Messages: Per-message analytics
 * - Performance: Models used, thinking mode analysis
 */

import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../theme/system';
import type { Message, MessageAnalytics, Conversation } from '../types/chat';
import { MessageRole } from '../types/chat';

/**
 * Tab type for navigation
 */
type AnalyticsTab = 'overview' | 'messages' | 'performance';

interface ChatAnalyticsScreenProps {
  messages: Message[];
  conversation?: Conversation;
  onClose: () => void;
}

/**
 * Performance Card Component
 */
interface PerformanceCardProps {
  title: string;
  value: string;
  icon: string;
  color: string;
}

const PerformanceCard: React.FC<PerformanceCardProps> = ({
  title,
  value,
  icon,
  color,
}) => {
  const styles = useThemedStyles(createStyles);
  return (
    <View style={[styles.performanceCard, { borderColor: `${color}30` }]}>
      <View style={styles.performanceCardHeader}>
        <Icon name={icon} size={18} color={color} />
      </View>
      <Text style={styles.performanceCardValue}>{value}</Text>
      <Text style={styles.performanceCardTitle}>{title}</Text>
    </View>
  );
};

/**
 * Metric View Component
 */
interface MetricViewProps {
  label: string;
  value: string;
  color: string;
}

const MetricView: React.FC<MetricViewProps> = ({ label, value, color }) => {
  const styles = useThemedStyles(createStyles);
  return (
    <View style={styles.metricView}>
      <Text style={[styles.metricValue, { color }]}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
};

/**
 * Message Analytics Row Component
 */
interface MessageAnalyticsRowProps {
  messageNumber: number;
  message: Message;
  analytics: MessageAnalytics;
}

const MessageAnalyticsRow: React.FC<MessageAnalyticsRowProps> = ({
  messageNumber,
  message,
  analytics,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  return (
    <View style={styles.messageRow}>
      <View style={styles.messageRowHeader}>
        <Text style={styles.messageRowTitle}>Message #{messageNumber}</Text>
        <View style={styles.messageRowBadges}>
          {message.modelInfo && (
            <View style={[styles.badge, styles.badgeModel]}>
              <Text style={styles.badgeTextModel}>
                {message.modelInfo.modelName}
              </Text>
            </View>
          )}
          {message.modelInfo?.framework && (
            <View style={[styles.badge, styles.badgeFramework]}>
              <Text style={styles.badgeTextFramework}>
                {message.modelInfo.framework}
              </Text>
            </View>
          )}
        </View>
      </View>

      <View style={styles.metricsRow}>
        <MetricView
          label="Time"
          value={`${(analytics.performance.latencyMs / 1000).toFixed(1)}s`}
          color={colors.success}
        />
        {analytics.timeToFirstToken && (
          <MetricView
            label="TTFT"
            value={`${(analytics.timeToFirstToken / 1000).toFixed(1)}s`}
            color={colors.primary}
          />
        )}
        {analytics.performance.throughputTokensPerSec > 0 && (
          <MetricView
            label="Speed"
            value={`${Math.round(analytics.performance.throughputTokensPerSec)} tok/s`}
            color={colors.tertiary}
          />
        )}
        {analytics.wasThinkingMode && (
          <Icon name="bulb-outline" size={14} color={colors.tertiary} />
        )}
      </View>

      <Text style={styles.messagePreview} numberOfLines={2}>
        {message.content.slice(0, 100)}
      </Text>
    </View>
  );
};

export const ChatAnalyticsScreen: React.FC<ChatAnalyticsScreenProps> = ({
  messages,
  conversation,
  onClose,
}) => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  const [activeTab, setActiveTab] = useState<AnalyticsTab>('overview');

  // Extract analytics from messages
  const analyticsMessages = useMemo(() => {
    return messages
      .filter(
        (m): m is Message & { analytics: MessageAnalytics } =>
          m.analytics != null
      )
      .map((m) => ({ message: m, analytics: m.analytics }));
  }, [messages]);

  // Computed metrics
  const metrics = useMemo(() => {
    if (analyticsMessages.length === 0) {
      return {
        averageResponseTime: 0,
        averageTokensPerSecond: 0,
        totalTokens: 0,
        completionRate: 0,
        thinkingModeCount: 0,
        thinkingModePercentage: 0,
        modelsUsed: new Map<
          string,
          { count: number; avgSpeed: number; avgTime: number }
        >(),
      };
    }

    const totalResponseTime = analyticsMessages.reduce(
      (sum, { analytics }) => sum + analytics.performance.latencyMs,
      0
    );
    const totalTPS = analyticsMessages.reduce(
      (sum, { analytics }) =>
        sum + analytics.performance.throughputTokensPerSec,
      0
    );
    const totalTokens = analyticsMessages.reduce(
      (sum, { analytics }) =>
        sum +
        analytics.performance.promptTokens +
        analytics.performance.completionTokens,
      0
    );
    const completedCount = analyticsMessages.filter(
      ({ analytics }) => analytics.completionStatus === 'completed'
    ).length;
    const thinkingModeCount = analyticsMessages.filter(
      ({ analytics }) => analytics.wasThinkingMode
    ).length;

    // Group by model
    const modelGroups = new Map<
      string,
      { times: number[]; speeds: number[] }
    >();
    analyticsMessages.forEach(({ message, analytics }) => {
      const modelName = message.modelInfo?.modelName || 'Unknown';
      if (!modelGroups.has(modelName)) {
        modelGroups.set(modelName, { times: [], speeds: [] });
      }
      const group = modelGroups.get(modelName);
      if (group) {
        group.times.push(analytics.performance.latencyMs);
        group.speeds.push(analytics.performance.throughputTokensPerSec);
      }
    });

    const modelsUsed = new Map<
      string,
      { count: number; avgSpeed: number; avgTime: number }
    >();
    modelGroups.forEach((data, modelName) => {
      modelsUsed.set(modelName, {
        count: data.times.length,
        avgSpeed: data.speeds.reduce((a, b) => a + b, 0) / data.speeds.length,
        avgTime: data.times.reduce((a, b) => a + b, 0) / data.times.length,
      });
    });

    return {
      averageResponseTime: totalResponseTime / analyticsMessages.length / 1000,
      averageTokensPerSecond: totalTPS / analyticsMessages.length,
      totalTokens,
      completionRate: (completedCount / analyticsMessages.length) * 100,
      thinkingModeCount,
      thinkingModePercentage:
        (thinkingModeCount / analyticsMessages.length) * 100,
      modelsUsed,
    };
  }, [analyticsMessages]);

  // Conversation summary
  const conversationSummary = useMemo(() => {
    const userMessages = messages.filter(
      (m) => m.role === MessageRole.User
    ).length;
    const assistantMessages = messages.filter(
      (m) => m.role === MessageRole.Assistant
    ).length;
    return `${messages.length} messages \u2022 ${userMessages} from you, ${assistantMessages} from AI`;
  }, [messages]);

  /**
   * Render tab buttons
   */
  const renderTabs = () => (
    <View style={styles.tabsContainer}>
      <TouchableOpacity
        style={[styles.tab, activeTab === 'overview' && styles.tabActive]}
        onPress={() => setActiveTab('overview')}
      >
        <Icon
          name="stats-chart"
          size={18}
          color={
            activeTab === 'overview' ? colors.primary : colors.onSurfaceVariant
          }
        />
        <Text
          style={[
            styles.tabText,
            activeTab === 'overview' && styles.tabTextActive,
          ]}
        >
          Overview
        </Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.tab, activeTab === 'messages' && styles.tabActive]}
        onPress={() => setActiveTab('messages')}
      >
        <Icon
          name="chatbubbles-outline"
          size={18}
          color={
            activeTab === 'messages' ? colors.primary : colors.onSurfaceVariant
          }
        />
        <Text
          style={[
            styles.tabText,
            activeTab === 'messages' && styles.tabTextActive,
          ]}
        >
          Messages
        </Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.tab, activeTab === 'performance' && styles.tabActive]}
        onPress={() => setActiveTab('performance')}
      >
        <Icon
          name="speedometer-outline"
          size={18}
          color={
            activeTab === 'performance'
              ? colors.primary
              : colors.onSurfaceVariant
          }
        />
        <Text
          style={[
            styles.tabText,
            activeTab === 'performance' && styles.tabTextActive,
          ]}
        >
          Performance
        </Text>
      </TouchableOpacity>
    </View>
  );

  /**
   * Render Overview Tab
   */
  const renderOverviewTab = () => (
    <ScrollView style={styles.tabContent} showsVerticalScrollIndicator={false}>
      {/* Conversation Summary Card */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Conversation Summary</Text>
        <View style={styles.summaryRow}>
          <Icon
            name="chatbubble-ellipses-outline"
            size={18}
            color={colors.primary}
          />
          <Text style={styles.summaryText}>{conversationSummary}</Text>
        </View>
        {conversation && (
          <View style={styles.summaryRow}>
            <Icon name="time-outline" size={18} color={colors.primary} />
            <Text style={styles.summaryText}>
              Created {new Date(conversation.createdAt).toLocaleDateString()}
            </Text>
          </View>
        )}
        {analyticsMessages.length > 0 && (
          <View style={styles.summaryRow}>
            <Icon name="cube-outline" size={18} color={colors.primary} />
            <Text style={styles.summaryText}>
              {metrics.modelsUsed.size} model
              {metrics.modelsUsed.size === 1 ? '' : 's'} used
            </Text>
          </View>
        )}
      </View>

      {/* Performance Highlights */}
      {analyticsMessages.length > 0 && (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Performance Highlights</Text>
          <View style={styles.performanceGrid}>
            <PerformanceCard
              title="Avg Response Time"
              value={`${metrics.averageResponseTime.toFixed(1)}s`}
              icon="timer-outline"
              color={colors.success}
            />
            <PerformanceCard
              title="Avg Speed"
              value={`${Math.round(metrics.averageTokensPerSecond)} tok/s`}
              icon="speedometer-outline"
              color={colors.primary}
            />
            <PerformanceCard
              title="Total Tokens"
              value={metrics.totalTokens.toLocaleString()}
              icon="text-outline"
              color={colors.tertiary}
            />
            <PerformanceCard
              title="Success Rate"
              value={`${Math.round(metrics.completionRate)}%`}
              icon="checkmark-circle-outline"
              color={colors.secondary}
            />
          </View>
        </View>
      )}

      {analyticsMessages.length === 0 && (
        <View style={styles.emptyState}>
          <Icon name="analytics-outline" size={48} color={colors.outline} />
          <Text style={styles.emptyText}>No analytics data available yet</Text>
          <Text style={styles.emptySubtext}>
            Start a conversation to see performance metrics
          </Text>
        </View>
      )}
    </ScrollView>
  );

  /**
   * Render Messages Tab
   */
  const renderMessagesTab = () => (
    <FlatList
      data={analyticsMessages}
      keyExtractor={(item, index) => `${item.message.id}-${index}`}
      renderItem={({ item, index }) => (
        <MessageAnalyticsRow
          messageNumber={index + 1}
          message={item.message}
          analytics={item.analytics}
        />
      )}
      contentContainerStyle={styles.messagesList}
      showsVerticalScrollIndicator={false}
      ListEmptyComponent={
        <View style={styles.emptyState}>
          <Icon name="chatbubbles-outline" size={48} color={colors.outline} />
          <Text style={styles.emptyText}>No messages with analytics</Text>
        </View>
      }
    />
  );

  /**
   * Render Performance Tab
   */
  const renderPerformanceTab = () => (
    <ScrollView style={styles.tabContent} showsVerticalScrollIndicator={false}>
      {/* Models Used */}
      {metrics.modelsUsed.size > 0 && (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Models Used</Text>
          {Array.from(metrics.modelsUsed.entries()).map(([modelName, data]) => (
            <View key={modelName} style={styles.modelRow}>
              <View style={styles.modelInfo}>
                <Text style={styles.modelName}>{modelName}</Text>
                <Text style={styles.modelMessages}>
                  {data.count} message{data.count === 1 ? '' : 's'}
                </Text>
              </View>
              <View style={styles.modelStats}>
                <Text style={styles.modelStatValue}>
                  {(data.avgTime / 1000).toFixed(1)}s avg
                </Text>
                <Text style={styles.modelStatSpeed}>
                  {Math.round(data.avgSpeed)} tok/s
                </Text>
              </View>
            </View>
          ))}
        </View>
      )}

      {/* Thinking Mode Analysis */}
      {metrics.thinkingModeCount > 0 && (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Thinking Mode Analysis</Text>
          <View style={styles.thinkingAnalysis}>
            <Icon name="bulb-outline" size={20} color={colors.tertiary} />
            <Text style={styles.thinkingText}>
              Used in {metrics.thinkingModeCount} messages (
              {Math.round(metrics.thinkingModePercentage)}%)
            </Text>
          </View>
        </View>
      )}

      {analyticsMessages.length === 0 && (
        <View style={styles.emptyState}>
          <Icon name="speedometer-outline" size={48} color={colors.outline} />
          <Text style={styles.emptyText}>No performance data available</Text>
        </View>
      )}
    </ScrollView>
  );

  /**
   * Render current tab content
   */
  const renderTabContent = () => {
    switch (activeTab) {
      case 'overview':
        return renderOverviewTab();
      case 'messages':
        return renderMessagesTab();
      case 'performance':
        return renderPerformanceTab();
      default:
        return renderOverviewTab();
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Chat Analytics</Text>
        <TouchableOpacity style={styles.closeButton} onPress={onClose}>
          <Text style={styles.closeButtonText}>Done</Text>
        </TouchableOpacity>
      </View>

      {/* Tabs */}
      {renderTabs()}

      {/* Tab Content */}
      {renderTabContent()}
    </SafeAreaView>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.surfaceContainer,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: 16,
      paddingVertical: 12,
      backgroundColor: colors.surface,
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    title: {
      ...typography.titleMedium,
      color: colors.onSurface,
    },
    closeButton: {
      paddingVertical: 6,
      paddingHorizontal: 10,
    },
    closeButtonText: {
      ...typography.bodyLarge,
      color: colors.primary,
      fontWeight: '600',
    },
    tabsContainer: {
      flexDirection: 'row',
      backgroundColor: colors.surface,
      borderBottomWidth: 1,
      borderBottomColor: colors.outlineVariant,
    },
    tab: {
      flex: 1,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      paddingVertical: 12,
      gap: 4,
    },
    tabActive: {
      borderBottomWidth: 2,
      borderBottomColor: colors.primary,
    },
    tabText: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
    },
    tabTextActive: {
      color: colors.primary,
      fontWeight: '600',
    },
    tabContent: {
      flex: 1,
      padding: 16,
    },
    card: {
      backgroundColor: colors.surface,
      borderRadius: 10,
      padding: 16,
      marginBottom: 10,
    },
    cardTitle: {
      ...typography.titleMedium,
      color: colors.onSurface,
      marginBottom: 10,
    },
    summaryRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      marginBottom: 6,
    },
    summaryText: {
      ...typography.bodyMedium,
      color: colors.onSurface,
    },
    performanceGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 10,
    },
    performanceCard: {
      flex: 1,
      minWidth: '45%',
      backgroundColor: colors.surfaceContainer,
      borderRadius: 8,
      padding: 12,
      borderWidth: 1,
    },
    performanceCardHeader: {
      marginBottom: 6,
    },
    performanceCardValue: {
      ...typography.titleLarge,
      color: colors.onSurface,
      marginBottom: 2,
    },
    performanceCardTitle: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
    },
    metricView: {
      alignItems: 'center',
    },
    metricValue: {
      ...typography.bodySmall,
      fontWeight: '600',
    },
    metricLabel: {
      ...typography.labelSmall,
      color: colors.onSurfaceVariant,
    },
    messagesList: {
      padding: 16,
    },
    messageRow: {
      backgroundColor: colors.surface,
      borderRadius: 8,
      padding: 16,
      marginBottom: 10,
    },
    messageRowHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginBottom: 6,
    },
    messageRowTitle: {
      ...typography.bodyMedium,
      color: colors.onSurface,
      fontWeight: '600',
    },
    messageRowBadges: {
      flexDirection: 'row',
      gap: 6,
    },
    badge: {
      paddingHorizontal: 6,
      paddingVertical: 2,
      borderRadius: 4,
    },
    badgeModel: {
      backgroundColor: colors.primaryContainer,
    },
    badgeFramework: {
      backgroundColor: colors.tertiaryContainer,
    },
    badgeTextModel: {
      ...typography.labelSmall,
      color: colors.onPrimaryContainer,
      fontWeight: '600',
    },
    badgeTextFramework: {
      ...typography.labelSmall,
      color: colors.onTertiaryContainer,
      fontWeight: '600',
    },
    metricsRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 16,
      marginBottom: 6,
    },
    messagePreview: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
    },
    modelRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      backgroundColor: colors.surfaceContainer,
      borderRadius: 8,
      padding: 12,
      marginBottom: 6,
    },
    modelInfo: {
      flex: 1,
    },
    modelName: {
      ...typography.bodyMedium,
      color: colors.onSurface,
      fontWeight: '500',
    },
    modelMessages: {
      ...typography.bodySmall,
      color: colors.onSurfaceVariant,
    },
    modelStats: {
      alignItems: 'flex-end',
    },
    modelStatValue: {
      ...typography.bodySmall,
      color: colors.success,
    },
    modelStatSpeed: {
      ...typography.bodySmall,
      color: colors.primary,
    },
    thinkingAnalysis: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      backgroundColor: `${colors.tertiary}10`,
      borderRadius: 8,
      padding: 12,
    },
    thinkingText: {
      ...typography.bodyMedium,
      color: colors.onSurface,
    },
    emptyState: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      paddingVertical: 40,
    },
    emptyText: {
      ...typography.bodyLarge,
      color: colors.onSurfaceVariant,
      marginTop: 10,
    },
    emptySubtext: {
      ...typography.bodySmall,
      color: colors.outline,
      marginTop: 4,
    },
  });

export default ChatAnalyticsScreen;
