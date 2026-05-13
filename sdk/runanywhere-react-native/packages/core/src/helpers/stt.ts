/**
 * helpers/stt
 *
 * Swift-parity conveniences for generated STT proto types.
 */

import {
  STTLanguage,
  type STTOutput,
} from '@runanywhere/proto-ts/stt_options';

export {
  STTConfiguration,
  STTOptions,
  STTLanguage,
  type STTOutput,
  type STTPartialResult,
  type STTLanguageDetectionResult,
  type STTServiceState,
  type STTStreamEvent,
  type STTTranscriptionRequest,
  type TranscriptionAlternative,
  type TranscriptionMetadata,
  type WordTimestamp,
} from '@runanywhere/proto-ts/stt_options';

export function sttLanguageFromBcp47(raw: string): STTLanguage {
  const base = (raw.split('-')[0] ?? raw).toLowerCase();
  switch (base) {
    case 'auto':
      return STTLanguage.STT_LANGUAGE_AUTO;
    case 'en':
      return STTLanguage.STT_LANGUAGE_EN;
    case 'es':
      return STTLanguage.STT_LANGUAGE_ES;
    case 'fr':
      return STTLanguage.STT_LANGUAGE_FR;
    case 'de':
      return STTLanguage.STT_LANGUAGE_DE;
    case 'zh':
      return STTLanguage.STT_LANGUAGE_ZH;
    case 'ja':
      return STTLanguage.STT_LANGUAGE_JA;
    case 'ko':
      return STTLanguage.STT_LANGUAGE_KO;
    case 'it':
      return STTLanguage.STT_LANGUAGE_IT;
    case 'pt':
      return STTLanguage.STT_LANGUAGE_PT;
    case 'ar':
      return STTLanguage.STT_LANGUAGE_AR;
    case 'ru':
      return STTLanguage.STT_LANGUAGE_RU;
    case 'hi':
      return STTLanguage.STT_LANGUAGE_HI;
    default:
      return STTLanguage.STT_LANGUAGE_UNSPECIFIED;
  }
}

export function sttLanguageBcp47Code(language: STTLanguage): string {
  switch (language) {
    case STTLanguage.STT_LANGUAGE_AUTO:
      return 'auto';
    case STTLanguage.STT_LANGUAGE_EN:
      return 'en';
    case STTLanguage.STT_LANGUAGE_ES:
      return 'es';
    case STTLanguage.STT_LANGUAGE_FR:
      return 'fr';
    case STTLanguage.STT_LANGUAGE_DE:
      return 'de';
    case STTLanguage.STT_LANGUAGE_ZH:
      return 'zh';
    case STTLanguage.STT_LANGUAGE_JA:
      return 'ja';
    case STTLanguage.STT_LANGUAGE_KO:
      return 'ko';
    case STTLanguage.STT_LANGUAGE_IT:
      return 'it';
    case STTLanguage.STT_LANGUAGE_PT:
      return 'pt';
    case STTLanguage.STT_LANGUAGE_AR:
      return 'ar';
    case STTLanguage.STT_LANGUAGE_RU:
      return 'ru';
    case STTLanguage.STT_LANGUAGE_HI:
      return 'hi';
    default:
      return '';
  }
}

export function sttOutputDetectedLanguageCode(output: STTOutput): STTLanguage {
  return output.language;
}
