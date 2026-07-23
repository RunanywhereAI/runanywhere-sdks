/**
 * VLMScreen - Vision Chat (VLM) camera view
 *
 * Complete VLM camera interface with:
 * - Live camera preview (45% screen height)
 * - Description panel with streaming tokens
 * - 4-button control bar (Photos, Main, Live, Model)
 * - Processing overlay during capture
 * - Model required overlay when no VLM loaded
 * - Three modes: single capture, gallery selection, auto-streaming
 *
 * Reference: iOS VLMCameraView.swift
 */

import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  useWindowDimensions,
  Linking,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Camera, useCameraDevice } from 'react-native-vision-camera';
import Icon from 'react-native-vector-icons/Ionicons';
import Clipboard from '@react-native-clipboard/clipboard';
import { useVLMCamera } from '../hooks/useVLMCamera';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model/ModelSelectionSheet';
import { type ModelInfo as SDKModelInfo } from '@runanywhere/proto-ts/model_types';
import {
  typography,
  useTheme,
  useThemedStyles,
  type ColorScheme,
} from '../theme/system';

const VLMScreen: React.FC = () => {
  const { colors } = useTheme();
  const styles = useThemedStyles(createStyles);
  const { height: screenHeight } = useWindowDimensions();
  const cameraRef = useRef<Camera>(null);
  const device = useCameraDevice('back');

  // VLM hook state and actions
  const vlm = useVLMCamera(cameraRef);

  // Local UI state
  const [showingModelSelection, setShowingModelSelection] = useState(false);

  // Request camera permission on mount
  useEffect(() => {
    vlm.requestCameraPermission();
  }, [vlm]);

  // Check model status on mount
  useEffect(() => {
    vlm.checkModelStatus();
  }, [vlm]);

  // Handle model selection
  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      // 1. Load the model FIRST
      await vlm.loadModel(model.id, model.name);
      await vlm.checkModelStatus();

      // 2. Close the modal AFTER the model is safely loaded and state is stable
      setShowingModelSelection(false);
    },
    [vlm]
  );

  // Copy description to clipboard
  const handleCopyDescription = useCallback(() => {
    if (vlm.currentDescription) {
      Clipboard.setString(vlm.currentDescription);
    }
  }, [vlm.currentDescription]);

  // Open system settings for camera permission
  const handleOpenSettings = useCallback(() => {
    Linking.openSettings();
  }, []);

  // Main action button handler
  const handleMainAction = useCallback(() => {
    if (vlm.isAutoStreaming) {
      vlm.toggleAutoStreaming();
    } else {
      vlm.captureAndDescribe();
    }
  }, [vlm]);

  const handleDismissError = useCallback(() => {
    vlm.clearError();
  }, [vlm]);

  // Main action button color — brand primary for capture, error red for stop
  const mainButtonColor = vlm.isAutoStreaming
    ? colors.error
    : vlm.isProcessing
      ? colors.outline
      : colors.primary;

  return (
    <SafeAreaView style={styles.container}>
      {/* Model Required Overlay */}
      {!vlm.isModelLoaded && (
        <View style={styles.modelRequiredOverlay}>
          <Icon
            name="scan-outline"
            size={48}
            color={colors.primary}
            style={styles.modelRequiredIcon}
          />
          <Text style={styles.modelRequiredTitle}>Vision AI</Text>
          <Text style={styles.modelRequiredSubtitle}>
            Load a vision-language model to describe images and scenes
          </Text>
          <TouchableOpacity
            style={styles.selectModelButton}
            onPress={() => setShowingModelSelection(true)}
            activeOpacity={0.8}
          >
            <Text style={styles.selectModelButtonText}>Select Model</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Main Content (when model loaded) */}
      {vlm.isModelLoaded && (
        <View style={styles.mainContent}>
          {/* Camera Preview */}
          <View style={[styles.cameraPreview, { height: screenHeight * 0.45 }]}>
            {device && vlm.isCameraAuthorized ? (
              <Camera
                ref={cameraRef}
                device={device}
                isActive={true}
                photo={true}
                style={StyleSheet.absoluteFill}
              />
            ) : !vlm.isCameraAuthorized ? (
              <View style={styles.cameraPermissionView}>
                <Icon
                  name="camera"
                  size={48}
                  color={colors.onSurfaceVariant}
                  style={styles.cameraPermissionIcon}
                />
                <Text style={styles.cameraPermissionTitle}>
                  Camera Access Required
                </Text>
                <TouchableOpacity
                  style={styles.openSettingsButton}
                  onPress={handleOpenSettings}
                  activeOpacity={0.7}
                >
                  <Text style={styles.openSettingsButtonText}>
                    Open Settings
                  </Text>
                </TouchableOpacity>
              </View>
            ) : (
              <View style={styles.cameraPermissionView}>
                <Text style={styles.cameraPermissionTitle}>
                  No camera available
                </Text>
              </View>
            )}

            {/* Processing Overlay */}
            {vlm.isProcessing && (
              <View style={styles.processingOverlay}>
                <View style={styles.processingContent}>
                  <ActivityIndicator size="small" color="#FFFFFF" />
                  <Text style={styles.processingText}>Analyzing...</Text>
                </View>
              </View>
            )}
          </View>

          {/* Description Panel */}
          <View style={styles.descriptionPanel}>
            {/* Header Row */}
            <View style={styles.descriptionHeader}>
              <View style={styles.descriptionTitleRow}>
                <Text style={styles.descriptionTitle}>Description</Text>
                {vlm.isAutoStreaming && (
                  <View style={styles.liveBadge}>
                    <View style={styles.liveDot} />
                    <Text style={styles.liveText}>LIVE</Text>
                  </View>
                )}
              </View>
              {vlm.currentDescription && (
                <TouchableOpacity
                  onPress={handleCopyDescription}
                  activeOpacity={0.7}
                >
                  <Icon
                    name="copy-outline"
                    size={18}
                    color={colors.onSurfaceVariant}
                  />
                </TouchableOpacity>
              )}
            </View>

            {/* Error Banner */}
            {vlm.error && (
              <TouchableOpacity
                style={styles.errorBanner}
                onPress={handleDismissError}
                accessibilityRole="button"
                accessibilityLabel="Dismiss error"
              >
                <Text style={styles.errorText}>{vlm.error}</Text>
                <Icon
                  name="close"
                  size={18}
                  color={colors.onErrorContainer}
                  style={styles.errorDismissIcon}
                />
              </TouchableOpacity>
            )}

            {/* Description Content */}
            <ScrollView
              style={styles.descriptionScroll}
              contentContainerStyle={styles.descriptionScrollContent}
              showsVerticalScrollIndicator={true}
            >
              <Text
                style={[
                  styles.descriptionText,
                  !vlm.currentDescription && styles.descriptionPlaceholder,
                ]}
              >
                {vlm.currentDescription ||
                  'Tap capture to describe what your camera sees'}
              </Text>
            </ScrollView>
          </View>

          {/* Control Bar */}
          <View style={styles.controlBar}>
            {/* Photos Button */}
            <TouchableOpacity
              style={styles.controlButton}
              onPress={vlm.selectPhotoAndDescribe}
              disabled={vlm.isProcessing}
              activeOpacity={0.7}
            >
              <Icon
                name="images-outline"
                size={24}
                color={vlm.isProcessing ? colors.outline : colors.primary}
              />
            </TouchableOpacity>

            {/* Main Action Button */}
            <TouchableOpacity
              style={[
                styles.mainActionButton,
                { backgroundColor: mainButtonColor },
              ]}
              onPress={handleMainAction}
              disabled={vlm.isProcessing && !vlm.isAutoStreaming}
              activeOpacity={0.8}
            >
              <Icon
                name={vlm.isAutoStreaming ? 'stop' : 'camera'}
                size={28}
                color="#FFFFFF"
              />
            </TouchableOpacity>

            {/* Live Button */}
            <TouchableOpacity
              style={styles.controlButton}
              onPress={vlm.toggleAutoStreaming}
              disabled={vlm.isProcessing && !vlm.isAutoStreaming}
              activeOpacity={0.7}
            >
              <Icon
                name="radio-outline"
                size={24}
                color={
                  vlm.isAutoStreaming
                    ? colors.success
                    : vlm.isProcessing
                      ? colors.outline
                      : colors.primary
                }
              />
            </TouchableOpacity>

            {/* Model Button */}
            <TouchableOpacity
              style={styles.controlButton}
              onPress={() => setShowingModelSelection(true)}
              activeOpacity={0.7}
            >
              <Icon
                name="hardware-chip-outline"
                size={24}
                color={colors.primary}
              />
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showingModelSelection}
        context={ModelSelectionContext.VLM}
        onModelSelected={handleModelSelected}
        onClose={() => setShowingModelSelection(false)}
      />
    </SafeAreaView>
  );
};

const createStyles = (colors: ColorScheme) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.background,
    },
    mainContent: {
      flex: 1,
    },

    // Model Required Overlay (always-dark scrim, so text stays literal white)
    modelRequiredOverlay: {
      ...StyleSheet.absoluteFill,
      backgroundColor: 'rgba(0, 0, 0, 0.5)',
      justifyContent: 'center',
      alignItems: 'center',
      paddingHorizontal: 24,
      zIndex: 100,
    },
    modelRequiredIcon: {
      marginBottom: 16,
    },
    modelRequiredTitle: {
      ...typography.titleLarge,
      color: '#FFFFFF',
      marginBottom: 6,
      textAlign: 'center',
    },
    modelRequiredSubtitle: {
      ...typography.bodyLarge,
      color: 'rgba(255, 255, 255, 0.7)',
      textAlign: 'center',
      marginBottom: 20,
    },
    selectModelButton: {
      backgroundColor: colors.primary,
      paddingHorizontal: 24,
      paddingVertical: 12,
      borderRadius: 10,
    },
    selectModelButtonText: {
      ...typography.titleMedium,
      color: colors.onPrimary,
    },

    // Camera Preview
    cameraPreview: {
      backgroundColor: colors.background,
      position: 'relative',
    },
    cameraPermissionView: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      backgroundColor: colors.surfaceContainer,
    },
    cameraPermissionIcon: {
      marginBottom: 10,
    },
    cameraPermissionTitle: {
      ...typography.titleMedium,
      color: colors.onSurface,
      marginBottom: 10,
    },
    openSettingsButton: {
      backgroundColor: colors.primary,
      paddingHorizontal: 16,
      paddingVertical: 8,
      borderRadius: 8,
    },
    openSettingsButtonText: {
      ...typography.bodyLarge,
      color: colors.onPrimary,
    },

    // Processing Overlay
    processingOverlay: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      justifyContent: 'flex-end',
      alignItems: 'center',
      paddingBottom: 16,
    },
    processingContent: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: 'rgba(0, 0, 0, 0.6)',
      paddingHorizontal: 16,
      paddingVertical: 12,
      borderRadius: 20,
    },
    processingText: {
      ...typography.bodySmall,
      color: '#FFFFFF',
      marginLeft: 8,
    },

    // Description Panel
    descriptionPanel: {
      flex: 1,
      backgroundColor: colors.background,
      paddingHorizontal: 16,
      paddingVertical: 14,
    },
    descriptionHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      marginBottom: 12,
    },
    descriptionTitleRow: {
      flexDirection: 'row',
      alignItems: 'center',
    },
    descriptionTitle: {
      ...typography.titleMedium,
      color: colors.onSurface,
    },
    liveBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: `${colors.success}20`,
      paddingHorizontal: 8,
      paddingVertical: 2,
      borderRadius: 4,
      marginLeft: 6,
    },
    liveDot: {
      width: 8,
      height: 8,
      borderRadius: 4,
      backgroundColor: colors.success,
      marginRight: 4,
    },
    liveText: {
      ...typography.labelSmall,
      color: colors.success,
      fontWeight: '700',
    },
    errorBanner: {
      backgroundColor: colors.errorContainer,
      padding: 8,
      borderRadius: 8,
      marginBottom: 10,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    errorText: {
      ...typography.bodySmall,
      color: colors.onErrorContainer,
      flex: 1,
    },
    errorDismissIcon: {
      marginLeft: 6,
    },
    descriptionScroll: {
      flex: 1,
    },
    descriptionScrollContent: {
      flexGrow: 1,
    },
    descriptionText: {
      ...typography.bodyLarge,
      color: colors.onSurface,
      lineHeight: 22,
    },
    descriptionPlaceholder: {
      color: colors.onSurfaceVariant,
    },

    // Control Bar
    controlBar: {
      flexDirection: 'row',
      justifyContent: 'space-evenly',
      alignItems: 'center',
      backgroundColor: colors.background,
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: colors.outlineVariant,
      paddingVertical: 16,
      paddingHorizontal: 16,
    },
    controlButton: {
      padding: 10,
    },
    mainActionButton: {
      width: 64,
      height: 64,
      borderRadius: 32,
      justifyContent: 'center',
      alignItems: 'center',
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.25,
      shadowRadius: 4,
      elevation: 5,
    },
  });

export default VLMScreen;
