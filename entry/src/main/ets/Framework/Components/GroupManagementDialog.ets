/**
 * 分组管理对话框
 * 提供全面的分组管理功能：统计、重命名、合并、拆分等
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/GroupManagementDialog.ets
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { FontAwareHelper, FontAwareState } from './FontAware';
import { promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { AppColors } from '../Theme/AppColors';

const TAG = 'GroupManagementDialog';

/**
 * 分组信息
 */
export interface GroupInfo {
  name: string;
  count: number;
  enabledCount: number;
  disabledCount: number;
  pinnedCount: number;
}

/**
 * 分组操作类型
 */
export enum GroupOperationType {
  RENAME = 'rename',
  MERGE = 'merge',
  SPLIT = 'split',
  DELETE = 'delete'
}

/**
 * 分组操作回调
 */
export interface GroupOperationCallback {
  onRename?: (oldName: string, newName: string) => Promise<void>;
  onMerge?: (sourceGroups: string[], targetGroup: string) => Promise<void>;
  onSplit?: (groupName: string, condition: SplitCondition) => Promise<void>;
  onDelete?: (groupName: string) => Promise<void>;
  onRefresh?: () => GroupInfo[];  // 刷新分组数据
}

/**
 * 拆分条件
 */
export interface SplitCondition {
  type: 'enabled' | 'pinned' | 'keyword';
  keyword?: string;
}

@CustomDialog
export struct GroupManagementDialog {
  controller?: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop groups: GroupInfo[] = [];
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  callbacks?: GroupOperationCallback;
  
  @State selectedGroups: Set<string> = new Set();
  @State currentView: 'list' | 'rename' | 'merge' | 'split' = 'list';
  @State selectedGroupForOperation: string = '';
  @State newGroupName: string = '';
  @State mergeTargetName: string = '';
  @State splitConditionType: 'enabled' | 'pinned' | 'keyword' = 'enabled';
  @State splitKeyword: string = '';
  @State searchKeyword: string = '';

  /**
   * 获取筛选后的分组列表
   */
  getFilteredGroups(): GroupInfo[] {
    if (!this.searchKeyword) {
      return this.groups;
    }
    return this.groups.filter(g => g.name.includes(this.searchKeyword));
  }

  /**
   * 切换分组选中状态
   */
  toggleGroupSelection(groupName: string): void {
    const newSet = new Set(this.selectedGroups);
    if (newSet.has(groupName)) {
      newSet.delete(groupName);
    } else {
      newSet.add(groupName);
    }
    this.selectedGroups = newSet;
  }

  /**
   * 重命名分组
   */
  async renameGroup(): Promise<void> {
    if (!this.selectedGroupForOperation || !this.newGroupName.trim()) {
      promptAction.showToast({ message: '请输入新的分组名称' });
      return;
    }

    if (this.callbacks?.onRename) {
      try {
        await this.callbacks.onRename(this.selectedGroupForOperation, this.newGroupName.trim());
        promptAction.showToast({ message: '重命名成功' });
        this.currentView = 'list';
        this.selectedGroupForOperation = '';
        this.newGroupName = '';
        // 刷新分组数据
        this.refreshGroupData();
      } catch (error) {
        promptAction.showToast({ message: `重命名失败: ${String(error)}` });
      }
    }
  }

  /**
   * 合并分组
   */
  async mergeGroups(): Promise<void> {
    if (this.selectedGroups.size < 2) {
      promptAction.showToast({ message: '请至少选择2个分组进行合并' });
      return;
    }

    if (!this.mergeTargetName.trim()) {
      promptAction.showToast({ message: '请输入合并后的分组名称' });
      return;
    }

    if (this.callbacks?.onMerge) {
      try {
        await this.callbacks.onMerge(Array.from(this.selectedGroups), this.mergeTargetName.trim());
        promptAction.showToast({ message: '合并成功' });
        this.currentView = 'list';
        this.selectedGroups = new Set();
        this.mergeTargetName = '';
        // 刷新分组数据
        this.refreshGroupData();
      } catch (error) {
        promptAction.showToast({ message: `合并失败: ${String(error)}` });
      }
    }
  }

