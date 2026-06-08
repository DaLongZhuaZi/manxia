/**
 * 文件编辑器服务
 * 提供文件读写、搜索、替换等功能
 * 可作为工具被其他模块调用
 */

import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
// 导入util模块
import { util } from '@kit.ArkTS';
import { SourceManager } from '../Source/SourceManager';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { LegadoSourceImportResult } from '../Novel/LegadoSourceTypes';

const TAG = 'FileEditorService';

/**
 * 文件信息
 */
export interface FileInfo {
  path: string;
  name: string;
  extension: string;
  size: number;
  isDirectory: boolean;
  modifiedTime: number;
}

/**
 * 搜索结果
 */
export interface SearchResult {
  line: number;
  column: number;
  text: string;
  match: string;
}

/**
 * 替换结果
 */
export interface ReplaceResult {
  success: boolean;
  replacedCount: number;
  newContent: string;
}

/**
 * 文件编辑器打开来源
 */
export enum FileEditorOpenSource {
  MANUAL = 'manual',
  MANGA_SOURCE = 'mangaSource',
  NOVEL_SOURCE = 'novelSource',
  EXTERNAL_IMPORT = 'externalImport',
  DEBUG_TOOL = 'debugTool',
  APP_INTERNAL = 'appInternal'
}

/**
 * 文件编辑器保存目标
 */
export enum FileEditorSaveTargetType {
  NONE = 'none',
  FILE_PATH = 'filePath',
  EXTERNAL_DOCUMENT = 'externalDocument',
  MANGA_SOURCE = 'mangaSource',
  NOVEL_SOURCE = 'novelSource',
  APP_CONFIG = 'appConfig'
}

/**
 * 文件编辑器能力检查状态
 */
export enum FileEditorFeatureStatus {
  READY = 'ready',
  PARTIAL = 'partial',
  UNAVAILABLE = 'unavailable'
}

/**
 * 保存目标上下文
 */
export interface FileEditorSaveTarget {
  type: FileEditorSaveTargetType;
  id?: string;
  name?: string;
  path?: string;
  pkg?: string;
  originalUri?: string;
  shouldApplyToApp?: boolean;
}

/**
 * 打开文件编辑器参数
 */
export interface FileEditorOpenParams {
  instanceId?: string;
  sessionId?: string;
  hostMode?: string;
  filePath?: string;
  content?: string;
  language?: string;
  readOnly?: boolean;
  title?: string;
  origin?: FileEditorOpenSource;
  saveTarget?: FileEditorSaveTarget;
}

/**
 * 独立编辑会话信息
 */
export interface FileEditorSessionInfo {
  instanceId: string;
  sessionId: string;
  createdAt: number;
  updatedAt: number;
  origin: FileEditorOpenSource;
  title: string;
  saveTarget: FileEditorSaveTarget;
}

/**
 * 联动保存结果
 */
export interface FileEditorLinkedSaveResult {
  success: boolean;
  targetType: FileEditorSaveTargetType;
  message: string;
  affectedId: string;
  affectedName: string;
}

/**
 * 文件编辑器功能检查项
 */
export interface FileEditorFeatureCheck {
  key: string;
  title: string;
  status: FileEditorFeatureStatus;
  detail: string;
}

/**
 * 文件编辑器功能检查报告
 */
export interface FileEditorFeatureAudit {
  sessionId: string;
  checkedAt: number;
  readyCount: number;
  partialCount: number;
  unavailableCount: number;
  items: FileEditorFeatureCheck[];
}

/**
 * 文件编辑器标签快照
 */
export interface FileEditorTabSnapshot {
  id: string;
  filePath: string;
  fileName: string;
  content: string;
  originalContent: string;
  language: string;
  isDirty: boolean;
  isReadOnly: boolean;
  origin: FileEditorOpenSource;
  saveTarget: FileEditorSaveTarget;
}

/**
 * 文件编辑器页面实例快照
 */
export interface FileEditorPageState {
  instanceId: string;
  sessionId: string;
  origin: FileEditorOpenSource;
  saveTarget: FileEditorSaveTarget;
  filePath: string;
  fileName: string;
  content: string;
  originalContent: string;
  language: string;
  isReadOnly: boolean;
  isDirty: boolean;
  editMode: string;
  showSearchBar: boolean;
  searchText: string;
  replaceText: string;
  currentSearchIndex: number;
  tabs: FileEditorTabSnapshot[];
  activeTabId: string;
}

