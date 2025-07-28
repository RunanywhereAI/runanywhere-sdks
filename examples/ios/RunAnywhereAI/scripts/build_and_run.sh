#!/bin/bash
# build_and_run.sh - Build, install, and run the RunAnywhereAI app
# Usage: ./build_and_run.sh [simulator|device] [device-name-or-id]
# Examples:
#   ./build_and_run.sh simulator "iPhone 16"
#   ./build_and_run.sh device "00008140-000C6D860A3B001C"
#   ./build_and_run.sh device "Monga's iphone"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Default values
TARGET_TYPE="${1:-device}"
DEVICE_NAME="${2:-}"
WORKSPACE="RunAnywhereAI.xcworkspace"
SCHEME="RunAnywhereAI"
CONFIGURATION="Debug"
BUNDLE_ID="com.runanywhere.RunAnywhereAI"

# Function to fix Pods resources script for Xcode 16
fix_pods_script() {
    local SCRIPT_PATH="Pods/Target Support Files/Pods-RunAnywhereAI/Pods-RunAnywhereAI-resources.sh"
    
    if [ ! -f "$SCRIPT_PATH" ]; then
        print_warning "Pods resources script not found. Running pod install..."
        pod install
    fi
    
    print_status "Fixing Pods script for Xcode 16 sandbox compatibility..."
    
    # Create the fixed script
    cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/sh
set -e
set -u
set -o pipefail

function on_error {
  echo "$(cd "$(dirname "${0}")" && pwd)/$(basename "${0}"):$1: error: Unexpected failure"
}
trap 'on_error $LINENO' ERR

if [ -z ${UNLOCALIZED_RESOURCES_FOLDER_PATH+x} ]; then
  exit 0
fi

mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

# Use temp directory for resources list to avoid sandbox issues
TEMP_DIR="${TMPDIR:-/tmp}"
RESOURCES_TO_COPY="${TEMP_DIR}/resources-to-copy-${TARGETNAME}-$$.txt"
> "$RESOURCES_TO_COPY"

XCASSET_FILES=()

case "${TARGETED_DEVICE_FAMILY:-}" in
  1,2)
    TARGET_DEVICE_ARGS="--target-device ipad --target-device iphone"
    ;;
  1)
    TARGET_DEVICE_ARGS="--target-device iphone"
    ;;
  2)
    TARGET_DEVICE_ARGS="--target-device ipad"
    ;;
  3)
    TARGET_DEVICE_ARGS="--target-device tv"
    ;;
  4)
    TARGET_DEVICE_ARGS="--target-device watch"
    ;;
  *)
    TARGET_DEVICE_ARGS="--target-device mac"
    ;;
esac

