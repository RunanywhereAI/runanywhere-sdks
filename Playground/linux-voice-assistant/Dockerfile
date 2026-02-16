# =============================================================================
# Dockerfile for Linux Voice Assistant — Build Verification
# =============================================================================
# Build from the SDK repository root:
#   docker build -t linux-voice-assistant -f Playground/linux-voice-assistant/Dockerfile .
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential git curl wget \
    libasound2-dev ca-certificates gpg lsb-release software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install newer CMake from Kitware
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ jammy main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null \
    && apt-get update && apt-get install -y cmake && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy SDK commons (needed for headers and libraries)
COPY sdk/runanywhere-commons /workspace/sdk/runanywhere-commons

# Copy the linux voice assistant
COPY Playground/linux-voice-assistant /workspace/Playground/linux-voice-assistant

WORKDIR /workspace/Playground/linux-voice-assistant

# Step 1: Download Sherpa-ONNX
RUN cd /workspace/sdk/runanywhere-commons && \
    chmod +x scripts/linux/*.sh && \
    ./scripts/linux/download-sherpa-onnx.sh

# Step 2: Build runanywhere-commons
RUN cd /workspace/sdk/runanywhere-commons && \
    chmod +x scripts/*.sh && \
    ./scripts/build-linux.sh --shared

# Step 3: Build the voice assistant (compilation check)
RUN mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . -j$(nproc)

# Verify build artifacts
RUN ls -la build/voice-assistant build/test-pipeline

CMD ["echo", "Build verification successful"]
