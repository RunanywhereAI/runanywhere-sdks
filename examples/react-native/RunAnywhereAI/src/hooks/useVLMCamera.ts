/**
 * useVLMCamera hook
 *
 * React hook for VLM camera functionality with three modes:
 * 1. Single capture - Take photo and describe
 * 2. Gallery pick - Select photo and describe
 * 3. Auto-streaming - Continuous description of live camera feed
 */

import { useState, useRef, useCallback, useEffect, useMemo } from 'react';
import { Platform } from 'react-native';
import type { Camera } from 'react-native-vision-camera';
import { launchImageLibrary } from 'react-native-image-picker';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { VLMService } from '../services/VLMService';

/**
 * VLM Camera Hook State
 */
export interface VLMCameraState {
  isModelLoaded: boolean;
  loadedModelName: string | null;
  isProcessing: boolean;
  currentDescription: string;
  error: string | null;
  isCameraAuthorized: boolean;
  isAutoStreaming: boolean;
}

/**
 * VLM Camera Hook Actions
 */
export interface VLMCameraActions {
  requestCameraPermission: () => Promise<void>;
  checkModelStatus: () => Promise<void>;
  loadModel: (modelPath: string, modelName: string, mmprojPath?: string) => Promise<void>;
  captureAndDescribe: () => Promise<void>;
  selectPhotoAndDescribe: () => Promise<void>;
  toggleAutoStreaming: () => void;
  cancelGeneration: () => void;
}

export type VLMCameraHook = VLMCameraState & VLMCameraActions;

// Configuration
const AUTO_STREAM_INTERVAL_MS = 2500;
const AUTO_STREAM_MAX_TOKENS = 100;
const AUTO_STREAM_PROMPT = 'Describe what you see in one sentence.';
const SINGLE_CAPTURE_MAX_TOKENS = 200;
const SINGLE_CAPTURE_PROMPT = 'Describe what you see briefly.';
const GALLERY_MAX_TOKENS = 300;
const GALLERY_PROMPT = 'Describe this image in detail.';

