/**
 * 文本阅读器设置面板组件
 * 提供字体、背景、翻页动画等设置
 * 修复响应性问题，支持多背景图片
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
  DEFAULT_TEXT_STYLE,
  DEFAULT_PAGE_MARGINS
} from '../Models/TextReaderModels';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { logger } from '../Utils/Logger';
import { promptAction } from '@kit.ArkUI';
import { EBookDataManager, BackgroundImageInfo } from '../Framework/Data/EBookDataManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';

const TAG = 'TextReaderSettingsPanel';

/**
 * 文字对齐选项接口
 */
interface AlignmentOption {
  text: string;
  align: TextAlignment;
}

/**
 * 字体粗细选项接口
 */
interface WeightOption {
  text: string;
  weight: number;
}

/**
 * 翻页动画选项接口
 */
interface AnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

/**
 * 设置面板标签页类型
 */
enum SettingsTab {
  FONT = 'FONT',
  BACKGROUND = 'BACKGROUND',
  READING = 'READING'
}

@Component
export struct TextReaderSettingsPanel {
  /** 阅读设置（双向绑定） */
  @Link settings: TextReaderSettings;
  /** 关闭回调 */
  onClose: () => void = () => {};
  /** 设置变化回调 */
  onSettingsChange: (settings: TextReaderSettings) => void = () => {};
  /** 是否横屏 */
  @Prop isLandscape: boolean = false;
  
  /** 当前选中的标签页 */
  @State private currentTab: SettingsTab = SettingsTab.FONT;
  /** 强制刷新计数器 - 用于触发UI更新 */
  @State private refreshCounter: number = 0;
  /** 预览文本 */
  private previewText: string = '这是一段预览文字，用于展示当前的字体设置和背景颜色效果。';
  /** 所有可用的背景图片（来自其他电子书和全局设置） */
  @State private allAvailableBackgroundImages: BackgroundImageInfo[] = [];
  /** 是否显示其他电子书背景图片选择器 */
  @State private showOtherBgImagePicker: boolean = false;
  /** 电子书数据管理器 */
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  
  aboutToAppear(): void {
    // 加载所有可用的背景图片
    this.loadAllAvailableBackgroundImages();
  }
  