install_resource()
{
  if [[ "$1" = /* ]] ; then
    RESOURCE_PATH="$1"
  else
    RESOURCE_PATH="${PODS_ROOT}/$1"
  fi
  if [[ ! -e "$RESOURCE_PATH" ]] ; then
    cat << EOM
error: Resource "$RESOURCE_PATH" not found. Run 'pod install' to update the copy resources script.
EOM
    exit 1
  fi
  case $RESOURCE_PATH in
    *.storyboard)
      echo "ibtool --reference-external-strings-file --errors --warnings --notices --minimum-deployment-target ${!DEPLOYMENT_TARGET_SETTING_NAME} --output-format human-readable-text --compile ${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename \"$RESOURCE_PATH\" .storyboard`.storyboardc $RESOURCE_PATH --sdk ${SDKROOT} ${TARGET_DEVICE_ARGS}" || true
      ibtool --reference-external-strings-file --errors --warnings --notices --minimum-deployment-target ${!DEPLOYMENT_TARGET_SETTING_NAME} --output-format human-readable-text --compile "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename \"$RESOURCE_PATH\" .storyboard`.storyboardc" "$RESOURCE_PATH" --sdk "${SDKROOT}" ${TARGET_DEVICE_ARGS}
      ;;
    *.xib)
      echo "ibtool --reference-external-strings-file --errors --warnings --notices --minimum-deployment-target ${!DEPLOYMENT_TARGET_SETTING_NAME} --output-format human-readable-text --compile ${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename \"$RESOURCE_PATH\" .xib`.nib $RESOURCE_PATH --sdk ${SDKROOT} ${TARGET_DEVICE_ARGS}" || true
      ibtool --reference-external-strings-file --errors --warnings --notices --minimum-deployment-target ${!DEPLOYMENT_TARGET_SETTING_NAME} --output-format human-readable-text --compile "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename \"$RESOURCE_PATH\" .xib`.nib" "$RESOURCE_PATH" --sdk "${SDKROOT}" ${TARGET_DEVICE_ARGS}
      ;;
    *.framework)
      echo "mkdir -p ${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}" || true
      mkdir -p "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
      echo "cp -R $RESOURCE_PATH ${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}" || true
      cp -R "$RESOURCE_PATH" "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
      ;;
    *.xcdatamodel)
      echo "xcrun momc \"$RESOURCE_PATH\" \"${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH"`.mom\"" || true
      xcrun momc "$RESOURCE_PATH" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH" .xcdatamodel`.mom"
      ;;
    *.xcdatamodeld)
      echo "xcrun momc \"$RESOURCE_PATH\" \"${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH" .xcdatamodeld`.momd\"" || true
      xcrun momc "$RESOURCE_PATH" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH" .xcdatamodeld`.momd"
      ;;
    *.xcmappingmodel)
      echo "xcrun mapc \"$RESOURCE_PATH\" \"${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH" .xcmappingmodel`.cdm\"" || true
      xcrun mapc "$RESOURCE_PATH" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/`basename "$RESOURCE_PATH" .xcmappingmodel`.cdm"
      ;;
    *.xcassets)
      ABSOLUTE_XCASSET_FILE="$RESOURCE_PATH"
      XCASSET_FILES+=("$ABSOLUTE_XCASSET_FILE")
      ;;
    *)
      echo "$RESOURCE_PATH" || true
      echo "$RESOURCE_PATH" >> "$RESOURCES_TO_COPY"
      ;;
  esac
}

if [[ "$CONFIGURATION" == "Debug" ]]; then
  install_resource "${PODS_CONFIGURATION_BUILD_DIR}/TensorFlowLiteC/TensorFlowLiteC.bundle"
  install_resource "${PODS_CONFIGURATION_BUILD_DIR}/TensorFlowLiteSwift/TensorFlowLite.bundle"
fi
if [[ "$CONFIGURATION" == "Release" ]]; then
  install_resource "${PODS_CONFIGURATION_BUILD_DIR}/TensorFlowLiteC/TensorFlowLiteC.bundle"
  install_resource "${PODS_CONFIGURATION_BUILD_DIR}/TensorFlowLiteSwift/TensorFlowLite.bundle"
fi

mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

# Copy resources using cp instead of rsync
if [[ -f "$RESOURCES_TO_COPY" ]]; then
  while IFS= read -r file; do
    if [[ -n "$file" ]] && [[ -e "$file" ]]; then
      cp -R "$file" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/" || true
    fi
  done < "$RESOURCES_TO_COPY"
fi

if [[ "${ACTION}" == "install" ]] && [[ "${SKIP_INSTALL}" == "NO" ]]; then
  mkdir -p "${INSTALL_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  if [[ -f "$RESOURCES_TO_COPY" ]]; then
    while IFS= read -r file; do
      if [[ -n "$file" ]] && [[ -e "$file" ]]; then
        cp -R "$file" "${INSTALL_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/" || true
      fi
    done < "$RESOURCES_TO_COPY"
  fi
fi

# Clean up temp file
rm -f "$RESOURCES_TO_COPY"

if [[ -n "${WRAPPER_EXTENSION}" ]] && [ "`xcrun --find actool`" ] && [ -n "${XCASSET_FILES:-}" ]
then
  # Find all other xcassets (this unfortunately includes those of path pods and other targets).
  OTHER_XCASSETS=$(find -L "$PWD" -iname "*.xcassets" -type d)
  while read line; do
    if [[ $line != "${PODS_ROOT}*" ]]; then
      XCASSET_FILES+=("$line")
    fi
  done <<<"$OTHER_XCASSETS"

  if [ -z ${ASSETCATALOG_COMPILER_APPICON_NAME+x} ]; then
    printf "%s\0" "${XCASSET_FILES[@]}" | xargs -0 xcrun actool --output-format human-readable-text --notices --warnings --platform "${PLATFORM_NAME}" --minimum-deployment-target "${!DEPLOYMENT_TARGET_SETTING_NAME}" ${TARGET_DEVICE_ARGS} --compress-pngs --compile "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  else
    printf "%s\0" "${XCASSET_FILES[@]}" | xargs -0 xcrun actool --output-format human-readable-text --notices --warnings --platform "${PLATFORM_NAME}" --minimum-deployment-target "${!DEPLOYMENT_TARGET_SETTING_NAME}" ${TARGET_DEVICE_ARGS} --compress-pngs --compile "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}" --app-icon "${ASSETCATALOG_COMPILER_APPICON_NAME}" --output-partial-info-plist "${TARGET_TEMP_DIR}/assetcatalog_generated_info_cocoapods.plist"
  fi
fi
EOF
    
    chmod +x "$SCRIPT_PATH"
}

# Function to get device destination
get_destination() {
    if [ "$TARGET_TYPE" = "simulator" ]; then
        if [ -z "$DEVICE_NAME" ]; then
            # Default to iPhone 16 simulator
            echo "platform=iOS Simulator,name=iPhone 16"
        else
            echo "platform=iOS Simulator,name=$DEVICE_NAME"
        fi
    else
        # For device
        if [ -z "$DEVICE_NAME" ]; then
            # Get first connected device UUID
            DEVICE_ID=$(xcrun devicectl list devices | grep -E "iPhone|iPad" | grep "connected" | head -1 | awk '{print $3}')
            if [ -z "$DEVICE_ID" ]; then
                print_error "No connected iOS device found!"
                exit 1
            fi
            echo "id=$DEVICE_ID"
        elif [[ "$DEVICE_NAME" =~ ^[0-9a-fA-F-]+$ ]]; then
            # It's a device ID
            echo "id=$DEVICE_NAME"
        else
            # It's a device name, try to find its ID
            DEVICE_ID=$(xcrun devicectl list devices | grep "$DEVICE_NAME" | grep "connected" | awk '{print $3}' | head -1)
            if [ -z "$DEVICE_ID" ]; then
                print_error "Device '$DEVICE_NAME' not found!"
                exit 1
            fi
            echo "id=$DEVICE_ID"
        fi
    fi
}

# Main execution
print_status "Starting build process for $TARGET_TYPE..."

# Fix Pods script
fix_pods_script

# Get destination
DESTINATION=$(get_destination)
print_status "Building for destination: $DESTINATION"

# Build the app
print_status "Building the app..."
if xcodebuild -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -allowProvisioningUpdates \
    build > /tmp/xcodebuild.log 2>&1; then
    print_status "Build succeeded!"
else
    print_error "Build failed! Check /tmp/xcodebuild.log for details"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi

# Install and run
if [ "$TARGET_TYPE" = "simulator" ]; then
    # For simulator
    print_status "Installing on simulator..."
    
    # Get the app path
    APP_PATH=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
    APP_PATH="$APP_PATH/$SCHEME.app"
    
    # Boot simulator if needed
    SIMULATOR_ID=$(xcrun simctl list devices | grep "$DEVICE_NAME" | grep -v "unavailable" | awk -F '[()]' '{print $2}' | head -1)
    if [ -z "$SIMULATOR_ID" ]; then
        SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16" | grep -v "unavailable" | awk -F '[()]' '{print $2}' | head -1)
    fi
    
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    
    # Install app
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
    
    # Launch app
    print_status "Launching app on simulator..."
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
    
    # Open simulator
    open -a Simulator
    
else
    # For device
    # Extract device ID from destination
    DEVICE_ID=$(echo "$DESTINATION" | sed 's/id=//')
    
    # Get the built app path
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*/Debug-iphoneos/*" | head -1)
    
    if [ -z "$APP_PATH" ]; then
        print_error "Could not find built app!"
        exit 1
    fi
    
    print_status "Installing app on device..."
    if xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
        print_status "App installed successfully!"
    else
        print_error "Failed to install app!"
        exit 1
    fi
    
    print_status "Launching app on device..."
    if xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
        print_status "App launched successfully!"
    else
        print_error "Failed to launch app!"
        exit 1
    fi
fi

print_status "Done! The app is now running on your $TARGET_TYPE."