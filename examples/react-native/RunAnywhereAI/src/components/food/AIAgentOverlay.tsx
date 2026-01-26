/**
 * AIAgentOverlay - Voice-powered AI ordering assistant
 * 
 * Shows step-by-step progress as the AI processes orders
 */

import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Modal,
  TouchableOpacity,
  ScrollView,
  Animated,
  Dimensions,
  ActivityIndicator,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { DoorDashColors, DoorDashTypography, DoorDashSpacing, DoorDashShadows } from '../../theme/doordash';
import type { CartItem } from '../../data/foodData';

const { height: SCREEN_HEIGHT } = Dimensions.get('window');

export interface AgentStep {
  id: string;
  type: 'thinking' | 'searching' | 'found' | 'adding' | 'cart' | 'confirm' | 'success' | 'error';
  title: string;
  content: string;
  timestamp: Date;
  isComplete: boolean;
}

interface AIAgentOverlayProps {
  visible: boolean;
  onClose: () => void;
  steps: AgentStep[];
  isProcessing: boolean;
  userQuery: string;
  cartItems: CartItem[];
  cartTotal: number;
  onConfirmOrder: () => void;
  onCancelOrder: () => void;
}

const StepIcon: React.FC<{ type: AgentStep['type']; isComplete: boolean }> = ({ type, isComplete }) => {
  if (!isComplete) {
    return <ActivityIndicator size="small" color={DoorDashColors.primary} />;
  }
  
  const iconMap: Record<string, { name: string; color: string; bg: string }> = {
    thinking: { name: 'bulb', color: DoorDashColors.warning, bg: DoorDashColors.warningLight },
    searching: { name: 'search', color: DoorDashColors.promoBlue, bg: '#E6F0FF' },
    found: { name: 'checkmark-circle', color: DoorDashColors.success, bg: DoorDashColors.successLight },
    adding: { name: 'cart', color: DoorDashColors.primary, bg: '#FFEBE8' },
    cart: { name: 'receipt', color: DoorDashColors.dashPassPurple, bg: DoorDashColors.dashPassBackground },
    confirm: { name: 'shield-checkmark', color: DoorDashColors.success, bg: DoorDashColors.successLight },
    success: { name: 'checkmark-done-circle', color: DoorDashColors.success, bg: DoorDashColors.successLight },
    error: { name: 'alert-circle', color: DoorDashColors.error, bg: DoorDashColors.errorLight },
  };
  
  const icon = iconMap[type] || iconMap.thinking;
  
  return (
    <View style={[styles.stepIconContainer, { backgroundColor: icon.bg }]}>
      <Icon name={icon.name} size={20} color={icon.color} />
    </View>
  );
};

