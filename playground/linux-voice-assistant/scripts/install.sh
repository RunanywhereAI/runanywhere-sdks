#!/bin/bash
# =============================================================================
# RunAnywhere Voice Assistant - Full Installation Script
# =============================================================================
# This script installs:
# 1. Moltbot (RunAnywhere fork with voice channel)
# 2. Voice Assistant SDK and models
# 3. Voice Bridge for Moltbot integration
#
# Usage: curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/playground/linux-voice-assistant/scripts/install.sh | bash
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
echo "  RunAnywhere Voice Assistant Installer"
echo "=========================================="
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

log_info "Checking prerequisites..."

# Check Node.js
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please install Node.js 22 or later."
    log_info "Visit: https://nodejs.org/ or use nvm: https://github.com/nvm-sh/nvm"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 22 ]; then
    log_error "Node.js version 22 or later is required. Found: $(node -v)"
    exit 1
fi
log_success "Node.js $(node -v) found"

# Check npm
if ! command -v npm &> /dev/null; then
    log_error "npm is not installed."
    exit 1
fi
log_success "npm $(npm -v) found"

# Check git
if ! command -v git &> /dev/null; then
    log_error "git is not installed. Please install git."
    exit 1
fi
log_success "git found"

# Check build tools (for C++ voice assistant)
if ! command -v cmake &> /dev/null; then
    log_warn "cmake not found. Installing build tools..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y cmake build-essential libasound2-dev
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y cmake gcc-c++ alsa-lib-devel
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm cmake base-devel alsa-lib
    else
        log_error "Could not install cmake. Please install it manually."
        exit 1
    fi
fi
log_success "cmake found"

# =============================================================================
# Configuration
# =============================================================================

MOLTBOT_DIR="${MOLTBOT_DIR:-$HOME/moltbot}"
SDK_DIR="${SDK_DIR:-$HOME/runanywhere-sdks}"
INSTALL_DAEMON="${INSTALL_DAEMON:-false}"

echo ""
log_info "Installation directories:"
echo "  Moltbot: $MOLTBOT_DIR"
echo "  SDK: $SDK_DIR"
echo ""

# =============================================================================
# Install Moltbot (RunAnywhere Fork)
# =============================================================================

if [ -d "$MOLTBOT_DIR" ]; then
    log_warn "Moltbot directory already exists: $MOLTBOT_DIR"
    read -p "Do you want to update it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Updating Moltbot..."
        cd "$MOLTBOT_DIR"
        git pull
    fi
else
    log_info "Cloning Moltbot (RunAnywhere fork)..."
    git clone https://github.com/RunanywhereAI/clawdbot.git "$MOLTBOT_DIR"
fi

cd "$MOLTBOT_DIR"

log_info "Installing Moltbot dependencies..."
npm install

log_info "Building Moltbot..."
npm run build

log_success "Moltbot installed successfully"

# =============================================================================
# Install Voice Assistant SDK
# =============================================================================

if [ -d "$SDK_DIR" ]; then
    log_warn "SDK directory already exists: $SDK_DIR"
    read -p "Do you want to update it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Updating SDK..."
        cd "$SDK_DIR"
        git pull
    fi
else
    log_info "Cloning RunAnywhere SDK..."
    git clone https://github.com/RunanywhereAI/runanywhere-sdks.git "$SDK_DIR"
fi

cd "$SDK_DIR/playground/linux-voice-assistant"

# =============================================================================
# Download Models
# =============================================================================

log_info "Downloading AI models (this may take a while)..."
./scripts/download-models.sh

# Download wake word models (optional)
read -p "Do you want to download wake word models? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./scripts/download-models.sh --wakeword
fi

# =============================================================================
# Build Voice Assistant
# =============================================================================

log_info "Building voice assistant..."
mkdir -p build
cd build
cmake ..
make -j$(nproc)
cd ..

log_success "Voice assistant built successfully"

# =============================================================================
# Create Convenience Scripts
# =============================================================================

log_info "Creating convenience scripts..."

# Start script
cat > "$SDK_DIR/playground/linux-voice-assistant/start.sh" << 'SCRIPT'
#!/bin/bash
# Start the complete voice assistant stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting voice assistant stack..."

