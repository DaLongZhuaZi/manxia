/**
 * 漫画阅读器章节列表组件
 * 用于在阅读器内快速切换章节
 */

import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { MangaChapter } from '../Models/MangaModels';
import { curves, UIContext } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'MangaReaderChapterList';

/**
 * 章节列表参数接口
 */
export interface MangaReaderChapterListParams {
  /** 章节列表 */
  chapters: MangaChapter[];
  /** 当前章节ID */
  currentChapterId: string;
  /** 是否显示 */
  isVisible: boolean;
  /** 章节切换回调 */
  onChapterSelect?: (chapterId: string) => void;
  /** 关闭回调 */
  onClose?: () => void;
}

// 定义事件回调接口
interface MangaReaderChapterListCallbacks {
  onChapterSelect: (chapterId: string) => void;
  onClose: () => void;
}

@Component
export struct MangaReaderChapterList {
  @Prop chapters: MangaChapter[];
  @Prop currentChapterId: string;
  @Prop isVisible: boolean;
  @Prop callbacks: MangaReaderChapterListCallbacks;

  // 内部状态
  @State private panelOpacity: number = 0;
  @State private panelScale: number = 0.95;
  @State private panelTranslateY: number = 20;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();

  // 动画系统
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    // 获取UI上下文
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
    }
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaReaderChapterList', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `MangaReaderChapterList 主题切换: ${theme}`);
    });
    
    // 延迟执行动画，确保组件完全渲染后再播放
    if (this.isVisible) {
      setTimeout(() => {
        this.showPanel();
      }, 50);
    }
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware('MangaReaderChapterList');
  }

  onPageShow() {
    if (this.isVisible) {
      this.showPanel();
    }
  }

  /**
   * 显示章节列表面板
   */
  private showPanel(): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

    const fadeInOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeInOptions, () => {
      this.backdropOpacity = 0.5;
    });

    const slideInOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(slideInOptions, () => {
      this.panelOpacity = 1;
      this.panelScale = 1;
      this.panelTranslateY = 0;
    });
  }

  /**
   * 隐藏章节列表面板
   */
  private hidePanel(): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

    const slideOutOptions: AnimateParam = { 
      duration: 160, 
      curve: curves.initCurve(Curve.EaseIn),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(slideOutOptions, () => {
      this.panelOpacity = 0;
      this.panelScale = 0.95;
      this.panelTranslateY = 20;
    });

    const fadeOutOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeOutOptions, () => {
      this.backdropOpacity = 0;
    });
  }

  /**
   * 选择章节
   */
  private selectChapter(chapterId: string): void {
    logger.info(TAG, `选择章节: ${chapterId}`);
    if (this.callbacks.onChapterSelect) {
      this.callbacks.onChapterSelect(chapterId);
    }
    this.hidePanel();
    
    // 动画完成后调用关闭回调
    setTimeout(() => {
      if (this.callbacks.onClose) {
        this.callbacks.onClose();
      }
    }, 500);
  }

  /**
   * 构建章节列表项
   */
  @Builder
  buildChapterItem(chapter: MangaChapter, index: number) {
    Row() {
      Column() {
        Text(chapter.title)
          .fontSize(16)
          .fontWeight(chapter.id === this.currentChapterId ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(chapter.id === this.currentChapterId ? 
            $r('app.color.accent') : $r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          if (chapter.isDownloaded) {
            Image($r('app.media.ic_download_done'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.accent_green'))
              .margin({ right: 8 })
          }
          
          // [懒加载优化] 优先使用totalPages（骨架模式），其次使用pages.length（已加载模式）
          Text(`${chapter.totalPages || chapter.pages.length}页`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (chapter.id === this.currentChapterId) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(chapter.id === this.currentChapterId ? 
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      if (chapter.id !== this.currentChapterId) {
        this.selectChapter(chapter.id);
      }
    })
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 背景遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .onClick(() => {
            this.hidePanel();
            if (this.callbacks.onClose) {
              this.callbacks.onClose();
            }
          })

        // 章节列表面板（居中弹窗样式）
        Column() {
          // 面板标题
          Row() {
            Text('章节目录')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Text(`共${this.chapters.length}章`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ right: 12 })

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
              this.hidePanel();
              if (this.callbacks.onClose) {
                this.callbacks.onClose();
              }
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          // 滚动章节列表
          List() {
            ForEach(this.chapters, (chapter: MangaChapter, index: number) => {
              ListItem() {
                this.buildChapterItem(chapter, index)
              }
            }, (chapter: MangaChapter) => chapter.id)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
            startMargin: 16,
            endMargin: 16
          })
        }
        .width('90%')
        .height('70%')
        .constraintSize({ maxWidth: 500, maxHeight: 600 })
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius(16)
        .padding(20)
        .opacity(this.panelOpacity)
        .scale({ x: this.panelScale, y: this.panelScale })
        .translate({ y: this.panelTranslateY })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}

