// 文件路径：entry/src/main/ets/pages/DownloadSyncPage.ets
/**
 * Download同步页面
 * 提供Download目录文件扫描和导入功能
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext, promptAction } from '@kit.ArkUI';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { picker } from '@kit.CoreFileKit';
import { common, abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { DataManager, ComicInfoInput, ChapterInfoInput, PageInfoInput, ComicInfo } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { MangaStatus } from '../Framework/Types/StatusEnums';
import { CompressionUtils } from '../Utils/CompressionUtils';
import { SandboxManager } from '../Framework/Storage/SandboxManager';
import { eventBus, GameEvent, MangaImportCompletedPayload } from '../Framework/EventBus';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { generateUUID } from '../Framework/Utils/UUIDGenerator';
import { PdfImportDialog, PdfImportDialogResult, PdfImportMode as DialogImportMode } from '../Framework/Components/PdfImportDialog';
import { MangaImportDialog, MangaImportDialogResult, ChapterInfo, ParsedArchiveStructure, ExistingMangaCandidate, PrefilledComicInfo } from '../Framework/Components/MangaImportDialog';
import { BatchMangaImportDialog, BatchMangaImportDialogResult, MangaGroupResult, BatchChapterResult } from '../Framework/Components/BatchMangaImportDialog';
import { ParsedArchiveStructure as CompressionParsedStructure } from '../Utils/CompressionUtils';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { EBookParserFactory, EBookCoverExtractor } from '../Framework/Parsers/EBookParser';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { NovelImportDialog, NovelImportDialogResult, TextEncoding } from '../Framework/Components/NovelImportDialog';
import { EBookMetadataDialog, EBookMetadataDialogResult } from '../Framework/Components/EBookMetadataDialog';
import { EBookMetadata, EBookChapter, EBook } from '../Models/EBookModels';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { componentSnapshot } from '@kit.ArkUI';

const TAG = 'DownloadSyncPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface NavDestinationContext {
  pathStack: NavPathStack;
}

enum ImportStatus {
  IDLE = 'idle',
  SELECTING = 'selecting',
  EXTRACTING = 'extracting',
  PARSING = 'parsing',
  PROCESSING = 'processing',
  IMPORTING = 'importing',
  COMPLETED = 'completed',
  ERROR = 'error'
}

interface ImportProgress {
  status: ImportStatus;
  message: string;
  progress: number;
  currentFile?: string;
  totalFiles?: number;
  processedFiles?: number;
}

// 文件树节点
interface FileTreeNode {
  name: string;
  path: string;
  isDirectory: boolean;
  isReserved: boolean;
  isImported: boolean;
  children: FileTreeNode[];
  expanded: boolean;
  fileType: string;
}

@Component
struct DownloadSyncPage {
  private scroller: Scroller = new Scroller();
  private sandboxManager: SandboxManager = SandboxManager.getInstance();
  
  // 封面生成器常量（基于 ebook.webp 图片精确测量）
  private static readonly COVER_WIDTH = 400;
  private static readonly COVER_HEIGHT = 600;
  private static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  private static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  private static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  private static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;
  
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DownloadSyncPage';
  
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  
  @State importProgress: ImportProgress = {
    status: ImportStatus.IDLE,
    message: '准备就绪',
    progress: 0
  };
  
  private dataManager: DataManager = DataManager.getInstance();
  private compressionUtils: CompressionUtils = CompressionUtils.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private uiContext: UIContext | undefined = undefined;
  private pdfImportDialogController: CustomDialogController | null = null;
  private mangaImportDialogController: CustomDialogController | null = null;
  private batchMangaImportDialogController: CustomDialogController | null = null;
  private novelImportDialogController: CustomDialogController | null = null;
  private ebookMetadataDialogController: CustomDialogController | null = null;
  
  // 电子书导入临时数据
  @State private pendingEbookData: EBook | null = null;
  @State private pendingEbookFolderPath: string = '';
  @State private pendingEbookSourceUri: string = '';
  @State private pendingEbookFilename: string = '';
  
  // 批量导入Promise回调
  private batchImportResolve: ((success: boolean) => void) | null = null;
  private batchImportCurrentIndex: number = 0;
  private batchImportTotalCount: number = 0;
  
  @State private currentParsedStructure: ParsedArchiveStructure | null = null;
  @State private currentFileUri: string = '';
  @State private existingMangaCandidates: ExistingMangaCandidate[] = [];
  
  // Download目录直接访问相关状态
  @State private downloadDirPath: string = '';
  @State private downloadDirUri: string = '';
  @State private downloadDirFiles: string[] = [];
  @State private downloadDirFileCount: number = 0;

  // 扫描到的待导入文件分类
  @State private pendingMangaFiles: string[] = [];
  @State private pendingEbookFiles: string[] = [];
  @State private pendingPdfFiles: string[] = [];
  @State private pendingNovelFiles: string[] = [];
  @State private isScanning: boolean = false;

  // 标签页状态
  @State private currentTabIndex: number = 0;
  // 已导入文件记录 (文件名 -> 导入状态)
  @State private importedFilesMap: Map<string, boolean> = new Map();
  // 文件树结构
  @State private fileTree: FileTreeNode[] = [];
  // 展开的节点路径集合
  @State private expandedPaths: Set<string> = new Set();

  private static readonly APP_FOLDER_NAME: string = '漫匹';
  private static readonly MANGA_EXTENSIONS: string[] = ['zip', 'cbz', 'rar', 'cbr', '7z', 'tar', 'gz'];
  private static readonly EBOOK_EXTENSIONS: string[] = ['epub', 'mobi', 'azw', 'azw3'];
  private static readonly PDF_EXTENSIONS: string[] = ['pdf'];
  private static readonly NOVEL_EXTENSIONS: string[] = ['txt'];
  // 保留文件夹（用于存储导入的文件，扫描时跳过）
  private static readonly RESERVED_FOLDERS: string[] = ['ebooks', 'manga', 'novel', 'storage', 'covers', 'temp', 'backup', 'legadoextensions'];

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    
    // 使用ThemeAwareHelper统一管理主题
    ThemeAwareHelper.initializeThemeAware(TAG, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题已切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(TAG, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    
    // 初始化响应式布局
    this.initializeResponsiveLayout();
    
    // 检查并自动初始化已存在的Download文件夹
    this.checkAndAutoInitDownloadDir();
  }

  aboutToDisappear(): void {
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
    }
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 检查并自动初始化已存在的Download文件夹
   */
  private async checkAndAutoInitDownloadDir(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) return;
      
      // 尝试读取已保存的Download目录路径
      const savedPath = AppStorage.get<string>('downloadSyncDirPath');
      const savedUri = AppStorage.get<string>('downloadSyncDirUri');
      
      if (savedPath && savedUri) {
        // 验证路径是否仍然有效
        try {
          const initFilePath = `${savedPath}/.manxia_init`;
          const exists = fs.accessSync(initFilePath);
          // accessSync返回undefined表示文件存在，抛出异常表示不存在
          logger.info(TAG, `检测到已初始化的Download目录: ${savedPath}`);
          this.downloadDirPath = savedPath;
          this.downloadDirUri = savedUri;
          // 自动扫描
          await this.scanDownloadDir();
          // 加载已导入状态
          await this.loadImportedFilesStatus();
        } catch (accessError) {
          logger.info(TAG, '已保存的路径无效，需要重新连接');
          AppStorage.delete('downloadSyncDirPath');
          AppStorage.delete('downloadSyncDirUri');
        }
      }
    } catch (e) {
      const error = e as Error;
      logger.warn(TAG, `自动初始化检查失败: ${String(error)}`);
    }
  }

  /**
   * 加载已导入文件状态
   */
  private async loadImportedFilesStatus(): Promise<void> {
    try {
      this.importedFilesMap.clear();
      
      // 获取所有本地导入的漫画
      const allComics: ComicInfo[] = await this.dataManager.getAllComics();
      for (const comic of allComics) {
        if (comic.sourceId === 'local_import' || comic.sourceId === 'download_import') {
          // 从coverUrl或其他字段提取原始文件名
          const originalFileName = this.extractOriginalFileName(comic.title);
          if (originalFileName) {
            this.importedFilesMap.set(originalFileName, true);
          }
        }
      }
      
      // 获取所有电子书
      const allEbooks = await this.ebookDataManager.getEBookList();
      for (const ebook of allEbooks) {
        const originalFileName = this.extractOriginalFileName(ebook.metadata.title);
        if (originalFileName) {
          this.importedFilesMap.set(originalFileName, true);
        }
        // 也检查文件路径
        if (ebook.filePath) {
          const pathFileName = ebook.filePath.substring(ebook.filePath.lastIndexOf('/') + 1);
          this.importedFilesMap.set(pathFileName, true);
        }
      }
      
      logger.info(TAG, `已加载 ${this.importedFilesMap.size} 个已导入文件记录`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `加载已导入状态失败: ${String(error)}`);
    }
  }

  /**
   * 从标题提取原始文件名
   */
  private extractOriginalFileName(title: string): string {
    // 移除时间戳前缀
    let cleaned = title.replace(/^\d+_/, '');
    // 如果没有扩展名，尝试添加常见扩展名进行匹配
    return cleaned;
  }

  /**
   * 检查文件是否已导入
   */
  private isFileImported(filename: string): boolean {
    // 直接匹配
    if (this.importedFilesMap.has(filename)) return true;
    // 去掉扩展名匹配
    const nameWithoutExt = filename.replace(/\.[^.]+$/, '');
    if (this.importedFilesMap.has(nameWithoutExt)) return true;
    // 模糊匹配
    const keys = Array.from(this.importedFilesMap.keys());
    for (const key of keys) {
      if (key.includes(nameWithoutExt) || nameWithoutExt.includes(key)) {
        return true;
      }
    }
    return false;
  }

  private updateProgress(status: ImportStatus, message: string, progress: number): void {
    this.importProgress = { status, message, progress };
  }

  private showDownloadSyncHelp(): void {
    const helpContent = `# Download同步帮助

## 功能介绍

Download同步功能允许您从设备的Download文件夹中导入漫画、电子书、PDF和小说文件，无需申请额外的存储权限。

## 使用步骤

### 1. 连接文件夹
首次使用时，点击"连接Download文件夹"按钮，选择您的Download目录。应用会在其中创建专属文件夹。

### 2. 放置文件
将您要导入的文件放入Download文件夹中：
- **漫画**: 支持 ZIP、CBZ、RAR、CBR、7Z 格式
- **电子书**: 支持 EPUB、MOBI、AZW、AZW3 格式
- **PDF**: 支持 PDF 格式（可转换为漫画或电子书）
- **小说**: 支持 TXT 格式

### 3. 扫描文件
点击"扫描文件"按钮，应用会自动检测可导入的文件。

### 4. 导入内容
- **快速导入**: 一键导入所有同类型文件
- **单独导入**: 点击文件列表中的导入按钮

## 文件状态说明

- ✓ **已导入**: 文件已成功导入到应用
- ○ **未导入**: 文件尚未导入

## 保留文件夹

以下文件夹为应用保留，扫描时会跳过：
- ebooks、manga、storage、covers、temp、backup

## 常见问题

**Q: 为什么扫描不到文件？**
A: 请确保文件格式正确，且不在保留文件夹中。

**Q: 导入后原文件会被删除吗？**
A: 不会，原文件保持不变。`;

    getHelpPanelManagerV2().showInlineHelp('Download同步帮助', helpContent);
  }

  private getDownloadFileExtension(filename: string): string {
    const lastDot = filename.lastIndexOf('.');
    if (lastDot === -1) return '';
    return filename.substring(lastDot + 1).toLowerCase();
  }

  private getFileIconResource(filename: string): Resource {
    const ext = this.getDownloadFileExtension(filename);
    if (DownloadSyncPage.MANGA_EXTENSIONS.includes(ext)) return $r('sys.symbol.rectangle_stack');
    if (DownloadSyncPage.EBOOK_EXTENSIONS.includes(ext)) return $r('sys.symbol.book');
    if (DownloadSyncPage.PDF_EXTENSIONS.includes(ext)) return $r('sys.symbol.doc_plaintext');
    if (DownloadSyncPage.NOVEL_EXTENSIONS.includes(ext)) return $r('sys.symbol.doc_text');
    return $r('sys.symbol.folder');
  }

  private sanitizeFolderName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').substring(0, 50);
  }

  private async accessAppDownloadDir(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取上下文' });
        return;
      }
      
      const documentViewPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      
      logger.info(TAG, '开始使用DOWNLOAD模式创建应用目录...');
      
      documentViewPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
        if (documentSaveResult.length > 0) {
          const uri = documentSaveResult[0];
          logger.info(TAG, `DOWNLOAD模式返回URI: ${uri}`);
          
          const uriObj = new fileUri.FileUri(uri);
          this.downloadDirPath = uriObj.path;
          this.downloadDirUri = uri;
          
          try {
            const testFilePath = new fileUri.FileUri(uri + '/.manxia_init').path;
            const file = fs.openSync(testFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
            fs.writeSync(file.fd, '漫匣应用目录初始化文件');
            fs.closeSync(file.fd);
            logger.info(TAG, `成功创建初始化文件: ${testFilePath}`);
          } catch (writeError) {
            logger.warn(TAG, `创建初始化文件失败: ${String(writeError)}`);
          }
          
          // 创建保留文件夹
          this.createReservedFolders();
          
          // 保存路径到AppStorage以便下次自动加载
          AppStorage.setOrCreate('downloadSyncDirPath', this.downloadDirPath);
          AppStorage.setOrCreate('downloadSyncDirUri', this.downloadDirUri);
          
          // [新增] 持久化保存到数据库
          this.saveDownloadSyncSettings();
          
          // 自动扫描文件
          this.scanDownloadDir().then(() => {
            this.loadImportedFilesStatus();
            promptAction.showToast({ message: `目录连接成功，已扫描 ${this.downloadDirFileCount} 个文件` });
          });
        }
      }).catch((err: Error) => {
        logger.error(TAG, `DOWNLOAD模式失败: ${err.message}`);
        promptAction.showToast({ message: `创建失败: ${err.message}` });
      });
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `访问Download目录失败: ${String(error)}`);
      promptAction.showToast({ message: `访问失败: ${String(error)}` });
    }
  }

  /**
   * 创建保留文件夹
   */
  private createReservedFolders(): void {
    for (const folderName of DownloadSyncPage.RESERVED_FOLDERS) {
      try {
        const folderPath = `${this.downloadDirPath}/${folderName}`;
        if (!fs.accessSync(folderPath)) {
          fs.mkdirSync(folderPath);
          logger.info(TAG, `创建保留文件夹: ${folderName}`);
        }
      } catch (e) {
        // 文件夹可能已存在或创建失败
        try {
          fs.mkdirSync(`${this.downloadDirPath}/${folderName}`);
        } catch (mkdirError) {
          logger.warn(TAG, `创建文件夹 ${folderName} 失败: ${String(mkdirError)}`);
        }
      }
    }
  }

  /**
   * 检查是否为保留文件夹
   */
  private isReservedFolder(name: string): boolean {
    return DownloadSyncPage.RESERVED_FOLDERS.includes(name.toLowerCase());
  }

  /**
   * 持久化保存Download同步设置到数据库
   */
  private async saveDownloadSyncSettings(): Promise<void> {
    try {
      const settingsManager = SettingsManager.getInstance();
      if (this.downloadDirPath) {
        await settingsManager.setString(SettingKeys.DOWNLOAD_SYNC_DIR_PATH, this.downloadDirPath);
      }
      if (this.downloadDirUri) {
        await settingsManager.setString(SettingKeys.DOWNLOAD_SYNC_DIR_URI, this.downloadDirUri);
      }
      logger.info(TAG, '✅ Download同步设置已保存到数据库');
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `保存Download同步设置失败: ${String(error)}`);
    }
  }

  private async scanDownloadDir(): Promise<void> {
    if (!this.downloadDirPath) {
      promptAction.showToast({ message: '请先访问Download目录' });
      return;
    }
    
    this.isScanning = true;
    this.pendingMangaFiles = [];
    this.pendingEbookFiles = [];
    this.pendingPdfFiles = [];
    this.pendingNovelFiles = [];
    this.downloadDirFiles = [];
    this.fileTree = [];
    
    try {
      // 递归扫描整个目录树
      this.fileTree = this.scanDirectoryRecursive(this.downloadDirPath, '');
      
      // 统计文件数量
      this.downloadDirFileCount = this.countFilesInTree(this.fileTree);
      
      // 收集所有可导入文件的相对路径
      this.collectImportableFiles(this.fileTree, '');
      
      const totalPending = this.pendingMangaFiles.length + this.pendingEbookFiles.length + 
                          this.pendingPdfFiles.length + this.pendingNovelFiles.length;
      
      logger.info(TAG, `扫描完成: 漫画=${this.pendingMangaFiles.length}, 电子书=${this.pendingEbookFiles.length}, PDF=${this.pendingPdfFiles.length}, 小说=${this.pendingNovelFiles.length}`);
      promptAction.showToast({ message: `扫描完成，发现 ${totalPending} 个可导入文件` });
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `扫描目录失败: ${String(error)}`);
      promptAction.showToast({ message: `扫描失败: ${String(error)}` });
    } finally {
      this.isScanning = false;
    }
  }

  /**
   * 递归扫描目录
   */
  private scanDirectoryRecursive(basePath: string, relativePath: string): FileTreeNode[] {
    const result: FileTreeNode[] = [];
    const currentPath = relativePath ? `${basePath}/${relativePath}` : basePath;
    
    try {
      const entries = fs.listFileSync(currentPath);
      
      for (const entry of entries) {
        if (entry.startsWith('.')) continue;
        
        const entryPath = relativePath ? `${relativePath}/${entry}` : entry;
        const fullPath = `${basePath}/${entryPath}`;
        const isReserved = this.isReservedFolder(entry);
        
        try {
          const stat = fs.statSync(fullPath);
          const isDir = stat.isDirectory();
          
          const node: FileTreeNode = {
            name: entry,
            path: entryPath,
            isDirectory: isDir,
            isReserved: isReserved,
            isImported: !isDir && this.isFileImported(entry),
            children: [],
            expanded: false,
            fileType: isDir ? 'folder' : this.getFileTypeLabel(entry)
          };
          
          // 如果是目录且不是保留文件夹，递归扫描
          if (isDir && !isReserved) {
            node.children = this.scanDirectoryRecursive(basePath, entryPath);
          }
          
          result.push(node);
        } catch (statError) {
          logger.warn(TAG, `获取文件状态失败: ${fullPath}`);
        }
      }
    } catch (e) {
      logger.warn(TAG, `扫描目录失败: ${currentPath}`);
    }
    
    // 排序：文件夹在前，文件在后
    result.sort((a, b) => {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.localeCompare(b.name);
    });
    
    return result;
  }

  /**
   * 统计文件树中的文件数量
   */
  private countFilesInTree(nodes: FileTreeNode[]): number {
    let count = 0;
    for (const node of nodes) {
      if (node.isDirectory) {
        if (!node.isReserved) {
          count += this.countFilesInTree(node.children);
        }
      } else {
        count++;
      }
    }
    return count;
  }

  /**
   * 收集可导入文件
   */
  private collectImportableFiles(nodes: FileTreeNode[], parentPath: string): void {
    for (const node of nodes) {
      if (node.isReserved) continue;
      
      const fullRelativePath = parentPath ? `${parentPath}/${node.name}` : node.name;
      
      if (node.isDirectory) {
        this.collectImportableFiles(node.children, fullRelativePath);
      } else {
        const ext = this.getDownloadFileExtension(node.name);
        this.downloadDirFiles.push(fullRelativePath);
        
        if (DownloadSyncPage.MANGA_EXTENSIONS.includes(ext)) {
          this.pendingMangaFiles.push(fullRelativePath);
        } else if (DownloadSyncPage.EBOOK_EXTENSIONS.includes(ext)) {
          this.pendingEbookFiles.push(fullRelativePath);
        } else if (DownloadSyncPage.PDF_EXTENSIONS.includes(ext)) {
          this.pendingPdfFiles.push(fullRelativePath);
        } else if (DownloadSyncPage.NOVEL_EXTENSIONS.includes(ext)) {
          this.pendingNovelFiles.push(fullRelativePath);
        }
      }
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 标签页切换 - VSCode风格
          this.buildSecondaryTabs()

          if (this.currentTabIndex === 0) {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                this.buildFolderStatusSection()
                this.buildProgressIndicator()
                Blank().height(20)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          } else {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                this.buildImportedContentSection()
                Blank().height(20)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
        .padding({
          top: this.statusBarHeight,
          bottom: this.navigationBarHeight,
          left: this.responsive_contentPadding,
          right: this.responsive_contentPadding
        })

      }
    }
    .titleBar({
      padding: { start: LengthMetrics.vp(16), end: LengthMetrics.vp(16) },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: "Download同步" },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showDownloadSyncHelp();
              }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildSecondaryTabs() {
    Scroll() {
      Row({ space: 0 }) {
        // 文件扫描与导入Tab
        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(12)
            .fontColor([this.currentTabIndex === 0
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('文件扫描与导入')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTabIndex === 0
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.currentTabIndex === 0
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.currentTabIndex === 0 ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.currentTabIndex = 0; })
        .animation({ duration: 150 })

        // 已导入管理Tab
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(12)
            .fontColor([this.currentTabIndex === 1
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('已导入管理')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTabIndex === 1
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.currentTabIndex === 1
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.currentTabIndex === 1 ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { 
          this.currentTabIndex = 1; 
          this.loadImportedFilesStatus();
        })
        .animation({ duration: 150 })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(36)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
  }

  @Builder
  buildImportedContentSection() {
    Column({ space: 16 }) {
      // 统计信息
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('已导入内容管理')
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Text('查看Download文件夹中文件的导入状态')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      // 文件树状图
      if (this.fileTree.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text('文件导入状态（树状图）')
              .fontSize(16)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Text(`${this.getImportedCount()}/${this.downloadDirFileCount} 已导入`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')

          // 渲染文件树
          ForEach(this.fileTree, (node: FileTreeNode) => {
            this.buildTreeNode(node, 0)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(48).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('暂无文件')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text('请先连接Download文件夹并扫描文件')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
      }

      // 刷新按钮
      Button({ stateEffect: true }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([Color.White])
          Text('刷新状态').fontSize(14).fontColor(Color.White).fontFamily(this.appFontFamily)
        }
      }
      .width('100%')
      .height(44)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(10)
      .onClick(() => {
        this.loadImportedFilesStatus();
        promptAction.showToast({ message: '已刷新导入状态' });
      })
    }
  }

  private getImportedCount(): number {
    let count = 0;
    for (const file of this.downloadDirFiles) {
      if (!file.startsWith('.') && this.isFileImported(file)) {
        count++;
      }
    }
    return count;
  }

  private getFileTypeLabel(filename: string): string {
    const ext = this.getDownloadFileExtension(filename);
    if (DownloadSyncPage.MANGA_EXTENSIONS.includes(ext)) return '漫画';
    if (DownloadSyncPage.EBOOK_EXTENSIONS.includes(ext)) return '电子书';
    if (DownloadSyncPage.PDF_EXTENSIONS.includes(ext)) return 'PDF';
    if (DownloadSyncPage.NOVEL_EXTENSIONS.includes(ext)) return '小说';
    return '其他';
  }

  @Builder
  buildTreeNode(node: FileTreeNode, depth: number) {
    Column() {
      Row({ space: 8 }) {
        // 缩进
        if (depth > 0) {
          Blank().width(depth * 20)
        }
        
        // 展开/折叠图标（仅目录）
        if (node.isDirectory) {
          SymbolGlyph(this.expandedPaths.has(node.path) ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            .onClick(() => {
              this.toggleNodeExpanded(node.path);
            })
        } else {
          Blank().width(14)
        }
        
        // 文件/文件夹图标
        SymbolGlyph(node.isDirectory ? $r('sys.symbol.folder_fill') : this.getFileIconResource(node.name))
          .fontSize(18)
          .fontColor([node.isReserved ? '#FF9800' : 
            (node.isDirectory ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            (node.isImported ? '#4CAF50' : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)))])
        
        // 名称
        Column({ space: 2 }) {
          Text(node.name)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(node.isReserved ? '#FF9800' : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (node.isReserved) {
            Text('保留文件夹').fontSize(10).fontFamily(this.appFontFamily).fontColor('#FF9800')
          } else if (!node.isDirectory) {
            Text(node.fileType).fontSize(10).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        
        // 状态标记
        if (!node.isDirectory && !node.isReserved) {
          if (node.isImported) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(14).fontColor(['#4CAF50'])
          } else {
            SymbolGlyph($r('sys.symbol.circle')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
        }
      }
      .width('100%')
      .padding({ top: 6, bottom: 6, left: 8, right: 8 })
      .backgroundColor(node.isReserved ? '#FFF3E0' : Color.Transparent)
      .borderRadius(6)
      
      // 递归渲染子节点
      if (node.isDirectory && this.expandedPaths.has(node.path) && node.children.length > 0) {
        ForEach(node.children, (child: FileTreeNode) => {
          this.buildTreeNode(child, depth + 1)
        }, (child: FileTreeNode) => child.path)
      }
    }
  }

  private toggleNodeExpanded(path: string): void {
    const newSet = new Set(this.expandedPaths);
    if (newSet.has(path)) {
      newSet.delete(path);
    } else {
      newSet.add(path);
    }
    this.expandedPaths = newSet;
  }

  @Builder
  buildProgressIndicator() {
    if (this.importProgress.status !== ImportStatus.IDLE) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          if (this.importProgress.status !== ImportStatus.COMPLETED && this.importProgress.status !== ImportStatus.ERROR) {
            LoadingProgress().width(20).height(20).color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          Text(this.importProgress.message)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')

        Progress({ value: this.importProgress.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(this.importProgress.status === ImportStatus.ERROR ? '#F44336' : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }

  @Builder
  buildFolderStatusSection() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('Download文件夹同步')
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        Text('访问Download目录下应用专属文件夹，无需申请受限权限。\n将文件放入该文件夹后，可直接扫描并导入。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      Column({ space: 12 }) {
        Row() {
          Text('文件夹状态')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.downloadDirPath) {
            Text('✓ 已连接').fontSize(13).fontFamily(this.appFontFamily).fontColor('#4CAF50')
          } else {
            Text('未连接').fontSize(13).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')

        if (this.downloadDirPath) {
          Column({ space: 4 }) {
            Text('路径').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            Text(this.downloadDirPath)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

          Row() {
            Column({ space: 4 }) {
              Text(`${this.downloadDirFileCount}`)
                .fontSize(24)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('总文件数').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingMangaFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
              Text('漫画').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingEbookFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#2196F3')
              Text('电子书').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingPdfFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#FF9800')
              Text('PDF').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)
          }
          .width('100%')
        }

        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text(this.downloadDirPath ? '重新连接' : '连接文件夹').fontSize(14).fontFamily(this.appFontFamily)
          }
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(10)
          .onClick(() => { this.accessAppDownloadDir(); })

          if (this.downloadDirPath) {
            Button({ stateEffect: true }) {
              Text(this.isScanning ? '扫描中...' : '扫描文件').fontSize(14).fontFamily(this.appFontFamily)
            }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(10)
            .enabled(!this.isScanning)
            .onClick(() => { this.scanDownloadDir(); })
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)

      if (this.downloadDirFiles.length > 0) {
        Column({ space: 8 }) {
          Text('文件列表')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')

          ForEach(this.downloadDirFiles.slice(0, 10), (file: string) => {
            Row({ space: 8 }) {
              SymbolGlyph(this.getFileIconResource(file)).fontSize(16).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text(file)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          })

          if (this.downloadDirFiles.length > 10) {
            Text(`... 还有 ${this.downloadDirFiles.length - 10} 个文件`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
      }

      if (this.pendingMangaFiles.length > 0 || this.pendingEbookFiles.length > 0 || this.pendingPdfFiles.length > 0 || this.pendingNovelFiles.length > 0) {
        this.buildQuickImportSection()
      }
    }
    .width('100%')
  }

  @Builder
  buildQuickImportSection() {
    Column({ space: 12 }) {
      Text('快速导入')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      if (this.pendingMangaFiles.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.rectangle_stack'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text(`漫画文件 (${this.pendingMangaFiles.length})`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button({ stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.plus_square')).fontSize(18).fontColor([Color.White])
            }
            .width(36)
            .height(32)
            .backgroundColor('#4CAF50')
            .borderRadius(6)
            .onClick(() => { this.importMangaFromDownloadDir(); })
          }
          .width('100%')
          
          ForEach(this.pendingMangaFiles.slice(0, 3), (file: string) => {
            Text(file)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 24 })
          })
          if (this.pendingMangaFiles.length > 3) {
            Text(`... 还有 ${this.pendingMangaFiles.length - 3} 个文件`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 24 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }

      if (this.pendingEbookFiles.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text(`电子书文件 (${this.pendingEbookFiles.length})`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button({ stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.plus_square')).fontSize(18).fontColor([Color.White])
            }
            .width(36)
            .height(32)
            .backgroundColor('#2196F3')
            .borderRadius(6)
            .onClick(() => { this.importEbooksFromDownloadDir(); })
          }
          .width('100%')
          
          ForEach(this.pendingEbookFiles.slice(0, 3), (file: string) => {
            Text(file)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 24 })
          })
          if (this.pendingEbookFiles.length > 3) {
            Text(`... 还有 ${this.pendingEbookFiles.length - 3} 个文件`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 24 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }

      if (this.pendingPdfFiles.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text(`PDF文件 (${this.pendingPdfFiles.length})`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button({ stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.plus_square')).fontSize(18).fontColor([Color.White])
            }
            .width(36)
            .height(32)
            .backgroundColor('#FF9800')
            .borderRadius(6)
            .onClick(() => { this.importPdfsFromDownloadDir(); })
          }
          .width('100%')
          
          ForEach(this.pendingPdfFiles.slice(0, 3), (file: string) => {
            Text(file)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 24 })
          })
          if (this.pendingPdfFiles.length > 3) {
            Text(`... 还有 ${this.pendingPdfFiles.length - 3} 个文件`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 24 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }

      // 小说文件导入
      if (this.pendingNovelFiles.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text(`小说文件 (${this.pendingNovelFiles.length})`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button({ stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.plus_square')).fontSize(18).fontColor([Color.White])
            }
            .width(36)
            .height(32)
            .backgroundColor('#9C27B0')
            .borderRadius(6)
            .onClick(() => { this.importNovelsFromDownloadDir(); })
          }
          .width('100%')
          
          ForEach(this.pendingNovelFiles.slice(0, 3), (file: string) => {
            Text(file)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 24 })
          })
          if (this.pendingNovelFiles.length > 3) {
            Text(`... 还有 ${this.pendingNovelFiles.length - 3} 个文件`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 24 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  private async importMangaFromDownloadDir(): Promise<void> {
    if (this.pendingMangaFiles.length === 0) {
      promptAction.showToast({ message: '没有待导入的漫画文件' });
      return;
    }
    
    if (this.pendingMangaFiles.length >= 2) {
      await this.showDownloadBatchImportDialog();
      return;
    }
    
    const filename = this.pendingMangaFiles[0];
    const uri = `${this.downloadDirUri}/${filename}`;
    await this.showDownloadSingleImportDialog(uri, filename);
  }

  private async showDownloadBatchImportDialog(): Promise<void> {
    const fileUris: string[] = [];
    for (let i = 0; i < this.pendingMangaFiles.length; i++) {
      const filename = this.pendingMangaFiles[i];
      const uri = `${this.downloadDirUri}/${filename}`;
      fileUris.push(uri);
    }
    
    await this.findExistingMangaCandidatesForBatch();
    
    this.batchMangaImportDialogController = new CustomDialogController({
      builder: BatchMangaImportDialog({
        themeState: this.themeState,
        fileUris: fileUris,
        existingMangaCandidates: this.existingMangaCandidates,
        parseFileStructure: async (fileUri: string): Promise<ParsedArchiveStructure | null> => {
          const parsed = await this.compressionUtils.parseArchiveStructure(fileUri);
          return this.convertToDialogStructure(parsed);
        },
        parseComicInfoXml: (xmlContent: string): PrefilledComicInfo | null => {
          return this.parseComicInfoXml(xmlContent);
        },
        onConfirm: (result: BatchMangaImportDialogResult) => {
          this.handleDownloadBatchImportResult(result);
        },
        onCancel: () => {
          this.updateProgress(ImportStatus.IDLE, '已取消批量导入', 0);
          this.pendingMangaFiles = [];
        }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });

    this.batchMangaImportDialogController.open();
    this.updateProgress(ImportStatus.IDLE, '请配置批量导入选项', 10);
  }

  private async handleDownloadBatchImportResult(result: BatchMangaImportDialogResult): Promise<void> {
    this.updateProgress(ImportStatus.IMPORTING, `开始导入...`, 10);
    let successCount = 0;
    const total = result.groups.length;
    
    for (let i = 0; i < result.groups.length; i++) {
      const group: MangaGroupResult = result.groups[i];
      this.updateProgress(ImportStatus.IMPORTING, `导入 (${i + 1}/${total}): ${group.title}`, 10 + (i / total) * 80);
      
      try {
        await this.importDownloadMangaGroup(group);
        successCount++;
      } catch (e) {
        const error = e as Error;
        logger.error(TAG, `导入失败 ${group.title}: ${String(error)}`);
      }
    }
    
    this.updateProgress(ImportStatus.COMPLETED, `完成: 成功 ${successCount}/${total}`, 100);
    promptAction.showToast({ message: `导入完成: 成功 ${successCount}` });
    this.pendingMangaFiles = [];
    
    if (successCount > 0) {
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(successCount, total));
    }
  }

  private async importDownloadMangaGroup(group: MangaGroupResult): Promise<void> {
    const mangaId = await this.dataManager.addComicInfo({
      title: group.title,
      author: group.author || '',
      description: group.description || '',
      coverUrl: '',
      sourceId: 'download_import',
      externalId: `download_${generateUUID()}`,
      status: MangaStatus.UNKNOWN,
      tags: group.tags || [],
      rating: 0,
      chapterCount: group.chapters.length,
      lastUpdateTime: Date.now()
    } as ComicInfoInput);
    
    await DataService.getInstance().addToFavorites(mangaId, group.tags || []);
    
    const folderName = this.sanitizeFolderName(group.title);
    
    // [修复] 漫画存储到manga子目录
    const mangaBaseDir = `${this.downloadDirPath}/manga`;
    try { fs.mkdirSync(mangaBaseDir); } catch (e) { /* 已存在 */ }
    const mangaPath = `${mangaBaseDir}/${folderName}`;
    try { fs.mkdirSync(mangaPath); } catch (e) { /* 已存在 */ }
    
    let firstCoverPath = '';
    
    for (let i = 0; i < group.chapters.length; i++) {
      const chapter = group.chapters[i];
      const chapterPath = `${mangaPath}/${this.sanitizeFolderName(chapter.title)}`;
      try { fs.mkdirSync(chapterPath); } catch (e) { /* 已存在 */ }
      
      const parsed = await this.compressionUtils.parseArchiveStructure(chapter.fileUri);
      const imageFiles: string[] = [];
      
      if (parsed.extractedPath) {
        const files = fs.listFileSync(parsed.extractedPath);
        for (const file of files) {
          if (/\.(jpg|jpeg|png|webp|avif)$/i.test(file)) {
            const srcPath = `${parsed.extractedPath}/${file}`;
            const destPath = `${chapterPath}/${file}`;
            try {
              fs.copyFileSync(srcPath, destPath);
              imageFiles.push(file);
            } catch (e) {
              logger.warn(TAG, `复制文件失败: ${file}`);
            }
          }
        }
      }
      
      const chapterId = await this.dataManager.addChapterInfo({
        comicId: mangaId,
        title: chapter.title,
        index: i,
        pageCount: imageFiles.length,
        isDownloaded: true,
        downloadPath: chapterPath,
        publishTime: Date.now(),
        externalId: `local_chapter_${generateUUID()}`
      } as ChapterInfoInput);
      
      await this.addPageInfoToDatabaseFromPath(chapterId, chapterPath);
      
      if (i === 0 && imageFiles.length > 0) {
        imageFiles.sort();
        firstCoverPath = `${chapterPath}/${imageFiles[0]}`;
      }
    }
    
    if (firstCoverPath) {
      const ext = firstCoverPath.substring(firstCoverPath.lastIndexOf('.'));
      const coverPath = `${mangaPath}/cover${ext}`;
      try {
        fs.copyFileSync(firstCoverPath, coverPath);
        await this.dataManager.updateComicCoverUrl(mangaId, coverPath);
        logger.info(TAG, `封面已保存: ${coverPath}`);
      } catch (e) {
        logger.warn(TAG, `保存封面失败: ${String(e)}`);
      }
    }
    
    logger.info(TAG, `Download导入成功: ${group.title}`);
  }

  private async showDownloadSingleImportDialog(fileUri: string, filename: string): Promise<void> {
    try {
      this.updateProgress(ImportStatus.PARSING, `正在解析: ${filename}`, 10);
      
      const parsed = await this.compressionUtils.parseArchiveStructure(fileUri);
      const dialogStructure: ParsedArchiveStructure = this.convertToDialogStructure(parsed);
      
      const titleMatch = filename.match(/^(.+?)(?:_[a-f0-9]+)?\.(?:zip|cbz|rar|cbr|7z)$/i);
      const title = titleMatch ? titleMatch[1] : filename.replace(/\.[^.]+$/, '');
      await this.findExistingMangaCandidates(title);
      
      this.currentFileUri = fileUri;
      this.currentParsedStructure = dialogStructure;
      
      this.mangaImportDialogController = new CustomDialogController({
        builder: MangaImportDialog({
          themeState: this.themeState,
          fileName: filename,
          parsedStructure: dialogStructure,
          existingMangaCandidates: this.existingMangaCandidates,
          sourceFileUri: fileUri,
          onConfirm: (result: MangaImportDialogResult) => {
            this.handleDownloadSingleImportResult(result);
          },
          onCancel: () => {
            this.updateProgress(ImportStatus.IDLE, '已取消导入', 0);
            this.pendingMangaFiles = [];
          }
        }),
        autoCancel: false,
        customStyle: true,
        alignment: DialogAlignment.Center
      });

      this.mangaImportDialogController.open();
      this.updateProgress(ImportStatus.IDLE, '请配置导入选项', 20);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `解析失败: ${filename}`, String(error));
      promptAction.showToast({ message: `解析失败: ${String(error)}` });
      this.pendingMangaFiles = [];
    }
  }

  private async handleDownloadSingleImportResult(result: MangaImportDialogResult): Promise<void> {
    try {
      this.updateProgress(ImportStatus.IMPORTING, '正在导入漫画...', 30);
      
      const parsed = result.parsedStructure;
      const folderName = this.sanitizeFolderName(result.title);
      
      // [修复] 漫画存储到manga子目录
      const mangaBaseDir = `${this.downloadDirPath}/manga`;
      try { fs.mkdirSync(mangaBaseDir); } catch (e) { /* 已存在 */ }
      const mangaPath = `${mangaBaseDir}/${folderName}`;
      try { fs.mkdirSync(mangaPath); } catch (e) { /* 已存在 */ }
      
      const mangaId = await this.dataManager.addComicInfo({
        title: result.title,
        author: result.author,
        description: result.description,
        coverUrl: '',
        sourceId: 'download_import',
        externalId: `download_${generateUUID()}`,
        status: MangaStatus.UNKNOWN,
        tags: result.tags,
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: Date.now()
      } as ComicInfoInput);
      
      await DataService.getInstance().addToFavorites(mangaId, result.tags);
      
      const chapterPath = `${mangaPath}/第1话`;
      try { fs.mkdirSync(chapterPath); } catch (e) { /* 已存在 */ }
      
      const imageFiles: string[] = [];
      if (parsed.extractedPath) {
        const files = fs.listFileSync(parsed.extractedPath);
        for (const file of files) {
          if (/\.(jpg|jpeg|png|webp|avif)$/i.test(file)) {
            const srcPath = `${parsed.extractedPath}/${file}`;
            const destPath = `${chapterPath}/${file}`;
            try {
              fs.copyFileSync(srcPath, destPath);
              imageFiles.push(file);
            } catch (e) {
              logger.warn(TAG, `复制文件失败: ${file}`);
            }
          }
        }
        
        if (parsed.hasComicInfo) {
          const comicInfoSrc = `${parsed.extractedPath}/ComicInfo.xml`;
          const comicInfoDest = `${mangaPath}/ComicInfo.xml`;
          try {
            fs.copyFileSync(comicInfoSrc, comicInfoDest);
            logger.info(TAG, `ComicInfo.xml已复制: ${comicInfoDest}`);
          } catch (e) {
            logger.warn(TAG, `复制ComicInfo.xml失败: ${String(e)}`);
          }
        }
      }
      
      const chapterId = await this.dataManager.addChapterInfo({
        comicId: mangaId,
        title: '第1话',
        index: 0,
        pageCount: imageFiles.length,
        isDownloaded: true,
        downloadPath: chapterPath,
        publishTime: Date.now(),
        externalId: `local_chapter_${generateUUID()}`
      } as ChapterInfoInput);
      
      await this.addPageInfoToDatabaseFromPath(chapterId, chapterPath);
      
      if (imageFiles.length > 0) {
        imageFiles.sort();
        const firstImagePath = `${chapterPath}/${imageFiles[0]}`;
        const ext = imageFiles[0].substring(imageFiles[0].lastIndexOf('.'));
        const coverPath = `${mangaPath}/cover${ext}`;
        
        try {
          fs.copyFileSync(firstImagePath, coverPath);
          await this.dataManager.updateComicCoverUrl(mangaId, coverPath);
          logger.info(TAG, `封面已保存: ${coverPath}`);
        } catch (e) {
          logger.warn(TAG, `保存封面失败: ${String(e)}`);
        }
      }
      
      this.updateProgress(ImportStatus.COMPLETED, '导入完成', 100);
      promptAction.showToast({ message: '导入成功' });
      this.pendingMangaFiles = [];
      
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(1, 1));
      
      if (result.sourceFileUri) {
        this.askDeleteSourceFile(result.sourceFileUri, result.title);
      }
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `导入失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  private askDeleteSourceFile(fileUri: string, title: string): void {
    AlertDialog.show({
      title: '删除原文件',
      message: `漫画"${title}"已成功导入。\n是否删除原压缩包文件以节省空间？`,
      primaryButton: {
        value: '保留',
        action: () => {
          logger.info(TAG, `用户选择保留原文件: ${fileUri}`);
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.deleteSourceFile(fileUri);
        }
      }
    });
  }

  private deleteSourceFile(fileUri: string): void {
    try {
      let filePath = fileUri;
      if (fileUri.startsWith('file://docs/')) {
        filePath = fileUri.replace('file://docs', '');
      } else if (fileUri.startsWith('file://')) {
        filePath = fileUri.replace('file://', '');
      }
      
      fs.unlinkSync(filePath);
      logger.info(TAG, `原文件已删除: ${filePath}`);
      promptAction.showToast({ message: '原文件已删除' });
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `删除原文件失败: ${String(error)}`);
      promptAction.showToast({ message: `删除失败: ${String(error)}` });
    }
  }

  private convertToDialogStructure(parsed: CompressionParsedStructure): ParsedArchiveStructure {
    let prefilledInfo: PrefilledComicInfo | undefined = undefined;
    if (parsed.hasComicInfo && parsed.comicInfoContent) {
      const parsedInfo = this.parseComicInfoXml(parsed.comicInfoContent);
      if (parsedInfo) {
        prefilledInfo = parsedInfo;
      }
    }
    
    return {
      hasComicInfo: parsed.hasComicInfo,
      comicInfoContent: parsed.comicInfoContent,
      isMultiLayer: parsed.isMultiLayer,
      detectedChapters: parsed.detectedChapters.map(ch => {
        const chapterInfo: ChapterInfo = {
          index: ch.index,
          number: ch.number,
          title: ch.title,
          originalName: ch.originalName,
          path: ch.path,
          pageCount: ch.pageCount
        };
        return chapterInfo;
      }),
      rootImageCount: parsed.rootImageCount,
      totalImageCount: parsed.totalImageCount,
      extractedPath: parsed.extractedPath,
      tempDirectories: parsed.tempDirectories,
      warnings: parsed.warnings,
      prefilledInfo: prefilledInfo
    };
  }

  private parseComicInfoXml(xmlContent: string): PrefilledComicInfo | null {
    try {
      const getTagValue = (tag: string): string => {
        const regex = new RegExp(`<${tag}>([^<]*)</${tag}>`, 'i');
        const match = xmlContent.match(regex);
        return match ? match[1].trim() : '';
      };
      
      const series = getTagValue('Series');
      const title = getTagValue('Title');
      const number = getTagValue('Number');
      
      logger.info(TAG, `解析ComicInfo.xml: series=${series}, title=${title}, number=${number}`);
      
      return {
        title: title,
        series: series,
        number: number,
        author: getTagValue('Writer') || getTagValue('Author'),
        description: getTagValue('Summary') || getTagValue('Description'),
        tags: (getTagValue('Genre') || getTagValue('Tags')).split(',').map(t => t.trim()).filter(t => t)
      };
    } catch (e) {
      const error = e as Error;
      logger.warn(TAG, `解析ComicInfo.xml失败: ${String(error)}`);
      return null;
    }
  }

  private async findExistingMangaCandidates(fileName: string): Promise<void> {
    try {
      const possibleTitle = fileName.replace(/\.[^.]+$/, '');
      const allManga: ComicInfo[] = await this.dataManager.getAllComics();
      const localManga: ComicInfo[] = [];
      for (let i = 0; i < allManga.length; i++) {
        const m: ComicInfo = allManga[i];
        if (m.sourceId === 'local_import' || m.sourceId === 'download_import') {
          localManga.push(m);
        }
      }
      
      const candidates: ExistingMangaCandidate[] = [];
      const comicsToProcess = localManga.slice(0, 20);
      for (const manga of comicsToProcess) {
        const candidate: ExistingMangaCandidate = {
          id: manga.id,
          title: manga.title,
          author: manga.author || '未知作者',
          coverUrl: manga.coverUrl || '',
          chapterCount: manga.chapterCount || 0
        };
        candidates.push(candidate);
      }
      this.existingMangaCandidates = candidates;
      logger.info(TAG, `找到 ${candidates.length} 个可能的重复漫画`);
    } catch (e) {
      const error = e as Error;
      logger.warn(TAG, `查找现有漫画失败: ${String(error)}`);
      this.existingMangaCandidates = [];
    }
  }

  private async findExistingMangaCandidatesForBatch(): Promise<void> {
    try {
      const allComics: ComicInfo[] = await this.dataManager.getAllComics();
      const candidates: ExistingMangaCandidate[] = [];
      const comicsToProcess = allComics.slice(0, 20);
      for (const comic of comicsToProcess) {
        const candidate: ExistingMangaCandidate = {
          id: comic.id,
          title: comic.title,
          author: comic.author || '未知作者',
          coverUrl: comic.coverUrl || '',
          chapterCount: comic.chapterCount || 0
        };
        candidates.push(candidate);
      }
      this.existingMangaCandidates = candidates;
      logger.info(TAG, `批量导入找到 ${this.existingMangaCandidates.length} 个已有漫画候选`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `查找已有漫画失败: ${String(error)}`);
      this.existingMangaCandidates = [];
    }
  }

  private async addPageInfoToDatabaseFromPath(chapterId: string, chapterPath: string): Promise<void> {
    try {
      const files = fs.listFileSync(chapterPath);
      const imageFiles = files.filter((f: string) => /\.(jpg|jpeg|png|webp|avif)$/i.test(f)).sort();
      
      for (let i = 0; i < imageFiles.length; i++) {
        const imagePath = `${chapterPath}/${imageFiles[i]}`;
        const pageInput: PageInfoInput = {
          chapterId: chapterId,
          index: i,
          imageUrl: imagePath,
          width: 0,
          height: 0,
          fileSize: 0
        };
        await this.dataManager.addPageInfo(pageInput);
      }
      
      logger.info(TAG, `已添加 ${imageFiles.length} 页到数据库`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `添加页面信息失败: ${String(error)}`);
    }
  }

  private async importEbooksFromDownloadDir(): Promise<void> {
    if (this.pendingEbookFiles.length === 0) {
      promptAction.showToast({ message: '没有待导入的电子书文件' });
      return;
    }
    
    // 逐个处理电子书，每本都显示确认窗口
    const sourceFiles: string[] = [...this.pendingEbookFiles];
    this.pendingEbookFiles = [];
    this.batchImportTotalCount = sourceFiles.length;
    
    promptAction.showToast({ message: `开始导入 ${sourceFiles.length} 个电子书/小说文件` });
    
    let successCount = 0;
    let failCount = 0;
    
    for (let i = 0; i < sourceFiles.length; i++) {
      const relativePath = sourceFiles[i];
      this.batchImportCurrentIndex = i + 1;
      
      promptAction.showToast({ message: `正在处理第 ${i + 1}/${sourceFiles.length} 个: ${relativePath.substring(relativePath.lastIndexOf('/') + 1)}` });
      
      // 等待用户确认后再处理下一个
      const success = await this.showEbookMetadataDialogAsync(relativePath, i + 1, sourceFiles.length);
      
      if (success) {
        successCount++;
      } else {
        failCount++;
      }
    }
    
    // 显示最终结果
    if (successCount > 0 || failCount > 0) {
      promptAction.showToast({ 
        message: `导入完成: 成功 ${successCount} 个${failCount > 0 ? `, 失败/取消 ${failCount} 个` : ''}` 
      });
    }
    
    this.batchImportCurrentIndex = 0;
    this.batchImportTotalCount = 0;
  }

  /**
   * 显示电子书元数据确认对话框（异步等待用户确认）
   */
  private async showEbookMetadataDialogAsync(relativePath: string, currentIndex: number, totalCount: number): Promise<boolean> {
    const sourceUri = `${this.downloadDirUri}/${relativePath}`;
    const sourcePath = `${this.downloadDirPath}/${relativePath}`;
    const filename = relativePath.includes('/') ? relativePath.substring(relativePath.lastIndexOf('/') + 1) : relativePath;
    
    try {
      this.updateProgress(ImportStatus.PARSING, `正在解析第 ${currentIndex}/${totalCount} 个电子书...`, (currentIndex / totalCount) * 50);
      
      // 创建临时目录用于解析
      const ebooksBasePath = `${this.downloadDirPath}/ebooks`;
      try { fs.mkdirSync(ebooksBasePath); } catch (e) { /* 已存在 */ }
      
      const bookName = filename.replace(/\.(txt|epub|mobi|azw|azw3|pdf)$/i, '').replace(/[<>:"/\\|?*]/g, '_');
      const bookFolderPath = `${ebooksBasePath}/${bookName}`;
      try { fs.mkdirSync(bookFolderPath); } catch (e) { /* 已存在 */ }
      
      const ext = filename.includes('.') ? filename.substring(filename.lastIndexOf('.')) : '.epub';
      const targetPath = `${bookFolderPath}/${bookName}${ext}`;
      
      // 复制文件到目标位置
      fs.copyFileSync(sourcePath, targetPath);
      logger.info(TAG, `电子书复制成功: ${targetPath}`);
      
      // 解析电子书
      const parser = EBookParserFactory.createParser(targetPath);
      if (!parser) {
        logger.warn(TAG, `不支持的电子书格式: ${targetPath}`);
        promptAction.showToast({ message: `不支持的电子书格式: ${filename}` });
        return false;
      }
      
      const ebook = await parser.parse();
      logger.info(TAG, `电子书解析完成: ${ebook.metadata.title}`);
      
      // 提取封面
      await this.extractEbookCover(ebook, targetPath, bookFolderPath);
      
      // 保存临时数据
      this.pendingEbookData = ebook;
      this.pendingEbookFolderPath = bookFolderPath;
      this.pendingEbookSourceUri = sourceUri;
      this.pendingEbookFilename = relativePath;
      
      // 显示确认对话框并等待用户操作
      return await this.openEbookMetadataDialogAsync(ebook);
      
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `解析电子书失败 ${relativePath}: ${String(error)}`);
      promptAction.showToast({ message: `解析失败: ${filename}` });
      return false;
    }
  }

  /**
   * 提取电子书封面
   */
  private async extractEbookCover(ebook: EBook, filePath: string, folderPath: string): Promise<void> {
    let coverSaved = false;
    
    // 方式1：从解析器获取的封面路径复制
    if (ebook.metadata.coverImagePath) {
      try {
        const originalCoverPath = ebook.metadata.coverImagePath;
        if (fs.accessSync(originalCoverPath)) {
          const coverExt = originalCoverPath.includes('.') ? 
            originalCoverPath.substring(originalCoverPath.lastIndexOf('.')) : '.jpg';
          const newCoverPath = `${folderPath}/cover${coverExt}`;
          fs.copyFileSync(originalCoverPath, newCoverPath);
          ebook.metadata.coverImagePath = newCoverPath;
          coverSaved = true;
          logger.info(TAG, `电子书封面已保存: ${newCoverPath}`);
        }
      } catch (e) {
        logger.warn(TAG, `复制封面失败: ${String(e)}`);
      }
    }
    
    // 方式2：主动提取封面
    if (!coverSaved) {
      try {
        const extractResult = await EBookCoverExtractor.extractCover(filePath, folderPath);
        if (extractResult.success && extractResult.coverPath) {
          ebook.metadata.coverImagePath = extractResult.coverPath;
          coverSaved = true;
          logger.info(TAG, `电子书封面提取成功: ${extractResult.coverPath}`);
        }
      } catch (e) {
        logger.warn(TAG, `提取封面失败: ${String(e)}`);
      }
    }
    
    // 方式3：生成文字封面
    if (!coverSaved) {
      try {
        const coverPath = `${folderPath}/cover.webp`;
        const success = await this.generateCoverWithSnapshot(ebook.metadata.title, coverPath);
        if (success) {
          ebook.metadata.coverImagePath = coverPath;
          logger.info(TAG, `生成文字封面: ${coverPath}`);
        }
      } catch (e) {
        logger.warn(TAG, `生成封面失败: ${String(e)}`);
      }
    }
  }

  /**
   * 打开电子书元数据确认对话框（异步等待用户操作）
   */
  private openEbookMetadataDialogAsync(ebook: EBook): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.batchImportResolve = resolve;
      
      this.ebookMetadataDialogController = new CustomDialogController({
        builder: EBookMetadataDialog({
          themeState: this.themeState,
          initialMetadata: ebook.metadata,
          chapters: ebook.chapters,
          onConfirm: (result: EBookMetadataDialogResult) => {
            this.handleEbookMetadataConfirmAsync(result).then((success: boolean) => {
              if (this.batchImportResolve) {
                this.batchImportResolve(success);
                this.batchImportResolve = null;
              }
            });
          },
          onCancel: () => {
            logger.info(TAG, '用户取消电子书导入');
            this.pendingEbookData = null;
            this.updateProgress(ImportStatus.IDLE, '已取消', 0);
            if (this.batchImportResolve) {
              this.batchImportResolve(false);
              this.batchImportResolve = null;
            }
          },
          onRegenerateCover: async (title: string, oldCoverPath: string): Promise<string> => {
            return await this.regenerateEbookCover(title, oldCoverPath);
          }
        }),
        autoCancel: false,
        alignment: DialogAlignment.Center,
        customStyle: true
      });
      
      this.ebookMetadataDialogController.open();
    });
  }

  /**
   * 重新生成电子书封面
   */
  private async regenerateEbookCover(title: string, oldCoverPath: string): Promise<string> {
    if (!this.pendingEbookData || !this.pendingEbookFolderPath) {
      return '';
    }
    
    try {
      // 删除旧封面
      if (oldCoverPath) {
        try {
          await fileIo.unlink(oldCoverPath);
        } catch (e) {
          // 忽略删除失败
        }
      }
      
      const coverPath = `${this.pendingEbookFolderPath}/cover_${Date.now()}.webp`;
      const success = await this.generateCoverWithSnapshot(title, coverPath);
      if (success) {
        logger.info(TAG, `重新生成封面成功: ${coverPath}`);
        return coverPath;
      }
      return '';
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `重新生成封面失败: ${String(error)}`);
      return '';
    }
  }

  /**
   * 处理电子书元数据确认结果（异步版本，返回是否成功）
   */
  private async handleEbookMetadataConfirmAsync(result: EBookMetadataDialogResult): Promise<boolean> {
    if (!this.pendingEbookData) {
      logger.error(TAG, '没有待处理的电子书数据');
      return false;
    }
    
    try {
      this.updateProgress(ImportStatus.IMPORTING, `正在导入: ${result.metadata.title}`, 70);
      
      // 应用用户修改的元数据
      this.pendingEbookData.metadata = result.metadata;
      
      // 如果用户选择了自定义封面，复制到目标位置
      if (result.customCoverPath) {
        try {
          const coverExt = result.customCoverPath.includes('.') ? 
            result.customCoverPath.substring(result.customCoverPath.lastIndexOf('.')) : '.jpg';
          const newCoverPath = `${this.pendingEbookFolderPath}/cover${coverExt}`;
          fs.copyFileSync(result.customCoverPath, newCoverPath);
          this.pendingEbookData.metadata.coverImagePath = newCoverPath;
          logger.info(TAG, `自定义封面已保存: ${newCoverPath}`);
        } catch (e) {
          logger.warn(TAG, `保存自定义封面失败: ${String(e)}`);
        }
      }
      
      // 标记为收藏
      this.pendingEbookData.isFavorite = true;
      
      // 保存到数据库
      this.updateProgress(ImportStatus.IMPORTING, `正在保存: ${result.metadata.title}`, 90);
      await this.ebookDataManager.saveEBook(this.pendingEbookData);
      
      logger.info(TAG, `电子书导入成功: ${result.metadata.title}`);
      this.updateProgress(ImportStatus.COMPLETED, `导入成功: ${result.metadata.title}`, 100);
      promptAction.showToast({ message: `导入成功: ${result.metadata.title}` });
      
      // 批量导入时不询问删除源文件，最后统一处理
      if (this.batchImportTotalCount <= 1) {
        this.askDeleteSourceFile(this.pendingEbookSourceUri, this.pendingEbookFilename);
      }
      
      return true;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `保存电子书失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
      return false;
    } finally {
      this.pendingEbookData = null;
      this.pendingEbookFolderPath = '';
      this.pendingEbookSourceUri = '';
      this.pendingEbookFilename = '';
    }
  }

  private async continueImportEBook(sandboxPath: string): Promise<boolean> {
    return this.continueImportEBookWithFolder(sandboxPath, '');
  }

  /**
   * 导入电子书并保存封面到指定文件夹
   */
  private async continueImportEBookWithFolder(sandboxPath: string, bookFolderPath: string): Promise<boolean> {
    try {
      logger.info(TAG, `继续导入电子书: ${sandboxPath}`);
      
      this.updateProgress(ImportStatus.PARSING, '正在解析电子书...', 20);
      
      const parser = EBookParserFactory.createParser(sandboxPath);
      if (!parser) {
        this.updateProgress(ImportStatus.ERROR, '不支持的电子书格式', 0);
        logger.warn(TAG, `不支持的电子书格式: ${sandboxPath}`);
        return false;
      }

      const ebook = await parser.parse();
      logger.info(TAG, `电子书解析完成: ${ebook.metadata.title}`);
      
      this.updateProgress(ImportStatus.PROCESSING, `正在处理: ${ebook.metadata.title}`, 50);

      ebook.isFavorite = true;
      
      if (ebook.metadata.title.match(/^\d+_/)) {
        const cleanTitle = ebook.metadata.title.replace(/^\d+_/, '').replace(/\.(txt|epub|mobi|azw|azw3|pdf)$/i, '');
        if (cleanTitle.length > 0) {
          ebook.metadata.title = cleanTitle;
          logger.info(TAG, `提取真实书名: ${cleanTitle}`);
        }
      }

      // [修复] 提取并保存封面图片到电子书文件夹
      if (bookFolderPath) {
        let coverSaved = false;
        
        // 方式1：从解析器获取的封面路径复制
        if (ebook.metadata.coverImagePath) {
          try {
            const originalCoverPath = ebook.metadata.coverImagePath;
            if (fs.accessSync(originalCoverPath)) {
              const coverExt = originalCoverPath.includes('.') ? 
                originalCoverPath.substring(originalCoverPath.lastIndexOf('.')) : '.jpg';
              const newCoverPath = `${bookFolderPath}/cover${coverExt}`;
              fs.copyFileSync(originalCoverPath, newCoverPath);
              ebook.metadata.coverImagePath = newCoverPath;
              coverSaved = true;
              logger.info(TAG, `电子书封面已保存: ${newCoverPath}`);
            }
          } catch (e) {
            logger.warn(TAG, `复制封面失败: ${String(e)}`);
          }
        }
        
        // 方式2：主动提取封面（如果解析器没有提供）
        // 注意：extractCover的第二个参数是目录路径，不是文件路径
        if (!coverSaved) {
          try {
            const extractResult = await EBookCoverExtractor.extractCover(sandboxPath, bookFolderPath);
            if (extractResult.success && extractResult.coverPath) {
              ebook.metadata.coverImagePath = extractResult.coverPath;
              coverSaved = true;
              logger.info(TAG, `电子书封面提取成功: ${extractResult.coverPath}`);
            }
          } catch (e) {
            logger.warn(TAG, `提取封面失败: ${String(e)}`);
          }
        }
        
        // 方式3：检查文件夹中是否已有封面文件
        if (!coverSaved) {
          const coverFormats = ['jpg', 'jpeg', 'png', 'webp'];
          for (const ext of coverFormats) {
            const testPath = `${bookFolderPath}/cover.${ext}`;
            try {
              if (fs.accessSync(testPath)) {
                ebook.metadata.coverImagePath = testPath;
                coverSaved = true;
                logger.info(TAG, `使用已有封面: ${testPath}`);
                break;
              }
            } catch (e) {
              // 文件不存在，继续检查
            }
          }
        }
        
        if (!coverSaved) {
          logger.warn(TAG, `电子书无封面: ${ebook.metadata.title}`);
        }
      }

      await this.ebookDataManager.saveEBook(ebook);
      
      this.updateProgress(ImportStatus.COMPLETED, '电子书导入成功', 100);
      logger.info(TAG, `电子书导入成功: ${ebook.metadata.title}, ID: ${ebook.id}`);
      return true;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `电子书导入失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      return false;
    }
  }

  private async importPdfsFromDownloadDir(): Promise<void> {
    if (this.pendingPdfFiles.length === 0) {
      promptAction.showToast({ message: '没有待导入的PDF文件' });
      return;
    }
    
    const fileUris: string[] = [];
    for (let i = 0; i < this.pendingPdfFiles.length; i++) {
      const filename = this.pendingPdfFiles[i];
      const uri = `${this.downloadDirUri}/${filename}`;
      fileUris.push(uri);
    }
    
    for (let i = 0; i < fileUris.length; i++) {
      this.showPdfImportDialog(fileUris[i]);
    }
    promptAction.showToast({ message: `开始导入 ${fileUris.length} 个PDF文件` });
    this.pendingPdfFiles = [];
  }

  /**
   * 导入小说文件（txt格式）
   * 显示小说导入对话框，让用户配置元数据和章节规则
   */
  private async importNovelsFromDownloadDir(): Promise<void> {
    if (this.pendingNovelFiles.length === 0) {
      promptAction.showToast({ message: '没有待导入的小说文件' });
      return;
    }
    
    // 逐个显示导入对话框
    const sourceFiles: string[] = [...this.pendingNovelFiles];
    this.pendingNovelFiles = [];
    
    // 处理第一个文件，后续文件在对话框关闭后继续处理
    await this.showNovelImportDialogForFile(sourceFiles, 0);
  }

  /**
   * 显示小说导入对话框
   */
  private async showNovelImportDialogForFile(files: string[], index: number): Promise<void> {
    if (index >= files.length) {
      this.updateProgress(ImportStatus.COMPLETED, `小说导入完成`, 100);
      return;
    }
    
    const filename = files[index];
    const sourcePath = `${this.downloadDirPath}/${filename}`;
    const sourceUri = `${this.downloadDirUri}/${filename}`;
    
    // 提取文件名（去掉路径前缀）
    const displayName = filename.includes('/') ? filename.substring(filename.lastIndexOf('/') + 1) : filename;
    const defaultTitle = displayName.replace(/\.txt$/i, '').replace(/^\d+_/, '');
    
    // 提取文件夹路径
    const folderPath = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
    
    this.novelImportDialogController = new CustomDialogController({
      builder: NovelImportDialog({
        themeState: this.themeState,
        defaultTitle: defaultTitle,
        filePath: sourcePath,
        folderPath: folderPath,
        onConfirm: (result: NovelImportDialogResult) => {
          this.handleNovelImportResult(result, sourcePath, sourceUri, displayName).then(() => {
            // 处理下一个文件
            this.showNovelImportDialogForFile(files, index + 1);
          });
        },
        onCancel: () => {
          this.updateProgress(ImportStatus.IDLE, '已取消小说导入', 0);
          // 询问是否继续处理剩余文件
          if (index < files.length - 1) {
            AlertDialog.show({
              title: '继续导入',
              message: `还有 ${files.length - index - 1} 个小说文件未处理，是否继续？`,
              primaryButton: {
                value: '继续',
                action: () => {
                  this.showNovelImportDialogForFile(files, index + 1);
                }
              },
              secondaryButton: {
                value: '取消全部',
                action: () => {
                  logger.info(TAG, '用户取消所有小说导入');
                }
              }
            });
          }
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    this.novelImportDialogController.open();
    this.updateProgress(ImportStatus.IDLE, `配置小说导入 (${index + 1}/${files.length})`, 10);
  }

  /**
   * 处理小说导入结果
   */
  private async handleNovelImportResult(
    result: NovelImportDialogResult, 
    sourcePath: string, 
    sourceUri: string,
    filename: string
  ): Promise<void> {
    try {
      this.updateProgress(ImportStatus.IMPORTING, `正在导入: ${result.title}`, 30);
      
      // 创建novel子目录
      const novelBasePath = `${this.downloadDirPath}/novel`;
      try { fs.mkdirSync(novelBasePath); } catch (e) { /* 已存在 */ }
      
      // 为小说创建单独的文件夹
      const bookName = result.title.replace(/[<>:"/\\|?*]/g, '_');
      const bookFolderPath = `${novelBasePath}/${bookName}`;
      try { fs.mkdirSync(bookFolderPath); } catch (e) { /* 已存在 */ }
      
      const targetPath = `${bookFolderPath}/${bookName}.txt`;
      
      // 处理文件：应用替换净化规则并确保UTF-8编码
      await this.processAndSaveNovelFile(sourcePath, targetPath, result);
      logger.info(TAG, `小说处理并保存成功: ${targetPath}`);
      
      this.updateProgress(ImportStatus.IMPORTING, `正在解析: ${result.title}`, 50);
      
      // 使用自定义元数据导入
      const importSuccess = await this.continueImportNovelWithMetadata(
        targetPath, 
        bookFolderPath, 
        result
      );
      
      if (importSuccess) {
        this.updateProgress(ImportStatus.COMPLETED, `导入成功: ${result.title}`, 100);
        promptAction.showToast({ message: `小说导入成功: ${result.title}` });
        this.askDeleteSourceFile(sourceUri, filename);
      } else {
        this.updateProgress(ImportStatus.ERROR, `导入失败: ${result.title}`, 0);
      }
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `导入小说失败 ${filename}: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  /**
   * 处理并保存小说文件
   * 应用替换净化规则，删除广告行，确保UTF-8编码输出
   */
  private async processAndSaveNovelFile(
    sourcePath: string,
    targetPath: string,
    result: NovelImportDialogResult
  ): Promise<void> {
    try {
      // 读取源文件
      const file = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      
      // 根据用户选择的编码解码文件内容
      let encoding = 'utf-8';
      switch (result.encoding) {
        case TextEncoding.UTF8:
          encoding = 'utf-8';
          break;
        case TextEncoding.GBK:
          encoding = 'gbk';
          break;
        case TextEncoding.GB2312:
          encoding = 'gb2312';
          break;
        case TextEncoding.BIG5:
          encoding = 'big5';
          break;
        case TextEncoding.AUTO:
        default:
          // 自动检测编码
          encoding = this.detectFileEncoding(new Uint8Array(buffer));
          break;
      }
      
      const decoder = new util.TextDecoder(encoding);
      let content = decoder.decodeToString(new Uint8Array(buffer));
      logger.info(TAG, `文件解码完成，使用编码: ${encoding}, 内容长度: ${content.length}`);
      
      // 应用替换净化规则
      if (result.enableReplaceRules && result.adLinesToRemove && result.adLinesToRemove.length > 0) {
        const lines = content.split('\n');
        const adLineSet = new Set(result.adLinesToRemove);
        const filteredLines: string[] = [];
        
        for (let i = 0; i < lines.length; i++) {
          // 行号从1开始
          if (!adLineSet.has(i + 1)) {
            filteredLines.push(lines[i]);
          }
        }
        
        content = filteredLines.join('\n');
        logger.info(TAG, `已删除 ${result.adLinesToRemove.length} 行广告内容`);
      }
      
      // 使用UTF-8编码保存文件（确保阅读器能正常读取）
      const encoder = new util.TextEncoder('utf-8');
      const utf8Buffer = encoder.encodeInto(content);
      
      const targetFile = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(targetFile.fd, utf8Buffer.buffer);
      fileIo.closeSync(targetFile);
      
      logger.info(TAG, `文件已保存为UTF-8编码: ${targetPath}`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `处理小说文件失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 检测文件编码
   */
  private detectFileEncoding(bytes: Uint8Array): string {
    // UTF-8 BOM
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    // UTF-16 LE BOM
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'utf-16le';
    }
    // UTF-16 BE BOM
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return 'utf-16be';
    }
    
    // 简单的GBK/UTF-8检测
    let utf8Score = 0;
    let gbkScore = 0;
    
    for (let i = 0; i < Math.min(bytes.length, 10000); i++) {
      const b = bytes[i];
      
      // UTF-8多字节序列检测
      if (b >= 0xC0 && b <= 0xDF && i + 1 < bytes.length) {
        if ((bytes[i + 1] & 0xC0) === 0x80) {
          utf8Score++;
          i++;
        }
      } else if (b >= 0xE0 && b <= 0xEF && i + 2 < bytes.length) {
        if ((bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80) {
          utf8Score += 2;
          i += 2;
        }
      }
      
      // GBK双字节检测
      if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
        const b2 = bytes[i + 1];
        if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
          gbkScore++;
          i++;
        }
      }
    }
    
    // 如果GBK得分明显高于UTF-8，使用GBK
    if (gbkScore > utf8Score * 2 && gbkScore > 10) {
      return 'gbk';
    }
    
    return 'utf-8';
  }

  /**
   * 使用自定义元数据导入小说
   */
  private async continueImportNovelWithMetadata(
    sandboxPath: string, 
    bookFolderPath: string,
    metadata: NovelImportDialogResult
  ): Promise<boolean> {
    try {
      logger.info(TAG, `导入小说: ${metadata.title}, 作者: ${metadata.author}`);
      
      this.updateProgress(ImportStatus.PARSING, '正在解析小说...', 60);
      
      const parser = EBookParserFactory.createParser(sandboxPath);
      if (!parser) {
        this.updateProgress(ImportStatus.ERROR, '不支持的文件格式', 0);
        logger.warn(TAG, `不支持的文件格式: ${sandboxPath}`);
        return false;
      }

      const ebook = await parser.parse();
      logger.info(TAG, `小说解析完成，原标题: ${ebook.metadata.title}`);
      
      this.updateProgress(ImportStatus.PROCESSING, `正在处理: ${metadata.title}`, 70);

      // 应用用户自定义的元数据
      ebook.metadata.title = metadata.title;
      ebook.metadata.author = metadata.author || '未知作者';
      ebook.metadata.description = metadata.description || '';
      ebook.metadata.tags = metadata.tags || [];
      ebook.isFavorite = true;
      
      this.updateProgress(ImportStatus.PROCESSING, '正在处理封面...', 80);

      // 处理封面
      if (bookFolderPath) {
        let coverSaved = false;
        
        // 方式1：使用用户在对话框中选择/生成的封面
        if (metadata.coverPath) {
          try {
            // 如果封面路径不在目标文件夹中，复制过去
            if (!metadata.coverPath.startsWith(bookFolderPath)) {
              const coverExt = metadata.coverPath.includes('.') ? 
                metadata.coverPath.substring(metadata.coverPath.lastIndexOf('.')) : '.jpg';
              const newCoverPath = `${bookFolderPath}/cover${coverExt}`;
              fs.copyFileSync(metadata.coverPath, newCoverPath);
              ebook.metadata.coverImagePath = newCoverPath;
              logger.info(TAG, `封面已复制到: ${newCoverPath}`);
            } else {
              ebook.metadata.coverImagePath = metadata.coverPath;
              logger.info(TAG, `使用对话框封面: ${metadata.coverPath}`);
            }
            coverSaved = true;
          } catch (e) {
            logger.warn(TAG, `复制封面失败: ${String(e)}`);
          }
        }
        
        // 方式2：检查文件夹中是否已有封面文件
        if (!coverSaved) {
          const coverFormats = ['jpg', 'jpeg', 'png', 'webp'];
          for (const ext of coverFormats) {
            const testPath = `${bookFolderPath}/cover.${ext}`;
            try {
              fs.accessSync(testPath);
              ebook.metadata.coverImagePath = testPath;
              coverSaved = true;
              logger.info(TAG, `使用已有封面: ${testPath}`);
              break;
            } catch (e) {
              // 文件不存在，继续检查
            }
          }
        }
        
        // 方式3：生成文字封面
        if (!coverSaved) {
          try {
            const coverPath = `${bookFolderPath}/cover.webp`;
            const success = await this.generateCoverWithSnapshot(metadata.title, coverPath);
            if (success) {
              ebook.metadata.coverImagePath = coverPath;
              coverSaved = true;
              logger.info(TAG, `生成文字封面: ${coverPath}`);
            }
          } catch (e) {
            logger.warn(TAG, `生成封面失败: ${String(e)}`);
          }
        }
        
        if (!coverSaved) {
          logger.info(TAG, `小说无封面: ${metadata.title}`);
        }
      }

      this.updateProgress(ImportStatus.IMPORTING, '正在保存到数据库...', 90);
      
      await this.ebookDataManager.saveEBook(ebook);
      
      logger.info(TAG, `小说导入成功: ${metadata.title}, ID: ${ebook.id}`);
      return true;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `小说导入失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      return false;
    }
  }

  /**
   * 使用 componentSnapshot 生成封面
   */
  private async generateCoverWithSnapshot(title: string, outputPath: string): Promise<boolean> {
    try {
      const pixelMap = await componentSnapshot.createFromBuilder(
        () => { this.buildCoverForSnapshot(title); }
      );
      
      if (!pixelMap) {
        logger.warn(TAG, '封面生成失败: PixelMap 为空');
        return false;
      }
      
      const success = await this.savePixelMapToFile(pixelMap, outputPath);
      pixelMap.release();
      return success;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `封面生成异常: ${String(error)}`);
      return false;
    }
  }

  /**
   * 构建封面组件（用于 componentSnapshot）
   */
  @Builder
  buildCoverForSnapshot(title: string) {
    Stack() {
      // 底层：默认封面图片
      Image($r('app.media.ebook'))
        .width(DownloadSyncPage.COVER_WIDTH)
        .height(DownloadSyncPage.COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      // 标题文字层
      Text(this.formatCoverTitle(title))
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(DownloadSyncPage.COVER_WIDTH * (DownloadSyncPage.TITLE_AREA_RIGHT_PERCENT - DownloadSyncPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: DownloadSyncPage.COVER_HEIGHT * (DownloadSyncPage.TITLE_AREA_BOTTOM_PERCENT - DownloadSyncPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: DownloadSyncPage.COVER_WIDTH * DownloadSyncPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: DownloadSyncPage.COVER_HEIGHT * (DownloadSyncPage.TITLE_AREA_TOP_PERCENT + DownloadSyncPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(DownloadSyncPage.COVER_WIDTH)
    .height(DownloadSyncPage.COVER_HEIGHT)
  }

  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }

  /**
   * 根据标题长度计算合适的字体大小
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    if (length <= 2) return 70;
    else if (length <= 4) return 56;
    else if (length <= 6) return 48;
    else if (length <= 8) return 36;
    else if (length <= 12) return 32;
    else if (length <= 16) return 28;
    else return 24;
  }

  /**
   * 将 PixelMap 保存为图片文件
   */
  private async savePixelMapToFile(pixelMap: image.PixelMap, filePath: string): Promise<boolean> {
    try {
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      try {
        await fileIo.mkdir(dirPath);
      } catch (e) {
        // 目录可能已存在
      }
      
      const imagePacker = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: 'image/webp',
        quality: 90
      };
      
      const arrayBuffer = await imagePacker.packing(pixelMap, packOptions);
      const file = await fileIo.open(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, arrayBuffer);
      await fileIo.close(file.fd);
      imagePacker.release();
      
      logger.info(TAG, `封面图片已保存: ${filePath}`);
      return true;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `保存封面失败: ${String(error)}`);
      return false;
    }
  }

  private showPdfImportDialog(fileUri: string): void {
    const filename = fileUri.substring(fileUri.lastIndexOf('/') + 1);
    const defaultTitle = filename.replace(/\.pdf$/i, '');
    
    this.pdfImportDialogController = new CustomDialogController({
      builder: PdfImportDialog({
        themeState: this.themeState,
        defaultTitle: defaultTitle,
        defaultAuthor: '',
        onConfirm: (result: PdfImportDialogResult) => {
          this.handlePdfImportResult(result, fileUri);
        },
        onCancel: () => {
          this.updateProgress(ImportStatus.IDLE, '已取消PDF导入', 0);
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    this.pdfImportDialogController.open();
  }

  private async handlePdfImportResult(result: PdfImportDialogResult, fileUri: string): Promise<void> {
    try {
      this.updateProgress(ImportStatus.IMPORTING, '正在导入PDF...', 30);
      
      promptAction.showToast({ message: `PDF导入: ${result.title}` });
      logger.info(TAG, `PDF导入请求: ${result.title}, 文件: ${fileUri}`);
      
      this.updateProgress(ImportStatus.COMPLETED, 'PDF导入完成', 100);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `PDF导入失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `PDF导入失败: ${String(error)}`, 0);
    }
  }
}

export { DownloadSyncPage };
