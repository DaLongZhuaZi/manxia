import { common, Want } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { fileUri } from '@kit.CoreFileKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { getNetworkFolderManager, NetworkFolderManager } from '../Framework/Network/NetworkFolderManager';
import { BackgroundTaskManager, TaskType, TaskNotificationScene, TaskStatus } from '../Framework/Task/BackgroundTaskManager';
import type { BackgroundTask, TaskStatusListener } from '../Framework/Task/BackgroundTaskManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import {
  NetworkFolderCacheDetail,
  NetworkFolderDirectoryCacheDetail,
  NetworkFolderDownloadCacheDetail,
  NetworkFolderDownloadResult,
  createEmptyNetworkFolderDraft,
  createNetworkFolderConnection,
  draftFromNetworkFolderConnection,
  draftFromScanResult,
  getNetworkFolderFileExtension,
  getNetworkFolderProtocolLabel,
  getScanProtocolLabel,
  mapScanProtocolToFolderProtocol,
  NetworkFolderCacheStats,
  NetworkFolderConnection,
  NetworkFolderConnectionDraft,
  NetworkFolderEntry,
  NetworkFolderImportCategory,
  NetworkFolderProtocol,
  NetworkSMBEnumResult,
  NetworkSMBShare,
  NetworkScanHost,
  NetworkScanProgress,
  ProtocolPort
} from '../Models/NetworkFolderModels';
import { NetworkScannerAdapter } from '../Framework/Network/NetworkScannerAdapter';
import { openExternalFileTaskInIsolatedAbility } from '../Framework/ExternalFile/ExternalFileTaskLauncher';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskKind,
  ExternalFileTaskParams,
  ExternalFileTaskSource
} from '../Framework/ExternalFile/ExternalFileTaskTypes';

const TAG = 'NetworkFolderPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const ACCENT_COLOR: string = '#0F8A6C';
const INFO_COLOR: string = '#1F7AE0';
const DANGER_COLOR: string = '#C74848';
const ACTION_STYLE_NEUTRAL: number = 0;
const ACTION_STYLE_PRIMARY: number = 1;
const ACTION_STYLE_INFO: number = 2;
const ACTION_STYLE_DANGER: number = 3;
const ENTRY_NAME_MARQUEE_INTERVAL_MS: number = 260;
const ENTRY_NAME_MARQUEE_GAP: string = '   ';

interface NavDestinationContext {
  pathStack: NavPathStack;
}

interface NetworkFolderImportNavParam {
  fromPage: string;
  timestamp: number;
}

interface NetworkFolderBreadcrumb {
  label: string;
  path: string;
}

@Component
export struct NetworkFolderPage {
  private connectionScroller: Scroller = new Scroller();
  private browserScroller: Scroller = new Scroller();
  private dialogScroller: Scroller = new Scroller();
  private manager: NetworkFolderManager = getNetworkFolderManager();
  private componentId: string = TAG;
  private pathStack: NavPathStack = new NavPathStack();
  private protocolOptions: NetworkFolderProtocol[] = ['webdav', 'ftp', 'ftps', 'sftp', 'smb'];

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @State connections: NetworkFolderConnection[] = [];
  @State selectedConnectionId: string = '';
  @State currentPath: string = '/';
  @State entries: NetworkFolderEntry[] = [];
  @State cacheStats: NetworkFolderCacheStats = { directoryCount: 0, fileCount: 0, totalBytes: 0 };
  @State statusMessage: string = '支持 WebDAV、FTP、FTPS、SFTP、SMB，可浏览远程目录、缓存文件并直接导入。';
  @State isInitializing: boolean = false;
  @State isLoadingDirectory: boolean = false;
  @State isCaching: boolean = false;
  @State activeCacheTaskId: string = '';
  @State isCurrentPathFavorite: boolean = false;
  @State isTogglingFavorite: boolean = false;
  @State favDialogMounted: boolean = false;
  @State favDialogBackdropOpacity: number = 0;
  @State favDialogOpacity: number = 0;
  @State favDialogScale: number = 0.96;
  @State favDialogTranslateY: number = 24;
  @State favoriteFolders: string[] = [];
  private taskStatusListener: TaskStatusListener | null = null;
  private scrollPositionMap: Map<string, number> = new Map<string, number>();
  private scannerAdapter: NetworkScannerAdapter = new NetworkScannerAdapter();

  @State scanMounted: boolean = false;
  @State scanSubnet: string = '';
  @State scanProgress: NetworkScanProgress = { scannedHosts: 0, totalHosts: 254, currentIP: '' };
  @State scanResults: NetworkScanHost[] = [];
  @State scanPhase: string = 'idle';
  @State scanBackdropOpacity: number = 0;
  @State scanOpacity: number = 0;
  @State scanScale: number = 0.96;
  @State scanTranslateY: number = 24;
  @State scanStartTime: number = 0;
  @State scanDurationMs: number = 0;
  @State smbEnumLoading: boolean = false;
  @State smbEnumHost: string = '';
  @State smbEnumShares: NetworkSMBShare[] = [];

  @State viewMode: string = 'connections';
  @State pageReady: boolean = false;
  @State routeOpacity: number = 1;
  @State routeTranslateX: number = 0;
  @State routeScale: number = 1;
  @State directoryOpacity: number = 1;
  @State directoryTranslateX: number = 0;
  @State directoryScale: number = 1;
  @State isPageRefreshing: boolean = false;
  @State showFloatingCapsule: boolean = false;
  @State floatingCapsuleText: string = '';
  @State entryNameMarqueeTick: number = 0;

