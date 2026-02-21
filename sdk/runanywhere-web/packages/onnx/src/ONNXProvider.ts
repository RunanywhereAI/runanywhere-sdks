/**
 * ONNXProvider - Backend registration for @runanywhere/web-onnx
 *
 * Registers the sherpa-onnx backend with the RunAnywhere core SDK.
 * Provides STT (speech-to-text), TTS (text-to-speech), and VAD
 * (voice activity detection) capabilities.
 *
 * The provider also implements the model loader interfaces, handling
 * all sherpa-onnx FS operations (writing model files, extracting
 * archives) that were previously in ModelManager.
 */

import {
  SDKLogger,
  ModelManager,
  ExtensionPoint,
  BackendCapability,
  ExtensionRegistry,
  extractTarGz,
} from '@runanywhere/web';

import type { BackendExtension, ModelLoadContext } from '@runanywhere/web';

import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
import { STT } from './Extensions/RunAnywhere+STT';
import { STTModelType } from './Extensions/STTTypes';
import { TTS } from './Extensions/RunAnywhere+TTS';
import { VAD } from './Extensions/RunAnywhere+VAD';

const logger = new SDKLogger('ONNXProvider');

let _isRegistered = false;

// ---------------------------------------------------------------------------
// Model Loaders (implement the interfaces from @runanywhere/web)
// ---------------------------------------------------------------------------

/**
 * STT Model Loader — handles sherpa-onnx FS writes and archive extraction.
 * Moved from ModelManager's private loadSTTModel/loadSTTFromArchive/loadSTTFromIndividualFiles.
 */
