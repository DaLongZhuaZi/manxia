/**
 * 小说听书页面（播放器样式）
 */

import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelContentProcessor, ContentProcessConfig } from '../Framework/Novel/NovelContentProcessor';
import { LegadoBook, LegadoBookSourceType, LegadoChapter } from '../Framework/Novel/LegadoSourceTypes';
import {
  DEFAULT_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  ReadAloudSettings
} from '../Models/TextReaderModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudPlaybackState } from '../Framework/ReadAloud/ReadAloudTypes';
import { eventBus, GameEvent, IEventPayload, ReadAloudStatePayload } from '../Framework/EventBus';

const TAG = 'NovelReadAloudPage';

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

  private sourceManager = getNovelSourceManager();
  private cacheManager = getNovelChapterCacheManager();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  private sourceId: string = '';
  private bookUrl: string = '';
  private chapterUrl: string = '';
  private tocUrl: string = '';
  private bookId: string = '';
  private chapterList: LegadoChapter[] = [];
  private chapterContent: string = '';
  private readAloudSettings: ReadAloudSettings = DEFAULT_READ_ALOUD_SETTINGS;
  private autoSwitchingChapter: boolean = false;
  private lastReadAloudResumePersistTime: number = 0;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
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
    const engineRaw = this.settingsManager.getString(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENGINE,
      DEFAULT_READ_ALOUD_SETTINGS.engineType
    ) as ReadAloudEngineType;
    return {
      enabled: this.settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENABLED, DEFAULT_READ_ALOUD_SETTINGS.enabled),
      engineType: engineRaw,
      speed: this.settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_SPEED, DEFAULT_READ_ALOUD_SETTINGS.speed),
      pitch: this.settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_PITCH, DEFAULT_READ_ALOUD_SETTINGS.pitch),
      volume: this.settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOLUME, DEFAULT_READ_ALOUD_SETTINGS.volume),
      continueInBackground: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG,
        DEFAULT_READ_ALOUD_SETTINGS.continueInBackground
      ),
      autoPlayNextChapter: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER,
        DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter
      ),
      pauseOnManualPageTurn: this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN,
        DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn
      ),
      voiceLanguage: this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE,
        DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage ?? ''
      ),
      voicePerson: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON,
        DEFAULT_READ_ALOUD_SETTINGS.voicePerson ?? -1
      ),
      voiceOnline: this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE,
        DEFAULT_READ_ALOUD_SETTINGS.voiceOnline ?? -1
      )
    };
  }

  private getReadAloudResumeKey(): string {
    return `${NovelReadAloudPage.READ_ALOUD_RESUME_KEY_PREFIX}${this.bookId}_${this.currentChapterIndex}`;
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

  private async loadChapterList(): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      return;
    }
    const tocUrl = this.tocUrl || this.bookUrl;
    const book: LegadoBook = {
      id: '',
      type: LegadoBookSourceType.TEXT,
      bookUrl: this.bookUrl,
      tocUrl,
      name: this.bookName,
      author: this.author,
      origin: this.sourceId,
      originName: ''
    };
    try {
      const chapters = await this.sourceManager.getChapterList(this.sourceId, book);
      if (chapters && chapters.length > 0) {
        this.chapterList = chapters;
        this.totalChapters = chapters.length;
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
      this.loadErrorMessage = '当前章节无内容，请先缓存章节或检查书源';
      return false;
    }

    const processor = getNovelContentProcessor();
    const processConfig: ContentProcessConfig = {
      useReplace: true,
      chineseConvert: 0,
      reSegment: false,
      includeTitle: true,
      paragraphIndent: '',
      sourceId: this.sourceId
    };
    this.chapterContent = processor.processContent(rawContent, this.chapterTitle, this.bookName, processConfig).content;
    this.loadErrorMessage = '';
    this.restoreReadAloudResumeCharIndex();
    this.updateReadAloudContext();
    return true;
  }

  private async switchToChapter(targetIndex: number, forceStart: boolean): Promise<void> {
    if (targetIndex < 0 || (this.totalChapters > 0 && targetIndex >= this.totalChapters)) {
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

  private toggleReadAloud(): void {
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
      coverUrl: this.coverUrl
    };
    this.pathStack.pushPathByName('NovelReaderPage', params);
  }

  private getProgressPercent(): number {
    if (!this.chapterContent || this.chapterContent.length <= 0 || this.readAloudCurrentCharIndex < 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, (this.readAloudCurrentCharIndex / this.chapterContent.length) * 100));
  }

  private closePage(): void {
    this.persistReadAloudResumeCharIndex(true);
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

            Progress({ value: this.getProgressPercent(), total: 100, type: ProgressType.Linear })
              .width('88%')
              .height(6)

            Row({ space: 16 }) {
              Button('上一章')
                .enabled(this.currentChapterIndex > 0)
                .onClick(() => this.switchToChapter(this.currentChapterIndex - 1, false))
              Button(this.readAloudPlaying ? '暂停' : '播放')
                .onClick(() => this.toggleReadAloud())
              Button('下一章')
                .enabled(this.totalChapters <= 0 || this.currentChapterIndex < this.totalChapters - 1)
                .onClick(() => this.switchToChapter(this.currentChapterIndex + 1, false))
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
      this.bookId = `${param.sourceId}_${encodeURIComponent(param.bookUrl)}`;
      this.readAloudSettings = this.loadGlobalReadAloudSettings();
      this.readAloudController.updateSettings(this.readAloudSettings);

      this.loadChapterList().then(() => {
        return this.loadChapterContent(this.currentChapterIndex);
      }).then((_ok: boolean) => {
        this.readAloudPlaying = this.readAloudController.getSnapshot().playbackState === ReadAloudPlaybackState.PLAYING;
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
