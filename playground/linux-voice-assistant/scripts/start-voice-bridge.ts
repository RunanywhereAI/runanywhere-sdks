#!/usr/bin/env npx tsx
/**
 * Voice Bridge - WebSocket Client for Moltbot Voice Channel
 *
 * This bridge provides TWO modes of operation:
 *
 * 1. WEBSOCKET MODE (Recommended):
 *    - Connects to Moltbot voice-assistant channel via WebSocket
 *    - Bidirectional: transcriptions → Moltbot, speak commands → voice assistant
 *    - Real-time streaming of all channel messages
 *
 * 2. HTTP MODE (Legacy/Standalone):
 *    - HTTP server receives transcriptions from voice assistant
 *    - Forwards to Moltbot via HTTP API
 *    - No real-time outbound streaming
 *
 * Usage:
 *   npx tsx start-voice-bridge.ts [options]
 *
 * Options:
 *   --mode <ws|http>        Connection mode (default: ws)
 *   --ws-url <url>          Moltbot WebSocket URL (default: ws://localhost:8082)
 *   --http-port <port>      HTTP port for voice assistant (default: 8081)
 *   --moltbot-url <url>     Moltbot HTTP URL for legacy mode (default: http://localhost:3000)
 *   --moltbot-token <tok>   Auth token for Moltbot
 *   --device-id <id>        Device identifier (default: pi-voice)
 *   --help, -h              Show this help
 */

import { createServer, IncomingMessage, ServerResponse } from "node:http";
import WebSocket from "ws";

// =============================================================================
// TYPES
// =============================================================================

interface Config {
  mode: "ws" | "http";
  wsUrl: string;
  httpPort: number;
  moltbotUrl: string;
  moltbotToken: string;
  deviceId: string;
}

// Messages TO Moltbot
interface TranscriptionMessage {
  type: "transcription";
  text: string;
  sessionId?: string;
  timestamp?: number;
  isFinal?: boolean;
}

interface ConnectMessage {
  type: "connect";
  deviceId: string;
  accountId?: string;
  capabilities?: {
    stt?: boolean;
    tts?: boolean;
    wakeWord?: boolean;
  };
}

// Messages FROM Moltbot
interface SpeakMessage {
  type: "speak";
  text: string;
  sourceChannel?: string;
  priority?: number;
  interrupt?: boolean;
}

interface ConnectedMessage {
  type: "connected";
  sessionId: string;
  serverVersion: string;
}

// =============================================================================
// CONFIGURATION
// =============================================================================

function parseArgs(): Config {
  const args = process.argv.slice(2);
  const config: Config = {
    mode: "ws",
    wsUrl: "ws://localhost:8082",
    httpPort: 8081,
    moltbotUrl: "http://localhost:3000",
    moltbotToken: "",
    deviceId: "pi-voice",
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const next = args[i + 1];

    switch (arg) {
      case "--mode":
        if (next === "ws" || next === "http") {
          config.mode = next;
          i++;
        }
        break;
      case "--ws-url":
        if (next) { config.wsUrl = next; i++; }
        break;
      case "--http-port":
        if (next) { config.httpPort = parseInt(next, 10); i++; }
        break;
      case "--moltbot-url":
        if (next) { config.moltbotUrl = next; i++; }
        break;
      case "--moltbot-token":
        if (next) { config.moltbotToken = next; i++; }
        break;
      case "--device-id":
        if (next) { config.deviceId = next; i++; }
        break;
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
    }
  }

  return config;
}

