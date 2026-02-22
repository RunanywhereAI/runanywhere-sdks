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
  SafeAreaView,
  ActivityIndicator,
  useWindowDimensions,
  Linking,
  Platform,
} from 'react-native';
import { Camera, useCameraDevice } from 'react-native-vision-camera';
import Icon from 'react-native-vector-icons/Ionicons';
import Clipboard from '@react-native-clipboard/clipboard';
import { useVLMCamera } from '../hooks/useVLMCamera';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model/ModelSelectionSheet';
import { FileSystem } from '@runanywhere/core';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';

const VLMScreen: React.FC = () => {
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
  async (model: any) => {
    // 1. Find the projector path
    const mmprojPath = model.localPath
      ? await FileSystem.findMmprojForModel(model.localPath)
      : undefined;

    // 2. Load the model FIRST
    await vlm.loadModel(model.localPath, model.name, mmprojPath);
    await vlm.checkModelStatus();
    
    // 3. Close the modal AFTER the model is safely loaded and state is stable
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

  // Dismiss error
  const handleDismissError = useCallback(() => {
    // Reset error in next render to prevent flicker
    // Since hook doesn't expose setError, we'll just let user retry
  }, []);

  // Main action button color
  const mainButtonColor = vlm.isAutoStreaming
    ? Colors.primaryRed
    : vlm.isProcessing
    ? Colors.textTertiary
    : Colors.primaryOrange;

  return (
    <SafeAreaView style={styles.container}>
      {/* Model Required Overlay */}
      {!vlm.isModelLoaded && (
        <View style={styles.modelRequiredOverlay}>
          <Icon
            name="scan-outline"
            size={48}
            color={Colors.primaryOrange}
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
                  color={Colors.textSecondary}
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
                  <ActivityIndicator size="small" color={Colors.textWhite} />
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
                    color={Colors.textSecondary}
                  />
                </TouchableOpacity>
              )}
            </View>

            {/* Error Banner */}
            {vlm.error && (
              <View style={styles.errorBanner}>
                <Text style={styles.errorText}>{vlm.error}</Text>
              </View>
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
                color={vlm.isProcessing ? Colors.textTertiary : Colors.primaryBlue}
              />
            </TouchableOpacity>

            {/* Main Action Button */}
            <TouchableOpacity
              style={[styles.mainActionButton, { backgroundColor: mainButtonColor }]}
              onPress={handleMainAction}
              disabled={vlm.isProcessing && !vlm.isAutoStreaming}
              activeOpacity={0.8}
            >
              <Icon
                name={vlm.isAutoStreaming ? 'stop' : 'camera'}
                size={28}
                color={Colors.textWhite}
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
                    ? Colors.statusGreen
                    : vlm.isProcessing
                    ? Colors.textTertiary
                    : Colors.primaryBlue
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
                color={Colors.primaryBlue}
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

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  mainContent: {
    flex: 1,
  },

  // Model Required Overlay
  modelRequiredOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.overlayMedium,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: Padding.padding24,
    zIndex: 100,
  },
  modelRequiredIcon: {
    marginBottom: Spacing.large,
  },
  modelRequiredTitle: {
    ...Typography.title2,
    color: Colors.textWhite,
    marginBottom: Spacing.small,
    textAlign: 'center',
  },
  modelRequiredSubtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.xLarge,
  },
  selectModelButton: {
    backgroundColor: Colors.primaryOrange,
    paddingHorizontal: Padding.padding24,
    paddingVertical: Padding.padding12,
    borderRadius: BorderRadius.medium,
  },
  selectModelButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },

  // Camera Preview
  cameraPreview: {
    backgroundColor: Colors.backgroundPrimary,
    position: 'relative',
  },
  cameraPermissionView: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.backgroundSecondary,
  },
  cameraPermissionIcon: {
    marginBottom: Spacing.medium,
  },
  cameraPermissionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.medium,
  },
  openSettingsButton: {
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding8,
    borderRadius: BorderRadius.regular,
  },
  openSettingsButtonText: {
    ...Typography.body,
    color: Colors.textWhite,
  },

  // Processing Overlay
  processingOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    justifyContent: 'flex-end',
    alignItems: 'center',
    paddingBottom: Spacing.large,
  },
  processingContent: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderRadius: BorderRadius.pill,
  },
  processingText: {
    ...Typography.caption,
    color: Colors.textWhite,
    marginLeft: Spacing.smallMedium,
  },

  // Description Panel
  descriptionPanel: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding14,
  },
  descriptionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: Spacing.mediumLarge,
  },
  descriptionTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  descriptionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  liveBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: `${Colors.statusGreen}20`,
    paddingHorizontal: Spacing.smallMedium,
    paddingVertical: Spacing.xxSmall,
    borderRadius: BorderRadius.small,
    marginLeft: Spacing.small,
  },
  liveDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: Colors.statusGreen,
    marginRight: Spacing.xSmall,
  },
  liveText: {
    ...Typography.caption2,
    color: Colors.statusGreen,
    fontWeight: '700',
  },
  errorBanner: {
    backgroundColor: Colors.badgeRed,
    padding: Spacing.smallMedium,
    borderRadius: BorderRadius.regular,
    marginBottom: Spacing.medium,
  },
  errorText: {
    ...Typography.caption,
    color: Colors.primaryRed,
  },
  descriptionScroll: {
    flex: 1,
  },
  descriptionScrollContent: {
    flexGrow: 1,
  },
  descriptionText: {
    ...Typography.body,
    color: Colors.textPrimary,
    lineHeight: 22,
  },
  descriptionPlaceholder: {
    color: Colors.textSecondary,
  },

  // Control Bar
  controlBar: {
    flexDirection: 'row',
    justifyContent: 'space-evenly',
    alignItems: 'center',
    backgroundColor: Colors.backgroundPrimary,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: Colors.borderLight,
    paddingVertical: Spacing.large,
    paddingHorizontal: Padding.padding16,
  },
  controlButton: {
    padding: Spacing.medium,
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
