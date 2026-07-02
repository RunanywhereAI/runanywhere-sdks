export type ModelState = 'available' | 'downloading' | 'downloaded' | 'loaded';

export type Modality = 'llm' | 'vlm' | 'stt' | 'tts' | 'vad' | 'embedding';

export interface ModelItem {
  id: string;
  name: string;
  meta: string;
  state: ModelState;
  progress?: number;
}