const sttModelLoader = {
  async loadModelFromData(ctx: ModelLoadContext): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${ctx.model.id}`;

    if (ctx.model.isArchive) {
      await loadSTTFromArchive(ctx, sherpa, modelDir);
    } else {
      await loadSTTFromIndividualFiles(ctx, sherpa, modelDir);
    }
  },

  async unloadModel(): Promise<void> {
    await STT.unloadModel();
  },
};

async function loadSTTFromArchive(
  ctx: ModelLoadContext,
  sherpa: SherpaONNXBridge,
  modelDir: string,
): Promise<void> {
  logger.debug(`Extracting STT archive for ${ctx.model.id} (${ctx.data.length} bytes)...`);

  const entries = await extractTarGz(ctx.data);
  logger.debug(`Extracted ${entries.length} files from STT archive`);

  const prefix = findArchivePrefix(entries.map(e => e.path));

  let encoderPath: string | null = null;
  let decoderPath: string | null = null;
  let tokensPath: string | null = null;
  let joinerPath: string | null = null;
  let modelPath: string | null = null;

  for (const entry of entries) {
    const relativePath = prefix ? entry.path.slice(prefix.length) : entry.path;
    const fsPath = `${modelDir}/${relativePath}`;
    sherpa.writeFile(fsPath, entry.data);

    if (relativePath.includes('encoder') && relativePath.endsWith('.onnx')) {
      encoderPath = fsPath;
    } else if (relativePath.includes('decoder') && relativePath.endsWith('.onnx')) {
      decoderPath = fsPath;
    } else if (relativePath.includes('joiner') && relativePath.endsWith('.onnx')) {
      joinerPath = fsPath;
    } else if (relativePath.includes('tokens') && relativePath.endsWith('.txt')) {
      tokensPath = fsPath;
    } else if (relativePath.endsWith('.onnx') && !relativePath.includes('encoder') && !relativePath.includes('decoder') && !relativePath.includes('joiner')) {
      modelPath = fsPath;
    }
  }

  if (ctx.model.id.includes('whisper')) {
    if (!encoderPath || !decoderPath || !tokensPath) {
      throw new Error(`Whisper archive for '${ctx.model.id}' missing encoder/decoder/tokens`);
    }
    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Whisper,
      modelFiles: { encoder: encoderPath, decoder: decoderPath, tokens: tokensPath },
      sampleRate: 16000,
      language: 'en',
    });
  } else if (ctx.model.id.includes('paraformer')) {
    if (!modelPath || !tokensPath) {
      throw new Error(`Paraformer archive for '${ctx.model.id}' missing model/tokens`);
    }
    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Paraformer,
      modelFiles: { model: modelPath, tokens: tokensPath },
      sampleRate: 16000,
    });
  } else if (ctx.model.id.includes('zipformer')) {
    if (!encoderPath || !decoderPath || !joinerPath || !tokensPath) {
      throw new Error(`Zipformer archive for '${ctx.model.id}' missing encoder/decoder/joiner/tokens`);
    }
    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Zipformer,
      modelFiles: { encoder: encoderPath, decoder: decoderPath, joiner: joinerPath, tokens: tokensPath },
      sampleRate: 16000,
    });
  } else {
    throw new Error(`Unknown STT model type for model: ${ctx.model.id}`);
  }
}

async function loadSTTFromIndividualFiles(
  ctx: ModelLoadContext,
  sherpa: SherpaONNXBridge,
  modelDir: string,
): Promise<void> {
  const primaryFilename = ctx.model.url.split('/').pop()!;
  const primaryPath = `${modelDir}/${primaryFilename}`;

  logger.debug(`Writing STT primary file to ${primaryPath} (${ctx.data.length} bytes)`);
  sherpa.writeFile(primaryPath, ctx.data);

  const additionalPaths: Record<string, string> = {};
  if (ctx.model.additionalFiles) {
    for (const file of ctx.model.additionalFiles) {
      const fileKey = ctx.additionalFileKey(ctx.model.id, file.filename);
      let fileData = await ctx.loadFile(fileKey);
      if (!fileData) {
        logger.debug(`Additional file ${file.filename} not in storage, downloading...`);
        fileData = await ctx.downloadFile(file.url);
        await ctx.storeFile(fileKey, fileData);
      }
      const filePath = `${modelDir}/${file.filename}`;
      logger.debug(`Writing STT file to ${filePath} (${fileData.length} bytes)`);
      sherpa.writeFile(filePath, fileData);
      additionalPaths[file.filename] = filePath;
    }
  }

  if (ctx.model.id.includes('whisper')) {
    const encoderPath = primaryPath;
    const decoderFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
    const tokensFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;

    if (!decoderFilename || !tokensFilename) {
      throw new Error('Whisper model requires encoder, decoder, and tokens files');
    }

    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Whisper,
      modelFiles: {
        encoder: encoderPath,
        decoder: `${modelDir}/${decoderFilename}`,
        tokens: `${modelDir}/${tokensFilename}`,
      },
      sampleRate: 16000,
      language: 'en',
    });
  } else if (ctx.model.id.includes('paraformer')) {
    const tokensFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;
    if (!tokensFilename) {
      throw new Error('Paraformer model requires model and tokens files');
    }
    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Paraformer,
      modelFiles: { model: primaryPath, tokens: `${modelDir}/${tokensFilename}` },
      sampleRate: 16000,
    });
  } else if (ctx.model.id.includes('zipformer')) {
    const decoderFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('decoder'))?.filename;
    const joinerFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('joiner'))?.filename;
    const tokensFilename = ctx.model.additionalFiles?.find(f => f.filename.includes('tokens'))?.filename;
    if (!decoderFilename || !joinerFilename || !tokensFilename) {
      throw new Error('Zipformer model requires encoder, decoder, joiner, and tokens files');
    }
    await STT.loadModel({
      modelId: ctx.model.id,
      type: STTModelType.Zipformer,
      modelFiles: {
        encoder: primaryPath,
        decoder: `${modelDir}/${decoderFilename}`,
        joiner: `${modelDir}/${joinerFilename}`,
        tokens: `${modelDir}/${tokensFilename}`,
      },
      sampleRate: 16000,
    });
  } else {
    throw new Error(`Unknown STT model type for model: ${ctx.model.id}`);
  }
}

/**
 * TTS Model Loader — handles sherpa-onnx FS writes and archive extraction.
 */
const ttsModelLoader = {
  async loadModelFromData(ctx: ModelLoadContext): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${ctx.model.id}`;

    if (ctx.model.isArchive) {
      await loadTTSFromArchive(ctx, sherpa, modelDir);
    } else {
      await loadTTSFromIndividualFiles(ctx, sherpa, modelDir);
    }

    // Re-register as the active TTS provider (in case KittenTTS was previously active)
    ExtensionPoint.registerProvider('tts', TTS);
  },

  async unloadVoice(): Promise<void> {
    await TTS.unloadVoice();
  },
};

async function loadTTSFromArchive(
  ctx: ModelLoadContext,
  sherpa: SherpaONNXBridge,
  modelDir: string,
): Promise<void> {
  logger.debug(`Extracting TTS archive for ${ctx.model.id} (${ctx.data.length} bytes)...`);

  const entries = await extractTarGz(ctx.data);
  logger.debug(`Extracted ${entries.length} files from archive`);

  const prefix = findArchivePrefix(entries.map(e => e.path));

  let modelPath: string | null = null;
  let tokensPath: string | null = null;
  let dataDirPath: string | null = null;

  for (const entry of entries) {
    const relativePath = prefix ? entry.path.slice(prefix.length) : entry.path;
    const fsPath = `${modelDir}/${relativePath}`;
    sherpa.writeFile(fsPath, entry.data);

    if (relativePath.endsWith('.onnx') && !relativePath.includes('/')) {
      modelPath = fsPath;
    }
    if (relativePath === 'tokens.txt') {
      tokensPath = fsPath;
    }
    if (relativePath.startsWith('espeak-ng-data/') && !dataDirPath) {
      dataDirPath = `${modelDir}/espeak-ng-data`;
    }
  }

  if (!modelPath) throw new Error(`TTS archive for '${ctx.model.id}' does not contain an .onnx model file`);
  if (!tokensPath) throw new Error(`TTS archive for '${ctx.model.id}' does not contain tokens.txt`);

  await TTS.loadVoice({
    voiceId: ctx.model.id,
    modelPath,
    tokensPath,
    dataDir: dataDirPath ?? '',
    numThreads: 1,
  });
}

