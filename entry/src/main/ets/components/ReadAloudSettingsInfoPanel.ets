import { curves, UIContext } from '@kit.ArkUI';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { SettingKeys, SettingsManager } from '../Framework/Managers/SettingsManager';
import {
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  DEFAULT_REMOTE_READ_ALOUD_PRESET_ID,
  getXiaomiMimoRemoteReadAloudVoiceLabel,
  hasRemoteReadAloudStylePrompt,
  isXiaomiMimoRemoteReadAloud,
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudChoiceOption,
  RemoteReadAloudPreset,
  RemoteReadAloudPresetConfig,
  RemoteReadAloudSettings,
  RemoteReadAloudStyleCategory,
  toggleRemoteReadAloudStylePrompt,
  XIAOMI_MIMO_REMOTE_READ_ALOUD_STYLE_CATEGORIES,
  XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS,
  extractRemoteReadAloudPresetConfig,
  isRemoteReadAloudPresetConfigEqual,
  mergeRemoteReadAloudSettings,
  normalizeRemoteReadAloudSettings,
  splitRemoteReadAloudStylePrompt,
  normalizeRemoteReadAloudStylePrompt
} from '../Models/TextReaderModels';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
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
  @State private remotePresetDraftName: string = '';
  @State private remotePresetStatusMessage: string = '';

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
    this.syncRemotePresetDraftName();
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
      return '兼容渠道不可用，请先确认系统 TTS 可用后点击“刷新”';
    }
    return '远程 TTS 当前不可用，请检查 endpoint/model/voice/apiKey 后点击“刷新”';
  }

  private getReadAloudUnavailableDetail(engineType: ReadAloudEngineType): string {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
      return probeError.length > 0 ? `系统 TTS 不可用：${probeError}` : this.getReadAloudUnavailableHint(engineType);
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
      return probeError.length > 0 ? `兼容渠道不可用：${probeError}` : this.getReadAloudUnavailableHint(engineType);
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
      return probeError.length > 0 ? `远程 TTS 不可用：${probeError}` : this.getReadAloudUnavailableHint(engineType);
    }
    return this.getReadAloudUnavailableHint(engineType);
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

  private getRemoteSettings(): RemoteReadAloudSettings {
    return normalizeRemoteReadAloudSettings(this.settings.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS);
  }

  private updateRemoteSettings(partial: Partial<RemoteReadAloudSettings>): void {
    const merged = mergeRemoteReadAloudSettings(this.getRemoteSettings(), partial);
    this.callbacks.onChange({
      remote: merged
    });
  }

  private isMiMoRemoteSettings(): boolean {
    return isXiaomiMimoRemoteReadAloud(this.getRemoteSettings());
  }

  private getRemoteStylePrompt(): string {
    return normalizeRemoteReadAloudStylePrompt(this.getRemoteSettings().stylePrompt);
  }

  private isRemoteStyleSelected(style: string): boolean {
    return hasRemoteReadAloudStylePrompt(this.getRemoteStylePrompt(), style);
  }

  private toggleRemoteStyle(style: string): void {
    this.updateRemoteSettings({
      stylePrompt: toggleRemoteReadAloudStylePrompt(this.getRemoteStylePrompt(), style)
    });
  }

  private getRemoteVoiceLabel(voice: string): string {
    if (this.isMiMoRemoteSettings()) {
      return getXiaomiMimoRemoteReadAloudVoiceLabel(voice);
    }
    const normalizedVoice = voice.trim();
    return normalizedVoice.length > 0 ? normalizedVoice : '默认音色';
  }

  private syncRemotePresetDraftName(): void {
    const activePreset = this.getActiveRemotePreset();
    this.remotePresetDraftName = activePreset ? activePreset.name : '';
  }

  private getRemoteCurrentConfig(): RemoteReadAloudPresetConfig {
    return extractRemoteReadAloudPresetConfig(this.getRemoteSettings());
  }

  private getRemoteConfigWithoutApiKey(config: RemoteReadAloudPresetConfig): RemoteReadAloudPresetConfig {
    return {
      endpoint: config.endpoint,
      apiPath: config.apiPath,
      apiKey: '',
      model: config.model,
      voice: config.voice,
      stylePrompt: config.stylePrompt,
      audioFormat: config.audioFormat,
      streamEnabled: config.streamEnabled,
      prefetchSegments: config.prefetchSegments,
      connectTimeoutMs: config.connectTimeoutMs,
      readTimeoutMs: config.readTimeoutMs,
      maxInputChars: config.maxInputChars,
      reservedInputChars: config.reservedInputChars,
      minChunkChars: config.minChunkChars,
      targetChunkChars: config.targetChunkChars,
      maxChunkChars: config.maxChunkChars,
      cacheAudioFiles: config.cacheAudioFiles,
      autoConcatAudio: config.autoConcatAudio,
      customHeadersJson: config.customHeadersJson,
      extraBodyJson: config.extraBodyJson
    };
  }

  private getActiveRemotePreset(): RemoteReadAloudPreset | null {
    const remote = this.getRemoteSettings();
    const activePresetId = remote.activePresetId ?? '';
    if (activePresetId.length <= 0) {
      return null;
    }
    const matched = remote.presets.find((preset: RemoteReadAloudPreset) => preset.id === activePresetId);
    return matched ?? null;
  }

  private isCurrentConfigMatchingPreset(preset: RemoteReadAloudPreset): boolean {
    const current = this.getRemoteCurrentConfig();
    if (isRemoteReadAloudPresetConfigEqual(current, preset.settings)) {
      return true;
    }
    if (!preset.builtIn) {
      return false;
    }
    return isRemoteReadAloudPresetConfigEqual(
      this.getRemoteConfigWithoutApiKey(current),
      this.getRemoteConfigWithoutApiKey(preset.settings)
    );
  }

  private getRemotePresetSummary(): string {
    const activePreset = this.getActiveRemotePreset();
    if (!activePreset) {
      return '当前配置尚未保存为预设';
    }
    if (this.isCurrentConfigMatchingPreset(activePreset)) {
      return `当前预设：${activePreset.name}`;
    }
    return `当前基于“${activePreset.name}”修改`;
  }

  private buildRemotePresetDescriptionFromCurrentConfig(): string {
    const remote = this.getRemoteSettings();
    if (remote.endpoint.toLowerCase().includes('xiaomimimo.com') || remote.model.toLowerCase() === 'mimo-v2-tts') {
      const stylePrompt = this.getRemoteStylePrompt();
      const voiceLabel = this.getRemoteVoiceLabel(remote.voice);
      return stylePrompt.length > 0
        ? `基于 Xiaomi MiMo-V2-TTS 接口 / ${voiceLabel} / ${stylePrompt}`
        : `基于 Xiaomi MiMo-V2-TTS 接口 / ${voiceLabel}`;
    }
    const model = remote.model.trim().length > 0 ? remote.model.trim() : '自定义模型';
    const voice = this.getRemoteVoiceLabel(remote.voice);
    return `${model} / ${voice}`;
  }

  private generateRemotePresetId(): string {
    return `remote_preset_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }

  private canEditActiveRemotePreset(): boolean {
    const activePreset = this.getActiveRemotePreset();
    return activePreset !== null && activePreset.builtIn !== true;
  }

  private buildRemoteSettingsUpdate(
    config: RemoteReadAloudPresetConfig,
    activePresetId: string,
    presets?: RemoteReadAloudPreset[]
  ): Partial<RemoteReadAloudSettings> {
    const update: Partial<RemoteReadAloudSettings> = {
      endpoint: config.endpoint,
      apiPath: config.apiPath,
      apiKey: config.apiKey,
      model: config.model,
      voice: config.voice,
      stylePrompt: config.stylePrompt,
      audioFormat: config.audioFormat,
      streamEnabled: config.streamEnabled,
      prefetchSegments: config.prefetchSegments,
      connectTimeoutMs: config.connectTimeoutMs,
      readTimeoutMs: config.readTimeoutMs,
      maxInputChars: config.maxInputChars,
      reservedInputChars: config.reservedInputChars,
      minChunkChars: config.minChunkChars,
      targetChunkChars: config.targetChunkChars,
      maxChunkChars: config.maxChunkChars,
      cacheAudioFiles: config.cacheAudioFiles,
      autoConcatAudio: config.autoConcatAudio,
      customHeadersJson: config.customHeadersJson,
      extraBodyJson: config.extraBodyJson,
      activePresetId
    };
    if (presets !== undefined) {
      update.presets = presets;
    }
    return update;
  }

  private saveRemotePresetAsNew(): void {
    const name = this.remotePresetDraftName.trim().length > 0 ? this.remotePresetDraftName.trim() : '新的远程预设';
    const current = this.getRemoteSettings();
    const nextPreset: RemoteReadAloudPreset = {
      id: this.generateRemotePresetId(),
      name,
      description: this.buildRemotePresetDescriptionFromCurrentConfig(),
      builtIn: false,
      settings: this.getRemoteCurrentConfig()
    };
    const nextPresets = current.presets.slice();
    nextPresets.push(nextPreset);
    this.updateRemoteSettings(this.buildRemoteSettingsUpdate(nextPreset.settings, nextPreset.id, nextPresets));
    this.remotePresetDraftName = name;
    this.remotePresetStatusMessage = `已保存预设：${name}`;
  }

  private updateCurrentRemotePreset(): void {
    const activePreset = this.getActiveRemotePreset();
    if (!activePreset || activePreset.builtIn) {
      this.saveRemotePresetAsNew();
      return;
    }
    const name = this.remotePresetDraftName.trim().length > 0 ? this.remotePresetDraftName.trim() : activePreset.name;
    const nextPresets = this.getRemoteSettings().presets.map((preset: RemoteReadAloudPreset) => {
      if (preset.id !== activePreset.id) {
        return preset;
      }
      return {
        id: preset.id,
        name,
        description: this.buildRemotePresetDescriptionFromCurrentConfig(),
        builtIn: false,
        settings: this.getRemoteCurrentConfig()
      };
    });
    this.updateRemoteSettings({
      activePresetId: activePreset.id,
      presets: nextPresets
    });
    this.remotePresetDraftName = name;
    this.remotePresetStatusMessage = `已更新预设：${name}`;
  }

  private applyRemotePreset(preset: RemoteReadAloudPreset): void {
    const currentRemote = this.getRemoteSettings();
    const presetApiKey = preset.settings.apiKey ?? '';
    const shouldPreserveApiKey = preset.builtIn === true &&
      presetApiKey.trim().length <= 0 &&
      currentRemote.apiKey.trim().length > 0;
    const appliedConfig: RemoteReadAloudPresetConfig = {
      endpoint: preset.settings.endpoint,
      apiPath: preset.settings.apiPath,
      apiKey: shouldPreserveApiKey ? currentRemote.apiKey : presetApiKey,
      model: preset.settings.model,
      voice: preset.settings.voice,
      stylePrompt: preset.settings.stylePrompt,
      audioFormat: preset.settings.audioFormat,
      streamEnabled: preset.settings.streamEnabled,
      prefetchSegments: preset.settings.prefetchSegments,
      connectTimeoutMs: preset.settings.connectTimeoutMs,
      readTimeoutMs: preset.settings.readTimeoutMs,
      maxInputChars: preset.settings.maxInputChars,
      reservedInputChars: preset.settings.reservedInputChars,
      minChunkChars: preset.settings.minChunkChars,
      targetChunkChars: preset.settings.targetChunkChars,
      maxChunkChars: preset.settings.maxChunkChars,
      cacheAudioFiles: preset.settings.cacheAudioFiles,
      autoConcatAudio: preset.settings.autoConcatAudio,
      customHeadersJson: preset.settings.customHeadersJson,
      extraBodyJson: preset.settings.extraBodyJson
    };
    if (shouldPreserveApiKey) {
      logger.info(TAG, `应用内置远程预设时保留现有 API Key: presetId=${preset.id}, keyLength=${currentRemote.apiKey.length}`);
    }
    this.updateRemoteSettings(this.buildRemoteSettingsUpdate(appliedConfig, preset.id));
    this.remotePresetDraftName = preset.name;
    this.remotePresetStatusMessage = `已应用预设：${preset.name}`;
  }

  private deleteCurrentRemotePreset(): void {
    const activePreset = this.getActiveRemotePreset();
    if (!activePreset) {
      this.remotePresetStatusMessage = '当前没有可删除的预设';
      return;
    }
    if (activePreset.builtIn) {
      this.remotePresetStatusMessage = '内置预设不可删除';
      return;
    }
    const current = this.getRemoteSettings();
    const nextPresets = current.presets.filter((preset: RemoteReadAloudPreset) => preset.id !== activePreset.id);
    const fallbackPreset = nextPresets.find((preset: RemoteReadAloudPreset) => preset.id === DEFAULT_REMOTE_READ_ALOUD_PRESET_ID) ??
      (nextPresets.length > 0 ? nextPresets[0] : null);
    if (fallbackPreset) {
      this.updateRemoteSettings(this.buildRemoteSettingsUpdate(fallbackPreset.settings, fallbackPreset.id, nextPresets));
      this.remotePresetDraftName = fallbackPreset.name;
    } else {
      this.updateRemoteSettings({
        activePresetId: '',
        presets: nextPresets
      });
      this.remotePresetDraftName = '';
    }
    this.remotePresetStatusMessage = `已删除预设：${activePreset.name}`;
  }

  private parseIntegerInput(text: string, fallback: number, min: number, max: number): number {
    const parsed = Math.floor(Number(text));
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(min, Math.min(max, parsed));
  }

  @Builder
  private buildRemoteTextInput(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: value, placeholder })
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
        .height(36)
        .padding({ left: 10, right: 10 })
        .width('100%')
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildRemoteNumberInput(
    label: string,
    value: number,
    min: number,
    max: number,
    onChange: (value: number) => void
  ) {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`${value}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent_primary'))
      }
      .width('100%')
      TextInput({ text: `${value}`, placeholder: `${min}-${max}` })
        .type(InputType.Number)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
        .height(36)
        .padding({ left: 10, right: 10 })
        .width('100%')
        .onChange((nextValue: string) => {
          onChange(this.parseIntegerInput(nextValue, value, min, max));
        })
    }
    .width('100%')
  }

  @Builder
  private buildRemoteJsonInput(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ text: value, placeholder })
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
        .padding(10)
        .height(88)
        .width('100%')
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildRemoteChoiceChip(label: string, selected: boolean, onClick: () => void) {
    Button() {
      Row({ space: 6 }) {
        if (selected) {
          Text('✓')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
            .width(16)
            .height(16)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.accent_primary'))
            .borderRadius(8)
        }
        Text(label)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(selected ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
      }
    }
      .height(34)
      .padding({ left: selected ? 10 : 12, right: 12 })
      .backgroundColor(selected ? $r('app.color.accent_background') : $r('app.color.background_secondary'))
      .border({
        width: 1,
        color: selected ? $r('app.color.accent_primary') : $r('app.color.divider')
      })
      .borderRadius(17)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private buildMiMoRemoteVoiceSelector() {
    Column({ space: 8 }) {
      Text('MiMo 预设音色')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text(`当前选择：${getXiaomiMimoRemoteReadAloudVoiceLabel(this.getRemoteSettings().voice)}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent_primary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        ForEach(XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS, (option: RemoteReadAloudChoiceOption) => {
          this.buildRemoteChoiceChip(
            option.label,
            this.getRemoteSettings().voice.trim() === option.value,
            () => this.updateRemoteSettings({ voice: option.value })
          )
        }, (option: RemoteReadAloudChoiceOption) => `mimo_voice_${option.value}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildMiMoRemoteStyleSelector() {
    Column({ space: 8 }) {
      Text(`MiMo 风格控制${this.getRemoteStyleSelectionCount() > 0 ? ` · 已选 ${this.getRemoteStyleSelectionCount()}` : ''}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text('可直接多选多个风格，也可手动输入；发送时会自动转成 <style>风格...</style> 正文。')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.getRemoteStylePrompt().length > 0) {
        Text(`已选风格：${this.getRemoteStylePrompt()}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent_primary'))
          .width('100%')
      }
      ForEach(XIAOMI_MIMO_REMOTE_READ_ALOUD_STYLE_CATEGORIES, (category: RemoteReadAloudStyleCategory) => {
        Column({ space: 6 }) {
          Text(category.label)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
            ForEach(category.styles, (style: string) => {
              this.buildRemoteChoiceChip(style, this.isRemoteStyleSelected(style), () => {
                this.toggleRemoteStyle(style);
              })
            }, (style: string) => `mimo_style_${category.label}_${style}`)
          }
          .width('100%')
        }
        .width('100%')
      }, (category: RemoteReadAloudStyleCategory) => `mimo_style_category_${category.label}`)
      this.buildRemoteTextInput(
        '自定义风格',
        this.getRemoteStylePrompt(),
        '如 开心 东北话',
        (value: string) => this.updateRemoteSettings({ stylePrompt: value })
      )
      if (this.getRemoteStylePrompt().length > 0) {
        Text(`实际发送：<style>${this.getRemoteStylePrompt()}</style>待合成内容`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent_primary'))
          .width('100%')
      }
    }
    .width('100%')
  }

  private getCurrentEngineLabel(): string {
    if (this.settings.engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return '兼容渠道';
    }
    if (this.settings.engineType === ReadAloudEngineType.REMOTE) {
      return '远程 TTS';
    }
    return '系统 TTS';
  }

  private getCurrentEngineAvailabilityText(): string {
    return this.isReadAloudEngineAvailable(this.settings.engineType) ? '可用' : '需配置';
  }

  private getCurrentEngineAvailabilityColor() {
    return this.isReadAloudEngineAvailable(this.settings.engineType)
      ? '#16A34A'
      : '#F59E0B';
  }

  private getRemoteStyleSelectionCount(): number {
    return splitRemoteReadAloudStylePrompt(this.getRemoteStylePrompt()).length;
  }

  @Builder
  private buildEngineTabBar() {
    Row({ space: 0 }) {
      ForEach(READ_ALOUD_ENGINE_OPTIONS, (item: ReadAloudEngineOption) => {
        Row({ space: 6 }) {
          Text(item.label)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(
              this.settings.engineType === item.engine
                ? $r('app.color.text_primary')
                : $r('app.color.text_secondary')
            )
          Circle()
            .width(6)
            .height(6)
            .fill(this.isReadAloudEngineAvailable(item.engine) ? '#16A34A' : '#94A3B8')
        }
        .padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(
          this.settings.engineType === item.engine
            ? $r('app.color.background_primary')
            : $r('app.color.background_secondary')
        )
        .border({
          width: {
            top: this.settings.engineType === item.engine ? 2 : 0,
            bottom: 0,
            left: 0,
            right: 0
          },
          color: $r('app.color.accent_primary')
        })
        .onClick(() => {
          if (this.settings.engineType === item.engine) {
            return;
          }
          logger.info(TAG, `切换听书渠道页签: ${this.settings.engineType} -> ${item.engine}`);
          this.finishPreviewSession(this.previewSessionToken, '', false);
          this.previewStatusMessage = '';
          this.callbacks.onChange({ engineType: item.engine });
        })
        .animation({ duration: 150 })
      }, (item: ReadAloudEngineOption) => `engine_tab_${item.engine}`)
    }
    .width('100%')
  }

  @Builder
  private buildCurrentEngineStatusCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(`当前渠道：${this.getCurrentEngineLabel()}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Text(this.getCurrentEngineAvailabilityText())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getCurrentEngineAvailabilityColor())
      }
      .width('100%')

      if (!this.isReadAloudEngineAvailable(this.settings.engineType)) {
        Text(this.getReadAloudUnavailableDetail(this.settings.engineType))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.previewStatusMessage.length > 0) {
        Text(this.previewStatusMessage)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent_primary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private buildCompatEngineSection() {
    Column({ space: 8 }) {
      Text('兼容渠道')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text('该渠道复用系统 TTS 播放链路，重点用于兼容 legado 风格听书流程；音色预览建议在“系统”标签中设置。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildSystemEngineSection() {
    Column({ space: 6 }) {
      Text('可用音色（预览）')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.voiceOptions.length > 0) {
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
  }

  @Builder
  private buildRemoteEngineSection() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Text('远程 TTS 预设')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.getRemotePresetSummary())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        ForEach(
          this.getRemoteSettings().presets,
          (preset: RemoteReadAloudPreset) => {
            Column({ space: 6 }) {
              Button(
                `${preset.name}${this.getRemoteSettings().activePresetId === preset.id ? ' · 当前' : ''}`
              )
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .height(36)
                .width('100%')
                .backgroundColor(
                  this.getRemoteSettings().activePresetId === preset.id
                    ? $r('app.color.accent_primary')
                    : $r('app.color.background_secondary')
                )
                .fontColor(
                  this.getRemoteSettings().activePresetId === preset.id
                    ? Color.White
                    : $r('app.color.text_primary')
                )
                .onClick(() => {
                  this.applyRemotePreset(preset);
                })

              if (preset.description.length > 0) {
                Text(preset.description)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }
            .width('100%')
          },
          (preset: RemoteReadAloudPreset) => preset.id
        )

        this.buildRemoteTextInput(
          '预设名称',
          this.remotePresetDraftName,
          '输入预设名称后保存',
          (value: string) => {
            this.remotePresetDraftName = value;
          }
        )

        Row({ space: 8 }) {
          Button('保存为新预设')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.saveRemotePresetAsNew();
            })

          Button('更新当前预设')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .enabled(this.canEditActiveRemotePreset())
            .onClick(() => {
              this.updateCurrentRemotePreset();
            })

          Button('删除当前预设')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .enabled(this.canEditActiveRemotePreset())
            .onClick(() => {
              this.deleteCurrentRemotePreset();
            })
        }
        .width('100%')

        if (this.remotePresetStatusMessage.length > 0) {
          Text(this.remotePresetStatusMessage)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.accent_primary'))
            .width('100%')
        }
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Divider().color($r('app.color.divider'))

      Column({ space: 10 }) {
        Text('远程 TTS 参数')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text('以下配置会持久化保存，切换到“远程”标签时立即生效')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        this.buildRemoteTextInput(
          'Endpoint',
          this.getRemoteSettings().endpoint,
          'https://api.xiaomimimo.com',
          (value: string) => this.updateRemoteSettings({ endpoint: value.trim() })
        )
        this.buildRemoteTextInput(
          'API Path',
          this.getRemoteSettings().apiPath,
          '/v1/chat/completions',
          (value: string) => this.updateRemoteSettings({ apiPath: value.trim() })
        )
        this.buildRemoteTextInput(
          'API Key',
          this.getRemoteSettings().apiKey,
          '请输入 Xiaomi MiMo API Key',
          (value: string) => this.updateRemoteSettings({ apiKey: value })
        )
        this.buildRemoteTextInput(
          'Model',
          this.getRemoteSettings().model,
          'mimo-v2-tts',
          (value: string) => this.updateRemoteSettings({ model: value.trim() })
        )
        if (this.isMiMoRemoteSettings()) {
          this.buildMiMoRemoteVoiceSelector()
          this.buildMiMoRemoteStyleSelector()
        }
        this.buildRemoteTextInput(
          'Voice',
          this.getRemoteSettings().voice,
          this.isMiMoRemoteSettings() ? 'mimo_default / default_zh / default_en' : '输入 voice 参数',
          (value: string) => this.updateRemoteSettings({ voice: value.trim() })
        )
        this.buildRemoteTextInput(
          'Audio Format',
          this.getRemoteSettings().audioFormat,
          'wav',
          (value: string) => this.updateRemoteSettings({ audioFormat: value.trim() })
        )

        this.buildToggleRow('启用流式响应', this.getRemoteSettings().streamEnabled, (value: boolean) => {
          this.updateRemoteSettings({ streamEnabled: value });
        })
        this.buildToggleRow('缓存音频文件', this.getRemoteSettings().cacheAudioFiles, (value: boolean) => {
          this.updateRemoteSettings({ cacheAudioFiles: value });
        })
        this.buildToggleRow('章节自动拼接', this.getRemoteSettings().autoConcatAudio, (value: boolean) => {
          this.updateRemoteSettings({ autoConcatAudio: value });
        })

        this.buildRemoteNumberInput(
          '预取分片数量',
          this.getRemoteSettings().prefetchSegments,
          1,
          8,
          (value: number) => this.updateRemoteSettings({ prefetchSegments: value })
        )
        this.buildRemoteNumberInput(
          '连接超时(ms)',
          this.getRemoteSettings().connectTimeoutMs,
          3000,
          120000,
          (value: number) => this.updateRemoteSettings({ connectTimeoutMs: value })
        )
        this.buildRemoteNumberInput(
          '读取超时(ms)',
          this.getRemoteSettings().readTimeoutMs,
          5000,
          300000,
          (value: number) => this.updateRemoteSettings({ readTimeoutMs: value })
        )
        this.buildRemoteNumberInput(
          '最大输入字符',
          this.getRemoteSettings().maxInputChars,
          256,
          12000,
          (value: number) => this.updateRemoteSettings({ maxInputChars: value })
        )
        this.buildRemoteNumberInput(
          '保留字符预算',
          this.getRemoteSettings().reservedInputChars,
          0,
          2000,
          (value: number) => this.updateRemoteSettings({ reservedInputChars: value })
        )
        this.buildRemoteNumberInput(
          '最小分片字符',
          this.getRemoteSettings().minChunkChars,
          32,
          5000,
          (value: number) => this.updateRemoteSettings({ minChunkChars: value })
        )
        this.buildRemoteNumberInput(
          '目标分片字符',
          this.getRemoteSettings().targetChunkChars,
          64,
          7000,
          (value: number) => this.updateRemoteSettings({ targetChunkChars: value })
        )
        this.buildRemoteNumberInput(
          '最大分片字符',
          this.getRemoteSettings().maxChunkChars,
          80,
          9000,
          (value: number) => this.updateRemoteSettings({ maxChunkChars: value })
        )

        this.buildRemoteJsonInput(
          '自定义请求头(JSON)',
          this.getRemoteSettings().customHeadersJson,
          '{"X-Client":"ManXia"}',
          (value: string) => this.updateRemoteSettings({ customHeadersJson: value })
        )
        this.buildRemoteJsonInput(
          '额外请求体(JSON)',
          this.getRemoteSettings().extraBodyJson,
          '{"temperature":0.6}',
          (value: string) => this.updateRemoteSettings({ extraBodyJson: value })
        )
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
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
          this.buildEngineTabBar()
          this.buildCurrentEngineStatusCard()

          if (this.settings.engineType === ReadAloudEngineType.SYSTEM) {
            this.buildSystemEngineSection()
          } else if (this.settings.engineType === ReadAloudEngineType.LEGADO_COMPAT) {
            this.buildCompatEngineSection()
          } else {
            this.buildRemoteEngineSection()
          }

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
