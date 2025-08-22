import {
  VoicePipelineManager,
  PipelineEvent,
  PipelineState
} from '@runanywhere/voice';
import {
  logger,
  LogLevel,
  DIContainer
} from '@runanywhere/core';

// Configure logger for demo
logger.setLevel(LogLevel.DEBUG);
logger.addHandler((entry) => {
  console.log(`[${entry.category}] ${entry.message}`, entry.context);
});

// UI Elements
const initBtn = document.getElementById('initBtn') as HTMLButtonElement;
const startBtn = document.getElementById('startBtn') as HTMLButtonElement;
const stopBtn = document.getElementById('stopBtn') as HTMLButtonElement;
const pauseBtn = document.getElementById('pauseBtn') as HTMLButtonElement;
const statusEl = document.getElementById('status') as HTMLDivElement;
const statusTextEl = document.getElementById('statusText') as HTMLSpanElement;
const eventsEl = document.getElementById('events') as HTMLDivElement;
const speechCountEl = document.getElementById('speechCount') as HTMLDivElement;
const totalDurationEl = document.getElementById('totalDuration') as HTMLDivElement;
const avgEnergyEl = document.getElementById('avgEnergy') as HTMLDivElement;
const healthEl = document.getElementById('health') as HTMLDivElement;
const canvas = document.getElementById('visualizer') as HTMLCanvasElement;
const ctx = canvas.getContext('2d')!;

// Phase 2 UI Elements
const transcriptionEl = document.getElementById('transcription') as HTMLDivElement;
const partialTranscriptionEl = document.getElementById('partialTranscription') as HTMLDivElement;
const llmResponseEl = document.getElementById('llmResponse') as HTMLDivElement;
const llmStreamingEl = document.getElementById('llmStreaming') as HTMLDivElement;

// State
let pipeline: VoicePipelineManager | null = null;
let container: DIContainer | null = null;
let speechCount = 0;
let totalDuration = 0;
let energySum = 0;
let energyCount = 0;
let animationId: number | null = null;
let audioLevels: number[] = new Array(50).fill(0);

