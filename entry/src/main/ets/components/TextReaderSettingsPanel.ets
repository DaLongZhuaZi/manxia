import { common } from '@kit.AbilityKit';
import { SafeFileUtils } from '../Utils/SafeFileUtils';
/**
 * 阅读设置面板
  * 统一管理字体、背景、阅读与听书选项。
  * 仅执行 UI 层状态变更与回调通知。
 */

import {
  TextReaderSettings,
  TextReadingMode,
  TextReadingDirection,
  TextPageTurnAnimation,
  TextAlignment,
  BackgroundType,
  CustomBackground,
  TextStyleSettings,
  PageMargins,
  PRESET_BACKGROUNDS,
  PresetBackground,
  SavedBackgroundImage,
  ReadAloudEngineType,
  ReadAloudSettings,
  DEFAULT_READ_ALOUD_SETTINGS,
  mergeRemoteReadAloudSettings,
  normalizeReadAloudSettings,
  DEFAULT_TEXT_STYLE,
  DEFAULT_PAGE_MARGINS,
  TEXT_READER_FONT_SIZE_MIN,
  TEXT_READER_FONT_SIZE_MAX,
  clampTextReaderFontSize
} from '../Models/TextReaderModels';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { logger } from '../Utils/Logger';
import { promptAction } from '@kit.ArkUI';
import { EBookDataManager, BackgroundImageInfo } from '../Framework/Data/EBookDataManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { getFontManager, SystemFont, CustomFont, FontType } from '../Framework/Managers/FontManager';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../Framework/ReadAloud/ReadAloudAvailability';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { ReadAloudVoiceOption } from '../Framework/ReadAloud/ReadAloudTypes';
import { ReadAloudSettingsInfoPanel } from './ReadAloudSettingsInfoPanel';

const TAG = 'TextReaderSettingsPanel';

/**
 * 文本对齐方式选项
 */
interface AlignmentOption {
  text: string;
  align: TextAlignment;
}

/**
  * 字重选项
 */
interface WeightOption {
  text: string;
  weight: number;
}

/**
  * 翻页动画选项
 */
interface AnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

/**
   * 设置分组
 */
enum SettingsTab {
  FONT = 'FONT',
  BACKGROUND = 'BACKGROUND',
  READING = 'READING'
}

@Component
export struct TextReaderSettingsPanel {
  /** 阅读设置 */
  @Link settings: TextReaderSettings;
  /** 关闭回调 */
  onClose: () => void = () => {};
  /** 设置变更回调 */
  onSettingsChange: (settings: TextReaderSettings) => void = () => {};
  /** 是否横屏 */
  @Prop isLandscape: boolean = false;
  
  /** 当前页签 */
  @State private currentTab: SettingsTab = SettingsTab.FONT;
  /** 刷新计数器（用于刷新预览） */
  @State private refreshCounter: number = 0;
  /** 预览文本 */
  private previewText: string = 'This is preview text for current font and background settings.';
  /** 所有可用背景图片 */
  @State private allAvailableBackgroundImages: BackgroundImageInfo[] = [];
  /** 是否显示“其他背景”选择器 */
  @State private showOtherBgImagePicker: boolean = false;
  /** 电子书数据管理器 */
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  /** 系统字体列表 */
  @State private systemFonts: SystemFont[] = [];
  /** 自定义字体列表 */
  @State private customFonts: CustomFont[] = [];
  /** 是否显示字体选择器 */
  @State private showFontPicker: boolean = false;
  /** 是否显示听书设置面板 */
  @State private showReadAloudPanel: boolean = false;
  @State private readAloudAvailability: ReadAloudEngineAvailabilityMap = ReadAloudAvailability.getCachedOrDefault();
  @State private readAloudVoiceOptions: ReadAloudVoiceOption[] = [];
  @State private readAloudStatusMessage: string = '';
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  
  aboutToAppear(): void {
    // 加载背景图片池
    this.loadAllAvailableBackgroundImages();
    // 加载字体列表
    this.loadFontLists();
    this.refreshReadAloudAvailability();
  }
  
  /**
   * 加载系统和自定义字体
   */
  private loadFontLists(): void {
    const fontManager = getFontManager();
    this.systemFonts = fontManager.getSystemFonts();
    this.customFonts = fontManager.getCustomFonts();
  }
  