function printHelp(): void {
  console.log(`
Voice Bridge - WebSocket Client for Moltbot Voice Channel

Connects the voice assistant to Moltbot for bidirectional communication.
All messages from any channel (WhatsApp, Telegram, etc.) are forwarded
to voice for TTS playback.

Usage: npx tsx start-voice-bridge.ts [options]

Options:
  --mode <ws|http>        Connection mode (default: ws)
                          ws   = WebSocket to Moltbot voice channel (recommended)
                          http = HTTP bridge for legacy/standalone

  --ws-url <url>          Moltbot WebSocket URL (default: ws://localhost:8082)
  --http-port <port>      HTTP server port (default: 8081)
  --moltbot-url <url>     Moltbot HTTP URL (default: http://localhost:3000)
  --moltbot-token <tok>   Auth token for Moltbot
  --device-id <id>        Device identifier (default: pi-voice)
  --help, -h              Show this help

Examples:
  # WebSocket mode (connects to Moltbot voice channel)
  npx tsx start-voice-bridge.ts --mode ws --ws-url ws://localhost:8082

  # HTTP mode (standalone bridge)
  npx tsx start-voice-bridge.ts --mode http --moltbot-url http://localhost:3000
`);
}

// =============================================================================
// WEBSOCKET MODE
// =============================================================================

// Speak queue for C++ voice assistant to poll
interface SpeakQueueItem {
  text: string;
  sourceChannel: string;
  timestamp: number;
  priority: number;
}

class WebSocketBridge {
  private ws: WebSocket | null = null;
  private config: Config;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private pingTimer: NodeJS.Timeout | null = null;
  private httpServer: ReturnType<typeof createServer> | null = null;

  // Queue of messages to speak (for C++ voice assistant to poll)
  private speakQueue: SpeakQueueItem[] = [];
  private readonly maxQueueSize = 100;

  // Callback for when we receive speak commands
  onSpeak: ((text: string, source: string) => void) | null = null;

  constructor(config: Config) {
    this.config = config;
  }

  async start(): Promise<void> {
    // Start HTTP server for receiving transcriptions from voice assistant
    this.startHttpServer();

    // Connect to Moltbot
    this.connect();
  }

  private connect(): void {
    if (this.ws) {
      try { this.ws.close(); } catch {}
    }

    console.log(`[Bridge] Connecting to ${this.config.wsUrl}...`);

    this.ws = new WebSocket(this.config.wsUrl);

    this.ws.on("open", () => {
      console.log("[Bridge] Connected to Moltbot voice channel");

      // Send connect message
      const connectMsg: ConnectMessage = {
        type: "connect",
        deviceId: this.config.deviceId,
        accountId: "default",
        capabilities: {
          stt: true,
          tts: true,
          wakeWord: true,
        },
      };
      this.ws?.send(JSON.stringify(connectMsg));

      // Start ping timer
      this.startPingTimer();
    });

    this.ws.on("message", (data) => {
      this.handleMessage(data);
    });

    this.ws.on("close", (code, reason) => {
      console.log(`[Bridge] Disconnected (code: ${code})`);
      this.stopPingTimer();
      this.scheduleReconnect();
    });

    this.ws.on("error", (error) => {
      console.error("[Bridge] WebSocket error:", error.message);
    });
  }

  private handleMessage(data: WebSocket.RawData): void {
    try {
      const message = JSON.parse(data.toString());

      switch (message.type) {
        case "connected":
          const connected = message as ConnectedMessage;
          console.log(`[Bridge] Session: ${connected.sessionId}, Server: ${connected.serverVersion}`);
          break;

        case "speak":
          const speak = message as SpeakMessage;
          console.log(`[Bridge] SPEAK (from ${speak.sourceChannel ?? "voice"}): "${speak.text.substring(0, 50)}..."`);

          // Add to speak queue for C++ voice assistant to poll
          this.addToSpeakQueue(speak.text, speak.sourceChannel ?? "voice", speak.priority ?? 0);

          if (this.onSpeak) {
            this.onSpeak(speak.text, speak.sourceChannel ?? "voice");
          }
          break;

        case "pong":
          // Keepalive response, ignore
          break;

        case "error":
          console.error(`[Bridge] Error from Moltbot: ${message.code} - ${message.message}`);
          break;

        default:
          console.log(`[Bridge] Unknown message type: ${message.type}`);
      }
    } catch (error) {
      console.error("[Bridge] Failed to parse message:", error);
    }
  }

