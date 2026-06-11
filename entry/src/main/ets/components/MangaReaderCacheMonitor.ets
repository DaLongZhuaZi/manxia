// 文件路径: entry/src/main/ets/components/MangaReaderCacheMonitor.ets
// 职责: 汇总漫画阅读器缓存归属与运行快照，不持有 UI 状态，不释放资源。

export enum MangaReaderCacheOwner {
  ACTIVE_PIXEL_MAP = 'active_pixel_map',
  LEGACY_IMAGE_META = 'legacy_image_meta',
  LOCAL_IMAGE_LRU = 'local_image_lru',
  PRELOAD_MANAGER = 'preload_manager',
  IMAGE_LOAD_STATE = 'image_load_state'
}

export class MangaReaderCacheOwnershipItem {
  public owner: MangaReaderCacheOwner = MangaReaderCacheOwner.ACTIVE_PIXEL_MAP;
  public name: string = '';
  public responsibility: string = '';
  public releasePolicy: string = '';
}

export class MangaReaderCacheSnapshotInput {
  public reason: string = '';
  public pagePixelMapCount: number = 0;
  public pagePixelMapMetaCount: number = 0;
  public pixelMapEpochCount: number = 0;
  public reactiveImageLoadStateCount: number = 0;
  public legacyImageMetaCount: number = 0;
  public legacyImageMetaBytes: number = 0;
  public legacyImageMetaMaxBytes: number = 0;
  public preloadedImageCount: number = 0;
  public localCacheCount: number = 0;
  public localCacheBytes: number = 0;
  public localCacheMaxBytes: number = 0;
  public preloadQueueCount: number = 0;
  public preloadCompletedCount: number = 0;
  public preloadFailedCount: number = 0;
  public preloadMemCacheHits: number = 0;
  public preloadDiskCacheHits: number = 0;
  public preloadNetworkLoads: number = 0;
  public managedLoadStateTotal: number = 0;
  public managedLoadStateIdle: number = 0;
  public managedLoadStateLoading: number = 0;
  public managedLoadStateCompleted: number = 0;
  public managedLoadStateError: number = 0;
  public warmupState: string = '';
  public archivePath: string = '';
  public extractDir: string = '';
  public reusedExtract: boolean = false;
  public archivePageCount: number = 0;
  public networkPageCount: number = 0;
}

export class MangaReaderCacheSnapshot {
  public reason: string = '';
  public pagePixelMapCount: number = 0;
  public pagePixelMapMetaCount: number = 0;
  public pixelMapEpochCount: number = 0;
  public reactiveImageLoadStateCount: number = 0;
  public legacyImageMetaCount: number = 0;
  public legacyImageMetaBytes: number = 0;
  public legacyImageMetaMaxBytes: number = 0;
  public preloadedImageCount: number = 0;
  public localCacheCount: number = 0;
  public localCacheBytes: number = 0;
  public localCacheMaxBytes: number = 0;
  public preloadQueueCount: number = 0;
  public preloadCompletedCount: number = 0;
  public preloadFailedCount: number = 0;
  public preloadMemCacheHits: number = 0;
  public preloadDiskCacheHits: number = 0;
  public preloadNetworkLoads: number = 0;
  public managedLoadStateTotal: number = 0;
  public managedLoadStateIdle: number = 0;
  public managedLoadStateLoading: number = 0;
  public managedLoadStateCompleted: number = 0;
  public managedLoadStateError: number = 0;
  public warmupState: string = '';
  public archivePath: string = '';
  public extractDir: string = '';
  public reusedExtract: boolean = false;
  public archivePageCount: number = 0;
  public networkPageCount: number = 0;
  public hasActivity: boolean = false;
  public hasLegacyMetaPressure: boolean = false;
  public hasLocalCachePressure: boolean = false;
  public hasSplitPixelMapOwnership: boolean = false;
}

export class MangaReaderCacheMonitor {
  public createOwnershipItems(): MangaReaderCacheOwnershipItem[] {
    const items: MangaReaderCacheOwnershipItem[] = new Array<MangaReaderCacheOwnershipItem>();
    items.push(this.buildOwnershipItem(
      MangaReaderCacheOwner.ACTIVE_PIXEL_MAP,
      'pagePixelMaps',
      '在线图片与普通阅读可直接显示的 PixelMap 引用中心',
      '由 MangaPixelMapLifecycleManager 在不可见清理、章节切换和页面销毁时释放'
    ));
    items.push(this.buildOwnershipItem(
      MangaReaderCacheOwner.LOCAL_IMAGE_LRU,
      'LocalImageCacheManager',
      '本地漫画降采样 PixelMap LRU 缓存，优先服务条漫快速滚动',
      '由 LocalImageCacheManager 按容量、数量和可见范围释放'
    ));
    items.push(this.buildOwnershipItem(
      MangaReaderCacheOwner.LEGACY_IMAGE_META,
      'imageCache',
      '旧版 URL 预加载元信息计数，不拥有真实 PixelMap',
      '随 preloadedImages 和旧优化图片链路清理，后续可在验证后删除'
    ));
    items.push(this.buildOwnershipItem(
      MangaReaderCacheOwner.PRELOAD_MANAGER,
      'PreloadManager',
      '预加载队列、完成/失败状态与缓存命中统计',
      '章节切换和距离清理时删除状态，不释放 PixelMap'
    ));
    items.push(this.buildOwnershipItem(
      MangaReaderCacheOwner.IMAGE_LOAD_STATE,
      'ImageLoadStateManager',
      '新加载状态管理器内部快照与 PixelMap 引用镜像',
      '状态清理时仅删除引用，实际 PixelMap 生命周期归属外层缓存'
    ));
    return items;
  }

