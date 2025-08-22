import {
  VoicePipelineManager,
  PipelineEvent,
  PipelineState,
  EnhancedVoicePipelineManager,
  EnhancedPipelineEvents
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

// Phase 3 TTS UI Elements
const ttsStatusEl = document.getElementById('ttsStatus') as HTMLDivElement;
const ttsTextEl = document.getElementById('ttsText') as HTMLDivElement;
const playTTSBtn = document.getElementById('playTTSBtn') as HTMLButtonElement;
const stopTTSBtn = document.getElementById('stopTTSBtn') as HTMLButtonElement;
const autoPlayTTSCheckbox = document.getElementById('autoPlayTTS') as HTMLInputElement;

// State
let pipeline: VoicePipelineManager | null = null;
let enhancedPipeline: EnhancedVoicePipelineManager | null = null;
let container: DIContainer | null = null;
let speechCount = 0;
let totalDuration = 0;
let energySum = 0;
let energyCount = 0;
let animationId: number | null = null;
let audioLevels: number[] = new Array(50).fill(0);
let currentTTSAudio: AudioBuffer | null = null;

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

// Update health status (moved to end of file)

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

// Handle Enhanced Pipeline Events (Phase 2 + 3)
function handleEnhancedPipelineEvent(eventName: keyof EnhancedPipelineEvents, ...args: any[]) {
  console.log('Enhanced pipeline event:', eventName, args);

  switch (eventName) {
    case 'started':
      updateStatus('Listening...', 'listening');
      addEvent('STARTED', 'Enhanced pipeline started');
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
      addEvent('STOPPED', 'Enhanced pipeline stopped');
      startBtn.disabled = false;
      stopBtn.disabled = true;
      pauseBtn.disabled = true;
      if (animationId) {
        cancelAnimationFrame(animationId);
        animationId = null;
      }
      break;

    case 'vadSpeechStart':
      updateStatus('Speaking...', 'speaking');
      addEvent('SPEECH_START', 'Voice activity detected');
      break;

    case 'vadSpeechEnd':
      updateStatus('Processing...', 'speaking');
      addEvent('SPEECH_END', 'Speech ended, processing...');
      break;

    case 'transcriptionStart':
      addEvent('TRANSCRIPTION_START', 'Starting transcription...');
      break;

    case 'partialTranscription':
      const partial = args[0];
      partialTranscriptionEl.textContent = partial.text;
      break;

    case 'transcription':
      const transcription = args[0];
      transcriptionEl.innerHTML = `<strong>Latest:</strong> ${transcription.text}`;
      partialTranscriptionEl.textContent = "";
      addEvent('TRANSCRIPTION', transcription.text);
      break;

    case 'llmStart':
      llmStreamingEl.textContent = "AI is thinking...";
      addEvent('LLM_START', 'AI processing started...');
      break;

    case 'llmToken':
      const tokenData = args[0];
      llmResponseEl.textContent = (llmResponseEl.textContent || '') + tokenData.token;
      break;

    case 'llmResponse':
      const llmResult = args[0];
      llmStreamingEl.textContent = "";
      addEvent('LLM_COMPLETE', `AI response completed (${llmResult.text.length} chars)`);
      break;

    case 'ttsStart':
      const ttsStart = args[0];
      ttsStatusEl.innerHTML = '<em style="color: #667eea;">🔊 Synthesizing speech...</em>';
      ttsTextEl.textContent = ttsStart.text;
      addEvent('TTS_START', `Synthesizing: "${ttsStart.text.substring(0, 50)}..."`);
      break;

    case 'ttsProgress':
      const progress = args[0];
      ttsStatusEl.innerHTML = `<em style="color: #667eea;">🔊 Synthesizing... ${Math.round(progress.progress * 100)}%</em>`;
      break;

    case 'ttsComplete':
      const ttsResult = args[0];
      ttsStatusEl.innerHTML = '<em style="color: #28a745;">✅ Speech synthesis complete</em>';
      currentTTSAudio = ttsResult.audioBuffer;
      playTTSBtn.disabled = false;
      addEvent('TTS_COMPLETE', `Synthesis completed (${ttsResult.duration.toFixed(2)}s)`);
      break;

    case 'ttsPlaybackStart':
      ttsStatusEl.innerHTML = '<em style="color: #667eea;">🔊 Playing audio...</em>';
      stopTTSBtn.disabled = false;
      playTTSBtn.disabled = true;
      addEvent('TTS_PLAYBACK_START', 'Audio playback started');
      break;

    case 'ttsPlaybackEnd':
      ttsStatusEl.innerHTML = '<em style="color: #666;">TTS ready...</em>';
      stopTTSBtn.disabled = true;
      playTTSBtn.disabled = false;
      addEvent('TTS_PLAYBACK_END', 'Audio playback finished');
      setTimeout(() => {
        updateStatus('Listening...', 'listening');
      }, 500);
      break;

    case 'pipelineComplete':
      const results = args[0];
      addEvent('PIPELINE_COMPLETE', `Full pipeline completed - Transcription: "${results.transcription.text.substring(0, 30)}..."`);
      setTimeout(() => {
        updateStatus('Listening...', 'listening');
      }, 1000);
      break;

    case 'error':
      const error = args[0];
      updateStatus(`Error: ${error.message}`, 'error');
      addEvent('ERROR', error.message);
      ttsStatusEl.innerHTML = `<em style="color: #dc3545;">❌ Error: ${error.message}</em>`;
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

    // Register VAD service in container (as expected by enhanced pipeline)
    const { VAD_SERVICE_TOKEN, WebVADService } = await import('@runanywhere/voice');
    container.register(VAD_SERVICE_TOKEN, () => new WebVADService({
      positiveSpeechThreshold: 0.9,
      negativeSpeechThreshold: 0.75,
      minSpeechFrames: 5,
      frameSamples: 1536,
      submitUserSpeechOnPause: true
    }));

    // Create enhanced pipeline with all Phase 2/3 features
    enhancedPipeline = new EnhancedVoicePipelineManager(container, {
      vadConfig: {
        positiveSpeechThreshold: 0.9,
        negativeSpeechThreshold: 0.75,
        minSpeechFrames: 5,
        frameSamples: 1536,
        submitUserSpeechOnPause: true
      },
      enableTranscription: true,
      enableLLM: true,
      enableTTS: true,
      autoPlayTTS: autoPlayTTSCheckbox.checked,
      whisperConfig: {
        model: 'whisper-tiny' // Use smaller model for demo
      },
      llmConfig: {
        baseUrl: 'http://localhost:11434/v1', // Default Ollama endpoint
        model: 'llama3.2:1b',
        maxTokens: 150,
        temperature: 0.7,
        systemPrompt: 'You are a helpful voice assistant. Keep responses concise and conversational.'
      },
      ttsConfig: {
        engine: 'web-speech',
        voice: 'default',
        rate: 1.0,
        pitch: 1.0
      }
    });

    // Set up enhanced event handlers
    enhancedPipeline.on('vadSpeechStart', () => handleEnhancedPipelineEvent('vadSpeechStart'));
    enhancedPipeline.on('vadSpeechEnd', (audio) => handleEnhancedPipelineEvent('vadSpeechEnd', audio));
    enhancedPipeline.on('transcriptionStart', () => handleEnhancedPipelineEvent('transcriptionStart'));
    enhancedPipeline.on('partialTranscription', (partial) => handleEnhancedPipelineEvent('partialTranscription', partial));
    enhancedPipeline.on('transcription', (result) => handleEnhancedPipelineEvent('transcription', result));
    enhancedPipeline.on('llmStart', (data) => handleEnhancedPipelineEvent('llmStart', data));
    enhancedPipeline.on('llmToken', (token) => handleEnhancedPipelineEvent('llmToken', token));
    enhancedPipeline.on('llmResponse', (response) => handleEnhancedPipelineEvent('llmResponse', response));
    enhancedPipeline.on('ttsStart', (data) => handleEnhancedPipelineEvent('ttsStart', data));
    enhancedPipeline.on('ttsProgress', (progress) => handleEnhancedPipelineEvent('ttsProgress', progress));
    enhancedPipeline.on('ttsComplete', (result) => handleEnhancedPipelineEvent('ttsComplete', result));
    enhancedPipeline.on('ttsPlaybackStart', () => handleEnhancedPipelineEvent('ttsPlaybackStart'));
    enhancedPipeline.on('ttsPlaybackEnd', () => handleEnhancedPipelineEvent('ttsPlaybackEnd'));
    enhancedPipeline.on('pipelineComplete', (results) => handleEnhancedPipelineEvent('pipelineComplete', results));
    enhancedPipeline.on('started', () => handleEnhancedPipelineEvent('started'));
    enhancedPipeline.on('stopped', () => handleEnhancedPipelineEvent('stopped'));
    enhancedPipeline.on('error', (error) => handleEnhancedPipelineEvent('error', error));

    // Initialize the enhanced pipeline
    await enhancedPipeline.initialize();

    // Update metrics periodically
    setInterval(() => {
      updateHealth();
      if (enhancedPipeline) {
        console.log('Enhanced pipeline health:', enhancedPipeline.isHealthy());
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
    if (!enhancedPipeline) return;
    await enhancedPipeline.start();
  } catch (error) {
    console.error('Start error:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    updateStatus(`Error: ${errorMessage}`, 'error');
    addEvent('ERROR', errorMessage);
  }
});

// Stop listening
stopBtn.addEventListener('click', () => {
  if (!enhancedPipeline) return;
  enhancedPipeline.stop();
});

// Pause/Resume
pauseBtn.addEventListener('click', async () => {
  if (!enhancedPipeline) return;

  try {
    if (pauseBtn.textContent === 'Pause') {
      await enhancedPipeline.pause();
    } else {
      await enhancedPipeline.resume();
    }
  } catch (error) {
    console.error('Pause/Resume error:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    addEvent('ERROR', errorMessage);
  }
});

// TTS Button Handlers
playTTSBtn.addEventListener('click', async () => {
  if (!currentTTSAudio || !enhancedPipeline) return;

  try {
    // Get TTS service from enhanced pipeline and play audio manually
    const audioContext = new AudioContext();
    const source = audioContext.createBufferSource();
    source.buffer = currentTTSAudio;
    source.connect(audioContext.destination);

    playTTSBtn.disabled = true;
    stopTTSBtn.disabled = false;
    handleEnhancedPipelineEvent('ttsPlaybackStart');

    source.onended = () => {
      handleEnhancedPipelineEvent('ttsPlaybackEnd');
    };

    source.start();
  } catch (error) {
    console.error('TTS playback error:', error);
    addEvent('TTS_ERROR', error instanceof Error ? error.message : String(error));
  }
});

stopTTSBtn.addEventListener('click', () => {
  // In a real implementation, we'd stop the audio source
  // For now, just update UI
  handleEnhancedPipelineEvent('ttsPlaybackEnd');
});

// Auto-play TTS checkbox handler
autoPlayTTSCheckbox.addEventListener('change', () => {
  if (enhancedPipeline) {
    // Update the enhanced pipeline config
    enhancedPipeline['config'].autoPlayTTS = autoPlayTTSCheckbox.checked;
    addEvent('CONFIG_UPDATE', `Auto-play TTS: ${autoPlayTTSCheckbox.checked ? 'enabled' : 'disabled'}`);
  }
});

// Update health status
async function updateHealth() {
  if (!enhancedPipeline) {
    healthEl.textContent = '🔴';
    return;
  }

  const health = enhancedPipeline.isHealthy();
  healthEl.textContent = health ? '🟢' : '🔴';
}

// Clean up on page unload
window.addEventListener('beforeunload', () => {
  if (enhancedPipeline) {
    enhancedPipeline.destroy();
  }
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
addEvent('WELCOME', 'Click Initialize to begin Phase 3 Demo');
console.log('RunAnywhere Voice Pipeline Demo - Phase 3');
console.log('SDK Version: 0.1.0');
console.log('Features: VAD + Whisper STT + LLM + TTS');