async function loadTTSFromIndividualFiles(
  ctx: ModelLoadContext,
  sherpa: SherpaONNXBridge,
  modelDir: string,
): Promise<void> {
  const primaryFilename = ctx.model.url.split('/').pop()!;
  const primaryPath = `${modelDir}/${primaryFilename}`;

  sherpa.writeFile(primaryPath, ctx.data);

  const additionalPaths: Record<string, string> = {};
  if (ctx.model.additionalFiles) {
    for (const file of ctx.model.additionalFiles) {
      const fileKey = ctx.additionalFileKey(ctx.model.id, file.filename);
      let fileData = await ctx.loadFile(fileKey);
      if (!fileData) {
        logger.debug(`Additional file ${file.filename} not in storage, downloading...`);
        fileData = await ctx.downloadFile(file.url);
        await ctx.storeFile(fileKey, fileData);
      }
      const filePath = `${modelDir}/${file.filename}`;
      sherpa.writeFile(filePath, fileData);
      additionalPaths[file.filename] = filePath;
    }
  }

  const tokensPath = additionalPaths['tokens.txt'];
  if (!tokensPath) throw new Error('TTS model requires tokens.txt file');

  await TTS.loadVoice({
    voiceId: ctx.model.id,
    modelPath: primaryPath,
    tokensPath,
    dataDir: '',
    numThreads: 1,
  });
}

/**
 * VAD Model Loader — writes Silero VAD model to sherpa-onnx FS.
 */
const vadModelLoader = {
  async loadModelFromData(ctx: ModelLoadContext): Promise<void> {
    const sherpa = SherpaONNXBridge.shared;
    await sherpa.ensureLoaded();

    const modelDir = `/models/${ctx.model.id}`;
    const filename = ctx.model.url?.split('/').pop() ?? 'silero_vad.onnx';
    const fsPath = `${modelDir}/${filename}`;

    logger.debug(`Writing VAD model to ${fsPath} (${ctx.data.length} bytes)`);
    sherpa.writeFile(fsPath, ctx.data);

    await VAD.loadModel({ modelPath: fsPath });
    logger.info(`VAD model loaded: ${ctx.model.id}`);
  },

  cleanup(): void {
    VAD.cleanup();
  },
};

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

function findArchivePrefix(paths: string[]): string {
  if (paths.length === 0) return '';
  const firstSlash = paths[0].indexOf('/');
  if (firstSlash === -1) return '';
  const candidate = paths[0].slice(0, firstSlash + 1);
  const allMatch = paths.every(p => p.startsWith(candidate));
  return allMatch ? candidate : '';
}

// ---------------------------------------------------------------------------
// Extension registration
// ---------------------------------------------------------------------------

const onnxExtension: BackendExtension = {
  id: 'onnx',
  capabilities: [
    BackendCapability.STT,
    BackendCapability.TTS,
    BackendCapability.VAD,
  ],
  cleanup() {
    STT.cleanup();
    TTS.cleanup();
    VAD.cleanup();
    ExtensionPoint.removeProvider('stt');
    ExtensionPoint.removeProvider('tts');
    try { SherpaONNXBridge.shared.shutdown(); } catch { /* ignore */ }
    _isRegistered = false;
    logger.info('ONNX backend cleaned up');
  },
};

export const ONNXProvider = {
  get isRegistered(): boolean {
    return _isRegistered;
  },

  /**
   * Register the sherpa-onnx backend with the RunAnywhere SDK.
   *
   * This:
   * 1. Registers STT/TTS/VAD model loaders with ModelManager
   * 2. Registers extension singletons with ExtensionRegistry
   * 3. Registers this backend with ExtensionPoint
   *
   * Note: SherpaONNXBridge is lazy-loaded on first model load,
   * not during registration.
   */
  async register(): Promise<void> {
    if (_isRegistered) {
      logger.debug('ONNX backend already registered, skipping');
      return;
    }

    // Register model loaders with ModelManager
    ModelManager.setSTTLoader(sttModelLoader);
    ModelManager.setTTSLoader(ttsModelLoader);
    ModelManager.setVADLoader(vadModelLoader);

    // Register extensions with lifecycle registry
    ExtensionRegistry.register(STT);
    ExtensionRegistry.register(TTS);
    ExtensionRegistry.register(VAD);

    // Register with ExtensionPoint
    ExtensionPoint.registerBackend(onnxExtension);

    // Register typed providers so VoicePipeline (in core) can access
    // STT/TTS via ExtensionPoint.getProvider() at runtime.
    ExtensionPoint.registerProvider('stt', STT);
    ExtensionPoint.registerProvider('tts', TTS);

    _isRegistered = true;
    logger.info('ONNX backend registered successfully');
  },

  unregister(): void {
    onnxExtension.cleanup();
  },
};
