import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Components/NovelSettingsDialogComponent.ets
// 职责: 小说/电子书设置对话框组件，从UnifiedDetailPage提取的独立组件


import { promptAction, curves } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from '../../pages/settings/SettingsPageSurfaceManager';
import { eventBus, GameEvent, CoverChangedPayload, BasePayload } from '../EventBus';
import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedDetailPageParams
} from '../../Models/UnifiedContentModels';
import { EBookAdapter, NovelAdapter } from '../Adapters/UnifiedContentAdapter';
import { buildLocalTextNovelBookId } from '../Adapters/LocalTextNovelAdapter';
import { getNovelTxtTocRuleManager, TxtTocRule } from '../Novel/NovelTxtTocRuleManager';
import { NovelReplaceRuleManager, ReplaceScope, ReplaceRule } from '../Novel/NovelReplaceRuleManager';
import { getNovelContentProcessor } from '../Novel/NovelContentProcessor';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { EBook, EBookMetadata, EBookFormat } from '../../Models/EBookModels';
import { EBookDataManager } from '../Data/EBookDataManager';
import { getNovelDataManager } from '../Novel/NovelDataManager';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';
import { TrackingSettingsDialogComponent } from './TrackingSettingsDialogComponent';
import { ContentTrackingCardState, ContentTrackingCardCallbacks } from '../../components/ContentTrackingStatusCard';

const TAG = 'NovelSettingsDialogComponent';
const NOVEL_SETTINGS_STORE = 'novel_settings';
const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
const NOVEL_BOOK_TOC_RULE_IDS_PREFIX = 'book_toc_rule_ids_';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';
const NOVEL_SETTING_ENABLE_DIRECTORY_PARSING = 'enableNovelDirectoryParsing';
const NOVEL_SETTING_ENABLE_REPLACE_RULES = 'enableNovelReplaceRules';
const NOVEL_SETTING_ENABLE_READ_WHILE_DOWNLOAD = 'enableReadWhileDownload';
const NOVEL_SETTING_DEFAULT_LOAD_CHAPTERS = 'defaultLoadChapters';

@Component
export struct NovelSettingsDialogComponent {
  // 从父组件接收的属性
  @Prop content: UnifiedContent | null = null;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  pageParams: UnifiedDetailPageParams | null = null;

  // 回调函数
  onNavigate?: (pageName: string, params: object | null) => void;
  onContentUpdated?: (content: UnifiedContent) => void;
  onCoverChanged?: (bookId: string, coverPath: string) => void;
  onChaptersReloaded?: () => void;
  getNovelCacheBookId?: (sourceId: string, bookUrl: string) => string;
  isLocalImportedEBookContent?: () => boolean;
  loadNovelContent?: () => Promise<void>;
  getCurrentNovelSourceId?: () => string;
  isCurrentLocalImportedContent?: () => boolean;

  // 服务
  private novelCacheManager = getNovelChapterCacheManager();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private novelDataManager = getNovelDataManager();

  // 小说设置状态
  @State showNovelSettingsDialog: boolean = false;
  @State novelEnableReadWhileDownload: boolean = true;
  @State novelDefaultLoadChapters: number = 50;
  @State novelEnableDirectoryParsing: boolean = true;
  @State novelEnableReplaceRules: boolean = true;
  @State novelSettingsActiveTab: number = 0;
  @State novelDirectoryParsingSelection: boolean = true;
  @State novelReplaceRulesSelection: boolean = true;
  @State novelTocRules: TxtTocRule[] = [];
  @State novelReplaceRules: ReplaceRule[] = [];
  @State novelSelectedTocRuleIds: string[] = [];
  @State novelSelectedReplaceRuleIds: string[] = [];
  @State novelAppliedTocRuleIds: string[] = [];
  @State novelAppliedReplaceRuleIds: string[] = [];
  @State novelDirectoryRulesDirty: boolean = false;
  @State novelReplaceRulesDirty: boolean = false;
  @State isApplyingNovelDirectoryParsing: boolean = false;
  @State isApplyingNovelReplaceRules: boolean = false;
  @State ebookInfoTitle: string = '';
  @State ebookInfoAuthor: string = '';
  @State ebookInfoPublisher: string = '';
  @State ebookInfoPublishDate: string = '';
  @State ebookInfoIsbn: string = '';
  @State ebookInfoLanguage: string = '';
  @State ebookInfoDescription: string = '';
  @State ebookInfoTagsText: string = '';
  @State ebookInfoCoverPath: string = '';
  @State ebookInfoDirty: boolean = false;
  @State isSavingEBookInfo: boolean = false;
  @State coverRefreshKey: number = 0;
  private ebookInfoScraperDialogController: CustomDialogController | null = null;
  

  // 关闭确认对话框状态
  @State isNovelSettingsCloseConfirmDialogVisible: boolean = false;
  private novelSettingsCloseAfterClose: (() => void) | undefined = undefined;

  // 内容跟踪状态
  @State trackingLoadSignal: number = 0;
  @State trackingCardState: ContentTrackingCardState | null = null;
  @State trackingCardCallbacks: ContentTrackingCardCallbacks | null = null;
  


  // 生命周期
  onLoadSignalChanged(): void {
    if (this.loadSignal > 0) {
      this.openNovelSettings();
    }
  }

  // ==================== 辅助方法 ====================