/**
 * 文件编辑器服务类
 */
export class FileEditorService {
  private static instance: FileEditorService;
  private sessions: Map<string, FileEditorSessionInfo> = new Map<string, FileEditorSessionInfo>();
  private pageStates: Map<string, FileEditorPageState> = new Map<string, FileEditorPageState>();
  private sequence: number = 0;
  
  private constructor() {}
  
  public static getInstance(): FileEditorService {
    if (!FileEditorService.instance) {
      FileEditorService.instance = new FileEditorService();
    }
    return FileEditorService.instance;
  }

  /**
   * 创建独立编辑会话
   */
  public createSession(params: FileEditorOpenParams): FileEditorSessionInfo {
    const now = Date.now();
    const instanceId = params.instanceId && params.instanceId.length > 0
      ? params.instanceId
      : this.createInstanceId();
    const sessionId = params.sessionId && params.sessionId.length > 0
      ? params.sessionId
      : instanceId;
    const saveTarget = this.normalizeSaveTarget(params.saveTarget, params.filePath);
    const session: FileEditorSessionInfo = {
      instanceId: instanceId,
      sessionId: sessionId,
      createdAt: now,
      updatedAt: now,
      origin: params.origin ?? FileEditorOpenSource.MANUAL,
      title: params.title ?? this.getNameFromPath(params.filePath ?? '未命名'),
      saveTarget: saveTarget
    };
    this.sessions.set(sessionId, session);
    logger.info(TAG, `创建文件编辑器独立会话: instance=${instanceId}, session=${sessionId}, origin=${session.origin}, title=${session.title}`);
    return session;
  }

  /**
   * 生成新的编辑器实例标识
   */
  public createInstanceId(): string {
    this.sequence++;
    return `file_editor_${Date.now()}_${this.sequence}`;
  }

  /**
   * 获取会话信息
   */
  public getSession(sessionId: string): FileEditorSessionInfo | null {
    const session = this.sessions.get(sessionId);
    return session ? session : null;
  }

