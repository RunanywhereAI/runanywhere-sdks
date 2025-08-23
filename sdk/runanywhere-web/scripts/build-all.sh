#!/bin/bash

# Build script for RunAnywhere Web Voice SDK
# Ensures TypeScript declarations are properly generated

set -e

echo "🚀 Building RunAnywhere Web Voice SDK..."

# Build core package
echo "📦 Building @runanywhere/core..."
cd packages/core
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build cache package
echo "📦 Building @runanywhere/cache..."
cd packages/cache
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build monitoring package
echo "📦 Building @runanywhere/monitoring..."
cd packages/monitoring
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build optimization package
echo "📦 Building @runanywhere/optimization..."
cd packages/optimization
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build workers package
echo "📦 Building @runanywhere/workers..."
cd packages/workers
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build service packages
echo "📦 Building @runanywhere/transcription..."
cd packages/transcription
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

echo "📦 Building @runanywhere/llm..."
cd packages/llm
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

echo "📦 Building @runanywhere/tts..."
cd packages/tts
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build voice package (before React since React depends on it)
echo "📦 Building @runanywhere/voice..."
cd packages/voice
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

# Build framework packages
echo "📦 Building @runanywhere/react..."
cd packages/react
npx tsc --emitDeclarationOnly
npx vite build
cd ../..

echo "✅ Build complete!"
echo ""
echo "📊 Build Summary:"
echo "  - Core packages: ✅"
echo "  - Performance packages: ✅"
echo "  - Service packages: ✅"
echo "  - Framework adapters: ✅"
echo ""
echo "🎉 RunAnywhere Web Voice SDK built successfully!"
