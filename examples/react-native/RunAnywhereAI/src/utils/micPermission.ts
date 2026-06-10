import { Platform, Alert, Linking, PermissionsAndroid } from 'react-native';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';

/**
 * Request microphone permission before any audio capture begins.
 * Mirrors the iOS AVAudioApplication.requestRecordPermission pre-flight
 * gate used in VoiceDictationManagementViewModel and SpeechToTextView.
 *
 * Returns true when RECORD_AUDIO / MICROPHONE is granted.
 * Shows an 'Open Settings' alert when permanently denied so the user
 * can unblock without restarting the app.
 */
export async function requestMicrophonePermission(): Promise<boolean> {
  try {
    if (Platform.OS === 'ios') {
      const status = await check(PERMISSIONS.IOS.MICROPHONE);

      if (status === RESULTS.GRANTED) {
        return true;
      }

      if (status === RESULTS.DENIED) {
        const result = await request(PERMISSIONS.IOS.MICROPHONE);
        return result === RESULTS.GRANTED;
      }

      if (status === RESULTS.BLOCKED) {
        Alert.alert(
          'Microphone Permission Required',
          'Please enable microphone access in Settings to use the voice assistant.',
          [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Open Settings', onPress: () => Linking.openSettings() },
          ]
        );
        return false;
      }

      return false;
    } else {
      // Android — RECORD_AUDIO is a dangerous permission (API 23+).
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        {
          title: 'Microphone Permission',
          message:
            'RunAnywhereAI needs access to your microphone for the voice assistant.',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        }
      );
      return granted === PermissionsAndroid.RESULTS.GRANTED;
    }
  } catch (error) {
    console.error('[micPermission] Permission request error:', error);
    return false;
  }
}
