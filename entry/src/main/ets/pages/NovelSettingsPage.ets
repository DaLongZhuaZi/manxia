/**
 * 小说功能设置页面
 * 提供书源管理、规则管理入口以及全局设置
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSettingsPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const TAG = 'NovelSettingsPage';
const TITLE_BAR_HEIGHT_MINI = 56;
const NOVEL_SETTINGS_STORE = 'novel_settings';

/**
 * 小说全局设置接口
 */
interface NovelGlobalSettings {
  searchConcurrency: number;       // 搜索并发数
  defaultLoadChapters: number;     // 默认加载章节数
  enableReadWhileDownload: boolean; // 边看边下载
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
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSettingsPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 全局设置状态
  @State settings: NovelGlobalSettings = {
    searchConcurrency: 5,
    defaultLoadChapters: 50,
    enableReadWhileDownload: true
  };
  
  @State isLoading: boolean = true;
  @State showRuleTypeDialog: boolean = false;
  
  // 功能入口配置
  private featureTiles: FeatureTile[] = [
    {
      title: '书源管理',
      subtitle: '管理小说书源',
      icon: $r('sys.symbol.doc_text'),
      iconColor: '#4CAF50',
      route: 'NovelSourceManagementPage'
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
      icon: $r('sys.symbol.gearshape'),
      iconColor: '#FF9800',
      route: 'NovelSourceDebugPage'
    },
    {
      title: 'JSVM Playground',
      subtitle: 'JavaScript代码测试环境',
      icon: $r('app.media.ic_terminal'),
      iconColor: '#607D8B',
      route: 'JsvmPlaygroundPage'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    this.loadSettings();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 加载设置
   */
  async loadSettings(): Promise<void> {
    this.isLoading = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      
      this.settings = {
        searchConcurrency: await store.get('searchConcurrency', 5) as number,
        defaultLoadChapters: await store.get('defaultLoadChapters', 50) as number,
        enableReadWhileDownload: await store.get('enableReadWhileDownload', true) as boolean
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
      const context = getContext(this) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      
      await store.put('searchConcurrency', this.settings.searchConcurrency);
      await store.put('defaultLoadChapters', this.settings.defaultLoadChapters);
      await store.put('enableReadWhileDownload', this.settings.enableReadWhileDownload);
      await store.flush();
      
      logger.info(TAG, `设置保存完成`);
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
      promptAction.showToast({ message: '保存设置失败' });
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
        Column() {
          Scroll() {
            Column() {
              // 功能入口磁贴区域
              this.buildFeatureTilesSection()
              
              // 全局设置区域
              this.buildGlobalSettingsSection()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 32 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
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
          mainTitle: '小说设置'
        }
      }
    })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      Text(tile.subtitle)
        .fontSize(11)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .width('47%')
    .padding(16)
    .margin({ right: '3%', bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
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
      }
      .width('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
  }

  @Builder
  buildSettingItem(title: string, subtitle: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(subtitle)
          .fontSize(12)
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(subtitle)
          .fontSize(12)
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
    
    promptAction.showActionMenu({
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
        promptAction.showToast({ message: `已设置为同时搜索 ${this.settings.searchConcurrency} 个书源` });
      }
    }).catch(() => {
      // 用户取消
    });
  }

  /**
   * 显示章节数选择器
   */
  showChapterCountPicker(): void {
    promptAction.showActionMenu({
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
        promptAction.showToast({ message: msg });
      }
    }).catch(() => {
      // 用户取消
    });
  }
}
