// 文件路径: entry/src/main/ets/pages/CoverSelectionPage.ets
// 职责: 独立的封面选择页面，替代自定义对话框，可靠显示图片缩略图并返回选择结果

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { UIContext, LengthMetrics } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { eventBus, GameEvent, IEventPayload, CoverSelectionCompletedPayload } from '../Framework/EventBus';

const TAG: string = 'CoverSelectionPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 导航路径参数接口
export interface CoverSelectionPageParams {
  mangaId: string;
  chapterId: string;
  candidatePaths: string[];
  fromPage: string; // 例如 'DataManagementPage'
}

// NavDestinationContext接口定义（遵循现有页面模式）
interface NavDestinationContext {
  pathStack: NavPathStack;
}

@Component
export struct CoverSelectionPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  // 沉浸式安全区高度（强制规范）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  private uiContext: UIContext | undefined = undefined;

  // 主题相关
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `CoverSelectionPage_${Date.now()}`;

  // 页面参数与状态
  @State pageParams: CoverSelectionPageParams = {
    mangaId: '',
    chapterId: '',
    candidatePaths: [],
    fromPage: 'DataManagementPage'
  } as CoverSelectionPageParams;

  @State candidateThumbnails: Array<image.PixelMap> = [];
  @State selectedIndex: number = -1;
  @State isLoading: boolean = true;
  @State loadError: string = '';

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');

    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '无法获取UIContext');
    }

    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 此处不再主动预加载，改为在 onReady 解析 NavPathStack 参数后再触发
  }

  // onReady 生命周期在 HdsNavDestination 内部通过链式调用设置，组件级无需重复实现

  private lifecycle = new PageLifecycleManager('CoverSelectionPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 释放PixelMap资源，避免内存泄漏
    try {
      for (let i = 0; i < this.candidateThumbnails.length; i++) {
        const pm: image.PixelMap = this.candidateThumbnails[i];
        pm.release();
      }
      this.candidateThumbnails = [];
    } catch (error) {
      logger.warn(TAG, `释放缩略图资源失败: ${String(error)}`);
    }

    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private async preloadThumbnails(): Promise<void> {
    try {
      this.isLoading = true;
      this.loadError = '';
      logger.startup(TAG, '开始预加载封面候选缩略图');

      const candidates: Array<string> = this.pageParams.candidatePaths;
      if (!candidates || candidates.length === 0) {
        this.isLoading = false;
        this.loadError = '候选图片为空';
        logger.warn(TAG, '候选图片为空，无法显示封面选择');
        return;
      }

      const maxCount: number = Math.min(3, candidates.length);
      const thumbs: Array<image.PixelMap> = [];
      logger.debug(TAG, `计划解码的候选数量=${maxCount}`);
      for (let i = 0; i < maxCount; i++) {
        const path: string = candidates[i];
        try {
          logger.debug(TAG, `开始解码候选[${i}]: ${path}`);
          const imgSource: image.ImageSource = image.createImageSource(path);
          const decodingOptions: image.DecodingOptions = {
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          } as image.DecodingOptions;
          const pm: image.PixelMap = await imgSource.createPixelMap(decodingOptions);
          imgSource.release();
          thumbs.push(pm);
          logger.info(TAG, `解码成功: ${path}`);
        } catch (err) {
          logger.warn(TAG, `缩略图加载失败: ${path}, ${String(err)}`);
        }
      }

      this.candidateThumbnails = thumbs;
      this.selectedIndex = thumbs.length > 0 ? 0 : -1;
      logger.info(TAG, `缩略图加载完成，数量=${thumbs.length}, 默认选中索引=${this.selectedIndex}`);
    } catch (error) {
      this.loadError = '缩略图加载异常';
      logger.error(TAG, '缩略图加载异常', String(error));
    } finally {
      this.isLoading = false;
      logger.info(TAG, '预加载缩略图流程结束');
    }
  }

  private confirmSelection(): void {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.pageParams.candidatePaths.length) {
      logger.warn(TAG, '未选择有效的封面索引');
      return;
    }

    const selectedPath: string = this.pageParams.candidatePaths[this.selectedIndex];

    // 通过事件总线发布选择结果，供DataManagementPage处理复制与数据库更新
    const payload = new CoverSelectionCompletedPayload(
      this.pageParams.mangaId,
      this.pageParams.chapterId,
      selectedPath
    ) as CoverSelectionCompletedPayload;
    eventBus.publish(GameEvent.COVER_SELECTION_COMPLETED, payload as IEventPayload);
    logger.info(TAG, `封面选择完成: ${selectedPath}`);

    // 返回上一页
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回上一页失败', String(error));
    }
  }

  /**
   * 从 NavPathStack 解析参数，如果失败则回退到 Router 参数
   */
  private parsePageParamsFromNavStack(): void {
    try {
      // 绑定全局导航栈（若尚未绑定）
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        this.pathStack = globalStack;
        logger.debug(TAG, '✅ 成功获取 GlobalNavStack 并绑定到 pathStack');
      }

      // 从 pathStack 按页面名提取参数数组
      const paramsArray = this.pathStack.getParamByName('CoverSelectionPage') as CoverSelectionPageParams[];
      const count: number = paramsArray ? paramsArray.length : 0;
      logger.debug(TAG, `📋 NavPathStack 参数数组长度: ${count}`);

      if (paramsArray && paramsArray.length > 0) {
        const latest: CoverSelectionPageParams = paramsArray[paramsArray.length - 1] as CoverSelectionPageParams;
        // 明确字段存在性检查
        const keys: Array<string> = Object.keys(latest as Object);
        const ok: boolean = keys.includes('mangaId') && keys.includes('chapterId') && keys.includes('candidatePaths');
        if (ok) {
          this.pageParams = latest as CoverSelectionPageParams;
          logger.info(TAG, `✅ 解析 NavPathStack 参数成功: mangaId=${this.pageParams.mangaId}, chapterId=${this.pageParams.chapterId}, 候选数量=${this.pageParams.candidatePaths.length}, from=${this.pageParams.fromPage}`);
          // 预览部分候选路径
          const previewCount: number = Math.min(5, this.pageParams.candidatePaths.length);
          for (let i = 0; i < previewCount; i++) {
            logger.debug(TAG, `候选路径[${i}]: ${this.pageParams.candidatePaths[i]}`);
          }
          return; // 成功解析，直接返回
        } else {
          logger.warn(TAG, '⚠️ NavPathStack 参数格式不完整，尝试回退到 Router 参数');
        }
      } else {
        logger.warn(TAG, '⚠️ NavPathStack 未找到 CoverSelectionPage 参数，尝试回退到 Router 参数');
      }
    } catch (err) {
      logger.error(TAG, '解析 NavPathStack 参数异常', String(err));
    }

    // 回退：尝试从 Router 获取参数（用于 router.pushUrl 导航的场景）
    try {
      const router = this.getUIContext()?.getRouter();
      if (router) {
        const params = router.getParams() as CoverSelectionPageParams;
        const keys: Array<string> = Object.keys(params as Object);
        const ok: boolean = keys.includes('mangaId') && keys.includes('chapterId') && keys.includes('candidatePaths');
        if (params && ok) {
          this.pageParams = params as CoverSelectionPageParams;
          logger.info(TAG, `✅ Router 参数解析成功: mangaId=${this.pageParams.mangaId}, chapterId=${this.pageParams.chapterId}, 候选数量=${this.pageParams.candidatePaths.length}, from=${this.pageParams.fromPage}`);
          const previewCount: number = Math.min(5, this.pageParams.candidatePaths.length);
          for (let i = 0; i < previewCount; i++) {
            logger.debug(TAG, `候选路径[${i}]: ${this.pageParams.candidatePaths[i]}`);
          }
        } else {
          logger.error(TAG, '❌ Router 参数不存在或不完整，保持默认参数');
        }
      }
    } catch (err2) {
      logger.error(TAG, '获取 Router 参数异常', String(err2));
    }
  }

  private cancelSelection(): void {
    logger.info(TAG, '用户取消封面选择');
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回上一页失败', String(error));
    }
  }

  // 沉浸式标题栏
  @Builder
  private buildTopBar(): void {
    Row() {
      Text('选择封面')
        .fontSize(20)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
    }
    .height(TITLE_BAR_HEIGHT_MINI)
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }

  // 候选图片列表
  @Builder
  private buildCandidates(): void {
    Column() {
      if (this.isLoading) {
        Text('加载中...')
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else if (this.loadError !== '') {
        Text(this.loadError)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('error_text', this.themeState.currentTheme))
      } else if (!this.candidateThumbnails || this.candidateThumbnails.length === 0) {
        Text('没有可显示的缩略图')
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        // 修复：避免 Scroll + List 双重滚动导致内容不可见，改用 Column 渲染
        ForEach(this.candidateThumbnails, (pm: image.PixelMap, index: number) => {
          Row() {
            Image(pm)
              .width(240)
              .height(320)
              .borderRadius(8)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))

            Column() {
              // 不再显示路径文本
              // Text(this.pageParams.candidatePaths[index])
              //   .fontSize(12)
              //   .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

              Radio({ group: 'cover_select', value: `${index}` })
                .checked(this.selectedIndex === index)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.selectedIndex = index;
                    logger.debug(TAG, `用户选择封面索引=${index}`);
                  }
                })
            }
            .margin({ left: 12 })
          }
          .width('100%')
          .height(330)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        })
      }
    }
    .width('100%')
    // 不限制固定高度，交由外部 Scroll 负责滚动
  }

  // 底部操作区
  @Builder
  private buildActions(): void {
    Row() {
      Button({ stateEffect: true }) {
        Text('不设定封面')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .key('cancel_button')
      .height(40)
      .layoutWeight(1)
      // .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
      .borderRadius(20) // 圆角胶囊型
      .type(ButtonType.Capsule) // 胶囊型按钮
      .onClick(() => this.cancelSelection())

      Button({ stateEffect: true }) {
        Text('设定封面')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .key('confirm_button')
      .height(40)
      .layoutWeight(1)
      // .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
      .borderRadius(20) // 圆角胶囊型
      .type(ButtonType.Capsule) // 胶囊型按钮
      .enabled(this.selectedIndex >= 0)
      .onClick(() => {
        logger.info(TAG, `点击确定，当前选中索引=${this.selectedIndex}`);
          this.confirmSelection();
        })
        .stateEffect(true)
        .height(40)
        .layoutWeight(1)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    // .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
  }

  build() {
    // 使用 HdsNavDestination() + 链式 .titleBar/.onReady，与 DataManagementPage 保持一致
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        // 内容层：Scroll + Column，预留标题栏高度，避免重叠
        Scroll() {
          Column({ space: 24 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            // 页面主体
            this.buildCandidates()
            this.buildActions()

            Blank().height(20)
          }
          .width('100%')
          .padding({ bottom: 20 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            },
            menuStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            },
            menuStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: '选择封面'
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'CoverSelectionPage HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack as NavPathStack;
      logger.debug(TAG, '✅ onReady 绑定 pathStack 完成');
      this.uiContext = this.getUIContext();
      // 统一在 onReady 中解析参数并触发预加载，避免候选为空
      this.parsePageParamsFromNavStack();
      setTimeout(() => { this.preloadThumbnails(); }, 0);
    })
    .backgroundColor(Color.Transparent)
  }
}