  private getSectionSurfaceStyle(): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme);
  }

  private getSectionBackgroundColor(): ResourceColor {
    return this.getSectionSurfaceStyle().backgroundColor;
  }

  private getSectionBlurStyle(): BlurStyle | undefined {
    return this.getSectionSurfaceStyle().blurStyle;
  }

  private getSectionBlurOptions(): BackgroundBlurStyleOptions {
    return this.getSectionSurfaceStyle().blurOptions;
  }

  // ==================== Handler 方法 ====================

  private isNovelSettingsDialogForLocalEBook(): boolean {
    return this.showNovelSettingsDialog && (this.isLocalImportedEBookContent?.() ?? false);
  }


  private canUseNovelStyleSettingsDialog(): boolean {
    if (!this.content) {
      return false;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return true;
    }
    return this.isLocalImportedEBookContent?.() ?? false;
  }


  private async openNovelSettings(): Promise<void> {
    if (!this.content || !this.pageParams || !this.canUseNovelStyleSettingsDialog()) {
      return;
    }
    await this.loadNovelSettingsDialogConfig();
    await this.loadNovelRuleConfigurations();
    if (this.isLocalImportedEBookContent?.()) {
      this.initializeEBookInfoEditState();
    }
    logger.info(
      TAG,
      `打开小说设置: contentType=${this.content.contentType}, online=${this.isOnlineNovelContent()}, prefetchEnabled=${this.novelEnableReadWhileDownload}, prefetchCount=${this.novelDefaultLoadChapters}`
    );
    this.novelSettingsActiveTab = 0;
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showNovelSettingsDialog = true;
    });
  }


  private closeNovelSettingsDialog(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showNovelSettingsDialog = false;
    });
  }


  private cloneRuleIdList(source: string[]): string[] {
    const result: string[] = [];
    for (const id of source) {
      result.push(id);
    }
    return result;
  }


  private areSameRuleIdList(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (const id of a) {
      if (b.indexOf(id) < 0) {
        return false;
      }
    }
    return true;
  }


  private refreshNovelRuleDirtyState(): void {
    this.novelDirectoryRulesDirty = !this.areSameRuleIdList(this.novelSelectedTocRuleIds, this.novelAppliedTocRuleIds);
    this.novelReplaceRulesDirty = !this.areSameRuleIdList(this.novelSelectedReplaceRuleIds, this.novelAppliedReplaceRuleIds);
  }


  private hasPendingNovelSettingChanges(): boolean {
    return this.novelDirectoryRulesDirty ||
      this.novelReplaceRulesDirty ||
      ((this.isLocalImportedEBookContent?.() ?? false) && this.ebookInfoDirty);
  }


  private async applyPendingNovelSettingsChanges(): Promise<void> {
    if (this.novelDirectoryRulesDirty) {
      await this.applyNovelDirectoryParsingSelection();
    }
    if (this.novelReplaceRulesDirty) {
      await this.applyNovelReplaceRulesSelection();
    }
    if (this.isLocalImportedEBookContent?.() && this.ebookInfoDirty) {
      await this.saveEBookInfoEdit();
    }
  }


  private async requestCloseNovelSettingsDialog(afterClose?: () => void): Promise<void> {
    if (!this.showNovelSettingsDialog) {
      if (afterClose) {
        afterClose();
      }
      return;
    }
    if (this.isApplyingNovelDirectoryParsing || this.isApplyingNovelReplaceRules || this.isSavingEBookInfo) {
      return;
    }
    if (!this.hasPendingNovelSettingChanges()) {
      this.closeNovelSettingsDialog();
      if (afterClose) {
        afterClose();
      }
      return;
    }
    this.novelSettingsCloseAfterClose = afterClose;
    this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion(0.65, 0.92) }, () => {
      this.isNovelSettingsCloseConfirmDialogVisible = true;
    });
  }


  private isOnlineNovelContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return false;
    }
    return !this.content.isLocal && !!this.content.sourceId;
  }


  private pushUniqueRuleScopeId(target: string[], scopeId: string): void {
    if (scopeId.length <= 0 || target.indexOf(scopeId) >= 0) {
      return;
    }
    target.push(scopeId);
  }


  private getCurrentNovelRuleScopeIds(): string[] {
    const scopeIds: string[] = [];
    if (!this.content) {
      return scopeIds;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      const sourceId = this.content.sourceId || this.pageParams?.sourceId || 'local';
      this.pushUniqueRuleScopeId(scopeIds, this.getNovelCacheBookId?.(sourceId, this.content.id) ?? '');
      return scopeIds;
    }
    if (this.isLocalImportedEBookContent?.()) {
      const ebook = EBookAdapter.getOriginalEBook(this.content);
      if (!ebook) {
        return scopeIds;
      }
      if (ebook.format === EBookFormat.TXT) {
        this.pushUniqueRuleScopeId(scopeIds, buildLocalTextNovelBookId(ebook.id));
      }
      this.pushUniqueRuleScopeId(scopeIds, ebook.id);
    }
    return scopeIds;
  }


  private getCurrentNovelRuleScopeId(): string {
    const scopeIds = this.getCurrentNovelRuleScopeIds();
    if (scopeIds.length <= 0) {
      return '';
    }
    return scopeIds[0];
  }


  private buildBookTocRuleKey(scopeId: string): string {
    return `${NOVEL_BOOK_TOC_RULE_IDS_PREFIX}${scopeId}`;
  }


  private buildBookReplaceRuleKey(scopeId: string): string {
    return `${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${scopeId}`;
  }


  private parseRuleIdArray(rawValue: string): string[] {
    if (!rawValue || rawValue.length === 0) {
      return [];
    }
    try {
      const parsed = SafeUtils.parseArr(rawValue) as Array<string>;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (const item of parsed) {
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result;
    } catch (error) {
      logger.warn(TAG, `解析规则ID列表失败: ${String(error)}`);
      return [];
    }
  }


  private isRuleSelected(selectedIds: string[], ruleId: string): boolean {
    return selectedIds.indexOf(ruleId) >= 0;
  }


  private toggleRuleSelection(selectedIds: string[], ruleId: string, enabled: boolean): string[] {
    const result: string[] = [];
    for (const id of selectedIds) {
      if (id !== ruleId) {
        result.push(id);
      }
    }
    if (enabled) {
      result.push(ruleId);
    }
    return result;
  }


  private getReplaceRuleScopeLabel(scope: ReplaceScope): string {
    if (scope === ReplaceScope.TITLE) {
      return '标题';
    }
    if (scope === ReplaceScope.CONTENT) {
      return '内容';
    }
    return '全部';
  }


  private getReplaceRuleSourceLabel(rule: ReplaceRule): string {
    if (!rule.sourceIds || rule.sourceIds.length === 0) {
      return '全部书源';
    }
    return `指定书源(${rule.sourceIds.length})`;
  }


  private async loadNovelRuleConfigurations(): Promise<void> {
    try {
      const tocRuleManager = getNovelTxtTocRuleManager();
      await tocRuleManager.initialize();
      this.novelTocRules = tocRuleManager.getAllRules();

      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
      this.novelReplaceRules = replaceRuleManager.getAllRules();

      const scopeIds = this.getCurrentNovelRuleScopeIds();
      const primaryScopeId = scopeIds.length > 0 ? scopeIds[0] : '';
      let scopedTocRuleIds: string[] = [];
      let scopedReplaceRuleIds: string[] = [];
      let hasScopedTocRuleIds = false;
      let hasScopedReplaceRuleIds = false;
      if (scopeIds.length > 0) {
        const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
        const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
        for (const scopeId of scopeIds) {
          if (!hasScopedTocRuleIds) {
            const rawTocRuleIds = await store.get(this.buildBookTocRuleKey(scopeId), '') as string;
            if (rawTocRuleIds.length > 0) {
              hasScopedTocRuleIds = true;
              scopedTocRuleIds = this.parseRuleIdArray(rawTocRuleIds);
            }
          }
          if (!hasScopedReplaceRuleIds) {
            const rawReplaceRuleIds = await store.get(this.buildBookReplaceRuleKey(scopeId), '') as string;
            if (rawReplaceRuleIds.length > 0) {
              hasScopedReplaceRuleIds = true;
              scopedReplaceRuleIds = this.parseRuleIdArray(rawReplaceRuleIds);
            }
          }
          if (hasScopedTocRuleIds && hasScopedReplaceRuleIds) {
            break;
          }
        }
      }
      if (!hasScopedTocRuleIds) {
        scopedTocRuleIds = this.novelTocRules.filter((rule: TxtTocRule) => rule.enabled).map((rule: TxtTocRule) => rule.id);
      }
      if (!hasScopedReplaceRuleIds) {
        scopedReplaceRuleIds = this.novelReplaceRules.filter((rule: ReplaceRule) => rule.enabled).map((rule: ReplaceRule) => rule.id);
      }
      this.novelSelectedTocRuleIds = scopedTocRuleIds;
      this.novelSelectedReplaceRuleIds = scopedReplaceRuleIds;
      this.novelAppliedTocRuleIds = this.cloneRuleIdList(this.novelSelectedTocRuleIds);
      this.novelAppliedReplaceRuleIds = this.cloneRuleIdList(this.novelSelectedReplaceRuleIds);
      this.novelDirectoryRulesDirty = false;
      this.novelReplaceRulesDirty = false;
      logger.info(
        TAG,
        `小说规则配置已加载: scopeId=${primaryScopeId}, scopeCount=${scopeIds.length}, tocRules=${this.novelSelectedTocRuleIds.length}, replaceRules=${this.novelSelectedReplaceRuleIds.length}`
      );
    } catch (error) {
      logger.warn(TAG, `加载小说规则配置失败: ${String(error)}`);
      this.novelTocRules = [];
      this.novelReplaceRules = [];
      this.novelSelectedTocRuleIds = [];
      this.novelSelectedReplaceRuleIds = [];
      this.novelAppliedTocRuleIds = [];
      this.novelAppliedReplaceRuleIds = [];
      this.novelDirectoryRulesDirty = false;
      this.novelReplaceRulesDirty = false;
    }
  }


  private async loadNovelSettingsDialogConfig(): Promise<void> {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      this.novelEnableReadWhileDownload = await store.get('enableReadWhileDownload', true) as boolean;
      this.novelDefaultLoadChapters = Number(await store.get('defaultLoadChapters', 50));
      this.novelEnableDirectoryParsing = await store.get(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, true) as boolean;
      this.novelEnableReplaceRules = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
      this.novelDirectoryParsingSelection = this.novelEnableDirectoryParsing;
      this.novelReplaceRulesSelection = this.novelEnableReplaceRules;
      logger.info(
        TAG,
        `加载小说设置: prefetchEnabled=${this.novelEnableReadWhileDownload}, prefetchCount=${this.novelDefaultLoadChapters}, directory=${this.novelEnableDirectoryParsing}, replace=${this.novelEnableReplaceRules}`
      );
      if (!Number.isFinite(this.novelDefaultLoadChapters) || this.novelDefaultLoadChapters < 0) {
        this.novelDefaultLoadChapters = 50;
      }
    } catch (error) {
      logger.warn(TAG, `加载小说设置对话框配置失败: ${String(error)}`);
      this.novelEnableReadWhileDownload = true;
      this.novelDefaultLoadChapters = 50;
      this.novelEnableDirectoryParsing = true;
      this.novelEnableReplaceRules = true;
      this.novelDirectoryParsingSelection = true;
      this.novelReplaceRulesSelection = true;
    }
  }


  private async saveNovelSettingValue(key: string, value: number | boolean): Promise<boolean> {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      await store.put(key, value);
      await store.flush();
      logger.info(TAG, `小说设置已保存: ${key}=${String(value)}`);
      return true;
    } catch (error) {
      logger.error(TAG, `保存小说设置失败: key=${key}, error=${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存设置失败', duration: 1200 });
      return false;
    }
  }


  private getNovelPrefetchChapterOptions(): number[] {
    return [10, 20, 50, 100, 200, 9999];
  }


  private formatNovelPrefetchChapterCount(value: number): string {
    if (value >= 9999) {
      return '全部';
    }
    return `${value}章`;
  }


  private onNovelPrefetchChapterCountChange(value: number): void {
    this.novelDefaultLoadChapters = value;
    logger.info(TAG, `小说预下载范围切换: ${value}章`);
    void this.saveNovelSettingValue('defaultLoadChapters', value);
  }


  private async saveBookScopedRuleIds(tocRuleIds: string[], replaceRuleIds: string[]): Promise<boolean> {
    const scopeIds = this.getCurrentNovelRuleScopeIds();
    if (scopeIds.length === 0) {
      return false;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      for (const scopeId of scopeIds) {
        await store.put(this.buildBookTocRuleKey(scopeId), JSON.stringify(tocRuleIds));
        await store.put(this.buildBookReplaceRuleKey(scopeId), JSON.stringify(replaceRuleIds));
      }
      await store.flush();
      logger.info(
        TAG,
        `小说书籍专属规则已保存: scopeIds=${scopeIds.join('|')}, tocRules=${tocRuleIds.length}, replaceRules=${replaceRuleIds.length}`
      );
      return true;
    } catch (error) {
      logger.error(TAG, `保存小说书籍专属规则失败: ${String(error)}`);
      return false;
    }
  }


  private async getScopedRuleIds(scopeId: string, key: string): Promise<string[] | null> {
    if (scopeId.length === 0) {
      return null;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      const raw = await store.get(key, '') as string;
      if (!raw || raw.length === 0) {
        return null;
      }
      return this.parseRuleIdArray(raw);
    } catch (error) {
      logger.warn(TAG, `读取书籍规则失败: key=${key}, error=${String(error)}`);
      return null;
    }
  }


  private async applyNovelDirectoryParsingSelection(): Promise<void> {
    if (this.isApplyingNovelDirectoryParsing || !this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    this.isApplyingNovelDirectoryParsing = true;
    try {
      const nextEnabled = true;
      this.novelDirectoryParsingSelection = true;
      const saved = await this.saveNovelSettingValue(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, nextEnabled);
      if (!saved) {
        return;
      }
      const scopedSaved = await this.saveBookScopedRuleIds(this.novelSelectedTocRuleIds, this.novelSelectedReplaceRuleIds);
      if (!scopedSaved) {
        this.getUIContext().getPromptAction().showToast({ message: '保存书籍规则失败', duration: 1400 });
        return;
      }
      this.novelEnableDirectoryParsing = nextEnabled;
      await this.refreshNovelContentByDirectorySetting(nextEnabled, this.novelSelectedTocRuleIds);
      this.novelAppliedTocRuleIds = this.cloneRuleIdList(this.novelSelectedTocRuleIds);
      this.refreshNovelRuleDirtyState();
      logger.info(TAG, `目录解析应用完成: enabled=${nextEnabled}, selectedRules=${this.novelSelectedTocRuleIds.length}`);
      this.getUIContext().getPromptAction().showToast({ message: '目录规则已应用并刷新章节', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `应用目录解析规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '应用目录解析规则失败', duration: 1400 });
    } finally {
      this.isApplyingNovelDirectoryParsing = false;
    }
  }


  private async applyNovelReplaceRulesSelection(): Promise<void> {
    if (this.isApplyingNovelReplaceRules || !this.content ||
      (this.content.contentType !== UnifiedContentType.NOVEL && !this.isLocalImportedEBookContent?.())) {
      return;
    }
    this.isApplyingNovelReplaceRules = true;
    try {
      const nextEnabled = true;
      this.novelReplaceRulesSelection = true;
      const saved = await this.saveNovelSettingValue(NOVEL_SETTING_ENABLE_REPLACE_RULES, nextEnabled);
      if (!saved) {
        return;
      }
      const scopedSaved = await this.saveBookScopedRuleIds(this.novelSelectedTocRuleIds, this.novelSelectedReplaceRuleIds);
      if (!scopedSaved) {
        this.getUIContext().getPromptAction().showToast({ message: '保存书籍规则失败', duration: 1400 });
        return;
      }
      this.novelEnableReplaceRules = nextEnabled;
      await this.applyReplaceRulesToCurrentNovelContent(nextEnabled, this.novelSelectedReplaceRuleIds);
      this.novelAppliedReplaceRuleIds = this.cloneRuleIdList(this.novelSelectedReplaceRuleIds);
      this.refreshNovelRuleDirtyState();
      logger.info(TAG, `净化规则应用完成: enabled=${nextEnabled}, selectedRules=${this.novelSelectedReplaceRuleIds.length}`);
      this.getUIContext().getPromptAction().showToast({ message: '净化规则已应用到当前内容', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `应用净化规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '应用净化规则失败', duration: 1400 });
    } finally {
      this.isApplyingNovelReplaceRules = false;
    }
  }


  private openNovelTxtTocRulePage(): void {
    void this.requestCloseNovelSettingsDialog(() => {
      try {
        this.onNavigate?.('NovelTxtTocRulePage', null);
      } catch (error) {
        logger.error(TAG, `打开TXT目录规则页失败: ${String(error)}`);
      }
    });
  }


  private openNovelReplaceRulePage(): void {
    void this.requestCloseNovelSettingsDialog(() => {
      try {
        this.onNavigate?.('NovelReplaceRulePage', null);
      } catch (error) {
        logger.error(TAG, `打开净化规则页失败: ${String(error)}`);
      }
    });
  }


  private async refreshNovelContentByDirectorySetting(enableDirectoryParsing: boolean, selectedTocRuleIds: string[]): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    const previousContent = this.content;
    if (enableDirectoryParsing && this.isOnlineNovelContent() && this.content.id) {
      await this.novelCacheManager.clearChapterListCache(this.content.id);
    }
    await this.loadNovelContent?.();
    await this.applyDirectoryRulesToCurrentContent(enableDirectoryParsing, selectedTocRuleIds);
    if (
      previousContent &&
      previousContent.chapters.length > 0 &&
      (!this.content || this.content.contentType !== UnifiedContentType.NOVEL || this.content.chapters.length === 0)
    ) {
      this.onContentUpdated?.(previousContent);
      this.onChaptersReloaded?.();
      logger.warn(TAG, '目录解析结果为空，已回退到应用前内容');
      this.getUIContext().getPromptAction().showToast({ message: '目录解析结果为空，已恢复原目录', duration: 1400 });
    }
  }


  private async applyDirectoryRulesToCurrentContent(enableDirectoryParsing: boolean, selectedTocRuleIds: string[]): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL || !enableDirectoryParsing) {
      return;
    }
    if (selectedTocRuleIds.length === 0) {
      return;
    }
    const tocRuleManager = getNovelTxtTocRuleManager();
    await tocRuleManager.initialize();
    const regexList: RegExp[] = [];
    for (const ruleId of selectedTocRuleIds) {
      const rule = tocRuleManager.getRule(ruleId);
      if (!rule || !rule.rule) {
        continue;
      }
      try {
        regexList.push(new RegExp(rule.rule, 'm'));
      } catch (error) {
        logger.warn(TAG, `目录规则无效正则: id=${ruleId}, error=${String(error)}`);
      }
    }
    if (regexList.length === 0) {
      return;
    }
    const currentContent = this.content;
    const nextChapters: UnifiedChapter[] = [];
    let matchedCount = 0;
    let changedCount = 0;
    for (const chapter of currentContent.chapters) {
      const baseTitle = chapter.title || '';
      let nextTitle = baseTitle;
      for (const regex of regexList) {
        regex.lastIndex = 0;
        const matched = regex.exec(baseTitle);
        if (matched && matched[0]) {
          matchedCount += 1;
          nextTitle = matched[0].trim();
          break;
        }
      }
      if (nextTitle !== baseTitle) {
        changedCount += 1;
      }
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    if (changedCount <= 0) {
      logger.info(TAG, `目录规则已应用: 匹配章节=${matchedCount}, 标题变化=${changedCount}`);
      return;
    }
    const updatedContent: UnifiedContent = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: currentContent.description,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: currentContent.lastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
    this.content = updatedContent;
    logger.info(TAG, `目录规则已应用: 匹配章节=${matchedCount}, 标题变化=${changedCount}`);
  }


  private async applyReplaceRulesToCurrentNovelContent(
    enableReplaceRules: boolean,
    selectedRuleIds: string[] | null = null
  ): Promise<void> {
    if (!this.content) {
      return;
    }
    if (this.isLocalImportedEBookContent?.()) {
      await this.applyReplaceRulesToCurrentEBookContent(enableReplaceRules, selectedRuleIds);
      return;
    }
    if (this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    const sourceId = this.content.sourceId || this.pageParams?.sourceId;
    const originalNovel = NovelAdapter.getOriginalNovel(this.content);
    if (!originalNovel) {
      return;
    }
    if (enableReplaceRules) {
      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
    }
    const contentProcessor = getNovelContentProcessor();
    const baseDescription = originalNovel.intro || this.content.description;
    const scopedRuleIds = selectedRuleIds === null ? undefined : selectedRuleIds;
    const nextDescription = enableReplaceRules
      ? contentProcessor.quickReplace(baseDescription, ReplaceScope.CONTENT, sourceId, scopedRuleIds)
      : baseDescription;

    const nextChapters: UnifiedChapter[] = [];
    for (const chapter of this.content.chapters) {
      const originalChapter = NovelAdapter.getOriginalChapter(chapter);
      if (!originalChapter) {
        nextChapters.push(chapter);
        continue;
      }
      const baseTitle = originalChapter.title || chapter.title;
      const nextTitle = enableReplaceRules
        ? contentProcessor.processTitle(baseTitle, sourceId, scopedRuleIds)
        : baseTitle;
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    let nextLastReadChapterTitle = this.content.lastReadChapterTitle;
    if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < nextChapters.length) {
      nextLastReadChapterTitle = nextChapters[this.content.lastReadChapterIndex].title;
    }
    const currentContent = this.content;
    const updatedContent: UnifiedContent = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: nextDescription,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: nextLastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
    this.content = updatedContent;
  }


  private async applyReplaceRulesToCurrentEBookContent(
    enableReplaceRules: boolean,
    selectedRuleIds: string[] | null = null
  ): Promise<void> {
    if (!this.content || !this.isLocalImportedEBookContent?.()) {
      return;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return;
    }
    if (enableReplaceRules) {
      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
    }
    const contentProcessor = getNovelContentProcessor();
    const scopedRuleIds = selectedRuleIds === null ? undefined : selectedRuleIds;
    const baseDescription = ebook.metadata?.description || this.content.description;
    const nextDescription = enableReplaceRules
      ? contentProcessor.quickReplace(baseDescription, ReplaceScope.CONTENT, undefined, scopedRuleIds)
      : baseDescription;

    const nextChapters: UnifiedChapter[] = [];
    for (const chapter of this.content.chapters) {
      const originalChapter = EBookAdapter.getOriginalChapter(chapter);
      const baseTitle = originalChapter ? (originalChapter.title || chapter.title) : chapter.title;
      const nextTitle = enableReplaceRules
        ? contentProcessor.processTitle(baseTitle, undefined, scopedRuleIds)
        : baseTitle;
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    let nextLastReadChapterTitle = this.content.lastReadChapterTitle;
    if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < nextChapters.length) {
      nextLastReadChapterTitle = nextChapters[this.content.lastReadChapterIndex].title;
    }
    const currentContent = this.content;
    const updatedContent: UnifiedContent = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: nextDescription,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: nextLastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
    this.content = updatedContent;
  }


  private initializeEBookInfoEditState(): void {
    const ebook = this.content ? EBookAdapter.getOriginalEBook(this.content) : null;
    const metadata = ebook?.metadata;
    this.ebookInfoTitle = metadata?.title || this.content?.title || '';
    this.ebookInfoAuthor = metadata?.author || this.content?.author || '';
    this.ebookInfoPublisher = metadata?.publisher || this.content?.publisher || '';
    this.ebookInfoPublishDate = metadata?.publishDate || this.content?.publishDate || '';
    this.ebookInfoIsbn = metadata?.isbn || this.content?.isbn || '';
    this.ebookInfoLanguage = metadata?.language || '';
    this.ebookInfoDescription = metadata?.description || this.content?.description || '';
    this.ebookInfoCoverPath = metadata?.coverImagePath || this.content?.coverUrl || '';
    const tags: string[] = metadata?.tags || this.content?.tags || [];
    this.ebookInfoTagsText = tags.join(', ');
    this.ebookInfoDirty = false;
  }


  private markEBookInfoDirty(): void {
    this.ebookInfoDirty = true;
  }


  private parseEBookInfoTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }
    return tagsText
      .split(/[,，、]/)
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }


  private buildEBookMetadataFromInfoDraft(ebook: EBook): EBookMetadata {
    const metadata: EBookMetadata = {
      title: this.ebookInfoTitle.trim(),
      author: this.ebookInfoAuthor.trim(),
      publisher: this.ebookInfoPublisher.trim(),
      publishDate: this.ebookInfoPublishDate.trim(),
      isbn: this.ebookInfoIsbn.trim(),
      language: this.ebookInfoLanguage.trim(),
      description: this.ebookInfoDescription.trim(),
      coverImagePath: this.ebookInfoCoverPath.trim(),
      tags: this.parseEBookInfoTags(this.ebookInfoTagsText),
      rating: ebook.metadata?.rating ?? 0
    };
    return metadata;
  }


  private isNetworkPath(path: string): boolean {
    return path.startsWith('http://') || path.startsWith('https://');
  }


  private syncCurrentContentFromEBookInfo(ebook: EBook, previousCoverPath: string): void {
    if (!this.content) {
      return;
    }
    const metadata = ebook.metadata;
    this.content.title = metadata.title;
    this.content.author = metadata.author;
    this.content.description = metadata.description;
    this.content.coverUrl = metadata.coverImagePath;
    this.content.publisher = metadata.publisher;
    this.content.publishDate = metadata.publishDate;
    this.content.isbn = metadata.isbn;
    this.content.tags = metadata.tags;
    this.onContentUpdated?.(this.content);
    if (previousCoverPath !== metadata.coverImagePath) {
      this.onCoverChanged?.(ebook.id, metadata.coverImagePath);
    }
  }


  private async saveEBookInfoEdit(): Promise<void> {
    if (this.isSavingEBookInfo || !this.content || !this.isLocalImportedEBookContent?.()) {
      return;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      this.getUIContext().getPromptAction().showToast({ message: '未找到电子书数据', duration: 1400 });
      return;
    }
    if (this.ebookInfoTitle.trim().length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入书名', duration: 1400 });
      return;
    }
    if (this.ebookInfoAuthor.trim().length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入作者', duration: 1400 });
      return;
    }
    this.isSavingEBookInfo = true;
    try {
      const previousCoverPath = ebook.metadata?.coverImagePath || '';
      ebook.metadata = this.buildEBookMetadataFromInfoDraft(ebook);
      ebook.lastUpdateTime = Date.now();
      await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
      this.syncCurrentContentFromEBookInfo(ebook, previousCoverPath);
      this.coverRefreshKey = Date.now();
      eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
      this.ebookInfoDirty = false;
      logger.info(TAG, `本地电子书信息已保存: ${ebook.id}, title=${ebook.metadata.title}`);
      this.getUIContext().getPromptAction().showToast({ message: '电子书信息已保存', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `保存电子书信息失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存电子书信息失败', duration: 1600 });
    } finally {
      this.isSavingEBookInfo = false;
    }
  }


  private openEBookInfoScraperDialog(): void {
    const config: ScraperDialogConfig = {
      initialKeyword: this.ebookInfoTitle || this.content?.title || '',
      contentType: ScraperContentType.BOOK,
      title: '搜索电子书信息'
    };
    this.ebookInfoScraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyEBookInfoScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消电子书信息刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.ebookInfoScraperDialogController.open();
  }


  private appendUniqueEBookInfoTags(target: string[], values: string[] | undefined): void {
    if (!values || values.length <= 0) {
      return;
    }
    for (const value of values) {
      const normalized = value.trim();
      if (normalized.length > 0 && target.indexOf(normalized) < 0) {
        target.push(normalized);
      }
    }
  }


  private applyEBookInfoScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用电子书刮削结果到编辑字段: ${metadata.title}`);
    if (metadata.title && metadata.title.trim().length > 0) {
      this.ebookInfoTitle = metadata.title.trim();
    }
    if (result.applyAuthor) {
      if (metadata.author && metadata.author.trim().length > 0) {
        this.ebookInfoAuthor = metadata.author.trim();
      } else if (metadata.authors && metadata.authors.length > 0) {
        this.ebookInfoAuthor = metadata.authors.join(', ');
      }
    }
    if (result.applyDescription) {
      const description = metadata.description || metadata.summary || '';
      if (description.trim().length > 0) {
        this.ebookInfoDescription = description.trim();
      }
    }
    if (result.applyPublisher && metadata.publisher && metadata.publisher.trim().length > 0) {
      this.ebookInfoPublisher = metadata.publisher.trim();
    }
    if (metadata.releaseDate && metadata.releaseDate.trim().length > 0) {
      this.ebookInfoPublishDate = metadata.releaseDate.trim();
    }
    if (result.applyTags) {
      const tags: string[] = [];
      this.appendUniqueEBookInfoTags(tags, metadata.genres);
      this.appendUniqueEBookInfoTags(tags, metadata.tags);
      this.appendUniqueEBookInfoTags(tags, metadata.themes);
      if (tags.length > 0) {
        this.ebookInfoTagsText = tags.join(', ');
      }
    }
    if (result.applyCover) {
      const coverPath = metadata.coverUrlLarge || metadata.coverUrl || metadata.coverUrlMedium || metadata.coverUrlSmall || '';
      if (coverPath.trim().length > 0) {
        this.ebookInfoCoverPath = coverPath.trim();
      }
    }
    this.ebookInfoDirty = true;
    this.getUIContext().getPromptAction().showToast({ message: '刮削信息已填入，请确认保存', duration: 1400 });
  }


  private normalizeEBookInfoCoverPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('file://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return `file://${trimmed}`;
    }
    return trimmed;
  }


  private getEBookInfoCoverPreviewSource(): string {
    const normalizedPath = this.normalizeEBookInfoCoverPath(this.ebookInfoCoverPath);
    if (normalizedPath.startsWith('http://') || normalizedPath.startsWith('https://')) {
      const connector = normalizedPath.indexOf('?') >= 0 ? '&' : '?';
      return `${normalizedPath}${connector}refresh=${this.coverRefreshKey}`;
    }
    return normalizedPath;
  }


  private closeNovelSettingsDialogImmediately(): void {
    this.novelDirectoryRulesDirty = false;
    this.novelReplaceRulesDirty = false;
    this.closeNovelSettingsDialog();
    const afterClose = this.novelSettingsCloseAfterClose;
    this.novelSettingsCloseAfterClose = undefined;
    if (afterClose) {
      afterClose();
    }
  }


  private hideNovelSettingsCloseConfirmDialog(shouldClearAfterClose: boolean = true): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.isNovelSettingsCloseConfirmDialogVisible = false;
    });
    if (shouldClearAfterClose) {
      this.novelSettingsCloseAfterClose = undefined;
    }
  }


  // ==================== Builder 方法 ====================

  @Builder
  private buildNovelSettingsTabButton(label: string, index: number) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.novelSettingsActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.novelSettingsActiveTab === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(14)
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      logger.info(TAG, `小说设置标签切换: ${label}`);
      this.novelSettingsActiveTab = index;
    })
  }


  @Builder
  private buildNovelPrefetchSettingsTab() {
    Column({ space: 10 }) {
      Row() {
        Text('预下载设置（仅在线）')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        if (this.isOnlineNovelContent()) {
          Toggle({ type: ToggleType.Switch, isOn: this.novelEnableReadWhileDownload })
            .onChange((isOn: boolean) => {
              this.novelEnableReadWhileDownload = isOn;
              logger.info(TAG, `小说预下载开关变更: ${isOn}`);
              void this.saveNovelSettingValue('enableReadWhileDownload', isOn);
            })
        }
      }
      .width('100%')

      if (this.isOnlineNovelContent()) {
        Text('在阅读时提前缓存后续章节，设置实时生效')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        if (this.novelEnableReadWhileDownload) {
          Column({ space: 8 }) {
            Text(`预下载范围：${this.formatNovelPrefetchChapterCount(this.novelDefaultLoadChapters)}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            Row({ space: 8 }) {
              ForEach(this.getNovelPrefetchChapterOptions(), (count: number) => {
                Button(this.formatNovelPrefetchChapterCount(count))
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor(this.novelDefaultLoadChapters === count
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                  .fontColor(this.novelDefaultLoadChapters === count
                    ? Color.White
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => this.onNovelPrefetchChapterCountChange(count))
              }, (count: number) => `novel_prefetch_${count}`)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      } else {
        Text('当前为本地小说，预下载仅在线小说可用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  @Builder
  private buildNovelDirectorySettingsTab() {
    Column({ space: 10 }) {
      Text('目录解析（书籍专属）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text('为当前小说单独选择目录解析规则，点击“应用”后会保存并重新解析目录')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        Button(this.isApplyingNovelDirectoryParsing ? '应用中...' : '应用')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .enabled(!this.isApplyingNovelDirectoryParsing)
          .onClick(() => {
            void this.applyNovelDirectoryParsingSelection();
          })
        Button('管理目录规则')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.openNovelTxtTocRulePage();
          })
      }
      .width('100%')

      if (this.novelTocRules.length <= 0) {
        Text('暂无目录规则')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        ForEach(this.novelTocRules, (rule: TxtTocRule) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(rule.name)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(rule.rule)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`序号：${rule.serialNumber}  默认：${rule.enabled ? '启用' : '禁用'}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (rule.example && rule.example.length > 0) {
                Text(`示例：${rule.example}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.isRuleSelected(this.novelSelectedTocRuleIds, rule.id) })
              .onChange((isOn: boolean) => {
                this.novelSelectedTocRuleIds = this.toggleRuleSelection(this.novelSelectedTocRuleIds, rule.id, isOn);
                this.refreshNovelRuleDirtyState();
                logger.info(TAG, `目录规则选择变更: rule=${rule.name}, enabled=${isOn}`);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(10)
        }, (rule: TxtTocRule) => `toc_rule_${rule.id}`)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  @Builder
  private buildNovelReplaceRuleSettingsTab() {
    Column({ space: 10 }) {
      Text('净化规则（书籍专属）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text(this.isNovelSettingsDialogForLocalEBook()
        ? '为当前电子书单独选择净化规则，点击“应用”后会保存到阅读器并立即作用于详情页内容'
        : '为当前小说单独选择净化规则，点击“应用”后会立即作用于当前内容并持久化')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        Button(this.isApplyingNovelReplaceRules ? '应用中...' : '应用')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .enabled(!this.isApplyingNovelReplaceRules)
          .onClick(() => {
            void this.applyNovelReplaceRulesSelection();
          })
        Button('管理净化规则')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.openNovelReplaceRulePage();
          })
      }
      .width('100%')

      if (this.novelReplaceRules.length <= 0) {
        Text('暂无净化规则')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        ForEach(this.novelReplaceRules, (rule: ReplaceRule) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(rule.name)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`匹配：${rule.pattern}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`替换：${rule.replacement}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`范围：${this.getReplaceRuleScopeLabel(rule.scope)}  来源：${this.getReplaceRuleSourceLabel(rule)}  默认：${rule.enabled ? '启用' : '禁用'}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.isRuleSelected(this.novelSelectedReplaceRuleIds, rule.id) })
              .onChange((isOn: boolean) => {
                this.novelSelectedReplaceRuleIds = this.toggleRuleSelection(this.novelSelectedReplaceRuleIds, rule.id, isOn);
                this.refreshNovelRuleDirtyState();
                logger.info(TAG, `净化规则选择变更: rule=${rule.name}, enabled=${isOn}`);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(10)
        }, (rule: ReplaceRule) => `replace_rule_${rule.id}`)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  @Builder
  private buildEBookInfoTextInput(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .height(38)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.markEBookInfoDirty();
        })
    }
    .width('100%')
  }


  @Builder
  private buildEBookInfoTextArea(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      TextArea({ text: value, placeholder: placeholder })
        .height(92)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .padding(10)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.markEBookInfoDirty();
        })
    }
    .width('100%')
  }


  @Builder
  private buildEBookInfoEditTab() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('信息修改')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.ebookInfoDirty ? '有未保存修改' : '修改后会同步到书库与详情页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.ebookInfoDirty
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('刮削')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '18')
        .borderRadius(15)
        .onClick(() => {
          this.openEBookInfoScraperDialog();
        })
      }
      .width('100%')

      Row({ space: 12 }) {
        if (this.ebookInfoCoverPath.trim().length > 0) {
          Image(this.getEBookInfoCoverPreviewSource())
            .width(68)
            .height(96)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        } else {
          Image($r('app.media.ebook'))
            .width(68)
            .height(96)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        }
        Column({ space: 8 }) {
          this.buildEBookInfoTextInput('封面路径 / URL', this.ebookInfoCoverPath, '可填本地路径或网络封面 URL', (value: string) => {
            this.ebookInfoCoverPath = value;
          })
          Button('清空封面')
            .height(30)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(15)
            .onClick(() => {
              this.ebookInfoCoverPath = '';
              this.markEBookInfoDirty();
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      this.buildEBookInfoTextInput('书名 *', this.ebookInfoTitle, '请输入书名', (value: string) => {
        this.ebookInfoTitle = value;
      })
      this.buildEBookInfoTextInput('作者 *', this.ebookInfoAuthor, '请输入作者', (value: string) => {
        this.ebookInfoAuthor = value;
      })
      this.buildEBookInfoTextInput('出版社', this.ebookInfoPublisher, '请输入出版社', (value: string) => {
        this.ebookInfoPublisher = value;
      })
      this.buildEBookInfoTextInput('出版日期', this.ebookInfoPublishDate, '例如 2024-03 或 2024年3月', (value: string) => {
        this.ebookInfoPublishDate = value;
      })
      this.buildEBookInfoTextInput('ISBN', this.ebookInfoIsbn, '请输入 ISBN', (value: string) => {
        this.ebookInfoIsbn = value;
      })
      this.buildEBookInfoTextInput('语言', this.ebookInfoLanguage, '例如 zh-CN、en、ja', (value: string) => {
        this.ebookInfoLanguage = value;
      })
      this.buildEBookInfoTextArea('简介', this.ebookInfoDescription, '请输入简介', (value: string) => {
        this.ebookInfoDescription = value;
      })
      this.buildEBookInfoTextInput('标签（逗号分隔）', this.ebookInfoTagsText, '例如 科幻, 推理, 历史', (value: string) => {
        this.ebookInfoTagsText = value;
      })

      Button(this.isSavingEBookInfo ? '保存中...' : '保存信息')
        .width('100%')
        .height(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(Color.White)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isSavingEBookInfo)
        .onClick(() => {
          void this.saveEBookInfoEdit();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  @Builder
  private buildNovelSettingsCloseConfirmDialog() {
    if (this.isNovelSettingsCloseConfirmDialogVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.hideNovelSettingsCloseConfirmDialog(),
        dialogWidth: '90%',
        maxWidth: 520,
        contentPadding: 24,
        zIndexValue: 120,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
          Text('存在未应用修改')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(this.isLocalImportedEBookContent?.()
            ? '净化规则或信息修改还有未保存内容。你可以先应用再退出，也可以直接退出。'
            : '目录规则或净化规则还有未应用的修改。你可以先应用再退出，也可以直接退出。')
            .fontSize(13)
            .lineHeight(22)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')

          Row({ space: 10 }) {
            Button('继续编辑')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(20)
              .onClick(() => this.hideNovelSettingsCloseConfirmDialog())

            Button('直接退出')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .borderRadius(20)
              .onClick(() => {
                this.hideNovelSettingsCloseConfirmDialog(false);
                this.closeNovelSettingsDialogImmediately();
              })

            Button('应用后退出')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(Color.White)
              .borderRadius(20)
              .enabled(!this.isApplyingNovelDirectoryParsing && !this.isApplyingNovelReplaceRules && !this.isSavingEBookInfo)
              .onClick(() => {
                void (async () => {
                  await this.applyPendingNovelSettingsChanges();
                  if (!this.hasPendingNovelSettingChanges()) {
                    this.hideNovelSettingsCloseConfirmDialog(false);
                    this.closeNovelSettingsDialog();
                    const afterClose = this.novelSettingsCloseAfterClose;
                    this.novelSettingsCloseAfterClose = undefined;
                    if (afterClose) {
                      afterClose();
                    }
                  }
                })();
              })
          }
          .width('100%')
        }
        .width('100%')
      }
    }
  }

  @Builder
  buildNovelSettingsDialog() {
    if (this.showNovelSettingsDialog && this.content && this.canUseNovelStyleSettingsDialog()) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          void this.requestCloseNovelSettingsDialog();
        },
        dialogWidth: '90%',
        maxWidth: 400,
        contentPadding: 24,
        zIndexValue: 120,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {

          Row() {
            Text(this.isNovelSettingsDialogForLocalEBook() ? '电子书设置' : '小说设置')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Blank()

            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                  this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              void this.requestCloseNovelSettingsDialog();
            })
          }
          .width('100%')

          Row({ space: 8 }) {
            if (this.isNovelSettingsDialogForLocalEBook()) {
              this.buildNovelSettingsTabButton('净化规则', 0)
              this.buildNovelSettingsTabButton('信息修改', 1)
            } else {
              this.buildNovelSettingsTabButton('预下载', 0)
              this.buildNovelSettingsTabButton('目录解析', 1)
              this.buildNovelSettingsTabButton('净化规则', 2)
            }
          }
          .width('100%')
          .padding(4)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
            this.themeState.currentTheme))
          .borderRadius(18)

          Scroll() {
            Column({ space: 12 }) {
              if (this.isNovelSettingsDialogForLocalEBook()) {
                if (this.novelSettingsActiveTab === 0) {
                  this.buildNovelReplaceRuleSettingsTab()
                } else {
                  this.buildEBookInfoEditTab()
                }
              } else {
                if (this.novelSettingsActiveTab === 0) {
                  this.buildNovelPrefetchSettingsTab()
                } else if (this.novelSettingsActiveTab === 1) {
                  this.buildNovelDirectorySettingsTab()
                } else {
                  this.buildNovelReplaceRuleSettingsTab()
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: 420 })
          .scrollBar(BarState.Auto)
        }
        .width('100%')
      }
    }
  }


  build() {
    if (this.isNovelSettingsCloseConfirmDialogVisible) {
      this.buildNovelSettingsCloseConfirmDialog()
    } else if (this.showNovelSettingsDialog && this.content && this.canUseNovelStyleSettingsDialog()) {
      this.buildNovelSettingsDialog()
    } else if (this.trackingLoadSignal > 0) {
      TrackingSettingsDialogComponent({
        content: this.content,
        themeState: this.themeState,
        loadSignal: this.trackingLoadSignal,
        onNavigate: (pageName: string, params: object | null) => {
          this.onNavigate?.(pageName, params);
        },
        getCurrentNovelSourceId: () => this.getCurrentNovelSourceId?.() ?? '',
        isCurrentLocalImportedContent: () => this.isCurrentLocalImportedContent?.() ?? false,
        isLocalImportedEBookContent: () => this.isLocalImportedEBookContent?.() ?? false,
        getNovelCacheBookId: (sourceId: string, bookUrl: string) => this.getNovelCacheBookId?.(sourceId, bookUrl) ?? '',
        onTrackingStateChanged: (state: ContentTrackingCardState, callbacks: ContentTrackingCardCallbacks) => {
          this.trackingCardState = state;
          this.trackingCardCallbacks = callbacks;
        }
      })
    } else {
      Column()
    }
  }
}
