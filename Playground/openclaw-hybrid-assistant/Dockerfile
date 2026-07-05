# =============================================================================
# Dockerfile for OpenClaw Hybrid Assistant Testing
# =============================================================================
# Build and test the voice assistant components without real audio hardware.
# Uses WAV files for testing wake word, VAD, and ASR.
#
# IMPORTANT: Build from the root of the sdks repository, not this directory!
#
# Build:   cd /path/to/sdks && docker build -t openclaw-assistant -f Playground/openclaw-hybrid-assistant/Dockerfile .
# Run:     docker run -it openclaw-assistant
# Shell:   docker run -it openclaw-assistant /bin/bash
# =============================================================================

FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    libasound2-dev \
    sox \
    libsox-fmt-all \
    espeak \
    espeak-ng \
    ca-certificates \
    ffmpeg \
    gpg \
    lsb-release \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install newer CMake (3.28+) from Kitware repository
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ jammy main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null \
    && apt-get update \
    && apt-get install -y cmake \
    && rm -rf /var/lib/apt/lists/*

# Verify CMake version
RUN cmake --version

# Create workspace
WORKDIR /workspace

# Copy the SDK and commons (needed for building)
COPY sdk/runanywhere-commons /workspace/sdk/runanywhere-commons

# Copy the openclaw-hybrid-assistant
COPY Playground/openclaw-hybrid-assistant /workspace/Playground/openclaw-hybrid-assistant

# Set working directory
WORKDIR /workspace/Playground/openclaw-hybrid-assistant

# Get architecture
RUN echo "Building for $(uname -m)"

# Step 1: Download Sherpa-ONNX
RUN cd /workspace/sdk/runanywhere-commons && \
    chmod +x scripts/linux/*.sh && \
    ./scripts/linux/download-sherpa-onnx.sh

# Step 2: Build runanywhere-commons
RUN cd /workspace/sdk/runanywhere-commons && \
    chmod +x scripts/*.sh && \
    ./scripts/build-linux.sh --shared

# Step 3: Download models (NO LLM)
RUN chmod +x scripts/*.sh tests/scripts/*.sh && \
    ./scripts/download-models.sh

# Step 4: Download wake word models
RUN ./scripts/download-models.sh --wakeword

# Step 5: Generate test audio files
RUN ./tests/scripts/generate-test-audio.sh

# Step 6: Build the assistant and test binary
RUN mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . -j$(nproc)

# Set library path for runtime
ENV LD_LIBRARY_PATH=/workspace/sdk/runanywhere-commons/dist/linux/x86_64:/workspace/sdk/runanywhere-commons/dist/linux/aarch64:/workspace/sdk/runanywhere-commons/third_party/sherpa-onnx-linux/lib

# Verify the build
RUN ls -la build/ && \
    echo "=== Build artifacts ===" && \
    file build/test-components build/openclaw-assistant 2>/dev/null || true

# Default command: run tests
CMD ["./build/test-components", "--run-all"]
