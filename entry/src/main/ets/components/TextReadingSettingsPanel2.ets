/**
 * 阅读设置面板（新版）
  * 包含阅读模式与听书相关配置。
  * 仅处理 UI 交互，不直接执行业务逻辑。
 */

import {
  TextReaderSettings,
  TextReadingMode,
  TextPageTurnAnimation,
  ReadAloudEngineType,
  ReadAloudSettings,
  DEFAULT_READ_ALOUD_SETTINGS,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings
} from '../Models/TextReaderModels';
import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { curves, UIContext, display } from '@kit.ArkUI';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { ReadAloudSettingsInfoPanel } from './ReadAloudSettingsInfoPanel';

const TAG = 'TextReadingSettingsPanel2';

/**
  * 翻页动画选项定义
 */
interface AnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

/**
 * 设置变更回调
 */
interface TextReadingSettingsCallbacks {
  onSettingsChange: (settings: TextReaderSettings) => void;
  onClose: () => void;
}

@Component
export struct TextReadingSettingsPanel2 {
  @Prop settings: TextReaderSettings;
  @Prop isVisible: boolean;
  @Prop initialShowReadAloudPanel: boolean = false;
  @Prop callbacks: TextReadingSettingsCallbacks;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 面板动效状态
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;
  @State private readAloudAvailability: ReadAloudEngineAvailabilityMap = ReadAloudAvailability.getCachedOrDefault();
  @State private readAloudVoiceOptions: ReadAloudVoiceOption[] = [];
  @State private showReadAloudPanel: boolean = false;
  @State private readAloudStatusMessage: string = '';
  @State private isClosing: boolean = false;

  private uiContext: UIContext | undefined = undefined;
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    this.detectScreenOrientation();
    this.refreshReadAloudAvailability();
    this.showReadAloudPanel = this.initialShowReadAloudPanel;

    ThemeAwareHelper.initializeThemeAware('TextReadingSettingsPanel2', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    setTimeout(() => {
      this.showPanel();
    }, 50);
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware('TextReadingSettingsPanel2');
  }

