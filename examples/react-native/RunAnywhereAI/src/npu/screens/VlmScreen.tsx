/**
 * Vision (VLM) — ask about a still image, or run a live camera caption loop,
 * answered on the NPU.
 *
 * QHexRT consumes the image by file path (it decodes the container itself; raw
 * pixel / base64 forms are not accepted) and its VLM path does not emit
 * incremental stream tokens, so both modes use the non-streaming
 * `RunAnywhere.processImage` with a FILE_PATH VLMImage. The live loop mirrors
 * the iOS / Android NPU live view: sample a frame every ~2.5s and caption it.
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  Image,
  StyleSheet,
  TouchableOpacity,
  Platform,
  ActivityIndicator,
} from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { launchImageLibrary } from 'react-native-image-picker';
import { Camera, useCameraDevice } from 'react-native-vision-camera';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space, Radius } from '../theme';
import { Screen, SectionCard, Field, PrimaryButton, StatusPill } from '../widgets';
import { RunAnywhere, VLMImages } from '@runanywhere/core';
import { VLMGenerationOptions } from '@runanywhere/proto-ts/vlm_options';

type Props = NativeStackScreenProps<NpuStackParamList, 'Vlm'>;

const LIVE_INTERVAL_MS = 2500;
const LIVE_MAX_TOKENS = 100;
const LIVE_PROMPT = 'Describe what you see in one sentence.';

const stripFilePrefix = (uri: string): string => uri.replace('file://', '');

const VlmScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [mode, setMode] = useState<'static' | 'live'>('static');

  // Static mode
  const [imageUri, setImageUri] = useState<string | null>(null);
  const [prompt, setPrompt] = useState('Describe this image.');
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Live mode
  const cameraRef = useRef<Camera>(null);
  const device = useCameraDevice('back');
  const [cameraAuthorized, setCameraAuthorized] = useState(false);
  const [liveCaption, setLiveCaption] = useState('Point the camera at a scene.');
  const liveBusyRef = useRef(false);
  const liveTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const requestCamera = useCallback(async () => {
    const perm = Platform.OS === 'ios' ? PERMISSIONS.IOS.CAMERA : PERMISSIONS.ANDROID.CAMERA;
    const status = await check(perm);
    if (status === RESULTS.GRANTED) {
      setCameraAuthorized(true);
    } else {
      const res = await request(perm);
      setCameraAuthorized(res === RESULTS.GRANTED);
    }
  }, []);

  // Non-streaming describe for a file path (QHexRT VLM yields no stream tokens).
  const describePath = useCallback(
    async (path: string, p: string, maxTokens: number): Promise<string> => {
      const result = await RunAnywhere.processImage(
        VLMImages.fromFilePath(path),
        VLMGenerationOptions.fromPartial({ prompt: p, maxTokens })
      );
      return result.text || '';
    },
    []
  );

  const pickImage = async () => {
    const res = await launchImageLibrary({ mediaType: 'photo', selectionLimit: 1 });
    const uri = res.assets?.[0]?.uri;
    if (uri) {
      setImageUri(uri);
      setOutput('');
      setError(null);
    }
  };

  const describe = async () => {
    if (!imageUri) return;
    setRunning(true);
    setError(null);
    setOutput('');
    try {
      const text = await describePath(stripFilePrefix(imageUri), prompt, 256);
      setOutput(text || '(no output)');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  };

  // Live capture loop: sample a frame, caption it, repeat. Skips frames while a
  // previous caption is still running so the NPU is never double-driven.
  const captureLiveFrame = useCallback(async () => {
    if (liveBusyRef.current || !cameraRef.current) return;
    liveBusyRef.current = true;
    try {
      const photo = await cameraRef.current.takePhoto({ enableShutterSound: false });
      const text = await describePath(stripFilePrefix(photo.path), LIVE_PROMPT, LIVE_MAX_TOKENS);
      if (text) setLiveCaption(text);
    } catch {
      /* skip this frame — camera not ready or no model loaded yet */
    } finally {
      liveBusyRef.current = false;
    }
  }, [describePath]);

  // Drive the live loop only while in live mode with camera access.
  useEffect(() => {
    if (mode !== 'live') return;
    requestCamera();
    return undefined;
  }, [mode, requestCamera]);

  useEffect(() => {
    if (mode === 'live' && cameraAuthorized && device) {
      liveTimerRef.current = setInterval(captureLiveFrame, LIVE_INTERVAL_MS);
    }
    return () => {
      if (liveTimerRef.current) {
        clearInterval(liveTimerRef.current);
        liveTimerRef.current = null;
      }
    };
  }, [mode, cameraAuthorized, device, captureLiveFrame]);

  return (
    <Screen title="Vision" onBack={() => navigation.goBack()}>
      <View style={styles.toggleRow}>
        {(['static', 'live'] as const).map((m) => {
          const active = mode === m;
          return (
            <TouchableOpacity
              key={m}
              onPress={() => setMode(m)}
              activeOpacity={0.85}
              style={[
                styles.toggle,
                { borderColor: active ? c.primary : c.outline, backgroundColor: active ? c.primary : c.surface },
              ]}
            >
              <Text style={[styles.toggleText, { color: active ? c.onPrimary : c.onSurfaceVariant }]}>
                {m === 'static' ? 'Image' : 'Live camera'}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>

      <View style={{ height: Space.lg }} />

      {mode === 'static' ? (
        <>
          <TouchableOpacity
            activeOpacity={0.85}
            onPress={pickImage}
            style={[styles.picker, { borderColor: c.outline, backgroundColor: c.surface }]}
          >
            {imageUri ? (
              <Image source={{ uri: imageUri }} style={styles.image} resizeMode="cover" />
            ) : (
              <Text style={{ color: c.onSurfaceVariant }}>Tap to choose an image</Text>
            )}
          </TouchableOpacity>

          <View style={{ height: Space.lg }} />
          <Field value={prompt} onChangeText={setPrompt} editable={!running} placeholder="Ask about the image" />
          <View style={{ height: Space.lg }} />
          <PrimaryButton
            label={running ? 'Analyzing…' : 'Describe'}
            onPress={describe}
            busy={running}
            disabled={!imageUri}
          />
          {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
          <View style={{ height: Space.lg }} />
          <SectionCard title="Answer">
            <Text style={{ color: output ? c.onSurface : c.onSurfaceVariant, fontSize: 15, lineHeight: 22 }}>
              {output || (running ? '…' : 'Pick an image and load an NPU VLM model from the Models screen.')}
            </Text>
          </SectionCard>
        </>
      ) : (
        <>
          <View style={[styles.cameraBox, { borderColor: c.outline, backgroundColor: c.surface }]}>
            {device && cameraAuthorized ? (
              <Camera
                ref={cameraRef}
                device={device}
                isActive={mode === 'live'}
                photo={true}
                style={StyleSheet.absoluteFill}
              />
            ) : (
              <View style={styles.cameraPlaceholder}>
                <Text style={{ color: c.onSurfaceVariant, textAlign: 'center' }}>
                  {cameraAuthorized ? 'No camera available' : 'Camera permission required'}
                </Text>
                {!cameraAuthorized && (
                  <>
                    <View style={{ height: Space.md }} />
                    <PrimaryButton label="Grant camera" onPress={requestCamera} />
                  </>
                )}
              </View>
            )}
            <View style={styles.liveBadge}>
              <StatusPill label="LIVE" tone="ok" />
            </View>
          </View>
          <View style={{ height: Space.lg }} />
          <SectionCard title="Live description">
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              {liveBusyRef.current ? <ActivityIndicator size="small" color={c.primary} /> : null}
              <Text style={{ color: c.onSurface, fontSize: 15, lineHeight: 22, flex: 1, marginLeft: Space.sm }}>
                {liveCaption}
              </Text>
            </View>
          </SectionCard>
          <Text style={{ color: c.onSurfaceVariant, fontSize: 12, lineHeight: 18 }}>
            Captures a frame every {(LIVE_INTERVAL_MS / 1000).toFixed(1)}s. Load an NPU VLM model from the
            Models screen first.
          </Text>
        </>
      )}
    </Screen>
  );
};

const styles = StyleSheet.create({
  toggleRow: { flexDirection: 'row', gap: Space.sm },
  toggle: {
    flex: 1,
    height: 44,
    borderWidth: 1,
    borderRadius: Radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toggleText: { fontSize: 14, fontWeight: '700' },
  picker: {
    height: 220,
    borderRadius: Radius.lg,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  image: { width: '100%', height: '100%' },
  cameraBox: {
    height: 320,
    borderRadius: Radius.lg,
    borderWidth: 1,
    overflow: 'hidden',
    justifyContent: 'center',
  },
  cameraPlaceholder: { padding: Space.lg, alignItems: 'center', justifyContent: 'center' },
  liveBadge: { position: 'absolute', top: Space.sm, left: Space.sm },
  error: { fontSize: 13, marginTop: Space.md },
});

export default VlmScreen;
