import { SafeFileUtils } from '../../Utils/SafeFileUtils';
/**
 * Download目录管理器
 * 管理应用在系统Download文件夹中的专属目录
 * 使用DocumentViewPicker的DOWNLOAD模式获取访问权限
 */

import { picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';
import { ISettingsManagerFacade, SettingsManagerHolder } from '../Contracts/ISettingsManagerFacade';
import { SettingKeys } from '../Contracts/SettingKeys';

const TAG = 'DownloadDirManager';
const DOWNLOAD_SYNC_DIR_PATH_KEY = 'downloadSyncDirPath';
const DOWNLOAD_SYNC_DIR_URI_KEY = 'downloadSyncDirUri';
const MANXIA_DOWNLOAD_APP_DIR = 'com.dlzz.manxia';

/**
 * Download目录信息
 */
export interface DownloadDirInfo {
  path: string;      // 文件系统路径
  uri: string;       // URI（用于后续访问）
  isInitialized: boolean;
}

export interface DownloadPathProbeResult {
  path: string;
  exists: boolean;
  isDirectory: boolean;
  isFile: boolean;
  fileSize: number;
}

export interface OnlineMangaArchivePathRequest {
  sourceId: string;
  sourceName: string;
  sourcePkg: string;
  mangaTitle: string;
  chapterTitle: string;
  chapterId: string;
  chapterNumber?: string;
  externalChapterId: string;
  storedArchivePath?: string;
}

export interface OnlineMangaArchiveLookupResult {
  archivePath: string;
  matchedBy: string;
  candidates: string[];
}

/**
 * Download目录管理器单例
 */
export class DownloadDirManager {
  private static instance: DownloadDirManager;
  private context: common.UIAbilityContext | null = null;
  private downloadDirPath: string = '';
  private downloadDirUri: string = '';
  private isInitialized: boolean = false;
  private initPromise: Promise<boolean> | null = null;

  private constructor() {
    logger.info(TAG, 'Download目录管理器初始化');
  }

  public static getInstance(): DownloadDirManager {
    if (!DownloadDirManager.instance) {
      DownloadDirManager.instance = new DownloadDirManager();
    }
    return DownloadDirManager.instance;
  }

  /**
   * 设置应用上下文
   */
  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
    this.restorePersistedDirInfo();
    logger.info(TAG, '应用上下文已设置');
  }

  /**
   * 获取Download目录信息
   */
  public getDirInfo(): DownloadDirInfo {
    return {
      path: this.downloadDirPath,
      uri: this.downloadDirUri,
      isInitialized: this.isInitialized
    };
  }

  /**
   * 检查是否已初始化
   */
  public isReady(): boolean {
    if (this.isInitialized && this.downloadDirPath !== '') {
      return true;
    }
    return this.restorePersistedDirInfo();
  }

  /**
   * 获取Download目录路径
   */
  public getPath(): string {
    return this.downloadDirPath;
  }

  /**
   * 获取应用专属Download根目录。
   * 如果用户授权的是系统Download根目录，则实际业务目录为 Download/com.dlzz.manxia。
   */
  public getManagedRootPath(ensureExists: boolean = false): string {
    if (!this.isReady()) {
      return '';
    }
    const rawRoot = this.normalizeDirectoryPath(this.downloadDirPath);
    if (rawRoot.length <= 0) {
      return '';
    }
    const root = this.pathEndsWithSegment(rawRoot, MANXIA_DOWNLOAD_APP_DIR)
      ? rawRoot
      : `${rawRoot}/${MANXIA_DOWNLOAD_APP_DIR}`;
    if (ensureExists) {
      this.ensureAbsoluteDirectory(root);
    }
    return root;
  }

  /**
   * 获取Download目录URI
   */
  public getUri(): string {
    return this.downloadDirUri;
  }

  /**
   * 设置Download目录信息（从外部设置，如DataManagementPage）
   */
  public setDirInfo(path: string, uri: string, persistToSettings: boolean = true): void {
    if (path.length === 0) {
      logger.warn(TAG, '忽略空Download目录路径');
      return;
    }
    this.downloadDirPath = path;
    this.downloadDirUri = uri;
    this.isInitialized = true;
    AppStorage.setOrCreate(DOWNLOAD_SYNC_DIR_PATH_KEY, path);
    if (uri.length > 0) {
      AppStorage.setOrCreate(DOWNLOAD_SYNC_DIR_URI_KEY, uri);
    }
    if (persistToSettings) {
      this.persistDirInfo(path, uri);
    }
    logger.info(TAG, `Download目录已设置: ${path}`);
  }

  private persistDirInfo(path: string, uri: string): void {
    void this.persistDirInfoAsync(path, uri);
  }

  private async persistDirInfoAsync(path: string, uri: string): Promise<void> {
    try {
      const settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
      await settingsManager.setString(SettingKeys.DOWNLOAD_SYNC_DIR_PATH, path);
      if (uri.length > 0) {
        await settingsManager.setString(SettingKeys.DOWNLOAD_SYNC_DIR_URI, uri);
      }
      logger.info(TAG, 'Download目录设置已持久化');
    } catch (error) {
      logger.warn(TAG, `持久化Download目录设置失败: ${String(error)}`);
    }
  }

  /**
   * 从Download同步流程已持久化的目录恢复缓存管理访问状态
   */
  public restorePersistedDirInfo(): boolean {
    if (this.isInitialized && this.downloadDirPath !== '') {
      return true;
    }

    let savedPath = AppStorage.get<string>(DOWNLOAD_SYNC_DIR_PATH_KEY);
    let savedUri = AppStorage.get<string>(DOWNLOAD_SYNC_DIR_URI_KEY);
    if (!savedPath || savedPath.length === 0) {
      const settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
      savedPath = settingsManager.getString(SettingKeys.DOWNLOAD_SYNC_DIR_PATH, '');
      savedUri = settingsManager.getString(SettingKeys.DOWNLOAD_SYNC_DIR_URI, '');
    }
    if (!savedPath || savedPath.length === 0) {
      return false;
    }

    if (!this.canAccessDirectory(savedPath)) {
      logger.warn(TAG, `已保存Download目录不可访问，等待用户重新连接: ${savedPath}`);
      return false;
    }

    this.setDirInfo(savedPath, savedUri ? savedUri : '', false);
    logger.info(TAG, `已恢复Download目录访问状态: ${savedPath}`);
    return true;
  }

  private canAccessDirectory(path: string): boolean {
    if (path.length === 0) {
      return false;
    }

    try {
      const stat = SafeFileUtils.statSyncStrict(path);
      return stat.isDirectory();
    } catch (error) {
      logger.warn(TAG, `校验Download目录失败: ${path}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 请求用户授权并初始化Download目录
   * 返回Promise，成功返回true，失败返回false
   */
  public async requestAccess(): Promise<boolean> {
    // 如果已经初始化，直接返回
    if (this.isReady()) {
      return true;
    }

    // 如果正在初始化，等待完成
    if (this.initPromise) {
      return this.initPromise;
    }

    // 开始初始化
    this.initPromise = this.doRequestAccess();
    const result = await this.initPromise;
    this.initPromise = null;
    return result;
  }

  /**
   * 执行实际的授权请求
   */
  private async doRequestAccess(): Promise<boolean> {
    try {
      if (!this.context) {
        logger.error(TAG, '应用上下文未设置');
        return false;
      }

      if (this.restorePersistedDirInfo()) {
        return true;
      }

      const documentViewPicker = new picker.DocumentViewPicker(this.context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

      logger.info(TAG, '开始使用DOWNLOAD模式请求访问权限...');

      return new Promise<boolean>((resolve) => {
        documentViewPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
          if (documentSaveResult.length > 0) {
            const uri = documentSaveResult[0];
            logger.info(TAG, `DOWNLOAD模式返回URI: ${uri}`);

            // 保存目录路径和URI
            const uriObj = new fileUri.FileUri(uri);
            this.setDirInfo(uriObj.path, uri);

            // 创建初始化标记文件
            this.createInitFile();

            logger.info(TAG, `Download目录初始化成功: ${this.downloadDirPath}`);
            resolve(true);
          } else {
            logger.warn(TAG, 'DOWNLOAD模式未返回URI');
            resolve(false);
          }
        }).catch((err: Error) => {
          logger.error(TAG, `DOWNLOAD模式失败: ${err.message}`);
          resolve(false);
        });
      });
    } catch (error) {
      logger.error(TAG, `请求Download目录访问失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 创建初始化标记文件
   */
  private createInitFile(): void {
    try {
      const initFilePath = `${this.downloadDirPath}/.manxia_init`;
      const file = SafeFileUtils.openSync(initFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      SafeFileUtils.writeSync(file.fd, `漫匣应用目录初始化文件\n创建时间: ${new Date().toISOString()}`);
      SafeFileUtils.closeSync(file.fd);
      logger.info(TAG, `初始化文件已创建: ${initFilePath}`);
    } catch (error) {
      logger.warn(TAG, `创建初始化文件失败: ${String(error)}`);
    }
  }

  /**
   * 确保目录存在
   */
  public ensureDirectory(relativePath: string): string {
    if (!this.isInitialized || !this.downloadDirPath) {
      throw new Error('Download目录未初始化');
    }

    const normalizedRelative = this.normalizeDirectoryPath(relativePath);
    const managedRoot = this.getManagedRootPath(true);
    const fullPath = this.isAbsoluteFileSystemPath(normalizedRelative)
      ? normalizedRelative
      : `${managedRoot}/${normalizedRelative}`;
    try {
      const stat = SafeFileUtils.statSync(fullPath);
      if (!stat.isDirectory()) {
        throw new Error('路径不是目录');
      }
    } catch (error) {
      // 目录不存在，创建它
      SafeFileUtils.mkdirSync(fullPath, true);
      logger.debug(TAG, `目录已创建: ${fullPath}`);
    }
    return fullPath;
  }

  /**
   * 获取漫画下载目录
   * 格式: Download/包名/manga/{mangaTitle}/{chapterTitle}/
   */
  public getMangaDownloadPath(mangaTitle: string, chapterTitle?: string): string {
    const sanitizedMangaTitle = this.sanitizeFolderName(mangaTitle);
    let path = `manga/${sanitizedMangaTitle}`;
    if (chapterTitle) {
      const sanitizedChapterTitle = this.sanitizeFolderName(chapterTitle);
      path = `${path}/${sanitizedChapterTitle}`;
    }
    return this.ensureDirectory(path);
  }

  /**
   * 获取在线漫画归档章节目录
   * 格式: Download/包名/manga/{sourceName}/{mangaTitle}/{chapterTitle}/
   */
  public getMangaArchiveDirectoryPath(sourceName: string, mangaTitle: string, chapterTitle: string): string {
    const sanitizedSourceName = this.sanitizeFolderName(sourceName.length > 0 ? sourceName : 'unknown_source');
    const sanitizedMangaTitle = this.sanitizeFolderName(mangaTitle.length > 0 ? mangaTitle : 'unknown_manga');
    const sanitizedChapterTitle = this.sanitizeFolderName(chapterTitle.length > 0 ? chapterTitle : 'unknown_chapter');
    const path = `manga/${sanitizedSourceName}/${sanitizedMangaTitle}/${sanitizedChapterTitle}`;
    return this.ensureDirectory(path);
  }

  /**
   * 获取在线漫画归档文件路径
   */
  public getMangaArchiveFilePath(sourceName: string, mangaTitle: string, chapterTitle: string): string {
    const chapterDir = this.getMangaArchiveDirectoryPath(sourceName, mangaTitle, chapterTitle);
    const fileName = `${this.sanitizeFolderName(chapterTitle.length > 0 ? chapterTitle : 'chapter')}.cbz`;
    return `${chapterDir}/${fileName}`;
  }

  public buildStandardOnlineMangaArchivePath(request: OnlineMangaArchivePathRequest): string {
    const root = this.getManagedRootPath(false);
    if (root.length <= 0) {
      return '';
    }
    const sourceSegment = this.resolvePrimarySourceSegment(request);
    const mangaDir = this.sanitizeFolderName(request.mangaTitle.length > 0 ? request.mangaTitle : 'unknown_manga');
    const chapterDir = this.sanitizeFolderName(request.chapterTitle.length > 0 ? request.chapterTitle : 'unknown_chapter');
    const fileName = this.buildArchiveFileName(request.chapterTitle, request.chapterId);
    return `${root}/manga/${sourceSegment}/${mangaDir}/${chapterDir}/${fileName}`;
  }

  public buildOnlineMangaArchiveCandidates(request: OnlineMangaArchivePathRequest): string[] {
    const candidates: string[] = [];
    const normalizedStoredPath = this.normalizeFileSystemPath(request.storedArchivePath || '');
    if (normalizedStoredPath.length > 0) {
      candidates.push(normalizedStoredPath);
    }
    const roots = this.resolveArchiveLookupRoots();
    const sourceSegments = this.resolveArchiveSourceSegments(request);
    const fileNames = this.resolveArchiveFileNames(request);
    const mangaDir = this.sanitizeFolderName(request.mangaTitle.length > 0 ? request.mangaTitle : 'unknown_manga');
    const chapterDir = this.sanitizeFolderName(request.chapterTitle.length > 0 ? request.chapterTitle : 'unknown_chapter');

    for (let i = 0; i < roots.length; i++) {
      const root = roots[i];
      this.appendArchiveLayoutCandidates(candidates, `${root}/manga`, sourceSegments, mangaDir, chapterDir, fileNames);
      this.appendArchiveLayoutCandidates(candidates, `${root}/online_archive`, sourceSegments, mangaDir, chapterDir, fileNames);
      this.appendArchiveLayoutCandidates(candidates, root, sourceSegments, mangaDir, chapterDir, fileNames);
      this.appendArchiveCrossSourceCandidates(candidates, `${root}/manga`, mangaDir, chapterDir, fileNames);
      this.appendArchiveCrossSourceCandidates(candidates, `${root}/online_archive`, mangaDir, chapterDir, fileNames);
    }
    return this.deduplicatePaths(candidates);
  }

  public resolveExistingOnlineMangaArchive(request: OnlineMangaArchivePathRequest): OnlineMangaArchiveLookupResult {
    const candidates = this.buildOnlineMangaArchiveCandidates(request);
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      const probe = this.probePath(candidate);
      if (probe.exists && probe.isFile && this.isCbzPath(candidate)) {
        return this.createLookupResult(candidate, 'candidate_file', candidates);
      }
      if (probe.exists && probe.isDirectory) {
        const discoveredInCandidate = this.findFirstCbzInDirectory(candidate);
        if (discoveredInCandidate.length > 0) {
          return this.createLookupResult(discoveredInCandidate, 'stored_directory_scan', candidates);
        }
      }

      const parentDir = this.getParentDirectoryPath(candidate);
      if (parentDir.length <= 0) {
        continue;
      }
      const parentProbe = this.probePath(parentDir);
      if (parentProbe.exists && parentProbe.isDirectory) {
        const discovered = this.findFirstCbzInDirectory(parentDir);
        if (discovered.length > 0) {
          return this.createLookupResult(discovered, 'chapter_directory_scan', candidates);
        }
      }
    }
    return this.createLookupResult('', 'miss', candidates);
  }

  public probePath(path: string): DownloadPathProbeResult {
    const normalizedPath = this.normalizeDirectoryPath(path);
    const missing: DownloadPathProbeResult = {
      path: normalizedPath,
      exists: false,
      isDirectory: false,
      isFile: false,
      fileSize: 0
    };
    if (normalizedPath.length <= 0 || !SafeFileUtils.accessSync(normalizedPath)) {
      return missing;
    }
    try {
      const stat = SafeFileUtils.statSyncStrict(normalizedPath);
      const result: DownloadPathProbeResult = {
        path: normalizedPath,
        exists: true,
        isDirectory: stat.isDirectory(),
        isFile: !stat.isDirectory(),
        fileSize: stat.size
      };
      return result;
    } catch (error) {
      logger.warn(TAG, `探测Download路径失败: ${normalizedPath}, ${String(error)}`);
      return missing;
    }
  }

  /**
   * 获取图片保存路径
   */
  public getImageSavePath(mangaTitle: string, chapterTitle: string, pageIndex: number, extension: string = 'jpg'): string {
    const chapterPath = this.getMangaDownloadPath(mangaTitle, chapterTitle);
    return `${chapterPath}/page_${String(pageIndex + 1).padStart(4, '0')}.${extension}`;
  }

  /**
   * 清理文件夹名称，移除非法字符
   */
  private sanitizeFolderName(name: string): string {
    // 移除或替换文件系统不允许的字符
    return name
      .replace(/[\\/:*?"<>|]/g, '_')  // 替换非法字符
      .replace(/\s+/g, ' ')           // 合并多个空格
      .trim()                          // 去除首尾空格
      .substring(0, 100);              // 限制长度
  }

  private resolvePrimarySourceSegment(request: OnlineMangaArchivePathRequest): string {
    if (request.sourceName.trim().length > 0) {
      return this.sanitizeFolderName(request.sourceName);
    }
    if (request.sourcePkg.trim().length > 0) {
      return this.sanitizeFolderName(request.sourcePkg);
    }
    if (request.sourceId.trim().length > 0) {
      return this.sanitizeFolderName(`source_${request.sourceId}`);
    }
    return 'unknown_source';
  }

  private resolveArchiveSourceSegments(request: OnlineMangaArchivePathRequest): string[] {
    const segments: string[] = [];
    this.appendSanitizedSegment(segments, request.sourceName);
    this.appendSanitizedSegment(segments, request.sourcePkg);
    this.appendSanitizedSegment(segments, request.sourceId);
    if (request.sourceId.trim().length > 0) {
      this.appendSanitizedSegment(segments, `source_${request.sourceId}`);
    }
    this.appendSanitizedSegment(segments, 'unknown_source');
    return segments;
  }

  private resolveArchiveFileNames(request: OnlineMangaArchivePathRequest): string[] {
    const fileNames: string[] = [];
    this.appendArchiveFileName(fileNames, request.chapterTitle);
    this.appendArchiveFileName(fileNames, request.externalChapterId);
    this.appendArchiveFileName(fileNames, request.chapterNumber || '');
    this.appendArchiveFileName(fileNames, request.chapterId);
    this.appendArchiveFileName(fileNames, 'chapter');
    return fileNames;
  }

  private appendArchiveLayoutCandidates(
    candidates: string[],
    rootPath: string,
    sourceSegments: string[],
    mangaDir: string,
    chapterDir: string,
    fileNames: string[]
  ): void {
    const root = this.normalizeDirectoryPath(rootPath);
    if (root.length <= 0) {
      return;
    }
    for (let i = 0; i < fileNames.length; i++) {
      const fileName = fileNames[i];
      candidates.push(`${root}/${mangaDir}/${chapterDir}/${fileName}`);
      for (let j = 0; j < sourceSegments.length; j++) {
        candidates.push(`${root}/${sourceSegments[j]}/${mangaDir}/${chapterDir}/${fileName}`);
      }
    }
  }

  private appendArchiveCrossSourceCandidates(
    candidates: string[],
    sourceRootPath: string,
    mangaDir: string,
    chapterDir: string,
    fileNames: string[]
  ): void {
    const sourceRoot = this.normalizeDirectoryPath(sourceRootPath);
    const rootProbe = this.probePath(sourceRoot);
    if (!rootProbe.exists || !rootProbe.isDirectory) {
      return;
    }

    try {
      const sourceEntries = SafeFileUtils.listFileSync(sourceRoot);
      for (let i = 0; i < sourceEntries.length; i++) {
        const sourcePath = `${sourceRoot}/${sourceEntries[i]}`;
        const sourceProbe = this.probePath(sourcePath);
        if (!sourceProbe.exists || !sourceProbe.isDirectory) {
          continue;
        }
        for (let j = 0; j < fileNames.length; j++) {
          candidates.push(`${sourcePath}/${mangaDir}/${chapterDir}/${fileNames[j]}`);
        }
      }
    } catch (error) {
      logger.warn(TAG, `扫描Download图源目录候选失败: ${sourceRoot}, ${String(error)}`);
    }
  }

  private appendSanitizedSegment(segments: string[], rawSegment: string): void {
    const trimmed = rawSegment.trim();
    if (trimmed.length <= 0) {
      return;
    }
    const segment = this.sanitizeFolderName(trimmed);
    for (let i = 0; i < segments.length; i++) {
      if (segments[i] === segment) {
        return;
      }
    }
    segments.push(segment);
  }

  private appendArchiveFileName(fileNames: string[], rawName: string): void {
    const trimmed = rawName.trim();
    if (trimmed.length <= 0) {
      return;
    }
    const fileName = this.buildArchiveFileName(trimmed, '');
    for (let i = 0; i < fileNames.length; i++) {
      if (fileNames[i] === fileName) {
        return;
      }
    }
    fileNames.push(fileName);
  }

  private buildArchiveFileName(rawName: string, fallbackName: string): string {
    const name = rawName.trim().length > 0 ? rawName : fallbackName;
    const sanitized = this.sanitizeFolderName(name.length > 0 ? name : 'chapter');
    return `${sanitized}.cbz`;
  }

  private resolveArchiveLookupRoots(): string[] {
    const roots: string[] = [];
    if (!this.isReady()) {
      return roots;
    }
    const managedRoot = this.getManagedRootPath(false);
    if (managedRoot.length > 0) {
      roots.push(managedRoot);
    }
    const rawRoot = this.normalizeDirectoryPath(this.downloadDirPath);
    if (rawRoot.length > 0) {
      roots.push(rawRoot);
    }
    return this.deduplicatePaths(roots);
  }

  private createLookupResult(archivePath: string, matchedBy: string, candidates: string[]): OnlineMangaArchiveLookupResult {
    const result: OnlineMangaArchiveLookupResult = {
      archivePath: archivePath,
      matchedBy: matchedBy,
      candidates: candidates
    };
    return result;
  }

  private findFirstCbzInDirectory(directoryPath: string): string {
    const normalizedDirectory = this.normalizeDirectoryPath(directoryPath);
    const probe = this.probePath(normalizedDirectory);
    if (!probe.exists || !probe.isDirectory) {
      return '';
    }
    try {
      const entries = SafeFileUtils.listFileSync(normalizedDirectory);
      entries.sort((left: string, right: string) => {
        return left.localeCompare(right);
      });
      for (let i = 0; i < entries.length; i++) {
        const fullPath = `${normalizedDirectory}/${entries[i]}`;
        const fileProbe = this.probePath(fullPath);
        if (fileProbe.exists && fileProbe.isFile && this.isCbzPath(fullPath)) {
          return fullPath;
        }
      }
    } catch (error) {
      logger.warn(TAG, `扫描章节CBZ目录失败: ${normalizedDirectory}, ${String(error)}`);
    }
    return '';
  }

  private isCbzPath(path: string): boolean {
    return path.toLowerCase().endsWith('.cbz');
  }

  private ensureAbsoluteDirectory(path: string): void {
    const normalizedPath = this.normalizeDirectoryPath(path);
    if (normalizedPath.length <= 0) {
      return;
    }
    try {
      const stat = SafeFileUtils.statSyncStrict(normalizedPath);
      if (!stat.isDirectory()) {
        throw new Error('路径不是目录');
      }
    } catch (_error) {
      SafeFileUtils.mkdirSync(normalizedPath, true);
      logger.debug(TAG, `应用专属Download目录已创建: ${normalizedPath}`);
    }
  }

  private normalizeDirectoryPath(path: string): string {
    let normalized = this.normalizeFileSystemPath(path).replace(/\\/g, '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private normalizeFileSystemPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      return trimmed.substring(7);
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('storage/') || trimmed.startsWith('data/')) {
      return `/${trimmed}`;
    }
    return trimmed;
  }

  private isAbsoluteFileSystemPath(path: string): boolean {
    const normalized = this.normalizeDirectoryPath(path);
    if (normalized.startsWith('/')) {
      return true;
    }
    return normalized.length >= 3 &&
      normalized.charAt(1) === ':' &&
      normalized.charAt(2) === '/';
  }

  private getParentDirectoryPath(path: string): string {
    const normalized = this.normalizeDirectoryPath(path);
    const slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalized.substring(0, slashIndex);
  }

  private pathEndsWithSegment(path: string, segment: string): boolean {
    const parts = this.normalizeDirectoryPath(path).split('/');
    if (parts.length <= 0) {
      return false;
    }
    return parts[parts.length - 1] === segment;
  }

  private deduplicatePaths(paths: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < paths.length; i++) {
      const currentPath = this.normalizeDirectoryPath(paths[i]);
      if (currentPath.length <= 0) {
        continue;
      }
      let exists = false;
      for (let j = 0; j < result.length; j++) {
        if (result[j] === currentPath) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        result.push(currentPath);
      }
    }
    return result;
  }

  /**
   * 检查文件是否存在
   */
  public fileExists(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      SafeFileUtils.accessSync(fullPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 列出目录下的文件
   */
  public listFiles(relativePath: string = ''): string[] {
    if (!this.isInitialized || !this.downloadDirPath) {
      return [];
    }
    try {
      const fullPath = relativePath ? `${this.downloadDirPath}/${relativePath}` : this.downloadDirPath;
      return SafeFileUtils.listFileSync(fullPath);
    } catch (error) {
      logger.warn(TAG, `列出文件失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 删除文件
   */
  public deleteFile(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      SafeFileUtils.unlinkSync(fullPath);
      logger.debug(TAG, `文件已删除: ${fullPath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除文件失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 删除目录（递归）
   */
  public deleteDirectory(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      SafeFileUtils.rmdirSync(fullPath);
      logger.debug(TAG, `目录已删除: ${fullPath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除目录失败: ${String(error)}`);
      return false;
    }
  }
}

// 导出单例
export default DownloadDirManager.getInstance();
