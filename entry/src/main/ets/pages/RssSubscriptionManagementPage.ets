/**
 * RSS subscription source management page.
 * Supports source CRUD, import, reorder and refresh actions.
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { RssFetchResult, RssSubscriptionSource } from '../Models/RssSubscriptionModels';
import { getRssSubscriptionInitializer } from '../Framework/Rss/RssSubscriptionInitializer';
import {
  getRssSubscriptionManager,
  RssImportConflictPolicy,
  RssImportResult,
  RssRulePreviewResult,
  RssSourceUpdatePayload,
  RssSubscriptionManager
} from '../Framework/Rss/RssSubscriptionManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'RssSubscriptionManagementPage';

interface BatchActionButton {
  text: string;
  color: Resource;
}

interface DialogResult {
  index: number;
}

interface GroupFilterOption {
  key: string;
  label: string;
  count: number;
}

interface RssSourceDebugRouteParam {
  sourceId: string;
}

type PageErrorValue = Object | string | number | boolean | null | undefined;

@Component
export struct RssSubscriptionManagementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private readonly componentId: string = `RssSubscriptionManagementPage_${Date.now()}`;

  @State sources: RssSubscriptionSource[] = [];
  @State filteredSources: RssSubscriptionSource[] = [];
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State isBatchOperating: boolean = false;
  @State progressText: string = '';
  @State showSearchBar: boolean = false;
  @State searchKeyword: string = '';
  @State selectedGroupFilterKey: string = 'all';

  @State showEditDialog: boolean = false;
  @State editingSourceId: string = '';
  @State editName: string = '';
  @State editUrl: string = '';
  @State editGroupName: string = '';
  @State editSourceComment: string = '';
  @State editAutoUpdate: boolean = true;
  @State editIntervalText: string = '180';
  @State editIconUrl: string = '';
  @State showAdvancedConfig: boolean = false;
  @State editHeader: string = '';
  @State editJsLib: string = '';
  @State editSortUrl: string = '';
  @State editRuleArticles: string = '';
  @State editRuleNextPage: string = '';
  @State editRuleTitle: string = '';
  @State editRuleLink: string = '';
  @State editRulePubDate: string = '';
  @State editRuleDescription: string = '';
  @State editRuleContent: string = '';
  @State editRuleImage: string = '';
  @State editSingleUrl: boolean = false;
  @State editArticleStyleText: string = '0';
  @State editEnableJs: boolean = true;
  @State editLoadWithBaseUrl: boolean = true;

  @State showImportDialog: boolean = false;
  @State importText: string = '';
  @State showImportTypeDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State importUrl: string = '';
  @State importConflictPolicy: RssImportConflictPolicy = 'overwrite';
  @State showImportErrorDialog: boolean = false;
  @State importErrorTitle: string = '';
  @State importErrorSummary: string = '';
  @State importErrorList: string[] = [];
  @State showDeleteConfirmDialog: boolean = false;
  @State pendingDeleteSource: RssSubscriptionSource | null = null;
  @State showRulePreviewDialog: boolean = false;
  @State isRulePreviewLoading: boolean = false;
  @State rulePreviewSourceName: string = '';
  @State rulePreviewText: string = '';
  @State showGroupInputDialog: boolean = false;
  @State groupInputDialogTitle: string = '';
  @State groupInputPlaceholder: string = '';
  @State groupInputText: string = '';
  @State groupInputAction: string = '';
  @State groupRenameOldName: string = '';

  private readonly manager: RssSubscriptionManager = getRssSubscriptionManager();
  private lifecycle = new PageLifecycleManager('RssSubscriptionManagementPage', { enableDebug: true });

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    this.initializeAndLoad();
  }

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  onPageShow(): void {
    if (!this.isLoading) {
      this.loadSources();
      this.triggerAutoDueRefresh();
    }
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    try {
      logger.info(TAG, '开始初始化订阅源管理页');
      const context = getContext(this) as common.UIAbilityContext;
      await getRssSubscriptionInitializer().initialize(context);
      await this.loadSources();
      this.triggerAutoDueRefresh();
      logger.info(TAG, '订阅源管理页初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化订阅源管理页失败: ${String(error)}`);
      promptAction.showToast({ message: `初始化失败: ${String(error)}` });
    }
    this.isLoading = false;
  }

  private triggerAutoDueRefresh(): void {
    this.manager.maybeRefreshDueSources('订阅源管理页进入').then((results: RssFetchResult[]) => {
      if (results.length > 0) {
        logger.info(TAG, `自动到期刷新完成并更新管理列表: 更新源=${results.length}`);
        this.loadSources();
      }
    }).catch((error: Object | string | number | boolean | null | undefined) => {
      logger.warn(TAG, `触发自动到期刷新失败: ${String(error)}`);
    });
  }

  private async loadSources(): Promise<void> {
    try {
      this.sources = await this.manager.getAllSources(false);
      this.ensureGroupFilterKeyValid();
      this.applyFilter();
      logger.info(TAG, `加载订阅源列表完成: ${this.sources.length} 个`);
    } catch (error) {
      logger.warn(TAG, `加载订阅源列表失败: ${String(error)}`);
      promptAction.showToast({ message: '加载订阅源失败' });
    }
  }

  private splitGroupNames(groupName: string | undefined): string[] {
    const rawText = groupName ? groupName.trim() : '';
    if (rawText.length === 0) {
      return [];
    }
    const pieces = rawText
      .split(',')
      .map((item: string): string => item.trim())
      .filter((item: string): boolean => item.length > 0);
    const uniqueGroups: string[] = [];
    for (let i = 0; i < pieces.length; i++) {
      const group = pieces[i];
      if (!uniqueGroups.includes(group)) {
        uniqueGroups.push(group);
      }
    }
    return uniqueGroups;
  }

  private isSourceUngrouped(source: RssSubscriptionSource): boolean {
    return this.splitGroupNames(source.groupName).length === 0;
  }

  private sourceContainsGroup(source: RssSubscriptionSource, groupName: string): boolean {
    const groups = this.splitGroupNames(source.groupName);
    for (let i = 0; i < groups.length; i++) {
      if (groups[i] === groupName) {
        return true;
      }
    }
    return false;
  }

  private sourceMatchesCurrentGroupFilter(source: RssSubscriptionSource): boolean {
    const filterKey = this.selectedGroupFilterKey;
    if (filterKey === 'all') {
      return true;
    }
    if (filterKey === 'enabled') {
      return source.enabled;
    }
    if (filterKey === 'disabled') {
      return !source.enabled;
    }
    if (filterKey === 'ungrouped') {
      return this.isSourceUngrouped(source);
    }
    if (filterKey.startsWith('group::')) {
      const groupName = filterKey.substring('group::'.length);
      if (groupName.length === 0) {
        return true;
      }
      return this.sourceContainsGroup(source, groupName);
    }
    return true;
  }

  private getGroupFilterOptions(): GroupFilterOption[] {
    let enabledCount = 0;
    let disabledCount = 0;
    let ungroupedCount = 0;
    const groupCountMap: Map<string, number> = new Map();

    for (let i = 0; i < this.sources.length; i++) {
      const source = this.sources[i];
      if (source.enabled) {
        enabledCount++;
      } else {
        disabledCount++;
      }
      const groups = this.splitGroupNames(source.groupName);
      if (groups.length === 0) {
        ungroupedCount++;
        continue;
      }
      for (let j = 0; j < groups.length; j++) {
        const group = groups[j];
        const currentCount = groupCountMap.get(group);
        groupCountMap.set(group, (currentCount !== undefined ? currentCount : 0) + 1);
      }
    }

    const options: GroupFilterOption[] = [
      { key: 'all', label: '全部', count: this.sources.length } as GroupFilterOption,
      { key: 'enabled', label: '已启用', count: enabledCount } as GroupFilterOption,
      { key: 'disabled', label: '已禁用', count: disabledCount } as GroupFilterOption,
      { key: 'ungrouped', label: '未分组', count: ungroupedCount } as GroupFilterOption
    ];

    const groupNames: string[] = Array.from(groupCountMap.keys());
    groupNames.sort((a: string, b: string): number => a.localeCompare(b));
    for (let i = 0; i < groupNames.length; i++) {
      const group = groupNames[i];
      const count = groupCountMap.get(group);
      options.push({
        key: `group::${group}`,
        label: group,
        count: count !== undefined ? count : 0
      } as GroupFilterOption);
    }
    return options;
  }

  private ensureGroupFilterKeyValid(): void {
    const options = this.getGroupFilterOptions();
    for (let i = 0; i < options.length; i++) {
      if (options[i].key === this.selectedGroupFilterKey) {
        return;
      }
    }
    this.selectedGroupFilterKey = 'all';
  }

  private getCurrentGroupFilterLabel(): string {
    const options = this.getGroupFilterOptions();
    for (let i = 0; i < options.length; i++) {
      if (options[i].key === this.selectedGroupFilterKey) {
        return options[i].label;
      }
    }
    return '全部';
  }

  private chooseGroupFilter(filterKey: string): void {
    if (this.selectedGroupFilterKey === filterKey) {
      return;
    }
    this.selectedGroupFilterKey = filterKey;
    logger.info(TAG, `切换订阅源分组筛选: ${this.getCurrentGroupFilterLabel()}`);
    this.applyFilter();
  }

  private resetAllFilters(): void {
    this.searchKeyword = '';
    this.selectedGroupFilterKey = 'all';
    this.applyFilter();
  }

  private normalizeGroupNames(groupName: string | undefined): string[] {
    return this.splitGroupNames(groupName);
  }

  private joinGroupNames(groupList: string[]): string {
    if (groupList.length === 0) {
      return '';
    }
    return groupList.join(',');
  }

  private appendGroupName(originalGroup: string | undefined, targetGroup: string): string {
    const normalizedTarget = targetGroup.trim();
    if (normalizedTarget.length === 0) {
      return this.joinGroupNames(this.normalizeGroupNames(originalGroup));
    }
    const groups = this.normalizeGroupNames(originalGroup);
    if (!groups.includes(normalizedTarget)) {
      groups.push(normalizedTarget);
    }
    return this.joinGroupNames(groups);
  }

  private removeGroupName(originalGroup: string | undefined, targetGroup: string): string {
    const normalizedTarget = targetGroup.trim();
    if (normalizedTarget.length === 0) {
      return this.joinGroupNames(this.normalizeGroupNames(originalGroup));
    }
    const groups = this.normalizeGroupNames(originalGroup).filter((item: string): boolean => item !== normalizedTarget);
    return this.joinGroupNames(groups);
  }

  private replaceGroupName(originalGroup: string | undefined, oldName: string, newName: string): string {
    const normalizedOld = oldName.trim();
    const normalizedNew = newName.trim();
    const groups = this.normalizeGroupNames(originalGroup);
    if (normalizedOld.length === 0 || normalizedNew.length === 0) {
      return this.joinGroupNames(groups);
    }
    const replaced: string[] = [];
    for (let i = 0; i < groups.length; i++) {
      const current = groups[i] === normalizedOld ? normalizedNew : groups[i];
      if (!replaced.includes(current)) {
        replaced.push(current);
      }
    }
    return this.joinGroupNames(replaced);
  }

  private getAllGroupNames(): string[] {
    const groups: string[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      const sourceGroups = this.normalizeGroupNames(this.sources[i].groupName);
      for (let j = 0; j < sourceGroups.length; j++) {
        const group = sourceGroups[j];
        if (!groups.includes(group)) {
          groups.push(group);
        }
      }
    }
    groups.sort((a: string, b: string): number => a.localeCompare(b));
    return groups;
  }

  private openGroupInputDialog(action: string, title: string, placeholder: string, defaultText: string = ''): void {
    this.groupInputAction = action;
    this.groupInputDialogTitle = title;
    this.groupInputPlaceholder = placeholder;
    this.groupInputText = defaultText;
    this.showGroupInputDialog = true;
  }

  private closeGroupInputDialog(): void {
    this.showGroupInputDialog = false;
    this.groupInputAction = '';
    this.groupInputDialogTitle = '';
    this.groupInputPlaceholder = '';
    this.groupInputText = '';
    this.groupRenameOldName = '';
  }

  private async applyGroupActionToFilteredSources(action: string, groupName: string): Promise<void> {
    const target = groupName.trim();
    const targetGroupList = this.normalizeGroupNames(target);
    if (target.length === 0 || targetGroupList.length === 0) {
      promptAction.showToast({ message: '分组名称不能为空' });
      return;
    }
    if (this.filteredSources.length === 0) {
      promptAction.showToast({ message: '当前筛选结果为空，无法执行分组操作' });
      return;
    }
    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始批量分组操作: action=${action}, target=${target}, 数量=${this.filteredSources.length}`);
      let changedCount = 0;
      for (let i = 0; i < this.filteredSources.length; i++) {
        const source = this.filteredSources[i];
        let nextGroupName = source.groupName || '';
        if (action === 'set') {
          nextGroupName = this.joinGroupNames(targetGroupList);
        } else if (action === 'append') {
          let currentGroupName = source.groupName || '';
          for (let j = 0; j < targetGroupList.length; j++) {
            currentGroupName = this.appendGroupName(currentGroupName, targetGroupList[j]);
          }
          nextGroupName = currentGroupName;
        } else if (action === 'remove') {
          let currentGroupName = source.groupName || '';
          for (let j = 0; j < targetGroupList.length; j++) {
            currentGroupName = this.removeGroupName(currentGroupName, targetGroupList[j]);
          }
          nextGroupName = currentGroupName;
        }
        if ((nextGroupName || '') === (source.groupName || '')) {
          continue;
        }
        await this.manager.updateSource(source.id, { groupName: nextGroupName });
        changedCount++;
      }
      await this.loadSources();
      promptAction.showToast({ message: `分组操作完成，已变更 ${changedCount} 个订阅源` });
      logger.info(TAG, `批量分组操作完成: action=${action}, target=${target}, 变更=${changedCount}`);
    } catch (error) {
      logger.error(TAG, `批量分组操作失败: action=${action}, ${String(error)}`);
      promptAction.showToast({ message: `分组操作失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private async renameGroupAcrossSources(oldName: string, newName: string): Promise<void> {
    const normalizedOld = oldName.trim();
    const normalizedNew = newName.trim();
    if (normalizedOld.length === 0 || normalizedNew.length === 0) {
      promptAction.showToast({ message: '分组名称不能为空' });
      return;
    }
    if (normalizedOld === normalizedNew) {
      promptAction.showToast({ message: '新旧分组名称相同，无需修改' });
      return;
    }
    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始重命名分组: ${normalizedOld} -> ${normalizedNew}`);
      let changedCount = 0;
      for (let i = 0; i < this.sources.length; i++) {
        const source = this.sources[i];
        if (!this.sourceContainsGroup(source, normalizedOld)) {
          continue;
        }
        const nextGroupName = this.replaceGroupName(source.groupName, normalizedOld, normalizedNew);
        if ((nextGroupName || '') === (source.groupName || '')) {
          continue;
        }
        await this.manager.updateSource(source.id, { groupName: nextGroupName });
        changedCount++;
      }
      await this.loadSources();
      promptAction.showToast({ message: `分组重命名完成，已变更 ${changedCount} 个订阅源` });
      logger.info(TAG, `重命名分组完成: ${normalizedOld} -> ${normalizedNew}, 变更=${changedCount}`);
    } catch (error) {
      logger.error(TAG, `重命名分组失败: ${normalizedOld} -> ${normalizedNew}, ${String(error)}`);
      promptAction.showToast({ message: `重命名失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private async removeGroupAcrossSources(groupName: string): Promise<void> {
    const normalizedName = groupName.trim();
    if (normalizedName.length === 0) {
      promptAction.showToast({ message: '分组名称不能为空' });
      return;
    }
    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始删除分组标签: ${normalizedName}`);
      let changedCount = 0;
      for (let i = 0; i < this.sources.length; i++) {
        const source = this.sources[i];
        if (!this.sourceContainsGroup(source, normalizedName)) {
          continue;
        }
        const nextGroupName = this.removeGroupName(source.groupName, normalizedName);
        if ((nextGroupName || '') === (source.groupName || '')) {
          continue;
        }
        await this.manager.updateSource(source.id, { groupName: nextGroupName });
        changedCount++;
      }
      await this.loadSources();
      promptAction.showToast({ message: `已从 ${changedCount} 个订阅源移除分组` });
      logger.info(TAG, `删除分组标签完成: group=${normalizedName}, 变更=${changedCount}`);
    } catch (error) {
      logger.error(TAG, `删除分组标签失败: ${normalizedName}, ${String(error)}`);
      promptAction.showToast({ message: `删除分组失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private toActionMenuButtons(entries: BatchActionButton[]): [
    BatchActionButton,
    BatchActionButton?,
    BatchActionButton?,
    BatchActionButton?,
    BatchActionButton?,
    BatchActionButton?
  ] {
    if (entries.length <= 1) {
      return [entries[0]];
    }
    if (entries.length === 2) {
      return [entries[0], entries[1]];
    }
    if (entries.length === 3) {
      return [entries[0], entries[1], entries[2]];
    }
    if (entries.length === 4) {
      return [entries[0], entries[1], entries[2], entries[3]];
    }
    if (entries.length === 5) {
      return [entries[0], entries[1], entries[2], entries[3], entries[4]];
    }
    return [entries[0], entries[1], entries[2], entries[3], entries[4], entries[5]];
  }

  private showPagedGroupPicker(
    title: string,
    groups: string[],
    pageIndex: number,
    onSelectGroup: (groupName: string) => void
  ): void {
    const pageSize = 3;
    const totalPages = Math.ceil(groups.length / pageSize);
    const safePageIndex = Math.max(0, Math.min(pageIndex, Math.max(totalPages - 1, 0)));
    const start = safePageIndex * pageSize;
    const end = Math.min(start + pageSize, groups.length);
    const pageGroups = groups.slice(start, end);

    const hasPrevPage = safePageIndex > 0;
    const hasNextPage = safePageIndex < totalPages - 1;
    const entries: BatchActionButton[] = [];
    for (let i = 0; i < pageGroups.length; i++) {
      entries.push({ text: pageGroups[i], color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton);
    }
    if (hasPrevPage) {
      entries.push({ text: '上一页', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton);
    }
    if (hasNextPage) {
      entries.push({ text: '下一页', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton);
    }
    entries.push({ text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') } as BatchActionButton);

    promptAction.showActionMenu({
      title: `${title}（${safePageIndex + 1}/${Math.max(totalPages, 1)}）`,
      buttons: this.toActionMenuButtons(entries)
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < 0) {
        return;
      }
      if (result.index < pageGroups.length) {
        onSelectGroup(pageGroups[result.index]);
        return;
      }

      let cursor = pageGroups.length;
      if (hasPrevPage) {
        if (result.index === cursor) {
          this.showPagedGroupPicker(title, groups, safePageIndex - 1, onSelectGroup);
          return;
        }
        cursor++;
      }
      if (hasNextPage) {
        if (result.index === cursor) {
          this.showPagedGroupPicker(title, groups, safePageIndex + 1, onSelectGroup);
        }
      }
    }).catch(() => {
      logger.debug(TAG, `${title}菜单已关闭`);
    });
  }

  private showRenameGroupMenu(): void {
    const groups = this.getAllGroupNames();
    if (groups.length === 0) {
      promptAction.showToast({ message: '当前没有可重命名的分组' });
      return;
    }
    this.showPagedGroupPicker('选择要重命名的分组', groups, 0, (oldName: string) => {
      this.groupRenameOldName = oldName;
      this.openGroupInputDialog('rename', `重命名分组：${oldName}`, '请输入新分组名称');
    });
  }

  private showDeleteGroupMenu(): void {
    const groups = this.getAllGroupNames();
    if (groups.length === 0) {
      promptAction.showToast({ message: '当前没有可删除的分组' });
      return;
    }
    this.showPagedGroupPicker('选择要删除的分组', groups, 0, (targetGroup: string) => {
      promptAction.showDialog({
        title: '确认删除分组标签',
        message: `确认从全部订阅源中移除分组「${targetGroup}」？`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '删除', color: '#FF4D4F' }
        ]
      }).then((dialogResult: DialogResult) => {
        if (dialogResult.index === 1) {
          this.removeGroupAcrossSources(targetGroup);
        }
      });
    });
  }

  private showGroupOperationMenu(): void {
    const buttons: [BatchActionButton, BatchActionButton, BatchActionButton, BatchActionButton, BatchActionButton, BatchActionButton] = [
      { text: '当前筛选设组', color: $r('sys.color.ohos_id_color_text_primary_activated') } as BatchActionButton,
      { text: '当前筛选追加组', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton,
      { text: '当前筛选移除组', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton,
      { text: '重命名分组', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton,
      { text: '删除分组', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton,
      { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') } as BatchActionButton
    ];
    promptAction.showActionMenu({
      title: '分组操作',
      buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.openGroupInputDialog('set', '当前筛选设组', '请输入分组名称');
        return;
      }
      if (result.index === 1) {
        this.openGroupInputDialog('append', '当前筛选追加组', '请输入分组名称');
        return;
      }
      if (result.index === 2) {
        this.openGroupInputDialog('remove', '当前筛选移除组', '请输入分组名称');
        return;
      }
      if (result.index === 3) {
        this.showRenameGroupMenu();
        return;
      }
      if (result.index === 4) {
        this.showDeleteGroupMenu();
        return;
      }
    }).catch(() => {
      logger.debug(TAG, '分组操作菜单已关闭');
    });
  }

  private async confirmGroupInputDialog(): Promise<void> {
    const action = this.groupInputAction;
    const input = this.groupInputText.trim();
    const renameOldName = this.groupRenameOldName;
    if (input.length === 0) {
      promptAction.showToast({ message: '请输入分组名称' });
      return;
    }
    this.closeGroupInputDialog();
    if (action === 'set' || action === 'append' || action === 'remove') {
      await this.applyGroupActionToFilteredSources(action, input);
      return;
    }
    if (action === 'rename') {
      await this.renameGroupAcrossSources(renameOldName, input);
    }
  }

  private applyFilter(): void {
    const keyword = this.searchKeyword.trim().toLowerCase();
    const result: RssSubscriptionSource[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      const source = this.sources[i];
      if (!this.sourceMatchesCurrentGroupFilter(source)) {
        continue;
      }
      if (keyword.length === 0) {
        result.push(source);
        continue;
      }
      const sourceName = source.name.toLowerCase();
      const sourceUrl = source.url.toLowerCase();
      const groupName = (source.groupName || '').toLowerCase();
      if (sourceName.includes(keyword) || sourceUrl.includes(keyword) || groupName.includes(keyword)) {
        result.push(source);
      }
    }
    this.filteredSources = result;
  }

  private onSearchChange(keyword: string): void {
    this.searchKeyword = keyword;
    this.applyFilter();
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '从未';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private openCreateDialog(): void {
    logger.info(TAG, '打开新增订阅源弹窗');
    this.editingSourceId = '';
    this.editName = '';
    this.editUrl = '';
    this.editGroupName = '';
    this.editSourceComment = '';
    this.editAutoUpdate = true;
    this.editIntervalText = '180';
    this.editIconUrl = '';
    this.showAdvancedConfig = false;
    this.editHeader = '';
    this.editJsLib = '';
    this.editSortUrl = '';
    this.editRuleArticles = '';
    this.editRuleNextPage = '';
    this.editRuleTitle = '';
    this.editRuleLink = '';
    this.editRulePubDate = '';
    this.editRuleDescription = '';
    this.editRuleContent = '';
    this.editRuleImage = '';
    this.editSingleUrl = false;
    this.editArticleStyleText = '0';
    this.editEnableJs = true;
    this.editLoadWithBaseUrl = true;
    this.showEditDialog = true;
  }

  private openEditDialog(source: RssSubscriptionSource): void {
    logger.info(TAG, `打开编辑订阅源弹窗: ${source.name}`);
    this.editingSourceId = source.id;
    this.editName = source.name;
    this.editUrl = source.url;
    this.editGroupName = source.groupName || '';
    this.editSourceComment = source.sourceComment || '';
    this.editAutoUpdate = source.autoUpdate;
    this.editIntervalText = `${source.updateIntervalMin}`;
    this.editIconUrl = source.iconUrl || '';
    this.showAdvancedConfig = (source.ruleArticles || '').trim().length > 0
      || (source.sortUrl || '').trim().length > 0
      || (source.ruleTitle || '').trim().length > 0
      || (source.ruleLink || '').trim().length > 0;
    this.editHeader = source.header || '';
    this.editJsLib = source.jsLib || '';
    this.editSortUrl = source.sortUrl || '';
    this.editRuleArticles = source.ruleArticles || '';
    this.editRuleNextPage = source.ruleNextPage || '';
    this.editRuleTitle = source.ruleTitle || '';
    this.editRuleLink = source.ruleLink || '';
    this.editRulePubDate = source.rulePubDate || '';
    this.editRuleDescription = source.ruleDescription || '';
    this.editRuleContent = source.ruleContent || '';
    this.editRuleImage = source.ruleImage || '';
    this.editSingleUrl = source.singleUrl;
    this.editArticleStyleText = `${source.articleStyle}`;
    this.editEnableJs = source.enableJs;
    this.editLoadWithBaseUrl = source.loadWithBaseUrl;
    this.showEditDialog = true;
  }

  private async saveEditDialog(): Promise<void> {
    const name = this.editName.trim();
    const url = this.editUrl.trim();
    const groupName = this.editGroupName.trim();
    const sourceComment = this.editSourceComment.trim();
    const iconUrl = this.editIconUrl.trim();
    const header = this.editHeader.trim();
    const jsLib = this.editJsLib.trim();
    const sortUrl = this.editSortUrl.trim();
    const ruleArticles = this.editRuleArticles.trim();
    const ruleNextPage = this.editRuleNextPage.trim();
    const ruleTitle = this.editRuleTitle.trim();
    const ruleLink = this.editRuleLink.trim();
    const rulePubDate = this.editRulePubDate.trim();
    const ruleDescription = this.editRuleDescription.trim();
    const ruleContent = this.editRuleContent.trim();
    const ruleImage = this.editRuleImage.trim();
    const interval = Math.max(1, parseInt(this.editIntervalText || '180', 10) || 180);
    const articleStyle = Math.max(0, parseInt(this.editArticleStyleText || '0', 10) || 0);

    if (name.length === 0 || url.length === 0) {
      promptAction.showToast({ message: '名称和 URL 不能为空' });
      return;
    }

    if (this.showAdvancedConfig && ruleArticles.length > 0 && ruleTitle.length === 0 && ruleLink.length === 0) {
      promptAction.showToast({ message: '规则模式下建议至少配置标题规则或链接规则' });
    }
    if (this.showAdvancedConfig && ruleArticles.length === 0) {
      const hasOtherRuleField = ruleTitle.length > 0
        || ruleLink.length > 0
        || rulePubDate.length > 0
        || ruleDescription.length > 0
        || ruleContent.length > 0
        || ruleImage.length > 0
        || ruleNextPage.length > 0;
      if (hasOtherRuleField) {
        promptAction.showToast({ message: '已填写规则字段，但缺少 ruleArticles 列表规则' });
        return;
      }
    }

    const updatePayload: RssSourceUpdatePayload = {
      name,
      url,
      groupName,
      sourceComment,
      autoUpdate: this.editAutoUpdate,
      updateIntervalMin: interval,
      iconUrl,
      header,
      jsLib,
      sortUrl,
      ruleArticles,
      ruleNextPage,
      ruleTitle,
      ruleLink,
      rulePubDate,
      ruleDescription,
      ruleContent,
      ruleImage,
      singleUrl: this.editSingleUrl,
      articleStyle,
      enableJs: this.editEnableJs,
      loadWithBaseUrl: this.editLoadWithBaseUrl
    };

    try {
      logger.info(
        TAG,
        `${this.editingSourceId.length === 0 ? '新增' : '更新'}订阅源: ${name}, 规则模式=${ruleArticles.length > 0}`
      );
      if (this.editingSourceId.length === 0) {
        const created = await this.manager.addSource(name, url, groupName);
        await this.manager.updateSource(created.id, updatePayload);
        promptAction.showToast({ message: '已新增订阅源' });
      } else {
        await this.manager.updateSource(this.editingSourceId, updatePayload);
        promptAction.showToast({ message: '已更新订阅源' });
      }
      this.showEditDialog = false;
      await this.loadSources();
    } catch (error) {
      logger.error(TAG, `保存订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `保存失败: ${String(error)}` });
    }
  }

  private deleteSource(source: RssSubscriptionSource): void {
    this.pendingDeleteSource = source;
    this.showDeleteConfirmDialog = true;
  }

  private async confirmDeleteSource(): Promise<void> {
    if (!this.pendingDeleteSource) {
      this.showDeleteConfirmDialog = false;
      return;
    }
    const sourceToDelete = this.pendingDeleteSource;
    this.showDeleteConfirmDialog = false;
    this.pendingDeleteSource = null;
    try {
      logger.info(TAG, `删除订阅源: ${sourceToDelete.name}`);
      await this.manager.deleteSource(sourceToDelete.id);
      await this.loadSources();
      promptAction.showToast({ message: '已删除' });
    } catch (error) {
      logger.error(TAG, `删除订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `删除失败: ${String(error)}` });
    }
  }

  private async moveSource(sourceId: string, direction: 'up' | 'down'): Promise<void> {
    try {
      const moved = await this.manager.moveSource(sourceId, direction);
      if (moved) {
        await this.loadSources();
      }
    } catch (error) {
      logger.error(TAG, `调整订阅源顺序失败: ${String(error)}`);
      promptAction.showToast({ message: `排序失败: ${String(error)}` });
    }
  }

  private async toggleSource(sourceId: string, enabled: boolean): Promise<void> {
    try {
      await this.manager.setSourceEnabled(sourceId, enabled);
      let found = false;
      for (let i = 0; i < this.sources.length; i++) {
        if (this.sources[i].id === sourceId) {
          this.sources[i].enabled = enabled;
          found = true;
          break;
        }
      }
      if (!found) {
        await this.loadSources();
        return;
      }
      this.ensureGroupFilterKeyValid();
      this.applyFilter();
    } catch (error) {
      logger.error(TAG, `更新订阅源启用状态失败: ${String(error)}`);
      promptAction.showToast({ message: `更新失败: ${String(error)}` });
    }
  }

  private async refreshSource(source: RssSubscriptionSource): Promise<void> {
    try {
      logger.info(TAG, `开始刷新订阅源: ${source.name}`);
      const result = await this.manager.refreshSource(source.id);
      if (result.success) {
        promptAction.showToast({ message: `刷新成功: ${result.insertedCount}/${result.itemCount}` });
      } else {
        promptAction.showToast({ message: `刷新失败: ${result.error || result.statusCode}` });
      }
      await this.loadSources();
    } catch (error) {
      logger.error(TAG, `刷新订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `刷新失败: ${String(error)}` });
    }
  }

  private openSourceDebugPage(sourceId: string): void {
    const params: RssSourceDebugRouteParam = { sourceId };
    this.pathStack.pushPathByName('RssSourceDebugPage', params);
  }

  private async refreshAllSources(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.progressText = '准备中...';
    try {
      logger.info(TAG, '开始批量刷新订阅源');
      const results = await this.manager.refreshAll((progress) => {
        const detail = progress.success
          ? `新增${progress.insertedCount || 0}/总${progress.itemCount || 0}`
          : `失败: ${progress.error || '未知错误'}`;
        this.progressText = `${progress.current}/${progress.total} ${progress.sourceName} ${detail}`;
      });
      const successCount = results.filter((item) => item.success).length;
      const failCount = results.length - successCount;
      promptAction.showToast({ message: `刷新完成，成功 ${successCount}，失败 ${failCount}` });
      logger.info(TAG, `批量刷新订阅源完成: 成功=${successCount}, 失败=${failCount}`);
      await this.loadSources();
    } catch (error) {
      logger.error(TAG, `批量刷新订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `批量刷新失败: ${String(error)}` });
    }
    this.isRefreshing = false;
    this.progressText = '';
  }

  private async refreshDueSources(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.progressText = '准备中...';
    try {
      logger.info(TAG, '开始刷新到期订阅源');
      const results = await this.manager.refreshDueSources((progress) => {
        const detail = progress.success
          ? `新增${progress.insertedCount || 0}/总${progress.itemCount || 0}`
          : `失败: ${progress.error || '未知错误'}`;
        this.progressText = `${progress.current}/${progress.total} ${progress.sourceName} ${detail}`;
      });
      if (results.length === 0) {
        promptAction.showToast({ message: '暂无到期订阅源' });
        logger.info(TAG, '刷新到期订阅源完成: 无到期源');
      } else {
        const successCount = results.filter((item) => item.success).length;
        const failCount = results.length - successCount;
        promptAction.showToast({ message: `到期刷新完成，成功 ${successCount}，失败 ${failCount}` });
        logger.info(TAG, `刷新到期订阅源完成: 总数=${results.length}, 成功=${successCount}, 失败=${failCount}`);
      }
      await this.loadSources();
    } catch (error) {
      logger.error(TAG, `刷新到期订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `到期刷新失败: ${String(error)}` });
    }
    this.isRefreshing = false;
    this.progressText = '';
  }

  private async setAllSourcesEnabled(enabled: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (this.sources.length === 0) {
      promptAction.showToast({ message: '当前没有可操作的订阅源' });
      return;
    }

    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始批量更新订阅源启用状态: enabled=${enabled}, 总数=${this.sources.length}`);
      let changedCount = 0;
      for (let i = 0; i < this.sources.length; i++) {
        const source = this.sources[i];
        if (source.enabled === enabled) {
          continue;
        }
        await this.manager.setSourceEnabled(source.id, enabled);
        changedCount++;
      }
      await this.loadSources();
      promptAction.showToast({
        message: `${enabled ? '已启用' : '已禁用'} ${changedCount} 个订阅源`
      });
      logger.info(
        TAG,
        `批量更新订阅源启用状态完成: enabled=${enabled}, 变更=${changedCount}, 总数=${this.sources.length}`
      );
    } catch (error) {
      logger.error(TAG, `批量更新订阅源启用状态失败: ${String(error)}`);
      promptAction.showToast({ message: `批量操作失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private showBatchActionMenu(): void {
    if (this.isBatchOperating) {
      return;
    }
    const buttons: [BatchActionButton, BatchActionButton, BatchActionButton] = [
      { text: '全部启用', color: $r('sys.color.ohos_id_color_text_primary_activated') } as BatchActionButton,
      { text: '全部禁用', color: $r('sys.color.ohos_id_color_text_primary') } as BatchActionButton,
      { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') } as BatchActionButton
    ];
    promptAction.showActionMenu({
      title: '批量操作订阅源',
      buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.setAllSourcesEnabled(true);
        return;
      }
      if (result.index === 1) {
        this.setAllSourcesEnabled(false);
        return;
      }
    }).catch(() => {
      logger.warn(TAG, '批量操作菜单已关闭');
    });
  }

  private async exportSourcesToClipboard(): Promise<void> {
    try {
      const sources = await this.manager.getAllSources(false);
      if (sources.length === 0) {
        promptAction.showToast({ message: '当前没有可导出的订阅源' });
        return;
      }
      const content = JSON.stringify(sources, null, 2);
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: `已复制 ${sources.length} 个订阅源 JSON` });
      logger.info(TAG, `导出订阅源到剪贴板完成: 数量=${sources.length}, 内容长度=${content.length}`);
    } catch (error) {
      logger.error(TAG, `导出订阅源到剪贴板失败: ${String(error)}`);
      promptAction.showToast({ message: `导出失败: ${String(error)}` });
    }
  }

  private async fillImportTextFromClipboard(): Promise<void> {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = await systemPasteboard.getData();
      if (!data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        promptAction.showToast({ message: '剪贴板中没有文本内容' });
        return;
      }
      const text: string = data.getPrimaryText();
      const normalized = text ? text.trim() : '';
      if (normalized.length === 0) {
        promptAction.showToast({ message: '剪贴板文本为空' });
        return;
      }
      this.importText = normalized;
      promptAction.showToast({ message: '已从剪贴板读取内容' });
      logger.info(TAG, `读取剪贴板导入内容成功: 长度=${normalized.length}`);
    } catch (error) {
      logger.error(TAG, `读取剪贴板导入内容失败: ${String(error)}`);
      promptAction.showToast({ message: `读取剪贴板失败: ${String(error)}` });
    }
  }

  private buildRulePreviewText(result: RssRulePreviewResult): string {
    const lines: string[] = [];
    lines.push(`源名称: ${result.sourceName}`);
    lines.push(`抓取地址: ${result.requestUrl}`);
    lines.push(`规则命中总数: ${result.total}`);
    lines.push(`预览返回数量: ${result.items.length}`);
    if (result.warning.length > 0) {
      lines.push(`提示: ${result.warning}`);
    }
    lines.push('----------------------------------------');
    for (let i = 0; i < result.items.length; i++) {
      const item = result.items[i];
      lines.push(`${i + 1}. ${item.title}`);
      if (item.link.length > 0) {
        lines.push(`链接: ${item.link}`);
      }
      if (item.pubDate > 0) {
        lines.push(`时间: ${this.formatTime(item.pubDate)}`);
      }
      if (item.description.length > 0) {
        lines.push(`摘要: ${item.description}`);
      }
      lines.push('----------------------------------------');
    }
    return lines.join('\n');
  }

  private async previewSourceRules(source: RssSubscriptionSource): Promise<void> {
    if (this.isRulePreviewLoading) {
      return;
    }
    this.isRulePreviewLoading = true;
    try {
      logger.info(TAG, `开始预览订阅源规则: ${source.name}`);
      const result = await this.manager.previewSourceRules(source.id, 12);
      this.rulePreviewSourceName = source.name;
      this.rulePreviewText = this.buildRulePreviewText(result);
      this.showRulePreviewDialog = true;
      logger.info(
        TAG,
        `规则预览成功: ${source.name}, 命中=${result.total}, 返回=${result.items.length}`
      );
    } catch (error) {
      logger.error(TAG, `规则预览失败: ${source.name}, ${String(error)}`);
      promptAction.showToast({ message: `规则预览失败: ${String(error)}` });
    }
    this.isRulePreviewLoading = false;
  }

  private showImportOptions(): void {
    logger.info(TAG, '打开订阅源导入方式弹窗');
    this.showImportTypeDialog = true;
  }

  private getImportConflictPolicyLabel(): string {
    return this.importConflictPolicy === 'overwrite' ? '覆盖已存在' : '跳过已存在';
  }

  private resolveErrorText(error: PageErrorValue): string {
    if (error === undefined || error === null) {
      return '未知错误';
    }
    if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      const message = error.message ? error.message.trim() : '';
      if (message.length > 0) {
        return message;
      }
      return error.name ? error.name : 'Error';
    }

    const objectError = error as Object;
    const entries = Object.entries(objectError) as [string, Object][];
    let message = '';
    let code = '';
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = String(entries[i][1]);
      if (message.length === 0 && (key === 'message' || key === 'msg' || key === 'error' || key === 'detail')) {
        message = value;
      }
      if (code.length === 0 && (key === 'code' || key === 'statusCode' || key === 'status' || key === 'errno')) {
        code = value;
      }
    }
    if (message.length > 0 && code.length > 0) {
      return `${message} (code=${code})`;
    }
    if (message.length > 0) {
      return message;
    }
    if (code.length > 0) {
      return `错误码 ${code}`;
    }
    try {
      const fallbackJson = JSON.stringify(objectError);
      if (fallbackJson && fallbackJson.length > 0 && fallbackJson !== '{}') {
        return fallbackJson;
      }
    } catch (_error) {
    }
    return String(objectError);
  }

  private buildImportResultMessage(prefix: string, result: RssImportResult): string {
    return `${prefix}，总计 ${result.total}，成功 ${result.success}（新增 ${result.created}，更新 ${result.updated}），失败 ${result.failed}，跳过 ${result.skipped}`;
  }

  private logImportErrors(mode: string, result: RssImportResult): void {
    if (result.failed <= 0 || result.errors.length === 0) {
      return;
    }
    const maxLogCount = result.errors.length > 5 ? 5 : result.errors.length;
    for (let i = 0; i < maxLogCount; i++) {
      logger.warn(TAG, `${mode}导入错误[${i + 1}/${result.errors.length}]: ${result.errors[i]}`);
    }
    if (result.errors.length > maxLogCount) {
      logger.warn(TAG, `${mode}导入还有 ${result.errors.length - maxLogCount} 条错误未展开`);
    }
  }

  private copyErrorList(errors: string[]): string[] {
    const copied: string[] = [];
    for (let i = 0; i < errors.length; i++) {
      copied.push(errors[i]);
    }
    return copied;
  }

  private presentImportResult(mode: string, result: RssImportResult): void {
    const summary = this.buildImportResultMessage(`${mode}导入完成`, result);
    promptAction.showToast({ message: summary });
    this.logImportErrors(mode, result);

    if (result.failed > 0 && result.errors.length > 0) {
      this.importErrorTitle = `${mode}导入失败详情`;
      this.importErrorSummary = summary;
      this.importErrorList = this.copyErrorList(result.errors);
      this.showImportErrorDialog = true;
    }
  }

  private async importSourcesFromPaste(): Promise<void> {
    const text = this.importText.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '请输入导入 JSON 内容' });
      return;
    }
    try {
      logger.info(TAG, `开始粘贴导入订阅源: 策略=${this.importConflictPolicy}`);
      const result = await this.manager.importSourcesFromJson(text, this.importConflictPolicy);
      this.showImportDialog = false;
      this.importText = '';
      await this.loadSources();
      this.presentImportResult('粘贴', result);
      logger.info(
        TAG,
        `粘贴导入订阅源完成: 策略=${this.importConflictPolicy}, 总计=${result.total}, 成功=${result.success}, 新增=${result.created}, 更新=${result.updated}, 失败=${result.failed}, 跳过=${result.skipped}`
      );
    } catch (error) {
      logger.error(TAG, `粘贴导入订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  private async importSourcesFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入网络导入链接' });
      return;
    }
    try {
      logger.info(TAG, `开始网络导入订阅源: url=${url}, 策略=${this.importConflictPolicy}`);
      const result = await this.manager.importSourcesFromUrl(url, this.importConflictPolicy);
      this.showImportUrlDialog = false;
      this.importUrl = '';
      await this.loadSources();
      this.presentImportResult('网络', result);
      logger.info(
        TAG,
        `网络导入订阅源完成: 策略=${this.importConflictPolicy}, 总计=${result.total}, 成功=${result.success}, 新增=${result.created}, 更新=${result.updated}, 失败=${result.failed}, 跳过=${result.skipped}`
      );
    } catch (error) {
      const errorText = this.resolveErrorText(error as PageErrorValue);
      logger.error(TAG, `网络导入订阅源失败: ${errorText}`);
      promptAction.showToast({ message: `网络导入失败: ${errorText}` });
      this.importErrorTitle = '网络导入失败详情';
      this.importErrorSummary = `网络导入失败: ${errorText}`;
      this.importErrorList = this.copyErrorList([errorText]);
      this.showImportErrorDialog = true;
    }
  }

  private async importSourcesFromFile(): Promise<void> {
    let file: fs.File | null = null;
    try {
      logger.info(TAG, `开始文件导入订阅源: 策略=${this.importConflictPolicy}`);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文' });
        logger.error(TAG, '文件导入失败: 无法获取 UIAbilityContext');
        return;
      }
      const documentPicker = new picker.DocumentViewPicker(context);
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1,
        fileSuffixFilters: ['.json', '.txt']
      };
      const selectResult = await documentPicker.select(selectOptions);
      if (!selectResult || selectResult.length === 0) {
        logger.info(TAG, '文件导入已取消，未选择文件');
        return;
      }

      const fileUri = selectResult[0];
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const fileSize = stat.size;
      if (fileSize <= 0) {
        throw new Error('文件内容为空');
      }
      const maxSize = 20 * 1024 * 1024;
      if (fileSize > maxSize) {
        throw new Error('文件过大，最大支持 20MB');
      }

      const buffer = new ArrayBuffer(fileSize);
      const readLen = fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      file = null;
      if (readLen <= 0) {
        throw new Error('文件读取失败');
      }

      const uint8Array = new Uint8Array(buffer, 0, readLen);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const text = decoder.decode(uint8Array).trim();
      if (text.length === 0) {
        throw new Error('文件内容为空');
      }

      const result = await this.manager.importSourcesFromJson(text, this.importConflictPolicy);
      await this.loadSources();
      this.presentImportResult('文件', result);
      logger.info(
        TAG,
        `文件导入订阅源完成: 策略=${this.importConflictPolicy}, 总计=${result.total}, 成功=${result.success}, 新增=${result.created}, 更新=${result.updated}, 失败=${result.failed}, 跳过=${result.skipped}`
      );
    } catch (error) {
      logger.error(TAG, `文件导入订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `文件导入失败: ${String(error)}` });
    } finally {
      if (file) {
        fs.closeSync(file);
      }
    }
  }

  private getTotalSourceCount(): number {
    return this.sources.length;
  }

  private getEnabledSourceCount(): number {
    let count = 0;
    for (const source of this.sources) {
      if (source.enabled) {
        count++;
      }
    }
    return count;
  }

  private getDisplaySourceCount(): number {
    return this.filteredSources.length;
  }

  private canReorderInCurrentView(): boolean {
    return this.searchKeyword.trim().length === 0 && this.selectedGroupFilterKey === 'all';
  }

  @Builder
  private buildSearchBar() {
    Row() {
      TextInput({ placeholder: '搜索订阅源名称、分组或 URL...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.onSearchChange(value);
        })

      if (this.searchKeyword.trim().length > 0) {
        Text('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 12 })
          .onClick(() => {
            this.searchKeyword = '';
            this.applyFilter();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .margin({ left: 12, right: 12 })
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

  @Builder
  private buildStatsCard() {
    Column() {
      Row() {
        Column() {
          Text(`${this.getTotalSourceCount()}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('总订阅源')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.getEnabledSourceCount()}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor('#52C41A')
          Text('已启用')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 8 })

      if (this.searchKeyword.trim().length > 0 || this.selectedGroupFilterKey !== 'all') {
        Text(`筛选结果 ${this.getDisplaySourceCount()} / ${this.getTotalSourceCount()}（${this.getCurrentGroupFilterLabel()}）`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 6 })
      }

      if (this.isRefreshing && this.progressText.length > 0) {
        Text(`刷新进度: ${this.progressText}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 12 })
      }

      Row() {
        Button(this.isBatchOperating ? '批量处理中...' : '批量启用/禁用')
          .height(34)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(17)
          .enabled(!this.isBatchOperating)
          .onClick(() => {
            this.showBatchActionMenu();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, bottom: 12 })
    }
    .width('100%')
    .margin({ left: 12, right: 12, top: 8, bottom: 8 })
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

  @Builder
  private buildGroupFilterButton(option: GroupFilterOption) {
    Button(`${option.label}(${option.count})`)
      .height(30)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(this.selectedGroupFilterKey === option.key
        ? '#FFFFFF'
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .backgroundColor(this.selectedGroupFilterKey === option.key
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(15)
      .padding({ left: 10, right: 10 })
      .onClick(() => {
        this.chooseGroupFilter(option.key);
      })
  }

  @Builder
  private buildGroupFilterBar() {
    Column({ space: 6 }) {
      Text(`当前分组筛选: ${this.getCurrentGroupFilterLabel()}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.getGroupFilterOptions(), (option: GroupFilterOption) => {
            this.buildGroupFilterButton(option)
          }, (option: GroupFilterOption): string => option.key)
        }
        .width('100%')
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
    .margin({ left: 12, right: 12, bottom: 8 })
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

  @Builder
  private buildSourceItem(source: RssSubscriptionSource, index: number) {
    Row() {
      Column()
        .width(4)
        .height(42)
        .borderRadius(2)
        .backgroundColor(source.enabled ? '#52C41A' : '#D9D9D9')

      Column({ space: 4 }) {
        Row() {
          Text(source.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (source.autoUpdate) {
            Text('自动更新')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(2)
              .margin({ left: 8 })
          }

          if ((source.ruleArticles || '').trim().length > 0) {
            Text('规则模式')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor('#FA8C16')
              .backgroundColor('rgba(250,140,22,0.16)')
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(2)
              .margin({ left: 6 })
          }
        }
        .width('100%')

        Text(source.groupName && source.groupName.length > 0 ? source.groupName : '未分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        Text(source.url)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (source.lastError && source.lastError.length > 0) {
          Text(`错误: ${source.lastError}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else {
          Text(`最近成功 ${this.formatTime(source.lastSuccessTime)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }

        Row({ space: 8 }) {
          Button('刷新')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.refreshSource(source);
            })

          Button('上移')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .enabled(this.canReorderInCurrentView() && index > 0)
            .onClick(() => {
              this.moveSource(source.id, 'up');
            })

          Button('下移')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .enabled(this.canReorderInCurrentView() && index < this.sources.length - 1)
            .onClick(() => {
              this.moveSource(source.id, 'down');
            })

          Button('编辑')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.openEditDialog(source);
            })

          Button('删除')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.deleteSource(source);
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button(this.isRulePreviewLoading ? '规则预览中...' : '规则预览')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .enabled(!this.isRulePreviewLoading && (source.ruleArticles || '').trim().length > 0)
            .onClick(() => {
              this.previewSourceRules(source);
            })

          Button('调试')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.openSourceDebugPage(source.id);
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Toggle({ type: ToggleType.Switch, isOn: source.enabled })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.toggleSource(source.id, isOn);
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
  }

  @Builder
  private buildEditDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      maxHeight: '90%',
      onMaskTap: () => {
        this.showEditDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text(this.editingSourceId.length > 0 ? '编辑订阅源' : '新增订阅源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('支持基础 RSS 与 Legado 规则模式，建议优先填写基础字段再配置高级规则')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Scroll() {
          Column({ space: 10 }) {
            TextInput({ placeholder: '名称', text: $$this.editName })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            TextInput({ placeholder: 'URL (https://...)', text: $$this.editUrl })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            TextInput({ placeholder: '分组（可选）', text: $$this.editGroupName })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            TextInput({ placeholder: '图标 URL（可选）', text: $$this.editIconUrl })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            TextInput({ placeholder: '备注（可选）', text: $$this.editSourceComment })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            Row() {
              Text('自动更新')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.editAutoUpdate })
                .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onChange((isOn: boolean) => {
                  this.editAutoUpdate = isOn;
                })
            }
            .width('100%')

            TextInput({ placeholder: '更新间隔（分钟）', text: $$this.editIntervalText })
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)

            Row() {
              Text('高级规则配置')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Blank()
              Text(this.showAdvancedConfig ? '收起' : '展开')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .padding({ top: 6, bottom: 2 })
            .onClick(() => {
              this.showAdvancedConfig = !this.showAdvancedConfig;
              logger.info(TAG, `切换高级规则配置面板: ${this.showAdvancedConfig ? '展开' : '收起'}`);
            })

            if (this.showAdvancedConfig) {
              Column({ space: 10 }) {
                TextInput({ placeholder: 'sortUrl（规则模式可选入口）', text: $$this.editSortUrl })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleArticles（列表规则，必填）', text: $$this.editRuleArticles })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleTitle（标题规则）', text: $$this.editRuleTitle })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleLink（链接规则）', text: $$this.editRuleLink })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'rulePubDate（发布时间规则）', text: $$this.editRulePubDate })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleDescription（摘要规则）', text: $$this.editRuleDescription })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleContent（正文规则）', text: $$this.editRuleContent })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleImage（图片规则）', text: $$this.editRuleImage })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'ruleNextPage（分页规则，可选）', text: $$this.editRuleNextPage })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: '请求头 header（可选）', text: $$this.editHeader })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'jsLib（可选）', text: $$this.editJsLib })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                TextInput({ placeholder: 'articleStyle（整数，默认 0）', text: $$this.editArticleStyleText })
                  .width('100%')
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(8)

                Row() {
                  Text('singleUrl（列表链接是否直接为正文）')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.editSingleUrl })
                    .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    .onChange((isOn: boolean) => {
                      this.editSingleUrl = isOn;
                    })
                }
                .width('100%')

                Row() {
                  Text('enableJs（启用 JS）')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.editEnableJs })
                    .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    .onChange((isOn: boolean) => {
                      this.editEnableJs = isOn;
                    })
                }
                .width('100%')

                Row() {
                  Text('loadWithBaseUrl（使用 baseUrl 加载）')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.editLoadWithBaseUrl })
                    .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    .onChange((isOn: boolean) => {
                      this.editLoadWithBaseUrl = isOn;
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 10, bottom: 10 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ right: 2 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.showEditDialog = false;
            })
          Button('保存')
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.saveEditDialog();
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildImportConflictPolicySelector() {
    Column({ space: 8 }) {
      Text('重复 URL 处理策略')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        Button('覆盖已存在')
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.importConflictPolicy === 'overwrite'
            ? '#FFFFFF'
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(this.importConflictPolicy === 'overwrite'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => {
            this.importConflictPolicy = 'overwrite';
            logger.info(TAG, '导入冲突策略切换: 覆盖已存在');
          })

        Button('跳过已存在')
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.importConflictPolicy === 'skip'
            ? '#FFFFFF'
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(this.importConflictPolicy === 'skip'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => {
            this.importConflictPolicy = 'skip';
            logger.info(TAG, '导入冲突策略切换: 跳过已存在');
          })
      }
      .width('100%')

      Text(`当前策略: ${this.getImportConflictPolicyLabel()}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
  }

  @Builder
  private buildImportTypeDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showImportTypeDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text('选择导入方式')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('请选择订阅源导入方式')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        this.buildImportConflictPolicySelector()

        Button('网络导入')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            logger.info(TAG, '导入方式选择: 网络导入');
            this.showImportTypeDialog = false;
            this.importUrl = '';
            this.showImportUrlDialog = true;
          })

        Button('文件导入')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            logger.info(TAG, '导入方式选择: 文件导入');
            this.showImportTypeDialog = false;
            this.importSourcesFromFile();
          })

        Button('粘贴导入')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            logger.info(TAG, '导入方式选择: 粘贴导入');
            this.showImportTypeDialog = false;
            this.showImportDialog = true;
          })

        Button('取消')
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(8)
          .margin({ top: 2 })
          .onClick(() => {
            this.showImportTypeDialog = false;
          })
      }
      .width('100%')
    }
  }

  @Builder
  private buildImportDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showImportDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text('粘贴导入订阅源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('支持 JSON 对象或 JSON 数组，字段可用 name/sourceName, url/sourceUrl/feedUrl')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        this.buildImportConflictPolicySelector()

        Row() {
          Button('读取剪贴板')
            .height(32)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(8)
            .onClick(() => {
              this.fillImportTextFromClipboard();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)

        TextArea({ text: $$this.importText, placeholder: '粘贴 JSON 内容' })
          .width('100%')
          .height(220)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)

        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.showImportDialog = false;
            })
          Button('导入')
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.importSourcesFromPaste();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildImportUrlDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showImportUrlDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text('网络导入订阅源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('请输入可访问的 JSON 链接，系统会自动拉取并导入订阅源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        this.buildImportConflictPolicySelector()

        TextInput({ placeholder: 'https://example.com/rss-sources.json', text: $$this.importUrl })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)

        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.showImportUrlDialog = false;
            })
          Button('导入')
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.importSourcesFromUrl();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildImportErrorDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      maxHeight: '80%',
      onMaskTap: () => {
        this.showImportErrorDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text(this.importErrorTitle.length > 0 ? this.importErrorTitle : '导入失败详情')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.importErrorSummary)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Text(`失败明细 ${this.importErrorList.length} 条`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.importErrorList, (item: string, index: number) => {
              Column({ space: 4 }) {
                Text(`第 ${index + 1} 条`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .width('100%')

                Text(item)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(8)
            }, (item: string, index: number): string => `${index}_${item}`)
          }
          .width('100%')
          .padding({ right: 2 })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Button('关闭')
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.showImportErrorDialog = false;
          })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildGroupInputDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.closeGroupInputDialog();
      }
    }) {
      Column({ space: 10 }) {
        Text(this.groupInputDialogTitle.length > 0 ? this.groupInputDialogTitle : '分组操作')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('支持英文逗号分隔多个分组，例如：资讯,漫画,科技')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        TextInput({
          placeholder: this.groupInputPlaceholder.length > 0 ? this.groupInputPlaceholder : '请输入分组名称',
          text: $$this.groupInputText
        })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)

        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.closeGroupInputDialog();
            })
          Button('确定')
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.confirmGroupInputDialog();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildDeleteConfirmDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showDeleteConfirmDialog = false;
        this.pendingDeleteSource = null;
      }
    }) {
      Column({ space: 12 }) {
        Text('删除订阅源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.pendingDeleteSource ? `确认删除「${this.pendingDeleteSource.name}」？此操作会同步删除该源条目。` : '确认执行删除操作？')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.showDeleteConfirmDialog = false;
              this.pendingDeleteSource = null;
            })
          Button('删除')
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              this.confirmDeleteSource();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildRulePreviewDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      maxHeight: '84%',
      onMaskTap: () => {
        this.showRulePreviewDialog = false;
      }
    }) {
      Column({ space: 10 }) {
        Text(`规则预览 - ${this.rulePreviewSourceName}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('以下是基于当前规则的解析预览结果，仅用于调试。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Scroll() {
          Text(this.rulePreviewText)
            .width('100%')
            .fontSize(12)
            .lineHeight(20)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .padding(10)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Button('关闭')
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.showRulePreviewDialog = false;
          })
      }
      .width('100%')
      .height('100%')
    }
  }

  private toggleSearchBar(): void {
    this.showSearchBar = !this.showSearchBar;
    if (!this.showSearchBar) {
      this.searchKeyword = '';
      this.applyFilter();
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'search',
        label: '搜索',
        symbol: $r('sys.symbol.magnifyingglass'),
        onClick: () => {
          this.toggleSearchBar();
        }
      },
      {
        id: 'create',
        label: '新增',
        symbol: $r('sys.symbol.plus'),
        onClick: () => {
          this.openCreateDialog();
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
          void this.exportSourcesToClipboard();
        }
      },
      {
        id: 'group',
        label: '分组',
        symbol: $r('sys.symbol.ellipsis_circle'),
        onClick: () => {
          this.showGroupOperationMenu();
        }
      },
      {
        id: 'refreshDue',
        label: '刷新到期',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isRefreshing,
        onClick: () => {
          void this.refreshDueSources();
        }
      },
      {
        id: 'refreshAll',
        label: '刷新全部',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isRefreshing,
        onClick: () => {
          void this.refreshAllSources();
        }
      }
    ];
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          Column() {
            this.buildSearchBar()
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .height(this.showSearchBar ? 56 : 0)
          .opacity(this.showSearchBar ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })

          this.buildStatsCard()
          this.buildGroupFilterBar()

          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('加载中...')
                .margin({ top: 10 })
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.sources.length === 0) {
            Column({ space: 12 }) {
              Text('暂无订阅源')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('点击右上角“新增”创建 RSS 订阅源')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Button('新增订阅源')
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor('#FFFFFF')
                .borderRadius(20)
                .onClick(() => {
                  this.openCreateDialog();
                })
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.filteredSources.length === 0) {
            Column({ space: 12 }) {
              Text('未找到符合条件的订阅源')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(this.selectedGroupFilterKey === 'all' ? '请尝试修改搜索关键词' : '请尝试修改搜索关键词或重置分组筛选')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Button('重置筛选')
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor('#FFFFFF')
                .borderRadius(20)
                .onClick(() => {
                  this.resetAllFilters();
                })
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List({ space: 0 }) {
              ForEach(this.filteredSources, (source: RssSubscriptionSource, index: number) => {
                ListItem() {
                  this.buildSourceItem(source, index)
                }
              }, (source: RssSubscriptionSource) => source.id)
            }
            .width('100%')
            .height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 8, bottom: 16 + this.navigationBarHeight })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({ bottom: this.navigationBarHeight })

        if (this.showEditDialog) {
          this.buildEditDialog()
        }
        if (this.showImportTypeDialog) {
          this.buildImportTypeDialog()
        }
        if (this.showImportDialog) {
          this.buildImportDialog()
        }
        if (this.showImportUrlDialog) {
          this.buildImportUrlDialog()
        }
        if (this.showImportErrorDialog) {
          this.buildImportErrorDialog()
        }
        if (this.showGroupInputDialog) {
          this.buildGroupInputDialog()
        }
        if (this.showDeleteConfirmDialog) {
          this.buildDeleteConfirmDialog()
        }
        if (this.showRulePreviewDialog) {
          this.buildRulePreviewDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '订阅源管理',
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
  }
}
