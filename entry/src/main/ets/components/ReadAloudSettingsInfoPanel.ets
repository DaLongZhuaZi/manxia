import { curves, UIContext } from '@kit.ArkUI';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
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

  private uiContext: UIContext | undefined = undefined;

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    this.callbacks.onRefresh();
    this.showPanel();
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
    const language = voice.language.length > 0 ? voice.language : 'unknown';
    const channel = voice.online === 1 ? '在线' : '离线';
    return `${language} / ${channel} / 声线${voice.person}`;
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
    this.callbacks.onChange({
      voiceLanguage: '',
      voicePerson: -1,
      voiceOnline: -1
    });
  }

  private selectVoiceOption(voice: ReadAloudVoiceOption): void {
    this.callbacks.onChange({
      voiceLanguage: voice.language,
      voicePerson: voice.person,
      voiceOnline: voice.online
    });
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
                      return;
                    }
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
                })

              ForEach(
                this.voiceOptions,
                (voice: ReadAloudVoiceOption) => {
                  Button(this.getReadAloudVoiceLabel(voice))
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .height(36)
                    .width('100%')
                    .backgroundColor(this.isVoiceSelected(voice) ? $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                    .fontColor(this.isVoiceSelected(voice) ? Color.White : $r('app.color.text_primary'))
                    .onClick(() => {
                      this.selectVoiceOption(voice);
                    })
                },
                (voice: ReadAloudVoiceOption) => voice.id
              )
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
