import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 图源仓库管理器
 * 负责管理extensions-source文件夹下的图源仓库
 */

import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { SourceManager, ImportResult } from './SourceManager';
import { http } from '@kit.NetworkKit';
import { ProxyManager } from '../Network/ProxyManager';
import { DataManager } from '../Data/DataManager';
import { ngfSourceLoaderFacade, ngfSourceRepositoryFacade } from '../NGF';

const TAG = 'SourceRepositoryManager';
const REPOSITORY_PROXY_GH: string = 'https://gh-proxy.org/';
const REPOSITORY_PROXY_HK_GH: string = 'https://hk.gh-proxy.org/';
const REPOSITORY_CONNECT_TIMEOUT_MS: number = 2500;
const REPOSITORY_READ_TIMEOUT_MS: number = 2500;

/**
 * 图源子条目
 */
export interface SourceSubEntry {
  name: string;         // 图源显示名称
  lang: string;         // 语言
  id: string;           // 图源ID
  baseUrl: string;      // 基础URL
}

/**
 * 图源类型
 */
export type SourceType = 'manga' | 'ebook' | 'novel' | 'video' | 'audio' | 'image';

/**
 * 图源仓库条目（参考Tachiyomi格式）
 */
export interface SourceRepositoryEntry {
  name: string;           // 图源名称
  pkg: string;            // 包名
  type?: SourceType;      // 图源类型（默认为manga）
  apk?: string;           // APK文件名（可选）
  lang: string;           // 语言
  code: number;           // 版本代码
  version: string;        // 版本号
  nsfw: number;           // 是否NSFW (0/1)
  hasIcon?: boolean;      // 是否有图标
  sources: SourceSubEntry[];
}

/**
 * 图源仓库索引文件（index.main.json）
 */
export interface SourceRepositoryIndex {
  version: string;                          // 仓库版本
  lastUpdate: number;                       // 最后更新时间
  sources: SourceRepositoryEntry[];         // 图源列表
}

/**
 * 已保存的仓库配置
 */
export interface SavedRepository {
  originalUrl?: string;
  lastEffectiveUrl?: string;
  id: string;             // 仓库ID
  name: string;           // 仓库名称
  url: string;            // 仓库URL
  lastSync: number;       // 最后同步时间
  sourceCount: number;    // 图源数量
}

/**
 * 同步结果接口
 */
export interface SyncResult {
  success: boolean;
  message: string;
  sourceCount?: number;
}

/**
 * 同步进度回调接口
 */
export interface SyncProgressCallback {
  onProgress: (current: number, total: number, message: string) => void;
  onLog: (level: 'info' | 'warn' | 'error', message: string) => void;
}

/**
 * 图源图标信息
 */
interface SourceIconInfo {
  data: ArrayBuffer;
  ext: string;
}

type RepositoryCandidateKind = 'origin' | 'ghProxy' | 'hkGhProxy';
type RepositoryRouteLogCallback = (level: 'info' | 'warn' | 'error', message: string) => void;

interface RepositoryRouteCandidate {
  kind: RepositoryCandidateKind;
  url: string;
}

interface RepositoryConnectivityCheckResult {
  reachable: boolean;
  responseCode: number;
  errorMessage: string;
}

interface RepositoryProbeResult {
  candidate: RepositoryRouteCandidate;
  check: RepositoryConnectivityCheckResult;
}

interface RepositoryRouteResult {
  originalUrl: string;
  effectiveUrl: string;
  usedProxy: boolean;
  proxyPrefix: string;
}

interface RepositoryProxyUnwrapResult {
  proxyPrefix: string;
  rawUrl: string;
}

interface RepositoryUrlSplitResult {
  baseUrl: string;
  query: string;
}

/**
 * 图源仓库管理器类
 */
export class SourceRepositoryManager {
  private static instance: SourceRepositoryManager | null = null;
  private context: Context | null = null;
  private repositoryDir: string = '';
  private indexFilePath: string = '';
  private savedRepositoriesPath: string = '';
  private sourceManager: SourceManager;
  
