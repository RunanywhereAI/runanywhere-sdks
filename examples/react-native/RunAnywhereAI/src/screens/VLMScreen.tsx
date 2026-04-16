import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Camera, useCameraDevice } from 'react-native-vision-camera';
import Clipboard from '@react-native-clipboard/clipboard';
import { AppIcon } from '../components/common/AppIcon';
import { useVLMCamera } from '../hooks/useVLMCamera';
import {
  ModelSelectionContext,
  ModelSelectionSheet,
} from '../components/model/ModelSelectionSheet';
import { FileSystem, type ModelInfo as SDKModelInfo } from '@runanywhere/core';
import { useTheme } from '../theme';
import { Typography } from '../theme/typography';
import { BorderRadius, Padding, Spacing } from '../theme/spacing';
import type { ThemeColors } from '../theme/colors';

const VLMScreen: React.FC = () => {
  const { colors } = useTheme();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { height: screenHeight } = useWindowDimensions();
  const cameraRef = useRef<Camera>(null);
  const device = useCameraDevice('back');
  const vlm = useVLMCamera(cameraRef);
  const [showingModelSelection, setShowingModelSelection] = useState(false);

  useEffect(() => {
    vlm.requestCameraPermission();
  }, [vlm]);

  useEffect(() => {
    vlm.checkModelStatus();
  }, [vlm]);

  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      const mmprojPath = model.localPath
        ? await FileSystem.findMmprojForModel(model.localPath)
        : undefined;
      await vlm.loadModel(model.localPath ?? '', model.name, mmprojPath);
      await vlm.checkModelStatus();
      setShowingModelSelection(false);
    },
    [vlm]
  );

  const handleCopyDescription = useCallback(() => {
    if (vlm.currentDescription) Clipboard.setString(vlm.currentDescription);
  }, [vlm.currentDescription]);

  const handleOpenSettings = useCallback(() => {
    Linking.openSettings();
  }, []);

  const handleMainAction = useCallback(() => {
    if (vlm.isAutoStreaming) vlm.toggleAutoStreaming();
    else vlm.captureAndDescribe();
  }, [vlm]);

  const mainButtonColor = vlm.isAutoStreaming
    ? colors.error
    : vlm.isProcessing
    ? colors.textTertiary
    : colors.primary;

  return (
    <SafeAreaView
      edges={['top', 'bottom']}
      style={[styles.container, { backgroundColor: colors.background }]}
    >
      {!vlm.isModelLoaded ? (
        <View style={styles.modelRequiredOverlay}>
          <View style={styles.modelRequiredIconWrap}>
            <AppIcon name="scan-outline" size={48} color={colors.primary} />
          </View>
          <Text style={[Typography.title2, { color: colors.text, textAlign: 'center' }]}>
            Vision AI
          </Text>
          <Text
            style={[
              Typography.body,
              { color: colors.textSecondary, textAlign: 'center', marginTop: 8 },
            ]}
          >
            Load a vision-language model to describe images and scenes
          </Text>
          <TouchableOpacity
            style={[styles.selectModelButton, { backgroundColor: colors.primary }]}
            onPress={() => setShowingModelSelection(true)}
            activeOpacity={0.8}
          >
            <Text style={[Typography.headline, { color: colors.onPrimary }]}>
              Select Model
            </Text>
          </TouchableOpacity>
        </View>
      ) : (
        <View style={styles.mainContent}>
          <View
            style={[
              styles.cameraPreview,
              { height: screenHeight * 0.45, backgroundColor: colors.surfaceAlt },
            ]}
          >
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
                <AppIcon name="camera" size={48} color={colors.textSecondary} />
                <Text
                  style={[
                    Typography.headline,
                    { color: colors.text, marginTop: Spacing.medium },
                  ]}
                >
                  Camera Access Required
                </Text>
                <TouchableOpacity
                  style={[styles.openSettingsButton, { backgroundColor: colors.primary }]}
                  onPress={handleOpenSettings}
                  activeOpacity={0.7}
                >
                  <Text style={[Typography.body, { color: colors.onPrimary }]}>
                    Open Settings
                  </Text>
                </TouchableOpacity>
              </View>
            ) : (
              <View style={styles.cameraPermissionView}>
                <Text style={[Typography.headline, { color: colors.text }]}>
                  No camera available
                </Text>
              </View>
            )}
            {vlm.isProcessing ? (
              <View style={styles.processingOverlay}>
                <View style={styles.processingContent}>
                  <ActivityIndicator size="small" color="#FFFFFF" />
                  <Text
                    style={[Typography.caption, styles.processingText]}
                  >
                    Analyzing…
                  </Text>
                </View>
              </View>
            ) : null}
          </View>

          <View style={[styles.descriptionPanel, { backgroundColor: colors.background }]}>
            <View style={styles.descriptionHeader}>
              <View style={styles.descriptionTitleRow}>
                <Text style={[Typography.headline, { color: colors.text }]}>
                  Description
                </Text>
                {vlm.isAutoStreaming ? (
                  <View
                    style={[
                      styles.liveBadge,
                      { backgroundColor: `${colors.error}22` },
                    ]}
                  >
                    <View
                      style={[styles.liveDot, { backgroundColor: colors.error }]}
                    />
                    <Text
                      style={[
                        Typography.caption2,
                        styles.liveText,
                        { color: colors.error },
                      ]}
                    >
                      LIVE
                    </Text>
                  </View>
                ) : null}
              </View>
              {vlm.currentDescription ? (
                <TouchableOpacity
                  onPress={handleCopyDescription}
                  activeOpacity={0.7}
                >
                  <AppIcon name="copy-outline" size={18} color={colors.textSecondary} />
                </TouchableOpacity>
              ) : null}
            </View>

            {vlm.error ? (
              <View
                style={[styles.errorBanner, { backgroundColor: `${colors.error}18` }]}
              >
                <Text style={[Typography.caption, { color: colors.error }]}>
                  {vlm.error}
                </Text>
              </View>
            ) : null}

            <ScrollView
              style={styles.descriptionScroll}
              contentContainerStyle={styles.descriptionScrollContent}
              showsVerticalScrollIndicator={true}
            >
              <Text
                style={[
                  Typography.body,
                  {
                    color: vlm.currentDescription
                      ? colors.text
                      : colors.textSecondary,
                    lineHeight: 22,
                  },
                ]}
              >
                {vlm.currentDescription ||
                  'Tap capture to describe what your camera sees'}
              </Text>
            </ScrollView>
          </View>

          <View
            style={[
              styles.controlBar,
              { borderTopColor: colors.border, backgroundColor: colors.background },
            ]}
          >
            <TouchableOpacity
              style={styles.controlButton}
              onPress={vlm.selectPhotoAndDescribe}
              disabled={vlm.isProcessing}
              activeOpacity={0.7}
            >
              <AppIcon
                name="images-outline"
                size={24}
                color={vlm.isProcessing ? colors.textTertiary : colors.text}
              />
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.mainActionButton,
                { backgroundColor: mainButtonColor },
              ]}
              onPress={handleMainAction}
              disabled={vlm.isProcessing && !vlm.isAutoStreaming}
              activeOpacity={0.8}
            >
              <AppIcon
                name={vlm.isAutoStreaming ? 'stop' : 'camera'}
                size={28}
                color={colors.onPrimary}
              />
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.controlButton}
              onPress={vlm.toggleAutoStreaming}
              disabled={vlm.isProcessing && !vlm.isAutoStreaming}
              activeOpacity={0.7}
            >
              <AppIcon
                name="radio-outline"
                size={24}
                color={
                  vlm.isAutoStreaming
                    ? colors.success
                    : vlm.isProcessing
                    ? colors.textTertiary
                    : colors.text
                }
              />
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.controlButton}
              onPress={() => setShowingModelSelection(true)}
              activeOpacity={0.7}
            >
              <AppIcon
                name="hardware-chip-outline"
                size={24}
                color={colors.text}
              />
            </TouchableOpacity>
          </View>
        </View>
      )}

      <ModelSelectionSheet
        visible={showingModelSelection}
        context={ModelSelectionContext.VLM}
        onModelSelected={handleModelSelected}
        onClose={() => setShowingModelSelection(false)}
      />
    </SafeAreaView>
  );
};

