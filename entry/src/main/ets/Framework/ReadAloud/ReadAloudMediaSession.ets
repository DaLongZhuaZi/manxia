import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import { logger } from '../../Utils/Logger';
import { getContext, isInitialized } from '../../GlobalContext';
import { ReadAloudSettings } from '../../Models/TextReaderModels';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from './ReadAloudTypes';

const TAG = 'ReadAloudMediaSession';
const BASE_CHARS_PER_SECOND: number = 11;
const PLAYBACK_SYNC_INTERVAL_MS: number = 350;

export interface ReadAloudMediaCommandListener {
  onPlay(): void;
  onPause(): void;
  onStop(): void;
  onPlayNext(): void;
  onPlayPrevious(): void;
  onSeek(positionMs: number): void;
}

export class ReadAloudMediaSession {
  private session: avSession.AVSession | null = null;
  private creatingPromise: Promise<void> | null = null;
  private commandListener: ReadAloudMediaCommandListener | null = null;
  private callbacksRegistered: boolean = false;
  private activated: boolean = false;
  private launchAbilityBound: boolean = false;
  private lastMetadataAssetId: string = '';
  private lastMetadataTitle: string = '';
  private lastMetadataSubtitle: string = '';
  private lastMetadataCoverUrl: string = '';
  private lastMetadataPixelMap: image.PixelMap | null = null;
  private lastMetadataDurationMs: number = -1;
  private lastPlaybackState: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_IDLE;
  private lastPlaybackPositionMs: number = -1;
  private lastPlaybackSyncTimeMs: number = 0;

  setCommandListener(listener: ReadAloudMediaCommandListener | null): void {
    this.commandListener = listener;
  }

  sync(snapshot: ReadAloudStateSnapshot, context: ReadAloudSessionContext | null, settings: ReadAloudSettings): void {
    this.ensureSessionReady().then((): void => {
      if (!this.session) {
        return;
      }
      this.syncMetadata(snapshot, context, settings).catch((error: Object | string): void => {
        logger.warn(TAG, `更新媒体元数据失败: ${this.formatError(error)}`);
      }).then((): Promise<void> => {
        return this.syncPlaybackState(snapshot, context, settings);
      }).catch((error: Object | string): void => {
        logger.warn(TAG, `更新媒体播放状态失败: ${this.formatError(error)}`);
      });
    }).catch((error: Object | string): void => {
      logger.warn(TAG, `同步媒体会话失败: ${this.formatError(error)}`);
    });
  }

  release(): void {
    this.releaseInternal().catch((error: Object | string): void => {
      logger.warn(TAG, `释放媒体会话失败: ${this.formatError(error)}`);
    });
  }

  private ensureSessionReady(): Promise<void> {
    if (this.session) {
      return Promise.resolve();
    }
    if (this.creatingPromise) {
      return this.creatingPromise;
    }
    this.creatingPromise = this.createSessionInternal().finally((): void => {
      this.creatingPromise = null;
    });
    return this.creatingPromise;
  }

  private async createSessionInternal(): Promise<void> {
    if (!isInitialized()) {
      logger.warn(TAG, '全局上下文尚未就绪，暂不创建媒体会话');
      return;
    }
    const abilityContext = getContext();
    this.session = await avSession.createAVSession(abilityContext, 'manxia_read_aloud', 'audio');
    this.registerCallbacks();
    await this.bindLaunchAbility(abilityContext);
    logger.info(TAG, '听书媒体会话创建成功');
  }

