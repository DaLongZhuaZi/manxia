import { media } from '@kit.MediaKit';
import { logger } from '../../Utils/Logger';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { LegadoBook, LegadoBookSourceType, LegadoChapter } from '../Novel/LegadoSourceTypes';
import { DEFAULT_READ_ALOUD_SETTINGS, ReadAloudSettings } from '../../Models/TextReaderModels';
import { loadGlobalReadAloudSettings } from './ReadAloudSettingsStore';
import { SettingsManager } from '../Managers/SettingsManager';

const TAG = 'NovelAudioSessionManager';
const CHAPTER_LIST_CACHE_MAX_AGE_HOURS: number = 48;
const WAIT_STATE_TIMEOUT_MS: number = 4600;
const PLAYER_OPERATION_TIMEOUT_MS: number = 5000;
const PLAYER_POST_PLAY_WAIT_TIMEOUT_MS: number = 2600;

type AudioJsonValue = string | number | boolean | Object | Array<Object> | null;
type AudioJsonRecord = Record<string, AudioJsonValue>;

export interface NovelAudioReadAloudLaunchParams {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  chapterUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  tocUrl?: string;
  author?: string;
  coverUrl?: string;
  autoStartReadAloud?: boolean;
}

export interface NovelAudioReadAloudSnapshot {
  hasSession: boolean;
  initialized: boolean;
  isLoading: boolean;
  loadErrorMessage: string;
  sourceId: string;
  bookUrl: string;
  bookId: string;
  bookName: string;
  author: string;
  coverUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  chapterUrl: string;
  audioSourceUrl: string;
  audioDurationMs: number;
  audioPositionMs: number;
  isPlaying: boolean;
  audioChapterCached: boolean;
  isCachingCurrentChapterAudio: boolean;
}

export type NovelAudioReadAloudStateListener = (snapshot: NovelAudioReadAloudSnapshot) => void;

export class NovelAudioReadAloudSessionManager {
  private static instance: NovelAudioReadAloudSessionManager | null = null;

  private readonly sourceManager = getNovelSourceManager();
  private readonly cacheManager = getNovelChapterCacheManager();
  private readonly settingsManager = SettingsManager.getInstance();

  private listeners: NovelAudioReadAloudStateListener[] = [];

  private readAloudSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  private sourceId: string = '';
  private bookUrl: string = '';
  private bookId: string = '';
  private bookName: string = '';
  private author: string = '';
  private coverUrl: string = '';
  private tocUrl: string = '';
  private chapterUrl: string = '';
  private chapterTitle: string = '';
  private chapterList: LegadoChapter[] = [];
  private totalChapters: number = 0;
  private currentChapterIndex: number = 0;
  private isLoading: boolean = false;
  private initialized: boolean = false;
  private loadErrorMessage: string = '';
  private audioSourceUrl: string = '';
  private audioDurationMs: number = 0;
  private audioPositionMs: number = 0;
  private isPlaying: boolean = false;
  private audioChapterCached: boolean = false;
  private isCachingCurrentChapterAudio: boolean = false;
  private sessionToken: number = 0;
  private autoSwitchingChapter: boolean = false;
  private chapterContent: string = '';

  private audioPlayer: media.AVPlayer | null = null;
  private audioStateChangeHandler: ((state: media.AVPlayerState, reason: media.StateChangeReason) => void) | null = null;
  private audioTimeUpdateHandler: ((timeMs: number) => void) | null = null;
  private audioErrorHandler: ((error: Object) => void) | null = null;

  private constructor() {
  }

  static getInstance(): NovelAudioReadAloudSessionManager {
    if (!NovelAudioReadAloudSessionManager.instance) {
      NovelAudioReadAloudSessionManager.instance = new NovelAudioReadAloudSessionManager();
    }
    return NovelAudioReadAloudSessionManager.instance;
  }

  subscribe(listener: NovelAudioReadAloudStateListener): void {
    if (this.listeners.includes(listener)) {
      return;
    }
    this.listeners.push(listener);
  }

  unsubscribe(listener: NovelAudioReadAloudStateListener): void {
    this.listeners = this.listeners.filter((item: NovelAudioReadAloudStateListener) => item !== listener);
  }

  hasActiveSession(): boolean {
    return this.sourceId.length > 0 && this.bookUrl.length > 0 && this.initialized;
  }

  isAudioSource(sourceId: string): boolean {
    if (!sourceId || sourceId.length <= 0) {
      return false;
    }
    const source = this.sourceManager.getSource(sourceId);
    return !!source && source.bookSourceType === LegadoBookSourceType.AUDIO;
  }