  /**
   * 拆分分组
   */
  async splitGroup(): Promise<void> {
    if (!this.selectedGroupForOperation) {
      promptAction.showToast({ message: '请选择要拆分的分组' });
      return;
    }

    if (this.splitConditionType === 'keyword' && !this.splitKeyword.trim()) {
      promptAction.showToast({ message: '请输入关键词' });
      return;
    }

    if (this.callbacks?.onSplit) {
      try {
        const condition: SplitCondition = {
          type: this.splitConditionType,
          keyword: this.splitConditionType === 'keyword' ? this.splitKeyword.trim() : undefined
        };
        await this.callbacks.onSplit(this.selectedGroupForOperation, condition);
        promptAction.showToast({ message: '拆分成功' });
        this.currentView = 'list';
        this.selectedGroupForOperation = '';
        this.splitKeyword = '';
        // 刷新分组数据
        this.refreshGroupData();
      } catch (error) {
        promptAction.showToast({ message: `拆分失败: ${String(error)}` });
      }
    }
  }

  /**
   * 删除分组
   */
  async deleteGroup(groupName: string): Promise<void> {
    if (this.callbacks?.onDelete) {
      try {
        await this.callbacks.onDelete(groupName);
        promptAction.showToast({ message: '删除成功' });
        // 刷新分组数据
        this.refreshGroupData();
      } catch (error) {
        promptAction.showToast({ message: `删除失败: ${String(error)}` });
      }
    }
  }

  /**
   * 刷新分组数据
   */
  refreshGroupData(): void {
    if (this.callbacks?.onRefresh) {
      this.groups = this.callbacks.onRefresh();
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text(this.currentView === 'list' ? '分组管理' : 
             this.currentView === 'rename' ? '重命名分组' :
             this.currentView === 'merge' ? '合并分组' : '拆分分组')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        if (this.currentView !== 'list') {
          Button('返回')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor('transparent')
            .onClick(() => {
              this.currentView = 'list';
              this.selectedGroupForOperation = '';
              this.newGroupName = '';
              this.mergeTargetName = '';
              this.splitKeyword = '';
            })
        }
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 主内容区域
      if (this.currentView === 'list') {
        this.buildGroupList();
      } else if (this.currentView === 'rename') {
        this.buildRenameView();
      } else if (this.currentView === 'merge') {
        this.buildMergeView();
      } else if (this.currentView === 'split') {
        this.buildSplitView();
      }

      // 底部操作按钮
      if (this.currentView === 'list') {
        this.buildBottomActions();
      }
    }
    .width('100%')
    .constraintSize({ maxHeight: '80%' })
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
  }

