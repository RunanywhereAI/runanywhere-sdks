/**
 * Type declarations for optional external modules
 * These modules are dynamically imported and may not be installed
 */

// react-native-fs is an optional dependency for file operations
declare module 'react-native-fs' {
  const RNFS: {
    DocumentDirectoryPath: string;
    CachesDirectoryPath: string;
    MainBundlePath: string;
    LibraryDirectoryPath: string;
    ExternalDirectoryPath: string;
    ExternalStorageDirectoryPath: string;
    TemporaryDirectoryPath: string;
    DownloadDirectoryPath: string;
    PicturesDirectoryPath: string;

    mkdir(
      filepath: string,
      options?: { NSURLIsExcludedFromBackupKey?: boolean }
    ): Promise<void>;
    moveFile(filepath: string, destPath: string): Promise<void>;
    copyFile(filepath: string, destPath: string): Promise<void>;
    unlink(filepath: string): Promise<void>;
    exists(filepath: string): Promise<boolean>;
    readFile(filepath: string, encoding?: string): Promise<string>;
    writeFile(
      filepath: string,
      contents: string,
      encoding?: string
    ): Promise<void>;
    appendFile(
      filepath: string,
      contents: string,
      encoding?: string
    ): Promise<void>;
    stat(filepath: string): Promise<{
      name: string;
      path: string;
      size: number;
      mode: number;
      ctime: number;
      mtime: number;
      originalFilepath: string;
      isFile: () => boolean;
      isDirectory: () => boolean;
    }>;
    readDir(dirpath: string): Promise<
      Array<{
        name: string;
        path: string;
        size: number;
        ctime: Date;
        mtime: Date;
        isFile: () => boolean;
        isDirectory: () => boolean;
      }>
    >;
    hash(filepath: string, algorithm: string): Promise<string>;
    getFSInfo(): Promise<{
      totalSpace: number;
      freeSpace: number;
    }>;
    downloadFile(options: {
      fromUrl: string;
      toFile: string;
      headers?: Record<string, string>;
      background?: boolean;
      begin?: (res: {
        jobId: number;
        contentLength: number;
        statusCode: number;
      }) => void;
      progress?: (res: {
        jobId: number;
        bytesWritten: number;
        contentLength: number;
      }) => void;
      progressDivider?: number;
    }): {
      jobId: number;
      promise: Promise<{
        jobId: number;
        statusCode: number;
        bytesWritten: number;
      }>;
    };
    stopDownload(jobId: number): void;
  };
  export = RNFS;
}

// rn-fetch-blob is an optional dependency for large file downloads
declare module 'rn-fetch-blob' {
  interface FetchBlobResponse {
    path(): string;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- External library JSON type
    json(): any;
    text(): string;
    data: string;
    info(): { status: number; headers: Record<string, string> };
    flush(): void;
  }

  interface StatefulPromise<T> extends Promise<T> {
    cancel(): void;
    progress(
      callback: (received: number, total: number) => void
    ): StatefulPromise<T>;
  }

  interface RNFetchBlob {
    fs: {
      dirs: {
        DocumentDir: string;
        CacheDir: string;
        DownloadDir: string;
      };
      exists(path: string): Promise<boolean>;
      unlink(path: string): Promise<void>;
      mkdir(path: string): Promise<void>;
    };
    config(options: {
      fileCache?: boolean;
      path?: string;
      appendExt?: string;
      timeout?: number;
    }): {
      fetch(
        method: string,
        url: string,
        headers?: Record<string, string>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- External library body type
        body?: any
      ): StatefulPromise<FetchBlobResponse>;
    };
  }

  const RNFetchBlob: { default: RNFetchBlob };
  export = RNFetchBlob;
}
