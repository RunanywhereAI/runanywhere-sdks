# Release Guide

How to create releases for the RunAnywhere Voice Assistant.

## Prerequisites

1. **GitHub CLI** installed and authenticated:
   ```bash
   # Install
   sudo apt install gh

   # Authenticate
   gh auth login
   ```

2. **Build environment** set up (see SETUP.md Option 3)

## Creating a Release

### Step 1: Build All Components

```bash
cd ~/runanywhere-sdks

# Build SDK with shared libraries
cd sdk/runanywhere-commons
./scripts/build-linux.sh --shared

# Build the server
mkdir -p build-server && cd build-server
cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF
make -j$(nproc)

# Build voice assistant
cd ~/runanywhere-sdks/playground/linux-voice-assistant
rm -rf build && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### Step 2: Create Release Bundle

```bash
# Create staging directory
mkdir -p /tmp/runanywhere-release
cd /tmp/runanywhere-release
rm -rf *

# Create directory structure
mkdir -p bin lib

# Copy binaries
cp ~/runanywhere-sdks/sdk/runanywhere-commons/build-server/tools/runanywhere-server bin/
cp ~/runanywhere-sdks/playground/linux-voice-assistant/build/voice-assistant bin/

# Copy shared libraries
ARCH=$(uname -m)
cp ~/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/$ARCH/*.so lib/

# Verify contents
ls -la bin/ lib/
```

### Step 3: Create Install Script

```bash
cat > /tmp/runanywhere-release/install.sh << 'INSTALL_EOF'
#!/bin/bash
set -e
INSTALL_DIR="$HOME/.local/runanywhere"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing RunAnywhere Voice Assistant to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib"
cp -r "$SCRIPT_DIR/bin/"* "$INSTALL_DIR/bin/"
cp -r "$SCRIPT_DIR/lib/"* "$INSTALL_DIR/lib/"
cp "$SCRIPT_DIR/run.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/run.sh" "$INSTALL_DIR/bin/"*

# Create versioned symlinks for shared libraries
# (binaries may link against libonnxruntime.so.1 instead of libonnxruntime.so)
for lib in "$INSTALL_DIR/lib/"*.so; do
    [ -f "$lib" ] || continue
    base=$(basename "$lib")
    ln -sf "$base" "${lib}.1" 2>/dev/null || true
done

echo "Installation complete!"
echo "Download models: curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/download-models.sh | bash"
echo "Run: ~/.local/runanywhere/run.sh"
INSTALL_EOF
chmod +x /tmp/runanywhere-release/install.sh
```

### Step 4: Create Run Script

```bash
cat > /tmp/runanywhere-release/run.sh << 'RUN_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$HOME/.local/share/runanywhere/Models"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"

find_model() {
    for model in qwen3-1.7b qwen3-0.6b lfm-1.2b; do
        local gguf=$(ls "$MODEL_DIR/LlamaCpp/$model"/*.gguf 2>/dev/null | head -1)
        [ -n "$gguf" ] && echo "$gguf" && return 0
    done
    return 1
}

cleanup() { kill $SERVER_PID 2>/dev/null; exit 0; }
trap cleanup INT TERM

MODEL_PATH=$(find_model)
[ -z "$MODEL_PATH" ] && echo "Error: No model found. Run download-models.sh first." && exit 1

echo "Starting RunAnywhere Voice Assistant..."
echo "Model: $(basename "$MODEL_PATH")"

"$SCRIPT_DIR/bin/runanywhere-server" --model "$MODEL_PATH" --port 8080 --threads 4 &
SERVER_PID=$!
sleep 3
"$SCRIPT_DIR/bin/voice-assistant" --wakeword
cleanup
RUN_EOF
chmod +x /tmp/runanywhere-release/run.sh
```

### Step 5: Create Tarball

```bash
cd /tmp
ARCH=$(uname -m)
tar -czvf runanywhere-voice-assistant-linux-$ARCH.tar.gz runanywhere-release
ls -lh runanywhere-voice-assistant-linux-$ARCH.tar.gz
```

### Step 6: Publish to GitHub

```bash
VERSION="v0.1.0"  # Update version as needed
ARCH=$(uname -m)

cd ~/runanywhere-sdks
gh release create voice-assistant-$VERSION \
  /tmp/runanywhere-voice-assistant-linux-$ARCH.tar.gz \
  --title "Voice Assistant $VERSION (Linux $ARCH)" \
  --notes "## RunAnywhere Voice Assistant $VERSION

Pre-built binaries for Linux $ARCH.

### Install
\`\`\`bash
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-$VERSION/runanywhere-voice-assistant-linux-$ARCH.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh
\`\`\`

### Download Models
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/download-models.sh | bash
\`\`\`

### Run
\`\`\`bash
~/.local/runanywhere/run.sh
\`\`\`

Say **Hey Jarvis** to activate!
"
```

## Release Checklist

- [ ] All components build successfully
- [ ] Binaries are stripped (optional: `strip bin/*`)
- [ ] Libraries are included
- [ ] Library versioned symlinks created (libonnxruntime.so.1, etc.)
- [ ] install.sh works on clean system
- [ ] run.sh works after install
- [ ] Models download script works
- [ ] GitHub release created
- [ ] Release notes are accurate

## Version Numbering

Format: `voice-assistant-vX.Y.Z`

- **X** - Major version (breaking changes)
- **Y** - Minor version (new features)
- **Z** - Patch version (bug fixes)

## Supported Architectures

| Architecture | Platform | Status |
|--------------|----------|--------|
| aarch64 | Raspberry Pi 5, ARM64 Linux | ✅ Supported |
| x86_64 | Intel/AMD Linux | 🔄 Planned |
