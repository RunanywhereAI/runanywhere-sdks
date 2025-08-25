// Inline worker code for Whisper STT
export const whisperWorkerCode = `
// Whisper STT Worker - Inline Implementation with Dynamic Import
let pipeline, env;
let transformersLoaded = false;

// Dynamically load transformers.js
async function loadTransformers() {
    if (!transformersLoaded) {
        const transformers = await import('https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2/+esm');
        pipeline = transformers.pipeline;
        env = transformers.env;

        // Configure transformers.js environment
        env.allowLocalModels = false;
        env.useBrowserCache = true;
        env.remoteURL = 'https://huggingface.co/';

        transformersLoaded = true;
    }
}

// Pipeline factory pattern from whisper-web
class PipelineFactory {
    static task = 'automatic-speech-recognition';
    static model = null;
    static quantized = true;
    static instance = null;

    static async getInstance(progress_callback = null) {
        await loadTransformers();

        if (this.instance === null) {
            this.instance = await pipeline(this.task, this.model, {
                quantized: this.quantized,
                progress_callback,
            });
        }
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
                // Check if model needs to be changed
                if (PipelineFactory.model !== data.model_id) {
                    // Invalidate old model
                    await PipelineFactory.invalidate();

                    // Set new model
                    PipelineFactory.model = data.model_id;
                    PipelineFactory.quantized = data.quantized !== false;
                }

                // Send loading status
                self.postMessage({
                    status: 'loading',
                    message: 'Loading model: ' + data.model_id,
                    progress: 0
                });

                // Create progress callback
                const progressCallback = (progress) => {
                    const file = progress.file || progress.name || 'model';
                    const progressPercent = progress.progress || 0;

                    self.postMessage({
                        status: 'progress',
                        message: 'Downloading ' + file + '...',
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
                const pipeline = await PipelineFactory.getInstance();

                if (!pipeline) {
                    throw new Error('Model not loaded');
                }

                // Process audio
                let audio = data.audio;

                // Ensure audio is Float32Array
                if (!(audio instanceof Float32Array)) {
                    audio = new Float32Array(audio);
                }

                // Run transcription
                const output = await pipeline(audio, {
                    language: data.language || null,
                    task: data.task || 'transcribe',
                    chunk_length_s: 30,
                    return_timestamps: true,
                });

                // Send result
                self.postMessage({
                    status: 'complete',
                    data: {
                        text: output.text || '',
                        chunks: output.chunks || [],
                        confidence: 1.0,
                        segments: output.chunks?.map(chunk => ({
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
                throw new Error('Unknown message type: ' + type);
        }
    } catch (error) {
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
`;