# Start Moltbot gateway in background
echo "Starting Moltbot gateway..."
cd ~/moltbot
npm run moltbot -- gateway --port 18789 &
MOLTBOT_PID=$!

# Wait for gateway to start
sleep 3

# Start voice bridge in background
echo "Starting voice bridge..."
cd "$SCRIPT_DIR"
npx tsx scripts/start-voice-bridge.ts --websocket &
BRIDGE_PID=$!

# Wait for bridge to start
sleep 2

# Start voice assistant
echo "Starting voice assistant..."
./build/voice-assistant --moltbot --wakeword

# Cleanup on exit
trap "kill $MOLTBOT_PID $BRIDGE_PID 2>/dev/null" EXIT
SCRIPT
chmod +x "$SDK_DIR/playground/linux-voice-assistant/start.sh"

# Stop script
cat > "$SDK_DIR/playground/linux-voice-assistant/stop.sh" << 'SCRIPT'
#!/bin/bash
# Stop all voice assistant processes

echo "Stopping voice assistant processes..."
pkill -f "voice-assistant" 2>/dev/null
pkill -f "start-voice-bridge" 2>/dev/null
pkill -f "moltbot.*gateway" 2>/dev/null
echo "Done"
SCRIPT
chmod +x "$SDK_DIR/playground/linux-voice-assistant/stop.sh"

log_success "Convenience scripts created"

# =============================================================================
# Optional: Install systemd services
# =============================================================================

if [ "$INSTALL_DAEMON" = "true" ] || [ -n "$SYSTEMD_INSTALL" ]; then
    log_info "Installing systemd services..."

    # Create moltbot service
    sudo tee /etc/systemd/system/moltbot.service > /dev/null << EOF
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MOLTBOT_DIR
ExecStart=$(which npm) run moltbot -- gateway --port 18789
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create voice-bridge service
    sudo tee /etc/systemd/system/voice-bridge.service > /dev/null << EOF
[Unit]
Description=Voice Bridge
After=moltbot.service
Requires=moltbot.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$SDK_DIR/playground/linux-voice-assistant
ExecStart=$(which npx) tsx scripts/start-voice-bridge.ts --websocket
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create voice-assistant service
    sudo tee /etc/systemd/system/voice-assistant.service > /dev/null << EOF
[Unit]
Description=Voice Assistant
After=voice-bridge.service
Requires=voice-bridge.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$SDK_DIR/playground/linux-voice-assistant
ExecStart=$SDK_DIR/playground/linux-voice-assistant/build/voice-assistant --moltbot --wakeword
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    log_success "Systemd services installed"

    echo ""
    log_info "To start services:"
    echo "  sudo systemctl start moltbot"
    echo "  sudo systemctl start voice-bridge"
    echo "  sudo systemctl start voice-assistant"
    echo ""
    log_info "To enable on boot:"
    echo "  sudo systemctl enable moltbot voice-bridge voice-assistant"
fi

# =============================================================================
# Done
# =============================================================================

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
log_success "Moltbot installed at: $MOLTBOT_DIR"
log_success "Voice Assistant installed at: $SDK_DIR/playground/linux-voice-assistant"
echo ""
log_info "Next steps:"
echo ""
echo "  1. Run Moltbot onboarding (first time only):"
echo "     cd $MOLTBOT_DIR && npm run moltbot -- onboard"
echo ""
echo "  2. Start the voice assistant stack:"
echo "     cd $SDK_DIR/playground/linux-voice-assistant"
echo "     ./start.sh"
echo ""
echo "  Or start components individually:"
echo "     # Terminal 1: Moltbot gateway"
echo "     cd $MOLTBOT_DIR && npm run moltbot -- gateway --port 18789"
echo ""
echo "     # Terminal 2: Voice bridge"
echo "     cd $SDK_DIR/playground/linux-voice-assistant"
echo "     npx tsx scripts/start-voice-bridge.ts --websocket"
echo ""
echo "     # Terminal 3: Voice assistant"
echo "     ./build/voice-assistant --moltbot --wakeword"
echo ""
log_info "Say \"Hey Jarvis\" to activate!"
echo ""
