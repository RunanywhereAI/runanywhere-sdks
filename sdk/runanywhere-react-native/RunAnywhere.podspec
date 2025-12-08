require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# XCFramework configuration - matches Android native-version.txt pattern
XCFRAMEWORK_VERSION = File.exist?(File.join(__dir__, "native-version.txt")) ?
  File.read(File.join(__dir__, "native-version.txt")).strip : "0.0.1-dev.e6b7a2f"
XCFRAMEWORK_NAME = "RunAnywhereCore"
GITHUB_ORG = "RunanywhereAI"
GITHUB_REPO = "runanywhere-binaries"

Pod::Spec.new do |s|
  # Pod name must match the Nitrogen module name for Swift interop
  s.name         = "RunAnywhere"
  s.module_name  = "RunAnywhere"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # Download Native XCFramework
  # =============================================================================
  # Automatically downloads pre-built XCFramework from GitHub releases
  # Similar to Android's downloadNativeLibs task in build.gradle
  s.prepare_command = <<-CMD
    set -e

    FRAMEWORK_DIR="ios/Frameworks"
    FRAMEWORK_NAME="#{XCFRAMEWORK_NAME}"
    VERSION="#{XCFRAMEWORK_VERSION}"
    VERSION_FILE="$FRAMEWORK_DIR/.version"

    # Check if already downloaded with correct version
    if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework" ]; then
      CURRENT_VERSION=$(cat "$VERSION_FILE")
      if [ "$CURRENT_VERSION" = "$VERSION" ]; then
        echo "✅ XCFramework version $VERSION already downloaded"
        exit 0
      fi
    fi

    echo "📦 Downloading $FRAMEWORK_NAME.xcframework version $VERSION..."

    # Create directory
    mkdir -p "$FRAMEWORK_DIR"

    # Download URL
    DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{GITHUB_REPO}/releases/download/v$VERSION/$FRAMEWORK_NAME.xcframework.zip"
    ZIP_FILE="/tmp/$FRAMEWORK_NAME.xcframework.zip"

    echo "   URL: $DOWNLOAD_URL"

    # Download with curl
    curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
      echo "❌ Failed to download XCFramework from $DOWNLOAD_URL"
      echo ""
      echo "Resolution options:"
      echo "  1. Check that version $VERSION exists in GitHub releases"
      echo "  2. Build locally from runanywhere-core"
      echo "  3. Check network connectivity"
      exit 1
    }

    # Remove old framework if exists
    rm -rf "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"

    # Extract
    echo "📂 Extracting XCFramework..."
    unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"

    # Cleanup
    rm -f "$ZIP_FILE"

    # Write version marker
    echo "$VERSION" > "$VERSION_FILE"

    # Verify extraction
    if [ -d "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework" ]; then
      echo "✅ XCFramework installed successfully"
      ls -la "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework/"
    else
      echo "❌ XCFramework extraction failed"
      exit 1
    fi
  CMD

  # Source files - C++ HybridObject + Swift implementations
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridRunAnywhere.cpp",
    "cpp/HybridRunAnywhere.hpp",
    "cpp/include/**/*.{h,hpp}",
  ]

  # XCFramework with runanywhere-core (ONNX Runtime + LlamaCpp + Sherpa-ONNX)
  s.vendored_frameworks = "ios/Frameworks/#{XCFRAMEWORK_NAME}.xcframework"

  # Build settings
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/include",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited)",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  # Required system libraries and frameworks
  s.libraries = "c++", "archive", "bz2"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  # React Native dependencies
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  # Load Nitrogen-generated autolinking
  load 'nitrogen/generated/ios/RunAnywhere+autolinking.rb'
  add_nitrogen_files(s)

  # Install React Native module dependencies
  install_modules_dependencies(s)
end
