/**
 * Audio Service - Microphone capture + playback wrapper
 * Uses Web Audio API for mic capture and AudioContext for playback.
 */

export type AudioLevelCallback = (level: number) => void;

// ---------------------------------------------------------------------------
// Microphone Capture
// ---------------------------------------------------------------------------

class MicCaptureImpl {
  private stream: MediaStream | null = null;
  private audioContext: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private processor: ScriptProcessorNode | null = null;
  private levelCallback: AudioLevelCallback | null = null;
  private _isCapturing = false;

  get isCapturing(): boolean {
    return this._isCapturing;
  }

  async start(onLevel?: AudioLevelCallback): Promise<void> {
    if (this._isCapturing) return;

    this.levelCallback = onLevel ?? null;
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { sampleRate: 16000, channelCount: 1, echoCancellation: true },
    });

    this.audioContext = new AudioContext({ sampleRate: 16000 });
    const source = this.audioContext.createMediaStreamSource(this.stream);

    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 256;
    source.connect(this.analyser);

    // Audio level monitoring
    if (onLevel) {
      const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
      const tick = () => {
        if (!this._isCapturing || !this.analyser) return;
        this.analyser.getByteFrequencyData(dataArray);
        let sum = 0;
        for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
        const avg = sum / dataArray.length / 255;
        onLevel(avg);
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }

    this._isCapturing = true;
  }

  stop(): void {
    this._isCapturing = false;
    this.levelCallback = null;

    if (this.processor) {
      this.processor.disconnect();
      this.processor = null;
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
