/**
 * Whisper STT Web Worker
 * Uses @huggingface/transformers with proper worker isolation to avoid bundle size issues
 */

import {
    AutoTokenizer,
    AutoProcessor,
    WhisperForConditionalGeneration,
    env,
} from '@huggingface/transformers';

// Configure environment for optimal loading
env.allowLocalModels = false;
env.backends.onnx.wasm.proxy = false;

/**
 * Singleton pipeline factory following transformers.js patterns
 */
class AutomaticSpeechRecognitionPipeline {
    static model_id = null;
    static tokenizer = null;
    static processor = null;
    static model = null;
    static isInitialized = false;

    static async getInstance(model_id = 'onnx-community/whisper-tiny', dtype = null, device = 'wasm', progress_callback = null) {
        // Check if we need to reload with different settings
        if (this.model_id !== model_id || !this.isInitialized) {
            this.model_id = model_id;

            // Dispose previous instances
            if (this.model) {
                try {
                    (await this.model).dispose();
                } catch (e) {
                    // Ignore disposal errors
                }
            }

            // Reset instances
            this.tokenizer = null;
            this.processor = null;
            this.model = null;
            this.isInitialized = false;
        }

        // Load tokenizer
        if (!this.tokenizer) {
            this.tokenizer = AutoTokenizer.from_pretrained(this.model_id, {
                progress_callback,
            });
        }

        // Load processor
        if (!this.processor) {
            this.processor = AutoProcessor.from_pretrained(this.model_id, {
                progress_callback,
            });
        }

        // Load model
        if (!this.model) {
            const modelDtype = dtype || {
                encoder_model: 'fp32',
                decoder_model_merged: 'q4',
            };

            this.model = WhisperForConditionalGeneration.from_pretrained(this.model_id, {
                dtype: modelDtype,
                device: device as any, // Type assertion for device compatibility
                progress_callback,
            });
        }

        const [tokenizer, processor, model] = await Promise.all([
            this.tokenizer,
            this.processor,
            this.model
        ]);

        this.isInitialized = true;
        return { tokenizer, processor, model };
    }
}

// Track processing state
let isProcessing = false;

/**
 * Load model and warm up
 */
async function loadModel({ model_id, dtype, device }) {
    try {
        self.postMessage({ status: 'loading', message: 'Initializing Whisper model...' });

        const { tokenizer, processor, model } = await AutomaticSpeechRecognitionPipeline.getInstance(
            model_id,
            dtype,
            device,
            (progress) => {
                self.postMessage({
                    status: 'progress',
                    ...progress
                });
            }
        );

        self.postMessage({ status: 'loading', message: 'Warming up model...' });

        // Warm up with dummy input (smaller for faster init)
        const dummyInput = new Float32Array(16000).fill(0); // 1 second of silence
        const inputs = await processor(dummyInput);
        await model.generate({
            ...inputs,
            max_new_tokens: 1,
        });

        self.postMessage({ status: 'ready', message: 'Whisper model ready!' });
    } catch (error) {
        console.error('Failed to load model:', error);
        self.postMessage({
            status: 'error',
            message: `Failed to load model: ${error.message}`,
            error: error
        });
    }
}

/**
 * Transcribe audio
 */
async function transcribeAudio({ audio, model_id, language, task }) {
    if (isProcessing) {
        self.postMessage({
            status: 'error',
            message: 'Already processing another request'
        });
        return;
    }

    try {
        isProcessing = true;
        self.postMessage({ status: 'transcribing', message: 'Processing audio...' });

        const { tokenizer, processor, model } = await AutomaticSpeechRecognitionPipeline.getInstance(model_id);

        // Process audio input
        const inputs = await processor(audio);

        // Generate transcription
        const generated_ids = await model.generate({
            ...inputs,
            max_new_tokens: 448, // Standard max for Whisper
            language: language,
            task: task || 'transcribe',
            return_timestamps: true,
        });

        // Decode the generated tokens
        const transcription = tokenizer.batch_decode(generated_ids, {
            skip_special_tokens: true
        });

        // Format result
        const result = {
            text: transcription[0] || '',
            language: language || 'en',
            confidence: 0.95, // Placeholder - Whisper doesn't provide confidence directly
            chunks: [], // Could be populated with timestamps if needed
        };

        self.postMessage({
            status: 'complete',
            data: result
        });

    } catch (error) {
        console.error('Transcription error:', error);
        self.postMessage({
            status: 'error',
            message: `Transcription failed: ${error.message}`,
            error: error
        });
    } finally {
        isProcessing = false;
    }
}

// Worker message handler
self.addEventListener('message', async (event) => {
    const { type, data } = event.data;

    switch (type) {
        case 'load':
            await loadModel(data || {
                model_id: 'onnx-community/whisper-tiny',
                dtype: {
                    encoder_model: 'fp32',
                    decoder_model_merged: 'q4',
                },
                device: 'wasm'
            });
            break;

        case 'transcribe':
            await transcribeAudio({
                audio: data.audio,
                model_id: data.model_id || 'onnx-community/whisper-tiny',
                language: data.language,
                task: data.task || 'transcribe'
            });
            break;

        case 'dispose':
            // Clean up resources
            if (AutomaticSpeechRecognitionPipeline.model) {
                try {
                    (await AutomaticSpeechRecognitionPipeline.model).dispose();
                } catch (e) {
                    // Ignore disposal errors
                }
            }
            AutomaticSpeechRecognitionPipeline.tokenizer = null;
            AutomaticSpeechRecognitionPipeline.processor = null;
            AutomaticSpeechRecognitionPipeline.model = null;
            AutomaticSpeechRecognitionPipeline.isInitialized = false;
            self.postMessage({ status: 'disposed' });
            break;

        default:
            self.postMessage({
                status: 'error',
                message: `Unknown message type: ${type}`
            });
            break;
    }
});

// Handle worker errors
self.addEventListener('error', (error) => {
    console.error('Worker error:', error);
    self.postMessage({
        status: 'error',
        message: `Worker error: ${error.message}`,
        error: error
    });
    isProcessing = false;
});

// Signal that worker is ready
self.postMessage({ status: 'worker_ready', message: 'Whisper worker initialized' });
