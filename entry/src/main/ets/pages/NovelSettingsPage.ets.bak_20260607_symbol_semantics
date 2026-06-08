/**
 * 小说功能设置页面
 * 提供书源管理、规则管理入口以及全局设置
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSettingsPage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'NovelSettingsPage';
const NOVEL_SETTINGS_STORE = 'novel_settings';

/**
 * 小说全局设置接口
 */
interface NovelGlobalSettings {
  searchConcurrency: number;       // 搜索并发数
  defaultLoadChapters: number;     // 默认加载章节数
  enableReadWhileDownload: boolean; // 边看边下载
  autoRefreshSource: boolean;      // 自动刷新书源
  enableSearchHistory: boolean;    // 启用搜索历史
  maxSearchHistory: number;        // 最大搜索历史条数
}

/**
 * 功能入口磁贴配置
 */
interface FeatureTile {
  title: string;
  subtitle: string;
  icon: Resource;
  iconColor: string;
  route: string;
}

/**
 * 规则类型枚举
 */
enum RuleType {
  REPLACE = 'replace',   // 替换净化规则
  SEARCH = 'search',     // 搜索规则（预留）
  DISCOVER = 'discover'  // 发现规则（预留）
}

@Component
export struct NovelSettingsPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSettingsPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 全局设置状态
  @State settings: NovelGlobalSettings = {
    searchConcurrency: 5,
    defaultLoadChapters: 50,
    enableReadWhileDownload: true,
    autoRefreshSource: false,
    enableSearchHistory: true,
    maxSearchHistory: 20
  };
  
  @State isLoading: boolean = true;
  @State showRuleTypeDialog: boolean = false;
  
  // 功能入口配置
  private featureTiles: FeatureTile[] = [
    {
      title: '阅读设置',
      subtitle: '字体、背景、翻页等',
      icon: $r('sys.symbol.textformat'),
      iconColor: '#E91E63',
      route: 'ReadingSettingsSubPage'
    },
    {
      title: '书源管理',
      subtitle: '管理小说书源',
      icon: $r('sys.symbol.text_book_closed'),
      iconColor: '#4CAF50',
      route: 'NovelSourceManagementPage'
    },
    {
      title: '订阅源',
      subtitle: '查看 RSS 订阅内容',
      icon: $r('sys.symbol.list_bullet'),
      iconColor: '#009688',
      route: 'RssSubscriptionPage'
    },
    {
      title: 'RSS收藏',
      subtitle: '查看已收藏的订阅条目',
      icon: $r('sys.symbol.star'),
      iconColor: '#FF9800',
      route: 'RssFavoritesPage'
    },
    {
      title: '订阅源管理',
      subtitle: '新增、编辑、刷新 RSS 源',
      icon: $r('sys.symbol.rectangle_stack'),
      iconColor: '#3F51B5',
      route: 'RssSubscriptionManagementPage'
    },
    {
      title: '订阅源调试',
      subtitle: '调试订阅源解析与刷新流程',
      icon: $r('sys.symbol.wrench_and_screwdriver'),
      iconColor: '#5C6BC0',
      route: 'RssSourceDebugPage'
    },
    {
      title: '替换净化规则',
      subtitle: '内容替换与净化',
      icon: $r('sys.symbol.arrow_left_arrow_right'),
      iconColor: '#2196F3',
      route: 'NovelReplaceRulePage'
    },
    {
      title: 'TXT目录规则',
      subtitle: '本地TXT章节识别',
      icon: $r('sys.symbol.list_bullet'),
      iconColor: '#9C27B0',
      route: 'NovelTxtTocRulePage'
    },
    {
      title: '字典规则',
      subtitle: '在线词典查询',
      icon: $r('sys.symbol.book'),
      iconColor: '#00BCD4',
      route: 'NovelDictRulePage'
    },
    {
      title: '书源调试',
      subtitle: '测试书源各项功能',
      icon: $r('sys.symbol.wrench_and_screwdriver'),
      iconColor: '#FF9800',
      route: 'NovelSourceDebugPage'
    },
    {
      title: 'JSVM Playground',
      subtitle: 'JavaScript代码测试环境',
      icon: $r('sys.symbol.wrench_and_screwdriver'),
      iconColor: '#607D8B',
      route: 'JsvmPlaygroundPage'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    this.loadSettings();
  }

  private lifecycle = new PageLifecycleManager('NovelSettingsPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  /**
   * 加载设置
   */
  async loadSettings(): Promise<void> {
    this.isLoading = true;
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      
      this.settings = {
        searchConcurrency: await store.get('searchConcurrency', 5) as number,
        defaultLoadChapters: await store.get('defaultLoadChapters', 50) as number,
        enableReadWhileDownload: await store.get('enableReadWhileDownload', true) as boolean,
        autoRefreshSource: await store.get('autoRefreshSource', false) as boolean,
        enableSearchHistory: await store.get('enableSearchHistory', true) as boolean,
        maxSearchHistory: await store.get('maxSearchHistory', 20) as number
      };
      
      logger.info(TAG, `设置加载完成: ${JSON.stringify(this.settings)}`);
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
    this.isLoading = false;
  }

  /**
   * 保存设置
   */
  async saveSettings(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      
      await store.put('searchConcurrency', this.settings.searchConcurrency);
      await store.put('defaultLoadChapters', this.settings.defaultLoadChapters);
      await store.put('enableReadWhileDownload', this.settings.enableReadWhileDownload);
      await store.put('autoRefreshSource', this.settings.autoRefreshSource);
      await store.put('enableSearchHistory', this.settings.enableSearchHistory);
      await store.put('maxSearchHistory', this.settings.maxSearchHistory);
      await store.flush();
      
      logger.info(TAG, `设置保存完成`);
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存设置失败' });
    }
  }

  /**
   * 导航到指定页面
   */
  navigateTo(route: string): void {
    this.pathStack.pushPathByName(route, null);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景，避免页面转场时重叠
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层
        Column() {
          Scroll() {
            Column() {
              // 标题栏占位
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              
              // 功能入口磁贴区域
              this.buildFeatureTilesSection()
              
              // 全局设置区域
              
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 + this.navigationBarHeight })
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '小说设置',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady(() => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    })
  }

  @Builder
  buildFeatureTilesSection() {
    Column() {
      Text('功能入口')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ top: 16, bottom: 12 })
      
      // 磁贴网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.featureTiles, (tile: FeatureTile) => {
          this.buildFeatureTile(tile)
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildFeatureTile(tile: FeatureTile) {
    Column() {
      Row() {
        SymbolGlyph(tile.icon)
          .fontSize(28)
          .fontColor([tile.iconColor])
      }
      .width(56)
      .height(56)
      .backgroundColor(tile.iconColor + '20')
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 12 })
      
      Text(tile.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      Text(tile.subtitle)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .width('47%')
    .padding(16)
    .margin({ right: '3%', bottom: 12 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.navigateTo(tile.route);
    })
  }

  @Builder
  buildGlobalSettingsSection() {
    Column() {
      Text('全局设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ top: 24, bottom: 12 })
      
      Column() {
        // 搜索并发设置
        this.buildSettingItem(
          '搜索并发数',
          `同时搜索 ${this.settings.searchConcurrency} 个书源`,
          () => {
            this.showConcurrencyPicker();
          }
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })
        
        // 默认加载章节数
        this.buildSettingItem(
          '默认加载章节数',
          `每次加载 ${this.settings.defaultLoadChapters} 章`,
          () => {
            this.showChapterCountPicker();
          }
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })
        
        // 边看边下载
        this.buildToggleSettingItem(
          '边看边下载',
          '阅读时自动缓存后续章节',
          this.settings.enableReadWhileDownload,
          (value: boolean) => {
            this.settings.enableReadWhileDownload = value;
            this.saveSettings();
          }
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })
        
        // 自动刷新书源
        this.buildToggleSettingItem(
          '自动刷新书源',
          '打开应用时自动检查书源更新',
          this.settings.autoRefreshSource,
          (value: boolean) => {
            this.settings.autoRefreshSource = value;
            this.saveSettings();
            this.getUIContext().getPromptAction().showToast({ message: value ? '已开启自动刷新' : '已关闭自动刷新' });
          }
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })
        
        // 启用搜索历史
        this.buildToggleSettingItem(
          '启用搜索历史',
          '保存并显示搜索历史记录',
          this.settings.enableSearchHistory,
          (value: boolean) => {
            this.settings.enableSearchHistory = value;
            this.saveSettings();
            this.getUIContext().getPromptAction().showToast({ message: value ? '已开启搜索历史' : '已关闭搜索历史' });
          }
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })
        
        // 最大搜索历史条数
        this.buildSettingItem(
          '最大搜索历史条数',
          `最多保存 ${this.settings.maxSearchHistory} 条记录`,
          () => {
            this.showHistoryCountPicker();
          }
        )
      }
      .width('100%')
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
  }

  @Builder
  buildSettingItem(title: string, subtitle: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(subtitle)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(16)
    .onClick(onClick)
  }

  @Builder
  buildToggleSettingItem(title: string, subtitle: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(subtitle)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange(onChange)
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 显示搜索并发数选择器
   */
  showConcurrencyPicker(): void {
    const options: number[] = [1, 3, 5, 8, 10, 15, 20];
    
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择搜索并发数',
      buttons: [
        { text: '1 个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '3 个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '5 个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '10 个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '20 个书源', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      const values: number[] = [1, 3, 5, 10, 20];
      if (result.index >= 0 && result.index < values.length) {
        this.settings.searchConcurrency = values[result.index];
        this.saveSettings();
        this.getUIContext().getPromptAction().showToast({ message: `已设置为同时搜索 ${this.settings.searchConcurrency} 个书源` });
      }
    }).catch(() => {
      // 用户取消
    });
  }

  /**
   * 显示章节数选择器
   */
  showChapterCountPicker(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择默认加载章节数',
      buttons: [
        { text: '20 章', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '50 章', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '100 章', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '200 章', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '全部章节', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      const values: number[] = [20, 50, 100, 200, 9999];
      if (result.index >= 0 && result.index < values.length) {
        this.settings.defaultLoadChapters = values[result.index];
        this.saveSettings();
        const msg = this.settings.defaultLoadChapters >= 9999 ? '已设置为加载全部章节' : `已设置为每次加载 ${this.settings.defaultLoadChapters} 章`;
        this.getUIContext().getPromptAction().showToast({ message: msg });
      }
    }).catch(() => {
      // 用户取消
    });
  }

  /**
   * 显示搜索历史条数选择器
   */
  showHistoryCountPicker(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择最大搜索历史条数',
      buttons: [
        { text: '10 条', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '20 条', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '50 条', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '100 条', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '不限制', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      const values: number[] = [10, 20, 50, 100, 9999];
      if (result.index >= 0 && result.index < values.length) {
        this.settings.maxSearchHistory = values[result.index];
        this.saveSettings();
        const msg = this.settings.maxSearchHistory >= 9999 ? '已设置为不限制搜索历史条数' : `已设置为最多保存 ${this.settings.maxSearchHistory} 条记录`;
        this.getUIContext().getPromptAction().showToast({ message: msg });
      }
    }).catch(() => {
      // 用户取消
    });
  }
}
