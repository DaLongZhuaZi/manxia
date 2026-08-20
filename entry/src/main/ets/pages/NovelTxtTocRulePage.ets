import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * TXT目录规则管理页面
 * ????TXT?????????
 * 
 * 文件路径: entry/src/main/ets/pages/NovelTxtTocRulePage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelTxtTocRuleManager, TxtTocRule, AddTxtTocRuleParams } from '../Framework/Novel/NovelTxtTocRuleManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'NovelTxtTocRulePage';
@Component
export struct NovelTxtTocRulePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelTxtTocRulePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  
  @State rules: TxtTocRule[] = [];
  @State isLoading: boolean = true;
  @State showAddDialog: boolean = false;
  @State editingRule: TxtTocRule | null = null;
  
  // 表单数据
  @State formName: string = '';
  @State formRule: string = '';
  @State formExample: string = '';
  
  // 测试相关
  @State testText: string = '';
  @State testResult: string = '';
  
  private ruleManager = getNovelTxtTocRuleManager();

  aboutToAppear(): void {
    // Re-capture mode on each enter to avoid stale restore target.
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    logger.info(TAG, `记录进入TXT目录规则页前显示模式: mode=${this.previousDisplayMode}`);
    // Use default mode so system status bar avoidance works reliably.
    PageWindowCoordinator.applyPagePolicy('NovelTxtTocRulePage', this.getUIContext());
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    logger.info(TAG, `离开TXT目录规则页，恢复显示模式: mode=${this.previousDisplayMode}`);
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  async loadRules(): Promise<void> {
    this.isLoading = true;
    try {
      // ?????????
      await this.ruleManager.initialize();
      this.rules = this.ruleManager.getAllRules();
    } catch (error) {
      logger.error(TAG, `加载规则失败: ${String(error)}`);
    }
    this.isLoading = false;
  }

  resetForm(): void {
    this.formName = '';
    this.formRule = '';
    this.formExample = '';
    this.editingRule = null;
    this.testText = '';
    this.testResult = '';
  }

  async saveRule(): Promise<void> {
    if (!this.formName.trim() || !this.formRule.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写规则名称和正则表达式' });
      return;
    }

    // ???????
    try {
      new RegExp(this.formRule);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `???????: ${String(error)}` });
      return;
    }

    try {
      const params: AddTxtTocRuleParams = {
        name: this.formName.trim(),
        rule: this.formRule,
        example: this.formExample,
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

  async deleteRule(rule: TxtTocRule): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `??????? "${rule.name}" ??`,
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

  async toggleRuleEnabled(rule: TxtTocRule): Promise<void> {
    await this.ruleManager.setRuleEnabled(rule.id, !rule.enabled);
    this.loadRules();
  }

  editRule(rule: TxtTocRule): void {
    this.editingRule = rule;
    this.formName = rule.name;
    this.formRule = rule.rule;
    this.formExample = rule.example;
    this.showAddDialog = true;
  }

  testRegex(): void {
    if (!this.formRule.trim()) {
      this.testResult = '请先输入正则表达式';
      return;
    }
    if (!this.testText.trim()) {
      this.testResult = '请输入测试文本';
      return;
    }

    try {
      const regex = new RegExp(this.formRule, 'gm');
      const matches: string[] = [];
      let match: RegExpExecArray | null;
      
      while ((match = regex.exec(this.testText)) !== null) {
        matches.push(match[0]);
        if (matches.length >= 10) break; // ????10?????
      }

      if (matches.length > 0) {
        this.testResult = `匹配成功，共 ${matches.length} 个结果\n${matches.join('\n')}`;
      } else {
        this.testResult = '未匹配到任何内容';
      }
    } catch (error) {
      this.testResult = `正则错误: ${String(error)}`;
    }
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
   * ?????????
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

      logger.info(TAG, '打开文件选择器，选择TXT目录规则文件');
      const selectResult = await documentPicker.select(selectOptions);
      
      if (!selectResult || selectResult.length === 0) {
        logger.info(TAG, '?????????');
        return;
      }

      const fileUri = selectResult[0];
      logger.info(TAG, `???????: ${fileUri}`);
      
      // 读取文件内容
      const file = SafeFileUtils.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(file.fd);
      const fileSize = stat.size;
      
      if (fileSize > 50 * 1024 * 1024) {
        SafeFileUtils.closeSync(file);
        this.getUIContext().getPromptAction().showToast({ message: '?????????50MB' });
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
      logger.error(TAG, `???????: ${String(error)}`);
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
        // ???
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
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
            ForEach(this.rules, (rule: TxtTocRule) => {
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
          title: 'TXT目录规则',
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
      PageWindowCoordinator.applyPagePolicy('NovelTxtTocRulePage', this.getUIContext());
    })
    .onWillShow(() => {
      PageWindowCoordinator.reapplyPagePolicy('NovelTxtTocRulePage', this.getUIContext());
    })
    .onReady((context: NavDestinationContext) => {
      this.loadRules();
    })
    .onShown(() => {
      PageWindowCoordinator.reapplyPagePolicy('NovelTxtTocRulePage', this.getUIContext());
      logger.info(TAG, 'TXT????? onShown ??????????');
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
      Text('暂无TXT目录规则')
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
      ForEach(this.rules, (rule: TxtTocRule) => {
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
  buildRuleItem(rule: TxtTocRule) {
    Row() {
      // ????
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
        
        Text(rule.rule)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (rule.example) {
          Text(`示例: ${rule.example}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      
      // ??
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
  buildSwipeActions(rule: TxtTocRule) {
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
      
      // ???
      Column() {
        Text(this.editingRule ? '编辑规则' : '添加规则')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 20 })
        
        // 规则名称
        TextInput({ placeholder: '规则名称', text: this.formName })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formName = value;
          })
        
        // ?????
        TextArea({ placeholder: '????? (?: ^\\s*?[0-9]+?.*)', text: this.formRule })
          .width('100%')
          .height(80)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formRule = value;
          })
        
        // 示例文本
        TextInput({ placeholder: '???? (??)', text: this.formExample })
          .width('100%')
          .height(44)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formExample = value;
          })
        
        // 测试区域
        Text('测试正则表达式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 16 })
          .alignSelf(ItemAlign.Start)
        
        TextArea({ placeholder: '输入测试文本...', text: this.testText })
          .width('100%')
          .height(60)
          .margin({ top: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.testText = value;
          })
        
        Button('测试')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .borderRadius(16)
          .margin({ top: 8 })
          .onClick(() => this.testRegex())
        
        if (this.testResult) {
          Text(this.testResult)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.testResult.startsWith('匹配成功') ? '#52C41A' : '#FF4D4F')
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
