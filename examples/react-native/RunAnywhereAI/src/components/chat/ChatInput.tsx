/**
 * ChatInput — the chat composer: an auto-growing pill text field with a send /
 * stop action button, themed on the design system.
 *
 * Keyboard handling: tracks the IME height per-pixel via reanimated's
 * useAnimatedKeyboard() so the bar rides up smoothly with the keyboard, and
 * falls back to the bottom safe-area inset (gesture nav bar) when it's closed.
 * Send turns into a stop control (white rounded square) while generating.
 */
import React, { useState } from 'react';
import { View, TextInput, TouchableOpacity, StyleSheet } from 'react-native';
import Animated, {
  useAnimatedKeyboard,
  useAnimatedStyle,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon, useTheme } from '../../theme/system';

interface ChatInputProps {
  value: string;
  onChangeText: (text: string) => void;
  onSend: () => void;
  onStop?: () => void;
  disabled?: boolean;
  placeholder?: string;
  isLoading?: boolean;
}

const MIN_HEIGHT = 24;
const MAX_HEIGHT = 120;

export const ChatInput: React.FC<ChatInputProps> = ({
  value,
  onChangeText,
  onSend,
  onStop,
  disabled = false,
  placeholder = 'Type a message…',
  isLoading = false,
}) => {
  const { colors, typography } = useTheme();
  const insets = useSafeAreaInsets();
  const keyboard = useAnimatedKeyboard();
  const [inputHeight, setInputHeight] = useState(MIN_HEIGHT);

  const canSend = value.trim().length > 0 && !disabled && !isLoading;
  const canStop = isLoading && !!onStop;
  const canPressAction = canSend || canStop;

  // Under edge-to-edge the window isn't resized for us, so lift the bar by the
  // keyboard height. reanimated reports that height from the very bottom of the
  // screen (including the gesture nav region), so subtract the bottom inset to
  // sit snug on the keyboard. When closed, rest on the bottom safe-area inset.
  const animatedStyle = useAnimatedStyle(() => ({
    paddingBottom:
      keyboard.height.value > 0
        ? Math.max(keyboard.height.value - insets.bottom, 8)
        : Math.max(insets.bottom, 8),
  }));

  const handleContentSizeChange = (event: {
    nativeEvent: { contentSize: { height: number } };
  }) => {
    const h = event.nativeEvent.contentSize.height;
    setInputHeight(Math.min(Math.max(h, MIN_HEIGHT), MAX_HEIGHT));
  };

  const handleAction = () => {
    if (canStop) onStop?.();
    else if (canSend) onSend();
  };

  return (
    <Animated.View
      style={[
        styles.container,
        {
          backgroundColor: colors.surface,
          borderTopColor: colors.outlineVariant,
        },
        animatedStyle,
      ]}
    >
      <View
        style={[styles.field, { backgroundColor: colors.surfaceContainerHigh }]}
      >
        <TextInput
          style={[
            styles.input,
            typography.bodyLarge,
            { color: colors.onSurface, height: inputHeight },
          ]}
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor={colors.onSurfaceVariant}
          multiline
          editable={!disabled}
          onContentSizeChange={handleContentSizeChange}
          returnKeyType="default"
          submitBehavior="newline"
        />

        <TouchableOpacity
          style={[
            styles.action,
            {
              backgroundColor: canPressAction
                ? colors.primary
                : colors.surfaceVariant,
            },
          ]}
          onPress={handleAction}
          disabled={!canPressAction}
          activeOpacity={0.8}
        >
          {canStop ? (
            <View style={[styles.stop, { backgroundColor: colors.onPrimary }]} />
          ) : (
            <Icon
              name="send"
              size={20}
              color={canPressAction ? colors.onPrimary : colors.onSurfaceVariant}
            />
          )}
        </TouchableOpacity>
      </View>
    </Animated.View>
  );
};

const styles = StyleSheet.create({
  container: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingTop: 10,
  },
  field: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
    borderRadius: 24,
    paddingLeft: 16,
    paddingRight: 6,
    paddingVertical: 6,
  },
  input: {
    flex: 1,
    paddingTop: 8,
    paddingBottom: 8,
    maxHeight: MAX_HEIGHT,
  },
  action: {
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
  },
  stop: {
    width: 13,
    height: 13,
    borderRadius: 3,
  },
});

export default ChatInput;
