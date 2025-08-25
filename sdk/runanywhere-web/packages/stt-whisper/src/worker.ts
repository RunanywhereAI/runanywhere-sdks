/**
 * Whisper STT Web Worker
 * EXACT implementation based on whisper-web patterns
 */

import { pipeline } from "@huggingface/transformers";

// Define model factories - EXACT copy from whisper-web
class PipelineFactory {
    static task = null;
    static model = null;
    static dtype = null;
    static gpu = false;
    static instance = null;

    static async getInstance(progress_callback = null) {
        if (this.instance === null) {
            this.instance = pipeline(this.task, this.model, {
                dtype: this.dtype,
                device: this.gpu ? "webgpu" : "wasm",
                progress_callback,
            });
        }

        return this.instance;
    }
}

class AutomaticSpeechRecognitionPipelineFactory extends PipelineFactory {
    static task = "automatic-speech-recognition";
    static model = null;
    static dtype = null;
    static gpu = false;
}

// Transcription function - EXACT copy from whisper-web
const transcribe = async ({ audio, model, dtype, gpu, subtask, language }) => {
    const isDistilWhisper = model.startsWith("distil-whisper/");

    const p = AutomaticSpeechRecognitionPipelineFactory;
    if (p.model !== model || p.dtype !== dtype || p.gpu !== gpu) {
        // Invalidate model if different model, dtype, or gpu setting
        p.model = model;
        p.dtype = dtype;
        p.gpu = gpu;

        if (p.instance !== null) {
            (await p.getInstance()).dispose();
            p.instance = null;
        }
    }

    // Load transcriber model
    const transcriber = await p.getInstance((data) => {
        self.postMessage(data);
    });

    const chunk_length_s = isDistilWhisper ? 20 : 30;
    const stride_length_s = isDistilWhisper ? 3 : 5;

    // Actually run transcription - simplified version
    const output = await transcriber(audio, {
        // Greedy
        top_k: 0,
        do_sample: false,

        // Sliding window
        chunk_length_s,
        stride_length_s,

        // Language and task
        language,
        task: subtask,

        // Return timestamps
        return_timestamps: true,
        force_full_sequences: false,
    }).catch((error) => {
        console.error(error);
        self.postMessage({
            status: "error",
            data: error,
        });
        return null;
    });

    return output;
};

// Worker message handling - EXACT copy from whisper-web
self.addEventListener("message", async (event) => {
    const message = event.data;

    // Do transcription
    let transcript = await transcribe(message);
    if (transcript === null) return;

    // Send the result back to the main thread
    self.postMessage({
        status: "complete",
        data: transcript,
    });
});
