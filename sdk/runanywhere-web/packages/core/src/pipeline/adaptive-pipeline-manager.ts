import { EventEmitter } from 'eventemitter3'
import { Result } from '../types/result'
import { logger } from '../utils/logger'
import { ServiceRegistry } from '../registry'
import {
  AdapterType,
  VADAdapter,
  STTAdapter,
  LLMAdapter,
  TTSAdapter,
  TranscriptionResult,
  CompletionResult,
  Message
} from '../interfaces'

export interface AdapterConfig {
  adapter: string
  config?: any
  model?: string
  priority?: number
}

export interface PipelineConfig {
  vad?: AdapterConfig
  stt?: AdapterConfig | AdapterConfig[]
  llm?: AdapterConfig | AdapterConfig[]
  tts?: AdapterConfig | AdapterConfig[]
  enableAutoReconnect?: boolean
  maxReconnectAttempts?: number
}

export interface PipelineState {
  isRunning: boolean
  isProcessing: boolean
  vadActive: boolean
  sttActive: boolean
  llmActive: boolean
  ttsActive: boolean
  error?: Error
}

export interface PipelineEvents {
  'state_change': (state: PipelineState) => void
  'speech_start': () => void
  'speech_end': (audio: Float32Array) => void
  'transcription': (result: TranscriptionResult) => void
  'llm_response': (result: CompletionResult) => void
  'tts_audio': (audio: AudioBuffer) => void
  'playback_start': () => void
  'playback_end': () => void
  'error': (error: Error) => void
  'pipeline_complete': () => void
}

export class AdaptivePipelineManager extends EventEmitter<PipelineEvents> {
  private vadAdapter?: VADAdapter
  private sttAdapters: STTAdapter[] = []
  private llmAdapters: LLMAdapter[] = []
  private ttsAdapters: TTSAdapter[] = []

  private registry = ServiceRegistry.getInstance()
  private config: PipelineConfig
  private state: PipelineState = {
    isRunning: false,
    isProcessing: false,
    vadActive: false,
    sttActive: false,
    llmActive: false,
    ttsActive: false
  }

  private conversationHistory: Message[] = []
  private reconnectAttempts = 0

