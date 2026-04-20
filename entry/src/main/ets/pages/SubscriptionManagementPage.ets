import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SettingsManager } from '../Framework/Managers/SettingsManager';
import { getTypeShelfManager, ShelfType, TypeShelf, TypeShelfManager } from '../Framework/Data/TypeShelfManager';
import {
  getSubscriptionInitializer,
  getSubscriptionManager,
  SubscriptionActionType,
  SubscriptionCondition,
  SubscriptionConditionMatchMode,
  SubscriptionConditionType,
  SubscriptionContentType,
  SubscriptionExecutionRecord,
  SubscriptionExecutionStatus,
  SubscriptionProviderType,
  SubscriptionRule,
  SubscriptionRuleCreateOptions,
  SubscriptionRuleRunResult,
  SubscriptionTargetPreview,
  SubscriptionTargetPreviewCandidate,
  SubscriptionTargetPreviewCounter,
  SubscriptionTargetType,
  SubscriptionManager
} from '../Framework/Subscription';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'SubscriptionManagementPage';
const TRACKING_PAGE_MAX_WIDTH = 1080;

enum SubscriptionCreateMode {
  SHELF = 'shelf',
  SUWAYOMI_LIBRARY = 'suwayomi_library',
  KOMGA_LIBRARY = 'komga_library'
}

enum SubscriptionPageButtonTone {
  PRIMARY = 'primary',
  SECONDARY = 'secondary',
  DANGER = 'danger'
}

interface RuleStatsSummary {
  totalCount: number;
  enabledCount: number;
  shelfCount: number;
  providerLibraryCount: number;
}

