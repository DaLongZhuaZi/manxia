/**
 * 小说听书页面（播放器样式）
 */

import { promptAction } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { logger } from '../Utils/Logger';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { LegadoBook, LegadoBookSourceType, LegadoChapter } from '../Framework/Novel/LegadoSourceTypes';
import {
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudSettings
} from '../Models/TextReaderModels';
import { SettingsManager } from '../Framework/Managers/SettingsManager';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState } from '../Framework/ReadAloud/ReadAloudTypes';
import { eventBus, GameEvent, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';
import { loadGlobalReadAloudSettings as loadStoredGlobalReadAloudSettings } from '../Framework/ReadAloud/ReadAloudSettingsStore';
import { processReadAloudNovelContentByBook } from '../Framework/ReadAloud/ReadAloudTextProcessing';

const TAG = 'NovelReadAloudPage';
type AudioJsonValue = string | number | boolean | Object | Array<Object> | null;
type AudioJsonRecord = Record<string, AudioJsonValue>;

@Component
export struct NovelReadAloudPage {
  private static readonly READ_ALOUD_RESUME_KEY_PREFIX: string = 'novel_read_aloud_resume_char_';

  @State pathStack: NavPathStack = new NavPathStack();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State isLoading: boolean = true;
  @State loadErrorMessage: string = '';
  @State bookName: string = '';
  @State author: string = '';
  @State coverUrl: string = '';
  @State chapterTitle: string = '';
  @State totalChapters: number = 0;
  @State currentChapterIndex: number = 0;
  @State readAloudPlaying: boolean = false;
  @State readAloudCurrentCharIndex: number = -1;
  @State audioDurationMs: number = 0;
  @State audioPositionMs: number = 0;
  @State audioChapterCached: boolean = false;
  @State isCachingCurrentChapterAudio: boolean = false;

  private sourceManager = getNovelSourceManager();
  private cacheManager = getNovelChapterCacheManager();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  private sourceId: string = '';
  private bookUrl: string = '';
  private chapterUrl: string = '';
  private tocUrl: string = '';
  private bookId: string = '';
  private sourceCoverComponentId: string = '';
  private chapterList: LegadoChapter[] = [];
  private chapterContent: string = '';
  private readAloudSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  private autoSwitchingChapter: boolean = false;
  private lastReadAloudResumePersistTime: number = 0;
  private currentSourceType: LegadoBookSourceType = LegadoBookSourceType.TEXT;
  private shouldAutoStartAudioOnReady: boolean = false;
  private audioSourceUrl: string = '';
  private audioPlayer: media.AVPlayer | null = null;
  private audioStateChangeHandler: ((state: media.AVPlayerState, reason: media.StateChangeReason) => void) | null = null;
  private audioTimeUpdateHandler: ((timeMs: number) => void) | null = null;
  private audioErrorHandler: ((error: Object) => void) | null = null;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    if (this.isAudioSourceMode()) {
      return;
    }
    const statePayload = payload as ReadAloudStatePayload;
    if (!this.bookId || statePayload.bookId !== this.bookId) {
      return;
    }
    this.readAloudPlaying = statePayload.playbackState === ReadAloudPlaybackState.PLAYING;
    this.applyReadAloudProgress(statePayload);
    if (statePayload.playbackState === ReadAloudPlaybackState.STOPPED) {
      this.persistReadAloudResumeCharIndex(true);
      this.tryAutoPlayNextChapter(statePayload);
    }
  };

  aboutToAppear(): void {
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
  }

  aboutToDisappear(): void {
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    if (this.isAudioSourceMode()) {
      this.releaseAudioPlayer();
      return;
    }
    this.persistReadAloudResumeCharIndex(true);
    const snapshot = this.readAloudController.getSnapshot();
    const isInBackground = this.isAppInBackground();
    const isOpeningReadAloudPlayer = this.isReadAloudPlayerOpeningSoon();
    const hasActivePlayback = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
      snapshot.playbackState === ReadAloudPlaybackState.PAUSED;
    const keepReadAloudAliveOnExit = hasActivePlayback &&
      (!isInBackground || this.readAloudSettings.continueInBackground) ||
      isOpeningReadAloudPlayer;
    if (keepReadAloudAliveOnExit) {
      this.readAloudPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
      logger.info(
        TAG,
        `离开听书页：保持听书会话，isInBackground=${isInBackground}, continueInBackground=${this.readAloudSettings.continueInBackground}, openingPlayer=${isOpeningReadAloudPlayer}`
      );
      return;
    }
    this.readAloudController.release();
    this.readAloudPlaying = false;
  }

  onPageHide(): void {
    if (this.isAudioSourceMode()) {
      if (this.isAppInBackground() && !this.readAloudSettings.continueInBackground) {
        void this.pauseAudioPlayback();
      }
      this.syncAudioProgressFromPlayer();
      return;
    }
    if (this.isAppInBackground()) {
      this.readAloudController.handlePageHide();
    }
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    this.persistReadAloudResumeCharIndex(true);
  }

  private isAppInBackground(): boolean {
    const backgroundFlag = AppStorage.get<boolean>('isInBackground');
    return backgroundFlag === true;
  }

  private isReadAloudPlayerOpeningSoon(): boolean {
    const openingAt = AppStorage.get<number>('ReadAloudPlayerOpeningAt') ?? 0;
    if (openingAt <= 0) {
      return false;
    }
    return Math.abs(Date.now() - openingAt) <= 2000;
  }

  private loadGlobalReadAloudSettings(): ReadAloudSettings {
    return loadStoredGlobalReadAloudSettings(this.settingsManager);
  }

  private getReadAloudResumeKey(): string {
    return `${NovelReadAloudPage.READ_ALOUD_RESUME_KEY_PREFIX}${this.bookId}_${this.currentChapterIndex}`;
  }

  private isAudioSourceMode(): boolean {
    return this.currentSourceType === LegadoBookSourceType.AUDIO;
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

  private updateReadAloudContext(): void {
    if (!this.chapterContent || this.chapterContent.trim().length === 0) {
      return;
    }
    const resumeCharIndex = this.readAloudCurrentCharIndex >= 0 ? this.readAloudCurrentCharIndex : 0;
    this.readAloudController.updateContext({
      bookId: this.bookId,
      bookTitle: this.bookName,
      chapterIndex: this.currentChapterIndex,
      chapterTitle: this.chapterTitle,
      coverUrl: this.coverUrl,
      content: this.chapterContent,
      pageIndex: 0,
      resumeCharIndex
    });
  }

  private restoreReadAloudResumeCharIndex(): void {
    const resumeCharIndex = Math.floor(this.settingsManager.getNumber(this.getReadAloudResumeKey(), 0));
    if (!this.chapterContent || this.chapterContent.length <= 0) {
      this.readAloudCurrentCharIndex = 0;
      return;
    }
    const maxCharIndex = Math.max(0, this.chapterContent.length - 1);
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(resumeCharIndex, maxCharIndex));
  }

  private persistReadAloudResumeCharIndex(force: boolean): void {
    if (!this.bookId || !this.chapterContent || this.chapterContent.length <= 0) {
      return;
    }
    const now = Date.now();
    if (!force && (now - this.lastReadAloudResumePersistTime) < 1200) {
      return;
    }
    this.lastReadAloudResumePersistTime = now;
    const maxCharIndex = Math.max(0, this.chapterContent.length - 1);
    const resumeCharIndex = Math.max(0, Math.min(this.readAloudCurrentCharIndex, maxCharIndex));
    this.settingsManager.setNumber(this.getReadAloudResumeKey(), resumeCharIndex).catch((error: Object | string) => {
      logger.warn(TAG, `保存听书恢复点失败: ${String(error)}`);
    });
  }

  private applyReadAloudProgress(payload: ReadAloudStatePayload): void {
    if (!this.chapterContent || this.chapterContent.length <= 0) {
      return;
    }
    const payloadChar = payload.currentCharIndex >= 0 ? payload.currentCharIndex : payload.chunkStartCharIndex;
    if (payloadChar < 0) {
      return;
    }
    const maxCharIndex = Math.max(0, this.chapterContent.length - 1);
    this.readAloudCurrentCharIndex = Math.max(0, Math.min(payloadChar, maxCharIndex));
    this.updateReadAloudContext();
    this.persistReadAloudResumeCharIndex(false);
  }

  private getCurrentSourceType(): LegadoBookSourceType {
    const source = this.sourceManager.getSource(this.sourceId);
    if (source) {
      return source.bookSourceType;
    }
    return LegadoBookSourceType.TEXT;
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
    const cacheMaxAgeHours = 48;
    try {
      const cachedByCompositeBookId = await this.cacheManager.getCachedChapterList(this.bookId, cacheMaxAgeHours);
      if (cachedByCompositeBookId && cachedByCompositeBookId.length > 0) {
        logger.info(TAG, `听书页命中章节列表缓存(组合ID): ${cachedByCompositeBookId.length}章`);
        return cachedByCompositeBookId;
      }
      const cachedByBookUrl = await this.cacheManager.getCachedChapterList(this.bookUrl, cacheMaxAgeHours);
      if (cachedByBookUrl && cachedByBookUrl.length > 0) {
        logger.info(TAG, `听书页命中章节列表缓存(bookUrl): ${cachedByBookUrl.length}章`);
        return cachedByBookUrl;
      }
      return null;
    } catch (error) {
      logger.warn(TAG, `听书页读取章节列表缓存失败: ${String(error)}`);
      return null;
    }
  }

  private async loadChapterList(): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      return;
    }
    const sourceType = this.getCurrentSourceType();
    let resolvedBook: LegadoBook | null = null;
    try {
      resolvedBook = await this.sourceManager.getBookInfo(this.sourceId, this.bookUrl);
    } catch (error) {
      logger.warn(TAG, `预加载书籍详情失败，继续按现有信息加载目录: ${String(error)}`);
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
    if (cachedChapters && cachedChapters.length > 0) {
      this.applyResolvedChapterList(cachedChapters);
      return;
    }

    const book: LegadoBook = {
      id: resolvedBook ? resolvedBook.id : '',
      type: resolvedBook ? resolvedBook.type : sourceType,
      bookUrl: this.bookUrl,
      tocUrl: resolvedTocUrl,
      name: this.bookName,
      author: this.author,
      origin: this.sourceId,
      originName: resolvedBook ? resolvedBook.originName : ''
    };
    try {
      const chapters = await this.sourceManager.getChapterList(this.sourceId, book);
      if (chapters && chapters.length > 0) {
        this.applyResolvedChapterList(chapters);
        try {
          await this.cacheManager.saveChapterList(this.bookId, chapters);
          if (this.bookUrl.length > 0 && this.bookUrl !== this.bookId) {
            await this.cacheManager.saveChapterList(this.bookUrl, chapters);
          }
        } catch (cacheError) {
          logger.warn(TAG, `听书页保存章节列表缓存失败: ${String(cacheError)}`);
        }
      }
    } catch (error) {
      logger.warn(TAG, `加载章节列表失败: ${String(error)}`);
    }
  }

  private async loadChapterContent(targetChapterIndex: number): Promise<boolean> {
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

    if (this.isAudioSourceMode()) {
      try {
        const cachedAudioPath = await this.cacheManager.getChapterAudioCachePath(this.bookId, safeIndex);
        if (cachedAudioPath && cachedAudioPath.length > 0) {
          this.chapterContent = '';
          this.audioSourceUrl = this.toAudioPlayerSourceUrl(cachedAudioPath);
          this.audioChapterCached = true;
          this.loadErrorMessage = '';
          this.readAloudCurrentCharIndex = -1;
          await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, false);
          this.syncAudioProgressFromPlayer();
          return true;
        }
      } catch (error) {
        logger.warn(TAG, `读取本地音频缓存失败，回退网络解析: chapter=${safeIndex}, error=${String(error)}`);
      }
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
    if (!rawContent || rawContent.length <= 0) {
      this.chapterContent = '';
      this.loadErrorMessage = this.isAudioSourceMode()
        ? '当前章节未获取到音频信息，请先缓存音频或检查书源'
        : '当前章节无内容，请先缓存章节或检查书源';
      return false;
    }

    if (this.isAudioSourceMode()) {
      let resolvedAudioUrl = this.resolveAudioSourceUrl(rawContent, this.chapterUrl);
      if ((!resolvedAudioUrl || resolvedAudioUrl.length <= 0) && this.looksLikeAudioUrlCandidate(this.chapterUrl)) {
        resolvedAudioUrl = this.resolveAudioUrlCandidate(this.chapterUrl, this.chapterUrl);
      }
      if (!resolvedAudioUrl || resolvedAudioUrl.length <= 0) {
        this.audioSourceUrl = '';
        this.loadErrorMessage = '当前章节未解析到可播放音频 URL';
        return false;
      }
      this.chapterContent = rawContent;
      this.audioSourceUrl = this.toAudioPlayerSourceUrl(resolvedAudioUrl);
      this.audioChapterCached = false;
      this.loadErrorMessage = '';
      this.readAloudCurrentCharIndex = -1;
      try {
        await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, false);
      } catch (error) {
        this.readAloudPlaying = false;
        this.loadErrorMessage = `音频加载失败：${String(error)}`;
        logger.warn(TAG, `音频章节加载失败: chapter=${safeIndex}, error=${String(error)}`);
        return false;
      }
      this.syncAudioProgressFromPlayer();
      return true;
    }

    this.chapterContent = await processReadAloudNovelContentByBook(
      rawContent,
      this.chapterTitle,
      this.bookName,
      this.sourceId,
      this.bookId
    );
    this.audioChapterCached = false;
    this.loadErrorMessage = '';
    this.restoreReadAloudResumeCharIndex();
    this.updateReadAloudContext();
    return true;
  }

  private async cacheCurrentAudioChapter(): Promise<void> {
    if (!this.isAudioSourceMode() || this.isCachingCurrentChapterAudio) {
      return;
    }
    if (this.sourceId.length <= 0) {
      promptAction.showToast({ message: '当前章节缺少书源信息，无法缓存', duration: 1500 });
      return;
    }
    this.isCachingCurrentChapterAudio = true;
    try {
      const alreadyCached = await this.cacheManager.isAudioChapterCached(this.bookId, this.currentChapterIndex);
      if (alreadyCached) {
        this.audioChapterCached = true;
        promptAction.showToast({ message: '当前章节已缓存音频', duration: 1200 });
        return;
      }

      const chapter = this.getCurrentChapterForCache();
      const success = await this.cacheManager.cacheChapter(this.sourceId, this.bookId, chapter);
      if (!success) {
        promptAction.showToast({ message: '缓存本章音频失败', duration: 1500 });
        return;
      }

      this.audioChapterCached = true;
      const localAudioPath = await this.cacheManager.getChapterAudioCachePath(this.bookId, this.currentChapterIndex);
      if (localAudioPath && localAudioPath.length > 0 && !this.readAloudPlaying) {
        this.audioSourceUrl = this.toAudioPlayerSourceUrl(localAudioPath);
        try {
          await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, false);
        } catch (error) {
          logger.warn(TAG, `切换到本地缓存音频失败: ${String(error)}`);
        }
      }
      promptAction.showToast({ message: '本章音频已缓存', duration: 1200 });
    } catch (error) {
      logger.error(TAG, `缓存当前音频章节失败: ${String(error)}`);
      promptAction.showToast({ message: '缓存本章音频失败', duration: 1500 });
    } finally {
      this.isCachingCurrentChapterAudio = false;
    }
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

  private async ensureAudioPlayer(): Promise<media.AVPlayer> {
    if (this.audioPlayer && this.audioPlayer.state !== 'released') {
      return this.audioPlayer;
    }
    this.releaseAudioPlayer();
    const player = await media.createAVPlayer();
    this.audioStateChangeHandler = (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
      logger.debug(TAG, `音频播放器状态变化: state=${state}, reason=${reason}, chapter=${this.currentChapterIndex}`);
      this.syncAudioProgressFromPlayer();
      this.readAloudPlaying = state === 'playing';
      if (state === 'completed') {
        this.audioPositionMs = this.audioDurationMs;
        this.tryAutoPlayNextChapterForAudio();
      }
    };
    this.audioTimeUpdateHandler = (_timeMs: number): void => {
      this.syncAudioProgressFromPlayer();
    };
    this.audioErrorHandler = (error: Object): void => {
      this.readAloudPlaying = false;
      this.syncAudioProgressFromPlayer();
      this.loadErrorMessage = `音频播放失败：${String(error)}`;
      logger.warn(TAG, `音频播放器错误: ${String(error)}`);
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
    player.url = url;
    const stateAfterUrl = await this.waitForAudioPlayerState(
      player,
      ['initialized', 'prepared'],
      4600,
      'set_url'
    );
    if (stateAfterUrl !== 'prepared' && player.state !== 'prepared') {
      await player.prepare();
      await this.waitForAudioPlayerState(player, ['prepared', 'playing'], 4600, 'prepare');
    }
    if (autoStart) {
      await player.play();
    }
    this.syncAudioProgressFromPlayer();
    this.readAloudPlaying = player.state === 'playing';
  }

  private async playAudioPlayback(): Promise<void> {
    if (!this.audioSourceUrl || this.audioSourceUrl.length <= 0) {
      promptAction.showToast({ message: '当前章节无可播放音频', duration: 1500 });
      return;
    }
    const player = await this.ensureAudioPlayer();
    const state = player.state;
    if (state === 'playing') {
      this.readAloudPlaying = true;
      return;
    }
    if (state === 'paused' || state === 'prepared') {
      await player.play();
      this.readAloudPlaying = true;
      return;
    }
    if (state === 'completed') {
      await this.seekAudioPlayer(player, 0);
      await player.play();
      this.readAloudPlaying = true;
      return;
    }
    if (state === 'initialized' || state === 'stopped') {
      await player.prepare();
      await this.waitForAudioPlayerState(player, ['prepared', 'playing'], 4200, 'play_prepare');
      await player.play();
      this.readAloudPlaying = true;
      return;
    }
    await this.prepareAudioPlayerWithUrl(this.audioSourceUrl, true);
  }

  private async pauseAudioPlayback(): Promise<void> {
    if (!this.audioPlayer) {
      this.readAloudPlaying = false;
      return;
    }
    if (this.audioPlayer.state === 'playing') {
      await this.audioPlayer.pause();
    }
    this.syncAudioProgressFromPlayer();
    this.readAloudPlaying = false;
  }

  private releaseAudioPlayer(): void {
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
    this.readAloudPlaying = false;
  }

  private async switchToChapter(targetIndex: number, forceStart: boolean): Promise<void> {
    if (targetIndex < 0 || (this.totalChapters > 0 && targetIndex >= this.totalChapters)) {
      return;
    }
    if (this.isAudioSourceMode()) {
      const shouldRestart = this.readAloudPlaying || forceStart;
      if (this.readAloudPlaying) {
        await this.pauseAudioPlayback();
      }
      this.isLoading = true;
      const ok = await this.loadChapterContent(targetIndex);
      this.isLoading = false;
      if (!ok) {
        this.readAloudPlaying = false;
        return;
      }
      if (shouldRestart) {
        try {
          await this.playAudioPlayback();
        } catch (error) {
          this.readAloudPlaying = false;
          this.loadErrorMessage = `音频播放失败：${String(error)}`;
        }
      }
      return;
    }
    const wasPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
    if (wasPlaying) {
      this.readAloudController.pause('chapter_switch');
    }
    this.isLoading = true;
    const ok = await this.loadChapterContent(targetIndex);
    this.isLoading = false;
    if (!ok) {
      this.readAloudPlaying = false;
      return;
    }
    if ((wasPlaying || forceStart) && this.readAloudSettings.enabled) {
      this.readAloudController.start('chapter_switch');
    }
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
  }

  private tryAutoPlayNextChapterForAudio(): void {
    if (!this.readAloudSettings.autoPlayNextChapter || this.autoSwitchingChapter) {
      return;
    }
    if (this.totalChapters <= 0 || this.currentChapterIndex >= this.totalChapters - 1) {
      return;
    }
    this.autoSwitchingChapter = true;
    this.switchToChapter(this.currentChapterIndex + 1, true).then(() => {
      this.autoSwitchingChapter = false;
    }).catch((_error: Object | string) => {
      this.autoSwitchingChapter = false;
    });
  }

  private tryAutoPlayNextChapter(payload: ReadAloudStatePayload): void {
    if (!this.readAloudSettings.autoPlayNextChapter || this.autoSwitchingChapter) {
      return;
    }
    if (!payload.reason || payload.reason.indexOf('backend_') !== 0) {
      return;
    }
    if (payload.reason.indexOf('speech_complete') < 0 && payload.reason.indexOf('queue_end') < 0) {
      return;
    }
    if (this.totalChapters <= 0 || this.currentChapterIndex >= this.totalChapters - 1) {
      return;
    }
    this.autoSwitchingChapter = true;
    this.switchToChapter(this.currentChapterIndex + 1, true).then(() => {
      this.autoSwitchingChapter = false;
    }).catch((_error: Object | string) => {
      this.autoSwitchingChapter = false;
    });
  }

  private formatDuration(durationMs: number): string {
    const safeMs = Math.max(0, Math.floor(durationMs));
    const totalSeconds = Math.floor(safeMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const minuteText = minutes.toString();
    const secondText = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minuteText}:${secondText}`;
  }

  private getAudioProgressText(): string {
    if (!this.isAudioSourceMode()) {
      return '';
    }
    if (this.audioDurationMs <= 0) {
      return this.readAloudPlaying ? '播放中' : '等待播放';
    }
    return `${this.formatDuration(this.audioPositionMs)} / ${this.formatDuration(this.audioDurationMs)}`;
  }

  private async toggleReadAloud(): Promise<void> {
    if (this.isAudioSourceMode()) {
      if (!this.audioSourceUrl || this.audioSourceUrl.length <= 0) {
        promptAction.showToast({ message: '当前章节无可播放音频', duration: 1500 });
        return;
      }
      if (this.readAloudPlaying) {
        await this.pauseAudioPlayback();
      } else {
        await this.playAudioPlayback();
      }
      this.syncAudioProgressFromPlayer();
      return;
    }
    if (!this.chapterContent || this.chapterContent.length <= 0) {
      promptAction.showToast({ message: '当前章节无可朗读内容', duration: 1500 });
      return;
    }
    if (!this.readAloudSettings.enabled) {
      this.readAloudSettings.enabled = true;
    }
    this.readAloudController.updateSettings(this.readAloudSettings);
    this.updateReadAloudContext();
    if (this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.pause('read_aloud_page_toggle');
      this.persistReadAloudResumeCharIndex(true);
    } else {
      this.readAloudController.start('read_aloud_page_toggle');
    }
    this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
  }

  private openNovelReaderPage(): void {
    const params: NovelReaderPageParams = {
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookName: this.bookName,
      chapterUrl: this.chapterUrl,
      chapterTitle: this.chapterTitle,
      chapterIndex: this.currentChapterIndex,
      totalChapters: this.totalChapters,
      tocUrl: this.tocUrl || this.bookUrl,
      author: this.author,
      coverUrl: this.coverUrl,
      coverComponentId: this.sourceCoverComponentId || undefined
    };
    this.pathStack.pushPathByName('NovelReaderPage', params);
  }

  private getProgressPercent(): number {
    if (this.isAudioSourceMode()) {
      if (this.audioDurationMs <= 0) {
        return 0;
      }
      return Math.max(0, Math.min(100, (this.audioPositionMs / this.audioDurationMs) * 100));
    }
    if (!this.chapterContent || this.chapterContent.length <= 0 || this.readAloudCurrentCharIndex < 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, (this.readAloudCurrentCharIndex / this.chapterContent.length) * 100));
  }

  private closePage(): void {
    if (!this.isAudioSourceMode()) {
      this.persistReadAloudResumeCharIndex(true);
    }
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column({ space: 16 }) {
        Row() {
          Button('返回')
            .height(36)
            .onClick(() => this.closePage())
          Blank()
          Button('打开阅读器')
            .height(36)
            .onClick(() => this.openNovelReaderPage())
        }
        .width('100%')
        .padding({ top: this.statusBarHeight + 8, left: 16, right: 16 })

        if (this.isLoading) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.accent_primary'))
        } else {
          Column({ space: 12 }) {
            if (this.coverUrl && this.coverUrl.length > 0) {
              Image(this.coverUrl)
                .width(180)
                .height(240)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
            }
            Text(this.bookName).fontSize(22).fontWeight(FontWeight.Medium).fontFamily(this.appFontFamily)
            if (this.author.length > 0) {
              Text(this.author).fontSize(14).fontColor($r('app.color.text_secondary')).fontFamily(this.appFontFamily)
            }
            Text(`第${this.currentChapterIndex + 1}章 ${this.chapterTitle}`)
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .fontFamily(this.appFontFamily)
              .textAlign(TextAlign.Center)
            if (this.isAudioSourceMode()) {
              Text(this.getAudioProgressText())
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .fontFamily(this.appFontFamily)

              Row({ space: 10 }) {
                Text(this.audioChapterCached ? '本章音频已缓存' : '本章音频未缓存')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .fontFamily(this.appFontFamily)
                Button(this.isCachingCurrentChapterAudio ? '缓存中...' : (this.audioChapterCached ? '已缓存' : '缓存本章'))
                  .height(30)
                  .enabled(!this.isCachingCurrentChapterAudio && !this.audioChapterCached)
                  .onClick(() => {
                    void this.cacheCurrentAudioChapter();
                  })
              }
            }

            Progress({ value: this.getProgressPercent(), total: 100, type: ProgressType.Linear })
              .width('88%')
              .height(6)

            Row({ space: 16 }) {
              Button('上一章')
                .enabled(this.currentChapterIndex > 0)
                .onClick(() => {
                  void this.switchToChapter(this.currentChapterIndex - 1, false);
                })
              Button(this.readAloudPlaying ? '暂停' : '播放')
                .onClick(() => {
                  void this.toggleReadAloud();
                })
              Button('下一章')
                .enabled(this.totalChapters <= 0 || this.currentChapterIndex < this.totalChapters - 1)
                .onClick(() => {
                  void this.switchToChapter(this.currentChapterIndex + 1, false);
                })
            }

            if (this.loadErrorMessage.length > 0) {
              Text(this.loadErrorMessage).fontSize(12).fontColor($r('app.color.text_secondary')).fontFamily(this.appFontFamily)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
        }
        Blank()
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.background_primary'))
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NovelReaderPageParams | null;
      if (!param) {
        this.isLoading = false;
        this.loadErrorMessage = '缺少听书参数';
        return;
      }

      this.sourceId = param.sourceId;
      this.bookUrl = param.bookUrl;
      this.bookName = param.bookName;
      this.chapterUrl = param.chapterUrl;
      this.chapterTitle = param.chapterTitle;
      this.currentChapterIndex = Math.max(0, param.chapterIndex);
      this.totalChapters = Math.max(0, param.totalChapters);
      this.tocUrl = param.tocUrl || param.bookUrl;
      this.author = param.author || '';
      this.coverUrl = param.coverUrl || '';
      this.sourceCoverComponentId = param.coverComponentId || '';
      this.bookId = `${param.sourceId}_${encodeURIComponent(param.bookUrl)}`;
      this.readAloudSettings = this.loadGlobalReadAloudSettings();
      this.currentSourceType = this.getCurrentSourceType();
      this.shouldAutoStartAudioOnReady = param.autoStartReadAloud === true;
      if (this.isAudioSourceMode()) {
        this.readAloudController.release();
      } else {
        this.readAloudController.updateSettings(this.readAloudSettings);
      }

      this.loadChapterList().then(() => {
        return this.loadChapterContent(this.currentChapterIndex);
      }).then((_ok: boolean) => {
        if (this.isAudioSourceMode()) {
          if (this.shouldAutoStartAudioOnReady) {
            this.shouldAutoStartAudioOnReady = false;
            void this.playAudioPlayback();
          }
          this.syncAudioProgressFromPlayer();
          this.readAloudPlaying = this.audioPlayer ? this.audioPlayer.state === 'playing' : false;
        } else {
          this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
        }
        this.isLoading = false;
      }).catch((error: Object | string) => {
        this.isLoading = false;
        this.loadErrorMessage = `听书页面初始化失败：${String(error)}`;
      });
    })
    .hideTitleBar(true)
    .onBackPressed(() => {
      this.closePage();
      return true;
    })
  }
}
