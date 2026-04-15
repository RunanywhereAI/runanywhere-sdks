## 3.1.2
Reverts onCupertinoProtectedDataAvailabilityChanged and isCupertinoProtectedDataAvailable.

## 3.1.1
Updated flutter_secure_storage_platform_interface to latest version.

## 3.1.0
Fixed CompanyName and CompanyProduct on Windows are ignored when the lang-charset in the Runner.rc file is not 040904e4

## 3.0.0
- Migrated to win32 package replacing C.
- Changed PathNotFoundException to FileSystemException to be backwards compatible with Flutter SDK 2.12.0
- Applied lint suggestions

## 2.1.1
Revert changes made in version 2.1.0 due to breaking changes.
These changes will be republished under a new major version number 3.0.0.

## 2.1.0
- Changed PathNotFoundException to FileSystemException to be backwards compatible with Flutter SDK 2.12.0
- Applied lint suggestions

## 2.0.0
Write encrypted data to files instead of the windows credential system.

## 1.1.3
Updated flutter_secure_storage_platform_interface to latest version.

## 1.1.2
- Silently ignore errors when deleting keys that don't exist

## 1.1.1
- Fix application crash when key doesn't exists.

## 1.1.0
Features
- Add readAll, deleteAll and containsKey functions.

Bugfixes
- Fix implementation of delete operation to allow null value.

## 1.0.0
- Initial Windows implementation
