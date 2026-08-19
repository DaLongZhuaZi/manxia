import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { ComicSourceDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { DataManager } from '../Data/DataManager';
import { SourceManager, ImportResult } from '../Source/SourceManager';
import { Action, MangaSourceSettings } from '../WebView/MangaSourceTypes';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { SourceConfigValidator } from './SourceConfigValidator';
import { sourceDraftStore } from './SourceDraftStore';
import { sourceMaintenanceManager } from '../Source/SourceMaintenanceManager';
import {
  DomSelectionSnapshot,
  RuleFieldMapping,
  SourceEditorDraft,
  SourceEditorMode,
  SourceEditorSaveResult,
  SourceEditorTaskType,
  SourceEditorVersionSnapshot,
  SourceInteractiveEditorPageParams,
  SourceSaveMode,
  SourceValidationResult
} from './SourceEditorTypes';
import { SourceRuleGenerator } from './SourceRuleGenerator';

const TAG = 'InteractiveSourceEditorService';

interface SourceEditorRawMetadata {
  id?: string;
  name?: string;
  version?: string;
  author?: string;
  description?: string;
  baseUrl?: string;
  language?: string;
  type?: string;
  created?: string;
  updated?: string;
}

interface SourceEditorRawWorkflows {
  initialize?: Object;
  login?: Object;
  search?: Object;
  directSearch?: Object;
  getMangaDetail?: Object;
  getChapterList?: Object;
  getPageList?: Object;
  popular?: Object;
  latest?: Object;
  filter?: Object;
  getCategory?: Object;
  getBookDetail?: Object;
}

interface SourceEditorRawConfig {
  metadata: SourceEditorRawMetadata;
  settings?: MangaSourceSettings;
  capabilities?: Object;
  network?: Object;
  workflows: SourceEditorRawWorkflows;
  searchConfig?: Object;
  variables?: Object;
  retry?: Object;
  fallback?: Object;
  cache?: Object;
  concurrency?: Object;
  debug?: Object;
  screenshot?: Object;
  performance?: Object;
  validation?: Object;
  authentication?: Object;
  customActions?: Object;
  plugins?: Object;
  antiCrawler?: Object;
  api?: Object;
  tabs?: Object;
}

export class InteractiveSourceEditorService {
  private static instance: InteractiveSourceEditorService | null = null;
  private readonly dataManager: DataManager = DataManager.getInstance();
  private readonly sourceManager: SourceManager = SourceManager.getInstance();
  private readonly webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private readonly ruleGenerator: SourceRuleGenerator = new SourceRuleGenerator();
  private readonly validator: SourceConfigValidator = new SourceConfigValidator();
  private abilityContext: common.UIAbilityContext | null = null;

  private constructor() {}

  public static getInstance(): InteractiveSourceEditorService {
    if (!InteractiveSourceEditorService.instance) {
      InteractiveSourceEditorService.instance = new InteractiveSourceEditorService();
    }
    return InteractiveSourceEditorService.instance;
  }

  public setAbilityContext(context: common.UIAbilityContext | null): void {
    this.abilityContext = context;
  }

  public async createDraft(params: SourceInteractiveEditorPageParams): Promise<SourceEditorDraft> {
    let configJson: string = '';
    let sourceName: string = params.sourceName || '新建图源';
    let sourcePkg: string = params.sourcePkg || '';
    let initialUrl: string = params.initialUrl || '';

    if (!params.createNew && params.sourceId > 0) {
      const record: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(params.sourceId);
      if (record) {
        configJson = record.configJson || '';
        sourceName = record.name || sourceName;
        sourcePkg = record.pkg || sourcePkg;
        if (initialUrl.length <= 0) {
          initialUrl = record.baseUrl || '';
        }
      }
    }

    if (configJson.trim().length <= 0) {
      configJson = this.buildEmptyConfigJson(sourcePkg, sourceName, initialUrl);
      sourcePkg = this.resolveConfigPkg(configJson, sourcePkg);
    } else if (sourcePkg.length <= 0) {
      sourcePkg = this.resolveConfigPkg(configJson, sourcePkg);
    }

    const draft: SourceEditorDraft = {
      draftId: `draft_${Date.now()}_${Math.floor(Math.random() * 1000000)}`,
      sourceId: params.sourceId,
      sourceName: sourceName,
      sourcePkg: sourcePkg,
      mode: SourceEditorMode.SIMPLE,
      taskType: SourceEditorTaskType.SEARCH,
      testUrl: initialUrl,
      configJson: configJson,
      generatedWorkflowJson: '',
      fieldMappings: [],
      createTime: Date.now(),
      updateTime: Date.now()
    };
    sourceDraftStore.saveDraft(draft);
    return draft;
  }

  public applySelectionToDraft(
    draft: SourceEditorDraft,
    selection: DomSelectionSnapshot,
    taskType: SourceEditorTaskType,
    testUrl: string
  ): SourceEditorDraft {
    const mappings: RuleFieldMapping[] = this.ruleGenerator.buildDefaultMappings(selection);
    const actions: Action[] = this.ruleGenerator.buildActions(taskType, testUrl, selection, mappings);
    draft.taskType = taskType;
    draft.testUrl = testUrl;
    draft.lastSelection = selection;
    draft.fieldMappings = mappings;
    draft.generatedWorkflowJson = JSON.stringify(actions, null, 2);
    draft.configJson = this.applyWorkflowToConfigJson(draft.configJson, taskType, testUrl, actions);
    draft.sourcePkg = this.resolveConfigPkg(draft.configJson, draft.sourcePkg);
    draft.updateTime = Date.now();
    sourceDraftStore.saveDraft(draft);
    return draft;
  }

  public validateDraft(draft: SourceEditorDraft): SourceValidationResult {
    return this.validator.validate(draft.configJson);
  }

  public listSnapshots(draftId: string): SourceEditorVersionSnapshot[] {
    return sourceDraftStore.listSnapshots(draftId);
  }

  public rollbackSnapshot(draftId: string, snapshotId: string): SourceEditorDraft | null {
    return sourceDraftStore.rollbackSnapshot(draftId, snapshotId);
  }

  public async saveDraft(draft: SourceEditorDraft, saveMode: SourceSaveMode): Promise<SourceEditorSaveResult> {
    sourceDraftStore.createSnapshot(draft, `保存前快照: ${saveMode}`);
    const validation: SourceValidationResult = this.validator.validate(draft.configJson);
    if (!validation.valid) {
      return this.buildSaveFailure(validation.message, draft);
    }

    if (saveMode === SourceSaveMode.LOCAL_FORK) {
      return await this.saveAsLocalFork(draft);
    }
    if (saveMode === SourceSaveMode.OVERWRITE_INSTALLED) {
      return await this.overwriteInstalled(draft);
    }
    return this.exportPackage(draft);
  }

  private async saveAsLocalFork(draft: SourceEditorDraft): Promise<SourceEditorSaveResult> {
    const forkConfigJson: string = this.buildLocalForkConfigJson(draft.configJson, draft);
    const result: ImportResult = await this.sourceManager.importFromJSON(forkConfigJson);
    if (!result.success) {
      return this.buildSaveFailure(result.error || '本地派生副本保存失败', draft);
    }
    const pkg: string = this.resolveConfigPkg(forkConfigJson, draft.sourcePkg);
    const sourceName: string = result.sourceName || this.resolveConfigName(forkConfigJson, draft.sourceName);
    await this.markSourceMaintenance(
      result.sourceId || 0,
      pkg,
      sourceName,
      this.resolveConfigVersion(forkConfigJson, '1.0.0'),
      forkConfigJson,
      '由交互式图源编辑器保存为本地派生副本'
    );
    return {
      success: true,
      message: '已保存为本地派生图源',
      sourceId: result.sourceId || 0,
      sourceName: sourceName,
      sourcePkg: pkg,
      exportPath: ''
    };
  }

  private async overwriteInstalled(draft: SourceEditorDraft): Promise<SourceEditorSaveResult> {
    if (draft.sourceId <= 0) {
      return this.buildSaveFailure('新建图源不能直接覆盖，请先保存为本地派生副本', draft);
    }
    const result: ImportResult = await this.sourceManager.updateSourceFromJSON(draft.configJson, draft.sourceId);
    if (!result.success) {
      return this.buildSaveFailure(result.error || '覆盖原图源失败', draft);
    }
    this.webViewSourceManager.invalidateSourceRuntime(draft.sourceId, draft.sourceName);
    const pkg: string = this.resolveConfigPkg(draft.configJson, draft.sourcePkg);
    const sourceName: string = result.sourceName || draft.sourceName;
    await this.markSourceMaintenance(
      draft.sourceId,
      pkg,
      sourceName,
      this.resolveConfigVersion(draft.configJson, '1.0.0'),
      draft.configJson,
      '由交互式图源编辑器覆盖安装'
    );
    return {
      success: true,
      message: '已覆盖原图源并清理运行缓存',
      sourceId: draft.sourceId,
      sourceName: sourceName,
      sourcePkg: pkg,
      exportPath: ''
    };
  }

  private exportPackage(draft: SourceEditorDraft): SourceEditorSaveResult {
    if (!this.abilityContext) {
      return this.buildSaveFailure('无法获取应用目录，暂不能导出扩展包', draft);
    }
    const pkg: string = this.resolveConfigPkg(draft.configJson, draft.sourcePkg);
    const exportDir: string = `${this.abilityContext.filesDir}/source_exports/${pkg}`;
    const exportPath: string = `${exportDir}/source.json`;
    let file: fs.File | null = null;
    try {
      SafeFileUtils.mkdirSync(exportDir, true);
      file = SafeFileUtils.openSyncStrict(exportPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeStringExactSync(file.fd, draft.configJson);
      logger.info(TAG, `图源扩展包已导出: ${exportPath}`);
      return {
        success: true,
        message: '已导出 source.json',
        sourceId: draft.sourceId,
        sourceName: draft.sourceName,
        sourcePkg: pkg,
        exportPath: exportPath
      };
    } catch (error) {
      logger.error(TAG, `导出图源扩展包失败: ${String(error)}`);
      return this.buildSaveFailure(`导出失败: ${String(error)}`, draft);
    } finally {
      if (file) {
        SafeFileUtils.closeSync(file);
      }
    }
  }

  private buildEmptyConfigJson(sourcePkg: string, sourceName: string, initialUrl: string): string {
    const nowText: string = String(Date.now());
    const pkg: string = sourcePkg.length > 0 ? sourcePkg : `local.new.source.${Date.now()}`;
    const metadata: SourceEditorRawMetadata = {
      id: pkg,
      name: sourceName.length > 0 ? sourceName : '新建图源',
      version: '1.0.0',
      author: '',
      description: '',
      baseUrl: initialUrl,
      language: 'zh-CN',
      type: 'manga',
      created: nowText,
      updated: nowText
    };
    const settings: MangaSourceSettings = {
      timeout: 30000,
      retryCount: 3,
      enableJavaScript: true,
      enableImages: true,
      enableCookies: true,
      bypassCloudflare: false
    };
    const workflows: SourceEditorRawWorkflows = {};
    const config: SourceEditorRawConfig = {
      metadata: metadata,
      settings: settings,
      workflows: workflows
    };
    return JSON.stringify(config, null, 2);
  }

  private applyWorkflowToConfigJson(configJson: string, taskType: SourceEditorTaskType, testUrl: string, actions: Action[]): string {
    const config: SourceEditorRawConfig = this.parseRawConfig(configJson);
    if (!config.metadata) {
      config.metadata = this.parseRawConfig(this.buildEmptyConfigJson('', '新建图源', testUrl)).metadata;
    }
    if (!config.workflows) {
      const workflows: SourceEditorRawWorkflows = {};
      config.workflows = workflows;
    }
    if (config.metadata.baseUrl === undefined || config.metadata.baseUrl.length <= 0) {
      config.metadata.baseUrl = this.resolveBaseUrl(testUrl);
    }
    config.metadata.updated = String(Date.now());
    this.assignWorkflow(config.workflows, taskType, actions);
    return JSON.stringify(config, null, 2);
  }

  private assignWorkflow(workflows: SourceEditorRawWorkflows, taskType: SourceEditorTaskType, actions: Action[]): void {
    if (taskType === SourceEditorTaskType.SEARCH) {
      workflows.search = actions as Object;
      return;
    }
    if (taskType === SourceEditorTaskType.DETAIL) {
      workflows.getMangaDetail = actions as Object;
      return;
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      workflows.getChapterList = actions as Object;
      return;
    }
    workflows.getPageList = actions as Object;
  }

  private buildLocalForkConfigJson(configJson: string, draft: SourceEditorDraft): string {
    const config: SourceEditorRawConfig = this.parseRawConfig(configJson);
    const metadata: SourceEditorRawMetadata = config.metadata;
    const originalPkg: string = metadata.id || draft.sourcePkg || 'source';
    const timestamp: string = String(Date.now());
    const forkPkg: string = this.normalizePkg(`local.${originalPkg}.${timestamp}`);
    metadata.id = forkPkg;
    metadata.name = `${metadata.name || draft.sourceName} (本地编辑)`;
    metadata.version = metadata.version || '1.0.0';
    metadata.updated = timestamp;
    if (!metadata.created) {
      metadata.created = timestamp;
    }
    return JSON.stringify(config, null, 2);
  }

  private parseRawConfig(configJson: string): SourceEditorRawConfig {
    try {
      const config: SourceEditorRawConfig = SafeUtils.parseObj(configJson) as SourceEditorRawConfig;
      if (!config.metadata) {
        config.metadata = this.parseRawConfig(this.buildEmptyConfigJson('', '新建图源', '')).metadata;
      }
      if (!config.workflows) {
        const workflows: SourceEditorRawWorkflows = {};
        config.workflows = workflows;
      }
      return config;
    } catch (error) {
      logger.warn(TAG, `图源配置解析失败，创建空配置: ${String(error)}`);
      return SafeUtils.parseObj(this.buildEmptyConfigJson('', '新建图源', '')) as SourceEditorRawConfig;
    }
  }

  private resolveConfigPkg(configJson: string, fallback: string): string {
    try {
      const config: SourceEditorRawConfig = this.parseRawConfig(configJson);
      return config.metadata.id || fallback;
    } catch (_error) {
      return fallback;
    }
  }

  private resolveConfigName(configJson: string, fallback: string): string {
    try {
      const config: SourceEditorRawConfig = this.parseRawConfig(configJson);
      return config.metadata.name || fallback;
    } catch (_error) {
      return fallback;
    }
  }

  private resolveConfigVersion(configJson: string, fallback: string): string {
    try {
      const config: SourceEditorRawConfig = this.parseRawConfig(configJson);
      return config.metadata.version || fallback;
    } catch (_error) {
      return fallback;
    }
  }

  private async markSourceMaintenance(
    sourceId: number,
    pkg: string,
    sourceName: string,
    sourceVersion: string,
    configJson: string,
    notes: string
  ): Promise<void> {
    if (pkg.length <= 0) {
      return;
    }
    try {
      await sourceMaintenanceManager.markLocalFork(sourceId, pkg, sourceName, sourceVersion, configJson, notes);
    } catch (error) {
      logger.warn(TAG, `图源维护状态标记失败: pkg=${pkg}, error=${String(error)}`);
    }
  }

  private resolveBaseUrl(url: string): string {
    const trimmed: string = url.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    const schemeIndex: number = trimmed.indexOf('://');
    if (schemeIndex < 0) {
      return trimmed;
    }
    const pathIndex: number = trimmed.indexOf('/', schemeIndex + 3);
    if (pathIndex < 0) {
      return trimmed;
    }
    return trimmed.substring(0, pathIndex);
  }

  private normalizePkg(pkg: string): string {
    let output: string = '';
    for (let i = 0; i < pkg.length; i++) {
      const ch = pkg.charAt(i);
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch === '.' || ch === '_' || ch === '-') {
        output += ch;
      } else {
        output += '.';
      }
    }
    return output;
  }

  private buildSaveFailure(message: string, draft: SourceEditorDraft): SourceEditorSaveResult {
    return {
      success: false,
      message: message,
      sourceId: draft.sourceId,
      sourceName: draft.sourceName,
      sourcePkg: draft.sourcePkg,
      exportPath: ''
    };
  }
}

export const interactiveSourceEditorService = InteractiveSourceEditorService.getInstance();
