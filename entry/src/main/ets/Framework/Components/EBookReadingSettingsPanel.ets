// 文件路径: entry/src/main/ets/Framework/Components/EBookReadingSettingsPanel.ets
/**
 * 电子书阅读设置面板
 * 提供字体大小、行高、主题等阅读设置
 */

import { logger } from '../../Utils/Logger';
import { ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { EBookReadingSettings, EBookPageMode } from '../../Models/EBookModels';

const TAG = 'EBookReadingSettingsPanel';

/**
 * 阅读设置面板参数
 */
export interface EBookReadingSettingsPanelParams {
  settings: EBookReadingSettings;
  onSettingsChange: (settings: EBookReadingSettings) => void;
  onClose: () => void;
}

@Component
export struct EBookReadingSettingsPanel {
  @Prop settings: EBookReadingSettings;
  onSettingsChange: (settings: EBookReadingSettings) => void = (settings: EBookReadingSettings) => {};
  onClose: () => void = () => {};

  @State currentTheme: ThemeType = ThemeType.AUTO;

  // 预设主题
  private themes: ReadingTheme[] = [
    { name: '默认', bgColor: '#FFFFFF', textColor: '#333333' },
    { name: '护眼', bgColor: '#C7EDCC', textColor: '#2B2B2B' },
    { name: '夜间', bgColor: '#1E1E1E', textColor: '#D4D4D4' },
    { name: '羊皮纸', bgColor: '#F4ECD8', textColor: '#5C4B37' }
  ];

  /**
   * 更新字体大小
   */
  private updateFontSize(size: number): void {
    const newSettings: EBookReadingSettings = {
      fontSize: size,
      lineHeight: this.settings.lineHeight,
      fontFamily: this.settings.fontFamily,
      backgroundColor: this.settings.backgroundColor,
      textColor: this.settings.textColor,
      pageMargin: this.settings.pageMargin,
      pageMode: this.settings.pageMode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval
    };
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新行高
   */
  private updateLineHeight(height: number): void {
    const newSettings: EBookReadingSettings = {
      fontSize: this.settings.fontSize,
      lineHeight: height,
      fontFamily: this.settings.fontFamily,
      backgroundColor: this.settings.backgroundColor,
      textColor: this.settings.textColor,
      pageMargin: this.settings.pageMargin,
      pageMode: this.settings.pageMode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval
    };
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新页边距
   */
  private updatePageMargin(margin: number): void {
    const newSettings: EBookReadingSettings = {
      fontSize: this.settings.fontSize,
      lineHeight: this.settings.lineHeight,
      fontFamily: this.settings.fontFamily,
      backgroundColor: this.settings.backgroundColor,
      textColor: this.settings.textColor,
      pageMargin: margin,
      pageMode: this.settings.pageMode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval
    };
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新主题
   */
  private updateTheme(theme: ReadingTheme): void {
    const newSettings: EBookReadingSettings = {
      fontSize: this.settings.fontSize,
      lineHeight: this.settings.lineHeight,
      fontFamily: this.settings.fontFamily,
      backgroundColor: theme.bgColor,
      textColor: theme.textColor,
      pageMargin: this.settings.pageMargin,
      pageMode: this.settings.pageMode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval
    };
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新翻页模式
   */
  private updatePageMode(mode: EBookPageMode): void {
    const newSettings: EBookReadingSettings = {
      fontSize: this.settings.fontSize,
      lineHeight: this.settings.lineHeight,
      fontFamily: this.settings.fontFamily,
      backgroundColor: this.settings.backgroundColor,
      textColor: this.settings.textColor,
      pageMargin: this.settings.pageMargin,
      pageMode: mode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval
    };
    this.onSettingsChange(newSettings);
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('阅读设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        }
        .width(32)
        .height(32)
        .backgroundColor('transparent')
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.currentTheme))

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

      // 设置内容
      Scroll() {
        Column({ space: 20 }) {
          // 字体大小
          this.buildFontSizeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 行高
          this.buildLineHeightSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 页边距
          this.buildPageMarginSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 阅读主题
          this.buildThemeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 翻页模式
          this.buildPageModeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 其他设置
          this.buildOtherSettings()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作栏
      Row({ space: 12 }) {
        Button('恢复默认')
          .fontSize(14)
          .layoutWeight(1)
          .height(44)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
          })
          .onClick(() => {
            this.resetToDefault();
          })

        Button('完成')
          .fontSize(14)
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme))
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
    }
    .width('100%')
    .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.currentTheme))
  }

  /**
   * 构建字体大小设置
   */
  @Builder
  buildFontSizeSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('字体大小')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.fontSize}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('A-')
          .fontSize(14)
          .width(50)
          .height(36)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            if (this.settings.fontSize > 12) {
              this.updateFontSize(this.settings.fontSize - 2);
            }
          })

        Slider({
          value: this.settings.fontSize,
          min: 12,
          max: 32,
          step: 2,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .showTips(false)
          .onChange((value: number) => {
            this.updateFontSize(Math.round(value));
          })

        Button('A+')
          .fontSize(14)
          .width(50)
          .height(36)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            if (this.settings.fontSize < 32) {
              this.updateFontSize(this.settings.fontSize + 2);
            }
          })
      }
      .width('100%')

      // 预览文本
      Text('这是预览文本 This is preview text')
        .fontSize(this.settings.fontSize)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .lineHeight(this.settings.fontSize * this.settings.lineHeight)
        .padding(16)
        .width('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
        .borderRadius(8)
    }
  }

  /**
   * 构建行高设置
   */
  @Builder
  buildLineHeightSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('行高')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.lineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Slider({
        value: this.settings.lineHeight,
        min: 1.0,
        max: 3.0,
        step: 0.1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
        .showTips(false)
        .onChange((value: number) => {
          this.updateLineHeight(Math.round(value * 10) / 10);
        })
    }
  }

  /**
   * 构建页边距设置
   */
  @Builder
  buildPageMarginSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('页边距')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.pageMargin}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Slider({
        value: this.settings.pageMargin,
        min: 10,
        max: 50,
        step: 5,
        style: SliderStyle.InSet
      })
        .width('100%')
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
        .showTips(false)
        .onChange((value: number) => {
          this.updatePageMargin(Math.round(value));
        })
    }
  }

  /**
   * 构建主题设置
   */
  @Builder
  buildThemeSetting() {
    Column({ space: 12 }) {
      Text('阅读主题')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        ForEach(this.themes, (theme: ReadingTheme) => {
          Column({ space: 4 }) {
            Column()
              .width(50)
              .height(50)
              .backgroundColor(theme.bgColor)
              .borderRadius(8)
              .border({
                width: this.settings.backgroundColor === theme.bgColor ? 2 : 1,
                color: this.settings.backgroundColor === theme.bgColor 
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
              })
              .onClick(() => {
                this.updateTheme(theme);
              })

            Text(theme.name)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
  }

  /**
   * 构建翻页模式设置
   */
  @Builder
  buildPageModeSetting() {
    Column({ space: 12 }) {
      Text('翻页模式')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        Button('滚动')
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
              .backgroundColor(this.settings.pageMode === EBookPageMode.SCROLL 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : 'transparent')
          .fontColor(this.settings.pageMode === EBookPageMode.SCROLL
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: this.settings.pageMode === EBookPageMode.SCROLL
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            this.updatePageMode(EBookPageMode.SCROLL);
          })

        Button('翻页')
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.settings.pageMode === EBookPageMode.PAGE 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : 'transparent')
          .fontColor(this.settings.pageMode === EBookPageMode.PAGE
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: this.settings.pageMode === EBookPageMode.PAGE
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            this.updatePageMode(EBookPageMode.PAGE);
          })

        Button('仿真')
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.settings.pageMode === EBookPageMode.SIMULATION 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : 'transparent')
          .fontColor(this.settings.pageMode === EBookPageMode.SIMULATION
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: this.settings.pageMode === EBookPageMode.SIMULATION
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            this.updatePageMode(EBookPageMode.SIMULATION);
          })
      }
      .width('100%')
    }
  }

  /**
   * 构建其他设置
   */
  @Builder
  buildOtherSettings() {
    Column({ space: 16 }) {
      Text('其他设置')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      // 自动保存
      Row() {
        Text('自动保存进度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.settings.autoSave })
          .onChange((isOn: boolean) => {
            const newSettings: EBookReadingSettings = {
              fontSize: this.settings.fontSize,
              lineHeight: this.settings.lineHeight,
              fontFamily: this.settings.fontFamily,
              backgroundColor: this.settings.backgroundColor,
              textColor: this.settings.textColor,
              pageMargin: this.settings.pageMargin,
              pageMode: this.settings.pageMode,
              brightness: this.settings.brightness,
              autoSave: isOn,
              saveInterval: this.settings.saveInterval
            };
            this.onSettingsChange(newSettings);
          })
      }
      .width('100%')

      // 保存间隔
      if (this.settings.autoSave) {
        Row() {
          Text('保存间隔（秒）')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

          Blank()

          Text(`${this.settings.saveInterval}`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')

        Slider({
          value: this.settings.saveInterval,
          min: 10,
          max: 120,
          step: 10,
          style: SliderStyle.InSet
        })
          .width('100%')
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .showTips(false)
          .onChange((value: number) => {
            const newSettings: EBookReadingSettings = {
              fontSize: this.settings.fontSize,
              lineHeight: this.settings.lineHeight,
              fontFamily: this.settings.fontFamily,
              backgroundColor: this.settings.backgroundColor,
              textColor: this.settings.textColor,
              pageMargin: this.settings.pageMargin,
              pageMode: this.settings.pageMode,
              brightness: this.settings.brightness,
              autoSave: this.settings.autoSave,
              saveInterval: Math.round(value)
            };
            this.onSettingsChange(newSettings);
          })
      }
    }
  }

  /**
   * 恢复默认设置
   */
  private resetToDefault(): void {
    const defaultSettings: EBookReadingSettings = {
      fontSize: 18,
      lineHeight: 1.8,
      fontFamily: 'HarmonyOS Sans',
      backgroundColor: '#FFFFFF',
      textColor: '#333333',
      pageMargin: 20,
      pageMode: EBookPageMode.PAGE,
      brightness: 100,
      autoSave: true,
      saveInterval: 30
    };
    this.onSettingsChange(defaultSettings);
    logger.info(TAG, '已恢复默认设置');
  }
}

/**
 * 阅读主题接口
 */
interface ReadingTheme {
  name: string;
  bgColor: string;
  textColor: string;
}

