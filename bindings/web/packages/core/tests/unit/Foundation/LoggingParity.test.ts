import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  SDKLogger,
  LogLevel,
  LOG_LEVEL_TO_RAC,
  toRacLogLevel,
  racLogLevelToProto,
} from '../../../src/Foundation/SDKLogger.js';
import { Logging } from '../../../src/Public/Extensions/RunAnywhere+Logging.js';
import {
  registerWasmModule,
  unregisterWasmModule,
  getCommonsMinLogLevel,
  setCommonsMinLogLevel,
  type EmscriptenRunanywhereModule,
} from '../../../src/runtime/EmscriptenModule.js';

describe('LoggingParity (Web)', () => {
  let previousLevel: LogLevel;
  let previousCommonsLevel: number;
  let mockModule: EmscriptenRunanywhereModule;
  let currentModuleLevel = 2;

  beforeEach(() => {
    previousLevel = SDKLogger.level;
    previousCommonsLevel = getCommonsMinLogLevel();
    currentModuleLevel = 2;

    mockModule = {
      _rac_logger_set_min_level: vi.fn((lvl: number) => {
        currentModuleLevel = lvl;
      }),
      _rac_logger_get_min_level: vi.fn(() => currentModuleLevel),
    } as unknown as EmscriptenRunanywhereModule;

    registerWasmModule(['tool-calling'], mockModule);
  });

  afterEach(() => {
    unregisterWasmModule(mockModule);
    SDKLogger.setMinLogLevel(previousLevel);
    setCommonsMinLogLevel(previousCommonsLevel);
  });

  it('LogLevel to rac_log_level_t mapping', () => {
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_TRACE)).toBe(0);
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_DEBUG)).toBe(1);
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_INFO)).toBe(2);
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_WARNING)).toBe(3);
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_ERROR)).toBe(4);
    expect(toRacLogLevel(LogLevel.LOG_LEVEL_FATAL)).toBe(5);
    expect(toRacLogLevel(LogLevel.UNRECOGNIZED)).toBe(2);
  });

  it('rac_log_level_t to LogLevel mapping', () => {
    expect(racLogLevelToProto(0)).toBe(LogLevel.LOG_LEVEL_TRACE);
    expect(racLogLevelToProto(1)).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(racLogLevelToProto(2)).toBe(LogLevel.LOG_LEVEL_INFO);
    expect(racLogLevelToProto(3)).toBe(LogLevel.LOG_LEVEL_WARNING);
    expect(racLogLevelToProto(4)).toBe(LogLevel.LOG_LEVEL_ERROR);
    expect(racLogLevelToProto(5)).toBe(LogLevel.LOG_LEVEL_FATAL);
    expect(racLogLevelToProto(999)).toBe(LogLevel.LOG_LEVEL_INFO);
  });

  it('SDKLogger.setMinLogLevel updates commons logger', () => {
    SDKLogger.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(1);
    expect(getCommonsMinLogLevel()).toBe(1);

    SDKLogger.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_ERROR);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(4);
    expect(getCommonsMinLogLevel()).toBe(4);
  });

  it('SDKLogger.configure updates commons logger', () => {
    SDKLogger.configure({
      enableLocalLogging: true,
      minLogLevel: LogLevel.LOG_LEVEL_WARNING,
      includeDeviceMetadata: false,
      enableRemoteLogging: false,
      includeSourceLocation: false,
    });
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_WARNING);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(3);
    expect(getCommonsMinLogLevel()).toBe(3);
  });

  it('Public Logging entrypoints update commons logger', () => {
    Logging.setLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(1);
    expect(getCommonsMinLogLevel()).toBe(1);

    Logging.setLogLevel(LogLevel.LOG_LEVEL_FATAL);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_FATAL);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(5);
    expect(getCommonsMinLogLevel()).toBe(5);

    Logging.setDebugMode(true);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(1);
    expect(getCommonsMinLogLevel()).toBe(1);

    Logging.setDebugMode(false);
    expect(SDKLogger.level).toBe(LogLevel.LOG_LEVEL_INFO);
    expect(mockModule._rac_logger_set_min_level).toHaveBeenCalledWith(2);
    expect(getCommonsMinLogLevel()).toBe(2);
  });
});
