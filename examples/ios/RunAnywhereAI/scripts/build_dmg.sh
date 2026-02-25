#!/bin/bash
#
# build_dmg.sh — Build, sign, notarize, and package RunAnywhere.app into a .dmg
#
# Usage:
#   ./scripts/build_dmg.sh                    # Full pipeline: archive → sign → notarize → dmg
#   ./scripts/build_dmg.sh --skip-build       # Package an existing export into a dmg
#   ./scripts/build_dmg.sh --skip-notarize    # Build + package without notarization (dev testing)
#
# Prerequisites:
#   - Xcode with "Developer ID Application" certificate in keychain
#   - App-specific password stored in keychain (see setup below)
#   - create-dmg: brew install create-dmg
#
# One-time keychain setup for notarization:
#   xcrun notarytool store-credentials "YapRun-Notarize" \
#     --apple-id "san@runanywhere.ai" \
#     --team-id "L86FH3K93L" \
#     --password "xxxx-xxxx-xxxx-xxxx"
#

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/RunAnywhereAI.xcodeproj"
SCHEME="RunAnywhereAI"
XCODE_APP_NAME="RunAnywhereAI"
DISPLAY_NAME="RunAnywhere"
DMG_VOLUME_NAME="RunAnywhere"

BUILD_DIR="$PROJECT_DIR/build/dmg"
ARCHIVE_PATH="$BUILD_DIR/$XCODE_APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_OUTPUT_DIR="$PROJECT_DIR/build"
EXPORT_OPTIONS="$SCRIPT_DIR/dmg/ExportOptions-developer-id.plist"
DMG_BACKGROUND="$SCRIPT_DIR/dmg/dmg-background.png"

KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-YapRun-Notarize}"

SKIP_BUILD=false
SKIP_NOTARIZE=false

# ─── Parse Arguments ──────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --skip-build)     SKIP_BUILD=true ;;
        --skip-notarize)  SKIP_NOTARIZE=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-build] [--skip-notarize]"
            echo ""
            echo "  --skip-build      Skip xcodebuild archive+export, use existing export"
            echo "  --skip-notarize   Skip Apple notarization (for local testing)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

