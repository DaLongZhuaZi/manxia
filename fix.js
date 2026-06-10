const fs = require('fs');
const file = 'F:/DevEcoStudioProject/manxia/entry/src/main/ets/pages/SourceDetailPage.ets';
let content = fs.readFileSync(file, 'utf8');

const s1 = `  // 设备方向检测
  @State private isLandscape: boolean = false;
  @State addedComicIds: Record<string, boolean> = {}; // 已添加到书库的漫画ID集合
  @State private coverPixelMaps: Map<string, image.PixelMap> = new Map();
  @State private coverAspectRatios: Map<string, number> = new Map();
  
  // 设备方向检测
  @State private isLandscape: boolean = false;`;

const r1 = `  @State addedComicIds: Record<string, boolean> = {}; // 已添加到书库的漫画ID集合
  @State private coverPixelMaps: Map<string, image.PixelMap> = new Map();
  @State private coverAspectRatios: Map<string, number> = new Map();
  
  // 设备方向检测
  @State private isLandscape: boolean = false;`;

content = content.replace(s1, r1);

const s2 = `    // 初始化设备方向
    this.updateDeviceOrientation();
    
        const searchType = param.searchType as string | undefined;`;

const r2 = `    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 获取路由参数 - 从NavPathStack获取
    const params: ESObject[] = this.pathStack.getParamByName('SourceDetailPage') as ESObject[];
    if (params && params.length > 0) {
      const param: ESObject = params[0] as ESObject;
      if (param && param.sourceId) {
        this.sourceId = param.sourceId as number;
        this.sourceDetailEnterTimestamp = Date.now();
        logger.info(TAG, \`加载图源详情，ID: \${this.sourceId}\`);
        
        // 保存初始标签和搜索关键词参数
        const initialTab = param.initialTab as string | undefined;
        const searchKeyword = param.searchKeyword as string | undefined;
        const searchType = param.searchType as string | undefined;`;

content = content.replace(s2, r2);

// Fix refreshAddedComicIds if not added
const s3 = `  private async initializeAsyncWithParams(initialTab?: string, searchKeyword?: string, searchType?: string, fromGlobalSearch?: boolean): Promise<void> {`;
const r3 = `  /**
   * 刷新当前图源下已加入书库的漫画ID记录
   */
  private async refreshAddedComicIds(): Promise<void> {
    try {
      if (!this.sourceId) return;
      const ids = await this.dataManager.getAddedExternalIdsBySource(this.sourceId);
      const newAddedIds: Record<string, boolean> = {};
      ids.forEach(id => {
        newAddedIds[id] = true;
      });
      this.addedComicIds = newAddedIds;
    } catch (error) {
      logger.error(TAG, '刷新已添加书库漫画状态失败', String(error));
    }
  }

  /**
   * 异步初始化（带参数版本）
   * @param fromGlobalSearch 是否来自全局搜索，如果是则优先使用缓存结果
   */
  private async initializeAsyncWithParams(initialTab?: string, searchKeyword?: string, searchType?: string, fromGlobalSearch?: boolean): Promise<void> {`;
if (!content.includes('refreshAddedComicIds')) {
    content = content.replace(s3, r3);
}

// Fix loadComics
const s4 = `  private async loadComics(): Promise<void> {
    if (this.isLoading) return;

    try {
      this.isLoading = true;`;
const r4 = `  private async loadComics(): Promise<void> {
    if (this.isLoading) return;

    try {
      this.isLoading = true;
      
      await this.refreshAddedComicIds();`;
if (!content.includes('await this.refreshAddedComicIds();') && content.includes(s4)) {
    content = content.replace(s4, r4);
}

fs.writeFileSync(file, content);
