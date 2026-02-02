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
  SafeAreaView,
  ScrollView,
  TouchableOpacity,
  FlatList,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
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
}) => (
  <View style={[styles.performanceCard, { borderColor: `${color}30` }]}>
    <View style={styles.performanceCardHeader}>
      <Icon name={icon} size={18} color={color} />
    </View>
    <Text style={styles.performanceCardValue}>{value}</Text>
    <Text style={styles.performanceCardTitle}>{title}</Text>
  </View>
);

/**
 * Metric View Component
 */
interface MetricViewProps {
  label: string;
  value: string;
  color: string;
}

const MetricView: React.FC<MetricViewProps> = ({ label, value, color }) => (
  <View style={styles.metricView}>
    <Text style={[styles.metricValue, { color }]}>{value}</Text>
    <Text style={styles.metricLabel}>{label}</Text>
  </View>
);

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
}) => (
  <View style={styles.messageRow}>
    <View style={styles.messageRowHeader}>
      <Text style={styles.messageRowTitle}>Message #{messageNumber}</Text>
      <View style={styles.messageRowBadges}>
        {message.modelInfo && (
          <View style={[styles.badge, styles.badgeBlue]}>
            <Text style={styles.badgeTextBlue}>
              {message.modelInfo.modelName}
            </Text>
          </View>
        )}
        {message.modelInfo?.framework && (
          <View style={[styles.badge, styles.badgePurple]}>
            <Text style={styles.badgeTextPurple}>
              {message.modelInfo.framework}
            </Text>
          </View>
        )}
      </View>
    </View>

    <View style={styles.metricsRow}>
      <MetricView
        label="Time"
        value={`${(analytics.totalGenerationTime / 1000).toFixed(1)}s`}
        color={Colors.statusGreen}
      />
      {analytics.timeToFirstToken && (
        <MetricView
          label="TTFT"
          value={`${(analytics.timeToFirstToken / 1000).toFixed(1)}s`}
          color={Colors.statusBlue}
        />
      )}
      {analytics.averageTokensPerSecond != null &&
        analytics.averageTokensPerSecond > 0 && (
          <MetricView
            label="Speed"
            value={`${Math.round(analytics.averageTokensPerSecond)} tok/s`}
            color={Colors.primaryPurple}
          />
        )}
      {analytics.wasThinkingMode && (
        <Icon name="bulb-outline" size={14} color={Colors.statusOrange} />
      )}
    </View>

    <Text style={styles.messagePreview} numberOfLines={2}>
      {message.content.slice(0, 100)}
    </Text>
  </View>
);