  private async bindLaunchAbility(abilityContext: common.UIAbilityContext): Promise<void> {
    if (!this.session || this.launchAbilityBound) {
      return;
    }
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: abilityContext.abilityInfo.bundleName,
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const launchWantAgent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await this.session.setLaunchAbility(launchWantAgent);
      this.launchAbilityBound = true;
    } catch (error) {
      logger.warn(TAG, `绑定媒体通知唤起能力失败: ${this.formatError(error)}`);
    }
  }

  private registerCallbacks(): void {
    if (!this.session || this.callbacksRegistered) {
      return;
    }
    this.session.on('play', (): void => {
      if (this.commandListener) {
        this.commandListener.onPlay();
      }
    });
    this.session.on('pause', (): void => {
      if (this.commandListener) {
        this.commandListener.onPause();
      }
    });
    this.session.on('stop', (): void => {
      if (this.commandListener) {
        this.commandListener.onStop();
      }
    });
    this.session.on('playNext', (): void => {
      if (this.commandListener) {
        this.commandListener.onPlayNext();
      }
    });
    this.session.on('playPrevious', (): void => {
      if (this.commandListener) {
        this.commandListener.onPlayPrevious();
      }
    });
    this.session.on('seek', (time: number): void => {
      if (this.commandListener) {
        const safeTime = Math.max(0, Math.floor(time));
        this.commandListener.onSeek(safeTime);
      }
    });
    this.callbacksRegistered = true;
  }

  private async syncMetadata(
    snapshot: ReadAloudStateSnapshot,
    context: ReadAloudSessionContext | null,
    settings: ReadAloudSettings
  ): Promise<void> {
    if (!this.session || !context) {
      return;
    }
    const assetId = this.buildAssetId(context);
    const title = this.buildTitle(context);
    const subtitle = this.buildSubtitle(context);
    const mediaImageKey = this.buildMediaImageKey(context);
    const durationMs = this.estimateDurationMs(snapshot, context, settings);
    if (
      assetId === this.lastMetadataAssetId &&
      title === this.lastMetadataTitle &&
      subtitle === this.lastMetadataSubtitle &&
      mediaImageKey === this.lastMetadataCoverUrl &&
      durationMs === this.lastMetadataDurationMs
    ) {
      return;
    }
    const mediaImage = await this.buildMediaImage(context);
    const metadata: avSession.AVMetadata = {
      assetId,
      title,
      subtitle,
      description: `听书 · 第${context.chapterIndex + 1}章`,
      duration: durationMs
    };
    if (typeof mediaImage === 'string') {
      this.releaseLastMetadataPixelMap();
      if (mediaImage.length > 0) {
        metadata.mediaImage = mediaImage;
      }
    } else {
      this.releaseLastMetadataPixelMap();
      this.lastMetadataPixelMap = mediaImage;
      metadata.mediaImage = mediaImage;
    }
    await this.session.setAVMetadata(metadata);
    this.lastMetadataAssetId = assetId;
    this.lastMetadataTitle = title;
    this.lastMetadataSubtitle = subtitle;
    this.lastMetadataCoverUrl = mediaImageKey;
    this.lastMetadataDurationMs = durationMs;
    logger.info(
      TAG,
      `媒体元数据已更新: title=${title}, subtitle=${metadata.subtitle}, hasCover=${mediaImageKey.length > 0}`
    );
  }

  private async syncPlaybackState(
    snapshot: ReadAloudStateSnapshot,
    context: ReadAloudSessionContext | null,
    settings: ReadAloudSettings
  ): Promise<void> {
    if (!this.session) {
      return;
    }
    const now = Date.now();
    const mappedState = this.mapPlaybackState(snapshot.playbackState);
    const positionMs = this.estimatePositionMs(snapshot, context, settings);
    const shouldThrottle = mappedState === this.lastPlaybackState &&
      Math.abs(positionMs - this.lastPlaybackPositionMs) < 100 &&
      (now - this.lastPlaybackSyncTimeMs) < PLAYBACK_SYNC_INTERVAL_MS;
    if (shouldThrottle) {
      return;
    }

    if (snapshot.playbackState !== ReadAloudPlaybackState.IDLE) {
      await this.activateSession();
    }

    const playbackState: avSession.AVPlaybackState = {
      state: mappedState
    };

    if (snapshot.playbackState === ReadAloudPlaybackState.PLAYING) {
      playbackState.speed = this.clampSpeed(settings.speed);
    }

    if (
      context &&
      mappedState === avSession.PlaybackState.PLAYBACK_STATE_PLAY
    ) {
      const durationMs = this.estimateDurationMs(snapshot, context, settings);
      if (durationMs > 0) {
        const playbackPosition: avSession.PlaybackPosition = {
          elapsedTime: Math.max(0, Math.min(positionMs, durationMs)),
          updateTime: now
        };
        playbackState.position = playbackPosition;
      }
    }

    await this.setPlaybackStateWithRecovery(playbackState);

    this.lastPlaybackState = mappedState;
    this.lastPlaybackPositionMs = positionMs;
    this.lastPlaybackSyncTimeMs = now;
    logger.debug(TAG, `媒体播放状态已同步: 原始状态=${snapshot.playbackState}, 映射状态=${mappedState}, 位置毫秒=${positionMs}`);

    if (snapshot.playbackState === ReadAloudPlaybackState.IDLE) {
      await this.deactivateSession();
    }
  }

  private mapPlaybackState(playbackState: ReadAloudPlaybackState): avSession.PlaybackState {
    if (playbackState === ReadAloudPlaybackState.PLAYING) {
      return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    if (playbackState === ReadAloudPlaybackState.PAUSED) {
      return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    }
    if (playbackState === ReadAloudPlaybackState.STOPPED) {
      return avSession.PlaybackState.PLAYBACK_STATE_STOP;
    }
    return avSession.PlaybackState.PLAYBACK_STATE_IDLE;
  }

  private async setPlaybackStateWithRecovery(playbackState: avSession.AVPlaybackState): Promise<void> {
    if (!this.session) {
      return;
    }
    try {
      await this.session.setAVPlaybackState(playbackState);
      return;
    } catch (error) {
      if (!this.shouldRecoverFromNativeSessionLoss(error)) {
        throw new Error(this.formatError(error));
      }
      logger.warn(TAG, `检测到媒体会话原生实例失效，准备自动重建: ${this.formatError(error)}`);
      await this.recreateSessionForNativeLoss();
      if (!this.session) {
        throw new Error(this.formatError(error));
      }
      await this.session.setAVPlaybackState(playbackState);
      logger.info(TAG, '媒体会话重建完成，播放状态重试成功');
    }
  }

  private shouldRecoverFromNativeSessionLoss(error: Object | string): boolean {
    const errorText = this.formatError(error).toLowerCase();
    if (errorText.includes('native session not exist')) {
      return true;
    }
    if (errorText.includes('session not exist')) {
      return true;
    }
    return false;
  }

  private async recreateSessionForNativeLoss(): Promise<void> {
    await this.releaseInternal();
    await this.ensureSessionReady();
  }

  private async activateSession(): Promise<void> {
    if (!this.session || this.activated) {
      return;
    }
    await this.session.activate();
    this.activated = true;
  }

  private async deactivateSession(): Promise<void> {
    if (!this.session || !this.activated) {
      return;
    }
    await this.session.deactivate();
    this.activated = false;
  }

  private async releaseInternal(): Promise<void> {
    if (!this.session) {
      return;
    }
    try {
      if (this.activated) {
        await this.session.deactivate();
      }
    } catch (error) {
      logger.warn(TAG, `媒体会话停用失败: ${this.formatError(error)}`);
    }
    try {
      await this.session.destroy();
    } catch (error) {
      logger.warn(TAG, `媒体会话销毁失败: ${this.formatError(error)}`);
    }
    this.session = null;
    this.callbacksRegistered = false;
    this.activated = false;
    this.launchAbilityBound = false;
    this.lastMetadataAssetId = '';
    this.lastMetadataTitle = '';
    this.lastMetadataSubtitle = '';
    this.lastMetadataCoverUrl = '';
    this.releaseLastMetadataPixelMap();
    this.lastMetadataDurationMs = -1;
    this.lastPlaybackState = avSession.PlaybackState.PLAYBACK_STATE_IDLE;
    this.lastPlaybackPositionMs = -1;
    this.lastPlaybackSyncTimeMs = 0;
  }

  private buildAssetId(context: ReadAloudSessionContext): string {
    return `${context.bookId}#${context.chapterIndex}`;
  }

  private buildTitle(context: ReadAloudSessionContext): string {
    if (context.bookTitle && context.bookTitle.length > 0) {
      return context.bookTitle;
    }
    if (context.chapterTitle && context.chapterTitle.length > 0) {
      return context.chapterTitle;
    }
    return `第${context.chapterIndex + 1}章`;
  }

  private buildSubtitle(context: ReadAloudSessionContext): string {
    if (context.chapterTitle && context.chapterTitle.length > 0) {
      return context.chapterTitle;
    }
    return `第${context.chapterIndex + 1}章`;
  }

  private buildMediaImageKey(context: ReadAloudSessionContext): string {
    const coverUrl = context.coverUrl ?? '';
    if (coverUrl.length <= 0 || coverUrl.startsWith('app.media.')) {
      return '';
    }
    return coverUrl;
  }

  private async buildMediaImage(context: ReadAloudSessionContext): Promise<image.PixelMap | string> {
    const coverUrl = this.buildMediaImageKey(context);
    if (coverUrl.length <= 0) {
      return '';
    }
    if (this.isNetworkOrDataImagePath(coverUrl)) {
      return coverUrl;
    }
    const localPath = this.resolveLocalMediaImagePath(coverUrl);
    if (localPath.length > 0) {
      const pixelMap = await this.createLocalCoverPixelMap(localPath);
      if (pixelMap) {
        return pixelMap;
      }
    }
    return coverUrl;
  }

  private isNetworkOrDataImagePath(path: string): boolean {
    const lower = path.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('data:image/');
  }

  private resolveLocalMediaImagePath(path: string): string {
    let normalized = path.trim().replace(/\\/g, '/');
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    try {
      normalized = decodeURIComponent(normalized);
    } catch (_error) {
    }
    if (normalized.startsWith('/') || /^[A-Za-z]:\//.test(normalized)) {
      return normalized;
    }
    return '';
  }

  private localPathExists(path: string): boolean {
    if (path.length <= 0) {
      return false;
    }
    try {
      return fileIo.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private async createLocalCoverPixelMap(localPath: string): Promise<image.PixelMap | null> {
    if (!this.localPathExists(localPath)) {
      return null;
    }
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(localPath);
      const decodingOptions: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: 512,
          height: 512
        }
      };
      return await source.createPixelMap(decodingOptions);
    } catch (error) {
      logger.warn(TAG, `媒体封面 PixelMap 解码失败，回退字符串路径: ${this.formatError(error)}`);
      return null;
    } finally {
      if (source) {
        try {
          source.release();
        } catch (releaseError) {
          logger.warn(TAG, `媒体封面 ImageSource 释放失败: ${this.formatError(releaseError)}`);
        }
      }
    }
  }

  private releaseLastMetadataPixelMap(): void {
    if (!this.lastMetadataPixelMap) {
      return;
    }
    try {
      this.lastMetadataPixelMap.release();
    } catch (error) {
      logger.warn(TAG, `释放媒体封面 PixelMap 失败: ${this.formatError(error)}`);
    }
    this.lastMetadataPixelMap = null;
  }

  private estimateDurationMs(
    snapshot: ReadAloudStateSnapshot,
    context: ReadAloudSessionContext | null,
    settings: ReadAloudSettings
  ): number {
    if (snapshot.totalDurationMs > 0) {
      return Math.floor(snapshot.totalDurationMs);
    }
    if (!context || !context.content || context.content.length <= 0) {
      return 0;
    }
    const speed = this.clampSpeed(settings.speed);
    const charsPerSecond = Math.max(1, BASE_CHARS_PER_SECOND * speed);
    return Math.max(1, Math.round((context.content.length / charsPerSecond) * 1000));
  }

  private estimatePositionMs(
    snapshot: ReadAloudStateSnapshot,
    context: ReadAloudSessionContext | null,
    settings: ReadAloudSettings
  ): number {
    if (snapshot.currentPositionMs >= 0) {
      const durationMs = this.estimateDurationMs(snapshot, context, settings);
      if (durationMs > 0) {
        return Math.max(0, Math.min(Math.floor(snapshot.currentPositionMs), durationMs));
      }
      return Math.max(0, Math.floor(snapshot.currentPositionMs));
    }
    if (!context || !context.content || context.content.length <= 0) {
      return 0;
    }
    const durationMs = this.estimateDurationMs(snapshot, context, settings);
    if (durationMs <= 0) {
      return 0;
    }
    const maxIndex = Math.max(0, context.content.length - 1);
    const safeCharIndex = Math.max(0, Math.min(snapshot.currentCharIndex, maxIndex));
    const ratio = safeCharIndex / Math.max(1, context.content.length);
    return Math.max(0, Math.min(durationMs, Math.floor(durationMs * ratio)));
  }

  private clampSpeed(speed: number): number {
    return Math.max(0.5, Math.min(2.0, speed));
  }

  private formatError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorObj = error as Error;
    if (errorObj.message && errorObj.message.length > 0) {
      return errorObj.message;
    }
    try {
      const jsonText = JSON.stringify(error);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_ignored) {
    }
    return String(error);
  }
}