  /**
    * 加载所有可用背景图片
   */
  private async loadAllAvailableBackgroundImages(): Promise<void> {
    try {
      const ebookImages = await this.ebookDataManager.getAllCustomBackgroundImages();
      
      const allImages: BackgroundImageInfo[] = [];
      const seenPaths = new Set<string>();
      
      // 优先加入全局背景图
      const settingsManager = SettingsManager.getInstance();
      const globalBgImagePath = settingsManager.getString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, '');
      if (globalBgImagePath && globalBgImagePath.length > 0) {
        seenPaths.add(globalBgImagePath);
        const globalBgInfo: BackgroundImageInfo = {
          bookId: 'global',
          bookTitle: '全局默认背景',
          imagePath: globalBgImagePath
        };
        allImages.push(globalBgInfo);
      }
      
      // 合并书籍背景图并去重
      for (const img of ebookImages) {
        if (!seenPaths.has(img.imagePath)) {
          seenPaths.add(img.imagePath);
          allImages.push(img);
        }
      }
      
      this.allAvailableBackgroundImages = allImages;
      logger.info(TAG, `加载到 ${this.allAvailableBackgroundImages.length} 张可用背景图片`);
    } catch (error) {
      logger.error(TAG, `加载背景图片列表失败: ${String(error)}`);
    }
  }
  
  /**
    * 更新设置并通知外部
    * 使用新对象触发响应式刷新
   */
  private updateAndNotify(): void {
    this.refreshCounter++;
    // 构建新对象，避免原地引用无法观测
    const newSettings: TextReaderSettings = {
      readingMode: this.settings.readingMode,
      readingDirection: this.settings.readingDirection,
      pageTurnAnimation: this.settings.pageTurnAnimation,
      background: {
        type: this.settings.background.type,
        color: this.settings.background.color,
        imagePath: this.settings.background.imagePath,
        imageOpacity: this.settings.background.imageOpacity
      },
      savedBackgroundImages: this.settings.savedBackgroundImages ? this.settings.savedBackgroundImages.slice() : [],
      textStyle: {
        fontSize: clampTextReaderFontSize(this.settings.textStyle.fontSize),
        lineHeight: this.settings.textStyle.lineHeight,
        paragraphSpacing: this.settings.textStyle.paragraphSpacing,
        firstLineIndent: this.settings.textStyle.firstLineIndent,
        letterSpacing: this.settings.textStyle.letterSpacing,
        textColor: this.settings.textStyle.textColor,
        fontWeight: this.settings.textStyle.fontWeight,
        fontFamily: this.settings.textStyle.fontFamily,
        textAlignment: this.settings.textStyle.textAlignment
      },
      pageMargins: {
        top: this.settings.pageMargins.top,
        bottom: this.settings.pageMargins.bottom,
        left: this.settings.pageMargins.left,
        right: this.settings.pageMargins.right
      },
      keepScreenOn: this.settings.keepScreenOn,
      lockDeviceOrientation: this.settings.lockDeviceOrientation ?? false,
      showPageNumber: this.settings.showPageNumber,
      showProgress: this.settings.showProgress,
      showTime: this.settings.showTime,
      showBattery: this.settings.showBattery,
      tapToTurn: this.settings.tapToTurn,
      volumeKeyNavigation: this.settings.volumeKeyNavigation,
      autoScrollSpeed: this.settings.autoScrollSpeed,
      autoPageTurnEnabled: this.settings.autoPageTurnEnabled,
      autoPageTurnInterval: this.settings.autoPageTurnInterval,
      curlBackOpacity: this.settings.curlBackOpacity,
      readAloud: this.getSafeReadAloudSettings()
    };
    this.settings = newSettings;
    this.onSettingsChange(newSettings);
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
    this.updateAndNotify();
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
    const settings = this.getSafeReadAloudSettings();
    let engineLabel: string = '系统';
    if (settings.engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      engineLabel = '兼容';
    } else if (settings.engineType === ReadAloudEngineType.REMOTE) {
      engineLabel = '远程';
    }
    const enabledText = settings.enabled ? '已启用' : '未启用';
    return `${enabledText} · ${engineLabel} · 语速${settings.speed.toFixed(1)}x`;
  }

  build() {
    Stack() {
      if (this.showReadAloudPanel) {
        ReadAloudSettingsInfoPanel({
          isLandscape: this.isLandscape,
          settings: this.getSafeReadAloudSettings(),
          availability: this.readAloudAvailability,
          voiceOptions: this.readAloudVoiceOptions,
          statusMessage: this.readAloudStatusMessage,
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
        Column() {
          // 标题栏
          Row() {
            Text('阅读设置')
              .fontSize(18)
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
            .onClick(() => this.onClose())
          }
          .width('100%')
          .padding({ left: 20, right: 12, top: 16, bottom: 12 })
          
          // 页签栏
          Row({ space: 0 }) {
            this.buildTabButton('字体', SettingsTab.FONT)
            this.buildTabButton('背景', SettingsTab.BACKGROUND)
            this.buildTabButton('阅读', SettingsTab.READING)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          
          Divider().color($r('app.color.divider'))
          
          // 设置内容
          Scroll() {
            Column({ space: 16 }) {
              if (this.currentTab === SettingsTab.FONT) {
                this.buildFontSettings()
              } else if (this.currentTab === SettingsTab.BACKGROUND) {
                this.buildBackgroundSettings()
              } else {
                this.buildReadingSettings()
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 20 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius({ topLeft: 16, topRight: 16 })
      }
    }
    .width('100%')
    .height('100%')
  }
  
  @Builder
  buildTabButton(title: string, tab: SettingsTab) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontColor(this.currentTab === tab ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
        .fontWeight(this.currentTab === tab ? FontWeight.Medium : FontWeight.Normal)
      
      if (this.currentTab === tab) {
        Divider()
          .width(24)
          .strokeWidth(2)
          .color($r('app.color.accent_primary'))
          .margin({ top: 4 })
      }
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 8 })
    .onClick(() => {
      this.currentTab = tab;
    })
  }
  
  /**
   * 字体设置
   */
  @Builder
  buildFontSettings() {
    // 利用 refreshCounter 强制刷新预览区
    Column({ space: 20 }) {
      // 字体预览
      Column() {
          Text('预览效果')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 8 })
        
        Text(this.previewText)
          .fontSize(clampTextReaderFontSize(this.settings.textStyle.fontSize))
          .lineHeight(clampTextReaderFontSize(this.settings.textStyle.fontSize) * this.settings.textStyle.lineHeight)
          .fontColor(this.settings.textStyle.textColor)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .width('100%')
          .padding(12)
          .backgroundColor(this.settings.background.type === BackgroundType.COLOR ? 
            this.settings.background.color || '#F5F0E1' : '#F5F0E1')
          .borderRadius(8)
      }
      .width('100%')
      .key(`preview_${this.refreshCounter}`)
      
      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text('字体大小')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${clampTextReaderFontSize(this.settings.textStyle.fontSize)}`)
            .fontSize(14)
            .fontColor($r('app.color.accent_primary'))
        }
        .width('100%')
        
        Row({ space: 12 }) {
          Button('A-')
            .fontSize(14)
            .width(48)
            .height(36)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              const nextFontSize = clampTextReaderFontSize(this.settings.textStyle.fontSize - 1);
              if (nextFontSize !== this.settings.textStyle.fontSize) {
                this.settings.textStyle.fontSize = nextFontSize;
                this.updateAndNotify();
              }
            })
          
          Slider({
            value: clampTextReaderFontSize(this.settings.textStyle.fontSize),
            min: TEXT_READER_FONT_SIZE_MIN,
            max: TEXT_READER_FONT_SIZE_MAX,
            step: 1
          })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.settings.textStyle.fontSize = clampTextReaderFontSize(value);
              this.updateAndNotify();
            })
          
          Button('A+')
            .fontSize(14)
            .width(48)
            .height(36)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              const nextFontSize = clampTextReaderFontSize(this.settings.textStyle.fontSize + 1);
              if (nextFontSize !== this.settings.textStyle.fontSize) {
                this.settings.textStyle.fontSize = nextFontSize;
                this.updateAndNotify();
              }
            })
        }
        .width('100%')
      }
      .width('100%')
      
      // 行高
      Column({ space: 8 }) {
        Row() {
        Text('行高')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${this.settings.textStyle.lineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontColor($r('app.color.accent_primary'))
        }
        .width('100%')
        
        Slider({
          value: this.settings.textStyle.lineHeight,
          min: 1.2,
          max: 3.0,
          step: 0.1
        })
          .width('100%')
          .onChange((value: number) => {
            this.settings.textStyle.lineHeight = Math.round(value * 10) / 10;
            this.updateAndNotify();
          })
      }
      .width('100%')
      
      // 页边距
      Column({ space: 8 }) {
        Row() {
          Text('页边距')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${this.settings.pageMargins.left}`)
            .fontSize(14)
            .fontColor($r('app.color.accent_primary'))
        }
        .width('100%')
        
        Slider({
          value: this.settings.pageMargins.left,
          min: 8,
          max: 64,
          step: 4
        })
          .width('100%')
          .onChange((value: number) => {
            const margin = Math.round(value);
            this.settings.pageMargins = {
              top: margin + 24,
              bottom: margin + 24,
              left: margin,
              right: margin
            };
            this.updateAndNotify();
          })
      }
      .width('100%')
      
      // 文字对齐
      Column({ space: 8 }) {
          Text('文字对齐')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        
        Row({ space: 8 }) {
          ForEach(
            [
              { text: '左对齐', align: TextAlignment.LEFT },
              { text: '居中', align: TextAlignment.CENTER },
              { text: '右对齐', align: TextAlignment.RIGHT },
              { text: '两端', align: TextAlignment.JUSTIFY }
            ],
            (item: AlignmentOption) => {
              Button(item.text)
                .fontSize(12)
                .height(32)
                .layoutWeight(1)
                .backgroundColor(this.settings.textStyle.textAlignment === item.align ? 
                  $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                .fontColor(this.settings.textStyle.textAlignment === item.align ? 
                  Color.White : $r('app.color.text_primary'))
                .onClick(() => {
                  this.settings.textStyle.textAlignment = item.align;
                  this.updateAndNotify();
                })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
      
      // 字重
      Column({ space: 8 }) {
        Row() {
            Text('字重')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${this.settings.textStyle.fontWeight}`)
            .fontSize(14)
            .fontColor($r('app.color.accent_primary'))
        }
        .width('100%')
        
        Row({ space: 8 }) {
          ForEach(
            [
              { text: '细', weight: 300 },
              { text: '常规', weight: 400 },
              { text: '中等', weight: 500 },
              { text: '粗', weight: 700 }
            ],
            (item: WeightOption) => {
              Button(item.text)
                .fontSize(12)
                .height(32)
                .layoutWeight(1)
                .backgroundColor(this.settings.textStyle.fontWeight === item.weight ? 
                  $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                .fontColor(this.settings.textStyle.fontWeight === item.weight ? 
                  Color.White : $r('app.color.text_primary'))
                .onClick(() => {
                  this.settings.textStyle.fontWeight = item.weight;
                  this.updateAndNotify();
                })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
      
      // 字体家族
      Column({ space: 8 }) {
        Row() {
              Text('字体')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.getCurrentFontDisplayName())
            .fontSize(14)
            .fontColor($r('app.color.accent_primary'))
        }
        .width('100%')
        .onClick(() => {
          this.showFontPicker = !this.showFontPicker;
        })
        
        if (this.showFontPicker) {
          Column({ space: 8 }) {
            // 系统字体列表
        Text('系统字体')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.systemFonts, (font: SystemFont) => {
                Button(font.displayName)
                  .fontSize(12)
                  .height(32)
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor(this.settings.textStyle.fontFamily === font.name ? 
                    $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                  .fontColor(this.settings.textStyle.fontFamily === font.name ? 
                    Color.White : $r('app.color.text_primary'))
                  .onClick(() => {
                    this.settings.textStyle.fontFamily = font.name;
                    this.settings.textStyle.fontPath = ''; // 使用系统字体时清空自定义字体路径
                    this.updateAndNotify();
                  })
              }, (font: SystemFont) => font.id)
            }
            .width('100%')
            
            // 自定义字体列表
            if (this.customFonts.length > 0) {
              Text('自定义字体')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ top: 8 })
              
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.customFonts, (font: CustomFont) => {
                  Button(font.displayName)
                    .fontSize(12)
                    .height(32)
                    .margin({ right: 8, bottom: 8 })
                    .backgroundColor(this.settings.textStyle.fontFamily === font.familyName ? 
                      $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                    .fontColor(this.settings.textStyle.fontFamily === font.familyName ? 
                      Color.White : $r('app.color.text_primary'))
                    .onClick(() => {
                      this.settings.textStyle.fontFamily = font.familyName;
                      this.settings.textStyle.fontPath = font.filePath;
                      this.updateAndNotify();
                    })
                }, (font: CustomFont) => font.id)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.background_secondary'))
          .borderRadius(8)
        }
      }
      .width('100%')
    }
    .width('100%')
  }
  
  /**
    * 获取当前字体显示名
   */
  private getCurrentFontDisplayName(): string {
    const currentFamily = this.settings.textStyle.fontFamily;
    
    // 优先匹配系统字体
    const systemFont = this.systemFonts.find(f => f.name === currentFamily);
    if (systemFont) {
      return systemFont.displayName;
    }
    
    // 再匹配自定义字体
    const customFont = this.customFonts.find(f => f.familyName === currentFamily);
    if (customFont) {
      return customFont.displayName;
    }
    
    return '系统默认';
  }
  
  /**
   * 背景设置
   */
  @Builder
  buildBackgroundSettings() {
    Column({ space: 20 }) {
      // 预设背景主题
      Column({ space: 12 }) {
        Text('可在此设置当前书籍背景，也可从其他书籍已保存背景中进行选择')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(PRESET_BACKGROUNDS, (preset: PresetBackground) => {
            Column() {
              Text('Aa')
                .fontSize(14)
                .fontColor(preset.textColor)
            }
            .width(52)
            .height(40)
            .backgroundColor(preset.backgroundColor)
            .borderRadius(8)
            .border({
              width: (this.settings.background.type === BackgroundType.COLOR && 
                     this.settings.background.color === preset.backgroundColor) ? 2 : 1,
              color: (this.settings.background.type === BackgroundType.COLOR && 
                     this.settings.background.color === preset.backgroundColor) ? 
                $r('app.color.accent_primary') : $r('app.color.divider')
            })
            .justifyContent(FlexAlign.Center)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.settings.background = {
                type: BackgroundType.COLOR,
                color: preset.backgroundColor,
                imageOpacity: 1.0
              };
              this.settings.textStyle.textColor = preset.textColor;
              this.updateAndNotify();
            })
          })
        }
        .width('100%')
      }
      .width('100%')
      
      Divider().color($r('app.color.divider'))
      
      // 背景图片设置
      Column({ space: 12 }) {
        Row() {
            Text('选择已有背景图片')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Row({ space: 8 }) {
            // 仅在有可复用背景时显示“添加”
            if (this.allAvailableBackgroundImages.length > 0) {
            Button('已有')
                .fontSize(12)
                .height(28)
                .backgroundColor($r('app.color.accent_secondary'))
                .fontColor(Color.White)
                .onClick(() => {
                  this.showOtherBgImagePicker = !this.showOtherBgImagePicker;
                })
            }
              Button('添加')
              .fontSize(12)
              .height(28)
              .backgroundColor($r('app.color.accent_primary'))
              .fontColor(Color.White)
              .onClick(() => {
                this.selectBackgroundImage();
              })
          }
        }
        .width('100%')
        
        // 展开跨书背景选择器
        if (this.showOtherBgImagePicker && this.allAvailableBackgroundImages.length > 0) {
          Column({ space: 8 }) {
            Text('从其他书籍背景中选择')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.allAvailableBackgroundImages, (item: BackgroundImageInfo) => {
                Column({ space: 2 }) {
                  Image(item.imagePath.startsWith('/') ? 'file://' + item.imagePath : item.imagePath)
                    .width(60)
                    .height(45)
                    .objectFit(ImageFit.Contain)
                    .borderRadius(6)
                    .backgroundColor($r('app.color.comp_background_tertiary'))
                    .border({
                      width: this.settings.background.imagePath === item.imagePath ? 2 : 0,
                      color: $r('app.color.accent_primary')
                    })
                  
                  Text(item.bookTitle)
                    .fontSize(9)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(60)
                    .textAlign(TextAlign.Center)
                }
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  // 应用所选背景图
                  this.settings.background = {
                    type: BackgroundType.IMAGE,
                    imagePath: item.imagePath,
                    imageOpacity: this.settings.background.imageOpacity || 1.0
                  };
                  this.showOtherBgImagePicker = false;
                  this.updateAndNotify();
                })
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.comp_background_tertiary'))
          .borderRadius(8)
        }
        
        // 已保存背景图
        if (this.settings.savedBackgroundImages && this.settings.savedBackgroundImages.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.settings.savedBackgroundImages, (savedImg: SavedBackgroundImage, index: number) => {
              Stack() {
                Image(savedImg.path.startsWith('/') ? 'file://' + savedImg.path : savedImg.path)
                  .width(60)
                  .height(45)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(6)
                  .backgroundColor($r('app.color.comp_background_tertiary'))
                  .border({
                    width: (this.settings.background.type === BackgroundType.IMAGE && 
                           this.settings.background.imagePath === savedImg.path) ? 2 : 0,
                    color: $r('app.color.accent_primary')
                  })
                
                // 当前使用中的背景标记
                if (this.settings.background.type === BackgroundType.IMAGE && 
                    this.settings.background.imagePath === savedImg.path) {
                  Column()
                    .width(16)
                    .height(16)
                    .backgroundColor($r('app.color.accent_primary'))
                    .borderRadius(8)
                    .position({ x: 44, y: -4 })
                }
              }
              .width(60)
              .height(45)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                // 应用已保存背景图
                this.settings.background = {
                  type: BackgroundType.IMAGE,
                  imagePath: savedImg.path,
                  imageOpacity: this.settings.background.imageOpacity || 1.0
                };
                this.updateAndNotify();
              })
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    this.showDeleteConfirmDialog(index);
                  })
              )
            })
          }
          .width('100%')
          
        Text('长按图片可删除')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          Text('暂无已保存背景图')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        }
        
        // 背景透明度
        if (this.settings.background.type === BackgroundType.IMAGE) {
          Column({ space: 8 }) {
            Row() {
          Text('背景透明度')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${Math.round((this.settings.background.imageOpacity || 1) * 100)}%`)
                .fontSize(14)
                .fontColor($r('app.color.accent_primary'))
            }
            .width('100%')
            
            Slider({
              value: (this.settings.background.imageOpacity || 1) * 100,
              min: 10,
              max: 100,
              step: 5
            })
              .width('100%')
              .onChange((value: number) => {
                this.settings.background.imageOpacity = value / 100;
                this.updateAndNotify();
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')
      
      Divider().color($r('app.color.divider'))
      
      // 文字颜色（图片背景）
      if (this.settings.background.type === BackgroundType.IMAGE) {
        Column({ space: 12 }) {
          Text('文字颜色')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          
          Row({ space: 8 }) {
            ForEach(['#333333', '#FFFFFF', '#5D4037', '#2E7D32', '#1565C0', '#D4D4D4'], (color: string) => {
              Column()
                .width(32)
                .height(32)
                .backgroundColor(color)
                .borderRadius(16)
                .border({
                  width: this.settings.textStyle.textColor === color ? 2 : 1,
                  color: this.settings.textStyle.textColor === color ? 
                    $r('app.color.accent_primary') : $r('app.color.divider')
                })
                .onClick(() => {
                  this.settings.textStyle.textColor = color;
                  this.updateAndNotify();
                })
            })
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
  }
  
  /**
   * 阅读设置
   */
  @Builder
  buildReadingSettings() {
    Column({ space: 20 }) {
      // 阅读模式
      Column({ space: 12 }) {
        Text('阅读模式')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        
        Row({ space: 8 }) {
          Button('翻页')
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.settings.readingMode === TextReadingMode.PAGE ? 
              $r('app.color.accent_primary') : $r('app.color.background_secondary'))
            .fontColor(this.settings.readingMode === TextReadingMode.PAGE ? 
              Color.White : $r('app.color.text_primary'))
            .onClick(() => {
              this.settings.readingMode = TextReadingMode.PAGE;
              this.updateAndNotify();
            })
          
          Button('上下滚动')
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.settings.readingMode === TextReadingMode.SCROLL ? 
              $r('app.color.accent_primary') : $r('app.color.background_secondary'))
            .fontColor(this.settings.readingMode === TextReadingMode.SCROLL ? 
              Color.White : $r('app.color.text_primary'))
            .onClick(() => {
              this.settings.readingMode = TextReadingMode.SCROLL;
              this.updateAndNotify();
            })
        }
        .width('100%')
      }
      .width('100%')
      
      // 翻页动画
      if (this.settings.readingMode === TextReadingMode.PAGE) {
        Column({ space: 12 }) {
          Text('翻页动画')
            .fontSize(14)
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
                Button(item.text)
                  .fontSize(12)
                  .height(32)
                  .layoutWeight(1)
                  .backgroundColor(this.settings.pageTurnAnimation === item.anim ? 
                    $r('app.color.accent_primary') : $r('app.color.background_secondary'))
                  .fontColor(this.settings.pageTurnAnimation === item.anim ? 
                    Color.White : $r('app.color.text_primary'))
                  .onClick(() => {
                    this.settings.pageTurnAnimation = item.anim;
                    this.updateAndNotify();
                  })
              }
            )
          }
          .width('100%')
        }
        .width('100%')
      }
      
      Divider().color($r('app.color.divider'))
      
      // 阅读交互开关
      this.buildToggleSetting('点击翻页', this.settings.tapToTurn, (isOn: boolean) => {
        this.settings.tapToTurn = isOn;
        this.updateAndNotify();
      })
      
      this.buildToggleSetting('音量键翻页', this.settings.volumeKeyNavigation, (isOn: boolean) => {
        this.settings.volumeKeyNavigation = isOn;
        this.updateAndNotify();
      })
      
      this.buildToggleSetting('保持屏幕常亮', this.settings.keepScreenOn, (isOn: boolean) => {
        this.settings.keepScreenOn = isOn;
        this.updateAndNotify();
      })

      this.buildDeviceOrientationLockSetting()

      Divider().color($r('app.color.divider'))
      
      // 底部显示模式
      Column({ space: 8 }) {
          Text('底部显示模式')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        
        // 页码/进度/不显示
          Text('选择底部显示内容')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        
        Row({ space: 8 }) {
          Button('页码')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(this.settings.showPageNumber ? 
              $r('app.color.accent_primary') : $r('app.color.background_secondary'))
            .fontColor(this.settings.showPageNumber ? 
              Color.White : $r('app.color.text_primary'))
            .onClick(() => {
              this.settings.showPageNumber = true;
              this.settings.showProgress = false;
              this.updateAndNotify();
            })
          
          Button('进度')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(!this.settings.showPageNumber && this.settings.showProgress ? 
              $r('app.color.accent_primary') : $r('app.color.background_secondary'))
            .fontColor(!this.settings.showPageNumber && this.settings.showProgress ? 
              Color.White : $r('app.color.text_primary'))
            .onClick(() => {
              this.settings.showPageNumber = false;
              this.settings.showProgress = true;
              this.updateAndNotify();
            })
          
          Button('不显示')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(!this.settings.showPageNumber && !this.settings.showProgress ? 
              $r('app.color.accent_primary') : $r('app.color.background_secondary'))
            .fontColor(!this.settings.showPageNumber && !this.settings.showProgress ? 
              Color.White : $r('app.color.text_primary'))
            .onClick(() => {
              this.settings.showPageNumber = false;
              this.settings.showProgress = false;
              this.updateAndNotify();
            })
        }
        .width('100%')
      }
      .width('100%')
      
      Divider().color($r('app.color.divider'))
      
      // 附加显示项
      this.buildToggleSetting('显示时间（底部信息栏）', this.settings.showTime, (isOn: boolean) => {
        this.settings.showTime = isOn;
        this.updateAndNotify();
      })
      
      this.buildToggleSetting('显示电量（状态栏）', this.settings.showBattery, (isOn: boolean) => {
        this.settings.showBattery = isOn;
        this.updateAndNotify();
      })
    }
    .width('100%')
  }
  
  @Builder
  buildDeviceOrientationLockSetting() {
    Row() {
      Column() {
        Text('锁定方向')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text((this.settings.lockDeviceOrientation ?? false)
          ? '保持当前屏幕方向，阅读时旋转设备不会改变方向'
          : '关闭后会跟随系统旋转策略，适合临时横屏阅读')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.settings.lockDeviceOrientation ?? false })
        .selectedColor($r('app.color.accent'))
        .onChange((value: boolean) => {
          this.settings.lockDeviceOrientation = value;
          this.updateAndNotify();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  buildToggleSetting(label: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
  
  /**
    * 选择并保存背景图片
   */
  private async selectBackgroundImage(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      
      if (result.photoUris && result.photoUris.length > 0) {
        const sourceUri = result.photoUris[0];
        
        // 复制图片到应用沙箱
        const savedPath = await this.copyImageToSandbox(sourceUri);
        if (!savedPath) {
          logger.error(TAG, '复制图片到沙箱失败');
          return;
        }
        
        // 初始化背景图列表
        if (!this.settings.savedBackgroundImages) {
          this.settings.savedBackgroundImages = [];
        }
        
        // 避免重复添加
        const exists = this.settings.savedBackgroundImages.some(
          (img: SavedBackgroundImage) => img.path === savedPath
        );
        
        if (!exists) {
          // 最多保留 10 张背景图
          if (this.settings.savedBackgroundImages.length >= 10) {
            // 移除最早一张
            const oldImage = this.settings.savedBackgroundImages.shift();
            if (oldImage) {
              this.deleteImageFile(oldImage.path);
            }
          }
          
          this.settings.savedBackgroundImages.push({
            path: savedPath,
            addTime: Date.now()
          });
        }
        
        // 应用新的背景配置
        this.settings.background = {
          type: BackgroundType.IMAGE,
          imagePath: savedPath,
          imageOpacity: this.settings.background.imageOpacity ?? 0.3
        };
        
        this.updateAndNotify();
        logger.info(TAG, `背景图已保存到应用目录: ${savedPath}`);
      }
    } catch (error) {
      logger.error(TAG, `保存背景图失败: ${String(error)}`);
    }
  }
  
  /**
    * 将图片复制到缓存目录
    * 返回新文件路径
    * 失败时返回 null
   */
  private async copyImageToSandbox(sourceUri: string): Promise<string | null> {
    try {
      // 获取应用缓存目录
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
      const cacheDir: string = context.cacheDir;
      
      // 生成目标文件名
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(2, 8);
      const extension = this.getFileExtension(sourceUri);
      const destFileName = `bg_${timestamp}_${randomStr}${extension}`;
      const destPath = `${cacheDir}/${destFileName}`;
      
      logger.info(TAG, `cacheDir: ${cacheDir}`);
      
      logger.info(TAG, `复制源文件到目标: ${sourceUri} -> ${destPath}`);
      
      // 打开源文件
      const sourceFile = SafeFileUtils.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      logger.info(TAG, `已打开源文件, fd: ${sourceFile.fd}`);
      
      // copyFileSync 支持 (fd, path) 的形式，这里使用源 fd 复制到目标路径
      SafeFileUtils.copyFileSync(sourceFile.fd, destPath);
      logger.info(TAG, `copyFileSync 执行完成`);
      
      SafeFileUtils.closeSync(sourceFile);
      
      // 校验目标文件
      const stat = SafeFileUtils.statSync(destPath);
      logger.info(TAG, `目标文件校验通过: ${destPath}, 大小: ${stat.size} bytes`);
      
      return destPath;
      
    } catch (error) {
      logger.error(TAG, `copyBackgroundImageToAppStorage 执行失败: ${String(error)}`);
      return null;
    }
  }
  
  /**
    * 获取文件扩展名
   */
  private getFileExtension(path: string): string {
    const lastDot = path.lastIndexOf('.');
    if (lastDot >= 0) {
      return path.substring(lastDot);
    }
    return '.jpg'; // 默认扩展名
  }
  
  /**
    * 删除背景图文件
   */
  private deleteImageFile(path: string): void {
    try {
      // 仅删除背景目录内文件
      if (path.includes('/bg_images/')) {
        SafeFileUtils.unlinkSync(path);
        logger.info(TAG, `已删除背景图片文件: ${path}`);
      }
    } catch (error) {
      logger.warn(TAG, `删除背景图片文件失败: ${String(error)}`);
    }
  }
  
  /**
    * 弹出删除确认对话框
   */
  private showDeleteConfirmDialog(index: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除背景图片',
      message: '确定要删除这张背景图片吗？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteBackgroundImage(index);
      }
    }).catch((err: Error) => {
      logger.error(TAG, `删除确认弹窗失败: ${err.message}`);
    });
  }
  
  /**
   * 删除背景图项
   */
  private deleteBackgroundImage(index: number): void {
    if (!this.settings.savedBackgroundImages || index < 0 || index >= this.settings.savedBackgroundImages.length) {
      return;
    }
    
    const deletedPath = this.settings.savedBackgroundImages[index].path;
    
    // 删除对应文件
    this.deleteImageFile(deletedPath);
    
    this.settings.savedBackgroundImages.splice(index, 1);
    
    // 若当前正在使用该图，回退为纯色背景
    if (this.settings.background.type === BackgroundType.IMAGE && 
        this.settings.background.imagePath === deletedPath) {
      this.settings.background = {
        type: BackgroundType.COLOR,
        color: '#F5F0E1',
        imageOpacity: 1.0
      };
      this.settings.textStyle.textColor = '#5D4037';
    }
    
    this.updateAndNotify();
    logger.info(TAG, `删除背景图项: index=${index}, path=${deletedPath}`);
  }
}
