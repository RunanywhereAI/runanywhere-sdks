#!/bin/bash

# Build STT Worker Script
# This script builds the STT worker and copies it to the public directory

set -e

echo "Building STT Whisper package with worker..."

# Build the package
pnpm build

# Check if worker was generated
WORKER_FILE=$(ls dist/assets/stt.worker-*.js 2>/dev/null | head -n 1)

if [ -z "$WORKER_FILE" ]; then
    echo "Error: Worker file not generated"
    exit 1
fi

# Copy worker to example app public directory
DEST_DIR="/Users/sanchitmonga/development/ODLM/sdks/examples/web/runanywhere-web/public"
if [ -d "$DEST_DIR" ]; then
    cp "$WORKER_FILE" "$DEST_DIR/stt-worker.js"
    echo "Worker copied to $DEST_DIR/stt-worker.js"
else
    echo "Warning: Destination directory not found: $DEST_DIR"
fi

echo "Build complete!"
echo "Worker size: $(du -h "$WORKER_FILE" | cut -f1)"
