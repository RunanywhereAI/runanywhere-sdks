/**
 * Speech-to-Text - record from the mic and transcribe on the NPU.
 *
 * Tap record, speak, then tap again to stop. The captured 16 kHz mono PCM is
 * wrapped in a WAV container and run through the loaded QHexRT STT model. Until
 * a model is loaded the control surfaces a graceful "load a model" prompt.
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, PermissionsAndroid, Platform } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

import { NpuStackParamList } from '../navTypes';
import { useAppColors, Space } from '../theme';
import { Screen, SectionCard, PrimaryButton } from '../widgets';
import NpuModelBar from '../NpuModelBar';
import { RunAnywhere, AudioCaptureManager } from '@runanywhere/core';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';

type Props = NativeStackScreenProps<NpuStackParamList, 'Stt'>;

const SAMPLE_RATE = 16000;
const BYTES_PER_MS = (SAMPLE_RATE * 2) / 1000;
const BAR_COUNT = 12;

/**
 * Concatenate captured PCM chunks into one buffer. The QHexRT STT engine
 * consumes raw 16 kHz mono int16 PCM directly (it cannot decode WAV/MP3), so we
 * hand it the bare samples and tag the format as PCM — unlike Sherpa-backed STT
 * which accepts a WAV container.
 */
function concatPcm16(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, c) => sum + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function formatDuration(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const SttScreen: React.FC<Props> = ({ navigation }) => {
  const c = useAppColors();
  const [recording, setRecording] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [modelLoaded, setModelLoaded] = useState(false);
  const [durationMs, setDurationMs] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);

  const captureRef = useRef<AudioCaptureManager | null>(null);
  const chunksRef = useRef<Uint8Array[]>([]);
  const bytesRef = useRef(0);

  const getCapture = (): AudioCaptureManager => {
    if (!captureRef.current) captureRef.current = new AudioCaptureManager();
    return captureRef.current;
  };

  useEffect(() => {
    return () => {
      try {
        captureRef.current?.stopRecording();
      } catch {}
      chunksRef.current = [];
      bytesRef.current = 0;
    };
  }, []);

  const requestMic = async (): Promise<boolean> => {
    if (Platform.OS !== 'android') return true;
    try {
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        {
          title: 'Microphone permission',
          message: 'RunAnywhere needs the microphone to transcribe speech on-device.',
          buttonPositive: 'OK',
        },
      );
      return granted === PermissionsAndroid.RESULTS.GRANTED;
    } catch {
      return false;
    }
  };

  const startRecording = async () => {
    setError(null);
    setTranscript('');
    const ok = await requestMic();
    if (!ok) {
      setError('Microphone permission denied.');
      return;
    }
    chunksRef.current = [];
    bytesRef.current = 0;
    setDurationMs(0);
    setAudioLevel(0);
    try {
      const cap = getCapture();
      await cap.startRecording((chunk: Uint8Array) => {
        chunksRef.current.push(chunk);
        bytesRef.current += chunk.length;
        setDurationMs(bytesRef.current / BYTES_PER_MS);
        setAudioLevel(cap.audioLevel);
      });
      setRecording(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const stopAndTranscribe = async () => {
    try {
      getCapture().stopRecording();
    } catch {}
    setRecording(false);
    setAudioLevel(0);
    setProcessing(true);
    try {
      const chunks = chunksRef.current;
      const total = bytesRef.current;
      chunksRef.current = [];
      bytesRef.current = 0;
      if (total < 1000) throw new Error('Recording too short — tap record and speak.');
      const result = await RunAnywhere.transcribe(concatPcm16(chunks), {
        language: STTLanguage.STT_LANGUAGE_EN,
        audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
        sampleRate: SAMPLE_RATE,
      });
      setTranscript(result?.text?.trim() || '(no speech detected)');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setProcessing(false);
      setDurationMs(0);
    }
  };

  const onToggle = useCallback(() => {
    if (recording) stopAndTranscribe();
    else startRecording();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recording]);

  const activeBars = Math.floor(audioLevel * BAR_COUNT);
  const buttonLabel = processing
    ? 'Transcribing…'
    : recording
      ? `Stop & transcribe · ${formatDuration(durationMs)}`
      : modelLoaded
        ? 'Record'
        : 'Load a model to record';

  return (
    <Screen title="Speech-to-Text" onBack={() => navigation.goBack()}>
      <NpuModelBar modality="stt" onLoadedChange={(id) => setModelLoaded(!!id)} />
      <SectionCard title="About">
        <Text style={{ color: c.onSurfaceVariant, fontSize: 14, lineHeight: 20 }}>
          Records from the microphone and transcribes your speech on-device with the loaded NPU STT
          model. Tap record, speak, then tap again to stop and transcribe.
        </Text>
      </SectionCard>
      <PrimaryButton
        label={buttonLabel}
        onPress={onToggle}
        busy={processing}
        disabled={!modelLoaded || processing}
      />
      {recording ? (
        <View style={styles.meterRow}>
          {Array.from({ length: BAR_COUNT }, (_, i) => (
            <View
              key={i}
              style={[
                styles.meterBar,
                {
                  height: 6 + i * 2,
                  backgroundColor: i < activeBars ? c.primary : c.surfaceVariant,
                },
              ]}
            />
          ))}
        </View>
      ) : null}
      {error ? <Text style={[styles.error, { color: c.error }]}>{error}</Text> : null}
      <View style={{ height: Space.lg }} />
      <SectionCard title="Transcript">
        <Text style={{ color: transcript ? c.onSurface : c.onSurfaceVariant, fontSize: 15, lineHeight: 22 }}>
          {transcript || (recording ? 'Listening…' : processing ? '…' : 'Transcript appears here.')}
        </Text>
      </SectionCard>
    </Screen>
  );
};

const styles = StyleSheet.create({
  error: { fontSize: 13, marginTop: Space.md },
  meterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    marginTop: Space.md,
  },
  meterBar: {
    width: 5,
    borderRadius: 3,
  },
});

export default SttScreen;
