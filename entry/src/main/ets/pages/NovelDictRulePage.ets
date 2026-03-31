/**
 * 瀛楀吀瑙勫垯绠＄悊椤甸潰
 * 绠＄悊鍦ㄧ嚎璇嶅吀鏌ヨ瑙勫垯
 * 
 * 鏂囦欢璺緞: entry/src/main/ets/pages/NovelDictRulePage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { getNovelDictRuleManager, DictRule, AddDictRuleParams } from '../Framework/Novel/NovelDictRuleManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
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
  
  // 琛ㄥ崟鏁版嵁
  @State formName: string = '';
  @State formUrlRule: string = '';
  @State formShowRule: string = '';
  
  // 娴嬭瘯鐩稿叧
  @State testWord: string = '';
  @State testResult: string = '';
  @State isTesting: boolean = false;
  
  private ruleManager = getNovelDictRuleManager();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `涓婚鍒囨崲: ${theme}`);
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
      // 纭繚绠＄悊鍣ㄥ凡鍒濆鍖?
      await this.ruleManager.initialize();
      this.rules = this.ruleManager.getAllRules();
    } catch (error) {
      logger.error(TAG, `鍔犺浇瑙勫垯澶辫触: ${String(error)}`);
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
      promptAction.showToast({ message: '请填写规则名称和 URL 规则' });
      return;
    }

    // 楠岃瘉URL瑙勫垯鍖呭惈鍗犱綅绗?
    if (!this.formUrlRule.includes('{{key}}')) {
      promptAction.showToast({ message: 'URL 规则必须包含 {{key}} 占位符' });
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
        promptAction.showToast({ message: '规则已更新' });
      } else {
        await this.ruleManager.addRule(params);
        promptAction.showToast({ message: '规则已添加' });
      }

      this.showAddDialog = false;
      this.resetForm();
      this.loadRules();
    } catch (error) {
      promptAction.showToast({ message: `淇濆瓨澶辫触: ${String(error)}` });
    }
  }

  async deleteRule(rule: DictRule): Promise<void> {
    promptAction.showDialog({
      title: '纭鍒犻櫎',
      message: `确定要删除规则 "${rule.name}" 吗？`,
      buttons: [
        { text: '鍙栨秷', color: '#666666' },
        { text: '鍒犻櫎', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await this.ruleManager.deleteRule(rule.id);
        promptAction.showToast({ message: '已删除' });
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
      // 鏋勫缓娴嬭瘯URL
      const testUrl = this.formUrlRule.replace(/\{\{key\}\}/g, encodeURIComponent(this.testWord));
      this.testResult = `生成的 URL:\n${testUrl}`;
    } catch (error) {
      this.testResult = `测试失败: ${String(error)}`;
    }

    this.isTesting = false;
  }

  /**
   * 鏄剧ず瀵煎叆閫夐」鑿滃崟
   */
  showImportOptions(): void {
    promptAction.showActionMenu({
      title: '选择导入方式',
      buttons: [
        { text: '浠庡壀璐存澘瀵煎叆', color: $r('sys.color.ohos_id_color_text_primary') },
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
            message: `瀵煎叆瀹屾垚: ${result.success}/${result.total} 鎴愬姛` 
          });
          this.loadRules();
        }
      }
    } catch (error) {
      promptAction.showToast({ message: `瀵煎叆澶辫触: ${String(error)}` });
    }
  }

  /**
   * 浠庢湰鍦版枃浠跺鍏ヨ鍒?
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

      logger.info(TAG, '鎵撳紑鏂囦欢閫夋嫨鍣紝閫夋嫨瀛楀吀瑙勫垯鏂囦欢');
      const selectResult = await documentPicker.select(selectOptions);
      
      if (!selectResult || selectResult.length === 0) {
        logger.info(TAG, '鐢ㄦ埛鍙栨秷浜嗘枃浠堕€夋嫨');
        return;
      }

      const fileUri = selectResult[0];
      logger.info(TAG, `鐢ㄦ埛閫夋嫨浜嗘枃浠? ${fileUri}`);
      
      // 璇诲彇鏂囦欢鍐呭
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const fileSize = stat.size;
      
      if (fileSize > 50 * 1024 * 1024) {
        fs.closeSync(file);
        promptAction.showToast({ message: '鏂囦欢杩囧ぇ锛屾渶澶ф敮鎸?0MB' });
        return;
      }
      
      const buffer = new ArrayBuffer(fileSize);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      
      const uint8Array = new Uint8Array(buffer);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const jsonContent = decoder.decode(uint8Array);
      
      logger.info(TAG, `璇诲彇鍒版枃浠跺唴瀹癸紝闀垮害: ${jsonContent.length}`);
      
      // 瀵煎叆瑙勫垯
      const result = await this.ruleManager.importFromJSON(jsonContent);
      
      if (result.success > 0) {
        promptAction.showToast({ 
          message: `瀵煎叆瀹屾垚: ${result.success}/${result.total} 鎴愬姛` 
        });
        this.loadRules();
      } else {
        promptAction.showToast({ 
          message: `瀵煎叆澶辫触: ${result.errors.join(', ')}` 
        });
      }
    } catch (error) {
      logger.error(TAG, `浠庢枃浠跺鍏ュけ璐? ${String(error)}`);
      promptAction.showToast({ message: `瀵煎叆澶辫触: ${String(error)}` });
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
      promptAction.showToast({ message: `瀵煎嚭澶辫触: ${String(error)}` });
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

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'add',
        label: '娣诲姞',
        symbol: $r('sys.symbol.plus'),
        onClick: () => {
          this.resetForm();
          this.showAddDialog = true;
        }
      },
      {
        id: 'import',
        label: '瀵煎叆',
        symbol: $r('sys.symbol.download'),
        onClick: () => {
          this.showImportOptions();
        }
      },
      {
        id: 'export',
        label: '瀵煎嚭',
        symbol: $r('sys.symbol.upload'),
        onClick: () => {
          void this.exportToClipboard();
        }
      },
      {
        id: 'reset',
        label: '閲嶇疆',
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
        // 鑳屾櫙灞?
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
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
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .padding({ top: 8 })
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
      Text('鏆傛棤瀛楀吀瑙勫垯')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Button('娣诲姞瑙勫垯')
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
      // 鐘舵€佹寚绀?
      Column()
        .width(4)
        .height(40)
        .borderRadius(2)
        .backgroundColor(rule.enabled ? '#52C41A' : '#D9D9D9')
      
      // 淇℃伅
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
      
      // 寮€鍏?
      Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.toggleRuleEnabled(rule);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ bottom: 8 })
    .borderRadius(8)
    .onClick(() => {
      this.editRule(rule);
    })
  }

  @Builder
  buildSwipeActions(rule: DictRule) {
    Row() {
      Button('鍒犻櫎')
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
      // 閬僵
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.showAddDialog = false;
          this.resetForm();
        })
        .transition(TransitionEffect.opacity(0).animation({ duration: 250, curve: Curve.EaseOut }))
      
      // 瀵硅瘽妗?
      Column() {
        Text(this.editingRule ? '缂栬緫瑙勫垯' : '娣诲姞瑙勫垯')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 20 })
        
        // 瑙勫垯鍚嶇О
        TextInput({ placeholder: '瑙勫垯鍚嶇О (濡? 鐧惧害鐧剧)', text: this.formName })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formName = value;
          })
        
        // URL瑙勫垯
        TextArea({ placeholder: 'URL瑙勫垯 (浣跨敤 {{key}} 浣滀负鍏抽敭璇嶅崰浣嶇)\n濡? https://baike.baidu.com/item/{{key}}', text: this.formUrlRule })
          .width('100%')
          .height(80)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formUrlRule = value;
          })
        
        // 鏄剧ず瑙勫垯锛堝彲閫夛級
        TextInput({ placeholder: '鏄剧ず瑙勫垯 (鍙€夛紝鐢ㄤ簬鎻愬彇缁撴灉鐨勬鍒?', text: this.formShowRule })
          .width('100%')
          .height(44)
          .margin({ top: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.formShowRule = value;
          })
        
        // 娴嬭瘯鍖哄煙
        Text('娴嬭瘯瑙勫垯')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 16 })
          .alignSelf(ItemAlign.Start)
        
        Row() {
          TextInput({ placeholder: '杈撳叆娴嬭瘯璇嶈...', text: this.testWord })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(8)
            .onChange((value: string) => {
              this.testWord = value;
            })
          
          Button('娴嬭瘯')
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
        
        // 鎸夐挳
        Row() {
          Button('鍙栨秷')
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
          
          Button('淇濆瓨')
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .borderRadius(16)
      .padding({ left: 20, right: 20 })
      .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 }).combine(TransitionEffect.opacity(0)).animation({ duration: 250, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