step() { echo -e "\n${BOLD}${GREEN}▸ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail() { echo -e "${RED}✖ $1${RESET}"; exit 1; }

# ─── Preflight Checks ────────────────────────────────────────────────────────

step "Preflight checks"

if ! command -v create-dmg &>/dev/null; then
    fail "create-dmg not found. Install with: brew install create-dmg"
fi

if ! command -v xcrun &>/dev/null; then
    fail "xcrun not found. Install Xcode command line tools."
fi

if [ ! -f "$EXPORT_OPTIONS" ]; then
    fail "Export options not found: $EXPORT_OPTIONS"
fi

echo "  Project:  $PROJECT_FILE"
echo "  Scheme:   $SCHEME"
echo "  Output:   $DMG_OUTPUT_DIR/"

# ─── Step 1: Archive ─────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = false ]; then
    step "Archiving $DISPLAY_NAME for macOS"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    xcodebuild archive \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        -configuration Release \
        CODE_SIGN_STYLE=Automatic \
        2>&1 | tail -5

    if [ ! -d "$ARCHIVE_PATH" ]; then
        fail "Archive failed — $ARCHIVE_PATH not found"
    fi
    echo "  Archive: $ARCHIVE_PATH"

    # ─── Step 2: Export with Developer ID ─────────────────────────────────────

    step "Exporting with Developer ID signing"

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -allowProvisioningUpdates \
        2>&1 | tail -5

    if [ ! -d "$EXPORT_DIR/$XCODE_APP_NAME.app" ]; then
        fail "Export failed — $XCODE_APP_NAME.app not found in $EXPORT_DIR"
    fi
    echo "  Exported: $EXPORT_DIR/$XCODE_APP_NAME.app"

    # Rename to display name
    if [ "$XCODE_APP_NAME" != "$DISPLAY_NAME" ] && [ -d "$EXPORT_DIR/$XCODE_APP_NAME.app" ]; then
        rm -rf "$EXPORT_DIR/$DISPLAY_NAME.app"
        mv "$EXPORT_DIR/$XCODE_APP_NAME.app" "$EXPORT_DIR/$DISPLAY_NAME.app"
        echo "  Renamed: $XCODE_APP_NAME.app → $DISPLAY_NAME.app"
    fi
else
    step "Skipping build (--skip-build)"
    if [ ! -d "$EXPORT_DIR/$DISPLAY_NAME.app" ] && [ ! -d "$EXPORT_DIR/$XCODE_APP_NAME.app" ]; then
        fail "No existing export found at $EXPORT_DIR/"
    fi
    # Rename if needed
    if [ -d "$EXPORT_DIR/$XCODE_APP_NAME.app" ] && [ ! -d "$EXPORT_DIR/$DISPLAY_NAME.app" ]; then
        mv "$EXPORT_DIR/$XCODE_APP_NAME.app" "$EXPORT_DIR/$DISPLAY_NAME.app"
        echo "  Renamed: $XCODE_APP_NAME.app → $DISPLAY_NAME.app"
    fi
fi

APP_PATH="$EXPORT_DIR/$DISPLAY_NAME.app"

# ─── Step 3: Notarize the .app ───────────────────────────────────────────────

if [ "$SKIP_NOTARIZE" = false ]; then
    step "Notarizing $DISPLAY_NAME.app"

    ZIP_PATH="$BUILD_DIR/$DISPLAY_NAME.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    echo "  Compressed for upload: $ZIP_PATH"

    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1 | tee "$BUILD_DIR/notarize-app.log" | tail -5

    if ! grep -q "status: Accepted" "$BUILD_DIR/notarize-app.log"; then
        warn "Notarization may have failed. Check $BUILD_DIR/notarize-app.log"
        echo "  To view details: xcrun notarytool log <submission-id> --keychain-profile $KEYCHAIN_PROFILE"
    fi

    step "Stapling notarization ticket to .app"
    xcrun stapler staple "$APP_PATH"
    echo "  Stapled: $APP_PATH"

    rm -f "$ZIP_PATH"
else
    warn "Skipping notarization (--skip-notarize)"
fi

# ─── Step 4: Get version for filename ────────────────────────────────────────

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")
DMG_FILENAME="${DISPLAY_NAME}-${APP_VERSION}-mac.dmg"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_FILENAME"

# ─── Step 5: Create .dmg ─────────────────────────────────────────────────────

step "Creating $DMG_FILENAME"
mkdir -p "$DMG_OUTPUT_DIR"
rm -f "$DMG_PATH"

DMG_ARGS=(
    --volname "$DMG_VOLUME_NAME"
    --window-pos 200 120
    --window-size 660 400
    --icon-size 120
    --icon "$DISPLAY_NAME.app" 160 190
    --app-drop-link 500 190
    --hide-extension "$DISPLAY_NAME.app"
    --no-internet-enable
)

if [ -f "$DMG_BACKGROUND" ]; then
    DMG_ARGS+=(--background "$DMG_BACKGROUND")
fi

create-dmg "${DMG_ARGS[@]}" "$DMG_PATH" "$APP_PATH"

if [ ! -f "$DMG_PATH" ]; then
    fail "DMG creation failed"
fi

# ─── Step 6: Notarize the .dmg ───────────────────────────────────────────────

if [ "$SKIP_NOTARIZE" = false ]; then
    step "Notarizing $DMG_FILENAME"

    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1 | tee "$BUILD_DIR/notarize-dmg.log" | tail -5

    if ! grep -q "status: Accepted" "$BUILD_DIR/notarize-dmg.log"; then
        warn "DMG notarization may have failed. Check $BUILD_DIR/notarize-dmg.log"
    fi

    step "Stapling notarization ticket to .dmg"
    xcrun stapler staple "$DMG_PATH"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)

step "Done!"
echo ""
echo -e "  ${BOLD}DMG:${RESET}      $DMG_PATH"
echo -e "  ${BOLD}Size:${RESET}     $DMG_SIZE"
echo -e "  ${BOLD}Version:${RESET}  $APP_VERSION ($APP_BUILD)"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "    1. Test: open \"$DMG_PATH\""
echo "    2. Upload to GitHub Release:"
echo "       gh release create v$APP_VERSION-runanywhere-mac \"$DMG_PATH\" --title \"RunAnywhere $APP_VERSION for macOS\" --notes \"Direct download for macOS.\""
echo ""
