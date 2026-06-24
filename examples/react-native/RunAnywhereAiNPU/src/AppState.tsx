/**
 * RunAnywhere NPU - shared app state (SDK init + NPU probe result).
 */
import React, { createContext, useContext } from 'react';
import { NpuInfo, UNKNOWN_NPU_INFO } from '@runanywhere/qhexrt';

export type InitState = 'loading' | 'ready' | 'error';

export interface AppStateValue {
  initState: InitState;
  error: string | null;
  npu: NpuInfo;
  qhexrtRegistered: boolean;
  sdkVersion: string;
}

const defaultValue: AppStateValue = {
  initState: 'loading',
  error: null,
  npu: UNKNOWN_NPU_INFO,
  qhexrtRegistered: false,
  sdkVersion: '',
};

export const AppStateContext = createContext<AppStateValue>(defaultValue);

export function useAppState(): AppStateValue {
  return useContext(AppStateContext);
}