export function useVLMCamera(cameraRef: React.RefObject<Camera>): VLMCameraHook {
  // 1. CRITICAL FIX: Memoize the service so it survives re-renders
  const vlmService = useMemo(() => new VLMService(), []);

  // State
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [loadedModelName, setLoadedModelName] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [currentDescription, setCurrentDescription] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isCameraAuthorized, setIsCameraAuthorized] = useState(false);
  const [isAutoStreaming, setIsAutoStreaming] = useState(false);

  const autoStreamIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // 2. Cleanup only when the component truly unmounts
  useEffect(() => {
    return () => {
      console.log('[useVLMCamera] Unmounting - Cleaning up');
      if (autoStreamIntervalRef.current) {
        clearInterval(autoStreamIntervalRef.current);
      }
      vlmService.cancel();
      vlmService.release();
    };
  }, [vlmService]);

  const requestCameraPermission = useCallback(async () => {
    const permission = Platform.OS === 'ios' ? PERMISSIONS.IOS.CAMERA : PERMISSIONS.ANDROID.CAMERA;
    const result = await check(permission);

    if (result === RESULTS.GRANTED) {
      setIsCameraAuthorized(true);
    } else if (result === RESULTS.DENIED) {
      const requestResult = await request(permission);
      setIsCameraAuthorized(requestResult === RESULTS.GRANTED);
    } else {
      setIsCameraAuthorized(false);
    }
  }, []);

  const checkModelStatus = useCallback(async () => {
    try {
      const loaded = await vlmService.isModelLoaded();
      setIsModelLoaded(loaded);
    } catch (err) {
      console.error('[useVLMCamera] Error checking status:', err);
      setIsModelLoaded(false);
    }
  }, [vlmService]);

  const loadModel = useCallback(
    async (modelPath: string, modelName: string, mmprojPath?: string) => {
      try {
        setIsProcessing(true);
        // Load into the persistent service instance
        await vlmService.loadModel(modelPath, mmprojPath, modelName);
        setIsModelLoaded(true);
        setLoadedModelName(modelName);
        setError(null);
      } catch (err: any) {
        const msg = err instanceof Error ? err.message : 'Failed to load model';
        setError(msg);
        setIsModelLoaded(false);
      } finally {
        setIsProcessing(false);
      }
    },
    [vlmService]
  );

  const captureAndDescribe = useCallback(async () => {
    if (!cameraRef.current || isProcessing) return;

    setIsProcessing(true);
    setError(null);
    setCurrentDescription('');

    try {
      // FIX: Removed 'qualityPrioritization' (invalid in V4)
      const photo = await cameraRef.current.takePhoto({
        enableShutterSound: false
      });

      // Use the service to describe with a callback for streaming
      await vlmService.describeImage(
        photo.path,
        SINGLE_CAPTURE_PROMPT,
        SINGLE_CAPTURE_MAX_TOKENS,
        (token) => {
          setCurrentDescription((prev) => prev + token);
        }
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Capture failed';
      setError(msg);
      console.error('[useVLMCamera] Capture error:', err);
    } finally {
      setIsProcessing(false);
    }
  }, [cameraRef, isProcessing, vlmService]);

  const selectPhotoAndDescribe = useCallback(async () => {
    try {
      const result = await launchImageLibrary({ mediaType: 'photo', quality: 1 });
      if (result.didCancel || !result.assets?.[0]?.uri) return;

      const photoUri = result.assets[0].uri;
      setIsProcessing(true);
      setError(null);
      setCurrentDescription('');

      // Strip file prefix if needed
      const cleanPath = photoUri.replace('file://', '');

      await vlmService.describeImage(
        cleanPath,
        GALLERY_PROMPT,
        GALLERY_MAX_TOKENS,
        (token) => {
          setCurrentDescription((prev) => prev + token);
        }
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Gallery failed';
      setError(msg);
    } finally {
      setIsProcessing(false);
    }
  }, [vlmService]);

  /**
   * Internal helper for auto-stream cycle
   */
  const performAutoStreamCapture = useCallback(async () => {
    if (!cameraRef.current) return;
    
    try {
      // FIX: Removed 'qualityPrioritization'
      const photo = await cameraRef.current.takePhoto({
        enableShutterSound: false
      });

      let accumulatedText = '';
      await vlmService.describeImage(
        photo.path,
        AUTO_STREAM_PROMPT,
        AUTO_STREAM_MAX_TOKENS,
        (token) => {
          accumulatedText += token;
          setCurrentDescription(accumulatedText);
        }
      );
    } catch (err) {
      console.warn('[useVLMCamera] Auto-stream skipped frame:', err);
    }
  }, [cameraRef, vlmService]);

  const toggleAutoStreaming = useCallback(() => {
    if (isAutoStreaming) {
      // STOP
      if (autoStreamIntervalRef.current) {
        clearInterval(autoStreamIntervalRef.current);
        autoStreamIntervalRef.current = null;
      }
      vlmService.cancel();
      setIsAutoStreaming(false);
    } else {
      // START
      setIsAutoStreaming(true);
      performAutoStreamCapture();
      autoStreamIntervalRef.current = setInterval(() => {
        performAutoStreamCapture();
      }, AUTO_STREAM_INTERVAL_MS);
    }
  }, [isAutoStreaming, performAutoStreamCapture, vlmService]);

  return {
    isModelLoaded,
    loadedModelName,
    isProcessing,
    currentDescription,
    error,
    isCameraAuthorized,
    isAutoStreaming,
    requestCameraPermission,
    checkModelStatus,
    loadModel,
    captureAndDescribe,
    selectPhotoAndDescribe,
    toggleAutoStreaming,
    cancelGeneration: () => vlmService.cancel(),
  };
}