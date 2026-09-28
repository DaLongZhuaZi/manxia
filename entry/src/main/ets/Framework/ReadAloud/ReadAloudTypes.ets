import { ReadAloudSettings } from 'manxia_core/src/main/ets/Models/TextReaderModels';

export enum ReadAloudPlaybackState {
  IDLE = 'IDLE',
  PLAYING = 'PLAYING',
  PAUSED = 'PAUSED',
  STOPPED = 'STOPPED'
}

export interface ReadAloudSessionContext {
  bookId: string;
  bookTitle?: string;
  chapterIndex: number;
  chapterTitle: string;
  coverUrl?: string;
  content: string;
  pageIndex: number;
  resumeCharIndex?: number;
  readerOpenFlowId?: string;
  sourceId?: string;
  totalChapters?: number;
}

export class ReadAloudProgressSnapshot {
  public currentCharIndex: number;
  public chunkStartCharIndex: number;
  public chunkEndCharIndex: number;
  public currentPositionMs: number;
  public totalDurationMs: number;

  constructor(
    currentCharIndex: number,
    chunkStartCharIndex: number,
    chunkEndCharIndex: number,
    currentPositionMs: number = -1,
    totalDurationMs: number = -1
  ) {
    this.currentCharIndex = currentCharIndex;
    this.chunkStartCharIndex = chunkStartCharIndex;
    this.chunkEndCharIndex = chunkEndCharIndex;
    this.currentPositionMs = currentPositionMs;
    this.totalDurationMs = totalDurationMs;
  }
}

export class ReadAloudVoiceOption {
  public id: string;
  public language: string;
  public person: number;
  public online: number;
  public status: string;
  public style: string;
  public gender: string;

  constructor(id: string, language: string, person: number, online: number, status: string, style: string = '', gender: string = '') {
    this.id = id;
    this.language = language;
    this.person = person;
    this.online = online;
    this.status = status;
    this.style = style;
    this.gender = gender;
  }
}

export interface ReadAloudStateSnapshot {
  playbackState: ReadAloudPlaybackState;
  settings: ReadAloudSettings;
  hasContext: boolean;
  chapterIndex: number;
  pageIndex: number;
  currentCharIndex: number;
  chunkStartCharIndex: number;
  chunkEndCharIndex: number;
  currentPositionMs: number;
  totalDurationMs: number;
}