  private startPingTimer(): void {
    this.stopPingTimer();
    this.pingTimer = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: "ping", timestamp: Date.now() }));
      }
    }, 30000);
  }

  private stopPingTimer(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer) return;

    console.log("[Bridge] Reconnecting in 5 seconds...");
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, 5000);
  }

  /**
   * Add message to speak queue
   */
  private addToSpeakQueue(text: string, sourceChannel: string, priority: number): void {
    const item: SpeakQueueItem = {
      text,
      sourceChannel,
      timestamp: Date.now(),
      priority,
    };

    // Insert based on priority (higher priority first)
    let inserted = false;
    for (let i = 0; i < this.speakQueue.length; i++) {
      if (priority > this.speakQueue[i].priority) {
        this.speakQueue.splice(i, 0, item);
        inserted = true;
        break;
      }
    }
    if (!inserted) {
      this.speakQueue.push(item);
    }

    // Limit queue size
    while (this.speakQueue.length > this.maxQueueSize) {
      this.speakQueue.pop();
    }
  }

  /**
   * Get next message to speak (removes from queue)
   */
  getNextSpeak(): SpeakQueueItem | null {
    return this.speakQueue.shift() ?? null;
  }

  /**
   * Get all pending speak messages (clears queue)
   */
  getAllSpeaks(): SpeakQueueItem[] {
    const items = [...this.speakQueue];
    this.speakQueue = [];
    return items;
  }

  /**
   * Send transcription to Moltbot
   */
  sendTranscription(text: string, sessionId?: string): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.error("[Bridge] Not connected to Moltbot");
      return false;
    }

    const msg: TranscriptionMessage = {
      type: "transcription",
      text,
      sessionId: sessionId ?? "main",
      timestamp: Date.now(),
      isFinal: true,
    };

    this.ws.send(JSON.stringify(msg));
    console.log(`[Bridge] Sent transcription: "${text}"`);
    return true;
  }

  /**
   * Start HTTP server for voice assistant to send transcriptions
   */
  private startHttpServer(): void {
    this.httpServer = createServer((req, res) => {
      this.handleHttpRequest(req, res);
    });

    this.httpServer.listen(this.config.httpPort, () => {
      console.log(`[Bridge] HTTP server on http://localhost:${this.config.httpPort}`);
    });
  }

  private async handleHttpRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    // CORS
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    // Health check
    if (req.method === "GET" && req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        connected: this.ws?.readyState === WebSocket.OPEN,
        mode: "websocket",
      }));
      return;
    }

    // Get next message to speak (for C++ voice assistant to poll)
    if (req.method === "GET" && req.url === "/speak") {
      const item = this.getNextSpeak();
      res.writeHead(200, { "Content-Type": "application/json" });
      if (item) {
        res.end(JSON.stringify({
          text: item.text,
          sourceChannel: item.sourceChannel,
          timestamp: item.timestamp,
        }));
      } else {
        res.end(JSON.stringify({ text: null }));
      }
      return;
    }

    // Get all pending messages to speak
    if (req.method === "GET" && req.url === "/speak-all") {
      const items = this.getAllSpeaks();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ messages: items }));
      return;
    }

    // Transcription endpoint
    if (req.method === "POST" && req.url === "/transcription") {
      const chunks: Buffer[] = [];
      for await (const chunk of req) {
        chunks.push(chunk as Buffer);
      }

      try {
        const body = JSON.parse(Buffer.concat(chunks).toString());
        if (!body.text) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Missing text field" }));
          return;
        }

        const sent = this.sendTranscription(body.text, body.sessionId);
        res.writeHead(sent ? 200 : 503, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          ok: sent,
          message: sent ? "Transcription sent" : "Not connected to Moltbot",
        }));
      } catch (error) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
      }
      return;
    }

    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  }

  stop(): void {
    this.stopPingTimer();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    if (this.httpServer) {
      this.httpServer.close();
      this.httpServer = null;
    }
  }
}

