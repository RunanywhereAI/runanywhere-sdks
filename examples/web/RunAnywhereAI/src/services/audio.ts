/**
 * Audio Service - Microphone capture + playback wrapper
 * Uses Web Audio API for mic capture and AudioContext for playback.
 *
 * MicCapture now collects raw PCM float32 data via AudioWorklet (or
 * ScriptProcessorNode fallback) alongside the level-monitoring AnalyserNode.
 */

export type AudioLevelCallback = (level: number) => void;

// ---------------------------------------------------------------------------
// Microphone Capture
// ---------------------------------------------------------------------------

class MicCaptureImpl {
  private stream: MediaStream | null = null;
  private audioContext: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private scriptNode: ScriptProcessorNode | null = null;
  private levelCallback: AudioLevelCallback | null = null;
  private _isCapturing = false;

  /** Collected PCM audio chunks (Float32, mono, 16 kHz). */
  private pcmChunks: Float32Array[] = [];

  /** Current audio level (0..1), updated per frame. */
  private _currentLevel = 0;

  get isCapturing(): boolean {
    return this._isCapturing;
  }

  /** Current normalized audio level (0..1). */
  get currentLevel(): number {
    return this._currentLevel;
  }

  /**
   * Start capturing microphone audio.
   * @param onLevel Optional callback invoked per animation frame with level 0..1.
   */
  async start(onLevel?: AudioLevelCallback): Promise<void> {
    if (this._isCapturing) return;

    this.levelCallback = onLevel ?? null;
    this.pcmChunks = [];
    this._currentLevel = 0;

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { sampleRate: 16000, channelCount: 1, echoCancellation: true },
    });

    this.audioContext = new AudioContext({ sampleRate: 16000 });
    const source = this.audioContext.createMediaStreamSource(this.stream);

    // --- AnalyserNode for level metering ---
    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 256;
    source.connect(this.analyser);

    // --- ScriptProcessorNode to capture raw PCM chunks ---
    // 4096 samples buffer ≈ 256 ms at 16 kHz
    this.scriptNode = this.audioContext.createScriptProcessor(4096, 1, 1);
    this.scriptNode.onaudioprocess = (e: AudioProcessingEvent) => {
      if (!this._isCapturing) return;
      const input = e.inputBuffer.getChannelData(0);
      // Copy the data (the buffer is reused by the browser)
      this.pcmChunks.push(new Float32Array(input));
    };
    source.connect(this.scriptNode);
    // ScriptProcessorNode must be connected to destination to fire events
    this.scriptNode.connect(this.audioContext.destination);

    this._isCapturing = true;

    // Level monitoring loop
    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    const tick = () => {
      if (!this._isCapturing || !this.analyser) return;
      this.analyser.getByteFrequencyData(dataArray);
      let sum = 0;
      for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
      const avg = sum / dataArray.length / 255;
      this._currentLevel = avg;
      this.levelCallback?.(avg);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  /** Stop capturing and release resources. */
  stop(): void {
    this._isCapturing = false;
    this._currentLevel = 0;
    this.levelCallback = null;

    if (this.scriptNode) {
      this.scriptNode.disconnect();
      this.scriptNode = null;
    }
    if (this.analyser) {
      this.analyser.disconnect();
      this.analyser = null;
    }
    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
  }

  /**
   * Get all collected PCM audio as a single Float32Array (mono, 16 kHz).
   * Does NOT clear the buffer -- call `clearBuffer()` separately.
   */
  getAudioBuffer(): Float32Array {
    if (this.pcmChunks.length === 0) return new Float32Array(0);
    const totalLength = this.pcmChunks.reduce((acc, c) => acc + c.length, 0);
    const merged = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of this.pcmChunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return merged;
  }

  /**
   * Drain: return the current buffer and clear it for the next segment.
   * Useful for live mode where we transcribe segments incrementally.
   */
  drainBuffer(): Float32Array {
    const buffer = this.getAudioBuffer();
    this.pcmChunks = [];
    return buffer;
  }

  /** Clear collected PCM data without stopping capture. */
  clearBuffer(): void {
    this.pcmChunks = [];
  }

  /** Duration of collected audio in seconds (at 16 kHz). */
  get bufferDurationSeconds(): number {
    const samples = this.pcmChunks.reduce((acc, c) => acc + c.length, 0);
    return samples / 16000;
  }
}

export const MicCapture = new MicCaptureImpl();

// ---------------------------------------------------------------------------
// Audio Playback
// ---------------------------------------------------------------------------

class AudioPlaybackImpl {
  private audioContext: AudioContext | null = null;
  private _isPlaying = false;

  get isPlaying(): boolean {
    return this._isPlaying;
  }

  async playSamples(pcmData: Float32Array, sampleRate = 16000): Promise<void> {
    if (!this.audioContext) {
      this.audioContext = new AudioContext({ sampleRate });
    }

    const buffer = this.audioContext.createBuffer(1, pcmData.length, sampleRate);
    buffer.copyToChannel(pcmData, 0);

    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audioContext.destination);

    return new Promise<void>((resolve) => {
      this._isPlaying = true;
      source.onended = () => {
        this._isPlaying = false;
        resolve();
      };
      source.start();
    });
  }

  stop(): void {
    this._isPlaying = false;
    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }
  }
}

export const AudioPlayback = new AudioPlaybackImpl();
