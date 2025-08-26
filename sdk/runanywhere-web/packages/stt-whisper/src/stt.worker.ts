// Whisper STT Worker
// Based on whisper-web implementation
import { pipeline, env, WhisperTextStreamer } from '@huggingface/transformers';

// Disable browser cache to prevent corrupted model issues
env.useBrowserCache = false;

// Pipeline factory pattern from whisper-web
class PipelineFactory {
    static task = 'automatic-speech-recognition' as const;
    static model: string | null = null;
    static dtype: string = 'q8';  // Use simple string like whisper-web
    static device: string = 'wasm';  // Use WASM like whisper-web for stability
    static instance: any = null;

    static async getInstance(progress_callback: any = null) {
        if (this.instance === null) {
            console.log('[PipelineFactory] Creating new pipeline:', {
                task: this.task,
                model: this.model,
                dtype: this.dtype,
                device: this.device
            });

            // Use dynamic dtype and device configuration like whisper-web
            // Store the promise immediately so multiple calls don't create multiple pipelines
            this.instance = pipeline(this.task, this.model!, {
                dtype: this.dtype,
                device: this.device,
                progress_callback,
            } as any);
        }
        // CRITICAL: Return the instance/promise directly like whisper-web
        // Don't await here - let the caller await
        return this.instance;
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
                // Use WASM by default like whisper-web for better stability
                // Despite WebGPU being available, WASM is more reliable with ONNX
                const device = data.device || 'wasm';  // Default to WASM like whisper-web

                // FORCE simple string dtype like whisper-web
                // Ignore any object dtype passed from adapter
                const dtype = typeof data.dtype === 'string' ? data.dtype : 'q8';  // Force string!

                console.log('[STT Worker] Load configuration:', {
                    model_id: data.model_id,
                    dtype: dtype,
                    device: device,
                    dtype_type: typeof dtype,
                    previous_dtype: PipelineFactory.dtype,
                    previous_model: PipelineFactory.model
                });

                // Check if model or configuration needs to be changed
                // Compare dtype (now a simple string)
                const dtypeChanged = PipelineFactory.dtype !== dtype;
                const deviceChanged = PipelineFactory.device !== device;
                const modelChanged = PipelineFactory.model !== data.model_id;

                if (modelChanged || dtypeChanged || deviceChanged) {
                    console.log('[STT Worker] Configuration change detected:', {
                        modelChanged,
                        dtypeChanged,
                        deviceChanged,
                        oldDevice: PipelineFactory.device,
                        newDevice: device
                    });

                    // Invalidate old model
                    await PipelineFactory.invalidate();

                    // Set new configuration
                    PipelineFactory.model = data.model_id;
                    PipelineFactory.dtype = dtype;
                    PipelineFactory.device = device;

                    console.log('[STT Worker] Pipeline invalidated and configuration updated');
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
                console.log('[STT Worker] Getting pipeline instance...');
                const transcriber = await PipelineFactory.getInstance(progressCallback);

                console.log('[STT Worker] Pipeline instance ready:', {
                    hasTranscriber: !!transcriber,
                    transcriber_type: transcriber ? transcriber.constructor.name : 'null',
                    model_config: transcriber?.model?.config ? Object.keys(transcriber.model.config).slice(0, 5) : 'no config'
                });

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
                console.log('[STT Worker] Getting pipeline for transcription...');
                const pipelineInstance = await PipelineFactory.getInstance();

                console.log('[STT Worker] Pipeline ready:', {
                    hasPipeline: !!pipelineInstance,
                    dtype: PipelineFactory.dtype,
                    device: PipelineFactory.device,
                    model: PipelineFactory.model
                });

                if (!pipelineInstance) {
                    throw new Error('Model not loaded');
                }

                // Process audio
                let audio = data.audio;

                // DEEP DEBUG: Log everything about the audio and pipeline state
                console.log('[STT Worker] Transcribe request received:', {
                    hasAudio: !!audio,
                    audioType: audio ? audio.constructor.name : 'undefined',
                    audioLength: audio ? audio.length : 0,
                    audioSample: audio && audio.length > 0 ? Array.from(audio.slice(0, 5)) : undefined,
                    dataKeys: Object.keys(data || {}),
                    // Additional deep logging
                    audioMin: audio ? Math.min(...Array.from(audio.slice(0, 100)) as number[]) : undefined,
                    audioMax: audio ? Math.max(...Array.from(audio.slice(0, 100)) as number[]) : undefined,
                    audioMean: audio ? (Array.from(audio.slice(0, 100)) as number[]).reduce((a: number, b: number) => a + b, 0) / 100 : undefined,
                    pipelineConfig: {
                        model: PipelineFactory.model,
                        dtype: PipelineFactory.dtype,
                        device: PipelineFactory.device,
                        instanceType: pipelineInstance ? pipelineInstance.constructor.name : 'null'
                    }
                });

                // DEEP DEBUG: Check WebGPU availability
                if (typeof navigator !== 'undefined' && 'gpu' in navigator) {
                    console.log('[STT Worker] WebGPU availability check:', {
                        hasGPU: 'gpu' in navigator,
                        adapterRequest: 'Requesting adapter...'
                    });

                    try {
                        const adapter = await (navigator as any).gpu?.requestAdapter();
                        console.log('[STT Worker] WebGPU adapter info:', {
                            hasAdapter: !!adapter,
                            adapterInfo: adapter ? {
                                vendor: adapter.vendor || 'unknown',
                                architecture: adapter.architecture || 'unknown',
                                device: adapter.device || 'unknown',
                                description: adapter.description || 'unknown'
                            } : null
                        });
                    } catch (gpuError) {
                        console.warn('[STT Worker] WebGPU adapter request failed:', gpuError);
                    }
                } else {
                    console.warn('[STT Worker] WebGPU not available in this environment');
                }

                // Ensure audio is Float32Array
                if (!(audio instanceof Float32Array)) {
                    if (Array.isArray(audio)) {
                        audio = new Float32Array(audio);
                    } else {
                        throw new Error(`Invalid audio data type: ${typeof audio}`);
                    }
                }

                // CRITICAL: Create a new Float32Array to ensure proper memory alignment
                // VAD audio might have different memory layout than expected
                const alignedAudio = new Float32Array(audio.length);
                alignedAudio.set(audio);
                audio = alignedAudio;

                console.log('[STT Worker] Audio buffer reallocated for memory alignment');

                // Apply proper scaling if needed (for stereo to mono conversion)
                // This is handled by the adapter before sending to worker

                // Determine chunk size based on model type
                const isDistilModel = data.model_id?.includes('distil');
                // Use whisper-web's configuration
                const chunk_length_s = isDistilModel ? 20 : 30;  // Back to 30 like whisper-web
                const stride_length_s = isDistilModel ? 3 : 5;

                // Run transcription with critical parameters from whisper-web
                console.log('[STT Worker] Starting transcription with params:', {
                    chunk_length_s,
                    stride_length_s,
                    language: data.language || null,
                    task: data.task || 'transcribe',
                    // Deep debug the actual parameters
                    fullParams: {
                        top_k: 0,
                        do_sample: false,
                        chunk_length_s,
                        stride_length_s,
                        language: data.language || null,
                        task: data.task || 'transcribe',
                        return_timestamps: true,
                        force_full_sequences: false
                    }
                });

                // DEEP DEBUG: Wrap transcription in try-catch for detailed error
                let output: any;
                try {
                    console.log('[STT Worker] About to call pipeline with audio length:', audio.length);

                    // CRITICAL: Create WhisperTextStreamer like whisper-web does
                    const streamer = new WhisperTextStreamer(pipelineInstance.tokenizer, {
                        time_precision: 0.02, // 20ms precision
                        skip_prompt: true,
                        skip_special_tokens: true,
                        callback_function: null, // We'll collect the full result
                    });

                    output = await pipelineInstance(audio, {
                        // CRITICAL: Add these for ONNX to work properly
                        top_k: 0,              // Forces greedy decoding
                        do_sample: false,      // Disables sampling

                        // Sliding window configuration (model-specific)
                        chunk_length_s,
                        stride_length_s,

                        // Language and task
                        language: data.language || null,
                        task: data.task || 'transcribe',

                        // Timestamps
                        return_timestamps: true,
                        force_full_sequences: false,  // CRITICAL: Prevents ONNX errors

                        // CRITICAL: Add streamer like whisper-web
                        streamer
                    });

                    console.log('[STT Worker] Transcription successful, output:', {
                        hasText: !!output?.text,
                        textLength: output?.text?.length || 0,
                        hasChunks: !!output?.chunks,
                        chunksCount: output?.chunks?.length || 0
                    });
                } catch (transcribeError: any) {
                    console.error('[STT Worker] Transcription failed with detailed error:', {
                        message: transcribeError.message,
                        stack: transcribeError.stack,
                        name: transcribeError.name,
                        // Try to extract more info from the error
                        errorKeys: Object.keys(transcribeError || {}),
                        errorString: transcribeError.toString()
                    });

                    // Re-throw with more context
                    throw new Error(`Transcription failed: ${transcribeError.message || transcribeError}`);
                }

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