  private decodeToString(buffer: ArrayBuffer, length: number): string {
    const bytes: Uint8Array = new Uint8Array(buffer, 0, length);
    let out: string = '';
    let i: number = 0;
    const len: number = bytes.length;
    while (i < len) {
      const b0: number = bytes[i++];
      if ((b0 & 0x80) === 0) {
        out += String.fromCharCode(b0);
      } else if ((b0 & 0xe0) === 0xc0 && i < len) {
        const b1: number = bytes[i++];
        const code: number = ((b0 & 0x1f) << 6) | (b1 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf0) === 0xe0 && i + 1 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const code: number = ((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf8) === 0xf0 && i + 2 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const b3: number = bytes[i++];
        let codePoint: number = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
        codePoint -= 0x10000;
        out += String.fromCharCode(0xd800 + ((codePoint >> 10) & 0x3ff));
        out += String.fromCharCode(0xdc00 + (codePoint & 0x3ff));
      } else {
        out += '\uFFFD';
      }
    }
    return out;
  }

  private constructor() {
    this.sourceManager = SourceManager.getInstance();
  }

  private async ensureSavedRepositoriesFileExists(): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(this.savedRepositoriesPath);
      if (!exists) {
        this.writeSavedRepositoriesToFile([]);
        logger.info(TAG, '创建空的 saved_repositories.json');
      }
    } catch (_) {
      this.writeSavedRepositoriesToFile([]);
      logger.info(TAG, '创建空的 saved_repositories.json');
    }
  }

  /**
   * 获取单例实例
   */
  static getInstance(): SourceRepositoryManager {
    if (!SourceRepositoryManager.instance) {
      SourceRepositoryManager.instance = new SourceRepositoryManager();
    }
    return SourceRepositoryManager.instance;
  }

  /**
   * 初始化仓库管理器
   */
  async initialize(context: Context): Promise<void> {
    try {
      this.context = context;
      
      // 设置仓库目录路径
      const filesDir = context.filesDir;
      this.repositoryDir = `${filesDir}/extensions-source`;
      this.indexFilePath = `${this.repositoryDir}/index.main.json`;
      this.savedRepositoriesPath = `${this.repositoryDir}/saved_repositories.json`;
      
      // 创建目录
      await this.ensureDirectoryExists(this.repositoryDir);
      
      // 初始化索引文件
      await this.ensureIndexFileExists();
      await this.ensureSavedRepositoriesFileExists();
      
      logger.info(TAG, `仓库管理器初始化完成: ${this.repositoryDir}`);
    } catch (error) {
      const errorMsg = `初始化仓库管理器失败: ${String(error)}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 确保目录存在
   */
  private async ensureDirectoryExists(dirPath: string): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(dirPath);
      if (!exists) {
        SafeFileUtils.mkdirSync(dirPath);
        logger.info(TAG, `创建目录: ${dirPath}`);
      }
    } catch (error) {
      // 目录不存在，创建它
      try {
        SafeFileUtils.mkdirSync(dirPath);
        logger.info(TAG, `创建目录: ${dirPath}`);
      } catch (mkdirError) {
        const errorMsg = `创建目录失败: ${dirPath} - ${String(mkdirError)}`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
    }
  }

  /**
   * 确保索引文件存在
   */
  private async ensureIndexFileExists(): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(this.indexFilePath);
      if (!exists) {
        // 创建空的索引文件
        const emptyIndex: SourceRepositoryIndex = {
          version: '1.0.0',
          lastUpdate: Date.now(),
          sources: []
        };
        await this.saveIndexFile(emptyIndex);
        logger.info(TAG, '创建空索引文件');
      }
    } catch (error) {
      // 文件不存在，创建它
      const emptyIndex: SourceRepositoryIndex = {
        version: '1.0.0',
        lastUpdate: Date.now(),
        sources: []
      };
      await this.saveIndexFile(emptyIndex);
      logger.info(TAG, '创建空索引文件');
    }
  }

  /**
   * 保存索引文件
   */
  private async saveIndexFile(index: SourceRepositoryIndex): Promise<void> {
    try {
      const jsonContent = JSON.stringify(index, null, 2);
      const savedByNgf = ngfSourceRepositoryFacade.updateIndexJson(jsonContent);
      if (savedByNgf) {
        logger.info(TAG, '索引文件保存成功（NGF facade）');
        return;
      }
      logger.warn(TAG, 'NGF facade 保存索引失败，回退旧写入路径');
      const file = SafeFileUtils.openSync(this.indexFilePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      SafeFileUtils.writeSync(file.fd, jsonContent);
      SafeFileUtils.closeSync(file);
      logger.info(TAG, '索引文件保存成功');
    } catch (error) {
      const errorMsg = `保存索引文件失败: ${String(error)}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 读取索引文件
   */
  async readIndexFile(): Promise<SourceRepositoryIndex> {
    try {
      const indexJsonFromNgf = ngfSourceRepositoryFacade.readIndexJson().trim();
      if (indexJsonFromNgf.length > 0) {
        try {
          const parsedByNgf = SafeUtils.parseObj(indexJsonFromNgf) as SourceRepositoryIndex;
          if (parsedByNgf.sources && parsedByNgf.sources.length > 0) {
            return parsedByNgf;
          }

          let hasLegacyIndexFile = false;
          try {
            hasLegacyIndexFile = SafeFileUtils.accessSync(this.indexFilePath);
          } catch {
            hasLegacyIndexFile = false;
          }
          if (!hasLegacyIndexFile) {
            return parsedByNgf;
          }

          logger.debug(TAG, 'NGF facade 返回空索引，检测到旧索引文件存在，回退旧读取路径');
        } catch {
          logger.warn(TAG, 'NGF facade 索引解析失败，回退旧读取路径');
        }
      }

      const file = SafeFileUtils.openSync(this.indexFilePath, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(10 * 1024 * 1024); // 10MB
      const readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

      const jsonContent: string = this.decodeToString(buffer, readLen);

      return SafeUtils.parseObj(jsonContent) as SourceRepositoryIndex;
    } catch (error) {
      logger.error(TAG, '读取索引文件失败', String(error));
      // 返回空索引
      return {
        version: '1.0.0',
        lastUpdate: Date.now(),
        sources: []
      };
    }
  }

  /**
   * 从URL同步仓库（带进度回调）
   */
  async syncRepositoryFromUrl(url: string, repositoryName?: string, progressCallback?: SyncProgressCallback): Promise<SyncResult> {
    const log = (level: 'info' | 'warn' | 'error', message: string) => {
      if (level === 'info') logger.info(TAG, message);
      else if (level === 'warn') logger.warn(TAG, message);
      else logger.error(TAG, message);
      progressCallback?.onLog(level, message);
    };
    
    try {
      const normalizedInputUrl = this.normalizeRepositoryUrl(url);
      if (!normalizedInputUrl) {
        throw new Error('仓库地址不能为空');
      }

      const route = await this.resolveBestRepositoryUrl(normalizedInputUrl, log);
      const syncUrl = route.effectiveUrl;
      log('info', `开始同步仓库: ${normalizedInputUrl}`);
      progressCallback?.onProgress(0, 100, '正在连接仓库...');

      // 下载仓库索引文件（超时10秒）
      if (route.usedProxy) {
        log('warn', `原始仓库不可达，切换到代理地址: ${syncUrl}`);
      } else {
        log('info', '仓库连通性检测通过，使用原始地址同步');
      }
      progressCallback?.onProgress(5, 100, '连通性检测完成，开始下载仓库索引...');

      const httpRequest = http.createHttp();
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'Content-Type': 'application/json'
        }
      };
      
      // 应用代理配置
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        requestOptions.usingProxy = true;
        log('info', '使用代理连接图源仓库');
      }
      
      const response = await httpRequest.request(syncUrl, requestOptions);

      if (response.responseCode !== 200) {
        throw new Error(`HTTP请求失败: ${response.responseCode}`);
      }

      const responseData = response.result as string;
      const repositoryData = SafeUtils.parseArr(responseData) as SourceRepositoryEntry[];
      
      log('info', `获取到 ${repositoryData.length} 个图源`);
      progressCallback?.onProgress(10, 100, `获取到 ${repositoryData.length} 个图源`);

      // 下载每个图源的实际配置文件和图标
      const sourceConfigs: Record<string, string> = {};
      const sourceIcons: Record<string, SourceIconInfo> = {};
      const totalSources = repositoryData.length;
      let processedSources = 0;
      
      for (const entry of repositoryData) {
        processedSources++;
        const progressPercent = totalSources > 0
          ? 10 + Math.floor((processedSources / totalSources) * 60)
          : 70;
        progressCallback?.onProgress(progressPercent, 100, `下载图源配置 (${processedSources}/${totalSources}): ${entry.name}`);
        
        // 下载图源配置文件（超时5秒）
        const sourceConfigUrl = this.resolveSourceConfigUrl(syncUrl, entry.pkg);
        try {
          const configOptions: http.HttpRequestOptions = {
            method: http.RequestMethod.GET,
            connectTimeout: 5000,
            readTimeout: 5000,
            header: {
              'Content-Type': 'application/json'
            }
          };
          if (proxyManager.isEnabled()) {
            configOptions.usingProxy = true;
          }
          const configResponse = await httpRequest.request(sourceConfigUrl, configOptions);

          if (configResponse.responseCode !== 200 || !configResponse.result) {
            log('warn', `下载图源配置失败: ${entry.pkg}, code: ${configResponse.responseCode}`);
            continue;
          }

          sourceConfigs[entry.pkg] = configResponse.result as string;
          log('info', `下载图源配置成功: ${entry.name}`);
        } catch (error) {
          log('warn', `下载图源配置超时: ${entry.pkg} (5秒)`);
        }
        
        // 如果有图标，下载图标文件（超时3秒，只尝试一种格式）
        if (entry.hasIcon) {
          const iconFormats = ['webp', 'png', 'jpg'];
          let iconDownloaded = false;
          
          for (const ext of iconFormats) {
            if (iconDownloaded) break;
            
            const iconUrl = this.resolveSourceIconUrl(syncUrl, entry.pkg, ext);
            try {
              const iconOptions: http.HttpRequestOptions = {
                method: http.RequestMethod.GET,
                connectTimeout: 3000,
                readTimeout: 3000,
                expectDataType: http.HttpDataType.ARRAY_BUFFER
              };
              if (proxyManager.isEnabled()) {
                iconOptions.usingProxy = true;
              }
              const iconResponse = await httpRequest.request(iconUrl, iconOptions);
              
              if (iconResponse.responseCode === 200 && iconResponse.result) {
                const iconInfo: SourceIconInfo = {
                  data: iconResponse.result as ArrayBuffer,
                  ext: ext
                };
                sourceIcons[entry.pkg] = iconInfo;
                iconDownloaded = true;
                log('info', `下载图源图标成功: ${entry.pkg} (${ext})`);
              }
            } catch (iconError) {
              // 尝试下一个格式（静默失败）
            }
          }
          
          if (!iconDownloaded) {
            log('warn', `下载图源图标失败: ${entry.pkg}，跳过图标`);
          }
        }
      }
      
      progressCallback?.onProgress(70, 100, '正在保存图源配置...');

      // 读取当前索引
      const currentIndex = await this.readIndexFile();

      // 合并图源（去重）
      const existingIds = new Set(currentIndex.sources.map(s => s.pkg));
      let addedCount = 0;
      let updatedCount = 0;

      const sourcesToImport: SourceRepositoryEntry[] = [];
      for (const newSource of repositoryData) {
        if (existingIds.has(newSource.pkg)) {
          // 更新现有图源
          const index = currentIndex.sources.findIndex(s => s.pkg === newSource.pkg);
          if (index !== -1) {
            currentIndex.sources[index] = newSource;
            updatedCount++;
          }
        } else {
          // 添加新图源
          currentIndex.sources.push(newSource);
          addedCount++;
          sourcesToImport.push(newSource);
        }
      }

      // 更新索引文件
      currentIndex.lastUpdate = Date.now();
      await this.saveIndexFile(currentIndex);

      // 保存仓库配置
      await this.saveRepositoryConfig(route, repositoryName || this.deriveRepositoryName(route.originalUrl), repositoryData.length);

      progressCallback?.onProgress(75, 100, '正在保存图源文件...');
      // 保存各个图源的JSON文件和图标
      await this.saveSourceFiles(sourceConfigs);
      await this.saveSourceIcons(sourceIcons);

      progressCallback?.onProgress(80, 100, '正在导入图源到数据库...');
      // 导入新增的图源
      if (sourcesToImport.length > 0) {
        await this.importNewSources(sourcesToImport);
        log('info', `导入 ${sourcesToImport.length} 个新图源`);
      }

      // 对于更新的图源，直接更新数据库配置（不删除再导入）
      if (updatedCount > 0) {
        log('info', `检测到${updatedCount}个图源更新，更新数据库配置`);
        let reimportedCount = 0;
        for (const source of repositoryData) {
          if (existingIds.has(source.pkg)) {
            reimportedCount++;
            progressCallback?.onProgress(80 + Math.floor((reimportedCount / updatedCount) * 15), 100, `更新图源: ${source.name}`);
            try {
              // 直接重新导入（importFromJSON现在会自动检测并更新已存在的图源）
              const result = await this.importSourceFromRepository(source.pkg);
              if (result.success) {
                log('info', `图源已更新: ${source.name}`);
                // 同步仓库索引中的NSFW状态
                if (result.sourceId) {
                  try {
                    await DataManager.getInstance().updateSourceNSFW(result.sourceId, source.nsfw === 1);
                  } catch (nsfwError) {
                    log('warn', `同步NSFW状态失败: ${source.name} - ${String(nsfwError)}`);
                  }
                }
              } else {
                log('warn', `更新图源失败: ${source.name} - ${result.error ?? '未知错误'}`);
              }
            } catch (error) {
              log('warn', `更新图源异常: ${source.name} - ${String(error)}`);
            }
          }
        }
      }

      progressCallback?.onProgress(100, 100, '同步完成！');
      log('info', `仓库同步成功: 新增${addedCount}个, 更新${updatedCount}个图源`);

      return {
        success: true,
        message: `同步成功！新增${addedCount}个图源，更新${updatedCount}个图源`,
        sourceCount: repositoryData.length
      };
    } catch (error) {
      // 提取有意义的错误信息
      let errorMessage: string;
      if (error instanceof Error) {
        errorMessage = error.message;
      } else if (typeof error === 'object' && error !== null) {
        // 尝试提取常见的错误属性
        const errObj = error as Record<string, string | number | boolean>;
        if (errObj.message && typeof errObj.message === 'string') {
          errorMessage = errObj.message;
        } else if (errObj.code !== undefined) {
          errorMessage = `错误代码: ${String(errObj.code)}`;
        } else {
          try {
            errorMessage = JSON.stringify(error);
          } catch {
            errorMessage = '未知错误';
          }
        }
      } else {
        errorMessage = String(error);
      }
      
      log('error', `同步仓库失败: ${errorMessage}`);
      return {
        success: false,
        message: `同步失败: ${errorMessage}`
      };
    }
  }

  /**
   * 保存各个图源的JSON文件
   */
  private async saveSourceFiles(sourceConfigs: Record<string, string>): Promise<void> {
    const entries: Array<[string, string]> = Object.entries(sourceConfigs);
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const pkg = entry[0];
      const config = entry[1];
      try {
        const fileName = `${pkg}.json`;
        const filePath = `${this.repositoryDir}/${fileName}`;

        const file = SafeFileUtils.openSync(
          filePath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
        );
        SafeFileUtils.writeSync(file.fd, config);
        SafeFileUtils.closeSync(file);
        logger.info(TAG, `图源文件保存成功: ${fileName}`);
      } catch (error) {
        logger.warn(TAG, `保存图源文件失败: ${pkg}`, String(error));
      }
    }
  }

  /**
   * 保存图源图标文件
   */
  private async saveSourceIcons(sourceIcons: Record<string, SourceIconInfo>): Promise<void> {
    // 确保图标目录存在
    const iconsDir = `${this.repositoryDir}/icons`;
    await this.ensureDirectoryExists(iconsDir);
    
    const entries: Array<[string, SourceIconInfo]> = Object.entries(sourceIcons);
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const pkg = entry[0];
      const iconInfo = entry[1];
      try {
        // 使用原始扩展名保存
        const fileName = `${pkg}.${iconInfo.ext}`;
        const filePath = `${iconsDir}/${fileName}`;

        const file = SafeFileUtils.openSync(
          filePath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
        );
        SafeFileUtils.writeSync(file.fd, iconInfo.data);
        SafeFileUtils.closeSync(file);
        logger.info(TAG, `图源图标保存成功: ${fileName}`);
      } catch (error) {
        logger.warn(TAG, `保存图源图标失败: ${pkg}`, String(error));
      }
    }
  }

  /**
   * 获取图源图标路径
   * @param pkg 图源包名
   * @returns 图标文件路径，如果不存在返回 null
   */
  getSourceIconPath(pkg: string): string | null {
    const ngfIconPath = ngfSourceLoaderFacade.loadIconPath(pkg);
    if (ngfIconPath.length > 0) {
      return ngfIconPath;
    }

    // 检查 repositoryDir 是否已初始化
    if (!this.repositoryDir || this.repositoryDir.trim() === '') {
      logger.warn(TAG, `getSourceIconPath: repositoryDir 未初始化，无法获取图标路径: ${pkg}`);
      return null;
    }
    
    // 尝试多种格式
    const formats = ['webp', 'png', 'jpg'];
    for (const ext of formats) {
      const iconPath = `${this.repositoryDir}/icons/${pkg}.${ext}`;
      try {
        // fileIo.accessSync 如果文件存在不抛异常，不存在则抛异常
        SafeFileUtils.accessSync(iconPath);
        // 如果没有抛异常，说明文件存在
        logger.debug(TAG, `找到图源图标: ${iconPath}`);
        return iconPath;
      } catch (_) {
        // 文件不存在，尝试下一个格式
      }
    }
    logger.warn(TAG, `未找到图源图标: ${pkg}, repositoryDir=${this.repositoryDir}`);
    return null;
  }

  /**
   * 删除图源相关文件（JSON配置和图标）
   * @param pkg 图源包名
   */
  deleteSourceFiles(pkg: string): void {
    if (!pkg || !this.repositoryDir) {
      logger.warn(TAG, `无法删除图源文件: pkg=${pkg}, repositoryDir=${this.repositoryDir}`);
      return;
    }

    // 删除 JSON 配置文件
    const jsonPath = `${this.repositoryDir}/${pkg}.json`;
    try {
      if (SafeFileUtils.accessSync(jsonPath)) {
        SafeFileUtils.unlinkSync(jsonPath);
        logger.info(TAG, `已删除图源配置文件: ${pkg}.json`);
      }
    } catch (e) {
      logger.debug(TAG, `图源配置文件不存在或删除失败: ${pkg}.json`);
    }

    // 删除图标文件（尝试多种格式）
    const formats = ['webp', 'png', 'jpg'];
    for (const ext of formats) {
      const iconPath = `${this.repositoryDir}/icons/${pkg}.${ext}`;
      try {
        if (SafeFileUtils.accessSync(iconPath)) {
          SafeFileUtils.unlinkSync(iconPath);
          logger.info(TAG, `已删除图源图标: ${pkg}.${ext}`);
        }
      } catch (_) {
        // 文件不存在，继续尝试下一个格式
      }
    }
  }

  /**
   * 保存仓库配置
   */
  private async saveRepositoryConfig(route: RepositoryRouteResult, name: string, sourceCount: number): Promise<void> {
    try {
      const savedRepos = await this.getSavedRepositories();
      
      // 生成仓库ID
      const normalizedOriginalUrl = this.normalizeRepositoryUrl(route.originalUrl || route.effectiveUrl);
      const normalizedEffectiveUrl = this.normalizeRepositoryUrl(route.effectiveUrl || route.originalUrl);
      const repoId = this.generateRepositoryId(normalizedOriginalUrl);
      
      // 检查是否已存在
      let existingIndex = savedRepos.findIndex(r => r.id === repoId);
      if (existingIndex === -1) {
        existingIndex = savedRepos.findIndex(r => this.normalizeRepositoryUrl(r.url) === normalizedOriginalUrl);
      }
      if (existingIndex === -1) {
        existingIndex = savedRepos.findIndex(r => this.normalizeRepositoryUrl(r.originalUrl ?? '') === normalizedOriginalUrl);
      }
      if (existingIndex === -1 && normalizedEffectiveUrl.length > 0) {
        existingIndex = savedRepos.findIndex(r => this.normalizeRepositoryUrl(r.url) === normalizedEffectiveUrl);
      }
      const newRepo: SavedRepository = {
        id: repoId,
        name: name,
        url: normalizedOriginalUrl,
        originalUrl: normalizedOriginalUrl,
        lastEffectiveUrl: normalizedEffectiveUrl,
        lastSync: Date.now(),
        sourceCount: sourceCount
      };

      if (existingIndex !== -1) {
        savedRepos[existingIndex] = newRepo;
      } else {
        savedRepos.push(newRepo);
      }

      // 保存
      this.writeSavedRepositoriesToFile(savedRepos);
      logger.info(TAG, `已保存仓库配置, 总数: ${savedRepos.length}`);
    } catch (error) {
      logger.error(TAG, '保存仓库配置失败', String(error));
    }
  }

  /**
   * 获取已保存的仓库列表
   */
  async getSavedRepositories(): Promise<SavedRepository[]> {
    try {
      await this.ensureSavedRepositoriesFileExists();
      const exists = SafeFileUtils.accessSync(this.savedRepositoriesPath);
      if (!exists) {
        return [];
      }

      const file = SafeFileUtils.openSync(this.savedRepositoriesPath, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(1024 * 1024); // 1MB
      const readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

      const jsonContent: string = this.decodeToString(buffer, readLen);

      return SafeUtils.parseArr(jsonContent) as SavedRepository[];
    } catch (error) {
      logger.warn(TAG, '读取已保存仓库失败', String(error));
      return [];
    }
  }

  /**
   * 删除已保存的仓库
   */
  async deleteRepository(repoId: string): Promise<boolean> {
    try {
      const savedRepos = await this.getSavedRepositories();
      const filteredRepos = savedRepos.filter(r => r.id !== repoId);
      
      this.writeSavedRepositoriesToFile(filteredRepos);
      
      return true;
    } catch (error) {
      logger.error(TAG, '删除仓库失败', String(error));
      return false;
    }
  }

  /**
   * 生成仓库ID
   */
  private generateRepositoryId(url: string): string {
    // 简单的哈希函数
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return `repo_${Math.abs(hash)}`;
  }

  /**
   * 从仓库导入图源到应用
   */
  async importSourceFromRepository(pkg: string): Promise<ImportResult> {
    try {
      const sourceJsonFromNgf = ngfSourceLoaderFacade.loadSourceJson(pkg);
      if (sourceJsonFromNgf.trim().length > 0) {
        return await this.sourceManager.importFromJSON(sourceJsonFromNgf);
      }

      const filePath = `${this.repositoryDir}/${pkg}.json`;
      const exists = SafeFileUtils.accessSync(filePath);
      
      if (!exists) {
        return {
          success: false,
          error: '图源文件不存在'
        };
      }

      // 读取图源文件
      const file = SafeFileUtils.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(1024 * 1024); // 1MB
      const readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

      const jsonContent: string = this.decodeToString(buffer, readLen);

      // 使用SourceManager导入
      return await this.sourceManager.importFromJSON(jsonContent);
    } catch (error) {
      logger.error(TAG, '从仓库导入图源失败', String(error));
      return {
        success: false,
        error: String(error)
      };
    }
  }

  /**
   * 获取仓库中的所有图源
   */
  async getRepositorySources(): Promise<SourceRepositoryEntry[]> {
    const index = await this.readIndexFile();
    return index.sources;
  }

  /**
   * 搜索仓库中的图源
   */
  async searchRepositorySources(keyword: string): Promise<SourceRepositoryEntry[]> {
    const allSources = await this.getRepositorySources();
    const lowerKeyword = keyword.toLowerCase();
    
    return allSources.filter(source => 
      source.name.toLowerCase().includes(lowerKeyword) ||
      source.pkg.toLowerCase().includes(lowerKeyword) ||
      source.sources.some(s => s.name.toLowerCase().includes(lowerKeyword))
    );
  }

  private writeSavedRepositoriesToFile(repos: SavedRepository[]): void {
    const jsonContent = JSON.stringify(repos, null, 2);
    const file = SafeFileUtils.openSync(
      this.savedRepositoriesPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    SafeFileUtils.writeSync(file.fd, jsonContent);
    SafeFileUtils.closeSync(file);
  }

  private async importNewSources(sources: SourceRepositoryEntry[]): Promise<void> {
    for (const source of sources) {
      try {
        const result = await this.importSourceFromRepository(source.pkg);
        if (result.success) {
          logger.info(TAG, `新增图源已导入: ${source.name}`);
          // 根据仓库索引中的nsfw字段自动标记NSFW
          if (source.nsfw === 1 && result.sourceId) {
            try {
              await DataManager.getInstance().updateSourceNSFW(result.sourceId, true);
              logger.info(TAG, `图源已自动标记为NSFW: ${source.name}`);
            } catch (nsfwError) {
              logger.warn(TAG, `自动标记NSFW失败: ${source.name}`, String(nsfwError));
            }
          }
        } else {
          logger.warn(TAG, `导入图源失败: ${source.name}`, result.error ?? '未知错误');
        }
      } catch (error) {
        logger.warn(TAG, `导入图源异常: ${source.name}`, String(error));
      }
    }
  }

  /**
   * 解析图源配置文件URL
   * 支持两种格式：
   * - 新格式（文件夹）: base/pkg/source.json
   * - 旧格式（扁平）: base/pkg.json
   */
  private normalizeRepositoryUrl(url: string): string {
    if (!url) {
      return '';
    }
    return url.trim();
  }

  private splitRepositoryUrlQuery(url: string): RepositoryUrlSplitResult {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return {
        baseUrl: url,
        query: ''
      };
    }

    return {
      baseUrl: url.substring(0, queryIndex),
      query: url.substring(queryIndex)
    };
  }

  private getRepositoryProxyPrefixes(): string[] {
    return [REPOSITORY_PROXY_GH, REPOSITORY_PROXY_HK_GH];
  }

  private unwrapRepositoryProxyUrl(url: string): RepositoryProxyUnwrapResult {
    const normalizedUrl = this.normalizeRepositoryUrl(url);
    const proxyPrefixes = this.getRepositoryProxyPrefixes();
    for (const prefix of proxyPrefixes) {
      if (normalizedUrl.startsWith(prefix)) {
        return {
          proxyPrefix: prefix,
          rawUrl: normalizedUrl.substring(prefix.length)
        };
      }
    }

    return {
      proxyPrefix: '',
      rawUrl: normalizedUrl
    };
  }

  private buildRepositoryProxyUrl(proxyPrefix: string, rawUrl: string): string {
    if (!proxyPrefix || !rawUrl) {
      return rawUrl;
    }
    if (rawUrl.startsWith(proxyPrefix)) {
      return rawUrl;
    }
    return `${proxyPrefix}${rawUrl}`;
  }

  private getRepositoryCandidateKindByPrefix(prefix: string): RepositoryCandidateKind {
    if (prefix === REPOSITORY_PROXY_HK_GH) {
      return 'hkGhProxy';
    }
    return 'ghProxy';
  }

  private getRepositoryCandidateLabel(kind: RepositoryCandidateKind): string {
    if (kind === 'origin') {
      return 'origin';
    }
    if (kind === 'ghProxy') {
      return 'gh-proxy';
    }
    return 'hk-gh-proxy';
  }

  private addRepositoryRouteCandidate(candidates: RepositoryRouteCandidate[], seen: Set<string>, candidate: RepositoryRouteCandidate): void {
    const normalizedCandidateUrl = this.normalizeRepositoryUrl(candidate.url);
    if (!normalizedCandidateUrl || seen.has(normalizedCandidateUrl)) {
      return;
    }

    seen.add(normalizedCandidateUrl);
    candidates.push({
      kind: candidate.kind,
      url: normalizedCandidateUrl
    });
  }

  private buildRepositoryRouteCandidates(url: string): RepositoryRouteCandidate[] {
    const normalizedInputUrl = this.normalizeRepositoryUrl(url);
    if (!normalizedInputUrl) {
      return [];
    }

    const splitResult = this.splitRepositoryUrlQuery(normalizedInputUrl);
    const unwrapped = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrapped.rawUrl}${splitResult.query}`;

    const candidates: RepositoryRouteCandidate[] = [];
    const seen = new Set<string>();

    this.addRepositoryRouteCandidate(candidates, seen, {
      kind: 'origin',
      url: originalUrl
    });

    const proxyPrefixes = this.getRepositoryProxyPrefixes();
    for (const proxyPrefix of proxyPrefixes) {
      this.addRepositoryRouteCandidate(candidates, seen, {
        kind: this.getRepositoryCandidateKindByPrefix(proxyPrefix),
        url: this.buildRepositoryProxyUrl(proxyPrefix, originalUrl)
      });
    }

    return candidates;
  }

  private async quickCheckRepositoryConnectivity(url: string): Promise<RepositoryConnectivityCheckResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: REPOSITORY_CONNECT_TIMEOUT_MS,
        readTimeout: REPOSITORY_READ_TIMEOUT_MS,
        header: {
          'Accept': 'application/json,text/plain,*/*'
        }
      };

      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        options.usingProxy = true;
      }

      const response = await request.request(url, options);
      return {
        reachable: response.responseCode >= 200 && response.responseCode < 400,
        responseCode: response.responseCode,
        errorMessage: ''
      };
    } catch (error) {
      let errorMessage = 'unknown error';
      if (error instanceof Error) {
        errorMessage = error.message;
      } else if (typeof error === 'object' && error !== null) {
        const errObj = error as Record<string, string | number | boolean>;
        if (typeof errObj.message === 'string' && errObj.message.length > 0) {
          errorMessage = errObj.message;
        } else if (errObj.code !== undefined) {
          errorMessage = `code: ${String(errObj.code)}`;
        } else {
          try {
            errorMessage = JSON.stringify(error);
          } catch (_) {
            errorMessage = String(error);
          }
        }
      } else {
        errorMessage = String(error);
      }

      return {
        reachable: false,
        responseCode: 0,
        errorMessage: errorMessage
      };
    } finally {
      try {
        request.destroy();
      } catch (_) {
        // ignore destroy errors
      }
    }
  }

  private async probeRepositoryCandidate(candidate: RepositoryRouteCandidate): Promise<RepositoryProbeResult> {
    const check = await this.quickCheckRepositoryConnectivity(candidate.url);
    return {
      candidate: candidate,
      check: check
    };
  }

  private async resolveBestRepositoryUrl(url: string, log?: RepositoryRouteLogCallback): Promise<RepositoryRouteResult> {
    const candidates = this.buildRepositoryRouteCandidates(url);
    if (candidates.length === 0) {
      throw new Error('仓库地址无效');
    }

    const probeTasks: Promise<RepositoryProbeResult>[] = [];
    for (const candidate of candidates) {
      probeTasks.push(this.probeRepositoryCandidate(candidate));
    }
    const probeResults = await Promise.all(probeTasks);

    for (const probeResult of probeResults) {
      const label = this.getRepositoryCandidateLabel(probeResult.candidate.kind);
      if (probeResult.check.reachable) {
        log?.('info', `仓库连通性通过(${label}): ${probeResult.candidate.url}`);
      } else {
        const detail = probeResult.check.responseCode > 0
          ? `HTTP ${probeResult.check.responseCode}`
          : probeResult.check.errorMessage;
        log?.('warn', `仓库连通性失败(${label}): ${probeResult.candidate.url} (${detail})`);
      }
    }

    let selected: RepositoryRouteCandidate | null = null;
    for (const candidate of candidates) {
      const matched = probeResults.find(result => result.candidate.url === candidate.url);
      if (matched && matched.check.reachable) {
        selected = candidate;
        break;
      }
    }

    if (!selected) {
      throw new Error('原始地址和加速代理均不可连通');
    }

    const splitResult = this.splitRepositoryUrlQuery(this.normalizeRepositoryUrl(url));
    const unwrappedOriginal = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const originalUrl = `${unwrappedOriginal.rawUrl}${splitResult.query}`;

    const selectedUnwrapped = this.unwrapRepositoryProxyUrl(selected.url);
    return {
      originalUrl: originalUrl,
      effectiveUrl: selected.url,
      usedProxy: selected.kind !== 'origin',
      proxyPrefix: selectedUnwrapped.proxyPrefix
    };
  }

  private resolveRepositoryAssetUrl(indexUrl: string, relativePath: string): string {
    if (!indexUrl) {
      return relativePath;
    }

    const splitResult = this.splitRepositoryUrlQuery(indexUrl);
    const unwrapped = this.unwrapRepositoryProxyUrl(splitResult.baseUrl);
    const cleanInnerIndexUrl = unwrapped.rawUrl;
    const lastSlashIndex = cleanInnerIndexUrl.lastIndexOf('/');
    const rawBaseUrl = lastSlashIndex >= 0
      ? cleanInnerIndexUrl.substring(0, lastSlashIndex + 1)
      : `${cleanInnerIndexUrl}/`;

    const rawAssetUrl = `${rawBaseUrl}${relativePath}`;
    if (!unwrapped.proxyPrefix) {
      return rawAssetUrl;
    }
    return this.buildRepositoryProxyUrl(unwrapped.proxyPrefix, rawAssetUrl);
  }

  private resolveSourceConfigUrl(indexUrl: string, pkg: string): string {
    return this.resolveRepositoryAssetUrl(indexUrl, `${pkg}/source.json`);
  }

  /**
   * 解析图源图标URL
   * 图标文件位于: base/pkg/icon.{ext}
   * 支持的格式: png, jpg, webp
   */
  private resolveSourceIconUrl(indexUrl: string, pkg: string, ext: string = 'webp'): string {
    return this.resolveRepositoryAssetUrl(indexUrl, `${pkg}/icon.${ext}`);
  }

  private deriveRepositoryName(url: string): string {
    if (!url) {
      return '在线仓库';
    }

    // 移除协议
    let remainder = url;
    const protocolSeparatorIndex = remainder.indexOf('://');
    if (protocolSeparatorIndex >= 0) {
      remainder = remainder.substring(protocolSeparatorIndex + 3);
    }

    if (remainder.length === 0) {
      return '在线仓库';
    }

    // 主机名在第一个 '/' 之前
    const slashIndex = remainder.indexOf('/');
    if (slashIndex >= 0) {
      return remainder.substring(0, slashIndex) || '在线仓库';
    }
    return remainder;
  }
}
