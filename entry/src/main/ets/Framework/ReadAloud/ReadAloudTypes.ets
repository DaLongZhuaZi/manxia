import { ReadAloudSettings } from '../../Models/TextReaderModels';

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
}

export class ReadAloudProgressSnapshot {
  public currentCharIndex: number;
  public chunkStartCharIndex: number;
  public chunkEndCharIndex: number;

  constructor(currentCharIndex: number, chunkStartCharIndex: number, chunkEndCharIndex: number) {
    this.currentCharIndex = currentCharIndex;
    this.chunkStartCharIndex = chunkStartCharIndex;
    this.chunkEndCharIndex = chunkEndCharIndex;
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
}
