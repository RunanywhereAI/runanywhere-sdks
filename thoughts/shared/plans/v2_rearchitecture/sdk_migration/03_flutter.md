# Flutter SDK — migration plan

> `sdk/runanywhere-flutter/` is a melos-managed Dart monorepo. The
> production package uses Dart FFI to load a platform-specific shared
> library built from `sdk/runanywhere-commons/`.
>
> **Goal of this migration:** the FFI bindings regenerate against new
> ABI headers, and the shared library ships from the new core.

## Step 1 — Current interop layer

- `sdk/runanywhere-flutter/packages/runanywhere/lib/src/ffi/*.dart` —
  Dart FFI bindings (generated).
- `sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs/*/libcommons.so` —
  built from legacy commons.
- `sdk/runanywhere-flutter/packages/runanywhere/ios/libcommons.a` — iOS
  static library.
- `sdk/runanywhere-flutter/packages/runanywhere/macos/libcommons.dylib`,
  `linux/`, `windows/` — desktop shared libs.

## Step 2 — Symbol inventory

All `rac_*` entry points — pulled via `ffigen` from the legacy header.
New inventory pulls from `core/abi/*.h` + `core/net/*.h` + `core/util/*.h`.

## Step 3 — ABI mapping

`ffigen.yaml` updated to point at the new headers. Generated types
replace the old ones in `lib/src/ffi/`. Public Dart API under
`lib/src/adapter/` stays the same — only the private FFI layer moves.

## Step 4 — Native artifacts

Shared library per platform, copied into each platform's bundle:

```bash
# iOS (device + sim)
cmake --preset ios-release -DRA_STATIC_PLUGINS=ON
cp build/ios-release/core/libra_core.a \
   sdk/runanywhere-flutter/packages/runanywhere/ios/libs/

# Android (4 ABIs)
./sdk/runanywhere-kotlin/scripts/build-core-aar.sh  # reuse
cp -r build/android-*/engines/**/*.so \
   sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs/

# Desktop (macOS, Linux, Windows)
cmake --preset macos-release && cmake --build --preset macos-release
cp build/macos-release/core/libra_core.dylib \
   sdk/runanywhere-flutter/packages/runanywhere/macos/
```

## Step 5 — Wire the interop layer

Run `dart run ffigen --config ffigen.yaml` to regenerate bindings.
Verify the Dart-side types in `lib/src/ffi/ra_bindings.dart` look sane.

## Step 6 — Run the SDK's tests

```
cd sdk/runanywhere-flutter
melos bootstrap
melos run test
```

## Step 7 — Run the example app

```
cd examples/flutter/RunAnywhereAI
flutter run -d "iPhone 15"
flutter run -d <android_device>
```

## Known risks

- **Desktop Linux / Windows** — lower priority per earlier scope note;
  Flutter primary targets iOS + Android.
- **FFI calling convention** — ensure `@Native<Void Function(...)>`
  annotations match the new ABI.