  getSnapshot(): NovelAudioReadAloudSnapshot {
    return {
      hasSession: this.sourceId.length > 0 && this.bookUrl.length > 0,
      initialized: this.initialized,
      isLoading: this.isLoading,
      loadErrorMessage: this.loadErrorMessage,
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookId: this.bookId,
      bookName: this.bookName,
      author: this.author,
      coverUrl: this.coverUrl,
      chapterTitle: this.chapterTitle,
      chapterIndex: this.currentChapterIndex,
      totalChapters: this.totalChapters,
      chapterUrl: this.chapterUrl,
      audioSourceUrl: this.audioSourceUrl,
      audioDurationMs: this.audioDurationMs,
      audioPositionMs: this.audioPositionMs,
      isPlaying: this.isPlaying,
      audioChapterCached: this.audioChapterCached,
      isCachingCurrentChapterAudio: this.isCachingCurrentChapterAudio
    };
  }

  async startSession(params: NovelAudioReadAloudLaunchParams): Promise<boolean> {
    if (!params.sourceId || !params.bookUrl) {
      this.loadErrorMessage = 'Missing required launch params for audio session';
      this.publishState();
      return false;
    }
    if (!this.isAudioSource(params.sourceId)) {
      logger.debug(TAG, `Skip audio session init for non-audio source: sourceId=${params.sourceId}`);
      return false;
    }

    this.readAloudSettings = loadGlobalReadAloudSettings(this.settingsManager);
    const sameSession = this.sourceId === params.sourceId && this.bookUrl === params.bookUrl;
    if (!sameSession) {
      this.releasePlayerOnly();
    }

    this.sourceId = params.sourceId;
    this.bookUrl = params.bookUrl;
    this.bookName = params.bookName || this.bookName;
    this.author = params.author || this.author;
    this.coverUrl = params.coverUrl || this.coverUrl;
    this.tocUrl = params.tocUrl || params.bookUrl;
    this.chapterUrl = params.chapterUrl || this.chapterUrl;
    this.chapterTitle = params.chapterTitle || this.chapterTitle;
    this.totalChapters = Math.max(0, params.totalChapters);
    this.currentChapterIndex = Math.max(0, params.chapterIndex);
    this.bookId = `${params.sourceId}_${encodeURIComponent(params.bookUrl)}`;
    this.loadErrorMessage = '';
    this.isLoading = true;
    this.initialized = false;
    this.sessionToken += 1;
    const token = this.sessionToken;
    logger.info(TAG, `Start audio novel session: sourceId=${params.sourceId}, chapterIndex=${this.currentChapterIndex}, autoStart=${params.autoStartReadAloud === true}`);
    this.publishState();

    try {
      await this.loadChapterList(token);
      if (!this.isTokenValid(token)) {
        return false;
      }
      const loaded = await this.loadChapterContent(this.currentChapterIndex, token);
      if (!this.isTokenValid(token)) {
        return false;
      }
      if (!loaded) {
        this.isLoading = false;
        this.initialized = false;
        this.publishState();
        return false;
      }
      this.isLoading = false;
      this.initialized = true;
      this.publishState();
      logger.info(TAG, `Audio session initialized: bookId=${this.bookId}, chapterIndex=${this.currentChapterIndex}, hasAudioUrl=${this.audioSourceUrl.length > 0}`);
      if (params.autoStartReadAloud === true) {
        const started = await this.play();
        logger.info(TAG, `Audio session auto-start result: success=${started}, chapterIndex=${this.currentChapterIndex}`);
      }
      return true;
    } catch (error) {
      this.isLoading = false;
      this.initialized = false;
      this.loadErrorMessage = `Audio session init failed: ${String(error)}`;
      logger.error(TAG, this.loadErrorMessage);
      this.publishState();
      return false;
    }
  }

