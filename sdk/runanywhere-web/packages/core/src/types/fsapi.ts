/**
 * FileSystemDirectoryHandle augmented with the entries() iterator,
 * which is missing from older TS DOM lib types.
 */
export type DirectoryHandleWithEntries = FileSystemDirectoryHandle & {
  entries(): AsyncIterableIterator<[string, FileSystemFileHandle | FileSystemDirectoryHandle]>;
};
