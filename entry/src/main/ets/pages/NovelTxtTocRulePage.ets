/**
 * TXT目录规则管理页面
 * 管理本地TXT文件的章节识别规则
 * 
 * 文件路径: entry/src/main/ets/pages/NovelTxtTocRulePage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { getNovelTxtTocRuleManager, TxtTocRule, AddTxtTocRuleParams } from '../Framework/Novel/NovelTxtTocRuleManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'NovelTxtTocRulePage';
const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct NovelTxtTocRulePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelTxtTocRulePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
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
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
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
    this.formRule = '';
    this.formExample = '';
    this.editingRule = null;
    this.testText = '';
    this.testResult = '';
  }

  async saveRule(): Promise<void> {
    if (!this.formName.trim() || !this.formRule.trim()) {
      promptAction.showToast({ message: '请填写规则名称和正则表达式' });
      return;
    }

    // 验证正则表达式
    try {
      new RegExp(this.formRule);
    } catch (error) {
      promptAction.showToast({ message: `正则表达式无效: ${String(error)}` });
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
        promptAction.showToast({ message: '规则已更新' });
      } else {
        await this.ruleManager.addRule(params);
        promptAction.showToast({ message: '规则已添加' });
      }

      this.showAddDialog = false;
      this.resetForm();
      this.loadRules();
    } catch (error) {
      promptAction.showToast({ message: `保存失败: ${String(error)}` });
    }
  }

  async deleteRule(rule: TxtTocRule): Promise<void> {
    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除规则"${rule.name}"吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await this.ruleManager.deleteRule(rule.id);
        promptAction.showToast({ message: '已删除' });
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
        if (matches.length >= 10) break; // 最多显示10个匹配
      }

      if (matches.length > 0) {
        this.testResult = `✓ 匹配到 ${matches.length} 个结果:\n${matches.join('\n')}`;
      } else {
        this.testResult = '✗ 没有匹配到任何内容';
      }
    } catch (error) {
      this.testResult = `✗ 正则表达式错误: ${String(error)}`;
    }
  }

  /**
   * 显示导入选项菜单
   */
  showImportOptions(): void {
    promptAction.showActionMenu({
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
          promptAction.showToast({ 
            message: `导入完成: ${result.success}/${result.total} 成功` 
          });
          this.loadRules();
        }
      }
    } catch (error) {
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  /**
   * 从本地文件导入规则
   */
  async importFromFile(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文' });
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
        logger.info(TAG, '用户取消了文件选择');
        return;
      }

      const fileUri = selectResult[0];
      logger.info(TAG, `用户选择了文件: ${fileUri}`);
      
      // 读取文件内容
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const fileSize = stat.size;
      
      if (fileSize > 50 * 1024 * 1024) {
        fs.closeSync(file);
        promptAction.showToast({ message: '文件过大，最大支持50MB' });
        return;
      }
      
      const buffer = new ArrayBuffer(fileSize);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      
      const uint8Array = new Uint8Array(buffer);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const jsonContent = decoder.decode(uint8Array);
      
      logger.info(TAG, `读取到文件内容，长度: ${jsonContent.length}`);
      
      // 导入规则
      const result = await this.ruleManager.importFromJSON(jsonContent);
      
      if (result.success > 0) {
        promptAction.showToast({ 
          message: `导入完成: ${result.success}/${result.total} 成功` 
        });
        this.loadRules();
      } else {
        promptAction.showToast({ 
          message: `导入失败: ${result.errors.join(', ')}` 
        });
      }
    } catch (error) {
      logger.error(TAG, `从文件导入失败: ${String(error)}`);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  async exportToClipboard(): Promise<void> {
    try {
      const json = this.ruleManager.exportToJSON();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制到剪贴板' });
    } catch (error) {
      promptAction.showToast({ message: `导出失败: ${String(error)}` });
    }
  }

  async resetToDefault(): Promise<void> {
    promptAction.showDialog({
      title: '确认重置',
      message: '确定要重置为默认规则吗？这将删除所有自定义规则。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '重置', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await this.ruleManager.resetToDefault();
        promptAction.showToast({ message: '已重置为默认规则' });
        this.loadRules();
      }
    });
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          // 规则列表
          if (this.isLoading) {
            this.buildLoading()
          } else if (this.rules.length === 0) {
            this.buildEmpty()
          } else {
            this.buildRuleList()
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })

        // 添加/编辑对话框
        if (this.showAddDialog) {
          this.buildAddDialog()
        }
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
          mainTitle: 'TXT目录规则'
        },
        menu: {
          value: [{
            content: {
              label: '添加',
              icon: $r('app.media.ic_add'),
              isEnabled: true,
              action: () => { 
                this.resetForm();
                this.showAddDialog = true;
              }
            }
          }, {
            content: {
              label: '导入',
              icon: $r('app.media.ic_download'),
              isEnabled: true,
              action: () => { this.showImportOptions(); }
            }
          }, {
            content: {
              label: '导出',
              icon: $r('app.media.ic_download'),
              isEnabled: true,
              action: () => { this.exportToClipboard(); }
            }
          }, {
            content: {
              label: '重置',
              icon: $r('app.media.ic_refresh'),
              isEnabled: true,
              action: () => { this.resetToDefault(); }
            }
          }]
        }
      }
    })
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
      Text('暂无TXT目录规则')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Button('添加规则')
        .fontSize(14)
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
    .padding({ top: 8 })
  }

  @Builder
  buildRuleItem(rule: TxtTocRule) {
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(rule.rule)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (rule.example) {
          Text(`示例: ${rule.example}`)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ left: 12, right: 12, bottom: 8 })
    .borderRadius(8)
    .onClick(() => {
      this.editRule(rule);
    })
  }

  @Builder
  buildSwipeActions(rule: TxtTocRule) {
    Row() {
      Button('删除')
        .fontSize(14)
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
      
      // 对话框
      Column() {
        Text(this.editingRule ? '编辑规则' : '添加规则')
          .fontSize(18)
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
        
        // 正则表达式
        TextArea({ placeholder: '正则表达式 (如: ^\\s*第[0-9]+章.*)', text: this.formRule })
          .width('100%')
          .height(80)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formRule = value;
          })
        
        // 示例文本
        TextInput({ placeholder: '示例文本 (可选)', text: this.formExample })
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .borderRadius(16)
          .margin({ top: 8 })
          .onClick(() => this.testRegex())
        
        if (this.testResult) {
          Text(this.testResult)
            .fontSize(12)
            .fontColor(this.testResult.startsWith('✓') ? '#52C41A' : '#FF4D4F')
            .margin({ top: 8 })
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        // 按钮
        Row() {
          Button('取消')
            .fontSize(14)
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .borderRadius(16)
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
