/**
 * Suwayomi 浏览页面
 * 浏览 Suwayomi 服务器上的漫画源和漫画列表
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType, ThemeManager } from '../Framework/Managers/ThemeManager';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor, SuwayomiExtensionSource } from '../Framework/Source/SuwayomiSourceExecutor';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import { SuwayomiCategory, PaginatedResult, MangaSortType, SortDirection, MangaSortOption, MANGA_SORT_OPTIONS } from '../Framework/Source/SuwayomiSource';
import { SuwayomiSourceBrowseParams } from './SuwayomiSourceBrowsePage';
import SuwayomiCacheManager from '../Framework/Source/SuwayomiCacheManager';
import DownloadDirManager from '../Framework/Storage/DownloadDirManager';
import { SuwayomiImage } from '../components/SuwayomiImage';

const TAG = 'SuwayomiBrowsePage';
const TITLE_BAR_HEIGHT: number = 56;
const PAGE_SIZE: number = 50;

// 浏览模式
type BrowseMode = 'sources' | 'library';

// 页面参数接口
interface SuwayomiMangaDetailParams {
  mangaId: string;
  title: string;
}

@Component
export struct SuwayomiBrowsePage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isLoading: boolean = false;
  @State isLoadingMore: boolean = false;
  @State errorMessage: string = '';

  // 数据
  @State sources: SuwayomiExtensionSource[] = [];
  @State mangas: ComicInfo[] = [];
  @State currentSource: SuwayomiExtensionSource | null = null;

  // 分类
  @State categories: SuwayomiCategory[] = [];
  @State selectedCategoryId: number = -1;
  @State totalCount: number = 0;
  @State hasMore: boolean = false;
  @State currentOffset: number = 0;

  // 浏览模式
  @State browseMode: BrowseMode = 'library';

  // 搜索
  @State searchQuery: string = '';
  @State isSearching: boolean = false;

  // 显示模式
  @State displayMode: 'grid' | 'list' = 'grid';

  // 排序
  @State selectedSortIndex: number = 0;
  @State showSortMenu: boolean = false;

  // 下拉刷新
  @State isRefreshing: boolean = false;

  // 缓存图片路径映射
  @State coverCachePaths: Map<string, string> = new Map();
  @State sourceIconCachePaths: Map<string, string> = new Map();

  // 图源管理
  @State pinnedSourceIds: string[] = [];
  @State selectedLanguage: string = 'all';
  @State availableLanguages: string[] = [];
  
  // 横向滑动切换分类相关状态
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;

  private executor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private readonly PREFS_NAME = 'suwayomi_browse_prefs';

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    this.isLoading = true;
    try {
      // 加载偏好设置
      await this.loadPreferences();

      await this.executor.initialize();

      if (!this.executor.isConfigured()) {
        this.errorMessage = '请先配置 Suwayomi 服务器';
        this.isLoading = false;
        return;
      }

      // 加载分类
      await this.loadCategories();
      // 如果没有保存的分类或保存的分类不存在，默认选择第一个分类
      if (this.selectedCategoryId === -1 || !this.categories.find(c => c.id === this.selectedCategoryId)) {
        if (this.categories.length > 0) {
          this.selectedCategoryId = this.categories[0].id;
        }
      }
      // 加载库中的漫画（分页）
      await this.loadLibraryPaginated(true);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      this.errorMessage = `初始化失败: ${error}`;
    }
    this.isLoading = false;
  }

  private async loadPreferences(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: this.PREFS_NAME });
      this.displayMode = (store.getSync('displayMode', 'grid') as string) === 'list' ? 'list' : 'grid';
      const pinnedStr = store.getSync('pinnedSourceIds', '[]') as string;
      this.pinnedSourceIds = JSON.parse(pinnedStr) as string[];
      this.selectedLanguage = store.getSync('selectedLanguage', 'all') as string;
      // 加载排序设置
      this.selectedSortIndex = store.getSync('selectedSortIndex', 0) as number;
      // 加载选中的分类
      this.selectedCategoryId = store.getSync('selectedCategoryId', -1) as number;
      logger.info(TAG, `加载偏好设置: displayMode=${this.displayMode}, sortIndex=${this.selectedSortIndex}, categoryId=${this.selectedCategoryId}`);
    } catch (error) {
      logger.error(TAG, `加载偏好设置失败: ${error}`);
    }
  }

  private async savePreferences(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: this.PREFS_NAME });
      store.putSync('displayMode', this.displayMode);
      store.putSync('pinnedSourceIds', JSON.stringify(this.pinnedSourceIds));
      store.putSync('selectedLanguage', this.selectedLanguage);
      store.putSync('selectedSortIndex', this.selectedSortIndex);
      store.putSync('selectedCategoryId', this.selectedCategoryId);
      await store.flush();
    } catch (error) {
      logger.error(TAG, `保存偏好设置失败: ${error}`);
    }
  }

  private async loadCategories(): Promise<void> {
    try {
      this.categories = await this.executor.getCategories();
      logger.info(TAG, `加载分类: ${this.categories.length} 个`);
    } catch (error) {
      logger.error(TAG, `加载分类失败: ${error}`);
    }
  }

  /**
   * 切换到下一个分类（支持循环）
   */
  private switchToNextCategory(): void {
    if (this.categories.length === 0) return;
    // 构建分类ID列表，包含"全部"(-1)
    const categoryIds: number[] = [-1, ...this.categories.map(c => c.id)];
    const currentIndex = categoryIds.indexOf(this.selectedCategoryId);
    const nextIndex = (currentIndex + 1) % categoryIds.length;
    this.selectedCategoryId = categoryIds[nextIndex];
    this.savePreferences();
    this.loadLibraryPaginated(true);
  }
  
  /**
   * 切换到上一个分类（支持循环）
   */
  private switchToPrevCategory(): void {
    if (this.categories.length === 0) return;
    // 构建分类ID列表，包含"全部"(-1)
    const categoryIds: number[] = [-1, ...this.categories.map(c => c.id)];
    const currentIndex = categoryIds.indexOf(this.selectedCategoryId);
    const prevIndex = (currentIndex - 1 + categoryIds.length) % categoryIds.length;
    this.selectedCategoryId = categoryIds[prevIndex];
    this.savePreferences();
    this.loadLibraryPaginated(true);
  }

  /**
   * 下拉刷新库漫画（增量更新）
   */
  private async refreshLibrary(): Promise<void> {
    if (this.isRefreshing || this.isLoading) {
      return;
    }
    this.isRefreshing = true;
    this.errorMessage = '';
    try {
      // 重新加载分类（可能有新分类）
      await this.loadCategories();
      // 重新加载当前分类的漫画
      await this.loadLibraryPaginated(true);
      this.showToast('刷新成功');
    } catch (error) {
      logger.error(TAG, `刷新失败: ${error}`);
      this.errorMessage = `刷新失败: ${error}`;
    }
    this.isRefreshing = false;
  }

  /**
   * 下拉刷新图源列表
   */
  private async refreshSources(): Promise<void> {
    if (this.isRefreshing || this.isLoading) {
      return;
    }
    this.isRefreshing = true;
    this.errorMessage = '';
    try {
      this.sources = await this.executor.getAvailableSources();
      this.extractAvailableLanguages();
      // 预加载图源图标缓存
      this.cacheSourceIcons();
      this.showToast('刷新成功');
    } catch (error) {
      logger.error(TAG, `刷新图源失败: ${error}`);
      this.errorMessage = `刷新失败: ${error}`;
    }
    this.isRefreshing = false;
  }

  /**
   * 缓存漫画封面图片
   */
  private async cacheMangaCovers(): Promise<void> {
    if (!DownloadDirManager.isReady()) {
      return;
    }
    const headers = this.executor.getImageHeaders();
    for (const manga of this.mangas) {
      if (manga.coverUrl && !this.coverCachePaths.has(manga.id)) {
        // 检查是否已缓存
        const cachedPath = SuwayomiCacheManager.getCachedCoverPath(manga.id, manga.coverUrl);
        if (cachedPath) {
          this.coverCachePaths.set(manga.id, cachedPath);
        } else {
          // 异步缓存
          SuwayomiCacheManager.cacheCover(manga.id, manga.coverUrl, headers).then((path) => {
            if (path) {
              this.coverCachePaths.set(manga.id, path);
              this.coverCachePaths = new Map(this.coverCachePaths); // 触发UI更新
            } else {
              const coverUrl = manga.coverUrl || '';
              logger.warn(TAG, `封面缓存失败: mangaId=${manga.id}, coverUrl=${coverUrl.substring(0, 120)}`);
            }
          }).catch((error: Object | string | number | boolean) => {
            logger.warn(TAG, `封面缓存异常: mangaId=${manga.id}, error=${String(error)}`);
          });
        }
      }
    }
  }

  /**
   * 缓存图源图标
   */
  private async cacheSourceIcons(): Promise<void> {
    if (!DownloadDirManager.isReady()) {
      return;
    }
    const headers = this.executor.getImageHeaders();
    for (const source of this.sources) {
      if (source.iconUrl && !this.sourceIconCachePaths.has(source.id)) {
        const fullIconUrl = this.resolveSuwayomiAssetUrl(source.iconUrl);
        if (!fullIconUrl) {
          continue;
        }
        // 检查是否已缓存
        const cachedPath = SuwayomiCacheManager.getCachedSourceIconPath(source.id, fullIconUrl);
        if (cachedPath) {
          this.sourceIconCachePaths.set(source.id, cachedPath);
        } else {
          // 异步缓存
          SuwayomiCacheManager.cacheSourceIcon(source.id, fullIconUrl, headers).then((path) => {
            if (path) {
              this.sourceIconCachePaths.set(source.id, path);
              this.sourceIconCachePaths = new Map(this.sourceIconCachePaths); // 触发UI更新
            } else {
              logger.warn(TAG, `图标缓存失败: sourceId=${source.id}, iconUrl=${fullIconUrl.substring(0, 120)}`);
            }
          }).catch((error: Object | string | number | boolean) => {
            logger.warn(TAG, `图标缓存异常: sourceId=${source.id}, error=${String(error)}`);
          });
        }
      }
    }
  }

  /**
   * 获取漫画封面显示路径（优先使用缓存）
   */
  private getMangaCoverUrl(manga: ComicInfo): string {
    const cachedPath = this.coverCachePaths.get(manga.id);
    if (cachedPath) {
      return `file://${cachedPath}`;
    }
    return manga.coverUrl || '';
  }

  /**
   * 将 Suwayomi 资源路径（可能是相对路径）转为完整 URL
   */
  private isHostLikeUrlWithoutScheme(url: string): boolean {
    const slashIndex = url.indexOf('/');
    const hostPart = slashIndex >= 0 ? url.substring(0, slashIndex) : url;
    const pathPart = slashIndex >= 0 ? url.substring(slashIndex) : '';
    if (!hostPart) {
      return false;
    }

    const isIpv4Host = /^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?$/.test(hostPart);
    const isNamedHost = /^(localhost|[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)(?::\d+)?$/.test(hostPart);
    if (!isIpv4Host && !isNamedHost) {
      return false;
    }
    return hostPart.includes(':') || pathPart.startsWith('/');
  }

  private resolveSuwayomiAssetUrl(rawUrl: string): string {
    const url = (rawUrl || '').trim();
    if (!url) {
      return '';
    }
    if (url.includes('://') || url.startsWith('data:') || url.startsWith('file:')) {
      return url;
    }

    const serverUrlRaw = (this.executor.getServerUrl() || '').trim();
    if (!serverUrlRaw) {
      return url;
    }
    const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(serverUrlRaw);
    const normalizedServerUrl = hasScheme ? serverUrlRaw : `http://${serverUrlRaw}`;
    const serverUrl = normalizedServerUrl.endsWith('/') ?
      normalizedServerUrl.substring(0, normalizedServerUrl.length - 1) :
      normalizedServerUrl;
    const protocol = serverUrl.startsWith('https://') ? 'https:' : 'http:';

    if (url.startsWith('//')) {
      return `${protocol}${url}`;
    }
    if (this.isHostLikeUrlWithoutScheme(url)) {
      return `${protocol}//${url}`;
    }
    if (url.startsWith('/')) {
      return `${serverUrl}${url}`;
    }
    return `${serverUrl}/${url}`;
  }

  /**
   * 获取图源图标显示路径（优先使用缓存）
   */
  private getSourceIconUrl(source: SuwayomiExtensionSource): string {
    const cachedPath = this.sourceIconCachePaths.get(source.id);
    if (cachedPath) {
      return `file://${cachedPath}`;
    }
    if (source.iconUrl) {
      return this.resolveSuwayomiAssetUrl(source.iconUrl);
    }
    return '';
  }

  private async loadLibraryPaginated(reset: boolean = false): Promise<void> {
    if (reset) {
      this.currentOffset = 0;
      this.mangas = [];
    }

    if (this.isLoadingMore) return;

    this.isLoadingMore = !reset;
    this.isLoading = reset;
    this.browseMode = 'library';
    this.currentSource = null;
    this.errorMessage = '';

    try {
      const sortOption = MANGA_SORT_OPTIONS[this.selectedSortIndex];
      const result: PaginatedResult<ComicInfo> = await this.executor.getLibraryPaginated(
        this.selectedCategoryId,
        this.currentOffset,
        PAGE_SIZE,
        sortOption.type,
        sortOption.direction
      );

      if (reset) {
        this.mangas = result.items;
      } else {
        this.mangas = this.mangas.concat(result.items);
      }

      this.totalCount = result.totalCount;
      this.hasMore = result.hasMore;
      this.currentOffset += result.items.length;

      const coverCount = this.mangas.filter((manga: ComicInfo) => !!manga.coverUrl).length;
      const sampleCover = this.mangas.find((manga: ComicInfo) => !!manga.coverUrl)?.coverUrl || '';
      logger.info(
        TAG,
        `加载库漫画: ${this.mangas.length}/${this.totalCount} 本, 有封面字段: ${coverCount}/${this.mangas.length}${sampleCover ? `, 示例=${sampleCover.substring(0, 120)}` : ''}`
      );
      // 缓存封面图片
      this.cacheMangaCovers();
    } catch (error) {
      logger.error(TAG, `加载库失败: ${error}`);
      this.errorMessage = `加载失败: ${error}`;
    }
    this.isLoading = false;
    this.isLoadingMore = false;
  }

  private async loadSources(): Promise<void> {
    this.isLoading = true;
    this.browseMode = 'sources';
    this.errorMessage = '';
    try {
      this.sources = await this.executor.getAvailableSources();
      // 提取可用语言
      this.extractAvailableLanguages();
      // 缓存图源图标
      this.cacheSourceIcons();
      logger.info(TAG, `加载源: ${this.sources.length} 个, 语言: ${this.availableLanguages.length} 种`);
    } catch (error) {
      logger.error(TAG, `加载源失败: ${error}`);
      this.errorMessage = `加载失败: ${error}`;
    }
    this.isLoading = false;
  }

  private extractAvailableLanguages(): void {
    const langSet = new Set<string>();
    this.sources.forEach(source => {
      if (source.lang) {
        langSet.add(source.lang);
      }
    });
    // 自定义排序：zh, en, jp 优先，其他按字母排序
    const priorityLangs = ['zh', 'en', 'ja', 'jp'];
    const allLangs = Array.from(langSet);
    const prioritized = priorityLangs.filter(lang => allLangs.includes(lang));
    const others = allLangs.filter(lang => !priorityLangs.includes(lang)).sort();
    this.availableLanguages = [...prioritized, ...others];
  }

  private getFilteredSources(): SuwayomiExtensionSource[] {
    // 安全检查
    if (!this.sources || this.sources.length === 0) {
      return [];
    }

    let filtered = [...this.sources]; // 创建副本避免修改原数组

    // 按语言筛选
    if (this.selectedLanguage !== 'all') {
      filtered = filtered.filter(s => s.lang === this.selectedLanguage);
    }

    // 按搜索词筛选
    if (this.searchQuery && this.searchQuery.trim()) {
      const query = this.searchQuery.toLowerCase();
      filtered = filtered.filter(s =>
        (s.name && s.name.toLowerCase().includes(query)) ||
        (s.lang && s.lang.toLowerCase().includes(query))
      );
    }

    // 排序：置顶的在前面
    const pinnedIds = this.pinnedSourceIds || [];
    return filtered.sort((a, b) => {
      const aPinned = pinnedIds.includes(a.id);
      const bPinned = pinnedIds.includes(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return (a.name || '').localeCompare(b.name || '');
    });
  }

  private togglePinSource(sourceId: string): void {
    const index = this.pinnedSourceIds.indexOf(sourceId);
    if (index >= 0) {
      this.pinnedSourceIds.splice(index, 1);
    } else {
      this.pinnedSourceIds.push(sourceId);
    }
    this.pinnedSourceIds = [...this.pinnedSourceIds]; // 触发更新
    this.savePreferences();
  }

  private isSourcePinned(sourceId: string): boolean {
    return this.pinnedSourceIds.includes(sourceId);
  }

  private async performSearch(): Promise<void> {
    if (!this.searchQuery.trim()) {
      return;
    }
    this.isSearching = true;
    this.errorMessage = '';
    try {
      // 在库中搜索漫画
      this.mangas = await this.executor.searchLibrary(this.searchQuery);
      logger.info(TAG, `搜索结果: ${this.mangas.length} 本`);
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
      this.errorMessage = `搜索失败: ${error}`;
    }
    this.isSearching = false;
  }

  private toggleDisplayMode(): void {
    this.displayMode = this.displayMode === 'grid' ? 'list' : 'grid';
    this.savePreferences();
  }

  private selectSource(source: SuwayomiExtensionSource): void {
    // 跳转到专门的图源浏览页面
    const params: SuwayomiSourceBrowseParams = { source: source };
    this.pathStack.pushPathByName('SuwayomiSourceBrowsePage', params);
  }

  private openMangaDetail(manga: ComicInfo): void {
    const params: SuwayomiMangaDetailParams = { mangaId: manga.id, title: manga.title };
    this.pathStack.pushPathByName('SuwayomiMangaDetailPage', params);
  }

  private openSettings(): void {
    this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
  }

  private showToast(message: string): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
        message: message,
        duration: 2000
      });
    });
  }

  @Builder
  buildSourceItem(source: SuwayomiExtensionSource) {
    Row({ space: 12 }) {
      if (source.iconUrl) {
        SuwayomiImage({
          src: this.getSourceIconUrl(source),
          imageWidth: 40,
          imageHeight: 40,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(source.name.charAt(0))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width(40)
        .height(40)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 4 }) {
        Row({ space: 4 }) {
          if (this.isSourcePinned(source.id)) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          }
          Text(source.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(source.lang?.toUpperCase() || '')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (source.isNsfw) {
        Text('18+')
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FF6B6B')
          .borderRadius(4)
          .fontFamily(this.appFontFamily)
      }

      // 置顶按钮
      Button() {
        SymbolGlyph(this.isSourcePinned(source.id) ? $r('sys.symbol.pin_slash') : $r('sys.symbol.pin'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.togglePinSource(source.id);
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.selectSource(source))
  }

  @Builder
  buildSourceGridItem(source: SuwayomiExtensionSource) {
    Column({ space: 8 }) {
      Stack() {
        if (source.iconUrl) {
          SuwayomiImage({
            src: this.getSourceIconUrl(source),
            imageWidth: 60,
            imageHeight: 60,
            imgBorderRadius: 12,
            objectFit: ImageFit.Cover
          })
        } else {
          Column() {
            Text(source.name.charAt(0))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .fontFamily(this.appFontFamily)
          }
          .width(60)
          .height(60)
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
        }

        if (this.isSourcePinned(source.id)) {
          Column() {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(12)
              .fontColor([Color.White])
          }
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
          .position({ x: -4, y: -4 })
        }
      }

      Text(source.name)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Text(source.lang?.toUpperCase() || '')
        .fontSize(10)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.selectSource(source))
    .gesture(LongPressGesture().onAction(() => {
      this.togglePinSource(source.id);
    }))
  }

  @Builder
  buildMangaItem(manga: ComicInfo) {
    Row({ space: 12 }) {
      if (manga.coverUrl) {
        SuwayomiImage({
          src: this.getMangaCoverUrl(manga),
          imageWidth: 60,
          imageHeight: 80,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(manga.title.charAt(0))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width(60)
        .height(80)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      Column({ space: 4 }) {
        Text(manga.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)

        if (manga.author) {
          Text(manga.author)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(this.appFontFamily)
        }

        if (manga.status) {
          Text(manga.status)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.openMangaDetail(manga))
  }

  @Builder
  buildMangaGridItem(manga: ComicInfo) {
    Column({ space: 6 }) {
      if (manga.coverUrl) {
        SuwayomiImage({
          src: this.getMangaCoverUrl(manga),
          imageWidth: '100%',
          imgAspectRatio: 0.7,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(manga.title.charAt(0))
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .aspectRatio(0.7)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }

      Text(manga.title)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(4)
    .onClick(() => this.openMangaDetail(manga))
  }

  @Builder
  buildBottomTabBar() {
    Column() {
      // 顶部分隔线
      Divider()
        .width('100%')
        .height(0.5)
        .color(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

      Row({ space: 0 }) {
        // 库标签
        Column({ space: 4 }) {
          SymbolGlyph(this.browseMode === 'library' ? $r('sys.symbol.books_vertical_fill') : $r('sys.symbol.book'))
            .fontSize(24)
            .fontColor([this.browseMode === 'library' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('库')
            .fontSize(12)
            .fontColor(this.browseMode === 'library' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.loadLibraryPaginated(true))

        // 源标签
        Column({ space: 4 }) {
          SymbolGlyph(this.browseMode === 'sources' ? $r('sys.symbol.more') : $r('sys.symbol.square_grid_2x2'))
            .fontSize(24)
            .fontColor([this.browseMode === 'sources' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('源')
            .fontSize(12)
            .fontColor(this.browseMode === 'sources' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.loadSources())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: 8 })
    // .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? 'rgba(20, 20, 25, 0.5)' : 'rgba(255, 255, 255, 0.5)')
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.5
    })
    .shadow({ radius: 16, color: this.themeState.currentTheme === ThemeType.DARK ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.15)', offsetX: 0, offsetY: -4 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .position({ x: 0, y: '100%' })
    .translate({ y: -28 - 8 })
  }

  @Builder
  buildTopBar() {
    Row({ space: 8 }) {
      // 搜索框
      Search({ value: this.searchQuery, placeholder: this.browseMode === 'library' ? '搜索漫画...' : '搜索图源...' })
        .layoutWeight(1)
        .height(40)
        .searchButton('搜索')
        .onChange((value: string) => {
          this.searchQuery = value;
        })
        .onSubmit(() => {
          if (this.browseMode === 'library') {
            this.performSearch();
          }
        })

      // 显示模式切换按钮
      Button() {
        SymbolGlyph(this.displayMode === 'grid' ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .width(40)
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(20)
      .onClick(() => this.toggleDisplayMode())

      // 设置按钮
      Button() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .width(40)
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(20)
      .onClick(() => this.openSettings())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  buildLanguageFilter() {
    if (this.browseMode === 'sources' && this.availableLanguages.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          // 全部语言选项
          Text('全部')
            .fontSize(13)
            .fontColor(this.selectedLanguage === 'all' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.selectedLanguage === 'all' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(16)
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              this.selectedLanguage = 'all';
              this.savePreferences();
            })

          ForEach(this.availableLanguages, (lang: string) => {
            Text(lang.toUpperCase())
              .fontSize(13)
              .fontColor(this.selectedLanguage === lang ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.selectedLanguage === lang ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(16)
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.selectedLanguage = lang;
                this.savePreferences();
              })
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(44)
    }
  }

  @Builder
  buildSortSelector() {
    if (this.browseMode === 'library') {
      Row({ space: 8 }) {
        Text('排序:')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)

        Text(MANGA_SORT_OPTIONS[this.selectedSortIndex].label)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .bindMenu(this.buildSortMenuContent())
          .fontFamily(this.appFontFamily)

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
  }

  @Builder
  buildSortMenuContent() {
    Menu() {
      ForEach(MANGA_SORT_OPTIONS, (option: MangaSortOption, index: number) => {
        MenuItem({ content: option.label })
          .selected(index === this.selectedSortIndex)
          .onClick(() => {
            if (this.selectedSortIndex !== index) {
              this.selectedSortIndex = index;
              this.savePreferences();
              this.loadLibraryPaginated(true);
            }
          })
      })
    }
  }

  @Builder
  buildCategorySelector() {
    if (this.browseMode === 'library') {
      Scroll() {
        Row({ space: 8 }) {
          // "全部"选项
          Text('全部')
            .fontSize(13)
            .fontColor(this.selectedCategoryId === -1 ? Color.White :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.selectedCategoryId === -1 ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              this.selectedCategoryId = -1;
              this.savePreferences();
              this.loadLibraryPaginated(true);
            })
            .fontFamily(this.appFontFamily)

          // 各个分类
          ForEach(this.categories, (category: SuwayomiCategory) => {
            Text(`${category.name} (${category.mangaCount})`)
              .fontSize(13)
              .fontColor(this.selectedCategoryId === category.id ? Color.White :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.selectedCategoryId === category.id ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(16)
              .onClick(() => {
                this.selectedCategoryId = category.id;
                this.savePreferences();
                this.loadLibraryPaginated(true);
              })
              .fontFamily(this.appFontFamily)
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(44)
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          Blank().height(TITLE_BAR_HEIGHT)

          // 顶部工具栏
          this.buildTopBar()

          // 分类选择器（库模式）
          this.buildCategorySelector()

          // 语言筛选器（图源模式）
          this.buildLanguageFilter()

          // 排序选择器（库模式）
          this.buildSortSelector()

          // 统计信息
          if (this.browseMode === 'library' && this.totalCount > 0) {
            Text(`共 ${this.totalCount} 本漫画`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 16, right: 16, bottom: 8 })
              .fontFamily(this.appFontFamily)
          } else if (this.browseMode === 'sources') {
            Text(`共 ${this.getFilteredSources().length} 个图源`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 16, right: 16, bottom: 8 })
              .fontFamily(this.appFontFamily)
          }

          // 内容区域
          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
              Text('加载中...')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .margin({ top: 16 })
                .fontFamily(this.appFontFamily)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          } else if (this.errorMessage) {
            Column({ space: 16 }) {
              Text(this.errorMessage)
                .fontSize(14)
                .fontColor('#FF6B6B')
                .textAlign(TextAlign.Center)
                .fontFamily(this.appFontFamily)

              Button('打开设置')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .fontColor(Color.White)
                .onClick(() => this.openSettings())
                .fontFamily(this.appFontFamily)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding(16)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          } else if (this.browseMode === 'sources') {
            // 源列表
            if (this.getFilteredSources().length === 0) {
              Column() {
                Text('暂无图源')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.displayMode === 'grid') {
              // Grid模式
              Refresh({ refreshing: this.isRefreshing }) {
                Scroll() {
                  Column() {
                    Grid() {
                      ForEach(this.getFilteredSources(), (source: SuwayomiExtensionSource) => {
                        GridItem() {
                          this.buildSourceGridItem(source)
                        }
                      })
                    }
                    .columnsTemplate('1fr 1fr 1fr 1fr')
                    .columnsGap(8)
                    .rowsGap(8)
                    .width('100%')

                    Blank().height(80)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
              }
              .onRefreshing(() => {
                this.refreshSources();
              })
              .width('100%')
              .layoutWeight(1)
            } else {
              // List模式
              Refresh({ refreshing: this.isRefreshing }) {
                Scroll() {
                  Column({ space: 8 }) {
                    ForEach(this.getFilteredSources(), (source: SuwayomiExtensionSource) => {
                      this.buildSourceItem(source)
                    })
                    Blank().height(80)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
              }
              .onRefreshing(() => {
                this.refreshSources();
              })
              .width('100%')
              .layoutWeight(1)
            }
          } else {
            // 漫画列表
            if (this.mangas.length === 0) {
              Column() {
                Text('暂无漫画')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.displayMode === 'grid') {
              // Grid模式
              Refresh({ refreshing: this.isRefreshing }) {
                Scroll() {
                  Column() {
                    Grid() {
                      ForEach(this.mangas, (manga: ComicInfo) => {
                        GridItem() {
                          this.buildMangaGridItem(manga)
                        }
                      })
                    }
                    .columnsTemplate('1fr 1fr 1fr')
                    .columnsGap(8)
                    .rowsGap(8)
                    .width('100%')

                    // 加载更多按钮
                    if (this.hasMore) {
                      Button(this.isLoadingMore ? '加载中...' : '加载更多')
                        .width('100%')
                        .height(44)
                        .margin({ top: 16 })
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .enabled(!this.isLoadingMore)
                        .onClick(() => {
                          this.loadLibraryPaginated(false);
                        })
                        .fontFamily(this.appFontFamily)
                    }

                    Blank().height(80)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
              }
              .onRefreshing(() => {
                this.refreshLibrary();
              })
              .width('100%')
              .layoutWeight(1)
              .gesture(
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
                  .onActionStart((event: GestureEvent) => {
                    this.swipeStartX = event.offsetX;
                    this.swipeOffsetX = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.swipeOffsetX = event.offsetX - this.swipeStartX;
                  })
                  .onActionEnd((event: GestureEvent) => {
                    const swipeThreshold = 80;
                    if (this.swipeOffsetX < -swipeThreshold) {
                      this.switchToNextCategory();
                    } else if (this.swipeOffsetX > swipeThreshold) {
                      this.switchToPrevCategory();
                    }
                    this.swipeOffsetX = 0;
                  })
              )
            } else {
              // List模式
              Refresh({ refreshing: this.isRefreshing }) {
                Scroll() {
                  Column({ space: 8 }) {
                    ForEach(this.mangas, (manga: ComicInfo) => {
                      this.buildMangaItem(manga)
                    })

                    // 加载更多按钮
                    if (this.hasMore) {
                      Button(this.isLoadingMore ? '加载中...' : '加载更多')
                        .width('100%')
                        .height(44)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .enabled(!this.isLoadingMore)
                        .onClick(() => {
                          this.loadLibraryPaginated(false);
                        })
                        .fontFamily(this.appFontFamily)
                    }

                    Blank().height(80)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
              }
              .onRefreshing(() => {
                this.refreshLibrary();
              })
              .width('100%')
              .layoutWeight(1)
              .gesture(
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
                  .onActionStart((event: GestureEvent) => {
                    this.swipeStartX = event.offsetX;
                    this.swipeOffsetX = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.swipeOffsetX = event.offsetX - this.swipeStartX;
                  })
                  .onActionEnd((event: GestureEvent) => {
                    const swipeThreshold = 80;
                    if (this.swipeOffsetX < -swipeThreshold) {
                      this.switchToNextCategory();
                    } else if (this.swipeOffsetX > swipeThreshold) {
                      this.switchToPrevCategory();
                    }
                    this.swipeOffsetX = 0;
                  })
              )
            }
          }

          
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 底部导航栏
        this.buildBottomTabBar()
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: this.currentSource ? this.currentSource.name : 'Suwayomi' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
