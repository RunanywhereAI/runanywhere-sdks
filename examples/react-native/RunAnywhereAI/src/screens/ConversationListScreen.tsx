/**
 * ConversationListScreen - Modal for managing conversations
 *
 * Reference: iOS Core/Services/ConversationStore.swift (ConversationListView)
 *
 * Features:
 * - List all conversations with search
 * - Create new conversation
 * - Delete conversation with confirmation
 * - Switch between conversations
 */

import React, { useState, useCallback, useMemo } from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  TextInput,
  Alert,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, IconSize } from '../theme/spacing';
import type { Conversation } from '../types/chat';
import {
  useConversationStore,
  getConversationSummary,
  getLastMessagePreview,
  formatRelativeDate,
} from '../stores/conversationStore';

interface ConversationListScreenProps {
  onClose: () => void;
  onSelectConversation: (conversation: Conversation) => void;
}

/**
 * ConversationRow - Individual conversation item in list
 * Matches iOS ConversationRow struct
 */
interface ConversationRowProps {
  conversation: Conversation;
  onPress: () => void;
  onDelete: () => void;
}

/**
 * Stable separator component to avoid react/no-unstable-nested-components
 */
const ItemSeparator: React.FC = () => <View style={styles.separator} />;

const ConversationRow: React.FC<ConversationRowProps> = ({
  conversation,
  onPress,
  onDelete,
}) => {
  const handleDelete = useCallback(() => {
    Alert.alert(
      'Delete Conversation',
      `Are you sure you want to delete "${conversation.title}"? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: onDelete,
        },
      ]
    );
  }, [conversation.title, onDelete]);

  return (
    <TouchableOpacity style={styles.conversationRow} onPress={onPress}>
      <View style={styles.conversationContent}>
        {/* Title */}
        <Text style={styles.conversationTitle} numberOfLines={1}>
          {conversation.title}
        </Text>

        {/* Last message preview */}
        <Text style={styles.conversationPreview} numberOfLines={2}>
          {getLastMessagePreview(conversation)}
        </Text>

        {/* Summary line */}
        <Text style={styles.conversationSummary}>
          {getConversationSummary(conversation)}
        </Text>

        {/* Bottom row: date and framework badge */}
        <View style={styles.conversationBottom}>
          <Text style={styles.conversationDate}>
            {formatRelativeDate(conversation.updatedAt)}
          </Text>

          {conversation.frameworkName && (
            <View style={styles.frameworkBadge}>
              <Text style={styles.frameworkBadgeText}>
                {conversation.frameworkName}
              </Text>
            </View>
          )}
        </View>
      </View>

      {/* Delete button */}
      <TouchableOpacity
        style={styles.deleteButton}
        onPress={handleDelete}
        hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
      >
        <Icon name="trash-outline" size={20} color={Colors.primaryRed} />
      </TouchableOpacity>
    </TouchableOpacity>
  );
};

export const ConversationListScreen: React.FC<ConversationListScreenProps> = ({
  onClose,
  onSelectConversation,
}) => {
  const [searchQuery, setSearchQuery] = useState('');

  const {
    conversations,
    createConversation,
    deleteConversation,
    searchConversations,
  } = useConversationStore();

  // Filter conversations based on search
  const filteredConversations = useMemo(() => {
    if (!searchQuery.trim()) {
      return conversations;
    }
    return searchConversations(searchQuery);
  }, [conversations, searchQuery, searchConversations]);

  /**
   * Handle creating a new conversation
   */
  const handleCreateConversation = useCallback(async () => {
    const newConversation = await createConversation();
    onSelectConversation(newConversation);
    onClose();
  }, [createConversation, onSelectConversation, onClose]);

  /**
   * Handle selecting a conversation
   */
  const handleSelectConversation = useCallback(
    (conversation: Conversation) => {
      onSelectConversation(conversation);
      onClose();
    },
    [onSelectConversation, onClose]
  );

  /**
   * Handle deleting a conversation
   */
  const handleDeleteConversation = useCallback(
    async (conversationId: string) => {
      await deleteConversation(conversationId);
    },
    [deleteConversation]
  );

  /**
   * Render a conversation item
   */
  const renderConversation = ({ item }: { item: Conversation }) => (
    <ConversationRow
      conversation={item}
      onPress={() => handleSelectConversation(item)}
      onDelete={() => handleDeleteConversation(item.id)}
    />
  );

  /**
   * Render empty state
   */
  const renderEmptyState = () => (
    <View style={styles.emptyState}>
      <View style={styles.emptyIconContainer}>
        <Icon
          name="chatbubbles-outline"
          size={IconSize.large}
          color={Colors.textTertiary}
        />
      </View>
      <Text style={styles.emptyTitle}>
        {searchQuery ? 'No conversations found' : 'No conversations yet'}
      </Text>
      <Text style={styles.emptySubtitle}>
        {searchQuery
          ? 'Try a different search term'
          : 'Tap the + button to start a new conversation'}
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.headerButton} onPress={onClose}>
          <Text style={styles.doneText}>Done</Text>
        </TouchableOpacity>

        <Text style={styles.title}>Conversations</Text>

        <TouchableOpacity
          style={styles.headerButton}
          onPress={handleCreateConversation}
        >
          <Icon name="add" size={28} color={Colors.primaryBlue} />
        </TouchableOpacity>
      </View>

      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <Icon
          name="search"
          size={18}
          color={Colors.textTertiary}
          style={styles.searchIcon}
        />
        <TextInput
          style={styles.searchInput}
          placeholder="Search conversations..."
          placeholderTextColor={Colors.textTertiary}
          value={searchQuery}
          onChangeText={setSearchQuery}
          autoCapitalize="none"
          autoCorrect={false}
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity
            onPress={() => setSearchQuery('')}
            style={styles.clearButton}
          >
            <Icon name="close-circle" size={18} color={Colors.textTertiary} />
          </TouchableOpacity>
        )}
      </View>

      {/* Conversations List */}
      <FlatList
        data={filteredConversations}
        renderItem={renderConversation}
        keyExtractor={(item) => item.id}
        contentContainerStyle={[
          styles.listContent,
          filteredConversations.length === 0 && styles.emptyListContent,
        ]}
        ListEmptyComponent={renderEmptyState}
        showsVerticalScrollIndicator={false}
        ItemSeparatorComponent={ItemSeparator}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  headerButton: {
    minWidth: 60,
  },
  doneText: {
    ...Typography.body,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
    textAlign: 'center',
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    marginHorizontal: Padding.padding16,
    marginVertical: Padding.padding12,
    paddingHorizontal: Padding.padding12,
  },
  searchIcon: {
    marginRight: Spacing.small,
  },
  searchInput: {
    flex: 1,
    ...Typography.body,
    color: Colors.textPrimary,
    paddingVertical: Padding.padding12,
  },
  clearButton: {
    padding: Spacing.small,
  },
  listContent: {
    paddingBottom: Spacing.large,
  },
  emptyListContent: {
    flex: 1,
    justifyContent: 'center',
  },
  separator: {
    height: 1,
    backgroundColor: Colors.borderLight,
    marginHorizontal: Padding.padding16,
  },
  conversationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
  },
  conversationContent: {
    flex: 1,
    marginRight: Spacing.medium,
  },
  conversationTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.xSmall,
  },
  conversationPreview: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    marginBottom: Spacing.xSmall,
    lineHeight: 20,
  },
  conversationSummary: {
    ...Typography.caption,
    color: Colors.textTertiary,
    marginBottom: Spacing.xSmall,
  },
  conversationBottom: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
  },
  conversationDate: {
    ...Typography.caption2,
    color: Colors.textTertiary,
  },
  frameworkBadge: {
    backgroundColor: Colors.primaryBlue + '20',
    paddingHorizontal: Spacing.small,
    paddingVertical: 2,
    borderRadius: BorderRadius.small,
  },
  frameworkBadgeText: {
    ...Typography.caption2,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  deleteButton: {
    padding: Spacing.small,
  },
  emptyState: {
    alignItems: 'center',
    padding: Padding.padding40,
  },
  emptyIconContainer: {
    width: IconSize.huge,
    height: IconSize.huge,
    borderRadius: IconSize.huge / 2,
    backgroundColor: Colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.large,
  },
  emptyTitle: {
    ...Typography.title3,
    color: Colors.textPrimary,
    marginBottom: Spacing.small,
  },
  emptySubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    maxWidth: 280,
  },
});

export default ConversationListScreen;