const createStyles = (colors: ThemeColors) =>
  StyleSheet.create({
    container: { flex: 1 },
    mainContent: { flex: 1 },
    modelRequiredOverlay: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      paddingHorizontal: Padding.padding24,
    },
    modelRequiredIconWrap: {
      width: 96,
      height: 96,
      borderRadius: 48,
      backgroundColor: colors.primarySoft,
      justifyContent: 'center',
      alignItems: 'center',
      marginBottom: Spacing.xLarge,
    },
    selectModelButton: {
      paddingHorizontal: Padding.padding24,
      paddingVertical: Padding.padding12,
      borderRadius: BorderRadius.large,
      marginTop: Spacing.xLarge,
    },
    cameraPreview: {
      position: 'relative',
    },
    cameraPermissionView: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      paddingHorizontal: Padding.padding16,
    },
    openSettingsButton: {
      paddingHorizontal: Padding.padding16,
      paddingVertical: Padding.padding8,
      borderRadius: BorderRadius.regular,
      marginTop: Spacing.medium,
    },
    processingOverlay: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      alignItems: 'center',
      paddingBottom: Spacing.large,
    },
    processingContent: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: 'rgba(0, 0, 0, 0.66)',
      paddingHorizontal: Padding.padding16,
      paddingVertical: Padding.padding12,
      borderRadius: BorderRadius.pill,
    },
    processingText: {
      color: '#FFFFFF',
      marginLeft: Spacing.smallMedium,
    },
    descriptionPanel: {
      flex: 1,
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
    liveBadge: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: Spacing.smallMedium,
      paddingVertical: Spacing.xxSmall,
      borderRadius: BorderRadius.small,
      marginLeft: Spacing.small,
    },
    liveDot: {
      width: 8,
      height: 8,
      borderRadius: 4,
      marginRight: Spacing.xSmall,
    },
    liveText: {
      fontWeight: '700',
    },
    errorBanner: {
      padding: Spacing.smallMedium,
      borderRadius: BorderRadius.regular,
      marginBottom: Spacing.medium,
    },
    descriptionScroll: { flex: 1 },
    descriptionScrollContent: { flexGrow: 1 },
    controlBar: {
      flexDirection: 'row',
      justifyContent: 'space-evenly',
      alignItems: 'center',
      borderTopWidth: StyleSheet.hairlineWidth,
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