// Initialize canvas size
function resizeCanvas() {
  const rect = canvas.getBoundingClientRect();
  canvas.width = rect.width;
  canvas.height = rect.height;
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();

// Audio visualization
function drawVisualization() {
  ctx.fillStyle = '#f8f9fa';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  const barWidth = canvas.width / audioLevels.length;
  const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
  gradient.addColorStop(0, '#667eea');
  gradient.addColorStop(1, '#764ba2');
  ctx.fillStyle = gradient;

  audioLevels.forEach((level, index) => {
    const barHeight = level * canvas.height;
    const x = index * barWidth;
    const y = canvas.height - barHeight;

    ctx.fillRect(x + 2, y, barWidth - 4, barHeight);
  });

  // Decay levels
  audioLevels = audioLevels.map(level => level * 0.95);

  animationId = requestAnimationFrame(drawVisualization);
}

// Update UI status
function updateStatus(status: string, className: string = 'idle') {
  statusTextEl.textContent = status;
  statusEl.className = `status-card ${className}`;

  // Update status icon
  const icon = statusEl.querySelector('.status-icon') as HTMLElement;
  if (icon) {
    icon.className = className === 'listening' ? 'status-icon' : 'status-icon inactive';
  }
}

// Add event to log
function addEvent(type: string, details: string = '') {
  const time = new Date().toLocaleTimeString();
  const eventDiv = document.createElement('div');
  eventDiv.className = 'event-entry';
  eventDiv.innerHTML = `
    <span class="event-time">${time}</span>
    <span class="event-type">${type}</span>
    <span class="event-details">${details}</span>
  `;

  eventsEl.insertBefore(eventDiv, eventsEl.firstChild);

  // Keep only last 50 events
  while (eventsEl.children.length > 50) {
    eventsEl.removeChild(eventsEl.lastChild!);
  }
}

// Update metrics
function updateMetrics(duration: number = 0, energy: number = 0) {
  if (duration > 0) {
    speechCount++;
    totalDuration += duration;
    speechCountEl.textContent = speechCount.toString();
    totalDurationEl.textContent = `${totalDuration.toFixed(1)}s`;
  }

  if (energy > 0) {
    energySum += energy;
    energyCount++;
    const avgEnergy = energySum / energyCount;
    avgEnergyEl.textContent = avgEnergy.toFixed(3);
  }
}

// Update health status
async function updateHealth() {
  if (!pipeline) {
    healthEl.textContent = '🔴';
    return;
  }

  const health = await pipeline.getHealth();
  healthEl.textContent = health.overall ? '🟢' : '🔴';
}

// Handle pipeline events
function handlePipelineEvent(event: PipelineEvent) {
  console.log('Pipeline event:', event);

  switch (event.type) {
    case 'initialized':
      updateStatus('Ready', 'idle');
      addEvent('READY', `Pipeline initialized with ${event.components.join(', ')}`);
      startBtn.disabled = false;
      updateHealth();
      break;

    case 'started':
      updateStatus('Listening...', 'listening');
      addEvent('STARTED', 'Pipeline started');
      startBtn.disabled = true;
      stopBtn.disabled = false;
      pauseBtn.disabled = false;
      pauseBtn.textContent = 'Pause';
      if (!animationId) {
        drawVisualization();
      }
      break;

    case 'stopped':
      updateStatus('Stopped', 'idle');
      addEvent('STOPPED', 'Pipeline stopped');
      startBtn.disabled = false;
      stopBtn.disabled = true;
      pauseBtn.disabled = true;
      if (animationId) {
        cancelAnimationFrame(animationId);
        animationId = null;
      }
      break;

    case 'paused':
      updateStatus('Paused', 'idle');
      addEvent('PAUSED', 'Pipeline paused');
      pauseBtn.textContent = 'Resume';
      break;

    case 'resumed':
      updateStatus('Listening...', 'listening');
      addEvent('RESUMED', 'Pipeline resumed');
      pauseBtn.textContent = 'Pause';
      break;

    case 'vad:speech_start':
      updateStatus('Speaking...', 'speaking');
      addEvent('SPEECH_START', 'Voice activity detected');
      break;

    case 'vad:speech_end':
      updateStatus('Processing...', 'speaking');
      const duration = event.duration;
      addEvent('SPEECH_END', `Duration: ${duration.toFixed(2)}s, Samples: ${event.audio.length}`);
      updateMetrics(duration);

      // Phase 2 features will be triggered by enhanced pipeline events
      // when transcription and LLM services are integrated
      break;

    case 'vad:audio_level':
      // Update visualization
      audioLevels.push(Math.min(1, event.level * 10));
      if (audioLevels.length > 50) {
        audioLevels.shift();
      }
      break;

    case 'processing:start':
      addEvent('PROCESSING', `Started ${event.stage} processing`);
      break;

    case 'processing:complete':
      addEvent('COMPLETE', `Completed ${event.stage} (${event.duration.toFixed(2)}ms)`);
      break;

    case 'error':
      updateStatus(`Error: ${event.error.message}`, 'error');
      addEvent('ERROR', event.error.message);
      break;
  }
}

// Handle Phase 2 transcription events
function handleTranscriptionEvent(event: any) {
  switch (event.type) {
    case 'transcription:partial':
      partialTranscriptionEl.textContent = event.text;
      break;

    case 'transcription:final':
      transcriptionEl.innerHTML = `<strong>Latest:</strong> ${event.text}`;
      partialTranscriptionEl.textContent = "";
      addEvent('TRANSCRIPTION', event.text);
      break;

    case 'transcription:error':
      addEvent('TRANSCRIPTION_ERROR', event.error.message);
      break;
  }
}

// Handle Phase 2 LLM events
function handleLLMEvent(event: any) {
  switch (event.type) {
    case 'llm:streaming':
      llmStreamingEl.textContent = "AI is thinking...";
      llmResponseEl.textContent = event.text;
      break;

    case 'llm:complete':
      llmStreamingEl.textContent = "";
      addEvent('LLM_RESPONSE', 'Response completed');
      setTimeout(() => {
        updateStatus('Listening...', 'listening');
      }, 1000);
      break;

    case 'llm:error':
      llmStreamingEl.textContent = "";
      addEvent('LLM_ERROR', event.error.message);
      break;
  }
}

// Initialize pipeline
initBtn.addEventListener('click', async () => {
  try {
    initBtn.disabled = true;
    updateStatus('Initializing...', 'initializing');
    addEvent('INIT', 'Starting initialization');

    // Create DI container
    container = new DIContainer();

    // Create pipeline with VAD enabled
    pipeline = new VoicePipelineManager({
      vad: {
        enabled: true,
        config: {
          positiveSpeechThreshold: 0.9,
          negativeSpeechThreshold: 0.75,
          minSpeechFrames: 5,
          frameSamples: 1536,
          submitUserSpeechOnPause: true
        }
      },
      performance: {
        useWebWorkers: false, // Disabled for demo simplicity
        bufferSize: 4096
      }
    }, container);

    // Set up event handlers
    pipeline.on('event', handlePipelineEvent);

    // Initialize the pipeline
    await pipeline.initialize();

    // Update metrics periodically
    setInterval(() => {
      updateHealth();
      if (pipeline) {
        const metrics = pipeline.getMetrics();
        console.log('Pipeline metrics:', metrics);
      }
    }, 5000);

  } catch (error) {
    console.error('Initialization error:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    updateStatus(`Error: ${errorMessage}`, 'error');
    addEvent('ERROR', errorMessage);
    initBtn.disabled = false;
  }
});

// Start listening
startBtn.addEventListener('click', async () => {
  try {
    if (!pipeline) return;
    await pipeline.start();
  } catch (error) {
    console.error('Start error:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    updateStatus(`Error: ${errorMessage}`, 'error');
    addEvent('ERROR', errorMessage);
  }
});

// Stop listening
stopBtn.addEventListener('click', () => {
  if (!pipeline) return;
  pipeline.stop();
});

// Pause/Resume
pauseBtn.addEventListener('click', () => {
  if (!pipeline) return;

  const state = pipeline.getState();
  if (state === PipelineState.RUNNING) {
    pipeline.pause();
  } else if (state === PipelineState.PAUSED) {
    pipeline.resume();
  }
});

// Clean up on page unload
window.addEventListener('beforeunload', () => {
  if (pipeline) {
    pipeline.destroy();
  }
  if (container) {
    container.clear();
  }
  if (animationId) {
    cancelAnimationFrame(animationId);
  }
});

// Log initial message
addEvent('WELCOME', 'Click Initialize to begin');
console.log('RunAnywhere Voice Pipeline Demo - Phase 1');
console.log('SDK Version: 0.1.0');
