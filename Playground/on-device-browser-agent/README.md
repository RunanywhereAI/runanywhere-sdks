# Local Browser - On-Device AI Web Automation

# Launching support for runanywhere-web-sdk soon in our main repo: please go check it out: https://github.com/RunanywhereAI/runanywhere-sdks

A Chrome extension that uses WebLLM to run AI-powered web automation entirely on-device. No cloud APIs, no API keys, fully private.

## Demo

https://github.com/user-attachments/assets/898cc5c2-db77-4067-96e6-233c5da2bae5


## Features

- **On-Device AI**: Uses WebLLM with WebGPU acceleration for local LLM inference
- **Multi-Agent System**: Planner + Navigator agents for intelligent task execution
- **Browser Automation**: Navigate, click, type, extract data from web pages
- **Privacy-First**: All AI runs locally, no data leaves your device
- **Offline Support**: Works offline after initial model download

## Quick Start

### Prerequisites

- **Chrome 124+** (required for WebGPU in service workers)
- **Node.js 18+** and npm
- **GPU with WebGPU support** (most modern GPUs work)

### Installation

1. **Clone and install dependencies**:
   ```bash
   cd local-browser
   npm install
   ```

2. **Build the extension**:
   ```bash
   npm run build
   ```

3. **Load in Chrome**:
   - Open `chrome://extensions`
   - Enable "Developer mode" (top right)
   - Click "Load unpacked"
   - Select the `dist` folder from this project

4. **First run**:
   - Click the extension icon in your toolbar
   - The first run will download the AI model (~1GB)
   - This is cached for future use

### Usage

1. Navigate to any webpage
2. Click the Local Browser extension icon
3. Type a task like:
   - "Search for 'WebGPU' on Wikipedia and extract the first paragraph"
   - "Go to example.com and tell me what's there"
   - "Find the search box and search for 'AI news'"
4. Watch the AI execute the task step by step

## Development

### Development Mode

```bash
npm run dev
```

This watches for changes and rebuilds automatically.

### Project Structure

```
local-browser/
├── manifest.json           # Chrome extension manifest (MV3)
├── src/
│   ├── background/         # Service worker
│   │   ├── index.ts        # Entry point & message handling
│   │   ├── llm-engine.ts   # WebLLM wrapper
│   │   └── agents/         # AI agent system
│   │       ├── base-agent.ts
│   │       ├── planner-agent.ts
│   │       ├── navigator-agent.ts
│   │       └── executor.ts
│   ├── content/            # Content scripts
│   │   ├── dom-observer.ts # Page state extraction
│   │   └── action-executor.ts
│   ├── popup/              # React popup UI
│   │   ├── App.tsx
│   │   └── components/
│   └── shared/             # Shared types & constants
└── dist/                   # Build output
```

### How It Works

1. **User enters a task** in the popup UI
2. **Planner Agent** analyzes the task and creates a high-level strategy
3. **Navigator Agent** examines the current page DOM and decides on the next action
4. **Content Script** executes the action (click, type, extract, etc.)
5. Loop continues until task is complete or fails

### Agent System

The extension uses a two-agent architecture inspired by Nanobrowser:

- **PlannerAgent**: Strategic planning, creates step-by-step approach
- **NavigatorAgent**: Tactical execution, chooses specific actions based on page state

Both agents output structured JSON that is parsed and executed.

## Model Configuration

Default model: `Qwen2.5-1.5B-Instruct-q4f16_1-MLC` (~1GB)

Alternative models (configured in `src/shared/constants.ts`):
- `Phi-3.5-mini-instruct-q4f16_1-MLC` (~2GB, better reasoning)
- `Llama-3.2-1B-Instruct-q4f16_1-MLC` (~0.7GB, smaller)

## Troubleshooting

### WebGPU not supported
- Update Chrome to version 124 or later
- Check `chrome://gpu` to verify WebGPU status
- Some GPUs may not support WebGPU

### Model fails to load
- Ensure you have enough disk space (~2GB free)
- Check browser console for errors
- Try clearing the extension's storage and reloading

### Actions not executing
- Some pages block content scripts (chrome://, extension pages)
- Try on a regular webpage like wikipedia.org

### Extension not working after Chrome update
- Go to `chrome://extensions`
- Click the reload button on the extension

## Limitations

- **POC Scope**: This is a proof-of-concept, not production software
- **No Vision**: Uses text-only DOM analysis (no screenshot understanding)
- **Single Tab**: Only works with the currently active tab
- **Basic Actions**: Supports navigate, click, type, extract, scroll, wait
- **Model Size**: Smaller models may struggle with complex tasks

## Tech Stack

- **WebLLM**: On-device LLM inference with WebGPU
- **React**: Popup UI
- **TypeScript**: Type-safe development
- **Vite + CRXJS**: Chrome extension bundling
- **Chrome Extension Manifest V3**: Modern extension architecture

## Credits

This project is inspired by:
- [Nanobrowser](https://github.com/nanobrowser/nanobrowser) - Multi-agent web automation (MIT License)
- [WebLLM](https://github.com/mlc-ai/web-llm) - In-browser LLM inference (Apache-2.0 License)

### Dependency Licenses

| Package | License |
|---------|---------|
| @mlc-ai/web-llm | Apache-2.0 |
| React | MIT |
| Vite | MIT |
| @crxjs/vite-plugin | MIT |
| TypeScript | Apache-2.0 |

## License

MIT License - See LICENSE file for details.
