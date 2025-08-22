# RunAnywhere Web Voice Pipeline Demo

A vanilla JavaScript/TypeScript demo showcasing the RunAnywhere Web SDK's voice capabilities.

## Features

- Real-time Voice Activity Detection (VAD)
- Audio level visualization
- Pipeline state management
- Metrics tracking
- Beautiful UI with gradient styling

## Setup

### Prerequisites

1. Build the SDK packages first:
```bash
cd ../../../sdk/runanywhere-web
pnpm install
pnpm build
```

### Installation

```bash
npm install
```

### Development

```bash
npm run dev
```

Open http://localhost:5173 in your browser.

### Build

```bash
npm run build
```

## Usage

1. Click "Start Recording" to begin voice capture
2. Speak into your microphone
3. Watch real-time VAD detection and audio levels
4. View metrics and pipeline state updates
5. Click "Stop Recording" to end the session

## Architecture

The demo uses:
- **@runanywhere/core**: Core SDK types and utilities
- **@runanywhere/voice**: Voice pipeline and VAD services
- **Vite**: Modern build tool for fast development
- **TypeScript**: Type-safe development

## Browser Requirements

- Modern browser with Web Audio API support
- Microphone permissions required
