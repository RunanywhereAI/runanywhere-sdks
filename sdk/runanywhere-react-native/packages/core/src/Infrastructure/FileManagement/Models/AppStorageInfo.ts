/**
 * AppStorageInfo.ts
 * RunAnywhere SDK
 *
 * App storage breakdown information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Models/Domain/AppStorageInfo.swift
 */

/**
 * App storage breakdown
 */
export interface AppStorageInfo {
  /** Size of documents directory in bytes */
  readonly documentsSize: number;
  /** Size of cache directory in bytes */
  readonly cacheSize: number;
  /** Size of application support directory in bytes */
  readonly appSupportSize: number;
  /** Total size of all app storage in bytes */
  readonly totalSize: number;
}

/**
 * Creates an AppStorageInfo instance
 *
 * @param params - App storage parameters
 * @returns AppStorageInfo instance
 */
export function createAppStorageInfo(params: {
  documentsSize: number;
  cacheSize: number;
  appSupportSize: number;
  totalSize: number;
}): AppStorageInfo {
  return {
    documentsSize: params.documentsSize,
    cacheSize: params.cacheSize,
    appSupportSize: params.appSupportSize,
    totalSize: params.totalSize,
  };
}
