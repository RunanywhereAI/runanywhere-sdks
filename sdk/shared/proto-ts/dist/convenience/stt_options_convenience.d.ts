import { STTConfiguration, STTLanguage, STTOptions } from '../stt_options';
export declare const sTTLanguageWireString: (e: STTLanguage) => string;
export declare const sTTLanguageFromWireString: (s: string) => STTLanguage | undefined;
export declare const sTTConfigurationDefaults: () => STTConfiguration;
export declare const validateSTTConfiguration: (m: STTConfiguration) => void;
export declare const sTTOptionsDefaults: () => STTOptions;