  @State dialogMounted: boolean = false;
  @State dialogMode: string = 'create';
  @State dialogDraft: NetworkFolderConnectionDraft = createEmptyNetworkFolderDraft();
  @State dialogStatusMessage: string = '请填写连接信息。';
  @State dialogStatusExpanded: boolean = false;
  @State dialogStatusDetailVisible: boolean = false;
  @State dialogStatusDetailHeight: number = 0;
  @State dialogStatusDetailOpacity: number = 0;
  @State dialogStatusDetailTranslateY: number = -6;
  @State dialogTesting: boolean = false;
  @State dialogSaving: boolean = false;
  @State dialogBackdropOpacity: number = 0;
  @State dialogOpacity: number = 0;
  @State dialogScale: number = 0.96;
  @State dialogTranslateY: number = 24;
  @State cacheDetailConnectionId: string = '';
  @State cacheDetailStats: NetworkFolderCacheStats = { directoryCount: 0, fileCount: 0, totalBytes: 0 };
  @State cacheDirectoryDetails: NetworkFolderDirectoryCacheDetail[] = [];
  @State cacheFileDetails: NetworkFolderDownloadCacheDetail[] = [];
  private cacheReturnView: string = 'connections';
  private floatingCapsuleTimer: number = -1;
  private entryNameMarqueeTimer: number = -1;

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, undefined, (newState: ThemeAwareState) => {
      this.themeState = newState;
    });
    this.startEntryNameMarqueeTicker();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    this.hideFloatingCapsuleImmediately();
    this.stopEntryNameMarqueeTicker();
    if (this.taskStatusListener) {
      BackgroundTaskManager.getInstance().removeListener(this.taskStatusListener);
      this.taskStatusListener = null;
    }
  }

  private handleTitleBarBack(): boolean {
    if (this.favDialogMounted) {
      this.closeFavoritesDialog();
      return true;
    }
    if (this.scanMounted) {
      this.closeScanPanel();
      return true;
    }
    if (this.dialogMounted) {
      this.closeConnectionDialog();
      return true;
    }
    if (this.viewMode === 'cache') {
      void this.leaveCacheDetailView();
      return true;
    }
    if (this.viewMode === 'browser') {
      if (this.currentPath !== '/') {
        void this.goParentDirectory();
      } else {
        void this.returnToConnections();
      }
      return true;
    }
    return false;
  }

  private color(type: 'background' | 'panel_background' | 'comp_background_tertiary' | 'comp_background_secondary' |
    'text_primary' | 'text_secondary' | 'text_muted' | 'text_white' | 'text_black' | 'button_secondary' |
    'button_text_secondary' | 'icon_primary' | 'accent_primary'): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor(type, this.themeState.currentTheme);
  }

  private startEntryNameMarqueeTicker(): void {
    if (this.entryNameMarqueeTimer >= 0) {
      clearInterval(this.entryNameMarqueeTimer);
      this.entryNameMarqueeTimer = -1;
    }
    this.entryNameMarqueeTimer = setInterval(() => {
      if (this.viewMode !== 'browser' || this.entries.length === 0) {
        return;
      }
      this.entryNameMarqueeTick = (this.entryNameMarqueeTick + 1) % 4096;
    }, ENTRY_NAME_MARQUEE_INTERVAL_MS);
  }

  private stopEntryNameMarqueeTicker(): void {
    if (this.entryNameMarqueeTimer < 0) {
      return;
    }
    clearInterval(this.entryNameMarqueeTimer);
    this.entryNameMarqueeTimer = -1;
  }

  private getMarqueeDisplayText(sourceText: string, windowSize: number): string {
    const normalizedText = sourceText.trim();
    if (normalizedText.length <= 0) {
      return '';
    }
    if (this.viewMode !== 'browser' || normalizedText.length <= windowSize) {
      return normalizedText;
    }
    const paddedText = `${normalizedText}${ENTRY_NAME_MARQUEE_GAP}`;
    const start = this.entryNameMarqueeTick % paddedText.length;
    const doubledText = `${paddedText}${paddedText}`;
    return doubledText.substring(start, start + windowSize);
  }

  private async initializePage(): Promise<void> {
    logger.info(TAG, '开始初始化网络文件夹页面');
    this.isInitializing = true;
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await this.manager.initialize(context);
      this.reloadConnections();
      this.restoreLastSelection();
      this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
      if (this.connections.length > 0) {
        this.statusMessage = `已载入 ${this.connections.length} 个网络连接，点击即可进入远程文件夹。`;
      } else {
        this.statusMessage = '还没有网络文件夹连接，先新建一个。';
      }
      logger.info(TAG, `网络文件夹页面初始化完成，连接数量 ${this.connections.length}`);
    } catch (error) {
      logger.error(TAG, `初始化网络文件夹页面失败：${String(error)}`);
      this.statusMessage = '网络文件夹页面初始化失败。';
      this.showToast(`初始化失败：${String(error)}`);
    } finally {
      this.isInitializing = false;
      this.playPageEnterAnimation();
      this.showEntryFloatingCapsule();
    }
  }

  private playPageEnterAnimation(): void {
    this.pageReady = false;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
        this.pageReady = true;
      });
    }, 40);
  }

  private restoreLastSelection(): void {
    const lastConnectionId = this.manager.getLastConnectionId();
    let selectedConnection: NetworkFolderConnection | null = null;
    if (lastConnectionId.length > 0) {
      selectedConnection = this.getConnectionById(lastConnectionId);
    }
    if (!selectedConnection && this.connections.length > 0) {
      selectedConnection = this.connections[0];
    }
    if (!selectedConnection) {
      this.selectedConnectionId = '';
      this.currentPath = '/';
      return;
    }
    this.selectedConnectionId = selectedConnection.id;
    this.currentPath = this.manager.getLastPath(selectedConnection.id);
    logger.info(TAG, `恢复上次选择的连接：${selectedConnection.name}，路径 ${this.currentPath}`);
  }

  private reloadConnections(): void {
    this.connections = this.manager.getConnections();
    logger.info(TAG, `连接列表已刷新，共 ${this.connections.length} 项`);
  }

  private refreshConnectionsOverview(): void {
    this.reloadConnections();
    this.restoreLastSelection();
    this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
    if (this.viewMode === 'cache') {
      this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
    }
  }

  private getConnectionById(connectionId: string): NetworkFolderConnection | null {
    if (connectionId.length === 0) {
      return null;
    }
    for (let index = 0; index < this.connections.length; index++) {
      const connection = this.connections[index];
      if (connection.id === connectionId) {
        return connection;
      }
    }
    return null;
  }

  private getSelectedConnection(): NetworkFolderConnection | null {
    return this.getConnectionById(this.selectedConnectionId);
  }

  private hasSelectedConnection(): boolean {
    return this.getSelectedConnection() !== null;
  }

  private getSelectedConnectionForRender(): NetworkFolderConnection {
    const connection = this.getSelectedConnection();
    if (connection) {
      return connection;
    }
    throw new Error('当前没有可渲染的网络连接');
  }

  private isConnectionSelected(connection: NetworkFolderConnection): boolean {
    return this.selectedConnectionId === connection.id;
  }

  private isDialogProtocolSelected(protocol: NetworkFolderProtocol): boolean {
    return this.dialogDraft.protocol === protocol;
  }

  private async playRouteExitAnimation(offsetX: number): Promise<void> {
    return new Promise<void>((resolve) => {
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseInOut,
        onFinish: () => {
          resolve();
        }
      }, () => {
        this.routeOpacity = 0;
        this.routeTranslateX = offsetX;
        this.routeScale = 0.985;
      });
    });
  }

  private playRouteEnterAnimation(offsetX: number): void {
    this.routeOpacity = 0;
    this.routeTranslateX = offsetX;
    this.routeScale = 0.985;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.routeOpacity = 1;
      this.routeTranslateX = 0;
      this.routeScale = 1;
    });
  }

  private async playDirectoryExitAnimation(offsetX: number): Promise<void> {
    return new Promise<void>((resolve) => {
      this.getUIContext().animateTo({
        duration: 160,
        curve: Curve.EaseInOut,
        onFinish: () => {
          resolve();
        }
      }, () => {
        this.directoryOpacity = 0;
        this.directoryTranslateX = offsetX;
        this.directoryScale = 0.992;
      });
    });
  }

  private playDirectoryEnterAnimation(offsetX: number): void {
    this.directoryOpacity = 0;
    this.directoryTranslateX = offsetX;
    this.directoryScale = 0.992;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.directoryOpacity = 1;
      this.directoryTranslateX = 0;
      this.directoryScale = 1;
    });
  }

  private prepareConnection(connection: NetworkFolderConnection): void {
    this.selectedConnectionId = connection.id;
    this.currentPath = this.manager.getLastPath(connection.id);
    this.entries = [];
    this.scrollPositionMap.clear();
    this.isCurrentPathFavorite = this.manager.isFavoriteFolder(connection.id, this.currentPath);
    this.refreshCacheStats(connection.id);
  }

  private async openConnectionBrowser(connection: NetworkFolderConnection, forceRefresh: boolean): Promise<void> {
    logger.info(TAG, `进入连接浏览页：${connection.name}`);
    this.prepareConnection(connection);
    if (this.viewMode === 'connections') {
      await this.playRouteExitAnimation(-42);
      this.viewMode = 'browser';
      this.playRouteEnterAnimation(42);
    }
    this.statusMessage = `已进入连接：${connection.name}`;
    void this.loadDirectory(forceRefresh);
  }

  private async returnToConnections(): Promise<void> {
    logger.info(TAG, '返回网络连接列表页');
    this.scrollPositionMap.clear();
    await this.playRouteExitAnimation(42);
    this.viewMode = 'connections';
    this.playRouteEnterAnimation(-42);
    this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
    this.statusMessage = '已返回网络连接列表。';
  }

  private async loadDirectory(forceRefresh: boolean): Promise<void> {
    if (this.selectedConnectionId.length === 0) {
      this.entries = [];
      this.refreshCacheStats();
      this.statusMessage = '请先选择一个网络连接。';
      return;
    }

    const connection = this.getSelectedConnection();
    if (!connection) {
      this.entries = [];
      this.statusMessage = '当前连接已失效，请重新选择。';
      return;
    }

    logger.info(TAG, `开始加载目录：${connection.name} ${this.currentPath}，强制刷新=${forceRefresh}`);
    this.isLoadingDirectory = true;
    try {
      const result = await this.manager.browseDirectory(this.selectedConnectionId, this.currentPath, forceRefresh);
      if (!result.success) {
        logger.warn(TAG, `目录加载失败：${connection.name} ${this.currentPath}，原因：${result.message}`);
        this.statusMessage = result.message;
        this.showToast(result.message);
        return;
      }

      this.entries = result.entries;
      this.restoreScrollPosition(this.currentPath);
      if (result.fromCache) {
        if (result.stale) {
          this.statusMessage = `远程目录暂时不可用，已显示缓存内容：${this.currentPath}`;
          this.showToast('已显示缓存目录');
        } else {
          this.statusMessage = `已从缓存打开目录：${this.currentPath}`;
        }
      } else {
        this.statusMessage = `目录加载完成：${this.currentPath}，共 ${result.entries.length} 项。`;
      }
      this.refreshCacheStats(this.selectedConnectionId);
      if (this.viewMode === 'cache') {
        this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
      }
      logger.info(TAG, `目录加载完成：${connection.name} ${this.currentPath}，项目数 ${result.entries.length}`);
    } catch (error) {
      logger.error(TAG, `加载目录失败：${String(error)}`);
      this.statusMessage = '目录加载失败。';
      this.showToast(`加载目录失败：${String(error)}`);
    } finally {
      this.isLoadingDirectory = false;
    }
  }

  private async browseToPath(targetPath: string, forward: boolean, forceRefresh: boolean): Promise<void> {
    if (this.selectedConnectionId.length === 0) {
      return;
    }
    const normalizedTargetPath = targetPath.length > 0 ? targetPath : '/';
    if (normalizedTargetPath === this.currentPath && !forceRefresh) {
      return;
    }
    this.saveScrollPosition(this.currentPath);
    logger.info(TAG, `切换目录：${this.currentPath} -> ${normalizedTargetPath}`);
    const exitOffset = forward ? -26 : 26;
    const enterOffset = forward ? 26 : -26;
    await this.playDirectoryExitAnimation(exitOffset);
    this.currentPath = normalizedTargetPath;
    this.isCurrentPathFavorite = this.manager.isFavoriteFolder(this.selectedConnectionId, normalizedTargetPath);
    this.entries = [];
    this.playDirectoryEnterAnimation(enterOffset);
    void this.loadDirectory(forceRefresh);
  }

  private async refreshCurrentDirectory(): Promise<void> {
    logger.info(TAG, `刷新当前目录：${this.currentPath}`);
    await this.playDirectoryExitAnimation(0);
    this.playDirectoryEnterAnimation(0);
    await this.loadDirectory(true);
  }

  private async handlePageRefresh(): Promise<void> {
    if (this.isPageRefreshing) {
      return;
    }
    this.isPageRefreshing = true;
    this.showRefreshingFloatingCapsule();
    try {
      if (this.viewMode === 'browser' && this.hasSelectedConnection()) {
        await this.refreshCurrentDirectory();
      } else if (this.viewMode === 'cache') {
        this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
        this.statusMessage = '缓存详情已刷新。';
      } else {
        this.refreshConnectionsOverview();
      }
    } finally {
      this.isPageRefreshing = false;
      this.finishRefreshingFloatingCapsule();
    }
  }

  private async openEntry(entry: NetworkFolderEntry): Promise<void> {
    if (!entry.isDirectory) {
      if (entry.importCategory !== 'unsupported') {
        await this.importEntry(entry);
      } else {
        await this.cacheEntry(entry);
      }
      return;
    }
    logger.info(TAG, `进入子目录：${entry.relativePath}`);
    await this.browseToPath(entry.relativePath, true, false);
  }

  private async goParentDirectory(): Promise<void> {
    if (this.currentPath === '/') {
      return;
    }
    const lastSlash = this.currentPath.lastIndexOf('/');
    const parentPath = lastSlash <= 0 ? '/' : this.currentPath.substring(0, lastSlash);
    logger.info(TAG, `返回上级目录：${this.currentPath} -> ${parentPath}`);
    await this.browseToPath(parentPath, false, false);
  }

  private async openBreadcrumb(item: NetworkFolderBreadcrumb): Promise<void> {
    if (item.path === this.currentPath) {
      return;
    }
    logger.info(TAG, `通过面包屑跳转目录：${item.path}`);
    const currentDepth = this.getPathDepth(this.currentPath);
    const targetDepth = this.getPathDepth(item.path);
    await this.browseToPath(item.path, targetDepth >= currentDepth, false);
  }

  private getPathDepth(path: string): number {
    if (path.length === 0 || path === '/') {
      return 0;
    }
    let depth = 0;
    const normalized = path.startsWith('/') ? path.substring(1) : path;
    const parts = normalized.split('/');
    for (let index = 0; index < parts.length; index++) {
      if (parts[index].length > 0) {
        depth++;
      }
    }
    return depth;
  }

  private async cacheEntry(entry: NetworkFolderEntry): Promise<void> {
    if (this.selectedConnectionId.length === 0 || entry.isDirectory) {
      return;
    }
    logger.info(TAG, `开始缓存远程文件：${entry.relativePath}`);

    const connectionId = this.selectedConnectionId;
    const manager = this.manager;
    const page = this;

    const taskId = BackgroundTaskManager.getInstance().createTask(
      TaskType.DOWNLOAD,
      `缓存：${entry.name}`,
      async (onProgress, _cancelSignal) => {
        onProgress(0, 1, `正在缓存 ${entry.name}...`);
        const result = await manager.downloadFileToCache(connectionId, entry);
        if (!result.success) {
          throw new Error(result.message);
        }
        onProgress(1, 1, `缓存完成：${entry.name}`);
        return result;
      },
      {
        enableBackgroundRunning: true,
        context: (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext,
        notification: {
          scene: TaskNotificationScene.NETWORK_CACHE,
          targetName: entry.name
        }
      }
    );

    this.activeCacheTaskId = taskId;
    this.isCaching = true;
    this.registerCacheTaskListener();

    try {
      await BackgroundTaskManager.getInstance().startTask(taskId);
      const task = BackgroundTaskManager.getInstance().getTask(taskId);
      const result = task?.result as NetworkFolderDownloadResult | undefined;
      if (result) {
        this.statusMessage = result.reusedCache ? `已复用缓存文件：${entry.name}` : `文件已缓存：${entry.name}`;
        this.showToast(result.reusedCache ? '已复用缓存文件' : '文件缓存完成');
        this.markEntryCached(entry.relativePath, result.localPath);
        this.refreshCacheStats(connectionId);
        if (page.viewMode === 'cache') {
          page.refreshCacheDetail(page.cacheDetailConnectionId.length > 0 ? page.cacheDetailConnectionId : undefined);
        }
        await this.loadDirectory(false);
      }
      logger.info(TAG, `远程文件缓存完成：${entry.relativePath}`);
    } catch (error) {
      logger.error(TAG, `缓存远程文件异常：${String(error)}`);
      this.showToast(`缓存失败：${String(error)}`);
    } finally {
      this.isCaching = false;
      this.activeCacheTaskId = '';
    }
  }

  private async importEntry(entry: NetworkFolderEntry): Promise<void> {
    if (this.selectedConnectionId.length === 0 || entry.isDirectory) {
      return;
    }
    logger.info(TAG, `开始导入远程文件：${entry.relativePath}`);

    const connectionId = this.selectedConnectionId;
    const manager = this.manager;

    const taskId = BackgroundTaskManager.getInstance().createTask(
      TaskType.DOWNLOAD,
      `导入：${entry.name}`,
      async (onProgress, _cancelSignal) => {
        onProgress(0, 1, `正在下载 ${entry.name}...`);
        const result = await manager.downloadFileToCache(connectionId, entry);
        if (!result.success) {
          throw new Error(result.message);
        }
        onProgress(1, 1, `下载完成：${entry.name}`);
        return result;
      },
      {
        enableBackgroundRunning: true,
        context: (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext,
        notification: {
          scene: TaskNotificationScene.NETWORK_CACHE,
          targetName: entry.name
        }
      }
    );

    this.activeCacheTaskId = taskId;
    this.isCaching = true;
    this.registerCacheTaskListener();

    try {
      await BackgroundTaskManager.getInstance().startTask(taskId);
      const task = BackgroundTaskManager.getInstance().getTask(taskId);
      const result = task?.result as NetworkFolderDownloadResult | undefined;
      if (result) {
        this.dispatchImportFromNetworkFolder(result.fileUri, entry.name, result.importCategory);
        this.markEntryCached(entry.relativePath, result.localPath);
      }
      logger.info(TAG, `远程文件导入任务已分发：${entry.relativePath}`);
    } catch (error) {
      logger.error(TAG, `导入远程文件异常：${String(error)}`);
      this.showToast(`导入失败：${String(error)}`);
    } finally {
      this.isCaching = false;
      this.activeCacheTaskId = '';
    }
  }

  private cloneEntryForState(entry: NetworkFolderEntry): NetworkFolderEntry {
    return {
      key: entry.key,
      name: entry.name,
      relativePath: entry.relativePath,
      actualPath: entry.actualPath,
      size: entry.size,
      isDirectory: entry.isDirectory,
      lastModified: entry.lastModified,
      etag: entry.etag,
      contentType: entry.contentType,
      permissions: entry.permissions,
      importCategory: entry.importCategory,
      cacheStatus: entry.cacheStatus,
      cachedLocalPath: entry.cachedLocalPath,
      versionTag: entry.versionTag
    };
  }

  private markEntryCached(relativePath: string, localPath: string): void {
    if (relativePath.length === 0 || localPath.length === 0) {
      return;
    }
    const nextEntries: NetworkFolderEntry[] = [];
    for (const item of this.entries) {
      const cloned = this.cloneEntryForState(item);
      if (!cloned.isDirectory && cloned.relativePath === relativePath) {
        cloned.cacheStatus = 'cached';
        cloned.cachedLocalPath = localPath;
      }
      nextEntries.push(cloned);
    }
    this.entries = nextEntries;
  }

  private markEntryCacheRemoved(relativePath: string): void {
    if (relativePath.length === 0) {
      return;
    }
    const nextEntries: NetworkFolderEntry[] = [];
    for (const item of this.entries) {
      const cloned = this.cloneEntryForState(item);
      if (!cloned.isDirectory && cloned.relativePath === relativePath) {
        cloned.cacheStatus = 'none';
        cloned.cachedLocalPath = '';
      }
      nextEntries.push(cloned);
    }
    this.entries = nextEntries;
  }

  private saveScrollPosition(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      const yOffset = this.browserScroller.currentOffset().yOffset;
      this.scrollPositionMap.set(path, yOffset);
    } catch (_error) {
      // Scroller may not be attached yet
    }
  }

  private restoreScrollPosition(path: string): void {
    const savedOffset = this.scrollPositionMap.get(path);
    if (savedOffset === undefined || savedOffset <= 0) {
      return;
    }
    setTimeout(() => {
      try {
        this.browserScroller.scrollTo({ xOffset: 0, yOffset: savedOffset });
      } catch (_error) {
        // Scroller may not be ready
      }
    }, 80);
  }

  private async toggleCurrentPathFavorite(): Promise<void> {
    if (this.selectedConnectionId.length === 0 || this.isTogglingFavorite) {
      return;
    }
    this.isTogglingFavorite = true;
    try {
      const newState = await this.manager.toggleFavoriteFolder(this.selectedConnectionId, this.currentPath);
      this.isCurrentPathFavorite = newState;
      this.showToast(newState ? '已收藏当前文件夹' : '已取消收藏');
    } finally {
      this.isTogglingFavorite = false;
    }
  }

  private openFavoritesDialog(): void {
    if (this.selectedConnectionId.length === 0) {
      return;
    }
    logger.info(TAG, '打开收藏夹对话框');
    this.favoriteFolders = this.manager.getFavoriteFolders(this.selectedConnectionId);
    this.showFavoritesDialog();
  }

  private showFavoritesDialog(): void {
    this.favDialogMounted = true;
    this.favDialogBackdropOpacity = 0;
    this.favDialogOpacity = 0;
    this.favDialogScale = 0.96;
    this.favDialogTranslateY = 24;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.favDialogBackdropOpacity = 1;
        this.favDialogOpacity = 1;
        this.favDialogScale = 1;
        this.favDialogTranslateY = 0;
      });
    }, 16);
  }

  private async hideFavoritesDialog(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.favDialogMounted = false;
          resolve();
        }
      }, () => {
        this.favDialogBackdropOpacity = 0;
        this.favDialogOpacity = 0;
        this.favDialogScale = 0.96;
        this.favDialogTranslateY = 24;
      });
    });
  }

  private closeFavoritesDialog(): void {
    logger.info(TAG, '关闭收藏夹对话框');
    void this.hideFavoritesDialog();
  }

  private async navigateToFavoriteFolder(path: string): Promise<void> {
    await this.hideFavoritesDialog();
    setTimeout(() => {
      void this.browseToPath(path, true, false);
    }, 50);
  }

  // ==================== Network Scan Methods ====================

  private async openScanPanel(): Promise<void> {
    if (!this.scannerAdapter.isAvailable()) {
      this.statusMessage = '网络扫描模块不可用，请检查原生库是否已加载。';
      return;
    }
    this.scanResults = [];
    this.scanProgress = { scannedHosts: 0, totalHosts: 254, currentIP: '' };
    this.scanPhase = 'idle';
    this.scanStartTime = 0;
    this.scanDurationMs = 0;
    this.smbEnumLoading = false;
    this.smbEnumHost = '';
    this.smbEnumShares = [];

    const subnet = this.scannerAdapter.getLocalSubnet();
    this.scanSubnet = subnet.length > 0 ? subnet : '192.168.1';
    this.showScanPanel();
    // Auto-start scan after panel animation
    setTimeout(() => {
      this.startNetworkScan();
    }, 300);
  }

  private showScanPanel(): void {
    this.scanMounted = true;
    this.scanBackdropOpacity = 0;
    this.scanOpacity = 0;
    this.scanScale = 0.96;
    this.scanTranslateY = 24;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.scanBackdropOpacity = 1;
        this.scanOpacity = 1;
        this.scanScale = 1;
        this.scanTranslateY = 0;
      });
    }, 16);
  }

  private async hideScanPanel(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.scanMounted = false;
          resolve();
        }
      }, () => {
        this.scanBackdropOpacity = 0;
        this.scanOpacity = 0;
        this.scanScale = 0.96;
        this.scanTranslateY = 24;
      });
    });
  }

  private closeScanPanel(): void {
    if (this.scannerAdapter.isScanning()) {
      this.scannerAdapter.stopScan();
    }
    void this.hideScanPanel();
  }

  private startNetworkScan(): void {
    if (this.scanSubnet.trim().length === 0) {
      return;
    }
    this.scanPhase = 'scanning';
    this.scanResults = [];
    this.scanProgress = { scannedHosts: 0, totalHosts: 254, currentIP: '' };
    this.scanStartTime = Date.now();
    this.scanDurationMs = 0;

    const started = this.scannerAdapter.startScan(
      this.scanSubnet.trim(),
      (scanned: number, total: number, currentIP: string) => {
        this.scanProgress = { scannedHosts: scanned, totalHosts: total, currentIP: currentIP };
        this.scanDurationMs = Date.now() - this.scanStartTime;
      },
      (host: NetworkScanHost) => {
        this.scanResults = [...this.scanResults, host];
      },
      (cancelled: boolean) => {
        this.scanDurationMs = Date.now() - this.scanStartTime;
        this.scanPhase = 'done';
      }
    );

    if (!started) {
      this.scanPhase = 'idle';
    }
  }

  private cancelNetworkScan(): void {
    this.scannerAdapter.stopScan();
  }

  private openConnectionFromScan(host: NetworkScanHost, protocolIndex: number): void {
    const protocol = mapScanProtocolToFolderProtocol(protocolIndex);
    const draft = draftFromScanResult(host, protocol);
    this.dialogDraft = draft;
    this.dialogMode = 'create';
    this.dialogStatusMessage = '请填写凭据信息，然后保存连接。';
    this.closeScanPanel();
    setTimeout(() => {
      this.showConnectionDialog();
    }, 200);
  }

  private async requestSMBShareEnum(host: NetworkScanHost): Promise<void> {
    this.smbEnumLoading = true;
    this.smbEnumHost = host.ip;
    this.smbEnumShares = [];
    try {
      const result: NetworkSMBEnumResult = await this.scannerAdapter.enumSMBShares(host.ip, 445);
      if (result.success) {
        this.smbEnumShares = result.shares.filter((s: NetworkSMBShare) => s.isDiskShare && !s.isHidden);
      } else {
        this.smbEnumShares = [];
      }
    } catch (error) {
      this.smbEnumShares = [];
    }
    this.smbEnumLoading = false;
  }

  private openSMBConnectionFromShare(host: NetworkScanHost, share: NetworkSMBShare): void {
    const draft = createEmptyNetworkFolderDraft();
    draft.protocol = 'smb';
    draft.host = host.ip;
    draft.port = 445;
    draft.shareName = share.name;
    draft.name = share.remark.length > 0
      ? `${host.ip} ${share.name} (${share.remark})`
      : `${host.ip} ${share.name}`;
    this.dialogDraft = draft;
    this.dialogMode = 'create';
    this.dialogStatusMessage = '请填写凭据信息，然后保存连接。';
    this.closeScanPanel();
    setTimeout(() => {
      this.showConnectionDialog();
    }, 200);
  }

  private getScanProtocolIcon(protocol: number): Resource {
    switch (protocol) {
      case 0:
      case 1:
      case 2:
        return $r('sys.symbol.arrow_2_circlepath');
      case 3:
      case 4:
        return $r('sys.symbol.externaldrive_fill');
      case 5:
        return $r('sys.symbol.folder_fill');
      default:
        return $r('sys.symbol.questionmark_circle');
    }
  }

  private registerCacheTaskListener(): void {
    if (this.taskStatusListener) {
      BackgroundTaskManager.getInstance().removeListener(this.taskStatusListener);
    }
    const page = this;
    this.taskStatusListener = (task: BackgroundTask): void => {
      if (task.id !== page.activeCacheTaskId) {
        return;
      }
      if (task.status === TaskStatus.COMPLETED || task.status === TaskStatus.FAILED || task.status === TaskStatus.CANCELLED) {
        if (page.viewMode === 'browser' && page.hasSelectedConnection()) {
          void page.loadDirectory(false);
        }
      }
    };
    BackgroundTaskManager.getInstance().addListener(this.taskStatusListener);
  }

  private async importCachedFile(detail: NetworkFolderDownloadCacheDetail): Promise<void> {
    if (!detail.fileExists) {
      this.showToast('缓存文件不存在，无法导入');
      return;
    }
    const localUri = fileUri.getUriFromPath(detail.localPath);
    this.dispatchImportFromNetworkFolder(localUri, detail.fileName, detail.importCategory);
  }

  private dispatchImportFromNetworkFolder(
    fileUri: string,
    fileName: string,
    importCategory: NetworkFolderImportCategory
  ): void {
    const taskParams = this.buildNetworkFolderExternalTaskParams(fileUri, fileName, importCategory);
    void openExternalFileTaskInIsolatedAbility(
      this.getUIContext(),
      taskParams,
      'NetworkFolderPage.importCachedFile'
    ).then((started: boolean): void => {
      if (started) {
        this.statusMessage = `已打开独立导入窗口：${fileName}`;
        this.showToast('已打开独立导入窗口');
        return;
      }
      this.dispatchImportFromNetworkFolderFallback(fileUri, fileName, importCategory);
    });
  }

  private dispatchImportFromNetworkFolderFallback(
    fileUri: string,
    fileName: string,
    importCategory: NetworkFolderImportCategory
  ): void {
    if (this.shouldRouteToDownloadSyncImport(importCategory)) {
      this.preparePendingImportForDownloadSync(fileUri, fileName, importCategory);
      this.navigateToDataManagementForImport();
      this.statusMessage = `已按 Download 同步逻辑导入：${fileName}`;
      this.showToast('已按 Download 同步导入流程处理');
      return;
    }

    this.preparePendingImportForMainMenu(fileUri, fileName, importCategory);
    this.navigateToMainMenuForImport();
    this.statusMessage = `已转交首页处理导入：${fileName}`;
    this.showToast('已按首页导入流程处理');
  }

  private shouldRouteToDownloadSyncImport(importCategory: NetworkFolderImportCategory): boolean {
    return importCategory === 'comic' || importCategory === 'ebook' || importCategory === 'pdf';
  }

  private clearPendingImportMarkers(): void {
    AppStorage.delete('pendingFileUri');
    AppStorage.delete('pendingFileType');
    AppStorage.delete('pendingFileCategory');
    AppStorage.delete('pendingFileSource');
    AppStorage.delete('pendingFileTarget');
    AppStorage.delete('pendingFileDisplayName');
    AppStorage.delete('fileImportPending');

    AppStorage.delete('pendingBackupUri');
    AppStorage.delete('backupImportPending');
    AppStorage.delete('pendingJsonUri');
    AppStorage.delete('pendingFontUri');
    AppStorage.delete('pendingCodeUri');
    AppStorage.delete('pendingCodeLanguage');
    AppStorage.delete('pendingAvifUri');
  }

  private preparePendingImportForDownloadSync(
    fileUri: string,
    fileName: string,
    importCategory: NetworkFolderImportCategory
  ): void {
    this.clearPendingImportMarkers();
    AppStorage.setOrCreate('pendingFileUri', fileUri);
    AppStorage.setOrCreate('pendingFileType', fileName);
    AppStorage.setOrCreate('pendingFileCategory', importCategory);
    AppStorage.setOrCreate('pendingFileSource', 'network_folder');
    AppStorage.setOrCreate('pendingFileTarget', 'download_dir');
    AppStorage.setOrCreate('pendingFileDisplayName', fileName);
    AppStorage.setOrCreate('fileImportPending', true);
  }

  private preparePendingImportForMainMenu(
    fileUri: string,
    fileName: string,
    importCategory: NetworkFolderImportCategory
  ): void {
    this.clearPendingImportMarkers();

    if (importCategory === 'backup') {
      AppStorage.setOrCreate('pendingBackupUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'backup');
      AppStorage.setOrCreate('backupImportPending', true);
      return;
    }

    if (importCategory === 'json') {
      AppStorage.setOrCreate('pendingJsonUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'json');
      return;
    }

    if (importCategory === 'font') {
      AppStorage.setOrCreate('pendingFontUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'font');
      return;
    }

    if (importCategory === 'code') {
      AppStorage.setOrCreate('pendingCodeUri', fileUri);
      AppStorage.setOrCreate('pendingCodeLanguage', this.inferCodeLanguageForMainMenu(fileName));
      AppStorage.setOrCreate('pendingFileCategory', 'code');
      return;
    }

    if (importCategory === 'avif') {
      AppStorage.setOrCreate('pendingAvifUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'avif');
      return;
    }

    AppStorage.setOrCreate('pendingFileUri', fileUri);
    AppStorage.setOrCreate('pendingFileType', fileName);
    AppStorage.setOrCreate('pendingFileCategory', importCategory);
  }

  private buildNetworkFolderExternalTaskParams(
    fileUri: string,
    fileName: string,
    importCategory: NetworkFolderImportCategory
  ): ExternalFileTaskParams {
    const kind = this.mapNetworkFolderCategoryToExternalTaskKind(importCategory);
    return ExternalFileTaskFactory.createSingleFileTask(
      kind,
      fileUri,
      fileName,
      ExternalFileTaskSource.NETWORK_FOLDER,
      fileName,
      kind === ExternalFileTaskKind.CODE ? this.inferCodeLanguageForMainMenu(fileName) : '',
      'download_dir'
    );
  }

  private mapNetworkFolderCategoryToExternalTaskKind(importCategory: NetworkFolderImportCategory): ExternalFileTaskKind {
    switch (importCategory) {
      case 'comic':
        return ExternalFileTaskKind.COMIC;
      case 'ebook':
        return ExternalFileTaskKind.EBOOK;
      case 'pdf':
        return ExternalFileTaskKind.PDF;
      case 'backup':
        return ExternalFileTaskKind.BACKUP;
      case 'json':
        return ExternalFileTaskKind.JSON;
      case 'font':
        return ExternalFileTaskKind.FONT;
      case 'code':
        return ExternalFileTaskKind.CODE;
      case 'avif':
        return ExternalFileTaskKind.AVIF;
      case 'image':
        return ExternalFileTaskKind.IMAGE;
      default:
        return ExternalFileTaskKind.UNKNOWN;
    }
  }

  private inferCodeLanguageForMainMenu(fileName: string): string {
    const extension = getNetworkFolderFileExtension(fileName);
    if (extension === 'ts' || extension === 'ets' || extension === 'tsx') {
      return 'typescript';
    }
    if (extension === 'js' || extension === 'jsx') {
      return 'javascript';
    }
    if (extension === 'py') {
      return 'python';
    }
    if (extension === 'java') {
      return 'java';
    }
    if (extension === 'cpp' || extension === 'c' || extension === 'h' || extension === 'hpp') {
      return 'cpp';
    }
    if (extension === 'cs') {
      return 'csharp';
    }
    if (extension === 'go') {
      return 'go';
    }
    if (extension === 'rs') {
      return 'rust';
    }
    if (extension === 'swift') {
      return 'swift';
    }
    if (extension === 'kt') {
      return 'kotlin';
    }
    if (extension === 'rb') {
      return 'ruby';
    }
    if (extension === 'php') {
      return 'php';
    }
    if (extension === 'html' || extension === 'htm') {
      return 'html';
    }
    if (extension === 'css' || extension === 'scss' || extension === 'less') {
      return 'css';
    }
    if (extension === 'sql') {
      return 'sql';
    }
    if (extension === 'sh' || extension === 'bash' || extension === 'zsh') {
      return 'shell';
    }
    if (extension === 'ps1' || extension === 'bat' || extension === 'cmd') {
      return 'powershell';
    }
    if (extension === 'json' || extension === 'json5' || extension === 'jsonc') {
      return 'json';
    }
    if (extension === 'xml') {
      return 'xml';
    }
    if (extension === 'yaml' || extension === 'yml') {
      return 'yaml';
    }
    if (extension === 'md' || extension === 'markdown') {
      return 'markdown';
    }
    if (extension === 'ini' || extension === 'conf' || extension === 'cfg' || extension === 'toml') {
      return 'ini';
    }
    if (extension === 'lua') {
      return 'lua';
    }
    if (extension === 'r') {
      return 'r';
    }
    if (extension === 'dart') {
      return 'dart';
    }
    if (extension === 'vue') {
      return 'vue';
    }
    if (extension === 'svelte') {
      return 'svelte';
    }
    return 'plaintext';
  }

  private navigateToDataManagementForImport(): void {
    const navParam: NetworkFolderImportNavParam = {
      fromPage: 'NetworkFolderPage',
      timestamp: Date.now()
    };
    this.pathStack.pushPathByName('DataManagementPage', navParam);
  }

  private navigateToMainMenuForImport(): void {
    try {
      if (this.pathStack.size() > 0) {
        this.pathStack.pop();
        logger.info(TAG, '网络文件夹导入后返回首页：已从导航栈回退到 MainMenuPage');
        return;
      }
    } catch (error) {
      logger.warn(TAG, `网络文件夹导入后回退首页失败，尝试兜底跳转：${String(error)}`);
    }

    try {
      this.pathStack.pushPathByName('MainMenuPage', undefined);
      logger.info(TAG, '网络文件夹导入后返回首页：使用兜底 pushPathByName(MainMenuPage)');
    } catch (error) {
      logger.error(TAG, `网络文件夹导入后兜底跳转首页失败：${String(error)}`);
      this.showToast('请手动返回首页继续导入');
    }
  }

  private resolveParentDirectory(filePath: string): string {
    const normalizedPath = filePath.trim().replace(/\\/g, '/');
    const lastSlash = normalizedPath.lastIndexOf('/');
    if (lastSlash <= 0) {
      return normalizedPath;
    }
    return normalizedPath.substring(0, lastSlash);
  }

  private async openCachedFileLocation(detail: NetworkFolderDownloadCacheDetail): Promise<void> {
    if (!detail.fileExists) {
      this.showToast('缓存文件不存在，无法打开位置');
      return;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }
      const parentPath = this.resolveParentDirectory(detail.localPath);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(parentPath)
      };
      await context.startAbility(want);
      this.statusMessage = `已打开文件所在位置：${detail.fileName}`;
      this.showToast('已打开文件所在位置');
    } catch (error) {
      logger.warn(TAG, `打开文件所在位置失败，尝试打开文件本身: ${String(error)}`);
      try {
        const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
        if (!context) {
          throw new Error('无法获取应用上下文');
        }
        const fallbackWant: Want = {
          action: 'ohos.want.action.viewData',
          uri: fileUri.getUriFromPath(detail.localPath)
        };
        await context.startAbility(fallbackWant);
        this.showToast('已打开缓存文件');
      } catch (fallbackError) {
        logger.error(TAG, `打开缓存文件失败：${String(fallbackError)}`);
        this.showToast(`打开失败：${String(fallbackError)}`);
      }
    }
  }

  private async deleteCachedFile(detail: NetworkFolderDownloadCacheDetail): Promise<void> {
    if (this.isCaching) {
      return;
    }
    logger.info(TAG, `开始删除缓存文件：${detail.fileName} (${detail.relativePath})`);
    this.isCaching = true;
    try {
      const removed = await this.manager.deleteCachedFile(detail.connectionId, detail.relativePath, detail.localPath);
      if (this.selectedConnectionId === detail.connectionId) {
        this.markEntryCacheRemoved(detail.relativePath);
      }
      this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
      this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
      this.statusMessage = removed ? `缓存文件已删除：${detail.fileName}` : `缓存记录不存在：${detail.fileName}`;
      this.showToast(removed ? '缓存文件已删除' : '缓存记录不存在，页面已刷新');
    } catch (error) {
      logger.error(TAG, `删除缓存文件失败：${String(error)}`);
      this.showToast(`删除失败：${String(error)}`);
    } finally {
      this.isCaching = false;
    }
  }

  private async clearCurrentCache(): Promise<void> {
    if (this.selectedConnectionId.length === 0) {
      this.showToast('当前没有可清理的连接缓存');
      return;
    }
    const connection = this.getSelectedConnection();
    logger.info(TAG, `清理当前连接缓存：${connection ? connection.name : this.selectedConnectionId}`);
    await this.manager.clearCacheForConnection(this.selectedConnectionId);
    this.refreshCacheStats(this.selectedConnectionId);
    if (this.viewMode === 'cache') {
      this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
    }
    this.statusMessage = '当前连接缓存已清理。';
    this.showToast('当前连接缓存已清理');
    await this.loadDirectory(false);
  }

  private async clearAllCaches(): Promise<void> {
    logger.info(TAG, '开始清理全部网络文件夹缓存');
    await this.manager.clearAllCaches();
    this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
    if (this.viewMode === 'cache') {
      this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
    }
    this.statusMessage = '全部网络文件夹缓存已清理。';
    this.showToast('全部缓存已清理');
    if (this.selectedConnectionId.length > 0) {
      await this.loadDirectory(false);
    }
  }

  private showDeleteConnectionDialog(connection: NetworkFolderConnection): void {
    this.getUIContext().showAlertDialog({
      title: '删除连接',
      message: `确定删除“${connection.name}”吗？该连接关联的目录缓存和文件缓存也会一起清理。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_COLOR,
        action: () => {
          void this.deleteConnection(connection);
        }
      }
    });
  }

  private showClearAllCacheDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '清理全部缓存',
      message: '这会删除所有网络目录缓存和下载缓存，是否继续？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清理',
        fontColor: DANGER_COLOR,
        action: () => {
          void this.clearAllCaches();
        }
      }
    });
  }

  private showDeleteCachedFileDialog(detail: NetworkFolderDownloadCacheDetail): void {
    this.getUIContext().showAlertDialog({
      title: '删除缓存文件',
      message: `确定删除缓存文件“${detail.fileName}”吗？该操作会移除本地缓存文件和缓存记录。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_COLOR,
        action: () => {
          void this.deleteCachedFile(detail);
        }
      }
    });
  }

  private async deleteConnection(connection: NetworkFolderConnection): Promise<void> {
    logger.info(TAG, `开始删除连接：${connection.name}`);
    try {
      await this.manager.deleteConnection(connection.id);
      this.reloadConnections();
      if (this.selectedConnectionId === connection.id) {
        this.selectedConnectionId = '';
        this.currentPath = '/';
        this.entries = [];
        this.restoreLastSelection();
        if (this.viewMode === 'browser') {
          await this.returnToConnections();
        }
      }
      this.refreshCacheStats(this.selectedConnectionId.length > 0 ? this.selectedConnectionId : undefined);
      if (this.viewMode === 'cache') {
        this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
      }
      this.statusMessage = `连接已删除：${connection.name}`;
      this.showToast('连接已删除');
      logger.info(TAG, `连接删除完成：${connection.name}`);
    } catch (error) {
      logger.error(TAG, `删除连接失败：${String(error)}`);
      this.showToast(`删除失败：${String(error)}`);
    }
  }

  private openCreateConnectionDialog(): void {
    logger.info(TAG, '打开新建连接对话框');
    this.dialogMode = 'create';
    this.dialogDraft = createEmptyNetworkFolderDraft();
    this.dialogStatusMessage = '新建后会直接进入远程文件浏览页。';
    this.showConnectionDialog();
  }

  private openEditConnectionDialog(connection?: NetworkFolderConnection): void {
    let targetConnection: NetworkFolderConnection | null = null;
    if (connection) {
      targetConnection = connection;
    } else {
      targetConnection = this.getSelectedConnection();
    }

    if (!targetConnection) {
      this.showToast('当前没有可编辑的连接');
      return;
    }

    logger.info(TAG, `打开编辑连接对话框：${targetConnection.name}`);
    this.dialogMode = 'edit';
    this.dialogDraft = draftFromNetworkFolderConnection(targetConnection);
    this.dialogStatusMessage = `正在编辑连接：${targetConnection.name}`;
    this.showConnectionDialog();
  }

  private showConnectionDialog(): void {
    this.dialogMounted = true;
    this.dialogStatusExpanded = false;
    this.dialogStatusDetailVisible = false;
    this.dialogStatusDetailHeight = 0;
    this.dialogStatusDetailOpacity = 0;
    this.dialogStatusDetailTranslateY = -6;
    this.dialogBackdropOpacity = 0;
    this.dialogOpacity = 0;
    this.dialogScale = 0.96;
    this.dialogTranslateY = 24;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.dialogBackdropOpacity = 1;
        this.dialogOpacity = 1;
        this.dialogScale = 1;
        this.dialogTranslateY = 0;
      });
    }, 16);
  }

  private async hideConnectionDialog(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.dialogMounted = false;
          resolve();
        }
      }, () => {
        this.dialogBackdropOpacity = 0;
        this.dialogOpacity = 0;
        this.dialogScale = 0.96;
        this.dialogTranslateY = 24;
      });
    });
  }

  private closeConnectionDialog(): void {
    logger.info(TAG, '关闭连接配置对话框');
    void this.hideConnectionDialog();
  }

  private getDialogStatusExpandedHeight(): number {
    const trimmed = this.dialogStatusMessage.trim();
    const estimatedLines = Math.max(2, Math.ceil(trimmed.length / 22));
    const targetHeight = 18 + estimatedLines * 18;
    return Math.max(62, Math.min(184, targetHeight));
  }

  private toggleDialogStatusExpand(): void {
    if (this.dialogStatusExpanded) {
      this.dialogStatusExpanded = false;
      this.getUIContext().animateTo({
        duration: 180,
        curve: Curve.EaseInOut,
        onFinish: () => {
          this.dialogStatusDetailVisible = false;
        }
      }, () => {
        this.dialogStatusDetailHeight = 0;
        this.dialogStatusDetailOpacity = 0;
        this.dialogStatusDetailTranslateY = -6;
      });
      return;
    }

    this.expandDialogStatusDetail();
  }

  private expandDialogStatusDetail(): void {
    this.dialogStatusExpanded = true;
    this.dialogStatusDetailVisible = true;
    this.dialogStatusDetailHeight = 0;
    this.dialogStatusDetailOpacity = 0;
    this.dialogStatusDetailTranslateY = -6;
    const targetHeight = this.getDialogStatusExpandedHeight();
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.dialogStatusDetailHeight = targetHeight;
      this.dialogStatusDetailOpacity = 1;
      this.dialogStatusDetailTranslateY = 0;
    });
  }

  private validateDraft(draft: NetworkFolderConnectionDraft): boolean {
    if (draft.protocol === 'webdav' && draft.serverUrl.trim().length === 0) {
      this.showToast('请输入 WebDAV 服务地址');
      return false;
    }
    if ((draft.protocol === 'ftp' || draft.protocol === 'ftps' || draft.protocol === 'sftp' || draft.protocol === 'smb') &&
      draft.host.trim().length === 0) {
      this.showToast('请输入服务器主机地址');
      return false;
    }
    if (draft.protocol === 'smb' &&
      draft.shareName.trim().length === 0 &&
      this.inferSMBShareNameFromHost(draft.host).length === 0) {
      this.showToast('请输入 SMB 共享名称');
      return false;
    }
    return true;
  }

  private normalizeSMBHostInput(hostValue: string): string {
    let normalized = hostValue.trim();
    normalized = normalized.replace(/^smb:\/\//i, '');
    normalized = normalized.replace(/^\\\\+/, '');
    normalized = normalized.replace(/^\/+/, '');
    normalized = normalized.replace(/\\/g, '/');
    const separatorIndex = normalized.indexOf('/');
    if (separatorIndex >= 0) {
      normalized = normalized.substring(0, separatorIndex);
    }
    return normalized.trim();
  }

  private inferSMBShareNameFromHost(hostValue: string): string {
    const normalizedHostSource = hostValue.trim()
      .replace(/^smb:\/\//i, '')
      .replace(/^\\\\+/, '')
      .replace(/^\/+/, '')
      .replace(/\\/g, '/');
    const parts = normalizedHostSource.split('/').filter((item: string) => item.length > 0);
    if (parts.length > 1) {
      return parts[1];
    }
    return '';
  }

  private cloneDraft(source: NetworkFolderConnectionDraft): NetworkFolderConnectionDraft {
    const draft: NetworkFolderConnectionDraft = {
      id: source.id,
      name: source.name,
      protocol: source.protocol,
      serverUrl: source.serverUrl,
      host: source.host,
      shareName: source.shareName,
      domain: source.domain,
      clientIP: source.clientIP,
      port: source.port,
      username: source.username,
      password: source.password,
      basePath: source.basePath,
      passive: source.passive,
      verifySSL: source.verifySSL,
      verifyHostKey: source.verifyHostKey,
      timeoutMs: source.timeoutMs
    };
    return draft;
  }

  private buildPreparedDraft(draft: NetworkFolderConnectionDraft): NetworkFolderConnectionDraft {
    const preparedDraft = this.cloneDraft(draft);
    if (preparedDraft.protocol === 'smb') {
      if (preparedDraft.shareName.trim().length === 0) {
        preparedDraft.shareName = this.inferSMBShareNameFromHost(preparedDraft.host);
      }
      preparedDraft.host = this.normalizeSMBHostInput(preparedDraft.host);
    }
    preparedDraft.name = draft.name.trim().length > 0 ? draft.name.trim() : this.suggestConnectionName(preparedDraft);
    return preparedDraft;
  }

  private suggestConnectionName(draft: NetworkFolderConnectionDraft): string {
    if (draft.protocol === 'webdav') {
      return draft.serverUrl.trim().length > 0 ? draft.serverUrl.trim() : 'WebDAV 连接';
    }
    if (draft.protocol === 'smb') {
      const host = draft.host.trim();
      const share = draft.shareName.trim();
      if (host.length > 0 && share.length > 0) {
        return `${host}/${share}`;
      }
      if (host.length > 0) {
        return host;
      }
      if (share.length > 0) {
        return share;
      }
      return 'SMB 连接';
    }
    if (draft.host.trim().length > 0) {
      return draft.host.trim();
    }
    return `${getNetworkFolderProtocolLabel(draft.protocol)} 连接`;
  }

  private async saveDialogConnection(): Promise<void> {
    if (!this.validateDraft(this.dialogDraft)) {
      return;
    }

    const preparedDraft = this.buildPreparedDraft(this.dialogDraft);
    const connectionName = preparedDraft.name;
    logger.info(TAG, `开始保存连接：${connectionName}`);
    this.dialogSaving = true;
    try {
      const connection = createNetworkFolderConnection(preparedDraft, preparedDraft.id);
      await this.manager.saveConnection(connection);
      this.reloadConnections();
      this.selectedConnectionId = connection.id;
      this.currentPath = this.manager.getLastPath(connection.id);
      this.refreshCacheStats(connection.id);
      if (this.viewMode === 'cache') {
        this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
      }
      this.statusMessage = `连接已保存：${connection.name}`;
      this.showToast('连接已保存');
      logger.info(TAG, `连接保存完成：${connection.name}`);
      await this.hideConnectionDialog();
      if (this.dialogMode === 'create' || this.viewMode === 'connections') {
        await this.openConnectionBrowser(connection, false);
      } else {
        this.prepareConnection(connection);
        void this.loadDirectory(true);
      }
    } catch (error) {
      logger.error(TAG, `保存连接失败：${String(error)}`);
      this.dialogStatusMessage = `保存失败：${String(error)}`;
      this.expandDialogStatusDetail();
      this.showToast(`保存失败：${String(error)}`);
    } finally {
      this.dialogSaving = false;
    }
  }

  private async testDialogConnection(): Promise<void> {
    if (!this.validateDraft(this.dialogDraft)) {
      return;
    }

    const preparedDraft = this.buildPreparedDraft(this.dialogDraft);
    const connectionName = preparedDraft.name;
    logger.info(TAG, `开始测试连接：${connectionName}`);
    this.dialogTesting = true;
    try {
      const connection = createNetworkFolderConnection(preparedDraft, preparedDraft.id);
      const result = await this.manager.testConnection(connection);
      this.dialogStatusMessage = result.message;
      this.statusMessage = result.success
        ? `连接测试成功：${connection.name}`
        : `连接测试失败：${result.message}`;
      if (!result.success) {
        this.expandDialogStatusDetail();
      }
      this.showToast(result.success ? '连接测试成功' : '连接测试失败');
      logger.info(TAG, `连接测试结束：${connectionName}，结果 ${result.success ? '成功' : '失败'}，消息：${result.message}`);
    } catch (error) {
      logger.error(TAG, `连接测试异常：${String(error)}`);
      this.dialogStatusMessage = `连接测试失败：${String(error)}`;
      this.expandDialogStatusDetail();
      this.showToast(`连接测试失败：${String(error)}`);
    } finally {
      this.dialogTesting = false;
    }
  }

  private switchDialogProtocol(protocol: NetworkFolderProtocol): void {
    logger.info(TAG, `切换连接协议：${getNetworkFolderProtocolLabel(protocol)}`);
    const nextDraft = this.cloneDraft(this.dialogDraft);
    nextDraft.protocol = protocol;
    if (protocol === 'webdav') {
      nextDraft.port = 443;
      nextDraft.verifySSL = true;
    } else if (protocol === 'ftp') {
      nextDraft.port = 21;
      nextDraft.passive = true;
    } else if (protocol === 'ftps') {
      nextDraft.port = 990;
      nextDraft.passive = true;
      nextDraft.verifySSL = true;
    } else if (protocol === 'sftp') {
      nextDraft.port = 22;
      nextDraft.passive = false;
      nextDraft.verifySSL = true;
      nextDraft.verifyHostKey = true;
    } else {
      nextDraft.port = 445;
    }
    this.dialogDraft = nextDraft;
    this.dialogStatusMessage = `当前协议：${getNetworkFolderProtocolLabel(protocol)}`;
  }

  private refreshCacheStats(connectionId?: string): void {
    try {
      this.cacheStats = this.manager.getCacheStats(connectionId);
    } catch (error) {
      this.cacheStats = { directoryCount: 0, fileCount: 0, totalBytes: 0 };
    }
  }

  private refreshCacheDetail(connectionId?: string): void {
    try {
      const detail: NetworkFolderCacheDetail = this.manager.getCacheDetail(connectionId);
      this.cacheDetailConnectionId = connectionId?.trim() ?? '';
      this.cacheDetailStats = detail.stats;
      this.cacheDirectoryDetails = detail.directories;
      this.cacheFileDetails = detail.files;
    } catch (error) {
      logger.warn(TAG, `刷新缓存详情失败：${String(error)}`);
      this.cacheDetailConnectionId = connectionId?.trim() ?? '';
      this.cacheDetailStats = { directoryCount: 0, fileCount: 0, totalBytes: 0 };
      this.cacheDirectoryDetails = [];
      this.cacheFileDetails = [];
    }
  }

  private async openCacheDetailView(connectionId?: string): Promise<void> {
    const targetConnectionId = connectionId?.trim() ?? '';
    logger.info(TAG, `打开缓存详情页：${targetConnectionId.length > 0 ? targetConnectionId : '全部连接'}`);
    this.refreshCacheDetail(targetConnectionId.length > 0 ? targetConnectionId : undefined);
    this.cacheReturnView = this.viewMode;
    if (this.viewMode !== 'cache') {
      await this.playRouteExitAnimation(-42);
      this.viewMode = 'cache';
      this.playRouteEnterAnimation(42);
    }
    this.statusMessage = targetConnectionId.length > 0 ? '已进入当前连接缓存详情页。' : '已进入全部缓存详情页。';
  }

  private async leaveCacheDetailView(): Promise<void> {
    logger.info(TAG, '返回网络文件夹主视图');
    await this.playRouteExitAnimation(42);
    this.viewMode = this.cacheReturnView === 'cache' ? 'connections' : this.cacheReturnView;
    this.playRouteEnterAnimation(-42);
    this.statusMessage = this.viewMode === 'browser' ? '已返回远程目录浏览页。' : '已返回网络连接列表。';
  }

  private getCacheDetailTitle(): string {
    if (this.cacheDetailConnectionId.length === 0) {
      return '全部缓存';
    }
    const connection = this.getConnectionById(this.cacheDetailConnectionId);
    return connection ? `${connection.name} 的缓存` : '连接缓存';
  }

  private getCacheDetailSubtitle(): string {
    if (this.cacheDetailConnectionId.length === 0) {
      return '查看所有网络连接的目录缓存与文件缓存。';
    }
    const connection = this.getConnectionById(this.cacheDetailConnectionId);
    if (!connection) {
      return '查看当前连接关联的目录缓存与文件缓存。';
    }
    return `${getNetworkFolderProtocolLabel(connection.protocol)} · ${this.getConnectionEndpoint(connection)}`;
  }

  private getConnectionCacheSummary(connectionId: string): string {
    try {
      const stats = this.manager.getCacheStats(connectionId);
      return `目录 ${stats.directoryCount} · 文件 ${stats.fileCount} · ${this.formatBytes(stats.totalBytes)}`;
    } catch (error) {
      return '缓存状态暂不可用';
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let size = bytes;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    const fixedDigits = size >= 10 || unitIndex === 0 ? 0 : 1;
    return `${size.toFixed(fixedDigits)} ${units[unitIndex]}`;
  }

  private padNumber(value: number): string {
    return `${value}`;
  }

  private formatDateTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '时间未知';
    }
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${this.padNumber(date.getMonth() + 1)}-${this.padNumber(date.getDate())} ` +
      `${this.padNumber(date.getHours())}:${this.padNumber(date.getMinutes())}`;
  }

  private formatRelativeTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '尚未使用';
    }
    const delta = Date.now() - timestamp;
    if (delta < 60 * 1000) {
      return '刚刚使用';
    }
    if (delta < 60 * 60 * 1000) {
      return `${Math.floor(delta / (60 * 1000))} 分钟前`;
    }
    if (delta < 24 * 60 * 60 * 1000) {
      return `${Math.floor(delta / (60 * 60 * 1000))} 小时前`;
    }
    if (delta < 7 * 24 * 60 * 60 * 1000) {
      return `${Math.floor(delta / (24 * 60 * 60 * 1000))} 天前`;
    }
    return this.formatDateTime(timestamp);
  }

  private getConnectionEndpoint(connection: NetworkFolderConnection): string {
    if (connection.protocol === 'webdav') {
      return connection.serverUrl;
    }
    if (connection.protocol === 'smb') {
      return `\\\\${connection.host}\\${connection.shareName}`;
    }
    return `${connection.host}:${connection.port}`;
  }

  private getConnectionDescription(connection: NetworkFolderConnection): string {
    if (connection.protocol === 'smb') {
      return `共享路径 ${connection.shareName} · 基准目录 ${connection.basePath}`;
    }
    if (connection.protocol === 'webdav') {
      return `服务器地址 ${connection.serverUrl}`;
    }
    return `远程主机 ${connection.host}:${connection.port} · 基准目录 ${connection.basePath}`;
  }

  private getProtocolSymbol(protocol: NetworkFolderProtocol): Resource {
    if (protocol === 'webdav') {
      return $r('sys.symbol.cloud');
    }
    if (protocol === 'sftp') {
      return $r('sys.symbol.lock_fill');
    }
    if (protocol === 'smb') {
      return $r('sys.symbol.externaldrive_fill');
    }
    return $r('sys.symbol.folder');
  }

  private isExtensionMatch(extension: string, candidates: string[]): boolean {
    if (extension.length <= 0) {
      return false;
    }
    for (let index = 0; index < candidates.length; index++) {
      if (extension === candidates[index]) {
        return true;
      }
    }
    return false;
  }

  private isComicArchiveExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['zip', 'cbz', 'rar', 'cbr', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'lzma']);
  }

  private isEBookExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['epub', 'mobi', 'azw', 'azw3', 'txt']);
  }

  private isBackupExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['mxbak', 'mxbackup']);
  }

  private isJsonExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['json', 'json5', 'jsonc']);
  }

  private isImageExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif', 'heic', 'heif', 'svg']);
  }

  private isVideoExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['mp4', 'm4v', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'ts']);
  }

  private isAudioExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['mp3', 'flac', 'aac', 'ogg', 'wav', 'm4a', 'opus']);
  }

  private isFontExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['ttf', 'otf', 'ttc', 'woff', 'woff2']);
  }

  private isDocumentExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['doc', 'docx', 'rtf', 'odt', 'pages']);
  }

  private isSpreadsheetExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['xls', 'xlsx', 'csv', 'ods', 'numbers']);
  }

  private isPresentationExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['ppt', 'pptx', 'odp', 'key']);
  }

  private isArchiveExtension(extension: string): boolean {
    return this.isExtensionMatch(extension, ['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'lzma', 'cab', 'iso']);
  }

  private isCodeExtension(extension: string): boolean {
    return this.isExtensionMatch(
      extension,
      [
        'ets', 'ts', 'tsx', 'js', 'jsx',
        'jsonc', 'xml', 'yaml', 'yml', 'md', 'markdown',
        'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'py', 'rs',
        'cs', 'go', 'swift', 'rb', 'php', 'html', 'htm',
        'css', 'scss', 'less', 'sql', 'sh', 'bash', 'zsh',
        'ps1', 'bat', 'cmd', 'ini', 'conf', 'cfg', 'toml',
        'lua', 'r', 'dart', 'vue', 'svelte'
      ]
    );
  }

  private getSymbolForFileName(fileName: string, isDirectory: boolean): Resource {
    if (isDirectory) {
      return $r('sys.symbol.folder_fill');
    }

    const extension = getNetworkFolderFileExtension(fileName);
    if (this.isBackupExtension(extension)) {
      return $r('sys.symbol.externaldrive_fill');
    }
    if (this.isComicArchiveExtension(extension)) {
      return $r('sys.symbol.picture');
    }
    if (extension === 'pdf') {
      return $r('sys.symbol.doc_plaintext');
    }
    if (this.isEBookExtension(extension)) {
      return $r('sys.symbol.text_book_closed');
    }
    if (this.isJsonExtension(extension)) {
      return $r('sys.symbol.doc_text');
    }
    if (this.isFontExtension(extension)) {
      return $r('sys.symbol.textformat');
    }
    if (this.isImageExtension(extension)) {
      return $r('sys.symbol.picture');
    }
    if (this.isVideoExtension(extension)) {
      return $r('sys.symbol.play_circle');
    }
    if (this.isAudioExtension(extension)) {
      return $r('sys.symbol.play_fill');
    }
    if (this.isSpreadsheetExtension(extension)) {
      return $r('sys.symbol.doc_text');
    }
    if (this.isPresentationExtension(extension)) {
      return $r('sys.symbol.doc_plaintext');
    }
    if (this.isDocumentExtension(extension)) {
      return $r('sys.symbol.doc_plaintext');
    }
    if (this.isCodeExtension(extension)) {
      return $r('sys.symbol.doc');
    }
    if (this.isArchiveExtension(extension)) {
      return $r('sys.symbol.archivebox');
    }
    return $r('sys.symbol.doc_plaintext_fill');
  }

  private getFileSymbol(entry: NetworkFolderEntry): Resource {
    return this.getSymbolForFileName(entry.name, entry.isDirectory);
  }

  private getCacheFileSymbol(fileName: string, fileExists: boolean): Resource {
    if (!fileExists) {
      return $r('sys.symbol.exclamationmark_triangle_fill');
    }
    return this.getSymbolForFileName(fileName, false);
  }

  private getImportLabelByCategory(category: string, fileName: string): string {
    if (category === 'comic') {
      return '漫画归档';
    }
    if (category === 'ebook') {
      return getNetworkFolderFileExtension(fileName) === 'txt' ? 'TXT 小说' : '电子书';
    }
    if (category === 'pdf') {
      return 'PDF';
    }
    if (category === 'backup') {
      return '备份文件';
    }
    if (category === 'json') {
      return 'JSON 配置';
    }
    if (category === 'font') {
      return '字体文件';
    }
    if (category === 'code') {
      return '代码文件';
    }
    if (category === 'avif') {
      return 'AVIF 图片';
    }
    if (category === 'image') {
      return '图片文件';
    }

    const extension = getNetworkFolderFileExtension(fileName);
    if (this.isDocumentExtension(extension)) {
      return '文档文件';
    }
    if (this.isSpreadsheetExtension(extension)) {
      return '表格文件';
    }
    if (this.isPresentationExtension(extension)) {
      return '演示文件';
    }
    if (this.isVideoExtension(extension)) {
      return '视频文件';
    }
    if (this.isAudioExtension(extension)) {
      return '音频文件';
    }
    if (this.isArchiveExtension(extension)) {
      return '归档文件';
    }
    if (extension.length > 0) {
      return `${extension.toUpperCase()} 文件`;
    }
    return '可缓存文件';
  }

  private getImportLabel(entry: NetworkFolderEntry): string {
    if (entry.isDirectory) {
      return '文件夹';
    }
    return this.getImportLabelByCategory(entry.importCategory, entry.name);
  }

  private getCacheStatusLabel(entry: NetworkFolderEntry): string {
    if (entry.cacheStatus === 'cached') {
      return '缓存可用';
    }
    if (entry.cacheStatus === 'stale') {
      return '缓存已过期';
    }
    return '尚未缓存';
  }

  private getCacheStatusColor(entry: NetworkFolderEntry): ResourceColor {
    if (entry.cacheStatus === 'cached') {
      return '#35A86B';
    }
    if (entry.cacheStatus === 'stale') {
      return '#D18B2A';
    }
    return this.color('text_muted');
  }

  private getConnectionMarkerColor(connection: NetworkFolderConnection): ResourceColor {
    return this.selectedConnectionId === connection.id ? ACCENT_COLOR : this.color('text_muted');
  }

  private getActionBackgroundColor(styleKind: number): ResourceColor {
    if (styleKind === ACTION_STYLE_PRIMARY) {
      return ACCENT_COLOR;
    }
    if (styleKind === ACTION_STYLE_INFO) {
      return INFO_COLOR;
    }
    if (styleKind === ACTION_STYLE_DANGER) {
      return DANGER_COLOR;
    }
    return this.color('comp_background_tertiary');
  }

  private getActionForegroundColor(styleKind: number): ResourceColor {
    if (styleKind === ACTION_STYLE_NEUTRAL) {
      return this.color('text_primary');
    }
    return this.color('text_white');
  }

  private getBusyLabel(): string {
    if (this.isInitializing) {
      return '正在初始化网络文件夹…';
    }
    if (this.dialogSaving) {
      return '正在保存连接配置…';
    }
    if (this.dialogTesting) {
      return '正在测试远程连接…';
    }
    if (this.isLoadingDirectory) {
      return '正在读取远程目录…';
    }
    if (this.isCaching) {
      return '正在处理远程文件…';
    }
    return '状态正常';
  }

  private hasBusyState(): boolean {
    return this.isInitializing || this.dialogSaving || this.dialogTesting || this.isLoadingDirectory || this.isCaching;
  }

  private showFloatingCapsuleTemporarily(message: string, duration: number = 2200): void {
    if (this.floatingCapsuleTimer !== -1) {
      clearTimeout(this.floatingCapsuleTimer);
      this.floatingCapsuleTimer = -1;
    }
    this.floatingCapsuleText = message;
    this.showFloatingCapsule = true;
    this.floatingCapsuleTimer = setTimeout(() => {
      this.showFloatingCapsule = false;
      this.floatingCapsuleTimer = -1;
    }, duration) as number;
  }

  private hideFloatingCapsuleImmediately(): void {
    if (this.floatingCapsuleTimer !== -1) {
      clearTimeout(this.floatingCapsuleTimer);
      this.floatingCapsuleTimer = -1;
    }
    this.showFloatingCapsule = false;
  }

  private showEntryFloatingCapsule(): void {
    const connection = this.getSelectedConnection();
    if (connection) {
      this.showFloatingCapsuleTemporarily(`当前连接 · ${connection.name}`, 2400);
      return;
    }
    if (this.connections.length > 0) {
      this.showFloatingCapsuleTemporarily(`网络文件夹 · ${this.connections.length} 个连接`, 2400);
      return;
    }
    this.showFloatingCapsuleTemporarily('网络文件夹 · 暂无连接', 2400);
  }

  private showRefreshingFloatingCapsule(): void {
    if (this.floatingCapsuleTimer !== -1) {
      clearTimeout(this.floatingCapsuleTimer);
      this.floatingCapsuleTimer = -1;
    }
    const connection = this.getSelectedConnection();
    if (this.viewMode === 'browser' && connection) {
      this.floatingCapsuleText = `正在刷新 · ${connection.name} · ${this.currentPath}`;
    } else {
      this.floatingCapsuleText = '正在刷新 · 网络文件夹';
    }
    this.showFloatingCapsule = true;
  }

  private finishRefreshingFloatingCapsule(): void {
    this.showFloatingCapsuleTemporarily(this.floatingCapsuleText, 900);
  }

  private shouldUseCompactConnectionBanner(): boolean {
    return this.viewMode === 'browser' && this.currentPath !== '/' && this.hasSelectedConnection();
  }

  private getBreadcrumbs(): NetworkFolderBreadcrumb[] {
    const breadcrumbs: NetworkFolderBreadcrumb[] = [];
    breadcrumbs.push({
      label: '根目录',
      path: '/'
    });
    if (this.currentPath === '/') {
      return breadcrumbs;
    }
    const rawPath = this.currentPath.startsWith('/') ? this.currentPath.substring(1) : this.currentPath;
    const parts = rawPath.split('/');
    let currentPath = '';
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (part.length === 0) {
        continue;
      }
      currentPath = `${currentPath}/${part}`;
      breadcrumbs.push({
        label: part,
        path: currentPath
      });
    }
    return breadcrumbs;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  @Builder private buildActionButton(label: string, icon: Resource, styleKind: number, enabled: boolean,
    onClick: () => void) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted')])
        Text(label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted'))
      }
    }
    .height(36)
    .borderRadius(12)
    .enabled(enabled)
    .backgroundColor(enabled ? this.getActionBackgroundColor(styleKind) : this.color('comp_background_secondary'))
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder private buildToolbarIconButton(icon: Resource, enabled: boolean, onClick: () => void) {
    Button() {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([enabled ? this.color('text_primary') : this.color('text_muted')])
    }
    .width(34)
    .height(34)
    .enabled(enabled)
    .borderRadius(17)
    .backgroundColor(enabled ? this.color('comp_background_tertiary') : this.color('comp_background_secondary'))
    .onClick(() => {
      onClick();
    })
  }

  @Builder private buildToolbarBookmarkButton() {
    Button() {
      if (this.isTogglingFavorite) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.color('text_primary'))
      } else {
        SymbolGlyph(this.isCurrentPathFavorite ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(15)
          .fontColor([this.color('text_primary')])
      }
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.color('comp_background_tertiary'))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.openFavoritesDialog();
          }),
        TapGesture()
          .onAction(() => {
            void this.toggleCurrentPathFavorite();
          })
      )
    )
  }

  @Builder private buildFloatingStatusCapsule() {
    Row({ space: 8 }) {
      if (this.isPageRefreshing || this.isInitializing) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(ACCENT_COLOR)
      } else {
        SymbolGlyph($r('sys.symbol.externaldrive_fill'))
          .fontSize(16)
          .fontColor([this.color('accent_primary')])
      }

      Text(this.floatingCapsuleText)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .maxLines(1)
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.color('panel_background'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 1.0
    })
    .borderRadius(22)
  }

  @Builder private buildStatusBanner() {
    Row({ space: 12 }) {
      Column() {
        if (this.hasBusyState()) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(ACCENT_COLOR)
        } else {
          SymbolGlyph($r('sys.symbol.externaldrive_fill'))
            .fontSize(22)
            .fontColor([this.color('accent_primary')])
        }
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(17)

      Column({ space: 4 }) {
        Text(this.getBusyLabel())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .width('100%')
        Text(this.statusMessage)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .width('100%')
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 10 })
    .animation({ duration: 260, curve: Curve.EaseOut })
  }

  @Builder private buildCompactConnectionBanner(connection: NetworkFolderConnection) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(this.getProtocolSymbol(connection.protocol))
          .fontSize(18)
          .fontColor([this.color('accent_primary')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(18)

      Column({ space: 2 }) {
        Text(connection.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .width('100%')
          .maxLines(1)
        Text(getNetworkFolderProtocolLabel(connection.protocol))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('当前连接')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(12)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 10 })
    .animation({ duration: 260, curve: Curve.EaseOut })
  }

  @Builder private buildOverviewStat(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.78)')
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder private buildCacheHeaderOverviewStat(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeState.isLightTheme() ? this.color('text_black') : this.color('text_primary'))
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeState.isLightTheme() ? this.color('text_black') : this.color('text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder private buildConnectionsHeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.externaldrive_fill'))
              .fontSize(30)
              .fontColor(['#FFFFFF'])
          }
          .width(56)
          .height(56)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(255, 255, 255, 0.16)')
          .borderRadius(18)

          Column({ space: 6 }) {
            Text('网络文件夹')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
            Text('像文件管理器一样浏览远程目录，支持缓存、断线回退与直接导入。')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor('rgba(255, 255, 255, 0.78)')
              .maxLines(2)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Row({ space: 18 }) {
          this.buildOverviewStat('已保存连接', `${this.connections.length}`)
          this.buildOverviewStat('目录缓存', `${this.cacheStats.directoryCount}`)
          this.buildOverviewStat('文件缓存', `${this.cacheStats.fileCount}`)
        }
        .width('100%')
      }
      .width('100%')

      SymbolGlyph($r('sys.symbol.folder_fill'))
        .fontSize(86)
        .fontColor(['rgba(255, 255, 255, 0.12)'])
        .margin({ top: 12, right: 4 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#174E45')
    .borderRadius(24)
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 12 })
    .animation({ duration: 280, curve: Curve.EaseOut })
  }

  @Builder private buildQuickActionsCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.buildActionButton('新建连接', $r('sys.symbol.plus'), ACTION_STYLE_PRIMARY, true, () => {
          this.openCreateConnectionDialog();
        })
        Blank()
        this.buildActionButton('网络扫描', $r('sys.symbol.wifi_router'), ACTION_STYLE_INFO, true, () => {
          void this.openScanPanel();
        })
      }
      .width('100%')
      Row({ space: 10 }) {
        this.buildActionButton('缓存详情', $r('sys.symbol.inbox_fill'), ACTION_STYLE_INFO, true, () => {
          void this.openCacheDetailView();
        })
        Blank()
        this.buildActionButton('清理全部缓存', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
          this.showClearAllCacheDialog();
        })
      }
      .width('100%')

      Text(`当前缓存：目录 ${this.cacheStats.directoryCount} 项，文件 ${this.cacheStats.fileCount} 项，总大小 ${this.formatBytes(this.cacheStats.totalBytes)}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
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
    .borderRadius(20)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 20,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildConnectionsEmptyState() {
    Column({ space: 16 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.externaldrive_fill'))
          .fontSize(44)
          .fontColor([this.color('accent_primary')])
      }
      .width(88)
      .height(88)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(28)

      Text('还没有网络文件夹连接')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
      Text('先添加一个连接，然后就可以像文件管理器一样浏览远程目录。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
      this.buildActionButton('立即新建连接', $r('sys.symbol.plus'), ACTION_STYLE_PRIMARY, true, () => {
        this.openCreateConnectionDialog();
      })
    }
    .width('100%')
    .padding({ top: 56, bottom: 56, left: 24, right: 24 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 24,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder private buildConnectionCard(connection: NetworkFolderConnection) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(this.getProtocolSymbol(connection.protocol))
            .fontSize(22)
            .fontColor([this.isConnectionSelected(connection) ? '#FFFFFF' : this.color('accent_primary')])
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.isConnectionSelected(connection) ? ACCENT_COLOR : this.color('comp_background_tertiary'))
        .borderRadius(16)

        Column({ space: 4 }) {
          Text(connection.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .maxLines(1)
          Text(`${getNetworkFolderProtocolLabel(connection.protocol)} · ${this.getConnectionEndpoint(connection)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .maxLines(1)
          Text(this.getConnectionDescription(connection))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph(this.isConnectionSelected(connection) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(18)
          .fontColor([this.getConnectionMarkerColor(connection)])
      }
      .width('100%')

      Row({ space: 12 }) {
        Text(`缓存 ${this.getConnectionCacheSummary(connection.id)}`)
          .layoutWeight(1)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .maxLines(1)
        Text(this.formatRelativeTime(connection.lastUsedAt))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildActionButton('浏览', $r('sys.symbol.chevron_right'), ACTION_STYLE_PRIMARY, true, () => {
          void this.openConnectionBrowser(connection, false);
        })
        this.buildActionButton('编辑', $r('sys.symbol.gearshape'), ACTION_STYLE_NEUTRAL, true, () => {
          this.openEditConnectionDialog(connection);
        })
        this.buildActionButton('测试', $r('sys.symbol.checkmark_circle'), ACTION_STYLE_INFO, true, () => {
          this.dialogMode = 'edit';
          this.dialogDraft = draftFromNetworkFolderConnection(connection);
          this.dialogStatusMessage = `正在测试连接：${connection.name}`;
          this.showConnectionDialog();
          void this.testDialogConnection();
        })
        this.buildActionButton('删除', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
          this.showDeleteConnectionDialog(connection);
        })
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
    .borderRadius(22)
    .clip(true)
    .border({
      width: this.isConnectionSelected(connection) ? 1.5 : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: this.isConnectionSelected(connection) ? ACCENT_COLOR : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 12 })
    .animation({ duration: 260, curve: Curve.EaseOut })
  }

  @Builder private buildConnectionsView() {
    Scroll(this.connectionScroller) {
      Column({ space: 16 }) {
        this.buildConnectionsHeroCard()
        this.buildQuickActionsCard()

        Row() {
          Text('已保存连接')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Blank()
          Text(`${this.connections.length} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
        }
        .width('100%')

        if (this.connections.length === 0) {
          this.buildConnectionsEmptyState()
        } else {
          ForEach(this.connections, (connection: NetworkFolderConnection) => {
            this.buildConnectionCard(connection)
          }, (connection: NetworkFolderConnection) => connection.id)
        }

        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 + this.navigationBarHeight })
    }
    .width('100%')
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Auto)
  }

  @Builder private buildConnectionsRefreshView() {
    Refresh({ refreshing: $$this.isPageRefreshing }) {
      Scroll(this.connectionScroller) {
        Column({ space: 16 }) {
          this.buildConnectionsHeroCard()
          this.buildQuickActionsCard()

          Row() {
            Text('已保存连接')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
            Blank()
            Text(`${this.connections.length} 项`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
          }
          .width('100%')

          if (this.connections.length === 0) {
            this.buildConnectionsEmptyState()
          } else {
            ForEach(this.connections, (connection: NetworkFolderConnection) => {
              this.buildConnectionCard(connection)
            }, (connection: NetworkFolderConnection) => connection.id)
          }

          Blank().height(24)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 + this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .onRefreshing(async () => {
      await this.handlePageRefresh();
    })
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  private getCacheDetailConnectionName(connectionId: string): string {
    const connection = this.getConnectionById(connectionId);
    return connection ? connection.name : connectionId;
  }

  @Builder private buildCacheEmptyState(title: string, message: string) {
    Column({ space: 14 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.inbox_fill'))
          .fontSize(42)
          .fontColor([this.color('text_muted')])
      }
      .width(84)
      .height(84)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(24)

      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
      Text(message)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width('100%')
    .padding({ top: 32, bottom: 32, left: 20, right: 20 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 24,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder private buildDirectoryCacheCard(detail: NetworkFolderDirectoryCacheDetail) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(20)
            .fontColor([this.color('accent_primary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(14)

        Column({ space: 4 }) {
          Text(detail.relativePath)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .maxLines(1)
          Text(`${this.getCacheDetailConnectionName(detail.connectionId)} · ${detail.entryCount} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .maxLines(1)
          Text(`最近刷新：${this.formatDateTime(detail.fetchedAt)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildFileCacheCard(detail: NetworkFolderDownloadCacheDetail) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph(this.getCacheFileSymbol(detail.fileName, detail.fileExists))
            .fontSize(20)
            .fontColor([detail.fileExists ? this.color('icon_primary') : DANGER_COLOR])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(14)

        Column({ space: 4 }) {
          Text(detail.fileName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .maxLines(1)
          Text(`${this.getCacheDetailConnectionName(detail.connectionId)} · ${this.formatBytes(detail.size)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .maxLines(1)
          Text(`${this.getImportLabelByCategory(detail.importCategory, detail.fileName)} · ${detail.fileExists ? '可导入' : '文件缺失'}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(detail.fileExists ? this.color('text_secondary') : DANGER_COLOR)
            .width('100%')
            .maxLines(1)
          Text(`远程路径：${detail.relativePath}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
            .maxLines(1)
          Text(`本地路径：${detail.localPath}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
            .maxLines(1)
          Text(`缓存于 ${this.formatDateTime(detail.cachedAt)} · 最近访问 ${this.formatDateTime(detail.lastAccessedAt)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildActionButton('打开', $r('sys.symbol.folder'), ACTION_STYLE_NEUTRAL, detail.fileExists, () => {
          void this.openCachedFileLocation(detail);
        })
        this.buildActionButton('导入', $r('sys.symbol.square_and_arrow_down'), ACTION_STYLE_INFO,
          detail.fileExists && detail.importCategory !== 'unsupported', () => {
          void this.importCachedFile(detail);
        })
        this.buildActionButton('删除', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
          this.showDeleteCachedFileDialog(detail);
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildCacheDetailView() {
    Scroll(this.browserScroller) {
      Column({ space: 14 }) {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            this.buildActionButton('返回', $r('sys.symbol.arrow_left'), ACTION_STYLE_NEUTRAL, true, () => {
              void this.leaveCacheDetailView();
            })
            this.buildActionButton('刷新', $r('sys.symbol.arrow_clockwise'), ACTION_STYLE_INFO, true, () => {
              this.refreshCacheDetail(this.cacheDetailConnectionId.length > 0 ? this.cacheDetailConnectionId : undefined);
              this.showToast('缓存详情已刷新');
            })
            Blank()
            if (this.cacheDetailConnectionId.length > 0) {
              this.buildActionButton('清理当前', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
                void this.clearCurrentCache();
              })
            } else {
              this.buildActionButton('清理全部', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
                this.showClearAllCacheDialog();
              })
            }
          }
          .width('100%')

          Column({ space: 6 }) {
            Text(this.getCacheDetailTitle())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeState.isLightTheme() ? this.color('text_black') : this.color('text_primary'))
              .width('100%')
            Text(this.getCacheDetailSubtitle())
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeState.isLightTheme() ? this.color('text_black') : this.color('text_secondary'))
              .width('100%')
          }
          .width('100%')

          Row({ space: 12 }) {
            this.buildCacheHeaderOverviewStat('目录缓存', `${this.cacheDetailStats.directoryCount}`)
            this.buildCacheHeaderOverviewStat('文件缓存', `${this.cacheDetailStats.fileCount}`)
            this.buildCacheHeaderOverviewStat('占用空间', this.formatBytes(this.cacheDetailStats.totalBytes))
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
        .borderRadius(22)
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: 22,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        })

        Column({ space: 10 }) {
          Row() {
            Text('目录缓存明细')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
            Blank()
            Text(`${this.cacheDirectoryDetails.length} 项`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
          }
          .width('100%')

          if (this.cacheDirectoryDetails.length === 0) {
            this.buildCacheEmptyState('暂无目录缓存', '远程目录尚未被缓存，进入目录后会在这里显示明细。')
          } else {
            Column({ space: 10 }) {
              ForEach(this.cacheDirectoryDetails, (detail: NetworkFolderDirectoryCacheDetail) => {
                this.buildDirectoryCacheCard(detail)
              }, (detail: NetworkFolderDirectoryCacheDetail) => `${detail.connectionId}_${detail.relativePath}_${detail.fetchedAt}`)
            }
            .width('100%')
          }
        }
        .width('100%')

        Column({ space: 10 }) {
          Row() {
            Text('文件缓存明细')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
            Blank()
            Text(`${this.cacheFileDetails.length} 项`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
          }
          .width('100%')

          if (this.cacheFileDetails.length === 0) {
            this.buildCacheEmptyState('暂无文件缓存', '当你缓存或导入远程文件后，这里会显示对应的本地缓存文件。')
          } else {
            Column({ space: 10 }) {
              ForEach(this.cacheFileDetails, (detail: NetworkFolderDownloadCacheDetail) => {
                this.buildFileCacheCard(detail)
              }, (detail: NetworkFolderDownloadCacheDetail) => `${detail.connectionId}_${detail.relativePath}_${detail.cachedAt}`)
            }
            .width('100%')
          }
        }
        .width('100%')

        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 + this.navigationBarHeight })
    }
    .width('100%')
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Auto)
  }

  @Builder private buildBrowserRefreshView(connection: NetworkFolderConnection) {
    Refresh({ refreshing: $$this.isPageRefreshing }) {
      Scroll(this.browserScroller) {
        Column({ space: 12 }) {
          this.buildMergedBrowserToolbar(connection)
          this.buildEntriesSection(connection)
          Blank().height(24)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 + this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .onRefreshing(async () => {
      await this.handlePageRefresh();
    })
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  @Builder private buildBrowserHeader(connection: NetworkFolderConnection) {
    Column({ space: this.shouldUseCompactConnectionBanner() ? 12 : 14 }) {
      Row({ space: 10 }) {
        this.buildActionButton('连接列表', $r('sys.symbol.arrow_left'), ACTION_STYLE_NEUTRAL, true, () => {
          void this.returnToConnections();
        })
        Blank()
        this.buildActionButton('编辑', $r('sys.symbol.gearshape'), ACTION_STYLE_NEUTRAL, true, () => {
          this.openEditConnectionDialog(connection);
        })
      }
      .width('100%')

      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(this.getProtocolSymbol(connection.protocol))
            .fontSize(24)
            .fontColor([this.color('accent_primary')])
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)

        Column({ space: 4 }) {
          Text(connection.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .maxLines(1)
          Text(`${getNetworkFolderProtocolLabel(connection.protocol)} · ${this.getConnectionEndpoint(connection)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .maxLines(1)
          Text(`缓存 ${this.getConnectionCacheSummary(connection.id)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildActionButton('刷新', $r('sys.symbol.arrow_clockwise'), ACTION_STYLE_INFO, true, () => {
          void this.refreshCurrentDirectory();
        })
        this.buildActionButton('缓存详情', $r('sys.symbol.inbox_fill'), ACTION_STYLE_NEUTRAL, true, () => {
          void this.openCacheDetailView(connection.id);
        })
        this.buildActionButton('清理缓存', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
          void this.clearCurrentCache();
        })
        this.buildActionButton('上一级', $r('sys.symbol.arrow_left'), ACTION_STYLE_NEUTRAL, this.currentPath !== '/', () => {
          void this.goParentDirectory();
        })
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
    .borderRadius(22)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildCompactBrowserToolbar(connection: NetworkFolderConnection) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.buildActionButton('连接列表', $r('sys.symbol.arrow_left'), ACTION_STYLE_NEUTRAL, true, () => {
          void this.returnToConnections();
        })
        Blank()
        this.buildActionButton('编辑', $r('sys.symbol.gearshape'), ACTION_STYLE_NEUTRAL, true, () => {
          this.openEditConnectionDialog(connection);
        })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildActionButton('刷新', $r('sys.symbol.arrow_clockwise'), ACTION_STYLE_INFO, true, () => {
          void this.refreshCurrentDirectory();
        })
        this.buildActionButton('缓存详情', $r('sys.symbol.inbox_fill'), ACTION_STYLE_NEUTRAL, true, () => {
          void this.openCacheDetailView(connection.id);
        })
        this.buildActionButton('清理缓存', $r('sys.symbol.trash'), ACTION_STYLE_DANGER, true, () => {
          void this.clearCurrentCache();
        })
        this.buildActionButton('上一级', $r('sys.symbol.arrow_left'), ACTION_STYLE_NEUTRAL, this.currentPath !== '/', () => {
          void this.goParentDirectory();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(22)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildMergedBrowserToolbar(connection: NetworkFolderConnection) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.buildToolbarIconButton($r('sys.symbol.house'), true, () => {
          void this.returnToConnections();
        })

        Row({ space: 8 }) {
          SymbolGlyph(this.getProtocolSymbol(connection.protocol))
            .fontSize(16)
            .fontColor([this.color('accent_primary')])
          Column({ space: 2 }) {
            Text(connection.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
              .width('100%')
              .maxLines(1)
            Text(this.currentPath)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
              .width('100%')
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .padding({ left: 2, right: 2 })

        this.buildToolbarBookmarkButton()
        this.buildToolbarIconButton($r('sys.symbol.inbox_fill'), true, () => {
          void this.openCacheDetailView(connection.id);
        })
        this.buildToolbarIconButton($r('sys.symbol.gearshape'), true, () => {
          this.openEditConnectionDialog(connection);
        })
        this.buildToolbarIconButton($r('sys.symbol.arrow_up_circle'), this.currentPath !== '/', () => {
          void this.goParentDirectory();
        })
      }
      .width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.getBreadcrumbs(), (item: NetworkFolderBreadcrumb, index: number) => {
            Row({ space: 6 }) {
              Button(item.label)
                .height(28)
                .borderRadius(14)
                .backgroundColor(item.path === this.currentPath ? ACCENT_COLOR : this.color('comp_background_tertiary'))
                .fontColor(item.path === this.currentPath ? this.color('text_white') : this.color('text_primary'))
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  void this.openBreadcrumb(item);
                })
              if (index < this.getBreadcrumbs().length - 1) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(10)
                  .fontColor([this.color('text_muted')])
              }
            }
          }, (item: NetworkFolderBreadcrumb) => item.path)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildBreadcrumbBar() {
    Column({ space: 10 }) {
      Row() {
        Text('当前位置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
        Blank()
        Text(this.currentPath)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .maxLines(1)
      }
      .width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.getBreadcrumbs(), (item: NetworkFolderBreadcrumb, index: number) => {
            Row({ space: 6 }) {
              Button(item.label)
                .height(32)
                .borderRadius(16)
                .backgroundColor(item.path === this.currentPath ? ACCENT_COLOR : this.color('comp_background_tertiary'))
                .fontColor(item.path === this.currentPath ? this.color('text_white') : this.color('text_primary'))
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  void this.openBreadcrumb(item);
                })
              if (index < this.getBreadcrumbs().length - 1) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(12)
                  .fontColor([this.color('text_muted')])
              }
            }
          }, (item: NetworkFolderBreadcrumb) => item.path)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
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
    .borderRadius(20)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 20,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder private buildDirectoryEmptyState(connection: NetworkFolderConnection) {
    Column({ space: 14 }) {
      Column() {
        if (this.isLoadingDirectory) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(ACCENT_COLOR)
        } else {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(42)
            .fontColor([this.color('text_muted')])
        }
      }
      .width(84)
      .height(84)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(24)

      Text(this.isLoadingDirectory ? '正在读取目录…' : '当前目录为空')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
      Text(this.isLoadingDirectory
        ? `正在从 ${connection.name} 获取 ${this.currentPath} 的内容。`
        : '这个目录里暂时没有可显示的文件或文件夹。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width('100%')
    .padding({ top: 56, bottom: 56, left: 20, right: 20 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 24,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder private buildEntryCard(entry: NetworkFolderEntry) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(this.getFileSymbol(entry))
            .fontSize(22)
            .fontColor([entry.isDirectory ? this.color('accent_primary') : this.color('icon_primary')])
        }
        .width(50)
        .height(50)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(16)

        Column({ space: 4 }) {
          Text(this.getMarqueeDisplayText(entry.name, 28))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .maxLines(1)
          Text(entry.isDirectory
            ? this.getMarqueeDisplayText(`文件夹 · ${entry.relativePath}`, 40)
            : `${this.formatBytes(entry.size)} · ${this.formatDateTime(entry.lastModified)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .maxLines(1)
          Text(`${this.getImportLabel(entry)} · ${this.getCacheStatusLabel(entry)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getCacheStatusColor(entry))
            .width('100%')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          SymbolGlyph(entry.cacheStatus === 'cached' ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(16)
            .fontColor([this.getCacheStatusColor(entry)])
          if (entry.isDirectory) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([this.color('text_muted')])
          }
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        if (entry.isDirectory) {
          this.buildActionButton('打开', $r('sys.symbol.chevron_right'), ACTION_STYLE_PRIMARY, true, () => {
            void this.openEntry(entry);
          })
        } else {
          this.buildActionButton(
            entry.cacheStatus === 'cached' ? '已缓存' : '缓存',
            entry.cacheStatus === 'cached' ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.arrow_down_circle'),
            ACTION_STYLE_NEUTRAL,
            entry.cacheStatus !== 'cached',
            () => {
              void this.cacheEntry(entry);
            }
          )
          this.buildActionButton('导入', $r('sys.symbol.square_and_arrow_down'), ACTION_STYLE_INFO,
            entry.importCategory !== 'unsupported', () => {
              void this.importEntry(entry);
            })
        }
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
    .borderRadius(20)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 20,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .stateStyles({
      pressed: {
        .scale({ x: 0.985, y: 0.985 })
        .opacity(0.92)
      }
    })
    .onClick(() => {
      void this.openEntry(entry);
    })
  }

  @Builder private buildEntriesSection(connection: NetworkFolderConnection) {
    Column({ space: 12 }) {
      Row() {
        Text('目录内容')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
        Blank()
        if (this.isLoadingDirectory) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(ACCENT_COLOR)
        } else {
          Text(`${this.entries.length} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
        }
      }
      .width('100%')

      if (this.entries.length === 0) {
        this.buildDirectoryEmptyState(connection)
      } else {
        Column({ space: 12 }) {
          ForEach(this.entries, (entry: NetworkFolderEntry) => {
            this.buildEntryCard(entry)
          }, (entry: NetworkFolderEntry) => entry.key)
        }
        .width('100%')
        .opacity(this.directoryOpacity)
        .translate({ x: this.directoryTranslateX, y: 0 })
        .scale({ x: this.directoryScale, y: this.directoryScale })
      }
    }
    .width('100%')
  }

  @Builder private buildBrowserView(connection: NetworkFolderConnection) {
    Column({ space: 16 }) {
      if (this.shouldUseCompactConnectionBanner()) {
        this.buildCompactBrowserToolbar(connection)
      } else {
        this.buildBrowserHeader(connection)
      }
      this.buildBreadcrumbBar()

      Scroll(this.browserScroller) {
        Column({ space: 12 }) {
          this.buildEntriesSection(connection)
          Blank().height(24)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 + this.navigationBarHeight })
  }
  @Builder private buildDialogField(icon: Resource, label: string, placeholder: string, value: string,
    onChange: (value: string) => void, type: InputType = InputType.Normal) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([this.color('text_secondary')])
        Text(label)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
      }
      .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .type(type)
        .height(44)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .placeholderColor(this.color('text_muted'))
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }
  @Builder private buildDialogToggle(icon: Resource, label: string, description: string, isOn: boolean,
    onChange: (value: boolean) => void) {
    Row({ space: 10 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([this.color('accent_primary')])
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(10)

      Column({ space: 2 }) {
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .width('100%')
        Text(description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .width('100%')
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('comp_background_secondary'))
    .borderRadius(16)
  }
  @Builder private buildDialogProtocolOption(protocol: NetworkFolderProtocol) {
    Button() {
      Column({ space: 6 }) {
        SymbolGlyph(this.getProtocolSymbol(protocol))
          .fontSize(18)
          .fontColor([this.isDialogProtocolSelected(protocol) ? this.color('text_white') : this.color('accent_primary')])
        Text(getNetworkFolderProtocolLabel(protocol))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isDialogProtocolSelected(protocol) ? this.color('text_white') : this.color('text_primary'))
      }
      .width('100%')
    }
    .height(72)
    .layoutWeight(1)
    .borderRadius(18)
    .backgroundColor(this.isDialogProtocolSelected(protocol) ? ACCENT_COLOR : this.color('comp_background_tertiary'))
    .onClick(() => {
      this.switchDialogProtocol(protocol);
    })
  }
  @Builder private buildDialogStatusCard() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column() {
          if (this.dialogTesting || this.dialogSaving) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ACCENT_COLOR)
          } else {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(16)
              .fontColor([this.color('accent_primary')])
          }
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(14)

        Column({ space: 2 }) {
          Text('状态信息')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
          Text(this.dialogStatusMessage)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Row({ space: 4 }) {
            Text(this.dialogStatusExpanded ? '收起' : '展开')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
            SymbolGlyph(this.dialogStatusExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([this.color('icon_primary')])
          }
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .borderRadius(15)
        .backgroundColor(this.color('comp_background_tertiary'))
        .onClick(() => {
          this.toggleDialogStatusExpand();
        })
      }
      .width('100%')

      if (this.dialogStatusDetailVisible || this.dialogStatusExpanded) {
        Column() {
          Text(this.dialogStatusMessage)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .maxLines(12)
            .width('100%')
        }
        .width('100%')
        .height(this.dialogStatusDetailHeight)
        .opacity(this.dialogStatusDetailOpacity)
        .translate({ x: 0, y: this.dialogStatusDetailTranslateY })
        .clip(true)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('comp_background_secondary'))
    .borderRadius(16)
  }
  @Builder private buildConnectionDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(`rgba(6, 12, 18, ${0.52 * this.dialogBackdropOpacity})`)
        .onClick(() => {
          this.closeConnectionDialog();
        })

      Column({ space: 16 }) {
        Column({ space: 4 }) {
          Text(this.dialogMode === 'create' ? '新建网络连接' : '编辑网络连接')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Text(this.dialogMode === 'create'
            ? '填写连接信息，保存后直接进入远程文件浏览页。'
            : '更新连接信息，测试通过后可继续浏览和导入。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
        }
        .width('100%')

        Scroll(this.dialogScroller) {
          Column({ space: 16 }) {
            this.buildDialogStatusCard()

            Row({ space: 8 }) {
              ForEach(this.protocolOptions, (protocol: NetworkFolderProtocol) => {
                this.buildDialogProtocolOption(protocol)
              }, (protocol: NetworkFolderProtocol) => protocol)
            }
            .width('100%')

            this.buildDialogField($r('sys.symbol.externaldrive_fill'), '连接名称', '留空时自动生成',
              this.dialogDraft.name, (value: string) => {
                const nextDraft = this.cloneDraft(this.dialogDraft);
                nextDraft.name = value;
                this.dialogDraft = nextDraft;
              })

            if (this.dialogDraft.protocol === 'webdav') {
              this.buildDialogField($r('sys.symbol.link'), '服务地址', 'https://example.com/dav',
                this.dialogDraft.serverUrl, (value: string) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.serverUrl = value;
                  this.dialogDraft = nextDraft;
                })
            } else {
              this.buildDialogField($r('sys.symbol.desktop'), '主机地址',
                this.dialogDraft.protocol === 'smb'
                  ? '192.168.1.10'
                  : (this.dialogDraft.protocol === 'sftp' ? 'sftp.example.com' : 'ftp.example.com'),
                this.dialogDraft.host, (value: string) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.host = value;
                  this.dialogDraft = nextDraft;
                })
            }

            if (this.dialogDraft.protocol === 'smb') {
              this.buildDialogField($r('sys.symbol.folder_fill'), '共享名称', 'media',
                this.dialogDraft.shareName, (value: string) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.shareName = value;
                  this.dialogDraft = nextDraft;
                })
            }

            Row({ space: 12 }) {
              Column() {
                this.buildDialogField($r('sys.symbol.person_fill'), '用户名', '可留空',
                  this.dialogDraft.username, (value: string) => {
                    const nextDraft = this.cloneDraft(this.dialogDraft);
                    nextDraft.username = value;
                    this.dialogDraft = nextDraft;
                  })
              }
              .layoutWeight(1)

              Column() {
                this.buildDialogField($r('sys.symbol.lock_fill'), '密码', '可留空',
                  this.dialogDraft.password, (value: string) => {
                    const nextDraft = this.cloneDraft(this.dialogDraft);
                    nextDraft.password = value;
                    this.dialogDraft = nextDraft;
                  }, InputType.Password)
              }
              .layoutWeight(1)
            }
            .width('100%')

            if (this.dialogDraft.protocol === 'smb') {
              Row({ space: 12 }) {
                Column() {
                  this.buildDialogField($r('sys.symbol.building'), '域', 'WORKGROUP',
                    this.dialogDraft.domain, (value: string) => {
                      const nextDraft = this.cloneDraft(this.dialogDraft);
                      nextDraft.domain = value;
                      this.dialogDraft = nextDraft;
                    })
                }
                .layoutWeight(1)

                Column() {
                  this.buildDialogField($r('sys.symbol.wifi'), '客户端 IP', '留空自动探测',
                    this.dialogDraft.clientIP, (value: string) => {
                      const nextDraft = this.cloneDraft(this.dialogDraft);
                      nextDraft.clientIP = value;
                      this.dialogDraft = nextDraft;
                    })
                }
                .layoutWeight(1)
              }
              .width('100%')
            }

            Row({ space: 12 }) {
              Column() {
                this.buildDialogField($r('sys.symbol.folder'), '基准路径',
                  this.dialogDraft.protocol === 'smb' ? '/books' : '/library',
                  this.dialogDraft.basePath, (value: string) => {
                    const nextDraft = this.cloneDraft(this.dialogDraft);
                    nextDraft.basePath = value;
                    this.dialogDraft = nextDraft;
                  })
              }
              .layoutWeight(1)

              Column() {
                this.buildDialogField($r('sys.symbol.link'), '端口', `${this.dialogDraft.port}`,
                  `${this.dialogDraft.port}`, (value: string) => {
                    const nextDraft = this.cloneDraft(this.dialogDraft);
                    const parsed = parseInt(value, 10);
                    if (!Number.isNaN(parsed) && parsed > 0) {
                      nextDraft.port = parsed;
                    }
                    this.dialogDraft = nextDraft;
                  }, InputType.Number)
              }
              .layoutWeight(1)
            }
            .width('100%')

            this.buildDialogField($r('sys.symbol.timer'), '超时（毫秒）', '30000',
              `${this.dialogDraft.timeoutMs}`, (value: string) => {
                const nextDraft = this.cloneDraft(this.dialogDraft);
                const parsed = parseInt(value, 10);
                if (!Number.isNaN(parsed) && parsed > 0) {
                  nextDraft.timeoutMs = parsed;
                }
                this.dialogDraft = nextDraft;
              }, InputType.Number)

            if (this.dialogDraft.protocol === 'ftp' || this.dialogDraft.protocol === 'ftps') {
              this.buildDialogToggle($r('sys.symbol.arrow_clockwise'), '被动模式',
                '建议保留开启，以兼容更多 FTP 服务端。', this.dialogDraft.passive, (value: boolean) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.passive = value;
                  this.dialogDraft = nextDraft;
                })
            }

            if (this.dialogDraft.protocol === 'webdav' || this.dialogDraft.protocol === 'ftps') {
              this.buildDialogToggle($r('sys.symbol.checkmark_circle'), '验证 SSL',
                '建议保持开启，只有在自签名证书场景再关闭。', this.dialogDraft.verifySSL, (value: boolean) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.verifySSL = value;
                  this.dialogDraft = nextDraft;
                })
            }

            if (this.dialogDraft.protocol === 'sftp') {
              this.buildDialogToggle($r('sys.symbol.lock_shield'), '验证主机密钥',
                '建议保持开启，防止中间人攻击。关闭后将信任所有主机密钥。', this.dialogDraft.verifyHostKey, (value: boolean) => {
                  const nextDraft = this.cloneDraft(this.dialogDraft);
                  nextDraft.verifyHostKey = value;
                  this.dialogDraft = nextDraft;
                })
            }

            Blank().height(8)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Row({ space: 10 }) {
          this.buildActionButton('取消', $r('sys.symbol.xmark'), ACTION_STYLE_NEUTRAL, true, () => {
            this.closeConnectionDialog();
          })
          this.buildActionButton(this.dialogTesting ? '测试中…' : '测试连接', $r('sys.symbol.checkmark_circle'),
            ACTION_STYLE_INFO, !this.dialogSaving, () => {
              void this.testDialogConnection();
            })
          this.buildActionButton(this.dialogSaving ? '保存中…' : '保存', $r('sys.symbol.save'),
            ACTION_STYLE_PRIMARY, !this.dialogTesting, () => {
              void this.saveDialogConnection();
            })
        }
        .width('100%')
      }
      .width('92%')
      .height('84%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(26)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 26,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
      .opacity(this.dialogOpacity)
      .scale({ x: this.dialogScale, y: this.dialogScale })
      .translate({ x: 0, y: this.dialogTranslateY })
    }
    .width('100%')
    .height('100%')
  }

  @Builder private buildFavoritesDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(`rgba(6, 12, 18, ${0.52 * this.favDialogBackdropOpacity})`)
        .onClick(() => {
          this.closeFavoritesDialog();
        })

      Column({ space: 16 }) {
        Row() {
          Text('收藏夹')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([this.color('text_secondary')])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.color('comp_background_tertiary'))
          .onClick(() => {
            this.closeFavoritesDialog();
          })
        }
        .width('100%')

        Divider()
          .color(this.color('text_muted'))
          .opacity(0.6)

        if (this.favoriteFolders.length === 0) {
          Text('暂无收藏的文件夹')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.favoriteFolders, (path: string) => {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.bookmark_fill'))
                    .fontSize(14)
                    .fontColor([this.color('accent_primary')])
                  Text(path)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_primary'))
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button('前往')
                    .height(28)
                    .borderRadius(14)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .backgroundColor(this.color('accent_primary'))
                    .fontColor(this.color('text_white'))
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      void this.navigateToFavoriteFolder(path);
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(12)
                .backgroundColor(this.color('comp_background_secondary'))
              }, (path: string) => path)
            }
          }
          .scrollBar(BarState.Auto)
          .layoutWeight(1)
        }
      }
      .width('92%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      .constraintSize({ maxHeight: '70%' })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(26)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 26,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
      .opacity(this.favDialogOpacity)
      .scale({ x: this.favDialogScale, y: this.favDialogScale })
      .translate({ x: 0, y: this.favDialogTranslateY })
    }
    .width('100%')
    .height('100%')
  }

  @Builder private buildScanPanel() {
    Stack({ alignContent: Alignment.Center }) {
      // Backdrop
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(`rgba(6, 12, 18, ${0.52 * this.scanBackdropOpacity})`)
        .onClick(() => {
          this.closeScanPanel();
        })

      // Main panel
      Column({ space: 12 }) {
        // Header
        Row() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.wifi'))
              .fontSize(18)
              .fontColor([this.color('accent_primary')])
            Text('网络扫描')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
          }
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([this.color('text_secondary')])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.color('comp_background_tertiary'))
          .onClick(() => {
            this.closeScanPanel();
          })
        }
        .width('100%')

        Divider()
          .color(this.color('text_muted'))
          .opacity(0.6)

        // Subnet input + action button
        Row({ space: 10 }) {
          TextInput({ text: this.scanSubnet, placeholder: '子网前缀 (如 192.168.1)' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(this.color('comp_background_secondary'))
            .borderRadius(12)
            .onChange((value: string) => {
              this.scanSubnet = value;
            })
          if (this.scanPhase === 'scanning') {
            Button() {
              Row({ space: 6 }) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(this.color('text_white'))
                Text('停止')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
              }
            }
            .height(40)
            .borderRadius(12)
            .backgroundColor(this.color('accent_primary'))
            .fontColor(this.color('text_white'))
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.cancelNetworkScan();
            })
          } else {
            Button('开始扫描')
              .height(40)
              .borderRadius(12)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.color('accent_primary'))
              .fontColor(this.color('text_white'))
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.startNetworkScan();
              })
          }
        }
        .width('100%')

        // Progress section with animation
        if (this.scanPhase === 'scanning') {
          Column({ space: 8 }) {
            // Progress bar
            Column({ space: 4 }) {
              Progress({
                value: this.scanProgress.scannedHosts,
                total: this.scanProgress.totalHosts,
                type: ProgressType.Linear
              })
                .width('100%')
                .height(8)
                .borderRadius(4)
              Row() {
                Text(`${this.scanProgress.scannedHosts}/${this.scanProgress.totalHosts}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_secondary'))
                Text(` (${Math.floor(this.scanProgress.scannedHosts * 100 / Math.max(1, this.scanProgress.totalHosts))}%)`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
                Blank()
                if (this.scanResults.length > 0) {
                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(12)
                      .fontColor([this.color('accent_primary')])
                    Text(`已发现 ${this.scanResults.length} 台`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('accent_primary'))
                      .fontWeight(FontWeight.Medium)
                  }
                }
              }
              .width('100%')
            }
            .width('100%')

            // Current scan target
            Row({ space: 6 }) {
              LoadingProgress()
                .width(12)
                .height(12)
                .color(this.color('accent_primary'))
              Text(`正在扫描: ${this.scanProgress.currentIP}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_muted'))
              Blank()
              Text(`${this.scanDurationMs}ms`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_muted'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .borderRadius(8)
            .backgroundColor(this.color('comp_background_tertiary'))
          }
          .width('100%')
          .animation({ duration: 200, curve: Curve.EaseInOut })
        }

        // Scan complete summary
        if (this.scanPhase === 'done') {
          Row({ space: 8 }) {
            SymbolGlyph(this.scanResults.length > 0
              ? $r('sys.symbol.checkmark_circle_fill')
              : $r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.color('accent_primary')])
            Text(this.scanResults.length > 0
              ? `扫描完成，发现 ${this.scanResults.length} 台服务器`
              : '扫描完成，未发现文件服务器')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
            Blank()
            Text(`${this.scanDurationMs}ms`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_muted'))
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(this.color('comp_background_tertiary'))
          .animation({ duration: 200, curve: Curve.EaseInOut })
        }

        // Results list with animation
        if (this.scanResults.length > 0) {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.scanResults, (host: NetworkScanHost) => {
                this.buildScanResultCard(host)
              }, (host: NetworkScanHost) => host.ip)
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .layoutWeight(1)
          .animation({ duration: 300, curve: Curve.EaseInOut })
        } else if (this.scanPhase === 'idle') {
          // Idle state - show tips
          Column({ space: 16 }) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(48)
                .fontColor([this.color('accent_primary')])
              Text('局域网扫描')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_primary'))
            }
            Column({ space: 8 }) {
              Text('自动发现局域网中的文件服务器')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_secondary'))
                .textAlign(TextAlign.Center)
              Text('支持 FTP / SFTP / FTPS / WebDAV / SMB')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_muted'))
                .textAlign(TextAlign.Center)
            }
            // Protocol icons
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.externaldrive_fill'))
                  .fontSize(20)
                  .fontColor([this.color('accent_primary')])
                Text('NAS')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
              }
              Column({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.folder_fill'))
                  .fontSize(20)
                  .fontColor([this.color('accent_primary')])
                Text('SMB')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
              }
              Column({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(20)
                  .fontColor([this.color('accent_primary')])
                Text('FTP')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
              }
              Column({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.link'))
                  .fontSize(20)
                  .fontColor([this.color('accent_primary')])
                Text('WebDAV')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
              }
            }
            .padding({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('92%')
      .height('84%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(26)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 26,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
      .opacity(this.scanOpacity)
      .scale({ x: this.scanScale, y: this.scanScale })
      .translate({ x: 0, y: this.scanTranslateY })
    }
    .width('100%')
    .height('100%')
  }

  @Builder private buildScanResultCard(host: NetworkScanHost) {
    Column({ space: 10 }) {
      // Host info row
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.externaldrive_fill'))
            .fontSize(20)
            .fontColor([this.color('accent_primary')])
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(10)

        Column({ space: 3 }) {
          Text(host.ip)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          if (host.hostname.length > 0) {
            Text(host.hostname)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // Protocol count badge
        Text(`${host.protocolPorts.length} 个协议`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(this.color('comp_background_tertiary'))
      }
      .width('100%')

      // Protocol badges with port info
      Row({ space: 6 }) {
        ForEach(host.protocolPorts, (pp: ProtocolPort) => {
          Text(`${getScanProtocolLabel(pp.protocol)}:${pp.port}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('accent_primary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor(this.color('comp_background_tertiary'))
            .border({ width: 0.5, color: this.color('accent_primary') })
        }, (pp: ProtocolPort) => `${host.ip}_badge_${pp.protocol}_${pp.port}`)
      }
      .width('100%')

      // Action buttons
      Column({ space: 6 }) {
        // Protocol connection buttons
        ForEach(host.protocolPorts, (pp: ProtocolPort) => {
          Row({ space: 8 }) {
            SymbolGlyph(this.getScanProtocolIcon(pp.protocol))
              .fontSize(14)
              .fontColor([this.color('accent_primary')])
            Text(`连接 ${getScanProtocolLabel(pp.protocol)} :${pp.port}`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([this.color('text_muted')])
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(10)
          .backgroundColor(this.color('comp_background_secondary'))
          .onClick(() => {
            this.openConnectionFromScan(host, pp.protocol);
          })
        }, (pp: ProtocolPort) => `${host.ip}_btn_${pp.protocol}_${pp.port}`)

        // SMB shares button
        if (host.protocols.includes(5)) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.folder_fill'))
              .fontSize(14)
              .fontColor([this.color('accent_primary')])
            Text(this.smbEnumLoading && this.smbEnumHost === host.ip ? '正在加载共享...' : '查看 SMB 共享')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
              .layoutWeight(1)
            if (this.smbEnumLoading && this.smbEnumHost === host.ip) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(this.color('accent_primary'))
            } else {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(12)
                .fontColor([this.color('text_muted')])
            }
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(10)
          .backgroundColor(this.color('comp_background_secondary'))
          .enabled(!(this.smbEnumLoading && this.smbEnumHost === host.ip))
          .onClick(() => {
            this.requestSMBShareEnum(host);
          })
        }
      }
      .width('100%')

      // SMB shares sub-list
      if (this.smbEnumHost === host.ip && this.smbEnumShares.length > 0) {
        Column({ space: 4 }) {
          Row() {
            Text('可用共享')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
            Blank()
            Text(`${this.smbEnumShares.length} 项`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_muted'))
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 4 })

          ForEach(this.smbEnumShares, (share: NetworkSMBShare) => {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder_fill'))
                .fontSize(14)
                .fontColor([this.color('accent_primary')])
              Column({ space: 2 }) {
                Text(share.name)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_primary'))
                if (share.remark.length > 0) {
                  Text(share.remark)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_secondary'))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button('连接')
                .height(26)
                .borderRadius(8)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.color('accent_primary'))
                .fontColor(this.color('text_white'))
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.openSMBConnectionFromShare(host, share);
                })
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(this.color('comp_background_secondary'))
          }, (share: NetworkSMBShare) => `${host.ip}_${share.name}`)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 6, bottom: 6 })
        .borderRadius(10)
        .backgroundColor(this.color('comp_background_tertiary'))
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(this.color('comp_background_secondary'))
    .border({
      width: 0.5,
      color: this.color('text_muted')
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: this.color('background'),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column({ space: 0 }) {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          Stack() {
            if (this.viewMode === 'connections') {
              this.buildConnectionsRefreshView()
            } else if (this.viewMode === 'cache') {
              this.buildCacheDetailView()
            } else {
              if (this.hasSelectedConnection()) {
                this.buildBrowserRefreshView(this.getSelectedConnectionForRender())
              } else {
                this.buildConnectionsRefreshView()
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .opacity(this.routeOpacity)
          .translate({ x: this.routeTranslateX, y: this.pageReady ? 0 : 12 })
          .scale({ x: this.routeScale, y: this.routeScale })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.showFloatingCapsule) {
          Column() {
            this.buildFloatingStatusCapsule()
          }
          .width('100%')
          .padding({
            top: SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight) + 10,
            left: 16,
            right: 16
          })
          .alignItems(HorizontalAlign.Center)
          .translate({ y: this.showFloatingCapsule ? 0 : -12 })
          .opacity(this.showFloatingCapsule ? 1 : 0)
          .animation({ duration: 220, curve: Curve.EaseInOut })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(12)
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '网络文件夹',
          appFontFamily: this.appFontFamily,
          backAction: () => this.handleTitleBarBack()
        })

        if (this.dialogMounted) {
          this.buildConnectionDialog()
        }
        if (this.favDialogMounted) {
          this.buildFavoritesDialog()
        }
        if (this.scanMounted) {
          this.buildScanPanel()
        }
      }
    }
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      /*
      .titleBar({
        padding: {
          start: LengthMetrics.vp(16),
          end: LengthMetrics.vp(16)
        },
        style: {
          originalStyle: {
            backgroundStyle: { backgroundColor: this.color('panel_background') },
            contentStyle: {
              titleStyle: { mainTitleColor: this.color('text_primary') },
              backIconStyle: {
                backgroundColor: this.color('comp_background_tertiary'),
                iconColor: this.color('icon_primary')
              }
            }
          }
        },
        content: {
          title: {
            mainTitle: '网络文件夹'
          }
        }
      })
      */
      .onReady((context: NavDestinationContext) => {
        this.pathStack = context.pathStack;
        void this.initializePage();
      })
      .onBackPressed(() => {
        return this.handleTitleBarBack();
      })
      .backgroundColor(Color.Transparent)
  }
}