  private detectScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (displayInfo) {
        const w = displayInfo.width / (displayInfo.densityPixels || 1);
        const h = displayInfo.height / (displayInfo.densityPixels || 1);
        this.isLandscape = w > h;
      }
    } catch (error) {
      logger.error(TAG, `屏幕方向检测失败: ${String(error)}`);
    }
  }

  private showPanel(): void {
    if (!this.uiContext) {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.panelTranslateX = 0;
      this.backdropOpacity = 0.5;
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

  private hidePanel(): void {
    if (this.isClosing) {
      return;
    }
    this.isClosing = true;

    if (!this.uiContext) {
      this.panelOpacity = 0;
      this.panelTranslateY = 300;
      this.panelTranslateX = 320;
      this.backdropOpacity = 0;
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

  private notifyChange(): void {
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.settings);
    }
  }

  private getAutoPageTurnEnabled(): boolean {
    return this.settings.autoPageTurnEnabled === true;
  }

  private getAutoPageTurnInterval(): number {
    const rawInterval = this.settings.autoPageTurnInterval;
    if (typeof rawInterval !== 'number' || rawInterval <= 0) {
      return 8;
    }
    return Math.max(1, Math.min(60, Math.round(rawInterval)));
  }

  private setAutoPageTurnEnabled(enabled: boolean): void {
    this.settings.autoPageTurnEnabled = enabled;
    if (typeof this.settings.autoPageTurnInterval !== 'number' || this.settings.autoPageTurnInterval <= 0) {
      this.settings.autoPageTurnInterval = 8;
    }
    this.notifyChange();
  }

  private setAutoPageTurnInterval(value: number): void {
    const interval = Math.max(1, Math.min(60, Math.round(value)));
    this.settings.autoPageTurnInterval = interval;
    this.notifyChange();
  }

  private getSafeReadAloudSettings(): ReadAloudSettings {
    return normalizeReadAloudSettings(this.settings.readAloud ?? DEFAULT_READ_ALOUD_SETTINGS);
  }

  private updateReadAloudSettings(partial: Partial<ReadAloudSettings>): void {
    const current = this.getSafeReadAloudSettings();
    const currentRemote = current.remote;
    const partialRemote = partial.remote;
    let mergedRemote = currentRemote;
    if (partialRemote && currentRemote) {
      mergedRemote = mergeRemoteReadAloudSettings(currentRemote, partialRemote);
    }
    this.settings.readAloud = normalizeReadAloudSettings({
      enabled: partial.enabled ?? current.enabled,
      engineType: partial.engineType ?? current.engineType,
      speed: partial.speed ?? current.speed,
      pitch: partial.pitch ?? current.pitch,
      volume: partial.volume ?? current.volume,
      continueInBackground: partial.continueInBackground ?? current.continueInBackground,
      autoPlayNextChapter: partial.autoPlayNextChapter ?? current.autoPlayNextChapter,
      pauseOnManualPageTurn: partial.pauseOnManualPageTurn ?? current.pauseOnManualPageTurn,
      voiceLanguage: partial.voiceLanguage ?? current.voiceLanguage,
      voicePerson: partial.voicePerson ?? current.voicePerson,
      voiceOnline: partial.voiceOnline ?? current.voiceOnline,
      remote: mergedRemote
    });
    this.notifyChange();
    const shouldRefreshAvailability = partial.engineType !== undefined || partial.remote !== undefined;
    if (shouldRefreshAvailability) {
      this.refreshReadAloudAvailability();
      return;
    }
    if (
      partial.voiceLanguage !== undefined ||
      partial.voicePerson !== undefined ||
      partial.voiceOnline !== undefined
    ) {
      this.refreshReadAloudVoices();
    }
  }

  // ==================== 听书引擎可用性 ====================
  private refreshReadAloudAvailability(): void {
    ReadAloudAvailability.refresh(false, this.getSafeReadAloudSettings()).then((map: ReadAloudEngineAvailabilityMap) => {
      this.readAloudAvailability = map;
      if (!map.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `系统 TTS 探测失败：${probeError}`;
        }
      }
      if (!map.REMOTE && this.getSafeReadAloudSettings().engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `远程 TTS 不可用：${probeError}`;
        }
      }
      this.refreshReadAloudVoices();
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新听书引擎可用性失败: ${errorText}`);
      this.readAloudStatusMessage = `引擎可用性探测失败：${errorText}`;
    });
  }

  private isReadAloudEngineAvailable(engineType: ReadAloudEngineType): boolean {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return this.readAloudAvailability.SYSTEM === true;
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return this.readAloudAvailability.LEGADO_COMPAT === true;
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      return this.readAloudAvailability.REMOTE === true;
    }
    return false;
  }

  private refreshReadAloudVoices(): void {
    const engineType = this.getSafeReadAloudSettings().engineType;
    if (!this.isReadAloudEngineAvailable(engineType)) {
      this.readAloudVoiceOptions = [];
      if (engineType === ReadAloudEngineType.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `系统 TTS 探测失败：${probeError}`;
        } else {
          this.readAloudStatusMessage = '系统 TTS 当前不可用，请点击刷新重试';
        }
      } else if (engineType === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.readAloudStatusMessage = `远程 TTS 不可用：${probeError}`;
        } else {
          this.readAloudStatusMessage = '远程 TTS 当前不可用，请检查 endpoint/model/voice/apiKey';
        }
      } else {
        this.readAloudStatusMessage = '当前引擎不可用，请切换到“系统”或点击刷新重试';
      }
      return;
    }
    this.readAloudController.listVoices(engineType).then((voices: ReadAloudVoiceOption[]) => {
      this.readAloudVoiceOptions = voices;
      if (voices.length > 0) {
        this.readAloudStatusMessage = '';
      } else if (engineType === ReadAloudEngineType.SYSTEM) {
        this.readAloudStatusMessage = '系统 TTS 可直接朗读，但系统未返回可选音色';
      } else {
        this.readAloudStatusMessage = '当前引擎暂未返回音色列表';
      }
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新听书音色列表失败: ${errorText}`);
      this.readAloudVoiceOptions = [];
      this.readAloudStatusMessage = `音色列表拉取失败：${errorText}`;
    });
  }

  private formatReadAloudError(error: Object | string): string {
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

  private getReadAloudSummary(): string {
    const readAloud = this.getSafeReadAloudSettings();
    let engineLabel: string = '系统';
    if (readAloud.engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      engineLabel = '兼容';
    } else if (readAloud.engineType === ReadAloudEngineType.REMOTE) {
      engineLabel = '远程';
    }
    const enabledText = readAloud.enabled ? '已启用' : '未启用';
    return `${enabledText} · ${engineLabel} · 语速${readAloud.speed.toFixed(1)}x`;
  }

  @Builder
  buildPortraitPanel() {
    Column() {
      Row() {
        Text('阅读设置')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.hidePanel())
      }
      .width('100%')
      .margin({ bottom: 16 })

      Scroll() {
        Column({ space: 20 }) {
          this.buildReadingContent()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        Button('完成')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .layoutWeight(1)
          .height(40)
          .onClick(() => this.hidePanel())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: '75%' })
    .padding(20)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .opacity(this.panelOpacity)
    .translate({ x: 0, y: this.panelTranslateY })
    .position({ x: 0, y: '100%' })
    .translate({ x: 0, y: '-100%' })
    .hitTestBehavior(HitTestMode.Default)
  }

  // 横屏面板
  @Builder
  buildLandscapePanel() {
    Row() {
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.hidePanel())

      Column() {
        Row() {
          Text('阅读设置')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.hidePanel())
        }
        .width('100%')
        .margin({ bottom: 12 })

        Scroll() {
          Column({ space: 12 }) {
            this.buildReadingContentCompact()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Button('完成')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .width('100%')
          .height(36)
          .onClick(() => this.hidePanel())
      }
      .width(320)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  // 阅读设置内容（常规）
  @Builder
  buildReadingContent() {
    // 阅读模式
    Column({ space: 12 }) {
      Text('阅读模式')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Column() {
        Text('翻页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.PAGE;
          this.notifyChange();
        })

        Column() {
          Text('上下滚动')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.SCROLL ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.SCROLL ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.SCROLL;
          this.notifyChange();
        })

        Column() {
        Text('双页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.DUAL_PAGE;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    // 仅在翻页/双页模式下显示翻页动画设置
    if (this.settings.readingMode === TextReadingMode.PAGE || this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
      Column({ space: 12 }) {
        Text('翻页动画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 8 }) {
          ForEach(
            [
              { text: '无', anim: TextPageTurnAnimation.NONE },
              { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
              { text: '卷曲', anim: TextPageTurnAnimation.CURL },
              { text: '淡入', anim: TextPageTurnAnimation.FADE }
            ],
            (item: AnimationOption) => {
              Column() {
                Text(item.text)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.settings.pageTurnAnimation === item.anim ?
                    $r('app.color.accent') : $r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.settings.pageTurnAnimation === item.anim ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(8)
              .onClick(() => {
                this.settings.pageTurnAnimation = item.anim;
                this.notifyChange();
              })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
    }

    Column({ space: 10 }) {
      Text('右下角显示信息')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row() {
          Text('页码')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.getAutoPageTurnEnabled() })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.setAutoPageTurnEnabled(isOn);
          })
      }
      .width('100%')

      Text(`Auto page-turn interval: ${this.getAutoPageTurnInterval()} s`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Slider({
        value: this.getAutoPageTurnInterval(),
        min: 1,
        max: 60,
        step: 1
      })
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End) {
            this.setAutoPageTurnInterval(value);
          }
        })
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 基础阅读交互
    this.buildToggleSetting('点击翻页', this.settings.tapToTurn, (isOn: boolean) => {
      this.settings.tapToTurn = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('音量键翻页', this.settings.volumeKeyNavigation, (isOn: boolean) => {
      this.settings.volumeKeyNavigation = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('保持屏幕常亮', this.settings.keepScreenOn, (isOn: boolean) => {
      this.settings.keepScreenOn = isOn;
      this.notifyChange();
    })

    Divider().color($r('app.color.divider'))

    // 底部显示模式
    Column({ space: 8 }) {
        Text('底部显示模式')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('选择底部显示内容')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Column() {
      Text('页码')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.showPageNumber ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.showPageNumber ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = true;
          this.settings.showProgress = false;
          this.notifyChange();
        })

        Column() {
            Text('进度')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(!this.settings.showPageNumber && this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = true;
          this.notifyChange();
        })

        Column() {
            Text('不显示')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && !this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(!this.settings.showPageNumber && !this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = false;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 底部附加信息
    this.buildToggleSetting('显示时间（底部信息栏）', this.settings.showTime, (isOn: boolean) => {
      this.settings.showTime = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('显示电量（状态栏）', this.settings.showBattery, (isOn: boolean) => {
      this.settings.showBattery = isOn;
      this.notifyChange();
    })
  }

  @Builder
  buildToggleSetting(label: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.accent'))
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  // 阅读设置内容（紧凑）
  @Builder
  buildReadingContentCompact() {
    // 阅读模式
    Column() {
      Text('阅读模式')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        Column() {
            Text('翻页')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.PAGE;
          this.notifyChange();
        })

        Column() {
      Text('上下滚动')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.SCROLL ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.SCROLL ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.SCROLL;
          this.notifyChange();
        })

        Column() {
          Text('双页')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.DUAL_PAGE;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    // 仅在翻页/双页模式下显示翻页动画设置
    if (this.settings.readingMode === TextReadingMode.PAGE || this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
      Column() {
        Text('翻页动画')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 6 })

        Row({ space: 4 }) {
          ForEach(
            [
              { text: '无', anim: TextPageTurnAnimation.NONE },
              { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
              { text: '卷曲', anim: TextPageTurnAnimation.CURL },
              { text: '淡入', anim: TextPageTurnAnimation.FADE }
            ],
            (item: AnimationOption) => {
              Column() {
                Text(item.text)
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.settings.pageTurnAnimation === item.anim ?
                    $r('app.color.accent') : $r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .padding(8)
              .backgroundColor(this.settings.pageTurnAnimation === item.anim ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(6)
              .onClick(() => {
                this.settings.pageTurnAnimation = item.anim;
                this.notifyChange();
              })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
    }

    Column() {
          Text('无')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row() {
          Text('进度')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.getAutoPageTurnEnabled() })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.setAutoPageTurnEnabled(isOn);
          })
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(`${this.getAutoPageTurnInterval()} s/page`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 4 })

      Slider({
        value: this.getAutoPageTurnInterval(),
        min: 1,
        max: 60,
        step: 1
      })
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End) {
            this.setAutoPageTurnInterval(value);
          }
        })
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 其他显示开关
    Column() {
      Text('其他设置')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row() {
        Column() {
          Row() {
          Text('点击翻页')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.tapToTurn })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.tapToTurn = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('保持屏幕常亮')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.keepScreenOn })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.keepScreenOn = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
          Text('显示时间（底部信息栏）')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.showTime })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.showTime = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ right: 8 })

        Column() {
          Row() {
      Text('音量键翻页')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.volumeKeyNavigation })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.volumeKeyNavigation = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
      Text('显示电量（状态栏）')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.showBattery })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.showBattery = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 底部显示模式
    Column() {
          Text('底部模式')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        Column() {
          Text('页码')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.showPageNumber ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.showPageNumber ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = true;
          this.settings.showProgress = false;
          this.notifyChange();
        })

        Column() {
          Text('进度')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(!this.settings.showPageNumber && this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = true;
          this.notifyChange();
        })

        Column() {
      Text('不显示')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && !this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(!this.settings.showPageNumber && !this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = false;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
        if (this.showReadAloudPanel) {
          ReadAloudSettingsInfoPanel({
            isLandscape: this.isLandscape,
            settings: this.getSafeReadAloudSettings(),
            availability: this.readAloudAvailability,
            voiceOptions: this.readAloudVoiceOptions,
            statusMessage: this.readAloudStatusMessage,
            appFontFamily: this.appFontFamily,
            callbacks: {
              onClose: () => {
                this.showReadAloudPanel = false;
              },
              onRefresh: () => {
                this.refreshReadAloudAvailability();
              },
              onChange: (partial: Partial<ReadAloudSettings>) => {
                this.updateReadAloudSettings(partial);
              }
            }
          })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background_overlay'))
            .opacity(this.backdropOpacity)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.hidePanel();
            })

          if (this.isLandscape) {
            this.buildLandscapePanel()
          } else {
            this.buildPortraitPanel()
          }
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth > 0 && newHeight > 0) {
          this.isLandscape = newWidth > newHeight;
        }
      })
      .position({ x: 0, y: 0 })
    }
  }
}
