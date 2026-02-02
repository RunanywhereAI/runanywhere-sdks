/**
 * ChatInput Component
 *
 * Text input with send button for chat messages.
 *
 * Reference: iOS ChatInterfaceView input area
 */

import React, { useState } from 'react';
import {
  View,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../../theme/colors';
import { Typography } from '../../theme/typography';
import {
  Spacing,
  BorderRadius,
  Padding,
  ButtonHeight,
  Layout,
} from '../../theme/spacing';

interface ChatInputProps {
  /** Current input value */
  value: string;
  /** Callback when value changes */
  onChangeText: (text: string) => void;
  /** Callback when send button pressed */
  onSend: () => void;
  /** Whether input is disabled */
  disabled?: boolean;
  /** Placeholder text */
  placeholder?: string;
  /** Whether currently sending/generating */
  isLoading?: boolean;
}

export const ChatInput: React.FC<ChatInputProps> = ({
  value,
  onChangeText,
  onSend,
  disabled = false,
  placeholder = 'Type a message...',
  isLoading = false,
}) => {
  const [inputHeight, setInputHeight] = useState<number>(Layout.inputMinHeight);
  const canSend = value.trim().length > 0 && !disabled && !isLoading;

  const handleContentSizeChange = (event: {
    nativeEvent: { contentSize: { height: number } };
  }) => {
    const height = event.nativeEvent.contentSize.height;
    // Clamp between min and max (4 lines max)
    const clampedHeight = Math.min(
      Math.max(height, Layout.inputMinHeight),
      120
    );
    setInputHeight(clampedHeight);
  };

  const handleSend = () => {
    if (canSend) {
      onSend();
    }
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
    >
      <View style={styles.container}>
        <View style={styles.inputContainer}>
          <TextInput
            style={[
              styles.input,
              { height: Math.max(inputHeight, Layout.inputMinHeight) },
            ]}
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor={Colors.textTertiary}
            multiline
            editable={!disabled}
            onContentSizeChange={handleContentSizeChange}
            returnKeyType="default"
            blurOnSubmit={false}
          />

          <TouchableOpacity
            style={[
              styles.sendButton,
              canSend ? styles.sendButtonActive : styles.sendButtonInactive,
            ]}
            onPress={handleSend}
            disabled={!canSend}
            activeOpacity={0.7}
          >
            <Icon
              name={isLoading ? 'stop' : 'arrow-up'}
              size={20}
              color={canSend ? Colors.textWhite : Colors.textTertiary}
            />
          </TouchableOpacity>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: Colors.backgroundPrimary,
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding10,
    paddingBottom:
      Platform.OS === 'ios' ? Padding.padding20 : Padding.padding10,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: Spacing.smallMedium,
  },
  input: {
    flex: 1,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.large,
    paddingHorizontal: Padding.padding16,
    paddingTop: Padding.padding12,
    paddingBottom: Padding.padding12,
    ...Typography.body,
    color: Colors.textPrimary,
    maxHeight: 120,
  },
  sendButton: {
    width: ButtonHeight.regular,
    height: ButtonHeight.regular,
    borderRadius: ButtonHeight.regular / 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendButtonActive: {
    backgroundColor: Colors.primaryBlue,
  },
  sendButtonInactive: {
    backgroundColor: Colors.backgroundGray5,
  },
});

export default ChatInput;