// =============================================================================
// HTTP MODE (Legacy)
// =============================================================================

async function runHttpMode(config: Config): Promise<void> {
  console.log("[Bridge] Running in HTTP-only mode (legacy)");

  const server = createServer(async (req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    if (req.method !== "POST" || req.url !== "/transcription") {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Not found" }));
      return;
    }

    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      chunks.push(chunk as Buffer);
    }

    try {
      const body = JSON.parse(Buffer.concat(chunks).toString());
      if (!body.text) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Missing text field" }));
        return;
      }

      // Forward to Moltbot via HTTP
      const response = await forwardToMoltbot(body.text, body.sessionId, config);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(response));
    } catch (error) {
      console.error("[Bridge] Error:", error);
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Internal server error" }));
    }
  });

  server.listen(config.httpPort, () => {
    console.log(`[Bridge] HTTP server on http://localhost:${config.httpPort}`);
  });
}

async function forwardToMoltbot(
  text: string,
  sessionId: string | undefined,
  config: Config
): Promise<{ text: string; finished: boolean }> {
  console.log(`[Bridge] Forwarding: "${text}"`);

  try {
    // Try /api/chat first, then /hooks/agent
    let response = await fetch(`${config.moltbotUrl}/api/chat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(config.moltbotToken && { Authorization: `Bearer ${config.moltbotToken}` }),
      },
      body: JSON.stringify({ message: text, sessionId: sessionId ?? "voice-session" }),
      signal: AbortSignal.timeout(60000),
    });

    if (response.status === 404) {
      response = await fetch(`${config.moltbotUrl}/hooks/agent`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(config.moltbotToken && {
            Authorization: `Bearer ${config.moltbotToken}`,
            "x-moltbot-token": config.moltbotToken,
          }),
        },
        body: JSON.stringify({
          message: text,
          name: "Voice",
          sessionKey: `voice:${sessionId ?? "default"}`,
          deliver: false,
          channel: "voice-assistant",
        }),
        signal: AbortSignal.timeout(60000),
      });
    }

    if (!response.ok) {
      throw new Error(`Moltbot returned ${response.status}`);
    }

    const data = await response.json() as { response?: string; text?: string };
    const responseText = data.response ?? data.text ?? "";
    console.log(`[Bridge] Response: "${responseText}"`);
    return { text: responseText, finished: true };
  } catch (error) {
    console.error("[Bridge] Error:", error);
    return { text: "I'm having trouble processing that.", finished: true };
  }
}

// =============================================================================
// MAIN
// =============================================================================

async function main(): Promise<void> {
  const config = parseArgs();

  console.log("========================================");
  console.log("    Voice Bridge for Moltbot");
  console.log("========================================");
  console.log();
  console.log(`Mode:         ${config.mode === "ws" ? "WebSocket (recommended)" : "HTTP (legacy)"}`);
  console.log(`WebSocket:    ${config.wsUrl}`);
  console.log(`HTTP Port:    ${config.httpPort}`);
  console.log(`Device ID:    ${config.deviceId}`);
  console.log();

  if (config.mode === "ws") {
    const bridge = new WebSocketBridge(config);

    // Handle speak commands (for testing/logging)
    bridge.onSpeak = (text, source) => {
      console.log(`[TTS] Would speak: "${text}" (from ${source})`);
      // In the real voice assistant, this would trigger TTS playback
    };

    await bridge.start();

    // Shutdown handling
    const shutdown = () => {
      console.log("\n[Bridge] Shutting down...");
      bridge.stop();
      process.exit(0);
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
  } else {
    await runHttpMode(config);
  }

  console.log("========================================");
  console.log("Voice Bridge is running.");
  console.log("Press Ctrl+C to stop.");
  console.log("========================================");
}

main().catch(console.error);