  constructor(config: PipelineConfig) {
    super()
    this.config = config
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      logger.info('Initializing adaptive pipeline', 'AdaptivePipeline')

      // Initialize VAD
      if (this.config.vad) {
        const result = await this.initializeVAD(this.config.vad)
        if (!result.success) {
          logger.warn(`VAD initialization failed: ${result.error.message}`, 'AdaptivePipeline')
        }
      }

      // Initialize STT adapters
      if (this.config.stt) {
        const sttConfigs = Array.isArray(this.config.stt) ? this.config.stt : [this.config.stt]
        for (const sttConfig of sttConfigs) {
          const result = await this.initializeSTT(sttConfig)
          if (!result.success) {
            logger.warn(`STT initialization failed: ${result.error.message}`, 'AdaptivePipeline')
          }
        }
      }

      // Initialize LLM adapters
      if (this.config.llm) {
        const llmConfigs = Array.isArray(this.config.llm) ? this.config.llm : [this.config.llm]
        for (const llmConfig of llmConfigs) {
          const result = await this.initializeLLM(llmConfig)
          if (!result.success) {
            logger.warn(`LLM initialization failed: ${result.error.message}`, 'AdaptivePipeline')
          }
        }
      }

      // Initialize TTS adapters
      if (this.config.tts) {
        const ttsConfigs = Array.isArray(this.config.tts) ? this.config.tts : [this.config.tts]
        for (const ttsConfig of ttsConfigs) {
          const result = await this.initializeTTS(ttsConfig)
          if (!result.success) {
            logger.warn(`TTS initialization failed: ${result.error.message}`, 'AdaptivePipeline')
          }
        }
      }

      this.updateState({ isRunning: true })
      logger.info('Adaptive pipeline initialized', 'AdaptivePipeline', {
        vad: !!this.vadAdapter,
        stt: this.sttAdapters.length,
        llm: this.llmAdapters.length,
        tts: this.ttsAdapters.length
      })

      return Result.ok(undefined)

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      logger.error(`Pipeline initialization failed: ${err.message}`, 'AdaptivePipeline')
      return Result.err(err)
    }
  }

  private async initializeVAD(config: AdapterConfig): Promise<Result<void, Error>> {
    const result = await this.registry.create<AdapterType.VAD>(
      AdapterType.VAD,
      config.adapter,
      config.config
    )

    if (result.success) {
      this.vadAdapter = result.value
      this.setupVADHandlers()
      this.updateState({ vadActive: true })
    }

    return result.success ? Result.ok(undefined) : Result.err(result.error)
  }

  private async initializeSTT(config: AdapterConfig): Promise<Result<void, Error>> {
    const result = await this.registry.create<AdapterType.STT>(
      AdapterType.STT,
      config.adapter,
      config.config
    )

    if (result.success) {
      const adapter = result.value

      // Load model if specified
      if (config.model) {
        const modelResult = await adapter.loadModel(config.model)
        if (!modelResult.success) {
          return modelResult
        }
      }

      this.sttAdapters.push(adapter)
      this.setupSTTHandlers(adapter)
      this.updateState({ sttActive: true })
    }

    return result.success ? Result.ok(undefined) : Result.err(result.error)
  }

  private async initializeLLM(config: AdapterConfig): Promise<Result<void, Error>> {
    const result = await this.registry.create<AdapterType.LLM>(
      AdapterType.LLM,
      config.adapter,
      config.config
    )

    if (result.success) {
      this.llmAdapters.push(result.value)
      this.setupLLMHandlers(result.value)
      this.updateState({ llmActive: true })
    }

    return result.success ? Result.ok(undefined) : Result.err(result.error)
  }

  private async initializeTTS(config: AdapterConfig): Promise<Result<void, Error>> {
    const result = await this.registry.create<AdapterType.TTS>(
      AdapterType.TTS,
      config.adapter,
      config.config
    )

    if (result.success) {
      const adapter = result.value

      // Load model if specified and adapter supports it
      if (config.model && typeof adapter.loadModel === 'function') {
        const modelResult = await adapter.loadModel(config.model)
        if (!modelResult.success) {
          return modelResult
        }
      }

      this.ttsAdapters.push(adapter)
      this.setupTTSHandlers(adapter)
      this.updateState({ ttsActive: true })
    }

    return result.success ? Result.ok(undefined) : Result.err(result.error)
  }

  private setupVADHandlers(): void {
    if (!this.vadAdapter) return

    this.vadAdapter.on('speech_start', () => {
      logger.debug('Speech started', 'AdaptivePipeline')
      this.emit('speech_start')
    })

    this.vadAdapter.on('speech_end', async (audio) => {
      logger.debug('Speech ended', 'AdaptivePipeline', {
        audioLength: audio.length
      })
      this.emit('speech_end', audio)
      await this.processSpeech(audio)
    })

    this.vadAdapter.on('error', (error) => {
      logger.error(`VAD error: ${error.message}`, 'AdaptivePipeline')
      this.handleError(error)
    })
  }

  private setupSTTHandlers(adapter: STTAdapter): void {
    adapter.on('partial_transcript', (text) => {
      logger.debug('Partial transcript', 'AdaptivePipeline', { text })
    })

    adapter.on('error', (error) => {
      logger.error(`STT error: ${error.message}`, 'AdaptivePipeline')
      this.handleError(error)
    })
  }

  private setupLLMHandlers(adapter: LLMAdapter): void {
    adapter.on('error', (error) => {
      logger.error(`LLM error: ${error.message}`, 'AdaptivePipeline')
      this.handleError(error)
    })
  }

  private setupTTSHandlers(adapter: TTSAdapter): void {
    adapter.on('playback_start', () => {
      this.emit('playback_start')
    })

    adapter.on('playback_end', () => {
      this.emit('playback_end')
    })

    adapter.on('error', (error) => {
      logger.error(`TTS error: ${error.message}`, 'AdaptivePipeline')
      this.handleError(error)
    })
  }

  private async processSpeech(audio: Float32Array): Promise<void> {
    if (!this.sttAdapters.length) {
      logger.warn('No STT adapters available', 'AdaptivePipeline')
      return
    }

    this.updateState({ isProcessing: true })

    try {
      // Try STT adapters in priority order
      let transcriptionResult: TranscriptionResult | null = null

      for (const adapter of this.sttAdapters) {
        const result = await adapter.transcribe(audio)
        if (result.success) {
          transcriptionResult = result.value
          break
        } else {
          logger.warn(`STT adapter ${adapter.id} failed: ${result.error.message}`, 'AdaptivePipeline')
        }
      }

      if (!transcriptionResult) {
        throw new Error('All STT adapters failed')
      }

      logger.info('Transcription completed', 'AdaptivePipeline', {
        text: transcriptionResult.text,
        confidence: transcriptionResult.confidence
      })

      this.emit('transcription', transcriptionResult)

      // Add to conversation history
      this.conversationHistory.push({
        role: 'user',
        content: transcriptionResult.text,
        timestamp: Date.now()
      })

      // Process with LLM
      await this.processWithLLM(transcriptionResult.text)

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      this.handleError(err)
    } finally {
      this.updateState({ isProcessing: false })
    }
  }

  private async processWithLLM(text: string): Promise<void> {
    if (!this.llmAdapters.length) {
      logger.warn('No LLM adapters available', 'AdaptivePipeline')
      return
    }

    try {
      // Try LLM adapters in priority order
      let completionResult: CompletionResult | null = null

      for (const adapter of this.llmAdapters) {
        // Add conversation history to adapter
        for (const message of this.conversationHistory.slice(-10)) {
          adapter.addMessage(message)
        }

        const result = await adapter.complete(text)
        if (result.success) {
          completionResult = result.value
          break
        } else {
          logger.warn(`LLM adapter ${adapter.id} failed: ${result.error.message}`, 'AdaptivePipeline')
        }
      }

      if (!completionResult) {
        throw new Error('All LLM adapters failed')
      }

      logger.info('LLM response received', 'AdaptivePipeline', {
        responseLength: completionResult.text.length,
        model: completionResult.model
      })

      this.emit('llm_response', completionResult)

      // Add to conversation history
      this.conversationHistory.push({
        role: 'assistant',
        content: completionResult.text,
        timestamp: Date.now()
      })

      // Synthesize speech
      await this.synthesizeSpeech(completionResult.text)

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      this.handleError(err)
    }
  }

  private async synthesizeSpeech(text: string): Promise<void> {
    if (!this.ttsAdapters.length) {
      logger.warn('No TTS adapters available', 'AdaptivePipeline')
      return
    }

    try {
      // Try TTS adapters in priority order
      let audioBuffer: AudioBuffer | null = null
      let successfulAdapter: TTSAdapter | null = null

      for (const adapter of this.ttsAdapters) {
        const result = await adapter.synthesize(text)
        if (result.success) {
          audioBuffer = result.value
          successfulAdapter = adapter
          break
        } else {
          logger.warn(`TTS adapter ${adapter.id} failed: ${result.error.message}`, 'AdaptivePipeline')
        }
      }

      if (!audioBuffer || !successfulAdapter) {
        throw new Error('All TTS adapters failed')
      }

      logger.info('TTS synthesis completed', 'AdaptivePipeline', {
        duration: audioBuffer.duration,
        adapter: successfulAdapter.id
      })

      this.emit('tts_audio', audioBuffer)

      // Play the audio
      await successfulAdapter.play(audioBuffer)

      this.emit('pipeline_complete')

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      this.handleError(err)
    }
  }

  async start(): Promise<Result<void, Error>> {
    if (!this.vadAdapter) {
      return Result.err(new Error('No VAD adapter configured'))
    }

    const result = await this.vadAdapter.start()
    if (result.success) {
      logger.info('Pipeline started', 'AdaptivePipeline')
    }

    return result
  }

  stop(): void {
    if (this.vadAdapter) {
      this.vadAdapter.stop()
    }

    // Stop any ongoing TTS playback
    for (const adapter of this.ttsAdapters) {
      adapter.stop()
    }

    this.updateState({ isRunning: false })
    logger.info('Pipeline stopped', 'AdaptivePipeline')
  }

  pause(): void {
    if (this.vadAdapter) {
      this.vadAdapter.pause()
    }
    logger.info('Pipeline paused', 'AdaptivePipeline')
  }

  resume(): void {
    if (this.vadAdapter) {
      this.vadAdapter.resume()
    }
    logger.info('Pipeline resumed', 'AdaptivePipeline')
  }

  private updateState(partial: Partial<PipelineState>): void {
    this.state = { ...this.state, ...partial }
    this.emit('state_change', this.state)
  }

  private handleError(error: Error): void {
    logger.error(`Pipeline error: ${error.message}`, 'AdaptivePipeline')
    this.updateState({ error })
    this.emit('error', error)

    // Attempt reconnection if enabled
    if (this.config.enableAutoReconnect &&
        this.reconnectAttempts < (this.config.maxReconnectAttempts || 3)) {
      this.reconnectAttempts++
      logger.info(`Attempting reconnection ${this.reconnectAttempts}`, 'AdaptivePipeline')

      setTimeout(() => {
        this.initialize().then(result => {
          if (result.success) {
            this.reconnectAttempts = 0
            logger.info('Reconnection successful', 'AdaptivePipeline')
          }
        })
      }, 2000 * this.reconnectAttempts)
    }
  }

  getState(): PipelineState {
    return { ...this.state }
  }

  getConversationHistory(): Message[] {
    return [...this.conversationHistory]
  }

  clearConversationHistory(): void {
    this.conversationHistory = []

    // Clear history in all LLM adapters
    for (const adapter of this.llmAdapters) {
      adapter.clearHistory()
    }

    logger.info('Conversation history cleared', 'AdaptivePipeline')
  }

  async destroy(): Promise<void> {
    this.stop()

    // Destroy all adapters
    if (this.vadAdapter) {
      this.vadAdapter.destroy()
    }

    for (const adapter of this.sttAdapters) {
      adapter.destroy()
    }

    for (const adapter of this.llmAdapters) {
      adapter.destroy()
    }

    for (const adapter of this.ttsAdapters) {
      adapter.destroy()
    }

    this.vadAdapter = undefined
    this.sttAdapters = []
    this.llmAdapters = []
    this.ttsAdapters = []

    this.removeAllListeners()

    logger.info('Pipeline destroyed', 'AdaptivePipeline')
  }
}
