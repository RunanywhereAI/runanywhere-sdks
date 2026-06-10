import { LogLevel, LoggingConfiguration } from '../logging';
export declare const logLevelWireString: (e: LogLevel) => string;
export declare const logLevelFromWireString: (s: string) => LogLevel | undefined;
export declare const logLevelDisplayName: (e: LogLevel) => string;
export declare const loggingConfigurationDefaults: () => LoggingConfiguration;