  public createSnapshot(input: MangaReaderCacheSnapshotInput): MangaReaderCacheSnapshot {
    const snapshot: MangaReaderCacheSnapshot = new MangaReaderCacheSnapshot();
    snapshot.reason = input.reason;
    snapshot.pagePixelMapCount = input.pagePixelMapCount;
    snapshot.pagePixelMapMetaCount = input.pagePixelMapMetaCount;
    snapshot.pixelMapEpochCount = input.pixelMapEpochCount;
    snapshot.reactiveImageLoadStateCount = input.reactiveImageLoadStateCount;
    snapshot.legacyImageMetaCount = input.legacyImageMetaCount;
    snapshot.legacyImageMetaBytes = input.legacyImageMetaBytes;
    snapshot.legacyImageMetaMaxBytes = input.legacyImageMetaMaxBytes;
    snapshot.preloadedImageCount = input.preloadedImageCount;
    snapshot.localCacheCount = input.localCacheCount;
    snapshot.localCacheBytes = input.localCacheBytes;
    snapshot.localCacheMaxBytes = input.localCacheMaxBytes;
    snapshot.preloadQueueCount = input.preloadQueueCount;
    snapshot.preloadCompletedCount = input.preloadCompletedCount;
    snapshot.preloadFailedCount = input.preloadFailedCount;
    snapshot.preloadMemCacheHits = input.preloadMemCacheHits;
    snapshot.preloadDiskCacheHits = input.preloadDiskCacheHits;
    snapshot.preloadNetworkLoads = input.preloadNetworkLoads;
    snapshot.managedLoadStateTotal = input.managedLoadStateTotal;
    snapshot.managedLoadStateIdle = input.managedLoadStateIdle;
    snapshot.managedLoadStateLoading = input.managedLoadStateLoading;
    snapshot.managedLoadStateCompleted = input.managedLoadStateCompleted;
    snapshot.managedLoadStateError = input.managedLoadStateError;
    snapshot.warmupState = input.warmupState;
    snapshot.archivePath = input.archivePath;
    snapshot.extractDir = input.extractDir;
    snapshot.reusedExtract = input.reusedExtract;
    snapshot.archivePageCount = input.archivePageCount;
    snapshot.networkPageCount = input.networkPageCount;
    snapshot.hasActivity = this.hasActivity(input);
    snapshot.hasLegacyMetaPressure = this.isOverPressure(input.legacyImageMetaBytes, input.legacyImageMetaMaxBytes);
    snapshot.hasLocalCachePressure = this.isOverPressure(input.localCacheBytes, input.localCacheMaxBytes);
    snapshot.hasSplitPixelMapOwnership = input.pagePixelMapCount > 0 && input.localCacheCount > 0;
    return snapshot;
  }

  public describe(snapshot: MangaReaderCacheSnapshot): string {
    return `缓存快照(${snapshot.reason}): activePM=${snapshot.pagePixelMapCount}, localLRU=${snapshot.localCacheCount}, legacyMeta=${snapshot.legacyImageMetaCount}, preloadQueue=${snapshot.preloadQueueCount}, loading=${snapshot.managedLoadStateLoading}, error=${snapshot.managedLoadStateError}, warmupState=${snapshot.warmupState}, archivePath=${snapshot.archivePath}, extractDir=${snapshot.extractDir}, reusedExtract=${snapshot.reusedExtract}, pageCount=${snapshot.archivePageCount}, networkPageCount=${snapshot.networkPageCount}`;
  }

  private buildOwnershipItem(
    owner: MangaReaderCacheOwner,
    name: string,
    responsibility: string,
    releasePolicy: string
  ): MangaReaderCacheOwnershipItem {
    const item: MangaReaderCacheOwnershipItem = new MangaReaderCacheOwnershipItem();
    item.owner = owner;
    item.name = name;
    item.responsibility = responsibility;
    item.releasePolicy = releasePolicy;
    return item;
  }

  private hasActivity(input: MangaReaderCacheSnapshotInput): boolean {
    return input.pagePixelMapCount > 0 ||
      input.localCacheCount > 0 ||
      input.legacyImageMetaCount > 0 ||
      input.preloadedImageCount > 0 ||
      input.preloadQueueCount > 0 ||
      input.preloadCompletedCount > 0 ||
      input.preloadFailedCount > 0 ||
      input.managedLoadStateTotal > 0 ||
      input.reactiveImageLoadStateCount > 0 ||
      input.warmupState.length > 0;
  }

  private isOverPressure(size: number, maxSize: number): boolean {
    if (maxSize <= 0) {
      return false;
    }
    return size >= maxSize * 0.8;
  }
}
