import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 字典规则管理页面
 * 管理在线词典查询规则
 * 
 * 文件路径: entry/src/main/ets/pages/NovelDictRulePage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelDictRuleManager, DictRule, AddDictRuleParams } from '../Framework/Novel/NovelDictRuleManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

const TAG = 'NovelDictRulePage';

@Component
export struct NovelDictRulePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelDictRulePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State rules: DictRule[] = [];
  @State isLoading: boolean = true;
  @State showAddDialog: boolean = false;
  @State editingRule: DictRule | null = null;
  
  // 表单数据
  @State formName: string = '';
  @State formUrlRule: string = '';
  @State formShowRule: string = '';
  
  // 测试相关
  @State testWord: string = '';
  @State testResult: string = '';
  @State isTesting: boolean = false;
  
  private ruleManager = getNovelDictRuleManager();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
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
    this.formUrlRule = '';
    this.formShowRule = '';
    this.editingRule = null;
    this.testWord = '';
    this.testResult = '';
  }

  async saveRule(): Promise<void> {
    if (!this.formName.trim() || !this.formUrlRule.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写规则名称和 URL 规则' });
      return;
    }

    // 验证URL规则包含占位符
    if (!this.formUrlRule.includes('{{key}}')) {
      this.getUIContext().getPromptAction().showToast({ message: 'URL 规则必须包含 {{key}} 占位符' });
      return;
    }

    try {
      const params: AddDictRuleParams = {
        name: this.formName.trim(),
        urlRule: this.formUrlRule,
        showRule: this.formShowRule,
        enabled: true
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

  async deleteRule(rule: DictRule): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除规则 "${rule.name}" 吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await this.ruleManager.deleteRule(rule.id);
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.loadRules();
      }
    });
  }

  async toggleRuleEnabled(rule: DictRule): Promise<void> {
    await this.ruleManager.setRuleEnabled(rule.id, !rule.enabled);
    this.loadRules();
  }

  editRule(rule: DictRule): void {
    this.editingRule = rule;
    this.formName = rule.name;
    this.formUrlRule = rule.urlRule;
    this.formShowRule = rule.showRule;
    this.showAddDialog = true;
  }

  async testDictRule(): Promise<void> {
    if (!this.formUrlRule.trim()) {
      this.testResult = '请先输入 URL 规则';
      return;
    }
    if (!this.testWord.trim()) {
      this.testResult = '请输入测试词语';
      return;
    }

    this.isTesting = true;
    this.testResult = '正在查询...';

    try {
      // 构建测试URL
      const testUrl = this.formUrlRule.replace(/\{\{key\}\}/g, encodeURIComponent(this.testWord));
      this.testResult = `生成的 URL:\n${testUrl}`;
    } catch (error) {
      this.testResult = `测试失败: ${String(error)}`;
    }

    this.isTesting = false;
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

  async importFromClipboard(): Promise<void> {
    try {
      const pasteData = pasteboard.getSystemPasteboard();
      const data = await pasteData.getData();
      if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        const text = data.getPrimaryText();
        if (text) {
          const result = await this.ruleManager.importFromJSON(text);
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

      logger.info(TAG, '打开文件选择器，选择字典规则文件');
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
      const result = await this.ruleManager.importFromJSON(jsonContent);
      
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

  async exportToClipboard(): Promise<void> {
    try {
      const json = this.ruleManager.exportToJSON();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `导出失败: ${String(error)}` });
    }
  }

  async resetToDefault(): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认重置',
      message: '确定要重置为默认规则吗？这将删除所有自定义规则。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '重置', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await this.ruleManager.resetToDefault();
        this.getUIContext().getPromptAction().showToast({ message: '已重置为默认规则' });
        this.loadRules();
      }
    });
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
      },
      {
        id: 'reset',
        label: '重置',
        symbol: $r('sys.symbol.arrow_counterclockwise'),
        onClick: () => {
          void this.resetToDefault();
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
            ForEach(this.rules, (rule: DictRule) => {
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

        // 添加/编辑对话框
        if (this.showAddDialog) {
          this.buildAddDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '字典规则',
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
    .onReady((context: NavDestinationContext) => {
      this.loadRules();
    })
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
      Text('暂无字典规则')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Button('添加规则')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .margin({ top: 24 })
        .onClick(() => {
          this.resetForm();
          this.showAddDialog = true;
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildRuleList() {
    List() {
      ForEach(this.rules, (rule: DictRule) => {
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
  buildRuleItem(rule: DictRule) {
    Row() {
      // 状态指示
      Column()
        .width(4)
        .height(40)
        .borderRadius(2)
        .backgroundColor(rule.enabled ? '#52C41A' : '#D9D9D9')
      
      // 信息
      Column() {
        Text(rule.name)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(rule.urlRule)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      
      // 开关
      Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.toggleRuleEnabled(rule);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
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
    .onClick(() => {
      this.editRule(rule);
    })
  }

  @Builder
  buildSwipeActions(rule: DictRule) {
    Row() {
      Button('删除')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
        .width(80)
        .height('100%')
        .onClick(() => this.deleteRule(rule))
    }
  }

  @Builder
  buildAddDialog() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.showAddDialog = false;
          this.resetForm();
        })
        .transition(TransitionEffect.opacity(0).animation({ duration: 250, curve: Curve.EaseOut }))
      
      // 对话框
      Column() {
        Text(this.editingRule ? '编辑规则' : '添加规则')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 20 })
        
        // 规则名称
        TextInput({ placeholder: '规则名称 (如: 百度百科)', text: this.formName })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formName = value;
          })
        
        // URL规则
        TextArea({ placeholder: 'URL规则 (使用 {{key}} 作为关键词占位符)\n如: https://baike.baidu.com/item/{{key}}', text: this.formUrlRule })
          .width('100%')
          .height(80)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formUrlRule = value;
          })
        
        // 显示规则（可选）
        TextInput({ placeholder: '显示规则 (可选，用于提取结果的正则)', text: this.formShowRule })
          .width('100%')
          .height(44)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formShowRule = value;
          })
        
        // 测试区域
        Text('测试规则')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 16 })
          .alignSelf(ItemAlign.Start)
        
        Row() {
          TextInput({ placeholder: '输入测试词语...', text: this.testWord })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(8)
            .onChange((value: string) => {
              this.testWord = value;
            })
          
          Button('测试')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .borderRadius(16)
            .margin({ left: 8 })
            .enabled(!this.isTesting)
            .onClick(() => this.testDictRule())
        }
        .width('100%')
        .margin({ top: 8 })
        
        if (this.testResult) {
          Text(this.testResult)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.testResult.startsWith('生成的 URL') ? '#52C41A' : '#FF4D4F')
            .margin({ top: 8 })
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        // 按钮
        Row() {
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(20)
            .layoutWeight(1)
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
            .borderRadius(20)
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => this.saveRule())
        }
        .width('100%')
        .margin({ top: 16, bottom: 20 })
      }
      .width('90%')
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
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 6,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
      .padding({ left: 20, right: 20 })
      .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 }).combine(TransitionEffect.opacity(0)).animation({ duration: 250, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
