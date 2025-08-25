// Whisper STT Worker
// Based on whisper-web implementation
import { pipeline } from '@huggingface/transformers';

// Pipeline factory pattern from whisper-web
class PipelineFactory {
    static task = 'automatic-speech-recognition' as const;
    static model: string | null = null;
    static dtype: any = null;
    static device: string = 'wasm';
    static instance: any = null;

    static async getInstance(progress_callback: any = null) {
        if (this.instance === null) {
            // Use dynamic dtype and device configuration like whisper-web
            // Store the promise immediately so multiple calls don't create multiple pipelines
            this.instance = pipeline(this.task, this.model!, {
                dtype: this.dtype,
                device: this.device,
                progress_callback,
            } as any);
        }
        // Always await the instance before returning
        return await this.instance;
    }

    static async invalidate() {
        if (this.instance !== null) {
            if (this.instance.dispose) {
                await this.instance.dispose();
            }
            this.instance = null;
        }
    }
}

// Message handler
self.addEventListener('message', async (event) => {
    const { type, data } = event.data;

    try {
        switch (type) {
            case 'load':
                // Determine device and dtype dynamically like whisper-web
                const device = data.device || 'wasm';
                const dtype = data.dtype || (device === 'webgpu' ? 'fp32' : 'q8');

                // Check if model or configuration needs to be changed
                if (PipelineFactory.model !== data.model_id ||
                    PipelineFactory.dtype !== dtype ||
                    PipelineFactory.device !== device) {

                    // Invalidate old model
                    await PipelineFactory.invalidate();

                    // Set new configuration
                    PipelineFactory.model = data.model_id;
                    PipelineFactory.dtype = dtype;
                    PipelineFactory.device = device;
                }

                // Send loading status
                self.postMessage({
                    status: 'loading',
                    message: `Loading model: ${data.model_id}`,
                    progress: 0
                });

                // Create progress callback
                const progressCallback = (progress: any) => {
                    const file = progress.file || progress.name || 'model';
                    const progressPercent = progress.progress || 0;

                    self.postMessage({
                        status: 'progress',
                        message: `Downloading ${file}...`,
                        progress: Math.round(progressPercent),
                        file: file,
                        loaded: progress.loaded || 0,
                        total: progress.total || 1
                    });
                };

                // Get or create pipeline instance
                const transcriber = await PipelineFactory.getInstance(progressCallback);

                if (transcriber) {
                    self.postMessage({
                        status: 'ready',
                        message: 'Model loaded successfully'
                    });
                } else {
                    throw new Error('Failed to load model');
                }
                break;

            case 'transcribe':
                // Get pipeline instance
                const pipelineInstance = await PipelineFactory.getInstance();

                if (!pipelineInstance) {
                    throw new Error('Model not loaded');
                }

                // Process audio
                let audio = data.audio;

                // Debug log the audio data
                console.log('[STT Worker] Transcribe request received:', {
                    hasAudio: !!audio,
                    audioType: audio ? audio.constructor.name : 'undefined',
                    audioLength: audio ? audio.length : 0,
                    audioSample: audio && audio.length > 0 ? Array.from(audio.slice(0, 5)) : undefined,
                    dataKeys: Object.keys(data || {})
                });

                // Ensure audio is Float32Array
                if (!(audio instanceof Float32Array)) {
                    if (Array.isArray(audio)) {
                        audio = new Float32Array(audio);
                    } else {
                        throw new Error(`Invalid audio data type: ${typeof audio}`);
                    }
                }

                // Run transcription with critical parameters from whisper-web
                const output = await pipelineInstance(audio, {
                    // CRITICAL: Add these for ONNX to work properly
                    top_k: 0,              // Forces greedy decoding
                    do_sample: false,      // Disables sampling

                    // Sliding window configuration
                    chunk_length_s: 30,
                    stride_length_s: 5,

                    // Language and task
                    language: data.language || null,
                    task: data.task || 'transcribe',

                    // Timestamps
                    return_timestamps: true,
                    force_full_sequences: false  // CRITICAL: Prevents ONNX errors
                });

                // Send result
                self.postMessage({
                    status: 'complete',
                    data: {
                        text: output.text || '',
                        chunks: output.chunks || [],
                        confidence: 1.0,
                        segments: output.chunks?.map((chunk: any) => ({
                            start: chunk.timestamp?.[0] || 0,
                            end: chunk.timestamp?.[1] || 0,
                            text: chunk.text || '',
                            confidence: 1.0
                        })) || [],
                        language: data.language || 'en'
                    }
                });
                break;

            case 'dispose':
                await PipelineFactory.invalidate();
                self.postMessage({
                    status: 'disposed',
                    message: 'Model disposed'
                });
                break;

            default:
                throw new Error(`Unknown message type: ${type}`);
        }
    } catch (error: any) {
        console.error('Worker error:', error);
        self.postMessage({
            status: 'error',
            message: error.message || 'An error occurred',
            error: error.toString()
        });
    }
});

// Signal that worker is ready
self.postMessage({ status: 'worker_ready' });
