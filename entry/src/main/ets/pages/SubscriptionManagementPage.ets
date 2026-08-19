import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction, UIContext, curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SettingsManager } from '../Framework/Managers/SettingsManager';
import { getTypeShelfManager, ShelfType, TypeShelf, TypeShelfManager } from '../Framework/Data/TypeShelfManager';
import {
  getSubscriptionInitializer,
  getSubscriptionManager,
  convertSubscriptionIntervalDisplayToMinutes,
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
  SubscriptionIntervalUnit,
  SubscriptionTargetType,
  SubscriptionManager,
  formatSubscriptionIntervalSchedule,
  getSubscriptionIntervalUnitLabel,
  splitSubscriptionIntervalMinutesForDisplay
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

enum SubscriptionCreateDialogStage {
  TARGET = 0,
  SETTINGS = 1
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
  @State createDialogStage: SubscriptionCreateDialogStage = SubscriptionCreateDialogStage.TARGET;
  @State createDialogActiveTab: number = 0;
  @State editingRuleId: string = '';
  @State createMode: SubscriptionCreateMode = SubscriptionCreateMode.SHELF;
  @State createRuleName: string = '';
  @State createSelectedShelfId: string = '';
  @State createCheckIntervalText: string = '3';
  @State createCheckIntervalUnit: SubscriptionIntervalUnit = SubscriptionIntervalUnit.HOUR;
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
  @State createDialogOpacity: number = 0;
  @State createDialogScale: number = 0.96;
  @State createDialogTranslateY: number = 28;
  @State createDialogStageContentOpacity: number = 1;
  @State createDialogStageContentTranslateX: number = 0;
  @State showDeleteDialog: boolean = false;
  @State deleteDialogOpacity: number = 0;
  @State deleteDialogScale: number = 0.96;
  @State deleteDialogTranslateY: number = 12;
  @State deletingRuleId: string = '';
  @State showPreviewDialog: boolean = false;
  @State previewDialogOpacity: number = 0;
  @State previewDialogScale: number = 0.96;
  @State previewDialogTranslateY: number = 12;
  @State isPreviewLoading: boolean = false;
  @State previewRuleName: string = '';
  @State previewTarget: SubscriptionTargetPreview | null = null;

  private readonly lifecycle: PageLifecycleManager = new PageLifecycleManager('SubscriptionManagementPage', { enableDebug: true });
  private readonly createDialogScroller: Scroller = new Scroller();
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly typeShelfManager: TypeShelfManager = getTypeShelfManager();
  private readonly manager: SubscriptionManager = getSubscriptionManager();
  private uiContext: UIContext | undefined = undefined;
  private createDialogAnimationToken: number = 0;
  private createDialogStageAnimationToken: number = 0;

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
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
    this.uiContext = undefined;
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
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await getSubscriptionInitializer().initialize(context);
      await this.loadData();
      logger.info(TAG, `统一内容跟踪管理页初始化完成: 规则=${this.rules.length}`);
    } catch (error) {
      logger.error(TAG, `统一内容跟踪管理页初始化失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `打开提醒管理失败: ${String(error)}` });
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

  private showCreateDialogWithAnimation(): void {
    const animationToken = this.createDialogAnimationToken + 1;
    this.createDialogAnimationToken = animationToken;
    this.createDialogOpacity = 0;
    this.createDialogScale = 0.96;
    this.createDialogTranslateY = 12;
    this.createDialogStageContentOpacity = 1;
    this.createDialogStageContentTranslateX = 0;
    this.showCreateDialog = true;
    const startAnimation = (): void => {
      if (animationToken !== this.createDialogAnimationToken || !this.showCreateDialog) {
        return;
      }
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 260,
          curve: Curve.EaseOut
        }, () => {
          this.createDialogOpacity = 1;
          this.createDialogScale = 1;
          this.createDialogTranslateY = 0;
        });
        return;
      }
      this.createDialogOpacity = 1;
      this.createDialogScale = 1;
      this.createDialogTranslateY = 0;
    };
    setTimeout(startAnimation, 0);
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
      return '还没检查过';
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
      return '没有更新';
    }
    if (status === SubscriptionExecutionStatus.SKIPPED) {
      return '已跳过';
    }
    if (status === SubscriptionExecutionStatus.FAILED) {
      return '检查失败';
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
    const parts: string[] = [formatSubscriptionIntervalSchedule(rule.checkIntervalMin)];
    const minNewItems = this.getMinNewItems(rule.conditions);
    parts.push(`至少新增 ${minNewItems}`);
    const matchModeSummary = this.getConditionMatchModeSummary(rule.conditions);
    if (matchModeSummary.length > 0) {
      parts.push(matchModeSummary);
    }
    if (this.requiresFavorite(rule.conditions)) {
      parts.push('只检查已收藏的内容');
    }
    if (this.excludesNSFW(rule.conditions)) {
      parts.push('跳过 NSFW');
    }
    const titleKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TITLE_KEYWORD);
    if (titleKeyword.length > 0) {
      parts.push(`标题包含 ${titleKeyword}`);
    }
    const tagKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.TAG_KEYWORD);
    if (tagKeyword.length > 0) {
      parts.push(`标签包含 ${tagKeyword}`);
    }
    const sourceKeyword = this.getConditionTextByType(rule.conditions, SubscriptionConditionType.SOURCE_KEYWORD);
    if (sourceKeyword.length > 0) {
      parts.push(`来源包含 ${sourceKeyword}`);
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
        parts.push('提醒我');
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW) {
        parts.push(`自动下载 ${action.limitCount > 0 ? action.limitCount : '全部'}`);
      }
    }
    if (parts.length <= 0) {
      return '只检查，不自动处理';
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
      ? '满足任意一项'
      : '需要全部满足';
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
      this.createCheckIntervalText = '3';
      this.createCheckIntervalUnit = SubscriptionIntervalUnit.HOUR;
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
    const intervalDisplay = splitSubscriptionIntervalMinutesForDisplay(rule.checkIntervalMin);
    this.createCheckIntervalText = intervalDisplay.valueText;
    this.createCheckIntervalUnit = intervalDisplay.unit;
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
      this.getUIContext().getPromptAction().showToast({ message: '规则列表已刷新' });
    } catch (error) {
      logger.warn(TAG, `刷新内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `刷新失败: ${String(error)}` });
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
      this.getUIContext().getPromptAction().showToast({ message: this.buildRunDueToast(results.length) });
    } catch (error) {
      logger.error(TAG, `手动执行到期内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `批量检查失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private buildRunDueToast(resultCount: number): string {
    if (resultCount <= 0) {
      return '现在没有需要检查的提醒';
    }
    return `已检查 ${resultCount} 条提醒`;
  }

  private openCreateDialog(): void {
    this.createMode = SubscriptionCreateMode.SHELF;
    this.fillCreateFormFromRule(null);
    this.createDialogStage = SubscriptionCreateDialogStage.TARGET;
    this.createDialogActiveTab = 0;
    this.showCreateDialogWithAnimation();
    this.resetCreateDialogScroll();
  }

  private openEditDialog(rule: SubscriptionRule): void {
    this.fillCreateFormFromRule(rule);
    this.createDialogStage = SubscriptionCreateDialogStage.TARGET;
    this.createDialogActiveTab = 0;
    this.showCreateDialogWithAnimation();
    this.resetCreateDialogScroll();
  }

  private closeCreateDialog(): void {
    const animationToken = this.createDialogAnimationToken + 1;
    this.createDialogAnimationToken = animationToken;
    if (!this.showCreateDialog) {
      this.editingRuleId = '';
      return;
    }
    const finishClose = (): void => {
      if (animationToken !== this.createDialogAnimationToken) {
        return;
      }
      this.showCreateDialog = false;
      this.editingRuleId = '';
    };
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseIn
      }, () => {
        this.createDialogOpacity = 0;
        this.createDialogScale = 0.96;
        this.createDialogTranslateY = 12;
      });
      setTimeout(finishClose, 200);
      return;
    }
    this.createDialogOpacity = 0;
    this.createDialogScale = 0.96;
    this.createDialogTranslateY = 12;
    finishClose();
  }

  private resetCreateDialogScroll(): void {
    const resetAction = () => {
      try {
        this.createDialogScroller.scrollTo({
          xOffset: 0,
          yOffset: 0,
          animation: false
        });
      } catch (_error) {
      }
    };
    setTimeout(resetAction, 0);
    setTimeout(resetAction, 48);
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
      checkIntervalMin: convertSubscriptionIntervalDisplayToMinutes(
        this.createCheckIntervalText,
        this.createCheckIntervalUnit,
        180
      ),
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
        this.getUIContext().getPromptAction().showToast({ message: '提醒规则已更新，之后会在 APP 回到前台时补查' });
        this.isBusy = false;
        return;
      }
      if (this.createMode === SubscriptionCreateMode.SHELF) {
        if (this.createSelectedShelfId.length <= 0) {
          this.getUIContext().getPromptAction().showToast({ message: '请先选择书架' });
          this.isBusy = false;
          return;
        }
        const targetShelf = this.findShelfById(this.createSelectedShelfId);
        if (targetShelf === null) {
          this.getUIContext().getPromptAction().showToast({ message: '所选书架不存在' });
          this.isBusy = false;
          return;
        }
        const targetType = targetShelf.shelfType === ShelfType.DYNAMIC
          ? SubscriptionTargetType.DYNAMIC_SHELF
          : SubscriptionTargetType.SHELF;
        if (this.hasExistingTargetRule(targetType, targetShelf.id, SubscriptionProviderType.NONE)) {
          this.getUIContext().getPromptAction().showToast({ message: '这个书架已经有提醒了' });
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
          this.getUIContext().getPromptAction().showToast({ message: 'Suwayomi 书库已经有提醒了' });
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
          this.getUIContext().getPromptAction().showToast({ message: '这个 Komga 远程库已经有提醒了' });
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
      this.getUIContext().getPromptAction().showToast({ message: '提醒规则已创建，之后会在 APP 回到前台时补查' });
    } catch (error) {
      logger.error(TAG, `创建内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `创建提醒失败: ${String(error)}` });
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
      this.getUIContext().getPromptAction().showToast({ message: !rule.enabled ? '提醒已开启，APP 回到前台时会自动补查' : '提醒已暂停' });
    } catch (error) {
      logger.warn(TAG, `切换规则启用状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `操作失败: ${String(error)}` });
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
      this.getUIContext().getPromptAction().showToast({ message: this.buildRunRuleToast(result) });
    } catch (error) {
      logger.error(TAG, `立即执行内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `执行失败: ${String(error)}` });
    }
    this.runningRuleId = '';
  }

  private buildRunRuleToast(result: SubscriptionRuleRunResult): string {
    if (result.status === SubscriptionExecutionStatus.SUCCESS) {
      return result.deltaCount > 0 ? `发现 ${result.deltaCount} 个新内容` : '检查完成';
    }
    return result.message.length > 0 ? result.message : '检查完成';
  }

  private requestDeleteRule(rule: SubscriptionRule): void {
    this.deletingRuleId = rule.id;
    this.deleteDialogOpacity = 0;
    this.deleteDialogScale = 0.96;
    this.deleteDialogTranslateY = 12;
    this.showDeleteDialog = true;
    setTimeout(() => {
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 260,
          curve: Curve.EaseOut
        }, () => {
          this.deleteDialogOpacity = 1;
          this.deleteDialogScale = 1;
          this.deleteDialogTranslateY = 0;
        });
      }
    }, 0);
  }

  private closeDeleteDialog(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseIn
      }, () => {
        this.deleteDialogOpacity = 0;
        this.deleteDialogScale = 0.96;
        this.deleteDialogTranslateY = 12;
      });
      setTimeout(() => {
        this.showDeleteDialog = false;
        this.deletingRuleId = '';
      }, 200);
      return;
    }
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
      const shouldCloseCreateDialog = rule.id === this.editingRuleId;
      await this.manager.deleteRule(rule.id);
      this.closeDeleteDialog();
      if (shouldCloseCreateDialog) {
        this.closeCreateDialog();
      }
      await this.loadData();
      this.getUIContext().getPromptAction().showToast({ message: '提醒已删除' });
    } catch (error) {
      logger.error(TAG, `删除内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${String(error)}` });
    }
    this.isBusy = false;
  }

  private async previewRule(rule: SubscriptionRule): Promise<void> {
    this.previewRuleName = rule.name;
    this.previewTarget = null;
    this.previewDialogOpacity = 0;
    this.previewDialogScale = 0.96;
    this.previewDialogTranslateY = 12;
    this.showPreviewDialog = true;
    this.isPreviewLoading = true;
    setTimeout(() => {
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 260,
          curve: Curve.EaseOut
        }, () => {
          this.previewDialogOpacity = 1;
          this.previewDialogScale = 1;
          this.previewDialogTranslateY = 0;
        });
      }
    }, 0);
    try {
      this.previewTarget = await this.manager.previewRuleTarget(rule.id);
    } catch (error) {
      logger.warn(TAG, `预览内容跟踪规则目标失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `查看失败: ${String(error)}` });
    }
    this.isPreviewLoading = false;
  }

  private closePreviewDialog(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseIn
      }, () => {
        this.previewDialogOpacity = 0;
        this.previewDialogScale = 0.96;
        this.previewDialogTranslateY = 12;
      });
      setTimeout(() => {
        this.showPreviewDialog = false;
        this.previewTarget = null;
        this.previewRuleName = '';
        this.isPreviewLoading = false;
      }, 200);
      return;
    }
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
      return '已暂停';
    }
    if (execution !== null) {
      return this.getStatusText(execution.status);
    }
    return '还没检查过';
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
      return '已暂停，APP 回到前台时也不会自动补查。';
    }
    return '已开启，之后会在 APP 回到前台时自动补查。';
  }

  private getCreateModeDescription(mode: SubscriptionCreateMode): string {
    if (mode === SubscriptionCreateMode.SHELF) {
      return '检查整个书架';
    }
    if (mode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
      return '检查整个 Suwayomi 书库';
    }
    return '检查整个 Komga 书库';
  }

  private getCreateModeTitle(mode: SubscriptionCreateMode): string {
    if (mode === SubscriptionCreateMode.SHELF) {
      return '书架提醒';
    }
    if (mode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
      return 'Suwayomi 书库';
    }
    return 'Komga 书库';
  }

  private getCreateModeSymbol(mode: SubscriptionCreateMode): Resource {
    return $r('sys.symbol.bookshelf');
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
    return this.isEditingCreateDialog() ? '调整更新提醒' : '新建更新提醒';
  }

  private getCreateDialogDescriptionText(): string {
    return this.isEditingCreateDialog()
      ? '这里可以改检查频率、筛选条件和发现更新后的处理方式。当前版本只会在 APP 回到前台时自动补查。'
      : '这里创建的是应用里的更新提醒，不是 RSS。更适合批量检查书架或远程库；当前版本只会在 APP 回到前台时自动补查。';
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
    return this.isEditingCreateDialog() ? '保存设置' : '创建提醒';
  }

  private isEditingRuleEnabled(): boolean {
    const rule = this.getEditingRule();
    return rule !== null && rule.enabled;
  }

  private isCreateDialogBusy(): boolean {
    return this.isBusy || this.runningRuleId.length > 0;
  }

  private handleEditingRuleToggle(): void {
    const rule = this.getEditingRule();
    if (rule === null) {
      return;
    }
    void this.toggleRuleEnabled(rule);
  }

  private handleEditingRuleRunNow(): void {
    const rule = this.getEditingRule();
    if (rule === null) {
      return;
    }
    void this.runRuleNow(rule);
  }

  private handleEditingRuleDelete(): void {
    const rule = this.getEditingRule();
    if (rule === null) {
      return;
    }
    this.requestDeleteRule(rule);
  }

  private getCreateDialogLastCheckText(): string {
    const rule = this.getEditingRule();
    if (rule === null) {
      return '保存后开始生效';
    }
    const execution = this.getRuleExecution(rule);
    if (execution !== null) {
      return this.formatTimestamp(execution.checkedAt);
    }
    if (rule.lastCheckTime > 0) {
      return this.formatTimestamp(rule.lastCheckTime);
    }
    return '还没检查过';
  }

  private getCreateDialogOverviewInlineText(): string {
    const parts: string[] = [];
    if (this.isEditingCreateDialog()) {
      const targetTitle = this.getEditingRuleTargetTitle().trim();
      if (targetTitle.length > 0) {
        parts.push(targetTitle);
      }

      const rule = this.getEditingRule();
      if (rule !== null) {
        if (!rule.enabled) {
          parts.push('已暂停');
        } else {
          const execution = this.getRuleExecution(rule);
          if (execution !== null) {
            parts.push(this.getStatusText(execution.status));
            if (execution.deltaCount > 0) {
              parts.push(`新增 ${execution.deltaCount}`);
            }
          } else {
            parts.push('已开启');
          }
        }
      }

      const lastCheckText = this.getCreateDialogLastCheckText();
      if (lastCheckText.length > 0) {
        parts.push(`上次 ${lastCheckText}`);
      }
      return this.joinTextParts(parts);
    }

    parts.push(this.getCreateDialogTargetSummaryText());
    parts.push('准备创建');
    parts.push(formatSubscriptionIntervalSchedule(convertSubscriptionIntervalDisplayToMinutes(
      this.createCheckIntervalText,
      this.createCheckIntervalUnit,
      180
    )));
    return this.joinTextParts(parts);
  }

  private getCreateDialogTargetSectionHintText(): string {
    if (this.isEditingCreateDialog()) {
      return '这条提醒已经绑定好对象了，这里只做展示；如果想换对象，直接新建一条会更清楚。';
    }
    if (this.createMode === SubscriptionCreateMode.SHELF) {
      return '先选一个书架，这条提醒会跟着整个书架一起检查更新。';
    }
    if (this.createMode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
      return '会直接检查当前接入的整个 Suwayomi 书库，不需要再额外选择书架。';
    }
    return '可以指定某个 Komga 实例，也可以留空一起检查全部实例。';
  }

  private getCreateSelectedShelfTitle(): string {
    if (this.shelves.length <= 0) {
      return '还没有可选书架';
    }
    const selectedShelf = this.findShelfById(this.createSelectedShelfId);
    if (selectedShelf === null) {
      return '请选择一个书架';
    }
    return selectedShelf.name;
  }

  private getCreateSelectedShelfMetaText(): string {
    if (this.shelves.length <= 0) {
      return '先去书架页创建一个书架，再回来新建提醒。';
    }
    const selectedShelf = this.findShelfById(this.createSelectedShelfId);
    if (selectedShelf === null) {
      return '选中后会跟着整个书架一起检查和处理更新。';
    }
    return selectedShelf.shelfType === ShelfType.DYNAMIC
      ? '动态书架 · 会按这组筛选结果统一补查'
      : '普通书架 · 会按书架里的内容统一补查';
  }

  private getCreateKomgaTargetSummaryText(): string {
    const instanceName = this.createKomgaInstanceName.trim();
    if (instanceName.length > 0) {
      return `Komga - ${instanceName}`;
    }
    const instanceId = this.createKomgaInstanceId.trim();
    if (instanceId.length > 0) {
      return `Komga - ${instanceId}`;
    }
    return 'Komga 全部实例';
  }

  private getCreateDialogTargetSummaryText(): string {
    if (this.isEditingCreateDialog()) {
      const targetTitle = this.getEditingRuleTargetTitle().trim();
      return targetTitle.length > 0 ? targetTitle : this.getCreateModeTitle(this.createMode);
    }
    if (this.createMode === SubscriptionCreateMode.SHELF) {
      return this.getCreateSelectedShelfTitle();
    }
    if (this.createMode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
      return 'Suwayomi 书库';
    }
    return this.getCreateKomgaTargetSummaryText();
  }

  private canProceedFromCreateTargetStage(): boolean {
    if (this.isEditingCreateDialog()) {
      return true;
    }
    if (this.createMode === SubscriptionCreateMode.SHELF) {
      if (this.createSelectedShelfId.length <= 0) {
        return false;
      }
      return this.findShelfById(this.createSelectedShelfId) !== null;
    }
    return true;
  }

  private showCreateTargetStageBlockedToast(): void {
    if (this.createMode === SubscriptionCreateMode.SHELF) {
      this.getUIContext().getPromptAction().showToast({ message: this.shelves.length > 0 ? '请先选择书架' : '当前还没有可用书架' });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '请先完成当前步骤' });
  }

  private switchCreateDialogStage(stage: SubscriptionCreateDialogStage): void {
    if (this.createDialogStage === stage) {
      return;
    }
    const currentStage = this.createDialogStage;
    const isForward = stage > currentStage;
    const hideOffset = isForward ? -32 : 32;
    const showOffset = isForward ? 32 : -32;
    const animationToken = this.createDialogStageAnimationToken + 1;
    this.createDialogStageAnimationToken = animationToken;

    const animateIn = (): void => {
      if (animationToken !== this.createDialogStageAnimationToken) {
        return;
      }
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 220,
          curve: Curve.EaseOut
        }, () => {
          this.createDialogStageContentOpacity = 1;
          this.createDialogStageContentTranslateX = 0;
        });
        return;
      }
      this.createDialogStageContentOpacity = 1;
      this.createDialogStageContentTranslateX = 0;
    };

    const applyStage = (): void => {
      if (animationToken !== this.createDialogStageAnimationToken) {
        return;
      }
      this.createDialogStage = stage;
      this.resetCreateDialogScroll();
      this.createDialogStageContentOpacity = 0;
      this.createDialogStageContentTranslateX = showOffset;
      setTimeout(animateIn, 0);
    };

    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 150,
        curve: Curve.EaseIn
      }, () => {
        this.createDialogStageContentOpacity = 0;
        this.createDialogStageContentTranslateX = hideOffset;
      });
      setTimeout(applyStage, 160);
      return;
    }
    applyStage();
  }

  private openCreateDialogSettingsStage(): void {
    if (!this.canProceedFromCreateTargetStage()) {
      this.showCreateTargetStageBlockedToast();
      return;
    }
    this.switchCreateDialogStage(SubscriptionCreateDialogStage.SETTINGS);
  }

  private getCreateDialogFooterHintText(): string {
    if (this.createDialogStage === SubscriptionCreateDialogStage.TARGET) {
      if (this.isEditingCreateDialog()) {
        return '先确认当前跟踪对象，下一步再调整这条提醒的详细规则。';
      }
      if (this.createMode === SubscriptionCreateMode.SHELF) {
        return '先选好书架，再继续设置检查频率和后续动作。';
      }
      if (this.createMode === SubscriptionCreateMode.SUWAYOMI_LIBRARY) {
        return '这条提醒会跟踪整个 Suwayomi 书库，下一步再补充规则。';
      }
      return '可以先决定 Komga 检查范围，下一步再补充规则。';
    }
    if (this.createDialogActiveTab === 0) {
      return '名称和检查频率会一起决定这条提醒怎么跑；自动检查目前只会在 APP 回到前台时补查。';
    }
    if (this.createDialogActiveTab === 1) {
      return '这些筛选条件会决定哪些内容才会被算作更新。';
    }
    if (this.isEditingCreateDialog() && !this.isEditingRuleEnabled()) {
      return '提醒当前已暂停，重新开启后也只会在 APP 回到前台时自动补查。';
    }
    return '这里决定有更新时要提醒你，还是顺手自动下载。';
  }

  private getDeletingRulePromptText(): string {
    const deletingRule = this.getDeletingRule();
    return deletingRule !== null ? `确定删除「${deletingRule.name}」吗？` : '确定删除这条提醒吗？';
  }

  private getPreviewCandidateCount(): number {
    return this.getPreviewCandidates().length;
  }

  private getActionItems(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'create',
        label: '新建',
        symbol: $r('sys.symbol.plus'),
        enabled: !this.isBusy,
        onClick: () => {
          this.openCreateDialog();
        }
      },
      {
        id: 'run_due',
        label: '批量检查',
        symbol: $r('sys.symbol.play_fill'),
        enabled: !this.isBusy && this.runningRuleId.length <= 0,
        onClick: () => {
          void this.runDueRules();
        }
      },
      {
        id: 'refresh',
        label: '刷新',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isBusy && this.runningRuleId.length <= 0,
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
          Text('更新提醒')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('在这里统一管理作品、书架和远程库的更新提醒，也能顺手设置自动下载。')
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
        this.buildScopeChip('详情页单本', ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        this.buildScopeChip('书架 / 动态书架', ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        this.buildScopeChip('Suwayomi', ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        this.buildScopeChip('Komga', ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildSingleStatItem(
          this.getStatsTotalCountText(),
          '提醒总数',
          '当前页面里的全部提醒规则',
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          this.getStatsShelfCountText(),
          '书架提醒',
          '适用于普通书架和动态书架',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          this.getStatsProviderLibraryCountText(),
          '远程库提醒',
          `Suwayomi ${this.getRuleCountByProvider(SubscriptionProviderType.SUWAYOMI)} · Komga ${this.getRuleCountByProvider(SubscriptionProviderType.KOMGA)}`,
          ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
        )
        this.buildSingleStatItem(
          `${this.getRecentExecutionCount(24)}`,
          '24h 检查',
          '最近 24 小时内的检查记录',
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
      Text('使用建议')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Text('这里管理的是应用里的更新提醒，不是 RSS。单本内容更适合在详情页里开启，书架和远程库更适合批量检查。当前版本只会在 APP 回到前台时补查，后台不会定时检查。')
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildHintMetricCard(
          '详情页单本',
          '适合给单本小说、Suwayomi 作品或 Komga 作品单独开提醒。',
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        )
        this.buildHintMetricCard(
          '书架提醒',
          '适合普通书架和动态书架，可以一起检查、提醒和自动下载。',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildHintMetricCard(
          '远程库提醒',
          '适合 Suwayomi / Komga 整库检查，建议先看看会包含哪些内容。',
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

      Text(`规则 #${index + 1} · ${rule.enabled ? 'APP 回到前台时会自动补查' : '当前已暂停自动检查'}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 10 }) {
        this.buildRuleMetaCard('怎么检查', this.getConditionSummary(rule), this.getRuleAccentColor(rule))
        this.buildRuleMetaCard('发现更新后', this.getActionSummary(rule), ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
      .width('100%')

      Column({ space: 10 }) {
        Row() {
          Column({ space: 4 }) {
            Text('上次检查结果')
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
          this.buildInlineMetric('检查对象', rule.targetTitle)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(16)

      Column({ space: 10 }) {
        Text('快捷操作')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              '调整规则',
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
              this.runningRuleId === rule.id ? '检查中...' : '现在检查',
              $r('sys.symbol.checkmark_circle'),
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
              '看看会检查哪些',
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
              rule.enabled ? '暂停提醒' : '恢复提醒',
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
          '删除提醒',
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
        SymbolGlyph($r('sys.symbol.bell'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('还没有更新提醒')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .justifyContent(FlexAlign.Center)

      Text('可以先给书架或远程库开提醒，单本内容也能在详情页里单独开启。当前版本会在 APP 回到前台时补查，后台不会定时执行。')
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
        this.buildScopeChip('详情页单本', ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Button() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
          Text('创建第一条提醒')
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
      Row({ space: 10 }) {
        SymbolGlyph(this.getCreateModeSymbol(mode))
          .fontSize(18)
          .fontColor([this.isCreateModeSelected(mode) ? Color.White : this.getCreateModeAccentColor(mode)])
        Column({ space: 3 }) {
          Text(title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.isCreateModeSelected(mode)
              ? Color.White
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.getCreateModeDescription(mode))
            .fontSize(11)
            .lineHeight(16)
            .fontFamily(this.appFontFamily)
            .fontColor(this.isCreateModeSelected(mode)
              ? '#FFFFFFD8'
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .margin({ bottom: 8 })
      .constraintSize({ minWidth: 140, maxWidth: '48%' })
      .backgroundColor(this.isCreateModeSelected(mode)
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(16)
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
  private buildCreateShelfOptionChip(shelf: TypeShelf) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.bookshelf'))
          .fontSize(14)
          .fontColor([this.createSelectedShelfId === shelf.id
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text(shelf.name)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.createSelectedShelfId === shelf.id
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .margin({ right: 8, bottom: 8 })
    .constraintSize({ minWidth: 120, maxWidth: '48%' })
    .backgroundColor(this.createSelectedShelfId === shelf.id
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(14)
    .border({
      width: 1,
      color: this.createSelectedShelfId === shelf.id
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.createSelectedShelfId = shelf.id;
    })
  }

  @Builder
  private buildCreateDialogTabButton(label: string, icon: Resource, index: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(13)
        .fontColor([this.createDialogActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.createDialogActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.createDialogActiveTab === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(14)
    .scale({
      x: this.createDialogActiveTab === index ? 1 : 0.97,
      y: this.createDialogActiveTab === index ? 1 : 0.97
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.handleCreateDialogTabChange(index);
    })
  }

  private handleCreateDialogTabChange(index: number): void {
    if (this.createDialogActiveTab === index) {
      return;
    }
    this.createDialogActiveTab = index;
    this.resetCreateDialogScroll();
  }

  @Builder
  private buildCreateDialogHintCard(titleText: string, descriptionText: string) {
    Column({ space: 6 }) {
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
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }

  @Builder
  private buildCreateDialogOverviewCard() {
    Column({ space: 6 }) {
      Text(this.getCreateDialogOverviewInlineText())
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('当前版本只会在 APP 回到前台时自动补查，后台不会定时执行。')
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  private buildCreateDialogTextInput(
    labelText: string,
    placeholderText: string,
    textValue: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(labelText)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      TextInput({ placeholder: placeholderText, text: textValue })
        .width('100%')
        .height(42)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((value: string) => {
          onChange(value);
        })
    }
    .width('100%')
  }

  @Builder
  private buildCreateDialogNumberInput(
    labelText: string,
    placeholderText: string,
    textValue: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(labelText)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      TextInput({ placeholder: placeholderText, text: textValue })
        .width('100%')
        .height(42)
        .type(InputType.Number)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((value: string) => {
          onChange(value);
        })
    }
    .width('100%')
  }

  private getCreateIntervalPreviewText(): string {
    const totalMinutes = convertSubscriptionIntervalDisplayToMinutes(
      this.createCheckIntervalText,
      this.createCheckIntervalUnit,
      180
    );
    return `当前会按 ${formatSubscriptionIntervalSchedule(totalMinutes)}，并在 APP 回到前台时补查`;
  }

  @Builder
  private buildCreateIntervalUnitOption(unit: SubscriptionIntervalUnit) {
    Button(getSubscriptionIntervalUnitLabel(unit))
      .layoutWeight(1)
      .height(34)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.appFontFamily)
      .fontColor(this.createCheckIntervalUnit === unit
        ? Color.White
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .backgroundColor(this.createCheckIntervalUnit === unit
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
      .border({
        width: 1,
        color: this.createCheckIntervalUnit === unit
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .onClick(() => {
        this.createCheckIntervalUnit = unit;
      })
  }

  @Builder
  private buildCreateIntervalInput() {
    Column({ space: 8 }) {
      this.buildCreateDialogNumberInput(
        '多久检查一次',
        '例如 3',
        this.createCheckIntervalText,
        (value: string) => {
          this.createCheckIntervalText = value;
        }
      )

      Column({ space: 8 }) {
        Text('时间单位')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
        Row({ space: 8 }) {
          this.buildCreateIntervalUnitOption(SubscriptionIntervalUnit.MINUTE)
          this.buildCreateIntervalUnitOption(SubscriptionIntervalUnit.HOUR)
          this.buildCreateIntervalUnitOption(SubscriptionIntervalUnit.DAY)
          this.buildCreateIntervalUnitOption(SubscriptionIntervalUnit.WEEK)
        }
        .width('100%')
        Text(this.getCreateIntervalPreviewText())
          .fontSize(11)
          .lineHeight(17)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildCreateDialogTargetTab() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.bell'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('提醒对象')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text(this.getCreateDialogTargetSectionHintText())
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      if (!this.isEditingCreateDialog()) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
          this.buildCreateModeButton(SubscriptionCreateMode.SHELF, '书架提醒')
          this.buildCreateModeButton(SubscriptionCreateMode.SUWAYOMI_LIBRARY, 'Suwayomi')
          this.buildCreateModeButton(SubscriptionCreateMode.KOMGA_LIBRARY, 'Komga')
        }
        .width('100%')
      }

      Column({ space: 12 }) {
        if (this.isEditingCreateDialog()) {
          Column({ space: 6 }) {
            Text(this.getEditingRuleTargetTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.getEditingRuleMetaText())
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('对象已经固定，如需换对象，直接新建一条提醒会更稳妥。')
              .fontSize(11)
              .lineHeight(17)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
          }
          .width('100%')
        } else if (this.createMode === SubscriptionCreateMode.SHELF) {
          Column({ space: 10 }) {
            Column({ space: 4 }) {
              Text(this.getCreateSelectedShelfTitle())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.getCreateSelectedShelfMetaText())
                .fontSize(11)
                .lineHeight(17)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')
            }
            .width('100%')

            if (this.shelves.length > 0) {
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
                ForEach(this.shelves, (shelf: TypeShelf) => {
                  this.buildCreateShelfOptionChip(shelf)
                }, (shelf: TypeShelf): string => shelf.id)
              }
              .width('100%')
            }
          }
          .width('100%')
        } else if (this.createMode === SubscriptionCreateMode.KOMGA_LIBRARY) {
          Column({ space: 12 }) {
            Text(this.getCreateKomgaTargetSummaryText())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('两个输入都留空时，会一起检查全部 Komga 实例。')
              .fontSize(11)
              .lineHeight(17)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            this.buildCreateDialogTextInput(
              'Komga 实例 ID',
              '留空表示全部实例',
              this.createKomgaInstanceId,
              (value: string) => {
                this.createKomgaInstanceId = value;
              }
            )
            this.buildCreateDialogTextInput(
              '显示名称',
              '只用于显示在提醒标题里',
              this.createKomgaInstanceName,
              (value: string) => {
                this.createKomgaInstanceName = value;
              }
            )
          }
          .width('100%')
        } else {
          this.buildCreateDialogHintCard('Suwayomi 书库', '会直接检查当前接入的整个 Suwayomi 书库，不需要再额外选择。自动补查只会在 APP 回到前台时触发。')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(18)
  }

  @Builder
  private buildCreateDialogBasicTab() {
    Column({ space: 12 }) {
      this.buildCreateDialogHintCard('基础设置', '给提醒起个名字，再决定多久看一次。当前版本只会在 APP 回到前台时自动补查。')

      Column({ space: 12 }) {
        this.buildCreateDialogTextInput(
          '提醒名称',
          '可留空使用默认名称',
          this.createRuleName,
          (value: string) => {
            this.createRuleName = value;
          }
        )
        this.buildCreateIntervalInput()
        this.buildCreateDialogNumberInput(
          '最少新增内容数',
          '例如 1',
          this.createMinNewItemsText,
          (value: string) => {
            this.createMinNewItemsText = value;
          }
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
  }

  @Builder
  private buildCreateDialogFilterTab() {
    Column({ space: 12 }) {
      this.buildCreateDialogHintCard('筛选条件', '如果你只想盯住一部分内容，可以在这里加条件。同一个输入框里多个词用逗号隔开。')

      Column({ space: 12 }) {
        this.buildConditionMatchModeSelector(this.createConditionMatchMode, (mode: SubscriptionConditionMatchMode) => {
          this.createConditionMatchMode = mode;
        })
        this.buildCreateDialogTextInput(
          '标题包含',
          '例如：番外，单行本，合集',
          this.createTitleKeywordText,
          (value: string) => {
            this.createTitleKeywordText = value;
          }
        )
        this.buildCreateDialogTextInput(
          '标签包含',
          '例如：校园，悬疑，恋爱',
          this.createTagKeywordText,
          (value: string) => {
            this.createTagKeywordText = value;
          }
        )
        this.buildCreateDialogTextInput(
          '来源包含',
          '例如：Suwayomi，Komga，某书源名',
          this.createSourceKeywordText,
          (value: string) => {
            this.createSourceKeywordText = value;
          }
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(16)

      this.buildToggleRow('只看已收藏的内容', '没收藏的内容会先跳过，更适合做精确提醒。', this.createRequireFavorite, (value: boolean) => {
        this.createRequireFavorite = value;
      })

      this.buildToggleRow('跳过 NSFW 内容', '带 NSFW 标记的内容会直接跳过，不提醒也不自动处理。', this.createExcludeNSFW, (value: boolean) => {
        this.createExcludeNSFW = value;
      })
    }
    .width('100%')
  }

  @Builder
  private buildCreateDialogActionTab() {
    Column({ space: 12 }) {
      this.buildCreateDialogHintCard('后续操作', '发现更新后要不要提醒、要不要顺手下载，都可以在这里决定。这些操作会跟着前台补查一起执行。')

      Column({ space: 12 }) {
        this.buildCreateDialogNumberInput(
          '自动下载数量',
          '填 0 表示只提醒不下载',
          this.createAutoDownloadCountText,
          (value: string) => {
            this.createAutoDownloadCountText = value;
          }
        )
        Text('支持自动下载的内容会按这里的数量处理最新内容；填 0 就只检查和提醒。自动补查只会在 APP 回到前台时触发。')
          .fontSize(11)
          .lineHeight(17)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(16)

      this.buildToggleRow('有更新时提醒我', '发现新内容后，发一条应用内提醒。提醒也会跟着前台补查一起触发。', this.createEnableNotify, (value: boolean) => {
        this.createEnableNotify = value;
      })

      if (this.isEditingCreateDialog()) {
        Column({ space: 10 }) {
          Text('手动操作')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          Row({ space: 10 }) {
            Button(this.isEditingRuleEnabled() ? '暂停提醒' : '恢复提醒')
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .fontColor(this.isEditingRuleEnabled()
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              .borderRadius(19)
              .enabled(!this.isCreateDialogBusy())
              .onClick(() => {
                this.handleEditingRuleToggle();
              })

            Button(this.runningRuleId === this.editingRuleId ? '检查中...' : '立即检查')
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(Color.White)
              .borderRadius(19)
              .enabled(!this.isCreateDialogBusy())
              .onClick(() => {
                this.handleEditingRuleRunNow();
              })
          }
          .width('100%')

          Button('删除这条提醒')
            .width('100%')
            .height(38)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
            .borderRadius(19)
            .enabled(!this.isCreateDialogBusy())
            .onClick(() => {
              this.handleEditingRuleDelete();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(16)
      }
    }
    .width('100%')
  }

  @Builder
  private buildCreateDialogStageContent() {
    if (this.createDialogStage === SubscriptionCreateDialogStage.TARGET) {
      Scroll(this.createDialogScroller) {
        Column({ space: 12 }) {
          this.buildCreateDialogTargetTab()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    } else {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          this.buildCreateDialogTabButton('基础', $r('sys.symbol.bell'), 0)
          this.buildCreateDialogTabButton('筛选', $r('sys.symbol.funnel'), 1)
          this.buildCreateDialogTabButton('操作', $r('sys.symbol.gearshape'), 2)
        }
        .width('100%')
        .padding(4)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)

        Scroll(this.createDialogScroller) {
          Column({ space: 12 }) {
            if (this.createDialogActiveTab === 0) {
              this.buildCreateDialogBasicTab()
            } else if (this.createDialogActiveTab === 1) {
              this.buildCreateDialogFilterTab()
            } else {
              this.buildCreateDialogActionTab()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .animation({ duration: 220, curve: Curve.EaseOut })
        }
        .width('100%')
        .constraintSize({ maxHeight: 340 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
    }
  }

  @Builder
  private buildCreateDialogFooter() {
    Column({ space: 10 }) {
      Row() {
        Text(this.getCreateDialogFooterHintText())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.isEditingCreateDialog()) {
          Text(this.getCreateDialogLastCheckText())
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      Row({ space: 10 }) {
        Button(this.createDialogStage === SubscriptionCreateDialogStage.TARGET ? '取消' : '上一步')
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isCreateDialogBusy())
          .onClick(() => {
            if (this.createDialogStage === SubscriptionCreateDialogStage.TARGET) {
              this.closeCreateDialog();
              return;
            }
            this.switchCreateDialogStage(SubscriptionCreateDialogStage.TARGET);
          })

        Button(this.createDialogStage === SubscriptionCreateDialogStage.TARGET
          ? '下一步'
          : (this.isBusy ? (this.isEditingCreateDialog() ? '保存中...' : '创建中...') : this.getCreateDialogPrimaryButtonText()))
          .layoutWeight(1)
          .height(36)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .borderRadius(18)
          .enabled(!this.isCreateDialogBusy())
          .onClick(() => {
            if (this.createDialogStage === SubscriptionCreateDialogStage.TARGET) {
              this.openCreateDialogSettingsStage();
              return;
            }
            void this.confirmCreateRule();
          })
      }
      .width('100%')
    }
    .width('100%')
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

  @Builder
  private buildCreateDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      dialogWidth: '90%',
      maxHeight: '90%',
      maxWidth: 620,
      contentPadding: 0,
      dialogRadius: 26,
      useMaskBlur: true,
      onMaskTap: () => {
        if (!this.isCreateDialogBusy()) {
          this.closeCreateDialog();
        }
      }
    }) {
      Column({ space: 16 }) {
        Row() {
          Text(this.getCreateDialogTitleText())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .enabled(!this.isCreateDialogBusy())
          .onClick(() => {
            this.closeCreateDialog();
          })
        }
        .width('100%')

        this.buildCreateDialogOverviewCard()
        Column() {
          this.buildCreateDialogStageContent()
        }
        .width('100%')
        .opacity(this.createDialogStageContentOpacity)
        .translate({ x: this.createDialogStageContentTranslateX, y: 0 })

        this.buildCreateDialogFooter()
      }
      .width('100%')
      .padding(20)
      .opacity(this.createDialogOpacity)
      .scale({ x: this.createDialogScale, y: this.createDialogScale })
      .translate({ y: this.createDialogTranslateY })
      .borderRadius(26)
      .clip(true)
      .onClick(() => {
      })
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
      Text('条件怎么判断')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        this.buildConditionMatchModeOption(
          SubscriptionConditionMatchMode.ALL,
          '全部满足',
          '设定的条件都满足时才继续',
          selectedMode,
          onSelect
        )
        this.buildConditionMatchModeOption(
          SubscriptionConditionMatchMode.ANY,
          '任意一项',
          '满足其中一项就继续',
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
      dialogRadius: 26,
      onMaskTap: () => {
        this.closeDeleteDialog();
      }
    }) {
      Column({ space: 14 }) {
        Row() {
          Text('删除提醒规则')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.closeDeleteDialog();
          })
        }
        .width('100%')

        Column({ space: 8 }) {
          Text(this.getDeletingRulePromptText())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text('历史检查记录会保留，但这条提醒本身会被删除。以后重新创建时，会从新的起点开始。')
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
      .opacity(this.deleteDialogOpacity)
      .scale({ x: this.deleteDialogScale, y: this.deleteDialogScale })
      .translate({ y: this.deleteDialogTranslateY })
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
      dialogRadius: 26,
      contentScrollable: true,
      onMaskTap: () => {
        this.closePreviewDialog();
      }
    }) {
      Column({ space: 14 }) {
        Row() {
          Text(this.previewRuleName.length > 0 ? `检查范围 - ${this.previewRuleName}` : '检查范围')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.closePreviewDialog();
          })
        }
        .width('100%')

        if (this.isPreviewLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(32)
              .height(32)
            Text('正在看看会检查哪些内容...')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.previewTarget === null) {
          Text('暂时没有可显示的结果')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        } else {
          this.buildPreviewSummaryCard(this.previewTarget)
          this.buildPreviewBreakdownCard('内容类型', this.previewTarget.contentTypeBreakdown, false)
          this.buildPreviewBreakdownCard('来源', this.previewTarget.providerTypeBreakdown, true)
          this.buildPreviewCandidateSection()
        }

        Button('关闭')
          .width('100%')
          .height(38)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(19)
          .onClick(() => {
            this.closePreviewDialog();
          })
      }
      .width('100%')
      .opacity(this.previewDialogOpacity)
      .scale({ x: this.previewDialogScale, y: this.previewDialogScale })
      .translate({ y: this.previewDialogTranslateY })
    }
  }

  @Builder
  private buildPreviewSummaryCard(preview: SubscriptionTargetPreview) {
    Column({ space: 12 }) {
      Text(`${preview.targetTitle} · ${preview.totalCandidateCount} 个内容`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 10 }) {
        this.buildRuleMetaCard(
          '可检查',
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
            '会被检查',
            `${preview.matchedCandidateCount} 项`,
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          )
          this.buildRuleMetaCard(
            '会被跳过',
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
      Text(`包含的内容（最多显示 ${this.getPreviewCandidateCount()} 项）`)
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
              Text(!candidate.supported ? '暂不支持' : (candidate.conditionMatched ? '会检查' : '会跳过'))
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
              Text(`最近更新 · ${candidate.latestItemTitle}`)
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
          Text('提醒列表')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text('所有提醒都会在这里显示，可以直接查看状态、修改设置和马上检查。')
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
          Text('正在加载提醒...')
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
              this.buildPageSectionHeader('总览', '看看提醒开了多少，最近检查得怎么样。')
              this.buildStatsCard()
              this.buildPageSectionHeader('使用建议', '书架、远程库和单本内容都能在这里统一管理。')
              this.buildHintCard()
              this.buildPageSectionHeader('提醒列表', '在这里查看、检查、调整或删除所有提醒。')
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
          title: '更新提醒',
          appFontFamily: this.appFontFamily,
          maxDirectActions: 2,
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
