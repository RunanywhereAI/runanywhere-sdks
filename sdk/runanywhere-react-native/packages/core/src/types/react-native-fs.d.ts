/**
 * Type declarations for react-native-fs
 *
 * This module is an optional peer dependency.
 */
declare module 'react-native-fs' {
  export interface StatResult {
    name: string;
    path: string;
    size: number;
    mode: number;
    ctime: Date;
    mtime: Date;
    originalFilepath: string;
    isFile(): boolean;
    isDirectory(): boolean;
  }

  export interface ReadDirItem {
    name: string;
    path: string;
    size: number;
    isFile(): boolean;
    isDirectory(): boolean;
    ctime?: Date;
    mtime?: Date;
  }

  export interface DownloadFileOptions {
    fromUrl: string;
    toFile: string;
    headers?: Record<string, string>;
    background?: boolean;
    backgroundTimeout?: number;
    progressDivider?: number;
    progressInterval?: number;
    readTimeout?: number;
    connectionTimeout?: number;
    discretionary?: boolean;
    cacheable?: boolean;
    begin?: (result: DownloadBeginCallbackResult) => void;
    progress?: (result: DownloadProgressCallbackResult) => void;
  }

  export interface DownloadBeginCallbackResult {
    jobId: number;
    statusCode: number;
    contentLength: number;
    headers: Record<string, string>;
  }

  export interface DownloadProgressCallbackResult {
    jobId: number;
    contentLength: number;
    bytesWritten: number;
  }

  export interface DownloadResult {
    jobId: number;
    statusCode: number;
    bytesWritten: number;
  }

  export const DocumentDirectoryPath: string;
  export const CachesDirectoryPath: string;
  export const TemporaryDirectoryPath: string;
  export const LibraryDirectoryPath: string;
  export const ExternalDirectoryPath: string;
  export const MainBundlePath: string;

  export function exists(path: string): Promise<boolean>;
  export function stat(path: string): Promise<StatResult>;
  export function readDir(path: string): Promise<ReadDirItem[]>;
  export function mkdir(path: string, options?: { NSURLIsExcludedFromBackupKey?: boolean }): Promise<void>;
  export function readFile(path: string, encoding?: string): Promise<string>;
  export function writeFile(path: string, content: string, encoding?: string): Promise<void>;
  export function unlink(path: string): Promise<void>;
  export function moveFile(filepath: string, destPath: string): Promise<void>;
  export function copyFile(filepath: string, destPath: string): Promise<void>;
  export function downloadFile(options: DownloadFileOptions): { jobId: number; promise: Promise<DownloadResult> };
  export function stopDownload(jobId: number): void;
  export function hash(filepath: string, algorithm: string): Promise<string>;
  export function getFSInfo(): Promise<{ totalSpace: number; freeSpace: number }>;
}