export const AIAgentOverlay: React.FC<AIAgentOverlayProps> = ({
  visible,
  onClose,
  steps,
  isProcessing,
  userQuery,
  cartItems,
  cartTotal,
  onConfirmOrder,
  onCancelOrder,
}) => {
  const slideAnim = useRef(new Animated.Value(SCREEN_HEIGHT)).current;
  const scrollViewRef = useRef<ScrollView>(null);
  
  useEffect(() => {
    if (visible) {
      Animated.spring(slideAnim, {
        toValue: 0,
        useNativeDriver: true,
        tension: 65,
        friction: 11,
      }).start();
    } else {
      Animated.timing(slideAnim, {
        toValue: SCREEN_HEIGHT,
        duration: 300,
        useNativeDriver: true,
      }).start();
    }
  }, [visible, slideAnim]);
  
  useEffect(() => {
    // Auto-scroll to bottom when new steps are added
    if (scrollViewRef.current && steps.length > 0) {
      setTimeout(() => {
        scrollViewRef.current?.scrollToEnd({ animated: true });
      }, 100);
    }
  }, [steps.length]);
  
  const showOrderConfirmation = steps.some(s => s.type === 'cart' && s.isComplete) && !isProcessing;
  
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <View style={styles.overlay}>
        <Animated.View
          style={[
            styles.container,
            { transform: [{ translateY: slideAnim }] },
          ]}
        >
          {/* Header */}
          <View style={styles.header}>
            <View style={styles.headerLeft}>
              <View style={styles.aiAvatarContainer}>
                <Text style={styles.aiAvatar}>🤖</Text>
                {isProcessing && (
                  <View style={styles.processingDot} />
                )}
              </View>
              <View>
                <Text style={styles.headerTitle}>AI Food Agent</Text>
                <Text style={styles.headerSubtitle}>
                  {isProcessing ? 'Processing...' : 'Ready to help'}
                </Text>
              </View>
            </View>
            <TouchableOpacity onPress={onClose} style={styles.closeButton}>
              <Icon name="close" size={24} color={DoorDashColors.textSecondary} />
            </TouchableOpacity>
          </View>
          
          {/* On-Device Badge */}
          <View style={styles.onDeviceBadge}>
            <Icon name="shield-checkmark" size={14} color={DoorDashColors.success} />
            <Text style={styles.onDeviceText}>100% On-Device • Private • No Cloud</Text>
          </View>
          
          {/* User Query */}
          {userQuery && (
            <View style={styles.userQueryContainer}>
              <Icon name="mic" size={18} color={DoorDashColors.primary} />
              <Text style={styles.userQueryText}>"{userQuery}"</Text>
            </View>
          )}
          
          {/* Steps */}
          <ScrollView
            ref={scrollViewRef}
            style={styles.stepsContainer}
            contentContainerStyle={styles.stepsContent}
            showsVerticalScrollIndicator={false}
          >
            {steps.map((step, index) => (
              <View key={step.id} style={styles.stepItem}>
                <StepIcon type={step.type} isComplete={step.isComplete} />
                <View style={styles.stepContent}>
                  <Text style={styles.stepTitle}>{step.title}</Text>
                  <Text style={styles.stepDescription}>{step.content}</Text>
                </View>
                {index < steps.length - 1 && <View style={styles.stepConnector} />}
              </View>
            ))}
            
            {isProcessing && steps.length > 0 && (
              <View style={styles.thinkingIndicator}>
                <ActivityIndicator size="small" color={DoorDashColors.primary} />
                <Text style={styles.thinkingText}>Thinking...</Text>
              </View>
            )}
          </ScrollView>
          
          {/* Order Summary & Confirm */}
          {showOrderConfirmation && cartItems.length > 0 && (
            <View style={styles.orderSummary}>
              <View style={styles.orderHeader}>
                <Text style={styles.orderTitle}>Your Order</Text>
                <Text style={styles.orderTotal}>${cartTotal.toFixed(2)}</Text>
              </View>
              
              {cartItems.map((item, index) => (
                <View key={index} style={styles.orderItem}>
                  <Text style={styles.orderItemQty}>{item.quantity}x</Text>
                  <Text style={styles.orderItemName}>{item.menuItem.name}</Text>
                  <Text style={styles.orderItemPrice}>
                    ${(item.menuItem.price * item.quantity).toFixed(2)}
                  </Text>
                </View>
              ))}
              
              <View style={styles.orderActions}>
                <TouchableOpacity style={styles.cancelButton} onPress={onCancelOrder}>
                  <Text style={styles.cancelButtonText}>Cancel</Text>
                </TouchableOpacity>
                <TouchableOpacity style={styles.confirmButton} onPress={onConfirmOrder}>
                  <Text style={styles.confirmButtonText}>Place Order</Text>
                  <Icon name="arrow-forward" size={18} color={DoorDashColors.textWhite} />
                </TouchableOpacity>
              </View>
            </View>
          )}
        </Animated.View>
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: DoorDashColors.overlay,
    justifyContent: 'flex-end',
  },
  container: {
    backgroundColor: DoorDashColors.background,
    borderTopLeftRadius: DoorDashSpacing.radiusXLarge,
    borderTopRightRadius: DoorDashSpacing.radiusXLarge,
    maxHeight: SCREEN_HEIGHT * 0.85,
    minHeight: SCREEN_HEIGHT * 0.5,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: DoorDashSpacing.lg,
    borderBottomWidth: 1,
    borderBottomColor: DoorDashColors.divider,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.md,
  },
  aiAvatarContainer: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: DoorDashColors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  aiAvatar: {
    fontSize: 24,
  },
  processingDot: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: DoorDashColors.success,
    borderWidth: 2,
    borderColor: DoorDashColors.background,
  },
  headerTitle: {
    ...DoorDashTypography.headerSmall,
    color: DoorDashColors.textPrimary,
  },
  headerSubtitle: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
  },
  closeButton: {
    padding: DoorDashSpacing.sm,
  },
  onDeviceBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: DoorDashSpacing.xs,
    paddingVertical: DoorDashSpacing.sm,
    backgroundColor: DoorDashColors.successLight,
    marginHorizontal: DoorDashSpacing.lg,
    marginTop: DoorDashSpacing.md,
    borderRadius: DoorDashSpacing.radiusFull,
  },
  onDeviceText: {
    ...DoorDashTypography.caption,
    fontWeight: '600',
    color: DoorDashColors.success,
  },
  userQueryContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
    padding: DoorDashSpacing.md,
    margin: DoorDashSpacing.lg,
    backgroundColor: '#FFEBE8',
    borderRadius: DoorDashSpacing.radiusMedium,
    borderLeftWidth: 3,
    borderLeftColor: DoorDashColors.primary,
  },
  userQueryText: {
    ...DoorDashTypography.bodyMedium,
    color: DoorDashColors.textPrimary,
    fontStyle: 'italic',
    flex: 1,
  },
  stepsContainer: {
    flex: 1,
  },
  stepsContent: {
    padding: DoorDashSpacing.lg,
    paddingBottom: DoorDashSpacing.xxl,
  },
  stepItem: {
    flexDirection: 'row',
    marginBottom: DoorDashSpacing.lg,
    position: 'relative',
  },
  stepIconContainer: {
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: DoorDashSpacing.md,
  },
  stepContent: {
    flex: 1,
    paddingTop: 2,
  },
  stepTitle: {
    ...DoorDashTypography.bodyMedium,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
    marginBottom: 2,
  },
  stepDescription: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
    lineHeight: 18,
  },
  stepConnector: {
    position: 'absolute',
    left: 17,
    top: 40,
    width: 2,
    height: 20,
    backgroundColor: DoorDashColors.divider,
  },
  thinkingIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
    paddingVertical: DoorDashSpacing.md,
  },
  thinkingText: {
    ...DoorDashTypography.bodySmall,
    color: DoorDashColors.textSecondary,
    fontStyle: 'italic',
  },
  orderSummary: {
    borderTopWidth: 1,
    borderTopColor: DoorDashColors.divider,
    padding: DoorDashSpacing.lg,
    backgroundColor: DoorDashColors.backgroundSecondary,
  },
  orderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: DoorDashSpacing.md,
  },
  orderTitle: {
    ...DoorDashTypography.headerSmall,
    color: DoorDashColors.textPrimary,
  },
  orderTotal: {
    ...DoorDashTypography.headerSmall,
    color: DoorDashColors.primary,
  },
  orderItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: DoorDashSpacing.sm,
  },
  orderItemQty: {
    ...DoorDashTypography.bodyMedium,
    fontWeight: '600',
    color: DoorDashColors.textPrimary,
    width: 30,
  },
  orderItemName: {
    ...DoorDashTypography.bodyMedium,
    color: DoorDashColors.textPrimary,
    flex: 1,
  },
  orderItemPrice: {
    ...DoorDashTypography.bodyMedium,
    color: DoorDashColors.textSecondary,
  },
  orderActions: {
    flexDirection: 'row',
    gap: DoorDashSpacing.md,
    marginTop: DoorDashSpacing.lg,
  },
  cancelButton: {
    flex: 1,
    paddingVertical: DoorDashSpacing.md,
    borderRadius: DoorDashSpacing.radiusFull,
    borderWidth: 1,
    borderColor: DoorDashColors.border,
    alignItems: 'center',
  },
  cancelButtonText: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textPrimary,
  },
  confirmButton: {
    flex: 2,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: DoorDashSpacing.sm,
    paddingVertical: DoorDashSpacing.md,
    borderRadius: DoorDashSpacing.radiusFull,
    backgroundColor: DoorDashColors.primary,
    ...DoorDashShadows.button,
  },
  confirmButtonText: {
    ...DoorDashTypography.button,
    color: DoorDashColors.textWhite,
  },
});

export default AIAgentOverlay;