  @Builder
  buildGroupList() {
    Column() {
      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索分组...', text: this.searchKeyword })
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 统计信息
      Row() {
        Text(`共 ${this.groups.length} 个分组`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text(`已选 ${this.selectedGroups.size} 个`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 16 })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 分组列表
      List({ space: 8 }) {
        ForEach(this.getFilteredGroups(), (group: GroupInfo) => {
          ListItem() {
            this.buildGroupItem(group);
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  buildGroupItem(group: GroupInfo) {
    Row() {
      // 选择框
      Checkbox({ name: group.name })
        .select(this.selectedGroups.has(group.name))
        .onChange((isChecked: boolean) => {
          this.toggleGroupSelection(group.name);
        })
        .margin({ right: 12 })

      // 分组信息
      Column({ space: 4 }) {
        Row() {
          Text(group.name)
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)
          
          Text(`${group.count}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')

        Row({ space: 12 }) {
          Text(`启用: ${group.enabledCount}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.success)
          
          Text(`禁用: ${group.disabledCount}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.error)
          
          Text(`置顶: ${group.pinnedCount}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.info)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 操作按钮
      Row({ space: 6 }) {
        // 改名按钮
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(32)
        .height(32)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.selectedGroupForOperation = group.name;
          this.newGroupName = group.name;
          this.currentView = 'rename';
        })

        // 拆分按钮
        Button() {
          SymbolGlyph($r('sys.symbol.line_arrowtriangle_2_inward'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(32)
        .height(32)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.selectedGroupForOperation = group.name;
          this.currentView = 'split';
        })

        // 删除按钮
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([Color.White])
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.error)
        .borderRadius(6)
        .onClick(() => {
          promptAction.showDialog({
            title: '确认删除',
            message: `确定要删除分组"${group.name}"吗？这将移除所有书源的该分组标记。`,
            buttons: [
              { text: '取消', color: AppColors.textSecondary },
              { text: '删除', color: AppColors.error }
            ]
          }).then((result) => {
            if (result.index === 1) {
              this.deleteGroup(group.name);
            }
          });
        })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius(8)
  }

  @Builder
  buildRenameView() {
    Column({ space: 16 }) {
      Text(`原分组名: ${this.selectedGroupForOperation}`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      TextInput({ placeholder: '请输入新的分组名称', text: this.newGroupName })
        .fontSize(14)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.newGroupName = value;
        })

      Button('确认重命名')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(AppColors.onPrimary)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.renameGroup();
        })
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  buildMergeView() {
    Column({ space: 16 }) {
      Text(`已选择 ${this.selectedGroups.size} 个分组进行合并`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      // 显示选中的分组
      List({ space: 4 }) {
        ForEach(Array.from(this.selectedGroups), (groupName: string) => {
          ListItem() {
            Text(`• ${groupName}`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        })
      }
      .width('100%')
      .height(120)
      .scrollBar(BarState.Auto)

      TextInput({ placeholder: '请输入合并后的分组名称', text: this.mergeTargetName })
        .fontSize(14)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.mergeTargetName = value;
        })

      Text('提示: 所有选中分组的书源将被合并到新分组中')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Button('确认合并')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(AppColors.onPrimary)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.mergeGroups();
        })
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  buildSplitView() {
    Column({ space: 16 }) {
      Text(`拆分分组: ${this.selectedGroupForOperation}`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      // 拆分条件选择
      Column({ space: 8 }) {
        Text('拆分条件:')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Radio({ value: 'enabled', group: 'splitCondition' })
          .checked(this.splitConditionType === 'enabled')
          .onChange((isChecked: boolean) => {
            if (isChecked) this.splitConditionType = 'enabled';
          })
        Text('按启用状态拆分 (启用/禁用)')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ left: 8 })

        Radio({ value: 'pinned', group: 'splitCondition' })
          .checked(this.splitConditionType === 'pinned')
          .onChange((isChecked: boolean) => {
            if (isChecked) this.splitConditionType = 'pinned';
          })
        Text('按置顶状态拆分 (置顶/未置顶)')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ left: 8 })

        Radio({ value: 'keyword', group: 'splitCondition' })
          .checked(this.splitConditionType === 'keyword')
          .onChange((isChecked: boolean) => {
            if (isChecked) this.splitConditionType = 'keyword';
          })
        Text('按书源名称关键词拆分')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ left: 8 })

        if (this.splitConditionType === 'keyword') {
          TextInput({ placeholder: '请输入关键词', text: this.splitKeyword })
            .fontSize(14)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
            .margin({ top: 8 })
            .onChange((value: string) => {
              this.splitKeyword = value;
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text('提示: 拆分后将创建新的子分组')
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Button('确认拆分')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(AppColors.onPrimary)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.splitGroup();
        })
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  buildBottomActions() {
    Column({ space: 12 }) {
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
        .margin({ top: 8, bottom: 8 })

      Button('合并分组')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(AppColors.onPrimary)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .fontFamily(this.appFontFamily)
        .enabled(this.selectedGroups.size >= 2)
        .onClick(() => {
          this.currentView = 'merge';
        })
    }
    .width('100%')
  }
}
