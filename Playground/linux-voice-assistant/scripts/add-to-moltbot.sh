#!/bin/bash
# =============================================================================
# Add RunAnywhere to Existing Moltbot Installation
# =============================================================================
# This script adds RunAnywhere extensions to an existing Moltbot installation:
# 1. RunAnywhere extension (local LLM provider)
# 2. Voice Assistant channel extension
#
# Usage: curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/add-to-moltbot.sh | bash
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Banner
# =============================================================================

echo ""
echo "=========================================="
echo "  Add RunAnywhere to Moltbot"
echo "=========================================="
echo ""

# =============================================================================
# Detect Moltbot Installation
# =============================================================================

log_info "Detecting Moltbot installation..."

# Check if moltbot CLI is available
if command -v moltbot &> /dev/null; then
    MOLTBOT_CMD="moltbot"
    log_success "Found moltbot CLI: $(which moltbot)"
elif command -v clawdbot &> /dev/null; then
    MOLTBOT_CMD="clawdbot"
    log_success "Found clawdbot CLI: $(which clawdbot)"
else
    log_error "Moltbot CLI not found!"
    log_info "Please install Moltbot first:"
    echo "  npm install -g moltbot@latest"
    echo ""
    log_info "Or use the full installation script instead:"
    echo "  curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/install.sh | bash"
    exit 1
fi

# Check Moltbot version
MOLTBOT_VERSION=$($MOLTBOT_CMD --version 2>/dev/null || echo "unknown")
log_info "Moltbot version: $MOLTBOT_VERSION"

# =============================================================================
# Configuration
# =============================================================================

TEMP_DIR=$(mktemp -d)
SDK_DIR="${SDK_DIR:-$HOME/runanywhere-sdks}"
EXTENSIONS_DIR="${HOME}/.config/moltbot/extensions"

log_info "Extensions directory: $EXTENSIONS_DIR"

# Create extensions directory if it doesn't exist
mkdir -p "$EXTENSIONS_DIR"

# =============================================================================
# Download and Install Extensions
# =============================================================================

log_info "Downloading RunAnywhere extensions..."

# Clone the fork to get the extensions
if [ -d "$SDK_DIR" ]; then
    log_info "Using existing SDK at: $SDK_DIR"
else
    log_info "Cloning RunAnywhere SDK (for voice assistant)..."
    git clone --depth 1 https://github.com/RunanywhereAI/runanywhere-sdks.git "$SDK_DIR"
fi

# Clone Moltbot fork for extensions
FORK_DIR="$TEMP_DIR/moltbot-fork"
log_info "Downloading Moltbot fork (for extensions)..."
git clone --depth 1 https://github.com/RunanywhereAI/clawdbot.git "$FORK_DIR"

# =============================================================================
# Install RunAnywhere Extension
# =============================================================================

log_info "Installing RunAnywhere extension..."

RUNANYWHERE_EXT="$FORK_DIR/extensions/runanywhere"
if [ -d "$RUNANYWHERE_EXT" ]; then
    # Use moltbot plugins install for proper installation
    $MOLTBOT_CMD plugins install "$RUNANYWHERE_EXT" 2>/dev/null || {
        # Fallback: manual copy
        log_warn "Plugin install failed, copying manually..."
        cp -r "$RUNANYWHERE_EXT" "$EXTENSIONS_DIR/runanywhere"
        cd "$EXTENSIONS_DIR/runanywhere" && npm install --omit=dev 2>/dev/null || true
    }
    log_success "RunAnywhere extension installed"
else
    log_error "RunAnywhere extension not found in fork"
fi

# =============================================================================
# Install Voice Assistant Extension
# =============================================================================

log_info "Installing Voice Assistant extension..."

VOICE_EXT="$FORK_DIR/extensions/voice-assistant"
if [ -d "$VOICE_EXT" ]; then
    # Use moltbot plugins install for proper installation
    $MOLTBOT_CMD plugins install "$VOICE_EXT" 2>/dev/null || {
        # Fallback: manual copy
        log_warn "Plugin install failed, copying manually..."
        cp -r "$VOICE_EXT" "$EXTENSIONS_DIR/voice-assistant"
        cd "$EXTENSIONS_DIR/voice-assistant" && npm install --omit=dev 2>/dev/null || true
    }
    log_success "Voice Assistant extension installed"
else
    log_error "Voice Assistant extension not found in fork"
fi

# =============================================================================
# Update Configuration
# =============================================================================

CONFIG_FILE="${HOME}/.config/moltbot/config.yaml"

log_info "Checking configuration..."

if [ -f "$CONFIG_FILE" ]; then
    # Check if RunAnywhere provider is already configured
    if grep -q "runanywhere:" "$CONFIG_FILE"; then
        log_info "RunAnywhere provider already configured"
    else
        log_info "Adding RunAnywhere provider to config..."

        # Backup config
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"

        # Append RunAnywhere config
        cat >> "$CONFIG_FILE" << 'EOF'

# =============================================================================
# RunAnywhere Configuration (added by installer)
# =============================================================================

# RunAnywhere provider for local LLM inference
providers:
  runanywhere:
    enabled: true
    baseUrl: "http://localhost:8080"
    defaultModel: "llama-3.2-3b"

# Voice Assistant channel settings (optional)
# voice-assistant:
#   enabled: true
#   wakeWord: "Hey Jarvis"
#   wsPort: 8082
EOF
        log_success "Configuration updated"
    fi
else
    log_warn "Config file not found at: $CONFIG_FILE"
    log_info "Run 'moltbot onboard' to create initial configuration"
fi

# =============================================================================
# Verify Installation
# =============================================================================

log_info "Verifying installation..."

echo ""
$MOLTBOT_CMD plugins list 2>/dev/null || log_warn "Could not list plugins"
echo ""

# =============================================================================
# Build Voice Assistant (if SDK was cloned)
# =============================================================================

if [ -d "$SDK_DIR/Playground/linux-voice-assistant" ]; then
    read -p "Do you want to build the voice assistant? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Building voice assistant..."
        cd "$SDK_DIR/Playground/linux-voice-assistant"

        # Download models
        if [ ! -d "models" ] || [ -z "$(ls -A models 2>/dev/null)" ]; then
            log_info "Downloading AI models..."
            ./scripts/download-models.sh
        fi

        # Build
        mkdir -p build
        cd build
        cmake ..
        make -j$(nproc)
        cd ..

        log_success "Voice assistant built"
    fi
fi

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$TEMP_DIR"

# =============================================================================
# Done
# =============================================================================

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
log_success "Extensions installed to: $EXTENSIONS_DIR"
echo ""
log_info "Installed extensions:"
echo "  - runanywhere: Local LLM provider"
echo "  - voice-assistant: Voice channel"
echo ""
log_info "Next steps:"
echo ""
echo "  1. Restart the Moltbot gateway:"
echo "     $MOLTBOT_CMD gateway restart"
echo "     # Or: $MOLTBOT_CMD gateway --port 18789 --verbose"
echo ""
echo "  2. Verify plugins are loaded:"
echo "     $MOLTBOT_CMD plugins list"
echo ""

if [ -d "$SDK_DIR/Playground/linux-voice-assistant/build" ]; then
    echo "  3. Start the voice assistant:"
    echo "     cd $SDK_DIR/Playground/linux-voice-assistant"
    echo "     npx tsx scripts/start-voice-bridge.ts --websocket &"
    echo "     ./build/voice-assistant --moltbot --wakeword"
    echo ""
fi

log_info "Say \"Hey Jarvis\" to activate!"
echo ""