export const ChatAnalyticsScreen: React.FC<ChatAnalyticsScreenProps> = ({
  messages,
  conversation,
  onClose,
}) => {
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
      (sum, { analytics }) => sum + analytics.totalGenerationTime,
      0
    );
    const totalTPS = analyticsMessages.reduce(
      (sum, { analytics }) => sum + (analytics.averageTokensPerSecond || 0),
      0
    );
    const totalTokens = analyticsMessages.reduce(
      (sum, { analytics }) =>
        sum + analytics.inputTokens + analytics.outputTokens,
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
        group.times.push(analytics.totalGenerationTime);
        group.speeds.push(analytics.averageTokensPerSecond || 0);
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
            activeTab === 'overview' ? Colors.primaryBlue : Colors.textSecondary
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
            activeTab === 'messages' ? Colors.primaryBlue : Colors.textSecondary
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
              ? Colors.primaryBlue
              : Colors.textSecondary
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
            color={Colors.primaryBlue}
          />
          <Text style={styles.summaryText}>{conversationSummary}</Text>
        </View>
        {conversation && (
          <View style={styles.summaryRow}>
            <Icon name="time-outline" size={18} color={Colors.primaryBlue} />
            <Text style={styles.summaryText}>
              Created {new Date(conversation.createdAt).toLocaleDateString()}
            </Text>
          </View>
        )}
        {analyticsMessages.length > 0 && (
          <View style={styles.summaryRow}>
            <Icon name="cube-outline" size={18} color={Colors.primaryBlue} />
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
              color={Colors.statusGreen}
            />
            <PerformanceCard
              title="Avg Speed"
              value={`${Math.round(metrics.averageTokensPerSecond)} tok/s`}
              icon="speedometer-outline"
              color={Colors.statusBlue}
            />
            <PerformanceCard
              title="Total Tokens"
              value={metrics.totalTokens.toLocaleString()}
              icon="text-outline"
              color={Colors.primaryPurple}
            />
            <PerformanceCard
              title="Success Rate"
              value={`${Math.round(metrics.completionRate)}%`}
              icon="checkmark-circle-outline"
              color={Colors.statusOrange}
            />
          </View>
        </View>
      )}

      {analyticsMessages.length === 0 && (
        <View style={styles.emptyState}>
          <Icon
            name="analytics-outline"
            size={48}
            color={Colors.textTertiary}
          />
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
          <Icon
            name="chatbubbles-outline"
            size={48}
            color={Colors.textTertiary}
          />
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
            <Icon name="bulb-outline" size={20} color={Colors.primaryPurple} />
            <Text style={styles.thinkingText}>
              Used in {metrics.thinkingModeCount} messages (
              {Math.round(metrics.thinkingModePercentage)}%)
            </Text>
          </View>
        </View>
      )}

      {analyticsMessages.length === 0 && (
        <View style={styles.emptyState}>
          <Icon
            name="speedometer-outline"
            size={48}
            color={Colors.textTertiary}
          />
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

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundGrouped,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  closeButton: {
    paddingVertical: Spacing.small,
    paddingHorizontal: Spacing.medium,
  },
  closeButtonText: {
    ...Typography.body,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  tabsContainer: {
    flexDirection: 'row',
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: Padding.padding12,
    gap: Spacing.xSmall,
  },
  tabActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.primaryBlue,
  },
  tabText: {
    ...Typography.footnote,
    color: Colors.textSecondary,
  },
  tabTextActive: {
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  tabContent: {
    flex: 1,
    padding: Padding.padding16,
  },
  card: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding16,
    marginBottom: Spacing.medium,
  },
  cardTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.medium,
  },
  summaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.small,
  },
  summaryText: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  performanceGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.medium,
  },
  performanceCard: {
    flex: 1,
    minWidth: '45%',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding12,
    borderWidth: 1,
  },
  performanceCardHeader: {
    marginBottom: Spacing.small,
  },
  performanceCardValue: {
    ...Typography.title2,
    color: Colors.textPrimary,
    marginBottom: Spacing.xxSmall,
  },
  performanceCardTitle: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  metricView: {
    alignItems: 'center',
  },
  metricValue: {
    ...Typography.footnote,
    fontWeight: '600',
  },
  metricLabel: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  messagesList: {
    padding: Padding.padding16,
  },
  messageRow: {
    backgroundColor: Colors.backgroundPrimary,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding16,
    marginBottom: Spacing.medium,
  },
  messageRowHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.small,
  },
  messageRowTitle: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  messageRowBadges: {
    flexDirection: 'row',
    gap: Spacing.small,
  },
  badge: {
    paddingHorizontal: Spacing.small,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
  },
  badgeBlue: {
    backgroundColor: Colors.badgeBlue,
  },
  badgePurple: {
    backgroundColor: Colors.badgePurple,
  },
  badgeTextBlue: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  badgeTextPurple: {
    ...Typography.caption2,
    color: Colors.primaryPurple,
    fontWeight: '600',
  },
  metricsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.large,
    marginBottom: Spacing.small,
  },
  messagePreview: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  modelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding12,
    marginBottom: Spacing.small,
  },
  modelInfo: {
    flex: 1,
  },
  modelName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '500',
  },
  modelMessages: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  modelStats: {
    alignItems: 'flex-end',
  },
  modelStatValue: {
    ...Typography.caption,
    color: Colors.statusGreen,
  },
  modelStatSpeed: {
    ...Typography.caption,
    color: Colors.primaryBlue,
  },
  thinkingAnalysis: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: `${Colors.primaryPurple}10`,
    borderRadius: BorderRadius.regular,
    padding: Padding.padding12,
  },
  thinkingText: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: Padding.padding40,
  },
  emptyText: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginTop: Spacing.medium,
  },
  emptySubtext: {
    ...Typography.footnote,
    color: Colors.textTertiary,
    marginTop: Spacing.xSmall,
  },
});

export default ChatAnalyticsScreen;