  /**
   * 标记会话更新时间
   */
  public touchSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      const updated: FileEditorSessionInfo = {
        instanceId: session.instanceId,
        sessionId: session.sessionId,
        createdAt: session.createdAt,
        updatedAt: Date.now(),
        origin: session.origin,
        title: session.title,
        saveTarget: session.saveTarget
      };
      this.sessions.set(sessionId, updated);
    }
  }

  /**
   * 结束编辑会话
   */
  public closeSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (this.sessions.delete(sessionId)) {
      if (session) {
        this.pageStates.delete(session.instanceId);
      }
      this.pageStates.delete(sessionId);
      logger.info(TAG, `关闭文件编辑器会话: ${sessionId}`);
    }
  }

  /**
   * 保存页面实例快照
   */
  public savePageState(state: FileEditorPageState): void {
    if (state.instanceId.length === 0) {
      return;
    }
    this.pageStates.set(state.instanceId, this.clonePageState(state));
  }

  /**
   * 获取页面实例快照
   */
  public getPageState(instanceId: string): FileEditorPageState | null {
    const state = this.pageStates.get(instanceId);
    return state ? this.clonePageState(state) : null;
  }

  /**
   * 创建保存目标
   */
  public createSaveTarget(type: FileEditorSaveTargetType, id: string = '', name: string = '', path: string = '',
    pkg: string = '', originalUri: string = '', shouldApplyToApp: boolean = false): FileEditorSaveTarget {
    const target: FileEditorSaveTarget = {
      type: type,
      id: id,
      name: name,
      path: path,
      pkg: pkg,
      originalUri: originalUri,
      shouldApplyToApp: shouldApplyToApp
    };
    return target;
  }

  /**
   * 标准化保存目标
   */
  public normalizeSaveTarget(target: FileEditorSaveTarget | undefined, filePath: string | undefined): FileEditorSaveTarget {
    if (target) {
      const normalized: FileEditorSaveTarget = {
        type: target.type,
        id: target.id ?? '',
        name: target.name ?? '',
        path: target.path ?? filePath ?? '',
        pkg: target.pkg ?? '',
        originalUri: target.originalUri ?? '',
        shouldApplyToApp: target.shouldApplyToApp ?? false
      };
      return normalized;
    }

    if (filePath && filePath.length > 0) {
      return this.createSaveTarget(FileEditorSaveTargetType.FILE_PATH, '', this.getNameFromPath(filePath), filePath);
    }

    return this.createSaveTarget(FileEditorSaveTargetType.NONE);
  }

  /**
   * 对编辑器功能完整性进行检查
   */
  public auditCapabilities(sessionId: string, language: string, readOnly: boolean, saveTarget: FileEditorSaveTarget,
    hasFilePath: boolean, tabCount: number): FileEditorFeatureAudit {
    const items: FileEditorFeatureCheck[] = [];
    items.push(this.createFeatureCheck('isolatedSession', '独立编辑会话',
      sessionId.length > 0 ? FileEditorFeatureStatus.READY : FileEditorFeatureStatus.UNAVAILABLE,
      sessionId.length > 0 ? `session=${sessionId}` : '缺少独立会话标识'));
    items.push(this.createFeatureCheck('coreEditing', '核心编辑能力', readOnly ? FileEditorFeatureStatus.PARTIAL : FileEditorFeatureStatus.READY,
      readOnly ? '只读模式可查看、搜索、导出' : '可编辑、撤销、重做、格式化、搜索替换'));
    items.push(this.createFeatureCheck('filePersistence', '文件保存能力',
      hasFilePath || saveTarget.type !== FileEditorSaveTargetType.NONE ? FileEditorFeatureStatus.READY : FileEditorFeatureStatus.PARTIAL,
      hasFilePath ? '可直接写回文件路径' : '无原始路径时使用另存为或应用联动保存'));
    items.push(this.createFeatureCheck('importExport', '导入导出能力', FileEditorFeatureStatus.READY,
      '支持系统文档选择器导入与另存为导出'));
    items.push(this.createFeatureCheck('markdownPreview', 'Markdown预览能力',
      language === 'markdown' ? FileEditorFeatureStatus.READY : FileEditorFeatureStatus.PARTIAL,
      language === 'markdown' ? '当前文件启用编辑/预览/分屏' : '仅 Markdown 文件启用实时预览'));
    items.push(this.createFeatureCheck('multiTab', '多标签能力',
      tabCount > 1 ? FileEditorFeatureStatus.READY : FileEditorFeatureStatus.PARTIAL,
      tabCount > 1 ? `当前打开 ${tabCount} 个标签` : '支持在同一会话内继续导入或新建标签'));
    items.push(this.createFeatureCheck('appLinkage', '应用联动能力',
      saveTarget.shouldApplyToApp === true ? FileEditorFeatureStatus.READY : FileEditorFeatureStatus.PARTIAL,
      saveTarget.shouldApplyToApp === true ? `保存后联动: ${saveTarget.type}` : '普通文件编辑不会触发业务联动'));

    let readyCount = 0;
    let partialCount = 0;
    let unavailableCount = 0;
    for (const item of items) {
      if (item.status === FileEditorFeatureStatus.READY) {
        readyCount++;
      } else if (item.status === FileEditorFeatureStatus.PARTIAL) {
        partialCount++;
      } else {
        unavailableCount++;
      }
    }

    const audit: FileEditorFeatureAudit = {
      sessionId: sessionId,
      checkedAt: Date.now(),
      readyCount: readyCount,
      partialCount: partialCount,
      unavailableCount: unavailableCount,
      items: items
    };
    logger.info(TAG, `文件编辑器功能检查: session=${sessionId}, ready=${readyCount}, partial=${partialCount}, unavailable=${unavailableCount}`);
    return audit;
  }

  /**
   * 保存后执行应用联动
   */
  public async applyLinkedSave(saveTarget: FileEditorSaveTarget, content: string): Promise<FileEditorLinkedSaveResult> {
    if (saveTarget.shouldApplyToApp !== true) {
      return this.createLinkedSaveResult(true, saveTarget.type, '无需应用联动', saveTarget.id ?? '', saveTarget.name ?? '');
    }

    if (saveTarget.type === FileEditorSaveTargetType.MANGA_SOURCE) {
      const sourceManager = SourceManager.getInstance();
      const result = await sourceManager.importFromJSON(content);
      if (result.success) {
        sourceManager.clearCache();
        return this.createLinkedSaveResult(true, saveTarget.type, `图源配置已应用: ${result.sourceName ?? saveTarget.name ?? ''}`,
          result.sourceId !== undefined ? `${result.sourceId}` : saveTarget.id ?? '', result.sourceName ?? saveTarget.name ?? '');
      }
      return this.createLinkedSaveResult(false, saveTarget.type, result.error ?? '图源配置应用失败',
        saveTarget.id ?? '', saveTarget.name ?? '');
    }

    if (saveTarget.type === FileEditorSaveTargetType.NOVEL_SOURCE) {
      const novelSourceManager = getNovelSourceManager();
      const results: LegadoSourceImportResult[] = await novelSourceManager.importFromJSON(content, true);
      let successCount = 0;
      let firstName = saveTarget.name ?? '';
      for (const result of results) {
        if (result.success) {
          successCount++;
          if (firstName.length === 0 && result.sourceName) {
            firstName = result.sourceName;
          }
        }
      }
      if (successCount > 0) {
        return this.createLinkedSaveResult(true, saveTarget.type, `书源配置已应用: ${successCount} 个`,
          saveTarget.id ?? '', firstName);
      }
      const firstError = results.length > 0 ? results[0].error ?? '书源配置应用失败' : '未解析到有效书源';
      return this.createLinkedSaveResult(false, saveTarget.type, firstError, saveTarget.id ?? '', firstName);
    }

    return this.createLinkedSaveResult(true, saveTarget.type, '保存完成', saveTarget.id ?? '', saveTarget.name ?? '');
  }
  
  /**
   * 读取文件内容
   */
  public async readFile(filePath: string): Promise<string> {
    try {
      logger.info(TAG, `读取文件: ${filePath}`);
      
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      const buffer = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buffer);
      await fileIo.close(file.fd);
      
      const decoder = new util.TextDecoder('utf-8');
      const content = decoder.decodeToString(new Uint8Array(buffer));
      
      logger.info(TAG, `文件读取成功，大小: ${stat.size} bytes`);
      return content;
    } catch (e) {
      logger.error(TAG, `读取文件失败: ${e}`);
      throw new Error(`读取文件失败: ${e}`);
    }
  }

  private getNameFromPath(path: string): string {
    if (path.length === 0) {
      return '未命名';
    }
    const normalized = path.replace(/\\/g, '/');
    const parts = normalized.split('/');
    const last = parts.length > 0 ? parts[parts.length - 1] : '';
    return last.length > 0 ? decodeURIComponent(last) : '未命名';
  }

  private createFeatureCheck(key: string, title: string, status: FileEditorFeatureStatus, detail: string): FileEditorFeatureCheck {
    const item: FileEditorFeatureCheck = {
      key: key,
      title: title,
      status: status,
      detail: detail
    };
    return item;
  }

  private createLinkedSaveResult(success: boolean, targetType: FileEditorSaveTargetType, message: string,
    affectedId: string, affectedName: string): FileEditorLinkedSaveResult {
    const result: FileEditorLinkedSaveResult = {
      success: success,
      targetType: targetType,
      message: message,
      affectedId: affectedId,
      affectedName: affectedName
    };
    return result;
  }

  private cloneSaveTarget(target: FileEditorSaveTarget): FileEditorSaveTarget {
    return {
      type: target.type,
      id: target.id ?? '',
      name: target.name ?? '',
      path: target.path ?? '',
      pkg: target.pkg ?? '',
      originalUri: target.originalUri ?? '',
      shouldApplyToApp: target.shouldApplyToApp ?? false
    };
  }

  private cloneTabSnapshot(tab: FileEditorTabSnapshot): FileEditorTabSnapshot {
    return {
      id: tab.id,
      filePath: tab.filePath,
      fileName: tab.fileName,
      content: tab.content,
      originalContent: tab.originalContent,
      language: tab.language,
      isDirty: tab.isDirty,
      isReadOnly: tab.isReadOnly,
      origin: tab.origin,
      saveTarget: this.cloneSaveTarget(tab.saveTarget)
    };
  }

  private clonePageState(state: FileEditorPageState): FileEditorPageState {
    const tabs: FileEditorTabSnapshot[] = [];
    for (const tab of state.tabs) {
      tabs.push(this.cloneTabSnapshot(tab));
    }
    return {
      instanceId: state.instanceId,
      sessionId: state.sessionId,
      origin: state.origin,
      saveTarget: this.cloneSaveTarget(state.saveTarget),
      filePath: state.filePath,
      fileName: state.fileName,
      content: state.content,
      originalContent: state.originalContent,
      language: state.language,
      isReadOnly: state.isReadOnly,
      isDirty: state.isDirty,
      editMode: state.editMode,
      showSearchBar: state.showSearchBar,
      searchText: state.searchText,
      replaceText: state.replaceText,
      currentSearchIndex: state.currentSearchIndex,
      tabs: tabs,
      activeTabId: state.activeTabId
    };
  }
  
  /**
   * 写入文件内容
   */
  public async writeFile(filePath: string, content: string): Promise<boolean> {
    try {
      logger.info(TAG, `写入文件: ${filePath}`);
      
      const encoder = new util.TextEncoder();
      const buffer = encoder.encodeInto(content);
      
      const file = await fileIo.open(filePath, 
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, buffer.buffer);
      await fileIo.close(file.fd);
      
      logger.info(TAG, `文件写入成功，大小: ${buffer.buffer.byteLength} bytes`);
      return true;
    } catch (e) {
      logger.error(TAG, `写入文件失败: ${e}`);
      throw new Error(`写入文件失败: ${e}`);
    }
  }
  
  /**
   * 获取文件信息
   */
  public async getFileInfo(filePath: string): Promise<FileInfo> {
    try {
      const stat = await fileIo.stat(filePath);
      const name = filePath.split('/').pop() || '';
      const extension = name.includes('.') ? name.split('.').pop() || '' : '';
      
      return {
        path: filePath,
        name: name,
        extension: extension.toLowerCase(),
        size: stat.size,
        isDirectory: stat.isDirectory(),
        modifiedTime: stat.mtime
      };
    } catch (e) {
      logger.error(TAG, `获取文件信息失败: ${e}`);
      throw new Error(`获取文件信息失败: ${e}`);
    }
  }
  
  /**
   * 检查文件是否存在
   */
  public async fileExists(filePath: string): Promise<boolean> {
    try {
      await fileIo.access(filePath);
      return true;
    } catch {
      return false;
    }
  }
  
  /**
   * 创建文件
   */
  public async createFile(filePath: string, content: string = ''): Promise<boolean> {
    try {
      logger.info(TAG, `创建文件: ${filePath}`);
      
      // 确保目录存在
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      await this.ensureDirectory(dirPath);
      
      return await this.writeFile(filePath, content);
    } catch (e) {
      logger.error(TAG, `创建文件失败: ${e}`);
      throw new Error(`创建文件失败: ${e}`);
    }
  }
  
  /**
   * 删除文件
   */
  public async deleteFile(filePath: string): Promise<boolean> {
    try {
      logger.info(TAG, `删除文件: ${filePath}`);
      await fileIo.unlink(filePath);
      logger.info(TAG, '文件删除成功');
      return true;
    } catch (e) {
      logger.error(TAG, `删除文件失败: ${e}`);
      throw new Error(`删除文件失败: ${e}`);
    }
  }
  
  /**
   * 重命名/移动文件
   */
  public async renameFile(oldPath: string, newPath: string): Promise<boolean> {
    try {
      logger.info(TAG, `重命名文件: ${oldPath} -> ${newPath}`);
      await fileIo.rename(oldPath, newPath);
      logger.info(TAG, '文件重命名成功');
      return true;
    } catch (e) {
      logger.error(TAG, `重命名文件失败: ${e}`);
      throw new Error(`重命名文件失败: ${e}`);
    }
  }
  
  /**
   * 复制文件
   */
  public async copyFile(srcPath: string, destPath: string): Promise<boolean> {
    try {
      logger.info(TAG, `复制文件: ${srcPath} -> ${destPath}`);
      await fileIo.copyFile(srcPath, destPath);
      logger.info(TAG, '文件复制成功');
      return true;
    } catch (e) {
      logger.error(TAG, `复制文件失败: ${e}`);
      throw new Error(`复制文件失败: ${e}`);
    }
  }
  
  /**
   * 确保目录存在
   */
  public async ensureDirectory(dirPath: string): Promise<void> {
    try {
      await fileIo.access(dirPath);
    } catch {
      await fileIo.mkdir(dirPath, true);
      logger.info(TAG, `创建目录: ${dirPath}`);
    }
  }
  
  /**
   * 列出目录内容
   */
  public async listDirectory(dirPath: string): Promise<FileInfo[]> {
    try {
      const entries = await fileIo.listFile(dirPath);
      const files: FileInfo[] = [];
      
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        try {
          const info = await this.getFileInfo(fullPath);
          files.push(info);
        } catch {
          // 忽略无法访问的文件
        }
      }
      
      // 排序：目录在前，文件在后，按名称排序
      files.sort((a, b) => {
        if (a.isDirectory !== b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.localeCompare(b.name);
      });
      
      return files;
    } catch (e) {
      logger.error(TAG, `列出目录失败: ${e}`);
      throw new Error(`列出目录失败: ${e}`);
    }
  }
  
  /**
   * 在文件内容中搜索
   */
  public searchInContent(content: string, searchText: string, caseSensitive: boolean = false, useRegex: boolean = false): SearchResult[] {
    const results: SearchResult[] = [];
    const lines = content.split('\n');
    
    let pattern: RegExp;
    if (useRegex) {
      try {
        pattern = new RegExp(searchText, caseSensitive ? 'g' : 'gi');
      } catch {
        logger.error(TAG, '无效的正则表达式');
        return results;
      }
    } else {
      const escaped = searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      pattern = new RegExp(escaped, caseSensitive ? 'g' : 'gi');
    }
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let match: RegExpExecArray | null;
      
      while ((match = pattern.exec(line)) !== null) {
        results.push({
          line: i + 1,
          column: match.index + 1,
          text: line,
          match: match[0]
        });
        
        // 防止无限循环（对于空匹配）
        if (match.index === pattern.lastIndex) {
          pattern.lastIndex++;
        }
      }
    }
    
    logger.info(TAG, `搜索完成，找到 ${results.length} 个结果`);
    return results;
  }
  
  /**
   * 替换文件内容
   */
  public replaceInContent(content: string, searchText: string, replaceText: string, 
    caseSensitive: boolean = false, useRegex: boolean = false, replaceAll: boolean = true): ReplaceResult {
    
    let pattern: RegExp;
    if (useRegex) {
      try {
        pattern = new RegExp(searchText, caseSensitive ? (replaceAll ? 'g' : '') : (replaceAll ? 'gi' : 'i'));
      } catch {
        logger.error(TAG, '无效的正则表达式');
        return { success: false, replacedCount: 0, newContent: content };
      }
    } else {
      const escaped = searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      pattern = new RegExp(escaped, caseSensitive ? (replaceAll ? 'g' : '') : (replaceAll ? 'gi' : 'i'));
    }
    
    let replacedCount = 0;
    const newContent = content.replace(pattern, (match) => {
      replacedCount++;
      return replaceText;
    });
    
    logger.info(TAG, `替换完成，替换了 ${replacedCount} 处`);
    return {
      success: replacedCount > 0,
      replacedCount: replacedCount,
      newContent: newContent
    };
  }
  
  /**
   * 根据文件扩展名获取语言类型
   */
  public getLanguageByExtension(extension: string): string {
    const ext = extension.toLowerCase();
    switch (ext) {
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'ts':
      case 'tsx':
      case 'ets':
      case 'ark':
        return 'typescript';
      case 'json':
        return 'json';
      case 'xml':
        return 'xml';
      case 'html':
      case 'htm':
        return 'html';
      case 'css':
        return 'css';
      case 'scss':
        return 'scss';
      case 'less':
        return 'less';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'py':
        return 'python';
      case 'java':
        return 'java';
      case 'kt':
        return 'kotlin';
      case 'c':
      case 'h':
        return 'c';
      case 'cpp':
      case 'hpp':
        return 'cpp';
      case 'cs':
        return 'csharp';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'swift':
        return 'swift';
      case 'rb':
        return 'ruby';
      case 'php':
        return 'php';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
        return 'shell';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'toml':
      case 'ini':
      case 'conf':
        return 'ini';
      case 'txt':
      case 'log':
        return 'plaintext';
      default:
        return 'plaintext';
    }
  }
  
  /**
   * 检查是否为文本文件
   */
  public isTextFile(extension: string): boolean {
    const textExtensions = [
      'txt', 'md', 'markdown', 'json', 'xml', 'html', 'htm', 'css', 'scss', 'less',
      'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'cs',
      'go', 'rs', 'swift', 'rb', 'php', 'sql', 'sh', 'bash', 'yaml', 'yml', 'toml',
      'ini', 'conf', 'log', 'ets', 'ark', 'vue', 'svelte', 'astro'
    ];
    return textExtensions.includes(extension.toLowerCase());
  }
}



// 导出单例
export const fileEditorService = FileEditorService.getInstance();