@Component
export struct SubscriptionManagementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private readonly componentId: string = `SubscriptionManagementPage_${Date.now()}`;

  @State rules: SubscriptionRule[] = [];
  @State executions: SubscriptionExecutionRecord[] = [];
  @State shelves: TypeShelf[] = [];
  @State isLoading: boolean = true;
  @State isBusy: boolean = false;
  @State runningRuleId: string = '';
  @State showCreateDialog: boolean = false;
  @State editingRuleId: string = '';
  @State createMode: SubscriptionCreateMode = SubscriptionCreateMode.SHELF;
  @State createRuleName: string = '';
  @State createSelectedShelfId: string = '';
  @State createCheckIntervalText: string = '180';
  @State createAutoDownloadCountText: string = '0';
  @State createMinNewItemsText: string = '1';
  @State createConditionMatchMode: SubscriptionConditionMatchMode = SubscriptionConditionMatchMode.ALL;
  @State createRequireFavorite: boolean = false;
  @State createExcludeNSFW: boolean = false;
  @State createTitleKeywordText: string = '';
  @State createTagKeywordText: string = '';
  @State createSourceKeywordText: string = '';
  @State createEnableNotify: boolean = true;
  @State createKomgaInstanceId: string = '';
  @State createKomgaInstanceName: string = '';
  @State showDeleteDialog: boolean = false;
  @State deletingRuleId: string = '';
  @State showPreviewDialog: boolean = false;
  @State isPreviewLoading: boolean = false;
  @State previewRuleName: string = '';
  @State previewTarget: SubscriptionTargetPreview | null = null;

  private readonly lifecycle: PageLifecycleManager = new PageLifecycleManager('SubscriptionManagementPage', { enableDebug: true });
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly typeShelfManager: TypeShelfManager = getTypeShelfManager();
  private readonly manager: SubscriptionManager = getSubscriptionManager();

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
    void this.initializeAndLoad();
  }

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    try {
      if (!this.settingsManager.isInitialized()) {
        await this.settingsManager.initialize();
        this.settingsManager.syncToAppStorage();
      }
      await this.typeShelfManager.initialize();
      const context = getContext(this) as common.UIAbilityContext;
      await getSubscriptionInitializer().initialize(context);
      await this.loadData();
      logger.info(TAG, `统一内容跟踪管理页初始化完成: 规则=${this.rules.length}`);
    } catch (error) {
      logger.error(TAG, `统一内容跟踪管理页初始化失败: ${String(error)}`);
      promptAction.showToast({ message: `初始化失败: ${String(error)}` });
    }
    this.isLoading = false;
  }

  private async loadData(): Promise<void> {
    const loadedRules = await this.manager.getAllRules();
    loadedRules.sort((left: SubscriptionRule, right: SubscriptionRule): number => right.updateTime - left.updateTime);
    const loadedExecutions = await this.manager.getExecutions('', 200);
    const loadedShelves = this.typeShelfManager.getShelves().concat();
    loadedShelves.sort((left: TypeShelf, right: TypeShelf): number => left.order - right.order);
    this.rules = loadedRules;
    this.executions = loadedExecutions;
    this.shelves = loadedShelves;
    if (this.createSelectedShelfId.length <= 0 && loadedShelves.length > 0) {
      this.createSelectedShelfId = loadedShelves[0].id;
    }
  }

  private getStatsSummary(): RuleStatsSummary {
    let enabledCount = 0;
    let shelfCount = 0;
    let providerLibraryCount = 0;
    for (let index = 0; index < this.rules.length; index++) {
      const rule = this.rules[index];
      if (rule.enabled) {
        enabledCount++;
      }
      if (rule.targetType === SubscriptionTargetType.SHELF || rule.targetType === SubscriptionTargetType.DYNAMIC_SHELF) {
        shelfCount++;
      } else if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY) {
        providerLibraryCount++;
      }
    }
    return {
      totalCount: this.rules.length,
      enabledCount: enabledCount,
      shelfCount: shelfCount,
      providerLibraryCount: providerLibraryCount
    };
  }

  private getStatsEnabledDisplayText(): string {
    const stats = this.getStatsSummary();
    return `${stats.enabledCount}/${stats.totalCount}`;
  }

  private getStatsTotalCountText(): string {
    return `${this.getStatsSummary().totalCount}`;
  }

  private getStatsShelfCountText(): string {
    return `${this.getStatsSummary().shelfCount}`;
  }

  private getStatsProviderLibraryCountText(): string {
    return `${this.getStatsSummary().providerLibraryCount}`;
  }

  private getLatestExecution(ruleId: string): SubscriptionExecutionRecord | null {
    for (let index = 0; index < this.executions.length; index++) {
      const execution = this.executions[index];
      if (execution.ruleId === ruleId) {
        return execution;
      }
    }
    return null;
  }

  private formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '未执行';
    }
    try {
      return new Date(timestamp).toLocaleString();
    } catch (_error) {
      return `${timestamp}`;
    }
  }

  private getStatusText(status: SubscriptionExecutionStatus): string {
    if (status === SubscriptionExecutionStatus.SUCCESS) {
      return '发现更新';
    }
    if (status === SubscriptionExecutionStatus.NO_UPDATE) {
      return '无更新';
    }
    if (status === SubscriptionExecutionStatus.SKIPPED) {
      return '已跳过';
    }
    if (status === SubscriptionExecutionStatus.FAILED) {
      return '执行失败';
    }
    return '暂不支持';
  }

  private getStatusColor(status: SubscriptionExecutionStatus): ResourceColor {
    if (status === SubscriptionExecutionStatus.SUCCESS) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (status === SubscriptionExecutionStatus.NO_UPDATE) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (status === SubscriptionExecutionStatus.SKIPPED) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    if (status === SubscriptionExecutionStatus.FAILED) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
  }

  private getTargetTypeText(rule: SubscriptionRule): string {
    if (rule.targetType === SubscriptionTargetType.SHELF) {
      return '书架';
    }
    if (rule.targetType === SubscriptionTargetType.DYNAMIC_SHELF) {
      return '动态书架';
    }
    if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY) {
      return '远程库';
    }
    return '作品';
  }

  private getProviderText(rule: SubscriptionRule): string {
    return this.getProviderTypeText(rule.providerType);
  }

  private getProviderTypeText(providerType: SubscriptionProviderType): string {
    if (providerType === SubscriptionProviderType.SUWAYOMI) {
      return 'Suwayomi';
    }
    if (providerType === SubscriptionProviderType.KOMGA) {
      return 'Komga';
    }
    if (providerType === SubscriptionProviderType.LEGADO) {
      return 'Legado';
    }
    if (providerType === SubscriptionProviderType.WEBVIEW) {
      return 'WebView';
    }
    return '通用';
  }

  private getContentTypeText(rule: SubscriptionRule): string {
    return this.getContentTypeDisplayText(rule.contentType);
  }

  private getContentTypeDisplayText(contentType: SubscriptionContentType): string {
    if (contentType === SubscriptionContentType.NOVEL) {
      return '小说';
    }
    if (contentType === SubscriptionContentType.EBOOK) {
      return '电子书';
    }
    if (contentType === SubscriptionContentType.MIXED) {
      return '混合';
    }
    return '漫画';
  }

  private getConditionSummary(rule: SubscriptionRule): string {
    const parts: string[] = [`间隔 ${rule.checkIntervalMin} 分钟`];
    const minNewItems = this.getMinNewItems(rule.conditions);
    parts.push(`最少新增 ${minNewItems}`);
    const matchModeSummary = this.getConditionMatchModeSummary(rule.conditions);
    if (matchModeSummary.length > 0) {
      parts.push(matchModeSummary);
    }
    if (this.requiresFavorite(rule.conditions)) {
      parts.push('仅收藏');
    }
    if (this.excludesNSFW(rule.conditions)) {
      parts.push('排除 NSFW');
    }
    const titleKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TITLE_KEYWORD);
    if (titleKeyword.length > 0) {
      parts.push(`标题匹配 ${titleKeyword}`);
    }
    const tagKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TAG_KEYWORD);
    if (tagKeyword.length > 0) {
      parts.push(`标签匹配 ${tagKeyword}`);
    }
    const sourceKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.SOURCE_KEYWORD);
    if (sourceKeyword.length > 0) {
      parts.push(`来源匹配 ${sourceKeyword}`);
    }
    return this.joinTextParts(parts);
  }

  private getActionSummary(rule: SubscriptionRule): string {
    const parts: string[] = [];
    for (let index = 0; index < rule.actions.length; index++) {
      const action = rule.actions[index];
      if (!action.enabled) {
        continue;
      }
      if (action.type === SubscriptionActionType.NOTIFY) {
        parts.push('通知');
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW) {
        parts.push(`自动下载 ${action.limitCount > 0 ? action.limitCount : '全部'}`);
      }
    }
    if (parts.length <= 0) {
      return '仅检查更新';
    }
    return this.joinTextParts(parts);
  }

  private getMinNewItems(conditions: SubscriptionCondition[]): number {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.MIN_NEW_ITEMS && condition.enabled) {
        return condition.numericValue > 0 ? condition.numericValue : 1;
      }
    }
    return 1;
  }

  private requiresFavorite(conditions: SubscriptionCondition[]): boolean {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.ONLY_IF_FAVORITE && condition.enabled) {
        return true;
      }
    }
    return false;
  }

  private getConditionMatchMode(conditions: SubscriptionCondition[]): SubscriptionConditionMatchMode {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.MATCH_MODE && condition.enabled) {
        return condition.textValue === SubscriptionConditionMatchMode.ANY
          ? SubscriptionConditionMatchMode.ANY
          : SubscriptionConditionMatchMode.ALL;
      }
    }
    return SubscriptionConditionMatchMode.ALL;
  }

  private getPositiveConditionCount(conditions: SubscriptionCondition[]): number {
    let count = 0;
    if (this.requiresFavorite(conditions)) {
      count++;
    }
    if (this.getConditionTextByType(conditions, SubscriptionConditionType.TITLE_KEYWORD).length > 0) {
      count++;
    }
    if (this.getConditionTextByType(conditions, SubscriptionConditionType.TAG_KEYWORD).length > 0) {
      count++;
    }
    if (this.getConditionTextByType(conditions, SubscriptionConditionType.SOURCE_KEYWORD).length > 0) {
      count++;
    }
    return count;
  }

  private getConditionMatchModeSummary(conditions: SubscriptionCondition[]): string {
    if (this.getPositiveConditionCount(conditions) <= 1) {
      return '';
    }
    return this.getConditionMatchMode(conditions) === SubscriptionConditionMatchMode.ANY
      ? '任一条件命中'
      : '全部条件命中';
  }

  private excludesNSFW(conditions: SubscriptionCondition[]): boolean {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === SubscriptionConditionType.EXCLUDE_NSFW && condition.enabled) {
        return true;
      }
    }
    return false;
  }

  private getConditionTextByType(conditions: SubscriptionCondition[], conditionType: SubscriptionConditionType): string {
    for (let index = 0; index < conditions.length; index++) {
      const condition = conditions[index];
      if (condition.type === conditionType && condition.enabled && condition.textValue.trim().length > 0) {
        return condition.textValue.trim();
      }
    }
    return '';
  }

  private joinTextParts(parts: string[]): string {
    if (parts.length <= 0) {
      return '';
    }
    let result = parts[0];
    for (let index = 1; index < parts.length; index++) {
      result += ` · ${parts[index]}`;
    }
    return result;
  }

  private getEditingRule(): SubscriptionRule | null {
    if (this.editingRuleId.length <= 0) {
      return null;
    }
    for (let index = 0; index < this.rules.length; index++) {
      if (this.rules[index].id === this.editingRuleId) {
        return this.rules[index];
      }
    }
    return null;
  }

  private isEditingCreateDialog(): boolean {
    return this.editingRuleId.length > 0;
  }

  private resolveCreateModeFromRule(rule: SubscriptionRule): SubscriptionCreateMode {
    if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY) {
      return rule.providerType === SubscriptionProviderType.KOMGA
        ? SubscriptionCreateMode.KOMGA_LIBRARY
        : SubscriptionCreateMode.SUWAYOMI_LIBRARY;
    }
    return SubscriptionCreateMode.SHELF;
  }

  private fillCreateFormFromRule(rule: SubscriptionRule | null): void {
    if (rule === null) {
      this.editingRuleId = '';
      this.createRuleName = '';
      this.createCheckIntervalText = '180';
      this.createAutoDownloadCountText = '0';
      this.createMinNewItemsText = '1';
      this.createConditionMatchMode = SubscriptionConditionMatchMode.ALL;
      this.createRequireFavorite = false;
      this.createExcludeNSFW = false;
      this.createTitleKeywordText = '';
      this.createTagKeywordText = '';
      this.createSourceKeywordText = '';
      this.createEnableNotify = true;
      this.createKomgaInstanceId = '';
      this.createKomgaInstanceName = '';
      if (this.shelves.length > 0) {
        this.createSelectedShelfId = this.shelves[0].id;
      }
      return;
    }

    this.editingRuleId = rule.id;
    this.createMode = this.resolveCreateModeFromRule(rule);
    this.createRuleName = rule.name;
    this.createCheckIntervalText = `${rule.checkIntervalMin > 0 ? rule.checkIntervalMin : 180}`;
    this.createAutoDownloadCountText = '0';
    this.createMinNewItemsText = `${this.getMinNewItems(rule.conditions)}`;
    this.createConditionMatchMode = this.getConditionMatchMode(rule.conditions);
    this.createRequireFavorite = this.requiresFavorite(rule.conditions);
    this.createExcludeNSFW = this.excludesNSFW(rule.conditions);
    this.createTitleKeywordText = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TITLE_KEYWORD);
    this.createTagKeywordText = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TAG_KEYWORD);
    this.createSourceKeywordText = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.SOURCE_KEYWORD);
    this.createEnableNotify = false;
    this.createSelectedShelfId = rule.targetId;
    this.createKomgaInstanceId = '';
    this.createKomgaInstanceName = '';
    for (let index = 0; index < rule.actions.length; index++) {
      const action = rule.actions[index];
      if (action.type === SubscriptionActionType.NOTIFY && action.enabled) {
        this.createEnableNotify = true;
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW && action.enabled) {
        this.createAutoDownloadCountText = `${action.limitCount > 0 ? action.limitCount : 0}`;
      }
    }
    if (rule.targetType === SubscriptionTargetType.PROVIDER_LIBRARY && rule.providerType === SubscriptionProviderType.KOMGA) {
      if (rule.targetId !== SubscriptionProviderType.KOMGA) {
        this.createKomgaInstanceId = rule.targetId;
      }
      const titlePrefix = 'Komga 收藏库 - ';
      this.createKomgaInstanceName = rule.targetTitle.startsWith(titlePrefix)
        ? rule.targetTitle.substring(titlePrefix.length)
        : rule.targetTitle;
    }
  }

  private async refreshRules(): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      await this.loadData();
      promptAction.showToast({ message: '规则列表已刷新' });
    } catch (error) {
      logger.warn(TAG, `刷新内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `刷新失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private async runDueRules(): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      const results = await this.manager.maybeRunDueRules('manual');
      await this.loadData();
      promptAction.showToast({ message: this.buildRunDueToast(results.length) });
    } catch (error) {
      logger.error(TAG, `手动执行到期内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `执行失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private buildRunDueToast(resultCount: number): string {
    if (resultCount <= 0) {
      return '没有到期规则需要执行';
    }
    return `已执行 ${resultCount} 条到期规则`;
  }

  private openCreateDialog(): void {
    this.createMode = SubscriptionCreateMode.SHELF;
    this.fillCreateFormFromRule(null);
    this.showCreateDialog = true;
  }

  private openEditDialog(rule: SubscriptionRule): void {
    this.fillCreateFormFromRule(rule);
    this.showCreateDialog = true;
  }

  private closeCreateDialog(): void {
    this.showCreateDialog = false;
    this.editingRuleId = '';
  }

  private parsePositiveInteger(text: string, defaultValue: number, minValue: number): number {
    const parsedValue = Number(text.trim());
    if (Number.isNaN(parsedValue) || !Number.isFinite(parsedValue)) {
      return defaultValue;
    }
    const normalizedValue = Math.floor(parsedValue);
    if (normalizedValue < minValue) {
      return minValue;
    }
    return normalizedValue;
  }

  private buildCreateOptions(): Partial<SubscriptionRuleCreateOptions> {
    return {
      ruleName: this.createRuleName.trim(),
      checkIntervalMin: this.parsePositiveInteger(this.createCheckIntervalText, 180, 1),
      autoDownloadCount: this.parsePositiveInteger(this.createAutoDownloadCountText, 0, 0),
      minNewItems: this.parsePositiveInteger(this.createMinNewItemsText, 1, 1),
      conditionMatchMode: this.createConditionMatchMode,
      requireFavorite: this.createRequireFavorite,
      enableNotify: this.createEnableNotify,
      excludeNSFW: this.createExcludeNSFW,
      titleKeyword: this.createTitleKeywordText.trim(),
      tagKeyword: this.createTagKeywordText.trim(),
      sourceKeyword: this.createSourceKeywordText.trim()
    };
  }

  private hasExistingTargetRule(targetType: SubscriptionTargetType, targetId: string, providerType: SubscriptionProviderType): boolean {
    for (let index = 0; index < this.rules.length; index++) {
      const rule = this.rules[index];
      if (rule.targetType === targetType && rule.targetId === targetId && rule.providerType === providerType) {
        return true;
      }
      if ((targetType === SubscriptionTargetType.SHELF || targetType === SubscriptionTargetType.DYNAMIC_SHELF) &&
        (rule.targetType === SubscriptionTargetType.SHELF || rule.targetType === SubscriptionTargetType.DYNAMIC_SHELF) &&
        rule.targetId === targetId) {
        return true;
      }
    }
    return false;
  }

  private async confirmCreateRule(): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      const options = this.buildCreateOptions();
      const editingRule = this.getEditingRule();
      if (editingRule !== null) {
        await this.manager.saveRuleWithCreateOptions(editingRule, options);
        this.closeCreateDialog();
        await this.loadData();
        promptAction.showToast({ message: '内容跟踪规则已更新' });
        this.isBusy = false;
        return;
      }
      if (this.createMode === SubscriptionCreateMode.SHELF) {
        if (this.createSelectedShelfId.length <= 0) {
          promptAction.showToast({ message: '请先选择书架' });
          this.isBusy = false;
          return;
        }
        const targetShelf = this.findShelfById(this.createSelectedShelfId);
        if (targetShelf === null) {
          promptAction.showToast({ message: '所选书架不存在' });
          this.isBusy = false;
          return;
        }
        const targetType = targetShelf.shelfType === ShelfType.DYNAMIC
          ? SubscriptionTargetType.DYNAMIC_SHELF
          : SubscriptionTargetType.SHELF;
        if (this.hasExistingTargetRule(targetType, targetShelf.id, SubscriptionProviderType.NONE)) {
          promptAction.showToast({ message: '该书架已存在跟踪规则' });
          this.isBusy = false;
          return;
        }
        await this.manager.createShelfRule(targetShelf.id, options);
      } else if (this.createMode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
        if (this.hasExistingTargetRule(
          SubscriptionTargetType.PROVIDER_LIBRARY,
          SubscriptionProviderType.SUWAYOMI,
          SubscriptionProviderType.SUWAYOMI
        )) {
          promptAction.showToast({ message: 'Suwayomi 收藏库规则已存在' });
          this.isBusy = false;
          return;
        }
        await this.manager.createSuwayomiLibraryRule(options);
      } else {
        const komgaInstanceId = this.createKomgaInstanceId.trim();
        const targetId = komgaInstanceId.length > 0 ? komgaInstanceId : SubscriptionProviderType.KOMGA;
        if (this.hasExistingTargetRule(
          SubscriptionTargetType.PROVIDER_LIBRARY,
          targetId,
          SubscriptionProviderType.KOMGA
        )) {
          promptAction.showToast({ message: '该 Komga 远程库规则已存在' });
          this.isBusy = false;
          return;
        }
        await this.manager.createKomgaLibraryRule(
          komgaInstanceId,
          this.createKomgaInstanceName.trim(),
          options
        );
      }
      this.closeCreateDialog();
      await this.loadData();
      promptAction.showToast({ message: '内容跟踪规则已创建' });
    } catch (error) {
      logger.error(TAG, `创建内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `创建失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private findShelfById(shelfId: string): TypeShelf | null {
    for (let index = 0; index < this.shelves.length; index++) {
      if (this.shelves[index].id === shelfId) {
        return this.shelves[index];
      }
    }
    return null;
  }

  private async toggleRuleEnabled(rule: SubscriptionRule): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      await this.manager.setRuleEnabled(rule.id, !rule.enabled);
      await this.loadData();
      promptAction.showToast({ message: !rule.enabled ? '规则已启用' : '规则已停用' });
    } catch (error) {
      logger.warn(TAG, `切换规则启用状态失败: ${String(error)}`);
      promptAction.showToast({ message: `操作失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private async runRuleNow(rule: SubscriptionRule): Promise<void> {
    if (this.runningRuleId.length > 0) {
      return;
    }
    this.runningRuleId = rule.id;
    try {
      const result = await this.manager.runRuleNow(rule.id, 'manual');
      await this.loadData();
      promptAction.showToast({ message: this.buildRunRuleToast(result) });
    } catch (error) {
      logger.error(TAG, `立即执行内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `执行失败: ${String(error)}` });
    }
    this.runningRuleId = '';
  }

  private buildRunRuleToast(result: SubscriptionRuleRunResult): string {
    if (result.status === SubscriptionExecutionStatus.SUCCESS) {
      return result.deltaCount > 0 ? `发现 ${result.deltaCount} 个新内容` : '规则执行完成';
    }
    return result.message.length > 0 ? result.message : '规则执行完成';
  }

  private requestDeleteRule(rule: SubscriptionRule): void {
    this.deletingRuleId = rule.id;
    this.showDeleteDialog = true;
  }

  private closeDeleteDialog(): void {
    this.showDeleteDialog = false;
    this.deletingRuleId = '';
  }

  private getDeletingRule(): SubscriptionRule | null {
    if (this.deletingRuleId.length <= 0) {
      return null;
    }
    for (let index = 0; index < this.rules.length; index++) {
      if (this.rules[index].id === this.deletingRuleId) {
        return this.rules[index];
      }
    }
    return null;
  }

  private async confirmDeleteRule(): Promise<void> {
    const rule = this.getDeletingRule();
    if (rule === null) {
      this.closeDeleteDialog();
      return;
    }
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      await this.manager.deleteRule(rule.id);
      this.closeDeleteDialog();
      await this.loadData();
      promptAction.showToast({ message: '规则已删除' });
    } catch (error) {
      logger.error(TAG, `删除内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `删除失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private async previewRule(rule: SubscriptionRule): Promise<void> {
    this.previewRuleName = rule.name;
    this.previewTarget = null;
    this.showPreviewDialog = true;
    this.isPreviewLoading = true;
    try {
      this.previewTarget = await this.manager.previewRuleTarget(rule.id);
    } catch (error) {
      logger.warn(TAG, `预览内容跟踪规则目标失败: ${String(error)}`);
      promptAction.showToast({ message: `预览失败: ${String(error)}` });
    }
    this.isPreviewLoading = false;
  }

  private closePreviewDialog(): void {
    this.showPreviewDialog = false;
    this.previewTarget = null;
    this.previewRuleName = '';
    this.isPreviewLoading = false;
  }

  private getPreviewCandidates(): SubscriptionTargetPreviewCandidate[] {
    if (this.previewTarget === null) {
      return [];
    }
    if (this.previewTarget.candidates.length <= 30) {
      return this.previewTarget.candidates;
    }
    return this.previewTarget.candidates.slice(0, 30);
  }

  private getPreviewCounterLabel(counterKey: string, isProviderBreakdown: boolean): string {
    if (isProviderBreakdown) {
      return this.getProviderTypeText(counterKey as SubscriptionProviderType);
    }
    return this.getContentTypeDisplayText(counterKey as SubscriptionContentType);
  }

  private getPreviewCandidateMetaText(candidate: SubscriptionTargetPreviewCandidate): string {
    const parts: string[] = [
      this.getProviderTypeText(candidate.providerType),
      this.getContentTypeDisplayText(candidate.contentType),
      `本地 ${candidate.localCount}`
    ];
    if (candidate.sourceName.length > 0 && candidate.sourceName !== this.getProviderTypeText(candidate.providerType)) {
      parts.push(`来源 ${candidate.sourceName}`);
    }
    return this.joinTextParts(parts);
  }

  private getRuleCountByProvider(providerType: SubscriptionProviderType): number {
    let count = 0;
    for (let index = 0; index < this.rules.length; index++) {
      if (this.rules[index].providerType === providerType) {
        count++;
      }
    }
    return count;
  }

  private getRecentExecutionCount(hours: number): number {
    const threshold = Date.now() - hours * 60 * 60 * 1000;
    let count = 0;
    for (let index = 0; index < this.executions.length; index++) {
      if (this.executions[index].checkedAt >= threshold) {
        count++;
      }
    }
    return count;
  }

  private getRuleAccentColor(rule: SubscriptionRule): ResourceColor {
    if (rule.providerType === SubscriptionProviderType.SUWAYOMI) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (rule.providerType === SubscriptionProviderType.KOMGA) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (rule.contentType === SubscriptionContentType.EBOOK) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
  }

  private getRuleStatusBadgeText(rule: SubscriptionRule, execution: SubscriptionExecutionRecord | null): string {
    if (!rule.enabled) {
      return '已停用';
    }
    if (execution !== null) {
      return this.getStatusText(execution.status);
    }
    return '待首次检查';
  }

  private getRuleStatusBadgeColor(rule: SubscriptionRule, execution: SubscriptionExecutionRecord | null): ResourceColor {
    if (!rule.enabled) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    if (execution !== null) {
      return this.getStatusColor(execution.status);
    }
    return this.getRuleAccentColor(rule);
  }

  private getRuleExecutionSummary(rule: SubscriptionRule, execution: SubscriptionExecutionRecord | null): string {
    if (execution !== null) {
      if (execution.message.length > 0) {
        return execution.message;
      }
      return this.getStatusText(execution.status);
    }
    if (!rule.enabled) {
      return '规则已暂停，不会自动参与到期检查。';
    }
    return '规则已创建，等待下一次到期检查或手动立即执行。';
  }

  private getCreateModeDescription(mode: SubscriptionCreateMode): string {
    if (mode === SubscriptionCreateMode.SHELF) {
      return '以书架或动态书架为目标，按成员内容逐项跟踪。';
    }
    if (mode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
      return '面向整个 Suwayomi 收藏库，适合统一检查和批量自动下载。';
    }
    return '面向 Komga 远程库，可按实例聚合管理系列更新。';
  }

  private getCreateModeSymbol(mode: SubscriptionCreateMode): Resource {
    if (mode === SubscriptionCreateMode.SHELF) {
      return $r('sys.symbol.books_vertical_fill');
    }
    return $r('sys.symbol.rectangle_stack');
  }

  private isCreateModeSelected(mode: SubscriptionCreateMode): boolean {
    return this.createMode === mode;
  }

  private getCreateModeAccentColor(mode: SubscriptionCreateMode): ResourceColor {
    return this.isCreateModeSelected(mode)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
  }

  private getRuleExecution(rule: SubscriptionRule): SubscriptionExecutionRecord | null {
    return this.getLatestExecution(rule.id);
  }

  private hasRuleExecutionRecord(rule: SubscriptionRule): boolean {
    return this.getRuleExecution(rule) !== null;
  }

  private getRuleStatusBadgeTextByRule(rule: SubscriptionRule): string {
    return this.getRuleStatusBadgeText(rule, this.getRuleExecution(rule));
  }

  private getRuleStatusBadgeColorByRule(rule: SubscriptionRule): ResourceColor {
    return this.getRuleStatusBadgeColor(rule, this.getRuleExecution(rule));
  }

  private getRuleExecutionSummaryByRule(rule: SubscriptionRule): string {
    return this.getRuleExecutionSummary(rule, this.getRuleExecution(rule));
  }

  private getRuleExecutionStatusTextByRule(rule: SubscriptionRule): string {
    const execution = this.getRuleExecution(rule);
    if (execution === null) {
      return '';
    }
    return this.getStatusText(execution.status);
  }

  private getRuleExecutionStatusColorByRule(rule: SubscriptionRule): ResourceColor {
    const execution = this.getRuleExecution(rule);
    if (execution === null) {
      return this.getRuleAccentColor(rule);
    }
    return this.getStatusColor(execution.status);
  }

  private getCreateDialogTitleText(): string {
    return this.isEditingCreateDialog() ? '编辑内容跟踪规则' : '创建内容跟踪规则';
  }

  private getCreateDialogDescriptionText(): string {
    return this.isEditingCreateDialog()
      ? '这里编辑的是应用内内容更新跟踪规则。当前弹层会保留目标对象，只修改检查频率、条件与动作。'
      : '这里创建的是应用内内容更新跟踪规则，不是 RSS 订阅源。当前页优先覆盖书架级与远程库级规则，适合批量检查、聚合通知与自动下载。';
  }

  private getPageActionTextColor(tone: SubscriptionPageButtonTone): ResourceColor {
    if (tone === SubscriptionPageButtonTone.SECONDARY) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme);
  }

  private getPageActionBackgroundColor(tone: SubscriptionPageButtonTone): ResourceColor {
    if (tone === SubscriptionPageButtonTone.PRIMARY) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    if (tone === SubscriptionPageButtonTone.DANGER) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme);
  }

  private getPageActionBorderColor(tone: SubscriptionPageButtonTone): ResourceColor {
    if (tone === SubscriptionPageButtonTone.SECONDARY) {
      return ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme);
    }
    return this.getPageActionBackgroundColor(tone);
  }

  private getEditingRuleTargetTitle(): string {
    const rule = this.getEditingRule();
    return rule !== null ? rule.targetTitle : '';
  }

  private getEditingRuleMetaText(): string {
    const rule = this.getEditingRule();
    if (rule === null) {
      return '';
    }
    return `${this.getTargetTypeText(rule)} · ${this.getProviderText(rule)} · ${this.getContentTypeText(rule)}`;
  }

  private getCreateDialogPrimaryButtonText(): string {
    return this.isEditingCreateDialog() ? '保存' : '创建';
  }

  private getDeletingRulePromptText(): string {
    const deletingRule = this.getDeletingRule();
    return deletingRule !== null ? `确认删除「${deletingRule.name}」？` : '确认删除当前规则？';
  }

  private getPreviewCandidateCount(): number {
    return this.getPreviewCandidates().length;
  }

  private getActionItems(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'create',
        label: '新增',
        symbol: $r('sys.symbol.plus'),
        enabled: !this.isBusy && !this.isLoading,
        onClick: () => {
          this.openCreateDialog();
        }
      },
      {
        id: 'run_due',
        label: '执行到期',
        symbol: $r('sys.symbol.play_fill'),
        enabled: !this.isBusy && !this.isLoading,
        onClick: () => {
          void this.runDueRules();
        }
      },
      {
        id: 'refresh',
        label: '刷新',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isBusy && !this.isLoading,
        onClick: () => {
          void this.refreshRules();
        }
      }
    ];
  }

  @Builder
  private buildPageSectionHeader(titleText: string, subtitleText: string) {
    Column({ space: 4 }) {
      Text(titleText)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(subtitleText)
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  private buildStatsCard() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 8 }) {
          Text('统一内容跟踪')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('把作品级、书架级、远程库级的更新检查、自动动作与条件编排集中到同一个控制面板。')
            .fontSize(13)
            .lineHeight(20)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text(this.getStatsEnabledDisplayText())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('当前启用')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '14')
        .borderRadius(18)
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
        this.buildScopeChip('详情页单作品', ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        this.buildScopeChip('书架 / 动态书架', ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        this.buildScopeChip('Suwayomi', ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        this.buildScopeChip('Komga', ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildSingleStatItem(
          this.getStatsTotalCountText(),
          '总规则',
          '当前控制面板中存在的全部内容跟踪规则',
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          this.getStatsShelfCountText(),
          '书架规则',
          '面向普通书架和动态书架的聚合跟踪',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          this.getStatsProviderLibraryCountText(),
          '远程库规则',
          `Suwayomi ${this.getRuleCountByProvider(SubscriptionProviderType.SUWAYOMI)} · Komga ${this.getRuleCountByProvider(SubscriptionProviderType.KOMGA)}`,
          ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          `${this.getRecentExecutionCount(24)}`,
          '24h 执行',
          '最近 24 小时内写入的检查记录',
          ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
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
  private buildSingleStatItem(valueText: string, labelText: string, detailText: string, accentColor: ResourceColor) {
    Column({ space: 8 }) {
      Text(labelText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(valueText)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(accentColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(detailText)
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('48%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(18)
    .margin({ bottom: 8 })
  }

  @Builder
  private buildScopeChip(titleText: string, accentColor: ResourceColor) {
    Text(titleText)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(accentColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(accentColor + '14')
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private buildHintMetricCard(titleText: string, descriptionText: string, accentColor: ResourceColor) {
    Column({ space: 8 }) {
      Text(titleText)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Text(descriptionText)
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Blank()
      }
      .width(32)
      .height(4)
      .backgroundColor(accentColor)
      .borderRadius(2)
    }
    .width('48%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(18)
    .margin({ bottom: 8 })
  }

  @Builder
  private buildRuleMetaCard(titleText: string, valueText: string, accentColor: ResourceColor) {
    Column({ space: 6 }) {
      Text(titleText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      Text(valueText.length > 0 ? valueText : '未配置')
        .fontSize(13)
        .lineHeight(19)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Blank()
      }
      .width(32)
      .height(4)
      .backgroundColor(accentColor + '80')
      .borderRadius(2)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }

  @Builder
  private buildInlineMetric(titleText: string, valueText: string) {
    Column({ space: 4 }) {
      Text(titleText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      Text(valueText)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHintCard() {
    Column({ space: 14 }) {
      Text('能力边界与推荐用法')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Text('这里管理的是应用内任意在线内容的跟踪规则，不是 RSS 订阅源。书架与远程库更适合批量编排，作品级规则建议直接从统一详情页进入。')
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildHintMetricCard(
          '作品详情页入口',
          '适合为单个小说、Suwayomi 作品、Komga 作品建立精细化跟踪规则。',
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        )
        this.buildHintMetricCard(
          '书架级聚合跟踪',
          '面向普通书架和动态书架，可统一做条件检查、通知与自动下载。',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildHintMetricCard(
          '远程库级规则',
          '适合 Suwayomi / Komga 的全库巡检，建议先预览目标覆盖范围。',
          ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
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
  }

  @Builder
  private buildRuleListItem(rule: SubscriptionRule, index: number) {
    Column({ space: 14 }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
        this.buildScopeChip(this.getTargetTypeText(rule), this.getRuleAccentColor(rule))
        this.buildScopeChip(this.getProviderText(rule), ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        this.buildScopeChip(this.getContentTypeText(rule), ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
      }
      .width('100%')

      Row() {
        Column({ space: 4 }) {
          Text(rule.name)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .maxLines(2)
          Text(`${this.getTargetTypeText(rule)} · ${rule.targetTitle}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.getRuleStatusBadgeTextByRule(rule))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getRuleStatusBadgeColorByRule(rule))
          .backgroundColor(this.getRuleStatusBadgeColorByRule(rule) + '14')
          .borderRadius(999)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      }
      .width('100%')

      Text(`规则 #${index + 1} · ${rule.enabled ? '自动参与到期检查' : '当前已暂停自动执行'}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 10 }) {
        this.buildRuleMetaCard('检查条件', this.getConditionSummary(rule), this.getRuleAccentColor(rule))
        this.buildRuleMetaCard('更新动作', this.getActionSummary(rule), ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
      .width('100%')

      Column({ space: 10 }) {
        Row() {
          Column({ space: 4 }) {
            Text('最近一次执行摘要')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
            Text(this.getRuleExecutionSummaryByRule(rule))
              .fontSize(12)
              .lineHeight(18)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.hasRuleExecutionRecord(rule)) {
            Text(this.getRuleExecutionStatusTextByRule(rule))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
              .backgroundColor(this.getRuleExecutionStatusColorByRule(rule))
              .borderRadius(999)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          }
        }
        .width('100%')

        Row({ space: 12 }) {
          this.buildInlineMetric('上次检查', this.formatTimestamp(rule.lastCheckTime))
          this.buildInlineMetric('上次成功', this.formatTimestamp(rule.lastSuccessTime))
          this.buildInlineMetric('规则目标', rule.targetTitle)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(16)

      Column({ space: 10 }) {
        Text('快速操作')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              '编辑规则',
              $r('sys.symbol.gearshape'),
              SubscriptionPageButtonTone.PRIMARY,
              !this.isBusy,
              () => {
                this.openEditDialog(rule);
              }
            )
          }
          .layoutWeight(1)

          Column() {
            this.buildActionButton(
              this.runningRuleId === rule.id ? '执行中...' : '立即执行',
              $r('sys.symbol.arrow_clockwise'),
              SubscriptionPageButtonTone.SECONDARY,
              this.runningRuleId.length <= 0,
              () => {
                void this.runRuleNow(rule);
              }
            )
          }
          .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              '预览目标',
              $r('sys.symbol.eye'),
              SubscriptionPageButtonTone.SECONDARY,
              !this.isPreviewLoading,
              () => {
                void this.previewRule(rule);
              }
            )
          }
          .layoutWeight(1)

          Column() {
            this.buildActionButton(
              rule.enabled ? '暂停规则' : '启用规则',
              rule.enabled ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
              SubscriptionPageButtonTone.SECONDARY,
              !this.isBusy,
              () => {
                void this.toggleRuleEnabled(rule);
              }
            )
          }
          .layoutWeight(1)
        }
        .width('100%')

        this.buildActionButton(
          '删除规则',
          $r('sys.symbol.trash'),
          SubscriptionPageButtonTone.DANGER,
          !this.isBusy,
          () => {
            this.requestDeleteRule(rule);
          }
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
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
  private buildActionButton(
    label: string,
    symbol: Resource,
    tone: SubscriptionPageButtonTone,
    enabled: boolean,
    onClick: () => void
  ) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph(symbol)
          .fontSize(13)
          .fontColor([enabled
            ? this.getPageActionTextColor(tone)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(enabled
            ? this.getPageActionTextColor(tone)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.getPageActionBackgroundColor(tone))
      .borderRadius(20)
      .border({
        width: tone === SubscriptionPageButtonTone.SECONDARY ? 1 : 0,
        color: this.getPageActionBorderColor(tone)
      })
      .opacity(enabled ? 1 : 0.55)
      .onClick(() => {
        if (!enabled) {
          return;
        }
        onClick();
      })
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('还没有内容跟踪规则')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .justifyContent(FlexAlign.Center)

      Text('从这里开始为书架、Suwayomi 远程库、Komga 远程库建立统一的更新跟踪。作品级跟踪也可以直接在统一详情页里创建。')
        .fontSize(13)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
        this.buildScopeChip('书架', ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        this.buildScopeChip('Suwayomi', ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        this.buildScopeChip('Komga', ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        this.buildScopeChip('详情页单作品', ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Button() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
          Text('创建第一条规则')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: 20, right: 20 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(20)
      .onClick(() => {
        this.openCreateDialog();
      })
    }
    .width('100%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
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
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildCreateModeButton(mode: SubscriptionCreateMode, title: string) {
    Button() {
      Column({ space: 8 }) {
        SymbolGlyph(this.getCreateModeSymbol(mode))
          .fontSize(18)
          .fontColor([this.isCreateModeSelected(mode) ? '#FFFFFF' : this.getCreateModeAccentColor(mode)])
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isCreateModeSelected(mode) ? '#FFFFFF' : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(this.getCreateModeDescription(mode))
          .fontSize(10)
          .lineHeight(16)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isCreateModeSelected(mode) ? '#FFFFFFDD' : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
      .padding(12)
      .constraintSize({ minWidth: 140, maxWidth: '48%' })
      .backgroundColor(this.isCreateModeSelected(mode)
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(18)
      .border({
        width: 1,
        color: this.isCreateModeSelected(mode)
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .onClick(() => {
        this.createMode = mode;
      })
  }

  @Builder
  private buildCreateDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      dialogWidth: '92%',
      maxWidth: 680,
      maxHeight: '88%',
      contentPadding: 18,
      dialogRadius: 22,
      contentScrollable: true,
      useMaskBlur: true,
      onMaskTap: () => {
        this.closeCreateDialog();
      }
    }) {
      Column({ space: 14 }) {
        Text(this.getCreateDialogTitleText())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Column({ space: 8 }) {
          Text(this.getCreateDialogDescriptionText())
            .fontSize(12)
            .lineHeight(18)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          Text(this.getCreateModeDescription(this.createMode))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .width('100%')
        }
        .padding(14)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(16)

        if (!this.isEditingCreateDialog()) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
            this.buildCreateModeButton(SubscriptionCreateMode.SHELF, '书架规则')
            this.buildCreateModeButton(SubscriptionCreateMode.SUWAYOMI_LIBRARY, 'Suwayomi')
            this.buildCreateModeButton(SubscriptionCreateMode.KOMGA_LIBRARY, 'Komga')
          }
          .width('100%')
        } else {
          Column({ space: 6 }) {
            Text('当前目标')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            Text(this.getEditingRuleTargetTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')
            Text(this.getEditingRuleMetaText())
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(16)
        }

        Column({ space: 6 }) {
          Text('规则名称')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '可留空使用默认名称', text: $$this.createRuleName })
            .width('100%')
            .height(44)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        if (!this.isEditingCreateDialog() && this.createMode === SubscriptionCreateMode.SHELF) {
          Column({ space: 10 }) {
            Text('选择目标书架')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            Column({ space: 8 }) {
              ForEach(this.shelves, (shelf: TypeShelf) => {
                Button() {
                  Row() {
                    Column({ space: 4 }) {
                      Text(shelf.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(this.createSelectedShelfId === shelf.id
                          ? '#FFFFFF'
                          : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .width('100%')
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .maxLines(1)
                      Text(shelf.shelfType === ShelfType.DYNAMIC ? '动态书架' : '普通书架')
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(this.createSelectedShelfId === shelf.id
                          ? '#FFFFFFCC'
                          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (this.createSelectedShelfId === shelf.id) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(18)
                        .fontColor(['#FFFFFF'])
                    }
                  }
                  .width('100%')
                }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.createSelectedShelfId === shelf.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    this.createSelectedShelfId = shelf.id;
                  })
              }, (shelf: TypeShelf): string => shelf.id)
            }
            .width('100%')
          }
          .width('100%')
        }

        if (!this.isEditingCreateDialog() && this.createMode === SubscriptionCreateMode.KOMGA_LIBRARY) {
          Column({ space: 10 }) {
            Text('可选：限定 Komga 实例')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            TextInput({ placeholder: '实例 ID，留空表示所有 Komga 实例', text: $$this.createKomgaInstanceId })
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(12)
            TextInput({ placeholder: '实例名称，仅用于展示标题', text: $$this.createKomgaInstanceName })
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(12)
          }
          .width('100%')
        }

        Column({ space: 6 }) {
          Text('检查间隔（分钟）')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '检查间隔（分钟）', text: $$this.createCheckIntervalText })
            .width('100%')
            .height(44)
            .type(InputType.Number)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('最少新增内容数')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '最少新增内容数', text: $$this.createMinNewItemsText })
            .width('100%')
            .height(44)
            .type(InputType.Number)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        Column({ space: 10 }) {
          Text('高级条件')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text('这些条件会在实际执行前先筛选目标内容，特别适合书架级和远程库级规则。你可以选择“全部命中”或“任一命中”；单个关键词字段内部仍支持逗号分隔多个词，命中任意一个即通过。')
            .fontSize(11)
            .lineHeight(17)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          this.buildConditionMatchModeSelector(this.createConditionMatchMode, (mode: SubscriptionConditionMatchMode) => {
            this.createConditionMatchMode = mode;
          })
          Column({ space: 6 }) {
            Text('标题关键词')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            TextInput({ placeholder: '例如：番外，单行本，合集', text: $$this.createTitleKeywordText })
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
              .borderRadius(12)
          }
          .width('100%')
          Column({ space: 6 }) {
            Text('标签关键词')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            TextInput({ placeholder: '例如：校园，悬疑，恋爱', text: $$this.createTagKeywordText })
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
              .borderRadius(12)
          }
          .width('100%')
          Column({ space: 6 }) {
            Text('来源关键词')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            TextInput({ placeholder: '例如：Suwayomi，Komga，某书源名', text: $$this.createSourceKeywordText })
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
              .borderRadius(12)
          }
          .width('100%')
          this.buildToggleRow('排除 NSFW 内容', '当目标内容带有 NSFW 标记时跳过，不执行更新检查与自动动作。', this.createExcludeNSFW, (value: boolean) => {
            this.createExcludeNSFW = value;
          })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(16)

        Column({ space: 6 }) {
          Text('自动下载数量（0 表示关闭）')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '自动下载数量（0 表示关闭）', text: $$this.createAutoDownloadCountText })
            .width('100%')
            .height(44)
            .type(InputType.Number)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        this.buildToggleRow('启用通知', '检测到更新时发送聚合通知', this.createEnableNotify, (value: boolean) => {
          this.createEnableNotify = value;
        })

        this.buildToggleRow('仅收藏目标', '成员作品未收藏时跳过执行', this.createRequireFavorite, (value: boolean) => {
          this.createRequireFavorite = value;
        })

        Row({ space: 12 }) {
          Button('取消')
            .height(38)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(19)
            .layoutWeight(1)
            .onClick(() => {
              this.closeCreateDialog();
            })
          Button(this.getCreateDialogPrimaryButtonText())
            .height(38)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(19)
            .layoutWeight(1)
            .onClick(() => {
              void this.confirmCreateRule();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildToggleRow(titleText: string, subtitleText: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(titleText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitleText)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }

  @Builder
  private buildConditionMatchModeSelector(
    selectedMode: SubscriptionConditionMatchMode,
    onSelect: (mode: SubscriptionConditionMatchMode) => void
  ) {
    Column({ space: 8 }) {
      Text('条件命中方式')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        this.buildConditionMatchModeOption(
          SubscriptionConditionMatchMode.ALL,
          '全部命中',
          '所有已启用条件都满足时才执行',
          selectedMode,
          onSelect
        )
        this.buildConditionMatchModeOption(
          SubscriptionConditionMatchMode.ANY,
          '任一命中',
          '命中其中任意一个条件即可执行',
          selectedMode,
          onSelect
        )
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildConditionMatchModeOption(
    optionMode: SubscriptionConditionMatchMode,
    titleText: string,
    subtitleText: string,
    selectedMode: SubscriptionConditionMatchMode,
    onSelect: (mode: SubscriptionConditionMatchMode) => void
  ) {
    Button() {
      Column({ space: 4 }) {
        Text(titleText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(optionMode === selectedMode
            ? '#FFFFFF'
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitleText)
          .fontSize(10)
          .lineHeight(15)
          .fontFamily(this.appFontFamily)
          .fontColor(optionMode === selectedMode
            ? '#FFFFFFCC'
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(optionMode === selectedMode
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(14)
    .onClick(() => {
      onSelect(optionMode);
    })
  }

  @Builder
  private buildDeleteDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      dialogWidth: '90%',
      maxWidth: 520,
      contentPadding: 18,
      dialogRadius: 20,
      onMaskTap: () => {
        this.closeDeleteDialog();
      }
    }) {
      Column({ space: 14 }) {
        Text('删除内容跟踪规则')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .textAlign(TextAlign.Start)

        Column({ space: 8 }) {
          Text(this.getDeletingRulePromptText())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text('相关执行记录会保留，但规则本身以及已记录的基线会被移除。后续如果重新创建，会以新的基线重新开始。')
            .fontSize(12)
            .lineHeight(18)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }
        .padding(14)
        .backgroundColor('#C6282810')
        .borderRadius(16)

        Row({ space: 12 }) {
          Button('取消')
            .height(38)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(19)
            .layoutWeight(1)
            .onClick(() => {
              this.closeDeleteDialog();
            })
          Button('删除')
            .height(38)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor('#C62828')
            .borderRadius(19)
            .layoutWeight(1)
            .onClick(() => {
              void this.confirmDeleteRule();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildPreviewDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      dialogWidth: '92%',
      maxWidth: 700,
      maxHeight: '88%',
      contentPadding: 18,
      dialogRadius: 22,
      contentScrollable: true,
      onMaskTap: () => {
        this.closePreviewDialog();
      }
    }) {
      Column({ space: 14 }) {
        Text(this.previewRuleName.length > 0 ? `目标预览 - ${this.previewRuleName}` : '目标预览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.isPreviewLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(32)
              .height(32)
            Text('正在分析规则目标...')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.previewTarget === null) {
          Text('暂无可展示的目标预览结果')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        } else {
          this.buildPreviewSummaryCard(this.previewTarget)
          this.buildPreviewBreakdownCard('内容类型分布', this.previewTarget.contentTypeBreakdown, false)
          this.buildPreviewBreakdownCard('来源分布', this.previewTarget.providerTypeBreakdown, true)
          this.buildPreviewCandidateSection()
        }

        Button('关闭')
          .width('100%')
          .height(38)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(19)
          .onClick(() => {
            this.closePreviewDialog();
          })
      }
      .width('100%')
    }
  }

  @Builder
  private buildPreviewSummaryCard(preview: SubscriptionTargetPreview) {
    Column({ space: 12 }) {
      Text(`${preview.targetTitle} · ${preview.totalCandidateCount} 项`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 10 }) {
        this.buildRuleMetaCard(
          '可执行',
          `${preview.supportedCandidateCount} 项`,
          ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
        )
        this.buildRuleMetaCard(
          '暂不支持',
          `${preview.unsupportedCandidateCount} 项`,
          ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
        )
      }
      .width('100%')
      if (preview.filteredCandidateCount > 0 || preview.matchedCandidateCount > 0) {
        Row({ space: 10 }) {
          this.buildRuleMetaCard(
            '命中规则',
            `${preview.matchedCandidateCount} 项`,
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          )
          this.buildRuleMetaCard(
            '条件排除',
            `${preview.filteredCandidateCount} 项`,
            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          )
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }

  @Builder
  private buildPreviewBreakdownCard(
    titleText: string,
    counters: SubscriptionTargetPreviewCounter[],
    isProviderBreakdown: boolean
  ) {
    Column({ space: 8 }) {
      Text(titleText)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(counters, (counter: SubscriptionTargetPreviewCounter) => {
          Text(`${this.getPreviewCounterLabel(counter.key, isProviderBreakdown)} · ${counter.count}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '12')
            .borderRadius(999)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ right: 8, bottom: 8 })
        }, (counter: SubscriptionTargetPreviewCounter): string => counter.key)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }

  @Builder
  private buildPreviewCandidateSection() {
    Column({ space: 8 }) {
      Text(`目标成员预览（最多显示 ${this.getPreviewCandidateCount()} 项）`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Column({ space: 8 }) {
        ForEach(this.getPreviewCandidates(), (candidate: SubscriptionTargetPreviewCandidate, index: number) => {
          Column({ space: 6 }) {
            Row() {
              Text(candidate.title)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(!candidate.supported ? '未接入' : (candidate.conditionMatched ? '命中规则' : '条件排除'))
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor('#FFFFFF')
                .backgroundColor(!candidate.supported
                  ? '#8E24AA'
                  : (candidate.conditionMatched
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)))
                .borderRadius(999)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            }
            .width('100%')

            Text(this.getPreviewCandidateMetaText(candidate))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (!candidate.supported && candidate.unsupportedReason.length > 0) {
              Text(candidate.unsupportedReason)
                .fontSize(10)
                .lineHeight(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            } else if (candidate.supported && !candidate.conditionMatched && candidate.conditionReason.length > 0) {
              Text(candidate.conditionReason)
                .fontSize(10)
                .lineHeight(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            if (candidate.latestItemTitle.length > 0) {
              Text(`最近条目 · ${candidate.latestItemTitle}`)
                .fontSize(10)
                .lineHeight(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .padding(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(14)
        }, (candidate: SubscriptionTargetPreviewCandidate, index: number): string => `${candidate.itemId}_${index}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildRulesSection() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 4 }) {
          Text('规则列表')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text('所有内容跟踪规则会在这里按卡片展示，支持直接查看状态、调整规则和执行操作。')
            .fontSize(11)
            .lineHeight(17)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(`${this.rules.length} 条`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '14')
          .borderRadius(999)
      }
      .width('100%')

      if (this.isLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载内容跟踪规则...')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding({ top: 28, bottom: 28 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(18)
        .alignItems(HorizontalAlign.Center)
      } else if (this.rules.length <= 0) {
        this.buildEmptyState()
      } else {
        Column({ space: 12 }) {
          ForEach(this.rules, (rule: SubscriptionRule, index: number) => {
            this.buildRuleListItem(rule, index)
          }, (rule: SubscriptionRule): string => rule.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(24)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
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

        Scroll() {
          Column() {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              this.buildPageSectionHeader('总览', '统一内容追踪的规则覆盖、启用情况和最近执行状态。')
              this.buildStatsCard()
              this.buildPageSectionHeader('能力边界', '书架、远程库和详情页单作品都会汇聚到这里统一编排。')
              this.buildHintCard()
              this.buildPageSectionHeader('规则中心', '在这里直接查看、执行、编辑和清理所有内容跟踪规则。')
              this.buildRulesSection()
              Blank().height(this.navigationBarHeight + 20)
            }
            .width('100%')
            .constraintSize({ maxWidth: TRACKING_PAGE_MAX_WIDTH })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.showCreateDialog) {
          this.buildCreateDialog()
        }
        if (this.showDeleteDialog) {
          this.buildDeleteDialog()
        }
        if (this.showPreviewDialog) {
          this.buildPreviewDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '统一内容跟踪',
          appFontFamily: this.appFontFamily,
          maxDirectActions: 3,
          actions: this.getActionItems()
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
