require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# XCFramework configuration
XCFRAMEWORK_VERSION = File.exist?(File.join(__dir__, "native-version.txt")) ?
  File.read(File.join(__dir__, "native-version.txt")).strip : "0.0.1-dev.e6b7a2f"
XCFRAMEWORK_NAME = "RunAnywhereCore"
GITHUB_ORG = "RunanywhereAI"
GITHUB_REPO = "runanywhere-binaries"

Pod::Spec.new do |s|
  s.name         = "RunAnywhereNative"
  s.module_name  = "RunAnywhereNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # Download Native XCFramework
  # =============================================================================
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

    mkdir -p "$FRAMEWORK_DIR"

    DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{GITHUB_REPO}/releases/download/v$VERSION/$FRAMEWORK_NAME.xcframework.zip"
    ZIP_FILE="/tmp/$FRAMEWORK_NAME.xcframework.zip"

    echo "   URL: $DOWNLOAD_URL"

    curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
      echo "❌ Failed to download XCFramework from $DOWNLOAD_URL"
      exit 1
    }

    rm -rf "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework"

    echo "📂 Extracting XCFramework..."
    unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"

    rm -f "$ZIP_FILE"

    echo "$VERSION" > "$VERSION_FILE"

    if [ -d "$FRAMEWORK_DIR/$FRAMEWORK_NAME.xcframework" ]; then
      echo "✅ XCFramework installed successfully"
    else
      echo "❌ XCFramework extraction failed"
      exit 1
    fi
  CMD

  # Source files
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridRunAnywhere.cpp",
    "cpp/HybridRunAnywhere.hpp",
    "cpp/include/**/*.{h,hpp}",
  ]

  # XCFramework
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

  install_modules_dependencies(s)
end