  /**
   * 加载所有可用的背景图片（来自其他电子书和全局设置）
   */
  private async loadAllAvailableBackgroundImages(): Promise<void> {
    try {
      const ebookImages = await this.ebookDataManager.getAllCustomBackgroundImages();
      
      const allImages: BackgroundImageInfo[] = [];
      const seenPaths = new Set<string>();
      
      // 先添加全局设置的背景图片
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
      
      // 添加电子书的背景图片（去重）
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
   * 强制刷新设置并通知变化
   * 通过创建新对象来确保 ArkTS 能够检测到变化
   */
  private updateAndNotify(): void {
    this.refreshCounter++;
    // 创建深拷贝以触发响应式更新
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
      savedBackgroundImages: this.settings.savedBackgroundImages ? [...this.settings.savedBackgroundImages] : [],
      textStyle: {
        fontSize: this.settings.textStyle.fontSize,
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
      showPageNumber: this.settings.showPageNumber,
      showProgress: this.settings.showProgress,
      showTime: this.settings.showTime,
      showBattery: this.settings.showBattery,
      tapToTurn: this.settings.tapToTurn,
      volumeKeyNavigation: this.settings.volumeKeyNavigation,
      autoScrollSpeed: this.settings.autoScrollSpeed,
      curlBackOpacity: this.settings.curlBackOpacity
    };
    this.settings = newSettings;
    this.onSettingsChange(newSettings);
  }
  
  build() {
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
      
      // 标签页切换
      Row({ space: 0 }) {
        this.buildTabButton('字体', SettingsTab.FONT)
        this.buildTabButton('背景', SettingsTab.BACKGROUND)
        this.buildTabButton('阅读', SettingsTab.READING)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      
      Divider().color($r('app.color.divider'))
      
      // 内容区域
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
    .backgroundColor($r('app.color.background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
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
    // 使用 refreshCounter 触发重新渲染
    Column({ space: 20 }) {
      // 预览区域
      Column() {
        Text('预览效果')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 8 })
        
        Text(this.previewText)
          .fontSize(this.settings.textStyle.fontSize)
          .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
          .fontColor(this.settings.textStyle.textColor)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
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
          Text(`${this.settings.textStyle.fontSize}`)
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
              if (this.settings.textStyle.fontSize > 12) {
                this.settings.textStyle.fontSize -= 1;
                this.updateAndNotify();
              }
            })
          
          Slider({
            value: this.settings.textStyle.fontSize,
            min: 12,
            max: 32,
            step: 1
          })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.settings.textStyle.fontSize = Math.round(value);
              this.updateAndNotify();
            })
          
          Button('A+')
            .fontSize(14)
            .width(48)
            .height(36)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              if (this.settings.textStyle.fontSize < 32) {
                this.settings.textStyle.fontSize += 1;
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
      
      // 字体粗细
      Column({ space: 8 }) {
        Row() {
          Text('字体粗细')
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
    }
    .width('100%')
  }
  
  /**
   * 背景设置
   */
  @Builder
  buildBackgroundSettings() {
    Column({ space: 20 }) {
      // 预设背景颜色
      Column({ space: 12 }) {
        Text('预设主题(同时设置背景主题与文本颜色)')
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
      
      // 自定义背景图片
      Column({ space: 12 }) {
        Row() {
          Text('自定义背景图片')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Row({ space: 8 }) {
            // 使用已有背景按钮
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
        
        // 其他电子书背景图片选择器
        if (this.showOtherBgImagePicker && this.allAvailableBackgroundImages.length > 0) {
          Column({ space: 8 }) {
            Text('选择已有背景图片')
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
                  // 选择此图片作为背景
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
        
        // 已保存的背景图片缩略图
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
                
                // 选中标记
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
                // 选择此图片作为背景
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
          Text('暂无保存的背景图片')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        }
        
        // 图片不透明度调节（仅在使用图片背景时显示）
        if (this.settings.background.type === BackgroundType.IMAGE) {
          Column({ space: 8 }) {
            Row() {
              Text('图片不透明度')
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
      
      // 文字颜色（仅在使用图片背景时需要手动选择）
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
          Button('左右翻页')
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
      
      // 翻页动画（仅在翻页模式下显示）
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
      
      // 开关设置
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
      
      Divider().color($r('app.color.divider'))
      
      // 底部信息显示设置
      Column({ space: 8 }) {
        Text('阅读进度显示')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        
        // 右下角显示选项（页码/进度/不显示，三选一）
        Text('右下角显示信息')
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
      
      // 其他显示开关
      this.buildToggleSetting('显示时间 (底部中央)', this.settings.showTime, (isOn: boolean) => {
        this.settings.showTime = isOn;
        this.updateAndNotify();
      })
      
      this.buildToggleSetting('显示电量 (左下角)', this.settings.showBattery, (isOn: boolean) => {
        this.settings.showBattery = isOn;
        this.updateAndNotify();
      })
    }
    .width('100%')
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
   * 选择背景图片并复制到应用沙箱目录
   */
  private async selectBackgroundImage(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      
      if (result.photoUris && result.photoUris.length > 0) {
        const sourceUri = result.photoUris[0];
        
        // 将图片复制到应用沙箱目录
        const savedPath = await this.copyImageToSandbox(sourceUri);
        if (!savedPath) {
          logger.error(TAG, '复制图片到沙箱失败');
          return;
        }
        
        // 添加到保存的背景图片列表
        if (!this.settings.savedBackgroundImages) {
          this.settings.savedBackgroundImages = [];
        }
        
        // 检查是否已存在
        const exists = this.settings.savedBackgroundImages.some(
          (img: SavedBackgroundImage) => img.path === savedPath
        );
        
        if (!exists) {
          // 最多保存10个
          if (this.settings.savedBackgroundImages.length >= 10) {
            // 删除最旧的图片文件
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
        
        // 设置为当前背景
        this.settings.background = {
          type: BackgroundType.IMAGE,
          imagePath: savedPath,
          imageOpacity: this.settings.background.imageOpacity ?? 0.3
        };
        
        this.updateAndNotify();
        logger.info(TAG, `选择背景图片已保存到沙箱: ${savedPath}`);
      }
    } catch (error) {
      logger.error(TAG, `选择图片失败: ${String(error)}`);
    }
  }
  
  /**
   * 复制图片到应用沙箱目录
   * 注意：PhotoViewPicker 返回的是 file://media/... URI，需要特殊处理
   * 使用 @ohos.file.fs 模块（与 ThemeSettingsPage 一致）
   */
  private async copyImageToSandbox(sourceUri: string): Promise<string | null> {
    try {
      // 获取应用缓存目录（直接使用 cacheDir，与官方示例完全一致）
      const context = getContext(this);
      const cacheDir = context.cacheDir;
      
      // 生成唯一文件名（直接放在 cacheDir 下，与官方示例一致）
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(2, 8);
      const extension = this.getFileExtension(sourceUri);
      const destFileName = `bg_${timestamp}_${randomStr}${extension}`;
      const destPath = `${cacheDir}/${destFileName}`;
      
      logger.info(TAG, `cacheDir: ${cacheDir}`);
      
      logger.info(TAG, `准备复制图片: ${sourceUri} -> ${destPath}`);
      
      // 使用官方文档推荐的方式：打开源文件后直接 copyFileSync 到目标路径
      const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      logger.info(TAG, `源文件打开成功, fd: ${sourceFile.fd}`);
      
      // copyFileSync 支持 (fd, path) 格式，不需要预先创建目标文件
      fs.copyFileSync(sourceFile.fd, destPath);
      logger.info(TAG, `copyFileSync 完成`);
      
      fs.closeSync(sourceFile);
      
      // 验证文件是否复制成功
      const stat = fs.statSync(destPath);
      logger.info(TAG, `图片复制成功: ${destPath}, 大小: ${stat.size} 字节`);
      
      return destPath;
      
    } catch (error) {
      logger.error(TAG, `复制图片失败: ${String(error)}`);
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
   * 删除图片文件
   */
  private deleteImageFile(path: string): void {
    try {
      // 只删除沙箱内的文件
      if (path.includes('/bg_images/')) {
        fs.unlinkSync(path);
        logger.info(TAG, `已删除背景图片文件: ${path}`);
      }
    } catch (error) {
      logger.warn(TAG, `删除图片文件失败: ${String(error)}`);
    }
  }
  
  /**
   * 显示删除确认对话框
   */
  private showDeleteConfirmDialog(index: number): void {
    promptAction.showDialog({
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
      logger.error(TAG, `显示对话框失败: ${err.message}`);
    });
  }
  
  /**
   * 删除背景图片
   */
  private deleteBackgroundImage(index: number): void {
    if (!this.settings.savedBackgroundImages || index < 0 || index >= this.settings.savedBackgroundImages.length) {
      return;
    }
    
    const deletedPath = this.settings.savedBackgroundImages[index].path;
    
    // 删除沙箱中的图片文件
    this.deleteImageFile(deletedPath);
    
    this.settings.savedBackgroundImages.splice(index, 1);
    
    // 如果删除的是当前使用的背景，切换回默认颜色背景
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
    logger.info(TAG, `删除背景图片: index=${index}, path=${deletedPath}`);
  }
}
