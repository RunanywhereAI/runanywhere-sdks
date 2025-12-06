/**
 * TTSExample.tsx
 *
 * Example demonstrating how to use the System TTS service in React Native
 *
 * Features:
 * - Basic text-to-speech synthesis
 * - Voice selection by language
 * - Rate, pitch, and volume control
 * - Available voices listing
 * - Error handling
 */

import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  Button,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { TTSComponent } from '../src/components/TTS/TTSComponent';
import { TTSConfigurationImpl } from '../src/components/TTS/TTSConfiguration';
import { SystemTTSService, getVoicesByLanguage } from '../src/services/SystemTTSService';

export default function TTSExample() {
  const [ttsComponent, setTtsComponent] = useState<TTSComponent | null>(null);
  const [text, setText] = useState('Hello! This is a test of the text-to-speech system.');
  const [isInitialized, setIsInitialized] = useState(false);
  const [isSynthesizing, setIsSynthesizing] = useState(false);
  const [availableVoices, setAvailableVoices] = useState<string[]>([]);
  const [selectedVoice, setSelectedVoice] = useState<string | null>(null);
  const [rate, setRate] = useState(1.0);
  const [pitch, setPitch] = useState(1.0);
  const [volume, setVolume] = useState(1.0);

  // Initialize TTS component
  useEffect(() => {
    initializeTTS();
    return () => {
      // Cleanup on unmount
      if (ttsComponent) {
        ttsComponent.cleanup();
      }
    };
  }, []);

  const initializeTTS = async () => {
    try {
      // Create TTS configuration
      const config = new TTSConfigurationImpl({
        voice: 'system', // Use system default voice
        language: 'en-US',
        speakingRate: 1.0,
        pitch: 1.0,
        volume: 1.0,
        audioFormat: 'pcm',
        useNeuralVoice: true,
        enableSSML: false,
      });

      // Create and initialize TTS component
      const component = new TTSComponent(config);
      await component.initialize();

      setTtsComponent(component);
      setIsInitialized(true);

      // Load available voices
      const voices = await component.getAvailableVoices();
      setAvailableVoices(voices);
      if (voices.length > 0 && voices[0]) {
        setSelectedVoice(voices[0]);
      }
    } catch (error) {
      Alert.alert('Initialization Error', `Failed to initialize TTS: ${error}`);
      console.error('TTS initialization failed:', error);
    }
  };

  const handleSynthesize = async () => {
    if (!ttsComponent || !text.trim()) {
      Alert.alert('Error', 'Please enter text to synthesize');
      return;
    }

    setIsSynthesizing(true);

    try {
      // Synthesize speech with current settings
      const output = await ttsComponent.synthesize(text, {
        voice: selectedVoice,
        language: 'en-US',
        rate,
        pitch,
        volume,
        audioFormat: 'pcm',
        sampleRate: 16000,
        useSSML: false,
      });

      Alert.alert('Success', `Synthesized ${output.audioData.length} bytes of audio`);
      console.log('Synthesis metadata:', output.metadata);
    } catch (error) {
      Alert.alert('Synthesis Error', `Failed to synthesize: ${error}`);
      console.error('TTS synthesis failed:', error);
    } finally {
      setIsSynthesizing(false);
    }
  };

  const handleStop = async () => {
    if (ttsComponent) {
      await ttsComponent.stopSynthesis();
      setIsSynthesizing(false);
    }
  };

  const handleGetVoicesByLanguage = async (language: string) => {
    try {
      const voiceMap = await getVoicesByLanguage();
      const langVoices = voiceMap.get(language) || [];
      Alert.alert(
        `Voices for ${language}`,
        langVoices.length > 0
          ? langVoices.map(v => v.name).join('\n')
          : 'No voices found for this language'
      );
    } catch (error) {
      Alert.alert('Error', `Failed to get voices: ${error}`);
    }
  };

  if (!isInitialized) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0000ff" />
        <Text style={styles.loadingText}>Initializing TTS...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>Text-to-Speech Example</Text>

      {/* Text Input */}
      <View style={styles.section}>
        <Text style={styles.label}>Text to Synthesize:</Text>
        <TextInput
          style={styles.textInput}
          multiline
          numberOfLines={4}
          value={text}
          onChangeText={setText}
          placeholder="Enter text to synthesize..."
        />
      </View>

      {/* Voice Selection */}
      <View style={styles.section}>
        <Text style={styles.label}>Available Voices ({availableVoices.length}):</Text>
        <ScrollView style={styles.voiceList}>
          {availableVoices.map((voice, index) => (
            <Button
              key={index}
              title={voice}
              onPress={() => setSelectedVoice(voice)}
              color={selectedVoice === voice ? '#007AFF' : '#8E8E93'}
            />
          ))}
        </ScrollView>
      </View>

      {/* Rate Control */}
      <View style={styles.section}>
        <Text style={styles.label}>Rate: {rate.toFixed(2)}</Text>
        <View style={styles.buttonRow}>
          <Button title="-" onPress={() => setRate(Math.max(0.5, rate - 0.1))} />
          <Button title="Reset" onPress={() => setRate(1.0)} />
          <Button title="+" onPress={() => setRate(Math.min(2.0, rate + 0.1))} />
        </View>
      </View>

      {/* Pitch Control */}
      <View style={styles.section}>
        <Text style={styles.label}>Pitch: {pitch.toFixed(2)}</Text>
        <View style={styles.buttonRow}>
          <Button title="-" onPress={() => setPitch(Math.max(0.5, pitch - 0.1))} />
          <Button title="Reset" onPress={() => setPitch(1.0)} />
          <Button title="+" onPress={() => setPitch(Math.min(2.0, pitch + 0.1))} />
        </View>
      </View>

      {/* Volume Control */}
      <View style={styles.section}>
        <Text style={styles.label}>Volume: {volume.toFixed(2)}</Text>
        <View style={styles.buttonRow}>
          <Button title="-" onPress={() => setVolume(Math.max(0.0, volume - 0.1))} />
          <Button title="Reset" onPress={() => setVolume(1.0)} />
          <Button title="+" onPress={() => setVolume(Math.min(1.0, volume + 0.1))} />
        </View>
      </View>

      {/* Synthesis Controls */}
      <View style={styles.section}>
        <Button
          title={isSynthesizing ? 'Synthesizing...' : 'Synthesize Speech'}
          onPress={handleSynthesize}
          disabled={isSynthesizing}
        />
        {isSynthesizing && (
          <Button title="Stop" onPress={handleStop} color="#FF3B30" />
        )}
      </View>

      {/* Voice Filtering */}
      <View style={styles.section}>
        <Text style={styles.label}>Get Voices by Language:</Text>
        <View style={styles.buttonRow}>
          <Button title="English" onPress={() => handleGetVoicesByLanguage('en-US')} />
          <Button title="Spanish" onPress={() => handleGetVoicesByLanguage('es-ES')} />
          <Button title="French" onPress={() => handleGetVoicesByLanguage('fr-FR')} />
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    backgroundColor: '#F5F5F5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    textAlign: 'center',
  },
  section: {
    marginBottom: 20,
    padding: 15,
    backgroundColor: '#FFFFFF',
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 10,
  },
  textInput: {
    borderWidth: 1,
    borderColor: '#CCCCCC',
    borderRadius: 4,
    padding: 10,
    fontSize: 16,
    minHeight: 100,
    textAlignVertical: 'top',
  },
  voiceList: {
    maxHeight: 150,
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginTop: 10,
  },
});
