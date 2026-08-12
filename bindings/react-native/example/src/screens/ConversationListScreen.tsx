/**
 * ConversationListScreen — conversation history in the app bottom sheet.
 *
 * Search, start a new chat, switch conversations, and delete with confirmation.
 * Rows show title, last-message preview, a relative date and the framework chip.
 */
import React, { useCallback, useMemo, useState } from 'react';
import {
  Alert,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { BottomSheet, BottomSheetScrollView } from '../components/ui/BottomSheet';
import { Icon, useTheme } from '../theme/system';
import type { Conversation } from '../types/chat';
import {
  useConversationStore,
  getLastMessagePreview,
  formatRelativeDate,
} from '../stores/conversationStore';

interface ConversationListScreenProps {
  visible: boolean;
  onClose: () => void;
  onSelectConversation: (conversation: Conversation) => void;
}

const SNAP_POINTS = ['85%'];

export const ConversationListScreen: React.FC<ConversationListScreenProps> = ({
  visible,
  onClose,
  onSelectConversation,
}) => {
  const { colors, typography } = useTheme();
  const [searchQuery, setSearchQuery] = useState('');

  const { conversations, createConversation, deleteConversation, searchConversations } =
    useConversationStore();

  const filtered = useMemo(
    () =>
      searchQuery.trim() ? searchConversations(searchQuery) : conversations,
    [conversations, searchQuery, searchConversations]
  );

  const handleCreate = useCallback(async () => {
    const created = await createConversation();
    onSelectConversation(created);
    onClose();
  }, [createConversation, onSelectConversation, onClose]);

  const handleSelect = useCallback(
    (conversation: Conversation) => {
      onSelectConversation(conversation);
      onClose();
    },
    [onSelectConversation, onClose]
  );

  const handleDelete = useCallback(
    (conversation: Conversation) => {
      Alert.alert(
        'Delete conversation',
        `Delete "${conversation.title}"? This can't be undone.`,
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: () => void deleteConversation(conversation.id),
          },
        ]
      );
    },
    [deleteConversation]
  );

  return (
    <BottomSheet visible={visible} onClose={onClose} snapPoints={SNAP_POINTS}>
      <View style={styles.header}>
        <Text style={[typography.titleLarge, styles.bold, { color: colors.onSurface }]}>
          Conversations
        </Text>
        <TouchableOpacity onPress={handleCreate} hitSlop={8}>
          <Icon name="newChat" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      <View
        style={[styles.search, { backgroundColor: colors.surfaceContainerHigh }]}
      >
        <Icon name="search" size={18} color={colors.onSurfaceVariant} />
        <TextInput
          style={[styles.searchInput, typography.bodyMedium, { color: colors.onSurface }]}
          placeholder="Search conversations"
          placeholderTextColor={colors.onSurfaceVariant}
          value={searchQuery}
          onChangeText={setSearchQuery}
          autoCapitalize="none"
          autoCorrect={false}
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity onPress={() => setSearchQuery('')} hitSlop={8}>
            <Icon name="close" size={18} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
        )}
      </View>

      <BottomSheetScrollView contentContainerStyle={styles.list}>
        {filtered.length === 0 ? (
          <View style={styles.empty}>
            <Icon name="chat" size={40} color={colors.onSurfaceVariant} />
            <Text style={[typography.titleSmall, styles.bold, { color: colors.onSurface }]}>
              {searchQuery ? 'No matches' : 'No conversations yet'}
            </Text>
            <Text
              style={[
                typography.bodyMedium,
                styles.emptyText,
                { color: colors.onSurfaceVariant },
              ]}
            >
              {searchQuery
                ? 'Try a different search term'
                : 'Start a new chat with the + button'}
            </Text>
          </View>
        ) : (
          <View
            style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}
          >
            {filtered.map((c, i) => (
              <View key={c.id}>
                {i > 0 && (
                  <View
                    style={[styles.divider, { backgroundColor: colors.outlineVariant }]}
                  />
                )}
                <TouchableOpacity
                  style={styles.row}
                  activeOpacity={0.7}
                  onPress={() => handleSelect(c)}
                >
                  <View style={styles.rowText}>
                    <Text
                      style={[typography.titleSmall, styles.bold, { color: colors.onSurface }]}
                      numberOfLines={1}
                    >
                      {c.title}
                    </Text>
                    <Text
                      style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
                      numberOfLines={1}
                    >
                      {getLastMessagePreview(c)}
                    </Text>
                    <View style={styles.metaRow}>
                      <Text
                        style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
                      >
                        {formatRelativeDate(c.updatedAt)}
                      </Text>
                      {!!c.frameworkName && (
                        <View
                          style={[styles.chip, { backgroundColor: colors.surfaceVariant }]}
                        >
                          <Text
                            style={[
                              typography.labelSmall,
                              styles.bold,
                              { color: colors.onSurfaceVariant },
                            ]}
                          >
                            {c.frameworkName}
                          </Text>
                        </View>
                      )}
                    </View>
                  </View>
                  <TouchableOpacity
                    style={styles.deleteBtn}
                    onPress={() => handleDelete(c)}
                    hitSlop={8}
                  >
                    <Icon name="trash" size={18} color={colors.error} />
                  </TouchableOpacity>
                </TouchableOpacity>
              </View>
            ))}
          </View>
        )}
      </BottomSheetScrollView>
    </BottomSheet>
  );
};

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingTop: 4,
    paddingBottom: 12,
  },
  search: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginHorizontal: 16,
    paddingHorizontal: 12,
    borderRadius: 14,
    marginBottom: 12,
  },
  searchInput: {
    flex: 1,
    paddingVertical: 11,
  },
  list: {
    paddingHorizontal: 16,
    paddingBottom: 24,
  },
  card: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    marginLeft: 14,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  rowText: {
    flex: 1,
    gap: 3,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 2,
  },
  chip: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
  },
  deleteBtn: {
    padding: 6,
  },
  empty: {
    alignItems: 'center',
    gap: 8,
    paddingVertical: 48,
  },
  emptyText: {
    textAlign: 'center',
    maxWidth: 260,
  },
  bold: {
    fontWeight: '700',
  },
});

export default ConversationListScreen;