  async togglePlayPause(): Promise<void> {
    if (this.isPlaying) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  async play(): Promise<boolean> {
    if (!this.audioSourceUrl || this.audioSourceUrl.length <= 0) {
      this.loadErrorMessage = 'Current chapter has no playable audio URL';
      this.publishState();
      return false;
    }
    try {
      const player = await this.ensureAudioPlayer();
      const state = player.state;
      logger.debug(TAG, `Audio play requested: state=${state}, chapterIndex=${this.currentChapterIndex}, url=${this.audioSourceUrl.substring(0, 120)}`);
      if (state === 'playing') {
        this.isPlaying = true;
        this.loadErrorMessage = '';
        this.publishState();
        return true;
      }

      if (state === 'paused' || state === 'prepared') {
        await this.invokeAudioPlayerOperationWithTimeout('play_resume', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else if (state === 'completed') {
        await this.seekAudioPlayer(player, 0);
        await this.invokeAudioPlayerOperationWithTimeout('play_from_completed', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else if (state === 'initialized' || state === 'stopped') {
        await this.invokeAudioPlayerOperationWithTimeout('play_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.prepare());
        await this.waitForAudioPlayerState(player, ['prepared', 'playing'], WAIT_STATE_TIMEOUT_MS, 'play_prepare');
        await this.invokeAudioPlayerOperationWithTimeout('play_after_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      } else {
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, true);
      }

      if (player.state !== 'playing') {
        try {
          await this.waitForAudioPlayerState(player, 'playing', PLAYER_POST_PLAY_WAIT_TIMEOUT_MS, 'play_wait_playing');
        } catch (error) {
          logger.warn(TAG, `Wait playing state timeout after play request: ${String(error)}`);
        }
      }

      if (player.state !== 'playing') {
        logger.warn(TAG, `Audio player still not in playing state, retry prepare+play once: state=${player.state}`);
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, true);
      }

      this.syncAudioProgressFromPlayer();
      this.isPlaying = player.state === 'playing';
      if (!this.isPlaying) {
        this.loadErrorMessage = 'Audio playback did not enter playing state, tap play to retry';
      } else {
        this.loadErrorMessage = '';
      }
      this.publishState();
      return this.isPlaying;
    } catch (error) {
      this.isPlaying = false;
      this.loadErrorMessage = `Play failed: ${String(error)}`;
      logger.warn(TAG, this.loadErrorMessage);
      this.publishState();
      return false;
    }
  }

  async pause(): Promise<void> {
    if (!this.audioPlayer) {
      this.isPlaying = false;
      this.publishState();
      return;
    }
    if (this.audioPlayer.state === 'playing') {
      await this.audioPlayer.pause();
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = false;
    this.publishState();
  }

  async stop(): Promise<void> {
    if (!this.audioPlayer) {
      this.isPlaying = false;
      this.audioPositionMs = 0;
      this.publishState();
      return;
    }
    try {
      if (this.audioPlayer.state === 'playing') {
        await this.audioPlayer.pause();
      }
      await this.seekAudioPlayer(this.audioPlayer, 0);
    } catch (_error) {
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = false;
    this.publishState();
  }

  async playNextChapter(forceStart: boolean = false): Promise<boolean> {
    if (this.totalChapters > 0 && this.currentChapterIndex >= this.totalChapters - 1) {
      return false;
    }
    return await this.switchToChapter(this.currentChapterIndex + 1, forceStart);
  }

  async playPreviousChapter(forceStart: boolean = false): Promise<boolean> {
    if (this.currentChapterIndex <= 0) {
      return false;
    }
    return await this.switchToChapter(this.currentChapterIndex - 1, forceStart);
  }
  async cacheCurrentChapterAudio(): Promise<boolean> {
    if (this.isCachingCurrentChapterAudio || !this.sourceId || !this.bookId) {
      return false;
    }
    this.isCachingCurrentChapterAudio = true;
    this.publishState();
    try {
      const alreadyCached = await this.cacheManager.isAudioChapterCached(this.bookId, this.currentChapterIndex);
      if (alreadyCached) {
        this.audioChapterCached = true;
        this.publishState();
        return true;
      }
      const chapter = this.getCurrentChapterForCache();
      const success = await this.cacheManager.cacheChapter(this.sourceId, this.bookId, chapter);
      if (!success) {
        return false;
      }
      this.audioChapterCached = true;
      const localAudioPath = await this.cacheManager.getChapterAudioCachePath(this.bookId, this.currentChapterIndex);
      if (localAudioPath && localAudioPath.length > 0 && !this.isPlaying) {
        this.audioSourceUrl = this.toAudioPlayerSourceUrl(localAudioPath);
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, false);
      }
      this.publishState();
      return true;
    } catch (error) {
      logger.error(TAG, `缓存章节音频失败: ${String(error)}`);
      return false;
    } finally {
      this.isCachingCurrentChapterAudio = false;
      this.publishState();
    }
  }

  releaseSession(reason: string = 'manual_release'): void {
    logger.info(TAG, `释放听书会话: reason=${reason}, bookId=${this.bookId}, chapterIndex=${this.currentChapterIndex}`);
    this.releasePlayerOnly();
    this.sourceId = '';
    this.bookUrl = '';
    this.bookId = '';
    this.bookName = '';
    this.author = '';
    this.coverUrl = '';
    this.tocUrl = '';
    this.chapterUrl = '';
    this.chapterTitle = '';
    this.chapterList = [];
    this.totalChapters = 0;
    this.currentChapterIndex = 0;
    this.isLoading = false;
    this.initialized = false;
    this.loadErrorMessage = '';
    this.audioSourceUrl = '';
    this.audioDurationMs = 0;
    this.audioPositionMs = 0;
    this.isPlaying = false;
    this.audioChapterCached = false;
    this.isCachingCurrentChapterAudio = false;
    this.sessionToken += 1;
    this.publishState();
  }

  private async switchToChapter(targetIndex: number, forceStart: boolean): Promise<boolean> {
    if (targetIndex < 0 || (this.totalChapters > 0 && targetIndex >= this.totalChapters)) {
      return false;
    }
    const shouldRestart = this.isPlaying || forceStart;
    if (this.isPlaying) {
      await this.pause();
    }
    this.isLoading = true;
    this.publishState();
    const token = this.sessionToken;
    const loaded = await this.loadChapterContent(targetIndex, token);
    this.isLoading = false;
    if (!loaded) {
      this.isPlaying = false;
      this.publishState();
      return false;
    }
    if (shouldRestart) {
      await this.play();
    } else {
      this.publishState();
    }
    return true;
  }

  private isTokenValid(token: number): boolean {
    return token === this.sessionToken;
  }

  private publishState(): void {
    const snapshot = this.getSnapshot();
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](snapshot);
      } catch (error) {
        logger.warn(TAG, `听书状态监听回调失败: ${String(error)}`);
      }
    }
  }

  private getCurrentChapterForCache(): LegadoChapter {
    if (this.chapterList.length > this.currentChapterIndex) {
      const chapter = this.chapterList[this.currentChapterIndex];
      return {
        id: chapter.id || '',
        bookUrl: chapter.bookUrl || this.bookUrl,
        url: chapter.url || this.chapterUrl,
        title: chapter.title || this.chapterTitle,
        index: this.currentChapterIndex
      };
    }
    return {
      id: '',
      bookUrl: this.bookUrl,
      url: this.chapterUrl,
      title: this.chapterTitle,
      index: this.currentChapterIndex
    };
  }

  private applyResolvedChapterList(chapters: LegadoChapter[]): void {
    if (chapters.length <= 0) {
      return;
    }
    this.chapterList = chapters;
    this.totalChapters = chapters.length;
    const safeIndex = Math.max(0, Math.min(this.currentChapterIndex, chapters.length - 1));
    this.currentChapterIndex = safeIndex;
    const currentChapter = chapters[safeIndex];
    if (currentChapter.title && currentChapter.title.length > 0) {
      this.chapterTitle = currentChapter.title;
    }
    if (currentChapter.url && currentChapter.url.length > 0) {
      this.chapterUrl = currentChapter.url;
    }
  }

  private async loadCachedChapterList(): Promise<LegadoChapter[] | null> {
    try {
      const cachedByCompositeBookId = await this.cacheManager.getCachedChapterList(this.bookId, CHAPTER_LIST_CACHE_MAX_AGE_HOURS);
      if (cachedByCompositeBookId && cachedByCompositeBookId.length > 0) {
        return cachedByCompositeBookId;
      }
      const cachedByBookUrl = await this.cacheManager.getCachedChapterList(this.bookUrl, CHAPTER_LIST_CACHE_MAX_AGE_HOURS);
      if (cachedByBookUrl && cachedByBookUrl.length > 0) {
        return cachedByBookUrl;
      }
      return null;
    } catch (error) {
      logger.warn(TAG, `读取章节列表缓存失败: ${String(error)}`);
      return null;
    }
  }

  private async loadChapterList(token: number): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      return;
    }
    let resolvedBook: LegadoBook | null = null;
    try {
      resolvedBook = await this.sourceManager.getBookInfo(this.sourceId, this.bookUrl);
    } catch (error) {
      logger.warn(TAG, `预加载书籍详情失败，继续按已有信息加载目录: ${String(error)}`);
    }
    if (!this.isTokenValid(token)) {
      return;
    }

    const resolvedTocUrl = resolvedBook && resolvedBook.tocUrl && resolvedBook.tocUrl.length > 0
      ? resolvedBook.tocUrl
      : (this.tocUrl || this.bookUrl);
    const resolvedBookName = resolvedBook && resolvedBook.name && resolvedBook.name.length > 0
      ? resolvedBook.name
      : this.bookName;
    const resolvedAuthor = resolvedBook && resolvedBook.author && resolvedBook.author.length > 0
      ? resolvedBook.author
      : this.author;
    const resolvedCoverUrl = resolvedBook && resolvedBook.coverUrl && resolvedBook.coverUrl.length > 0
      ? resolvedBook.coverUrl
      : this.coverUrl;

    if (resolvedBookName.length > 0) {
      this.bookName = resolvedBookName;
    }
    if (resolvedAuthor.length > 0) {
      this.author = resolvedAuthor;
    }
    if (resolvedCoverUrl.length > 0) {
      this.coverUrl = resolvedCoverUrl;
    }
    this.tocUrl = resolvedTocUrl;

    const cachedChapters = await this.loadCachedChapterList();
    if (!this.isTokenValid(token)) {
      return;
    }
    if (cachedChapters && cachedChapters.length > 0) {
      this.applyResolvedChapterList(cachedChapters);
      return;
    }

    const book: LegadoBook = {
      id: resolvedBook ? resolvedBook.id : '',
      type: LegadoBookSourceType.AUDIO,
      bookUrl: this.bookUrl,
      tocUrl: resolvedTocUrl,
      name: this.bookName,
      author: this.author,
      origin: this.sourceId,
      originName: resolvedBook ? resolvedBook.originName : ''
    };
    const chapters = await this.sourceManager.getChapterList(this.sourceId, book);
    if (!this.isTokenValid(token)) {
      return;
    }
    if (chapters && chapters.length > 0) {
      this.applyResolvedChapterList(chapters);
      try {
        await this.cacheManager.saveChapterList(this.bookId, chapters);
        if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
          await this.cacheManager.saveChapterList(this.bookUrl, chapters);
        }
      } catch (error) {
        logger.warn(TAG, `保存章节列表缓存失败: ${String(error)}`);
      }
    }
  }

