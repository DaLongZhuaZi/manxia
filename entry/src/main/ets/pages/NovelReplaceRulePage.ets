import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 小说替换净化规则管理页面
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelReplaceRulePage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelReplaceRuleManager, ReplaceRule, ReplaceScope, AddRuleParams } from '../Framework/Novel/NovelReplaceRuleManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

const TAG = 'NovelReplaceRulePage';

@Component
export struct NovelReplaceRulePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelReplaceRulePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  
  @State rules: ReplaceRule[] = [];
  @State isLoading: boolean = true;
  @State showAddDialog: boolean = false;
  @State editingRule: ReplaceRule | null = null;
  
  // 表单数据
  @State formName: string = '';
  @State formPattern: string = '';
  @State formReplacement: string = '';
  @State formIsRegex: boolean = true;
  @State formScope: ReplaceScope = ReplaceScope.CONTENT;
  
  private ruleManager = getNovelReplaceRuleManager();

  aboutToAppear(): void {
    // Re-capture mode on each enter to avoid stale restore target.
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    logger.info(TAG, `记录进入净化规则页前显示模式: mode=${this.previousDisplayMode}`);
    // Use default mode so system status bar avoidance works reliably.
    PageWindowCoordinator.applyPagePolicy('NovelReplaceRulePage', this.getUIContext());
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    logger.info(TAG, `离开净化规则页，恢复显示模式: mode=${this.previousDisplayMode}`);
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  async loadRules(): Promise<void> {
    this.isLoading = true;
    try {
      // 确保管理器已初始化
      await this.ruleManager.initialize();
      this.rules = this.ruleManager.getAllRules();
    } catch (error) {
      logger.error(TAG, `加载规则失败: ${String(error)}`);
    }
    this.isLoading = false;
  }

  resetForm(): void {
    this.formName = '';
    this.formPattern = '';
    this.formReplacement = '';
    this.formIsRegex = true;
    this.formScope = ReplaceScope.CONTENT;
    this.editingRule = null;
  }

  async saveRule(): Promise<void> {
    if (!this.formName.trim() || !this.formPattern.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写规则名称和匹配内容' });
      return;
    }

    try {
      const params: AddRuleParams = {
        name: this.formName.trim(),
        pattern: this.formPattern,
        replacement: this.formReplacement,
        isRegex: this.formIsRegex,
        scope: this.formScope,
        enabled: true,
        order: this.rules.length
      };

      if (this.editingRule) {
        await this.ruleManager.updateRule(this.editingRule.id, params);
        this.getUIContext().getPromptAction().showToast({ message: '规则已更新' });
      } else {
        await this.ruleManager.addRule(params);
        this.getUIContext().getPromptAction().showToast({ message: '规则已添加' });
      }

      this.showAddDialog = false;
      this.resetForm();
      this.loadRules();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `保存失败: ${String(error)}` });
    }
  }

  async deleteRule(rule: ReplaceRule): Promise<void> {
    try {
      await this.ruleManager.deleteRule(rule.id);
      this.getUIContext().getPromptAction().showToast({ message: '规则已删除' });
      this.loadRules();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${String(error)}` });
    }
  }

  async toggleRule(rule: ReplaceRule): Promise<void> {
    await this.ruleManager.setRuleEnabled(rule.id, !rule.enabled);
    this.loadRules();
  }

  editRule(rule: ReplaceRule): void {
    this.editingRule = rule;
    this.formName = rule.name;
    this.formPattern = rule.pattern;
    this.formReplacement = rule.replacement;
    this.formIsRegex = rule.isRegex;
    this.formScope = rule.scope;
    this.showAddDialog = true;
  }

  /**
   * 显示导入选项菜单
   */
  showImportOptions(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择导入方式',
      buttons: [
        { text: '从剪贴板导入', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '从本地文件导入', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      switch (result.index) {
        case 0:
          this.importFromClipboard();
          break;
        case 1:
          this.importFromFile();
          break;
      }
    }).catch(() => {});
  }

  /**
   * 从剪贴板导入规则
   */
  async importFromClipboard(): Promise<void> {
    try {
      const pasteData = pasteboard.getSystemPasteboard();
      const data = await pasteData.getData();
      if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        const text = data.getPrimaryText();
        if (text) {
          const result = await this.ruleManager.importRules(text);
          this.getUIContext().getPromptAction().showToast({ 
            message: `导入完成: ${result.success}/${result.total} 成功` 
          });
          this.loadRules();
        }
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  /**
   * 从本地文件导入规则
   */
  async importFromFile(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      if (!context) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取应用上下文' });
        return;
      }

      const documentPicker = new picker.DocumentViewPicker(context);
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1,
        fileSuffixFilters: ['.json', '.txt'],
      };

      logger.info(TAG, '打开文件选择器，选择替换规则文件');
      const selectResult = await documentPicker.select(selectOptions);
      
      if (!selectResult || selectResult.length === 0) {
        logger.info(TAG, '用户取消了文件选择');
        return;
      }

      const fileUri = selectResult[0];
      logger.info(TAG, `用户选择了文件: ${fileUri}`);
      
      // 读取文件内容
      const file = SafeFileUtils.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(file.fd);
      const fileSize = stat.size;
      
      if (fileSize > 50 * 1024 * 1024) {
        SafeFileUtils.closeSync(file);
        this.getUIContext().getPromptAction().showToast({ message: '文件过大，最大支持50MB' });
        return;
      }
      
      const buffer = new ArrayBuffer(fileSize);
      SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);
      
      const uint8Array = new Uint8Array(buffer);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const jsonContent = decoder.decodeToString(uint8Array);
      
      logger.info(TAG, `读取到文件内容，长度: ${jsonContent.length}`);
      
      // 导入规则
      const result = await this.ruleManager.importRules(jsonContent);
      
      if (result.success > 0) {
        this.getUIContext().getPromptAction().showToast({ 
          message: `导入完成: ${result.success}/${result.total} 成功` 
        });
        this.loadRules();
      } else {
        this.getUIContext().getPromptAction().showToast({ 
          message: `导入失败: ${result.errors.join(', ')}` 
        });
      }
    } catch (error) {
      logger.error(TAG, `从文件导入失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  /**
   * 导出规则到剪贴板
   */
  async exportToClipboard(): Promise<void> {
    try {
      const json = this.ruleManager.exportRules();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `导出失败: ${String(error)}` });
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'add',
        label: '添加',
        symbol: $r('sys.symbol.plus'),
        onClick: () => {
          this.resetForm();
          this.showAddDialog = true;
        }
      },
      {
        id: 'import',
        label: '导入',
        symbol: $r('sys.symbol.download'),
        onClick: () => {
          this.showImportOptions();
        }
      },
      {
        id: 'export',
        label: '导出',
        symbol: $r('sys.symbol.upload'),
        onClick: () => {
          void this.exportToClipboard();
        }
      }
    ];
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        if (this.isLoading) {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildLoading()
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else if (this.rules.length === 0) {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildEmpty()
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else {
          List() {
            ListItem() {
              Column()
                .width('100%')
                .height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            }
            ForEach(this.rules, (rule: ReplaceRule) => {
              ListItem() {
                this.buildRuleItem(rule)
              }
              .swipeAction({
                end: this.buildSwipeActions(rule)
              })
            })
            ListItem() { Row().width('100%').height(24 + this.navigationBarHeight) }
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .padding({ top: 8, bottom: 8 })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
        }

        if (this.showAddDialog) {
          this.buildAddDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '替换净化规则',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onWillAppear(() => {
      PageWindowCoordinator.applyPagePolicy('NovelReplaceRulePage', this.getUIContext());
    })
    .onWillShow(() => {
      PageWindowCoordinator.reapplyPagePolicy('NovelReplaceRulePage', this.getUIContext());
    })
    .onReady((context: NavDestinationContext) => {
      this.ruleManager.initialize().then(() => {
        this.loadRules();
      });
    })
    .onShown(() => {
      PageWindowCoordinator.reapplyPagePolicy('NovelReplaceRulePage', this.getUIContext());
      logger.info(TAG, '净化规则页 onShown 重新应用默认显示模式');
    })
  }

  @Builder
  buildTopBar() {
    Row() {
      Image($r('sys.symbol.arrow_left'))
        .width(24)
        .height(24)
        .margin({ left: 16 })
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .onClick(() => this.pathStack.pop())
      
      Text('替换净化规则')
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ left: 16 })
      
      Blank()
      
      Text('添加')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .margin({ right: 16 })
        .onClick(() => {
          this.resetForm();
          this.showAddDialog = true;
        })
    }
    .width('100%')
    .height(56)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildEmpty() {
    Column() {
      Text('暂无替换规则')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Text('点击右上角"添加"创建规则')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildRuleList() {
    List() {
      ForEach(this.rules, (rule: ReplaceRule) => {
        ListItem() {
          this.buildRuleItem(rule)
        }
        .swipeAction({
          end: this.buildSwipeActions(rule)
        })
      })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 8 })
  }

  @Builder
  buildRuleItem(rule: ReplaceRule) {
    Row() {
      Column() {
        Row() {
          Text(rule.name)
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          
          Text(rule.isRegex ? '正则' : '普通')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(rule.isRegex ? '#1890FF' : '#52C41A')
            .backgroundColor(rule.isRegex ? '#E6F7FF' : '#F6FFED')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius(2)
            .margin({ left: 8 })
          
          Text(this.getScopeText(rule.scope))
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor('#FA8C16')
            .backgroundColor('#FFF7E6')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius(2)
            .margin({ left: 4 })
        }
        .width('100%')
        
        Text(`匹配: ${rule.pattern}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(`替换: ${rule.replacement || '(删除)'}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange(() => this.toggleRule(rule))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
    .margin({ bottom: 8 })
    .onClick(() => this.editRule(rule))
  }

  @Builder
  buildSwipeActions(rule: ReplaceRule) {
    Row() {
      Button('删除')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor('#FF4D4F')
        .width(80)
        .height('100%')
        .onClick(() => this.deleteRule(rule))
    }
  }

  @Builder
  buildAddDialog() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.showAddDialog = false;
          this.resetForm();
        })
        .transition(TransitionEffect.opacity(0).animation({ duration: 250, curve: Curve.EaseOut }))
      
      Column() {
        Text(this.editingRule ? '编辑规则' : '添加规则')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 20 })
        
        // 规则名称
        TextInput({ placeholder: '规则名称', text: this.formName })
          .width('90%')
          .height(44)
          .margin({ top: 16 })
          .onChange((value: string) => { this.formName = value; })
        
        // 匹配内容
        TextArea({ placeholder: '匹配内容（正则或普通文本）', text: this.formPattern })
          .width('90%')
          .height(80)
          .margin({ top: 12 })
          .onChange((value: string) => { this.formPattern = value; })
        
        // 替换内容
        TextInput({ placeholder: '替换为（留空则删除匹配内容）', text: this.formReplacement })
          .width('90%')
          .height(44)
          .margin({ top: 12 })
          .onChange((value: string) => { this.formReplacement = value; })
        
        // 选项
        Row() {
          Text('正则表达式')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Toggle({ type: ToggleType.Switch, isOn: this.formIsRegex })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onChange((isOn: boolean) => { this.formIsRegex = isOn; })
        }
        .width('90%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 12 })
        
        // 作用范围
        Row() {
          Text('作用范围')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Row() {
            this.buildScopeOption('全部', ReplaceScope.ALL)
            this.buildScopeOption('标题', ReplaceScope.TITLE)
            this.buildScopeOption('正文', ReplaceScope.CONTENT)
          }
        }
        .width('90%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 12 })
        
        // 按钮
        Row() {
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .layoutWeight(1)
            .height(44)
            .margin({ right: 8 })
            .onClick(() => {
              this.showAddDialog = false;
              this.resetForm();
            })
          
          Button('保存')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .layoutWeight(1)
            .height(44)
            .margin({ left: 8 })
            .onClick(() => this.saveRule())
        }
        .width('90%')
        .margin({ top: 24, bottom: 24 })
      }
      .width('100%')
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius({
        topLeft: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme),
        topRight: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)
      })
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 6,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: -2
      })
      .transition(TransitionEffect.translate({ y: 300 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildScopeOption(label: string, scope: ReplaceScope) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.formScope === scope ? '#FFFFFF' : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .backgroundColor(this.formScope === scope ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .margin({ left: 4 })
      .onClick(() => { this.formScope = scope; })
  }

  getScopeText(scope: ReplaceScope): string {
    switch (scope) {
      case ReplaceScope.ALL: return '全部';
      case ReplaceScope.TITLE: return '标题';
      case ReplaceScope.CONTENT: return '正文';
      default: return '未知';
    }
  }
}
