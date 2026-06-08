/**
 * 恢复选项对话框
 * 展示备份内容详情，支持选择性恢复
 * 
 * 文件路径: entry/src/main/ets/components/backup/RestoreOptionsDialog.ets
 */

import { BackupData, BackupMetadata } from '../../Models/BackupModels';
import { ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';

export interface RestoreOptions {
  restoreMangaLibrary: boolean;
  restoreNovelLibrary: boolean;
  restoreEBookLibrary: boolean;
  restoreSources: boolean;
  restoreReadProgress: boolean;
  restoreSettings: boolean;
  restoreHistory: boolean;
  restoreAnnotations: boolean;
  restoreWebViewConfig: boolean;
  restoreDownloadTasks: boolean;
  restoreFavorites: boolean;
  restoreOnlineData: boolean;
  restoreMediaFiles: boolean;
  restoreCloudConfig: boolean;
  
  // 冲突处理策略
  conflictStrategy: 'skip' | 'replace' | 'merge';
}

@ComponentV2
export struct RestoreOptionsDialog {
  @Param @Require backupData: BackupData;
  @Param @Require metadata: BackupMetadata;
  @Param @Require onConfirm: (options: RestoreOptions) => void;
  @Param @Require onCancel: () => void;
  @Param @Require currentTheme: ThemeType;
  
  @Local restoreOptions: RestoreOptions = {
    restoreMangaLibrary: true,
    restoreNovelLibrary: true,
    restoreEBookLibrary: true,
    restoreSources: true,
    restoreReadProgress: true,
    restoreSettings: true,
    restoreHistory: true,
    restoreAnnotations: true,
    restoreWebViewConfig: false,
    restoreDownloadTasks: false,
    restoreFavorites: true,
    restoreOnlineData: false,
    restoreMediaFiles: true,
    restoreCloudConfig: false,
    conflictStrategy: 'merge'
  };
  @Local currentTabIndex: number = 0;

  build() {
    Column() {
      Column() {
        // 标题
        Text('恢复备份')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .padding({ top: 20, bottom: 8 })
        
        // 备份信息
        Text(`备份时间: ${this.formatDate(this.metadata.timestamp)}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        
        Text(`应用版本: ${this.metadata.appVersion}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ bottom: 16 })
        
        // 标签页
        Tabs({ index: $$this.currentTabIndex }) {
          TabContent() {
            this.buildContentTab()
          }
          .tabBar('备份内容')
          
          TabContent() {
            this.buildOptionsTab()
          }
          .tabBar('恢复选项')
          
          TabContent() {
            this.buildConflictTab()
          }
          .tabBar('冲突处理')
        }
        .height('60%')
        .barMode(BarMode.Scrollable)
        .barBackgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
        
        // 底部按钮
        Row() {
          Button('取消')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onCancel();
            })
          
          Blank().width(16)
          
          Button('开始恢复')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onConfirm(this.restoreOptions);
            })
        }
        .width('100%')
        .padding({ top: 16, bottom: 20 })
      }
      .width('90%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
      .borderRadius(16)
      .padding({ left: 20, right: 20 })
      .scale({ x: 1, y: 1 })
      .opacity(1)
      .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }).animation({ duration: 300, curve: Curve.EaseOut })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  @Builder
  buildContentTab() {
    Scroll() {
      Column() {
        Text('备份文件包含以下内容：')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ bottom: 12 })
        
        this.buildContentItem('📚 漫画库', this.backupData.manga?.library?.length || 0, '部漫画')
        this.buildContentItem('📖 小说库', this.backupData.novel?.library?.length || 0, '本小说')
        this.buildContentItem('📕 电子书库', this.backupData.ebook?.library?.length || 0, '本电子书')
        this.buildContentItem('🔌 漫画源', this.backupData.sources?.manga?.length || 0, '个源')
        this.buildContentItem('🔌 小说源', this.backupData.sources?.novel?.length || 0, '个源')
        this.buildContentItem('📊 阅读进度', 
          (this.backupData.manga?.readProgress?.length || 0) +
          (this.backupData.novel?.readProgress?.length || 0) +
          (this.backupData.tracking?.records?.length || 0),
          '条记录')
        this.buildContentItem('⚙️ 应用设置', this.backupData.settings ? 1 : 0, '组配置')
        this.buildContentItem('🕒 浏览历史', this.backupData.history?.browse?.length || 0, '条记录')
        this.buildContentItem('🔍 搜索历史', this.backupData.history?.search?.length || 0, '条记录')
        this.buildContentItem('📝 统一标注', this.backupData.annotations?.records?.length || 0, '条记录')
        
        if (this.backupData.webview?.configs?.length) {
          this.buildContentItem('🌐 WebView配置', this.backupData.webview.configs.length, '个配置')
        }
        
        if (this.backupData.downloads?.tasks?.length) {
          this.buildContentItem('⬇️ 下载任务', this.backupData.downloads.tasks.length, '个任务')
        }
        
        if (this.backupData.favorites?.favorites?.length) {
          this.buildContentItem('⭐ 收藏标签', this.backupData.favorites.favorites.length, '个标签')
        }
        
        if (this.backupData.onlineData?.comics?.length) {
          this.buildContentItem('☁️ 在线数据', this.backupData.onlineData.comics.length, '部漫画')
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  buildOptionsTab() {
    Scroll() {
      Column() {
        Text('选择要恢复的内容：')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ bottom: 12 })
        
        if (this.backupData.manga?.library?.length) {
          this.buildRestoreOption('漫画库', this.restoreOptions.restoreMangaLibrary, (value: boolean) => { this.restoreOptions.restoreMangaLibrary = value; })
        }
        
        if (this.backupData.novel?.library?.length) {
          this.buildRestoreOption('小说库', this.restoreOptions.restoreNovelLibrary, (value: boolean) => { this.restoreOptions.restoreNovelLibrary = value; })
        }
        
        if (this.backupData.ebook?.library?.length) {
          this.buildRestoreOption('电子书库', this.restoreOptions.restoreEBookLibrary, (value: boolean) => { this.restoreOptions.restoreEBookLibrary = value; })
        }
        
        if ((this.backupData.sources?.manga?.length || 0) + (this.backupData.sources?.novel?.length || 0) > 0) {
          this.buildRestoreOption('书源配置', this.restoreOptions.restoreSources, (value: boolean) => { this.restoreOptions.restoreSources = value; })
        }
        
        if ((this.backupData.manga?.readProgress?.length || 0) +
          (this.backupData.novel?.readProgress?.length || 0) +
          (this.backupData.tracking?.records?.length || 0) > 0) {
          this.buildRestoreOption('阅读进度', this.restoreOptions.restoreReadProgress, (value: boolean) => { this.restoreOptions.restoreReadProgress = value; })
        }
        
        if (this.backupData.settings) {
          this.buildRestoreOption('应用设置', this.restoreOptions.restoreSettings, (value: boolean) => { this.restoreOptions.restoreSettings = value; })
        }
        
        if ((this.backupData.history?.browse?.length || 0) + (this.backupData.history?.search?.length || 0) > 0) {
          this.buildRestoreOption('浏览历史', this.restoreOptions.restoreHistory, (value: boolean) => { this.restoreOptions.restoreHistory = value; })
        }

        if ((this.backupData.annotations?.records?.length || 0) > 0) {
          this.buildRestoreOption('统一标注（书签/划线/想法）', this.restoreOptions.restoreAnnotations, (value: boolean) => { this.restoreOptions.restoreAnnotations = value; })
        }
        
        if (this.backupData.webview?.configs?.length) {
          this.buildRestoreOption('WebView配置', this.restoreOptions.restoreWebViewConfig, (value: boolean) => { this.restoreOptions.restoreWebViewConfig = value; })
        }
        
        if (this.backupData.downloads?.tasks?.length) {
          this.buildRestoreOption('下载任务', this.restoreOptions.restoreDownloadTasks, (value: boolean) => { this.restoreOptions.restoreDownloadTasks = value; })
        }
        
        if (this.backupData.favorites?.favorites?.length) {
          this.buildRestoreOption('收藏标签', this.restoreOptions.restoreFavorites, (value: boolean) => { this.restoreOptions.restoreFavorites = value; })
        }
        
        if (this.backupData.onlineData?.comics?.length) {
          this.buildRestoreOption('在线数据', this.restoreOptions.restoreOnlineData, (value: boolean) => { this.restoreOptions.restoreOnlineData = value; })
        }

        if (this.backupData.cloudConfig) {
          this.buildRestoreOption('云存储配置（包含账号/密码/API Key）', this.restoreOptions.restoreCloudConfig, (value: boolean) => { this.restoreOptions.restoreCloudConfig = value; })
        }
        
        this.buildRestoreOption('媒体文件（封面、图片等）', this.restoreOptions.restoreMediaFiles, (value: boolean) => { this.restoreOptions.restoreMediaFiles = value; })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  buildConflictTab() {
    Scroll() {
      Column() {
        Text('当备份数据与现有数据冲突时：')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ bottom: 16 })
        
        this.buildConflictOption(
          '跳过',
          '保留现有数据，不导入冲突项',
          'skip'
        )
        
        this.buildConflictOption(
          '替换',
          '用备份数据替换现有数据',
          'replace'
        )
        
        this.buildConflictOption(
          '合并（推荐）',
          '智能合并，保留两者的数据',
          'merge'
        )
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .margin({ top: 16, bottom: 16 })
        
        Text('说明：')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ bottom: 8 })
        
        Text('• 跳过：适合只想补充缺失数据的情况')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ bottom: 4 })
        
        Text('• 替换：适合想完全恢复到备份状态的情况')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ bottom: 4 })
        
        Text('• 合并：适合大多数情况，会保留阅读进度等重要数据')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  buildContentItem(label: string, count: number, unit: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .layoutWeight(1)
      
      Text(`${count} ${unit}`)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  buildRestoreOption(label: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .layoutWeight(1)
      
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  buildConflictOption(title: string, description: string, strategy: 'skip' | 'replace' | 'merge') {
    Row() {
      Radio({ value: strategy, group: 'conflictStrategy' })
        .checked(this.restoreOptions.conflictStrategy === strategy)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.restoreOptions.conflictStrategy = strategy;
          }
        })
      
      Column() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        
        Text(description)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
}