  private async loadChapterContent(targetChapterIndex: number, token: number): Promise<boolean> {
    const safeIndex = Math.max(0, targetChapterIndex);
    let safeTitle = this.chapterTitle;
    let safeUrl = this.chapterUrl;
    if (this.chapterList.length > safeIndex) {
      safeTitle = this.chapterList[safeIndex].title;
      safeUrl = this.chapterList[safeIndex].url;
    }
    this.currentChapterIndex = safeIndex;
    this.chapterTitle = safeTitle;
    this.chapterUrl = safeUrl;
    this.loadErrorMessage = '';
    this.publishState();

    try {
      const cachedAudioPath = await this.cacheManager.getChapterAudioCachePath(this.bookId, safeIndex);
      if (cachedAudioPath && cachedAudioPath.length > 0) {
        if (!this.isTokenValid(token)) {
          return false;
        }
        this.chapterContent = '';
        this.audioSourceUrl = this.toAudioPlayerSourceUrl(cachedAudioPath);
        this.audioChapterCached = true;
        logger.info(TAG, `章节命中本地音频缓存: chapter=${safeIndex + 1}, path=${cachedAudioPath}`);
        this.syncAudioProgressFromPlayer();
        this.publishState();
        return true;
      }
    } catch (error) {
      logger.warn(TAG, `读取本地音频缓存失败，回退网络解析: chapter=${safeIndex}, error=${String(error)}`);
    }

    let rawContent = await this.cacheManager.getChapterCache(this.bookId, safeIndex);
    if ((!rawContent || rawContent.length <= 0) && this.sourceId.length > 0 && this.chapterUrl.length > 0) {
      const chapter: LegadoChapter = {
        id: '',
        bookUrl: this.bookUrl,
        url: this.chapterUrl,
        title: this.chapterTitle,
        index: safeIndex
      };
      rawContent = await this.sourceManager.getContent(this.sourceId, chapter);
    }
    if (!this.isTokenValid(token)) {
      return false;
    }
    if (!rawContent || rawContent.length <= 0) {
      this.chapterContent = '';
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.loadErrorMessage = '当前章节未获取到音频信息，请先缓存音频或检查书源';
      this.publishState();
      return false;
    }

    let resolvedAudioUrl = this.resolveAudioSourceUrl(rawContent, this.chapterUrl);
    if ((!resolvedAudioUrl || resolvedAudioUrl.length <= 0) && this.looksLikeAudioUrlCandidate(this.chapterUrl)) {
      resolvedAudioUrl = this.resolveAudioUrlCandidate(this.chapterUrl, this.chapterUrl);
    }
    if (!resolvedAudioUrl || resolvedAudioUrl.length <= 0) {
      this.chapterContent = rawContent;
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.loadErrorMessage = '当前章节未解析到可播放音频 URL';
      this.publishState();
      return false;
    }
    const sanitizedAudioUrl = this.sanitizeAudioUrl(resolvedAudioUrl);
    if (!sanitizedAudioUrl || sanitizedAudioUrl.length <= 0) {
      this.chapterContent = rawContent;
      this.audioSourceUrl = '';
      this.audioChapterCached = false;
      this.loadErrorMessage = '当前章节音频地址无效';
      this.publishState();
      return false;
    }
    this.chapterContent = rawContent;
    this.audioSourceUrl = this.toAudioPlayerSourceUrl(sanitizedAudioUrl);
    this.audioChapterCached = false;
    const audioUrlLength = this.audioSourceUrl.length;
    const audioUrlPrefix = this.audioSourceUrl.substring(0, 140);
    const audioUrlTail = audioUrlLength > 120 ? this.audioSourceUrl.substring(audioUrlLength - 120, audioUrlLength) : this.audioSourceUrl;
    logger.info(
      TAG,
      `章节音频解析完成: chapter=${safeIndex + 1}, urlLength=${audioUrlLength}, audioUrlPrefix=${audioUrlPrefix}, audioUrlTail=${audioUrlTail}`
    );
    this.syncAudioProgressFromPlayer();
    this.publishState();
    return true;
  }

