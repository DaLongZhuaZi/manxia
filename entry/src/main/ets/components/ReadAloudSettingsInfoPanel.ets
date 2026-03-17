import { curves, UIContext } from '@kit.ArkUI';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { SettingKeys, SettingsManager } from '../Framework/Managers/SettingsManager';
import { ReadAloudEngineType, ReadAloudSettings } from '../Models/TextReaderModels';
import { ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import { ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { logger } from '../Utils/Logger';

interface ReadAloudEngineOption {
  label: string;
  engine: ReadAloudEngineType;
}

export interface ReadAloudSettingsInfoCallbacks {
  onClose: () => void;
  onRefresh: () => void;
  onChange: (partial: Partial<ReadAloudSettings>) => void;
}

const DEFAULT_READ_ALOUD_SETTINGS_INFO_CALLBACKS: ReadAloudSettingsInfoCallbacks = {
  onClose: () => {},
  onRefresh: () => {},
  onChange: (_partial: Partial<ReadAloudSettings>) => {}
};

const READ_ALOUD_ENGINE_OPTIONS: ReadAloudEngineOption[] = [
  { label: '系统', engine: ReadAloudEngineType.SYSTEM },
  { label: '兼容', engine: ReadAloudEngineType.LEGADO_COMPAT },
  { label: '远程', engine: ReadAloudEngineType.REMOTE }
];
const TAG = 'ReadAloudSettingsInfoPanel';

@Component
export struct ReadAloudSettingsInfoPanel {
  @Prop isLandscape: boolean = false;
  @Prop settings: ReadAloudSettings;
  @Prop availability: ReadAloudEngineAvailabilityMap;
  @Prop voiceOptions: ReadAloudVoiceOption[] = [];
  @Prop statusMessage: string = '';
  @Prop appFontFamily: string = 'HarmonyOS Sans';
  @Prop callbacks: ReadAloudSettingsInfoCallbacks = DEFAULT_READ_ALOUD_SETTINGS_INFO_CALLBACKS;

  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private isClosing: boolean = false;
  @State private favoriteVoiceIds: string[] = [];
  @State private voiceFilterLanguage: string = '全部语种';
  @State private voiceFilterGender: string = '全部性别';
  @State private voiceFilterStyle: string = '全部风格';
  @State private onlyShowFavorites: boolean = false;
  @State private previewVoiceId: string = '';
  @State private previewStatusMessage: string = '';
  @State private blockedVoiceIds: string[] = [];

  private uiContext: UIContext | undefined = undefined;
  private previewEngine: textToSpeech.TextToSpeechEngine | null = null;
  private previewAutoStopTimer: number = -1;
  private previewSessionToken: string = '';

  aboutToAppear(): void {
    logger.info(TAG, '听书设置面板显示，开始刷新音色与收藏数据');
    this.uiContext = this.getUIContext();
    this.blockedVoiceIds = [];
    this.callbacks.onRefresh();
    this.loadFavoriteVoices();
    this.showPanel();
  }

  aboutToDisappear(): void {
    logger.info(TAG, '听书设置面板即将关闭，清理试听会话');
    this.finishPreviewSession(this.previewSessionToken, '', false);
  }

  private showPanel(): void {
    if (!this.uiContext) {
      this.backdropOpacity = 0.5;
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.panelTranslateX = 0;
      return;
    }

    this.uiContext.animateTo({
      duration: 200,
      curve: curves.initCurve(Curve.EaseOut)
    }, () => {
      this.backdropOpacity = 0.5;
    });

    if (this.isLandscape) {
      this.uiContext.animateTo({
        duration: 250,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      this.uiContext.animateTo({
        duration: 300,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateY = 0;
      });
    }
  }

  private requestClose(trigger: string): void {
    if (this.isClosing) {
      logger.debug(TAG, `忽略重复关闭请求: trigger=${trigger}`);
      return;
    }
    this.finishPreviewSession(this.previewSessionToken, '', false);
    this.isClosing = true;
    logger.info(TAG, `收到关闭请求: trigger=${trigger}`);

    if (!this.uiContext) {
      this.backdropOpacity = 0;
      this.panelOpacity = 0;
      this.panelTranslateX = 320;
      this.panelTranslateY = 300;
      this.callbacks.onClose();
      this.isClosing = false;
      return;
    }

    if (this.isLandscape) {
      this.uiContext.animateTo({
        duration: 200,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = 320;
      });
    } else {
      this.uiContext.animateTo({
        duration: 200,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.panelOpacity = 0;
        this.panelTranslateY = 300;
      });
    }

    this.uiContext.animateTo({
      duration: 200,
      curve: curves.initCurve(Curve.EaseIn)
    }, () => {
      this.backdropOpacity = 0;
    });

    setTimeout(() => {
      this.callbacks.onClose();
      this.isClosing = false;
    }, 220);
  }

  private isReadAloudEngineAvailable(engineType: ReadAloudEngineType): boolean {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return this.availability.SYSTEM === true;
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return this.availability.LEGADO_COMPAT === true;
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      return this.availability.REMOTE === true;
    }
    return false;
  }

  private getReadAloudUnavailableHint(engineType: ReadAloudEngineType): string {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return '系统 TTS 探测失败，请点击“刷新”重试';
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return '兼容后端开发中，当前请使用系统引擎';
    }
    return '远程后端开发中，当前请使用系统引擎';
  }

  private getReadAloudVoiceLabel(voice: ReadAloudVoiceOption): string {
    const language = this.getVoiceLanguageLabel(voice);
    const channel = voice.online === 0 ? '在线' : '离线';
    const gender = this.getVoiceGenderLabel(voice);
    const style = this.getVoiceStyleLabel(voice);
    return `${language} / ${channel} / 声线${voice.person} / ${gender} / ${style}`;
  }

  private hasSelectedVoice(): boolean {
    const language = this.settings.voiceLanguage ?? '';
    const person = this.settings.voicePerson ?? -1;
    const online = this.settings.voiceOnline ?? -1;
    return language.length > 0 && person >= 0 && (online === 0 || online === 1);
  }

  private isVoiceSelected(voice: ReadAloudVoiceOption): boolean {
    const language = this.settings.voiceLanguage ?? '';
    const person = this.settings.voicePerson ?? -1;
    const online = this.settings.voiceOnline ?? -1;
    return language === voice.language && person === voice.person && online === voice.online;
  }

  private resetVoiceSelectionToSystemDefault(): void {
    logger.info(TAG, '切换音色为系统默认');
    this.callbacks.onChange({
      voiceLanguage: '',
      voicePerson: -1,
      voiceOnline: -1
    });
  }

  private selectVoiceOption(voice: ReadAloudVoiceOption): void {
    if (this.isBlockedVoiceId(voice.id)) {
      this.previewStatusMessage = '该音色已被屏蔽，请选择其他音色';
      logger.warn(TAG, `阻止选择已屏蔽音色: voiceId=${voice.id}`);
      return;
    }
    logger.info(TAG, `选择音色: voiceId=${voice.id}, language=${voice.language}, person=${voice.person}, online=${voice.online}`);
    this.callbacks.onChange({
      voiceLanguage: voice.language,
      voicePerson: voice.person,
      voiceOnline: voice.online
    });
  }

  private formatError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorObject = error as Error;
    if (errorObject.message && errorObject.message.length > 0) {
      return errorObject.message;
    }
    return String(error);
  }

  private normalizeFavoriteVoiceIds(rawIds: string[]): string[] {
    const normalized: string[] = [];
    const seenIds: Set<string> = new Set<string>();
    rawIds.forEach((id: string) => {
      if (!id || id.length <= 0 || seenIds.has(id)) {
        return;
      }
      seenIds.add(id);
      normalized.push(id);
    });
    return normalized;
  }

  private loadFavoriteVoices(): void {
    try {
      const manager = SettingsManager.getInstance();
      const ids = manager.getJSON<string[]>(SettingKeys.GLOBAL_TEXT_READ_ALOUD_FAVORITE_VOICE_IDS, []);
      this.favoriteVoiceIds = this.normalizeFavoriteVoiceIds(ids);
      logger.info(TAG, `加载音色收藏完成: count=${this.favoriteVoiceIds.length}`);
    } catch (error) {
      const errorText = this.formatError(error);
      logger.warn(TAG, `加载音色收藏失败: ${errorText}`);
    }
  }

  private persistFavoriteVoices(): void {
    const ids = this.normalizeFavoriteVoiceIds(this.favoriteVoiceIds);
    this.favoriteVoiceIds = ids;
    SettingsManager.getInstance()
      .setJSON<string[]>(SettingKeys.GLOBAL_TEXT_READ_ALOUD_FAVORITE_VOICE_IDS, ids)
      .then(() => {
        logger.info(TAG, `保存音色收藏成功: count=${ids.length}`);
      })
      .catch((error: Object | string) => {
        const errorText = this.formatError(error);
        logger.warn(TAG, `保存音色收藏失败: ${errorText}`);
      });
  }

  private isVoiceFavorited(voiceId: string): boolean {
    return this.favoriteVoiceIds.indexOf(voiceId) >= 0;
  }

  private isBlockedVoiceId(voiceId: string): boolean {
    return this.blockedVoiceIds.indexOf(voiceId) >= 0;
  }

  private isInvalidVoiceErrorText(errorText: string): boolean {
    const normalized = errorText.toLowerCase();
    if (normalized.includes('invalid relative path')) {
      return true;
    }
    if (normalized.includes('1002300005')) {
      return true;
    }
    return normalized.includes('create engine error') || normalized.includes('createengine error');
  }

  private blockVoiceOptionForSession(voice: ReadAloudVoiceOption, reason: string): void {
    if (this.isBlockedVoiceId(voice.id)) {
      return;
    }
    const nextBlockedVoiceIds = this.blockedVoiceIds.slice();
    nextBlockedVoiceIds.push(voice.id);
    this.blockedVoiceIds = nextBlockedVoiceIds;
    logger.warn(TAG, `音色已在当前面板会话中屏蔽: voiceId=${voice.id}, reason=${reason}`);
    if (this.isVoiceSelected(voice)) {
      logger.warn(TAG, `当前选中音色已不可用，回退系统默认: voiceId=${voice.id}`);
      this.resetVoiceSelectionToSystemDefault();
    }
  }

  private toggleFavoriteVoice(voice: ReadAloudVoiceOption): void {
    const wasFavorited = this.isVoiceFavorited(voice.id);
    const nextIds = this.favoriteVoiceIds.slice();
    const currentIndex = nextIds.indexOf(voice.id);
    if (currentIndex >= 0) {
      nextIds.splice(currentIndex, 1);
    } else {
      nextIds.push(voice.id);
    }
    this.favoriteVoiceIds = this.normalizeFavoriteVoiceIds(nextIds);
    logger.info(
      TAG,
      `音色收藏状态变更: voiceId=${voice.id}, action=${wasFavorited ? 'remove' : 'add'}, total=${this.favoriteVoiceIds.length}`
    );
    this.persistFavoriteVoices();
  }

  private getVoiceLanguageLabel(voice: ReadAloudVoiceOption): string {
    return voice.language.length > 0 ? voice.language : '未知语种';
  }

  private getVoiceGenderLabel(voice: ReadAloudVoiceOption): string {
    return voice.gender && voice.gender.length > 0 ? voice.gender : '未知性别';
  }

  private getVoiceStyleLabel(voice: ReadAloudVoiceOption): string {
    if (voice.style && voice.style.length > 0) {
      return voice.style;
    }
    return '默认风格';
  }

  private getVoiceLanguageOptions(): string[] {
    const options: string[] = ['全部语种'];
    const seen: Set<string> = new Set<string>();
    this.voiceOptions.forEach((voice: ReadAloudVoiceOption) => {
      const label = this.getVoiceLanguageLabel(voice);
      if (!seen.has(label)) {
        seen.add(label);
        options.push(label);
      }
    });
    return options;
  }

  private getVoiceGenderOptions(): string[] {
    const options: string[] = ['全部性别'];
    const seen: Set<string> = new Set<string>();
    this.voiceOptions.forEach((voice: ReadAloudVoiceOption) => {
      const label = this.getVoiceGenderLabel(voice);
      if (!seen.has(label)) {
        seen.add(label);
        options.push(label);
      }
    });
    return options;
  }

  private getVoiceStyleOptions(): string[] {
    const options: string[] = ['全部风格'];
    const seen: Set<string> = new Set<string>();
    this.voiceOptions.forEach((voice: ReadAloudVoiceOption) => {
      const label = this.getVoiceStyleLabel(voice);
      if (!seen.has(label)) {
        seen.add(label);
        options.push(label);
      }
    });
    return options;
  }

  private getFilteredVoiceOptions(): ReadAloudVoiceOption[] {
    const languageFilter = this.voiceFilterLanguage;
    const genderFilter = this.voiceFilterGender;
    const styleFilter = this.voiceFilterStyle;

    const filtered = this.voiceOptions.filter((voice: ReadAloudVoiceOption) => {
      if (this.isBlockedVoiceId(voice.id)) {
        return false;
      }
      if (this.onlyShowFavorites && !this.isVoiceFavorited(voice.id)) {
        return false;
      }
      if (languageFilter !== '全部语种' && this.getVoiceLanguageLabel(voice) !== languageFilter) {
        return false;
      }
      if (genderFilter !== '全部性别' && this.getVoiceGenderLabel(voice) !== genderFilter) {
        return false;
      }
      if (styleFilter !== '全部风格' && this.getVoiceStyleLabel(voice) !== styleFilter) {
        return false;
      }
      return true;
    });

    filtered.sort((left: ReadAloudVoiceOption, right: ReadAloudVoiceOption): number => {
      const leftFavorite = this.isVoiceFavorited(left.id) ? 1 : 0;
      const rightFavorite = this.isVoiceFavorited(right.id) ? 1 : 0;
      if (leftFavorite !== rightFavorite) {
        return rightFavorite - leftFavorite;
      }
      if (this.isVoiceSelected(left) !== this.isVoiceSelected(right)) {
        return this.isVoiceSelected(right) ? 1 : -1;
      }
      if (left.id < right.id) {
        return -1;
      }
      if (left.id > right.id) {
        return 1;
      }
      return 0;
    });

    return filtered;
  }

  private createPreviewSessionToken(voiceId: string): string {
    return `${Date.now()}_${voiceId}`;
  }

  private clearPreviewAutoStopTimer(): void {
    if (this.previewAutoStopTimer < 0) {
      return;
    }
    clearTimeout(this.previewAutoStopTimer);
    this.previewAutoStopTimer = -1;
  }

  private finishPreviewSession(sessionToken: string, statusMessage: string, writeStatusMessage: boolean): void {
    if (!sessionToken || sessionToken.length <= 0) {
      return;
    }
    if (sessionToken !== this.previewSessionToken) {
      return;
    }
    logger.info(
      TAG,
      `结束试听会话: token=${sessionToken}, writeStatus=${writeStatusMessage}, message=${statusMessage.length > 0 ? statusMessage : 'empty'}`
    );

    this.previewSessionToken = '';
    this.previewVoiceId = '';
    this.clearPreviewAutoStopTimer();

    const activeEngine = this.previewEngine;
    this.previewEngine = null;

    if (writeStatusMessage) {
      this.previewStatusMessage = statusMessage;
      logger.info(TAG, `音色试听结束: message=${statusMessage}`);
    }

    if (!activeEngine) {
      return;
    }

    try {
      activeEngine.stop();
    } catch (_error) {
    }

    try {
      activeEngine.shutdown();
    } catch (_error) {
    }
  }

  private getPreviewTextByVoice(voice: ReadAloudVoiceOption): string {
    const language = voice.language.toLowerCase();
    if (language.startsWith('en')) {
      return 'This is a short voice preview.';
    }
    return '这是一段听书音色试听。';
  }

  private async previewVoiceOption(voice: ReadAloudVoiceOption): Promise<void> {
    logger.info(TAG, `发起音色试听: voiceId=${voice.id}, language=${voice.language}, person=${voice.person}, online=${voice.online}`);
    if (this.isBlockedVoiceId(voice.id)) {
      this.previewStatusMessage = '该音色已被屏蔽，请选择其他音色';
      logger.warn(TAG, `音色试听被拒绝: voiceId=${voice.id} 已在当前会话中屏蔽`);
      return;
    }
    if (this.settings.engineType !== ReadAloudEngineType.SYSTEM) {
      this.previewStatusMessage = '仅系统 TTS 支持试听';
      logger.warn(TAG, `音色试听被拒绝: 当前引擎不是系统引擎, engine=${this.settings.engineType}`);
      return;
    }

    if (!voice.language || voice.language.length <= 0) {
      this.previewStatusMessage = '该音色缺少语种信息，无法试听';
      logger.warn(TAG, `音色试听失败: 缺少语种信息, voiceId=${voice.id}`);
      return;
    }

    if (this.previewSessionToken.length > 0) {
      logger.info(TAG, `检测到旧试听会话，先终止: token=${this.previewSessionToken}`);
      this.finishPreviewSession(this.previewSessionToken, '', false);
    }

    const sessionToken = this.createPreviewSessionToken(voice.id);
    this.previewSessionToken = sessionToken;
    this.previewVoiceId = voice.id;
    this.previewStatusMessage = `正在试听：${this.getReadAloudVoiceLabel(voice)}`;

    try {
      const engine = await textToSpeech.createEngine({
        language: voice.language,
        person: voice.person,
        online: voice.online
      });
      logger.info(TAG, `音色试听引擎创建成功: voiceId=${voice.id}`);
      if (sessionToken !== this.previewSessionToken) {
        logger.warn(TAG, `音色试听会话已变更，放弃当前引擎: voiceId=${voice.id}`);
        try {
          engine.shutdown();
        } catch (_error) {
        }
        return;
      }

      this.previewEngine = engine;
      engine.setListener({
        onStart: (_requestId: string, _response: textToSpeech.StartResponse): void => {
          logger.info(TAG, `音色试听开始: voiceId=${voice.id}`);
        },
        onComplete: (_requestId: string, response: textToSpeech.CompleteResponse): void => {
          if (response.type === 0) {
            logger.info(TAG, `音色试听回调: 合成完成，等待播放完成, voiceId=${voice.id}`);
            return;
          }
          logger.info(TAG, `音色试听回调: 播放完成, voiceId=${voice.id}`);
          this.finishPreviewSession(sessionToken, '试听结束', true);
        },
        onStop: (_requestId: string, _response: textToSpeech.StopResponse): void => {
          logger.info(TAG, `音色试听回调: 停止完成, voiceId=${voice.id}`);
          this.finishPreviewSession(sessionToken, '试听结束', true);
        },
        onError: (_requestId: string, errorCode: number, errorMessage: string): void => {
          logger.error(TAG, `音色试听回调: 发生错误, voiceId=${voice.id}, code=${errorCode}, message=${errorMessage}`);
          if (this.isInvalidVoiceErrorText(errorMessage)) {
            this.blockVoiceOptionForSession(voice, errorMessage);
          }
          this.finishPreviewSession(sessionToken, `试听失败：${errorMessage}`, true);
        }
      });

      const requestId = `voice_preview_${Date.now()}`;
      engine.speak(this.getPreviewTextByVoice(voice), { requestId });
      logger.info(TAG, `音色试听发起朗读成功: voiceId=${voice.id}, requestId=${requestId}`);
      this.previewAutoStopTimer = setTimeout(() => {
        logger.info(TAG, `音色试听到达自动停止时间: voiceId=${voice.id}`);
        this.finishPreviewSession(sessionToken, '试听结束', true);
      }, 3000);
    } catch (error) {
      const errorText = this.formatError(error);
      logger.error(TAG, `音色试听异常: voiceId=${voice.id}, error=${errorText}`);
      if (this.isInvalidVoiceErrorText(errorText)) {
        this.blockVoiceOptionForSession(voice, errorText);
      }
      this.finishPreviewSession(sessionToken, `试听失败：${errorText}`, true);
    }
  }

  @Builder
  private buildVoiceFilterRow(title: string, options: string[], currentValue: string, onSelect: (value: string) => void) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          ForEach(options, (option: string) => {
            Button(option)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .height(30)
              .backgroundColor(option === currentValue ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
              .fontColor(option === currentValue ? Color.White : $r('app.color.text_primary'))
              .onClick(() => {
                logger.info(TAG, `音色筛选变更: ${title} -> ${option}`);
                onSelect(option);
              })
          }, (option: string) => option)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .constraintSize({ minHeight: 32 })
    }
    .width('100%')
  }

  @Builder
  private buildToggleRow(label: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn })
        .selectedColor($r('app.color.accent_primary'))
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  private buildPanelContent() {
    Column() {
      Row() {
        Text('听书设置与信息')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button('刷新')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .height(30)
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
        .margin({ right: 8 })
        .onClick(() => {
          logger.info(TAG, '点击刷新听书信息');
          this.blockedVoiceIds = [];
          this.previewStatusMessage = '';
          this.callbacks.onRefresh();
        })

        Button() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.requestClose('close_button');
        })
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 6, bottom: 10 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Text('朗读引擎')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            Row({ space: 8 }) {
              ForEach(READ_ALOUD_ENGINE_OPTIONS, (item: ReadAloudEngineOption) => {
                Button(item.label)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(32)
                  .layoutWeight(1)
                  .backgroundColor(
                    this.settings.engineType === item.engine
                      ? $r('app.color.accent_primary')
                      : $r('app.color.background_secondary')
                  )
                  .fontColor(
                    this.settings.engineType === item.engine
                      ? Color.White
                      : $r('app.color.text_primary')
                  )
                  .opacity(this.isReadAloudEngineAvailable(item.engine) ? 1 : 0.45)
                  .onClick(() => {
                    if (!this.isReadAloudEngineAvailable(item.engine)) {
                      logger.warn(TAG, `引擎切换被忽略：目标引擎不可用, engine=${item.engine}`);
                      return;
                    }
                    logger.info(TAG, `切换朗读引擎: ${this.settings.engineType} -> ${item.engine}`);
                    this.finishPreviewSession(this.previewSessionToken, '', false);
                    this.callbacks.onChange({ engineType: item.engine });
                  })
              })
            }
            .width('100%')

            if (!this.isReadAloudEngineAvailable(this.settings.engineType)) {
              Text(this.getReadAloudUnavailableHint(this.settings.engineType))
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
          .width('100%')

          Column({ space: 6 }) {
            Text('可用音色（预览）')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            if (this.statusMessage.length > 0) {
              Text(this.statusMessage)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            if (this.previewStatusMessage.length > 0) {
              Text(this.previewStatusMessage)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.accent_primary'))
                .width('100%')
            }

            if (this.settings.engineType !== ReadAloudEngineType.SYSTEM) {
              Text('当前为非系统引擎，音色切换仅支持系统 TTS')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            } else if (this.voiceOptions.length > 0) {
              Row({ space: 8 }) {
                Text('当前音色')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_secondary'))

                Text(this.hasSelectedVoice() ? '自定义' : '系统默认')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.accent_primary'))
              }
              .width('100%')

              Button('跟随系统默认')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .height(32)
                .width('100%')
                .backgroundColor(this.hasSelectedVoice() ? $r('app.color.background_secondary') : $r('app.color.accent_primary'))
                .fontColor(this.hasSelectedVoice() ? $r('app.color.text_primary') : Color.White)
                .onClick(() => {
                  this.resetVoiceSelectionToSystemDefault();
                  this.previewStatusMessage = '';
                })

              Row({ space: 8 }) {
                Button(this.onlyShowFavorites ? '显示全部音色' : '仅看收藏')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .height(30)
                  .backgroundColor(this.onlyShowFavorites ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                  .fontColor(this.onlyShowFavorites ? Color.White : $r('app.color.text_primary'))
                  .onClick(() => {
                    logger.info(TAG, `切换收藏筛选模式: onlyFavorites=${!this.onlyShowFavorites}`);
                    this.onlyShowFavorites = !this.onlyShowFavorites;
                  })

                Text(`收藏 ${this.favoriteVoiceIds.length}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
              .width('100%')

              this.buildVoiceFilterRow('语种筛选', this.getVoiceLanguageOptions(), this.voiceFilterLanguage, (value: string) => {
                this.voiceFilterLanguage = value;
                logger.info(TAG, `语种筛选已更新: ${value}`);
              })
              this.buildVoiceFilterRow('性别筛选', this.getVoiceGenderOptions(), this.voiceFilterGender, (value: string) => {
                this.voiceFilterGender = value;
                logger.info(TAG, `性别筛选已更新: ${value}`);
              })
              this.buildVoiceFilterRow('风格筛选', this.getVoiceStyleOptions(), this.voiceFilterStyle, (value: string) => {
                this.voiceFilterStyle = value;
                logger.info(TAG, `风格筛选已更新: ${value}`);
              })

              ForEach(
                this.getFilteredVoiceOptions(),
                (voice: ReadAloudVoiceOption) => {
                  Row({ space: 8 }) {
                    Button(this.getReadAloudVoiceLabel(voice))
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(36)
                      .layoutWeight(1)
                      .backgroundColor(this.isVoiceSelected(voice) ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                      .fontColor(this.isVoiceSelected(voice) ? Color.White : $r('app.color.text_primary'))
                      .onClick(() => {
                        this.selectVoiceOption(voice);
                        this.previewStatusMessage = '';
                      })

                    Button(this.previewVoiceId === voice.id ? '试听中' : '试听')
                      .fontSize(11)
                      .fontFamily(this.appFontFamily)
                      .height(36)
                      .width(62)
                      .backgroundColor(this.previewVoiceId === voice.id ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                      .fontColor(this.previewVoiceId === voice.id ? Color.White : $r('app.color.text_primary'))
                      .enabled(this.previewVoiceId.length <= 0 || this.previewVoiceId === voice.id)
                      .onClick(() => {
                        void this.previewVoiceOption(voice);
                      })

                    Button(this.isVoiceFavorited(voice.id) ? '已藏' : '收藏')
                      .fontSize(11)
                      .fontFamily(this.appFontFamily)
                      .height(36)
                      .width(62)
                      .backgroundColor(this.isVoiceFavorited(voice.id) ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                      .fontColor(this.isVoiceFavorited(voice.id) ? Color.White : $r('app.color.text_primary'))
                      .onClick(() => {
                        this.toggleFavoriteVoice(voice);
                      })
                  }
                    .width('100%')
                },
                (voice: ReadAloudVoiceOption) => voice.id
              )

              if (this.getFilteredVoiceOptions().length <= 0) {
                Text('当前筛选条件下没有可用音色，请调整筛选条件')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            } else {
              Text('系统 TTS 可直接朗读；当前未返回音色列表，可在系统语音服务中下载音色后重试')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })

          Divider().color($r('app.color.divider'))

          this.buildToggleRow('启用听书', this.settings.enabled, (value: boolean) => {
            this.callbacks.onChange({ enabled: value });
          })

          this.buildToggleRow('后台继续播放', this.settings.continueInBackground, (value: boolean) => {
            this.callbacks.onChange({ continueInBackground: value });
          })

          this.buildToggleRow('自动播放下一章', this.settings.autoPlayNextChapter, (value: boolean) => {
            this.callbacks.onChange({ autoPlayNextChapter: value });
          })

          this.buildToggleRow('手动翻页时自动暂停', this.settings.pauseOnManualPageTurn, (value: boolean) => {
            this.callbacks.onChange({ pauseOnManualPageTurn: value });
          })

          Row() {
            Text('语速')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.settings.speed.toFixed(1)}x`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.accent_primary'))
          }
          .width('100%')

          Slider({
            value: this.settings.speed * 10,
            min: 5,
            max: 20,
            step: 1
          })
            .width('100%')
            .onChange((value: number) => {
              this.callbacks.onChange({
                speed: Math.max(0.5, Math.min(2.0, Math.round(value) / 10))
              });
            })

          Row() {
            Text('音调')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.settings.pitch.toFixed(1)}x`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.accent_primary'))
          }
          .width('100%')

          Slider({
            value: this.settings.pitch * 10,
            min: 5,
            max: 20,
            step: 1
          })
            .width('100%')
            .onChange((value: number) => {
              this.callbacks.onChange({
                pitch: Math.max(0.5, Math.min(2.0, Math.round(value) / 10))
              });
            })

          Row() {
            Text('音量')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${Math.round(this.settings.volume * 100)}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.accent_primary'))
          }
          .width('100%')

          Slider({
            value: this.settings.volume * 100,
            min: 0,
            max: 100,
            step: 1
          })
            .width('100%')
            .onChange((value: number) => {
              this.callbacks.onChange({
                volume: Math.max(0, Math.min(1, Math.round(value) / 100))
              });
            })
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 8, bottom: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width(this.isLandscape ? 320 : '100%')
    .height(this.isLandscape ? '100%' : '78%')
    .padding({ left: 16, right: 16, top: 10, bottom: 18 })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(this.isLandscape ? { topLeft: 16, bottomLeft: 16 } : { topLeft: 16, topRight: 16 })
    .opacity(this.panelOpacity)
    .translate({
      x: this.isLandscape ? this.panelTranslateX : 0,
      y: this.isLandscape ? 0 : this.panelTranslateY
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(this.backdropOpacity)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.requestClose('overlay_mask');
        })

      if (this.isLandscape) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.requestClose('landscape_blank');
            })

          this.buildPanelContent()
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Column()
            .layoutWeight(1)
            .width('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.requestClose('portrait_blank');
            })

          this.buildPanelContent()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(20000)
  }
}
