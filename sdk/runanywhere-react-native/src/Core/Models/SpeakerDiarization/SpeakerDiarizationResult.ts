/**
 * SpeakerDiarizationResult.ts
 *
 * Result from Speaker Diarization processing
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift
 */

export interface SpeakerDiarizationResult {
  segments?: SpeakerSegment[] | null;
  speakers: SpeakerInfo[];
}

export interface SpeakerSegment {
  speakerId?: string | null;
  startTime?: number | null;
  endTime?: number | null;
  confidence?: number | null;
}

export interface SpeakerInfo {
  id?: string | null;
  name?: string | null;
  confidence?: number | null;
  embedding?: number[] | null;
}