  private looksLikeAudioUrlCandidate(raw: string): boolean {
    const value = raw.trim();
    if (value.length <= 0) {
      return false;
    }
    if (
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('file://') ||
      value.startsWith('data:audio/') ||
      value.startsWith('//')
    ) {
      return true;
    }
    if (value.indexOf('://') > 0 && value.indexOf(' ') < 0) {
      return true;
    }
    const lower = value.toLowerCase();
    return lower.indexOf('.mp3') >= 0 ||
      lower.indexOf('.m4a') >= 0 ||
      lower.indexOf('.aac') >= 0 ||
      lower.indexOf('.wav') >= 0 ||
      lower.indexOf('.ogg') >= 0 ||
      lower.indexOf('.flac') >= 0 ||
      lower.indexOf('.m3u8') >= 0;
  }
  private resolveAudioUrlCandidate(raw: string, baseUrl: string): string {
    const trimmed = raw.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('file://') ||
      trimmed.startsWith('data:audio/')
    ) {
      return trimmed;
    }
    const baseMatch = /^(https?:\/\/[^/]+)(\/.*)?$/i.exec(baseUrl);
    if (trimmed.startsWith('//')) {
      const protocol = baseMatch && baseMatch.length > 1 && baseMatch[1].startsWith('http://')
        ? 'http:'
        : 'https:';
      return `${protocol}${trimmed}`;
    }
    if (!baseMatch || baseMatch.length <= 1) {
      return trimmed;
    }
    const host = baseMatch[1];
    const path = baseMatch.length > 2 && baseMatch[2] ? baseMatch[2] : '/';
    if (trimmed.startsWith('/')) {
      return `${host}${trimmed}`;
    }
    const slashIndex = path.lastIndexOf('/');
    const parentPath = slashIndex >= 0 ? path.substring(0, slashIndex + 1) : '/';
    return `${host}${parentPath}${trimmed}`;
  }

  private collectAudioUrlHints(payload: AudioJsonValue, urlHints: string[]): void {
    if (payload === null || payload === undefined) {
      return;
    }
    if (Array.isArray(payload)) {
      const payloadArray = payload as Array<Object>;
      for (let index = 0; index < payloadArray.length; index++) {
        this.collectAudioUrlHints(payloadArray[index] as AudioJsonValue, urlHints);
      }
      return;
    }
    if (typeof payload === 'string') {
      const text = payload.trim();
      if (text.length > 0 && this.looksLikeAudioUrlCandidate(text)) {
        urlHints.push(text);
      }
      return;
    }
    if (typeof payload !== 'object') {
      return;
    }
    const record = payload as AudioJsonRecord;
    const keys = Object.keys(record);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = record[key];
      if (typeof value === 'string') {
        const text = value.trim();
        const lowerKey = key.toLowerCase();
        if (text.length > 0) {
          if (
            lowerKey === 'url' ||
            lowerKey === 'audio' ||
            lowerKey === 'audio_url' ||
            lowerKey === 'playurl' ||
            lowerKey === 'play_url' ||
            lowerKey.endsWith('_url') ||
            lowerKey.indexOf('audio') >= 0 ||
            lowerKey.indexOf('play') >= 0
          ) {
            urlHints.push(text);
          } else if (this.looksLikeAudioUrlCandidate(text)) {
            urlHints.push(text);
          }
        }
      }
      this.collectAudioUrlHints(value, urlHints);
    }
  }

  private tryExtractAudioUrlFromJson(rawContent: string, baseUrl: string): string {
    if (!rawContent || rawContent.trim().length <= 0) {
      return '';
    }
    try {
      const parsed = JSON.parse(rawContent) as AudioJsonValue;
      const urlHints: string[] = [];
      this.collectAudioUrlHints(parsed, urlHints);
      for (let index = 0; index < urlHints.length; index++) {
        const resolved = this.resolveAudioUrlCandidate(urlHints[index], baseUrl);
        if (resolved.length > 0) {
          return resolved;
        }
      }
    } catch (_error) {
      return '';
    }
    return '';
  }

  private resolveAudioSourceUrl(rawContent: string, baseUrl: string): string {
    const text = rawContent.trim();
    if (text.length <= 0) {
      return '';
    }
    const fromJson = this.tryExtractAudioUrlFromJson(text, baseUrl);
    if (fromJson.length > 0) {
      return fromJson;
    }
    const urlMatch = /(https?:\/\/[^\s"'<>]+)/i.exec(text);
    if (urlMatch && urlMatch.length > 1) {
      return this.resolveAudioUrlCandidate(urlMatch[1], baseUrl);
    }
    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (this.looksLikeAudioUrlCandidate(line)) {
        return this.resolveAudioUrlCandidate(line, baseUrl);
      }
    }
    if (this.looksLikeAudioUrlCandidate(text)) {
      return this.resolveAudioUrlCandidate(text, baseUrl);
    }
    return '';
  }

  private sanitizeAudioUrl(rawUrl: string): string {
    let sanitized = rawUrl.trim();
    if (sanitized.length <= 0) {
      return '';
    }
    if (sanitized.indexOf('\\/') >= 0) {
      sanitized = sanitized.replace(/\\\//g, '/');
    }
    if (sanitized.indexOf('\\u0026') >= 0 || sanitized.indexOf('\\U0026') >= 0) {
      sanitized = sanitized.replace(/\\u0026/gi, '&');
    }
    if (sanitized.startsWith('"') && sanitized.endsWith('"') && sanitized.length > 1) {
      sanitized = sanitized.substring(1, sanitized.length - 1).trim();
    }
    if (sanitized.startsWith('\'') && sanitized.endsWith('\'') && sanitized.length > 1) {
      sanitized = sanitized.substring(1, sanitized.length - 1).trim();
    }
    const headersTailPattern = /,\s*\{[\s\S]*"headers"[\s\S]*\}\s*$/i;
    if (headersTailPattern.test(sanitized)) {
      sanitized = sanitized.replace(headersTailPattern, '').trim();
    }
    if (sanitized.indexOf('{{') >= 0 || sanitized.indexOf('}}') >= 0) {
      return '';
    }
    if (sanitized.startsWith('//')) {
      sanitized = `https:${sanitized}`;
    }
    return sanitized;
  }

  private toAudioPlayerSourceUrl(urlOrPath: string): string {
    const normalized = urlOrPath.trim();
    if (normalized.length <= 0) {
      return '';
    }
    if (normalized.startsWith('/') && !normalized.startsWith('//')) {
      return `file://${normalized}`;
    }
    return normalized;
  }

  private syncAudioProgressFromPlayer(): void {
    if (!this.audioPlayer) {
      return;
    }
    const rawDuration = Math.floor(this.audioPlayer.duration);
    const rawPosition = Math.floor(this.audioPlayer.currentTime);
    const safeDuration = rawDuration > 0 ? rawDuration : 0;
    const safePosition = safeDuration > 0
      ? Math.max(0, Math.min(rawPosition, safeDuration))
      : Math.max(0, rawPosition);
    this.audioDurationMs = safeDuration;
    this.audioPositionMs = safePosition;
  }

  private async waitForAudioPlayerState(
    player: media.AVPlayer,
    expectedState: media.AVPlayerState | media.AVPlayerState[],
    timeoutMs: number,
    label: string
  ): Promise<media.AVPlayerState> {
    const expectedStates = Array.isArray(expectedState) ? expectedState : [expectedState];
    for (let index = 0; index < expectedStates.length; index++) {
      if (player.state === expectedStates[index]) {
        return player.state;
      }
    }
    return await new Promise<media.AVPlayerState>((resolve, reject) => {
      let settled = false;
      let timerId: number = -1;
      const finish = (state: media.AVPlayerState, error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        player.off('stateChange', onStateChange);
        if (error) {
          reject(error as Error);
          return;
        }
        resolve(state);
      };
      const onStateChange = (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
        for (let index = 0; index < expectedStates.length; index++) {
          if (state === expectedStates[index]) {
            finish(state);
            return;
          }
        }
        if (state === 'released' || state === 'error') {
          finish(state, `AUDIO_PLAYER_WAIT_STATE_FAILED: label=${label}, state=${state}`);
        }
      };
      player.on('stateChange', onStateChange);
      timerId = setTimeout(() => {
        finish(player.state, `AUDIO_PLAYER_WAIT_STATE_TIMEOUT: label=${label}, state=${player.state}`);
      }, timeoutMs);
    });
  }

  private async invokeAudioPlayerOperationWithTimeout(
    label: string,
    timeoutMs: number,
    operation: () => Promise<void>
  ): Promise<void> {
    return await new Promise<void>((resolve, reject) => {
      let settled = false;
      let timerId: number = -1;
      const finish = (error?: Object | string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        if (error) {
          reject(error as Error);
          return;
        }
        resolve();
      };
      timerId = setTimeout(() => {
        const currentState = this.audioPlayer ? this.audioPlayer.state : 'null';
        finish(`AUDIO_PLAYER_OPERATION_TIMEOUT: label=${label}, state=${currentState}`);
      }, timeoutMs);
      operation().then(() => {
        finish();
      }).catch((error: Object | string) => {
        finish(`AUDIO_PLAYER_OPERATION_FAILED: label=${label}, error=${String(error)}`);
      });
    });
  }

  private async seekAudioPlayer(player: media.AVPlayer, seekMs: number): Promise<void> {
    const safeSeekMs = Math.max(0, Math.floor(seekMs));
    return await new Promise<void>((resolve) => {
      let settled = false;
      let timeoutId: number = -1;
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        player.off('seekDone', onSeekDone);
        if (timeoutId >= 0) {
          clearTimeout(timeoutId);
          timeoutId = -1;
        }
        resolve();
      };
      const onSeekDone = (): void => {
        finish();
      };
      player.on('seekDone', onSeekDone);
      timeoutId = setTimeout(() => {
        finish();
      }, 1400);
      try {
        player.seek(safeSeekMs);
      } catch (_error) {
        finish();
      }
    });
  }

  private async ensureAudioPlayer(): Promise<media.AVPlayer> {
    if (this.audioPlayer && this.audioPlayer.state !== 'released') {
      return this.audioPlayer;
    }
    this.releasePlayerOnly();
    const player = await media.createAVPlayer();
    this.audioStateChangeHandler = (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
      logger.debug(TAG, `音频播放器状态变化: state=${state}, reason=${reason}, chapter=${this.currentChapterIndex}`);
      this.syncAudioProgressFromPlayer();
      this.isPlaying = state === 'playing';
      if (state === 'completed') {
        this.audioPositionMs = this.audioDurationMs;
        this.tryAutoPlayNextChapter();
      }
      this.publishState();
    };
    this.audioTimeUpdateHandler = (_timeMs: number): void => {
      this.syncAudioProgressFromPlayer();
      this.publishState();
    };
    this.audioErrorHandler = (error: Object): void => {
      this.isPlaying = false;
      this.syncAudioProgressFromPlayer();
      this.loadErrorMessage = `音频播放失败: ${String(error)}`;
      logger.warn(TAG, `音频播放器错误: ${String(error)}`);
      this.publishState();
    };
    player.on('stateChange', this.audioStateChangeHandler);
    player.on('timeUpdate', this.audioTimeUpdateHandler);
    player.on('error', this.audioErrorHandler);
    this.audioPlayer = player;
    return player;
  }
  private async resetAudioPlayerForNewSource(player: media.AVPlayer): Promise<void> {
    if (player.state === 'idle' || player.state === 'released') {
      return;
    }
    try {
      await player.reset();
    } catch (error) {
      logger.warn(TAG, `重置音频播放器失败，继续尝试: ${String(error)}`);
    }
    try {
      await this.waitForAudioPlayerState(player, 'idle', 1800, 'reset');
    } catch (_error) {
    }
  }

  private async prepareAudioPlayerWithUrl(url: string, autoStart: boolean): Promise<void> {
    const player = await this.ensureAudioPlayer();
    await this.resetAudioPlayerForNewSource(player);
    this.audioDurationMs = 0;
    this.audioPositionMs = 0;
    logger.debug(TAG, `Prepare audio player with url: autoStart=${autoStart}, url=${url.substring(0, 140)}`);
    player.url = url;
    let stateAfterUrl: media.AVPlayerState = player.state;
    try {
      stateAfterUrl = await this.waitForAudioPlayerState(player, ['initialized', 'prepared'], WAIT_STATE_TIMEOUT_MS, 'set_url');
    } catch (error) {
      logger.warn(TAG, `Wait state after set url timed out, try direct prepare: ${String(error)}`);
      stateAfterUrl = player.state;
    }
    if (stateAfterUrl !== 'prepared' && player.state !== 'prepared' && player.state !== 'playing') {
      await this.invokeAudioPlayerOperationWithTimeout('prepare_after_set_url', PLAYER_OPERATION_TIMEOUT_MS, () => player.prepare());
      await this.waitForAudioPlayerState(player, ['prepared', 'playing'], WAIT_STATE_TIMEOUT_MS, 'prepare');
    }
    if (autoStart && player.state !== 'playing') {
      await this.invokeAudioPlayerOperationWithTimeout('play_after_prepare', PLAYER_OPERATION_TIMEOUT_MS, () => player.play());
      try {
        await this.waitForAudioPlayerState(player, 'playing', PLAYER_POST_PLAY_WAIT_TIMEOUT_MS, 'play_after_prepare_wait');
      } catch (error) {
        logger.warn(TAG, `Wait playing state after prepare timed out: ${String(error)}`);
      }
    }
    this.syncAudioProgressFromPlayer();
    this.isPlaying = player.state === 'playing';
    logger.info(TAG, `Audio player ready: state=${player.state}, autoStart=${autoStart}, durationMs=${this.audioDurationMs}`);
    this.publishState();
  }

  private releasePlayerOnly(): void {
    if (!this.audioPlayer) {
      return;
    }
    if (this.audioStateChangeHandler) {
      this.audioPlayer.off('stateChange', this.audioStateChangeHandler);
    }
    if (this.audioTimeUpdateHandler) {
      this.audioPlayer.off('timeUpdate', this.audioTimeUpdateHandler);
    }
    if (this.audioErrorHandler) {
      this.audioPlayer.off('error', this.audioErrorHandler);
    }
    try {
      this.audioPlayer.release();
    } catch (error) {
      logger.warn(TAG, `释放音频播放器失败: ${String(error)}`);
    }
    this.audioStateChangeHandler = null;
    this.audioTimeUpdateHandler = null;
    this.audioErrorHandler = null;
    this.audioPlayer = null;
    this.isPlaying = false;
  }

  private tryAutoPlayNextChapter(): void {
    if (!this.readAloudSettings.autoPlayNextChapter || this.autoSwitchingChapter) {
      return;
    }
    if (this.totalChapters <= 0 || this.currentChapterIndex >= this.totalChapters - 1) {
      return;
    }
    this.autoSwitchingChapter = true;
    this.playNextChapter(true).then((): void => {
      this.autoSwitchingChapter = false;
    }).catch((_error: Object | string): void => {
      this.autoSwitchingChapter = false;
    });
  }
}

export function getNovelAudioReadAloudSessionManager(): NovelAudioReadAloudSessionManager {
  return NovelAudioReadAloudSessionManager.getInstance();
}

