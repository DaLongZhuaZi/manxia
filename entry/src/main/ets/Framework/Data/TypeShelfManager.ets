/**
 * 类型书架管理器
 * 管理自定义书架的创建、删除和持久化存储
 * 与BookshelfCategoryManager集成，复用内容-书架映射逻辑
 */
import { logger } from '../../Utils/Logger';
import { SettingsManager } from '../Managers/SettingsManager';
import { BookshelfCategoryManager, ContentType, CategoryItem } from './BookshelfCategoryManager';

const TAG = 'TypeShelfManager';
const TYPE_SHELVES_KEY = 'type_shelves';

/**
 * 书架类型枚举
 */
export enum ShelfType {
  SINGLE = 'single',   // 单一书架：只显示一种内容类型
  MIXED = 'mixed',     // 混合书架：可以显示多种内容类型
  DYNAMIC = 'dynamic'  // 动态书架：基于筛选条件自动匹配内容
}

/**
 * 内容类型枚举（与LibraryContentType保持一致）
 */
export enum ShelfContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

/**
 * 动态书架筛选条件接口
 */
export interface DynamicShelfFilter {
  authors: string[];          // 选中的作者
  tags: string[];             // 选中的标签
  titleKeywords: string[];    // 从标题智能拆分的关键词
  sourceNames: string[];      // 选中的书源/图源名称
  customKeywords: string[];   // 用户自定义的筛选关键词
  nsfwFilter?: 'nsfw' | 'sfw' | 'all';  // NSFW内容分级筛选：'nsfw'=仅NSFW, 'sfw'=仅SFW, 'all'/undefined=不限
}

/**
 * 类型书架接口
 */
export interface TypeShelf {
  id: string;                          // 唯一标识
  name: string;                        // 书架名称
  shelfType: ShelfType;                // 书架类型：单一、混合或动态
  contentTypes: ShelfContentType[];    // 允许的内容类型（单一书架只有一个，混合书架可以有多个）
  icon: string;                        // 书架图标（emoji或系统图标名）
  color: string;                       // 书架主题色
  order: number;                       // 排序顺序
  isSystem: boolean;                   // 是否为系统内置书架（不可删除）
  createTime: number;                  // 创建时间
  updateTime: number;                  // 更新时间
  dynamicFilter?: DynamicShelfFilter;  // 动态书架筛选条件（仅DYNAMIC类型使用）
}

/**
 * 创建书架参数
 */
export interface CreateShelfParams {
  name: string;
  shelfType: ShelfType;
  contentTypes: ShelfContentType[];
  icon?: string;
  color?: string;
  dynamicFilter?: DynamicShelfFilter;
}

/**
 * 移动内容项信息（用于批量移动）
 */
export interface MoveToShelfItemInfo {
  itemId: string;
  contentType: ContentType;
}

/**
 * 默认系统书架配置
 */
const DEFAULT_SYSTEM_SHELVES: TypeShelf[] = [
  {
    id: 'system_manga',
    name: '漫画书架',
    shelfType: ShelfType.SINGLE,
    contentTypes: [ShelfContentType.MANGA],
    icon: '📚',
    color: '#FF6B6B',
    order: 0,
    isSystem: true,
    createTime: 0,
    updateTime: 0
  },
  {
    id: 'system_ebook',
    name: '电子书书架',
    shelfType: ShelfType.SINGLE,
    contentTypes: [ShelfContentType.EBOOK],
    icon: '📖',
    color: '#4ECDC4',
    order: 1,
    isSystem: true,
    createTime: 0,
    updateTime: 0
  },
  {
    id: 'system_novel',
    name: '小说书架',
    shelfType: ShelfType.SINGLE,
    contentTypes: [ShelfContentType.NOVEL],
    icon: '📝',
    color: '#45B7D1',
    order: 2,
    isSystem: true,
    createTime: 0,
    updateTime: 0
  }
];

/**
 * 预设书架颜色
 */
export const SHELF_COLORS: string[] = [
  '#FF6B6B', // 珊瑚红
  '#4ECDC4', // 青绿
  '#45B7D1', // 天蓝
  '#96CEB4', // 薄荷绿
  '#FFEAA7', // 柠檬黄
  '#DDA0DD', // 梅子紫
  '#98D8C8', // 湖水绿
  '#F7DC6F', // 向日葵黄
  '#BB8FCE', // 薰衣草紫
  '#85C1E9', // 晴空蓝
  '#F8B500', // 琥珀橙
  '#E74C3C'  // 石榴红
];

/**
 * 预设书架图标
 */
export const SHELF_ICONS: string[] = [
  '📚', '📖', '📝', '📕', '📗', '📘', '📙',
  '🎨', '🎬', '🎮', '🎵', '💡', '⭐', '❤️',
  '🔥', '✨', '🌟', '🌈', '🍀', '🌸', '🎯'
];

/**
 * 类型书架管理器
 */
export class TypeShelfManager {
  private static instance: TypeShelfManager | null = null;
  private settingsManager: SettingsManager;
  private categoryManager: BookshelfCategoryManager;
  private shelves: TypeShelf[] = [];
  private initialized: boolean = false;

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
    this.categoryManager = BookshelfCategoryManager.getInstance();
  }

  static getInstance(): TypeShelfManager {
    if (!TypeShelfManager.instance) {
      TypeShelfManager.instance = new TypeShelfManager();
    }
    return TypeShelfManager.instance;
  }

  /**
   * 复制书架对象（避免使用spread语法）
   */
  private copyShelfWithTimestamp(shelf: TypeShelf): TypeShelf {
    const result: TypeShelf = {
      id: shelf.id,
      name: shelf.name,
      shelfType: shelf.shelfType,
      contentTypes: shelf.contentTypes.slice(),
      icon: shelf.icon,
      color: shelf.color,
      order: shelf.order,
      isSystem: shelf.isSystem,
      createTime: Date.now(),
      updateTime: Date.now()
    };
    if (shelf.dynamicFilter) {
      result.dynamicFilter = {
        authors: shelf.dynamicFilter.authors.slice(),
        tags: shelf.dynamicFilter.tags.slice(),
        titleKeywords: shelf.dynamicFilter.titleKeywords.slice(),
        sourceNames: shelf.dynamicFilter.sourceNames.slice(),
        customKeywords: shelf.dynamicFilter.customKeywords.slice(),
        nsfwFilter: shelf.dynamicFilter.nsfwFilter
      };
    }
    return result;
  }

  /**
   * 初始化管理器
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      // 加载书架列表
      const shelvesJson: string = this.settingsManager.getString(TYPE_SHELVES_KEY, '');
      
      if (shelvesJson && shelvesJson.length > 0) {
        this.shelves = JSON.parse(shelvesJson) as TypeShelf[];
        logger.info(TAG, `加载了 ${this.shelves.length} 个书架`);
      } else {
        // 首次使用，创建默认系统书架
        this.shelves = [];
        for (const shelf of DEFAULT_SYSTEM_SHELVES) {
          this.shelves.push(this.copyShelfWithTimestamp(shelf));
        }
        await this.saveShelves();
        logger.info(TAG, '创建了默认系统书架');
      }

      // 确保系统书架存在
      this.ensureSystemShelves();

      this.initialized = true;
      logger.info(TAG, `初始化完成，共 ${this.shelves.length} 个书架`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      // 创建默认书架
      this.shelves = [];
      for (const shelf of DEFAULT_SYSTEM_SHELVES) {
        this.shelves.push(this.copyShelfWithTimestamp(shelf));
      }
      this.initialized = true;
    }
  }

  /**
   * 确保系统书架存在
   */
  private ensureSystemShelves(): void {
    for (const defaultShelf of DEFAULT_SYSTEM_SHELVES) {
      const exists = this.shelves.some(s => s.id === defaultShelf.id);
      if (!exists) {
        this.shelves.push(this.copyShelfWithTimestamp(defaultShelf));
      }
    }
  }

  /**
   * 保存书架列表
   */
  private async saveShelves(): Promise<void> {
    try {
      if (!this.settingsManager.isInitialized()) {
        logger.warn(TAG, '跳过保存书架：SettingsManager未初始化');
        return;
      }
      await this.settingsManager.setString(TYPE_SHELVES_KEY, JSON.stringify(this.shelves));
      logger.debug(TAG, `保存了 ${this.shelves.length} 个书架`);
    } catch (error) {
      logger.error(TAG, `保存书架失败: ${error}`);
    }
  }

  /**
   * 获取所有书架（按order排序）
   */
  getShelves(): TypeShelf[] {
    return this.shelves.slice().sort((a, b) => a.order - b.order);
  }

  /**
   * 获取可见书架（根据内容数量过滤）
   * @param mangaCount 漫画数量
   * @param ebookCount 电子书数量
   * @param novelCount 小说数量
   */
  getVisibleShelves(mangaCount: number, ebookCount: number, novelCount: number): TypeShelf[] {
    return this.getShelves().filter(shelf => {
      // 自定义书架始终显示
      if (!shelf.isSystem) {
        return true;
      }
      // 系统书架根据内容数量决定是否显示
      if (shelf.contentTypes.includes(ShelfContentType.MANGA) && mangaCount > 0) {
        return true;
      }
      if (shelf.contentTypes.includes(ShelfContentType.EBOOK) && ebookCount > 0) {
        return true;
      }
      if (shelf.contentTypes.includes(ShelfContentType.NOVEL) && novelCount > 0) {
        return true;
      }
      return false;
    });
  }

  /**
   * 获取书架
   */
  getShelf(shelfId: string): TypeShelf | undefined {
    return this.shelves.find(s => s.id === shelfId);
  }

  /**
   * 创建新书架
   * 同时在BookshelfCategoryManager中创建对应的分类
   */
  async createShelf(params: CreateShelfParams): Promise<TypeShelf> {
    const maxOrder = this.shelves.reduce((max, s) => Math.max(max, s.order), 0);
    const now = Date.now();
    const shelfId = `shelf_${now}`;
    
    const newShelf: TypeShelf = {
      id: shelfId,
      name: params.name,
      shelfType: params.shelfType,
      contentTypes: params.contentTypes,
      icon: params.icon || '📚',
      color: params.color || SHELF_COLORS[0],
      order: maxOrder + 1,
      isSystem: false,
      createTime: now,
      updateTime: now
    };
    if (params.dynamicFilter) {
      newShelf.dynamicFilter = {
        authors: params.dynamicFilter.authors.slice(),
        tags: params.dynamicFilter.tags.slice(),
        titleKeywords: params.dynamicFilter.titleKeywords.slice(),
        sourceNames: params.dynamicFilter.sourceNames.slice(),
        customKeywords: params.dynamicFilter.customKeywords.slice(),
        nsfwFilter: params.dynamicFilter.nsfwFilter
      };
    }

    this.shelves.push(newShelf);
    await this.saveShelves();
    
    // 动态书架不需要创建BookshelfCategory映射（实时计算）
    if (params.shelfType !== ShelfType.DYNAMIC) {
      // 同步创建BookshelfCategory（用于内容映射）
      await this.categoryManager.createCategoryWithId(shelfId, params.name);
    }
    
    logger.info(TAG, `创建书架: ${newShelf.name}, 类型: ${newShelf.shelfType}`);
    return newShelf;
  }

  /**
   * 更新书架
   */
  async updateShelf(shelfId: string, updates: Partial<TypeShelf>): Promise<boolean> {
    const shelf = this.shelves.find(s => s.id === shelfId);
    if (!shelf) {
      return false;
    }

    // 系统书架不允许修改某些属性
    if (shelf.isSystem) {
      // 只允许修改名称和颜色
      if (updates.name !== undefined) shelf.name = updates.name;
      if (updates.color !== undefined) shelf.color = updates.color;
      if (updates.icon !== undefined) shelf.icon = updates.icon;
    } else {
      // 自定义书架可以修改所有属性（手动赋值避免Object.assign）
      if (updates.name !== undefined) shelf.name = updates.name;
      if (updates.shelfType !== undefined) shelf.shelfType = updates.shelfType;
      if (updates.contentTypes !== undefined) shelf.contentTypes = updates.contentTypes;
      if (updates.icon !== undefined) shelf.icon = updates.icon;
      if (updates.color !== undefined) shelf.color = updates.color;
      if (updates.order !== undefined) shelf.order = updates.order;
      if (updates.dynamicFilter !== undefined) shelf.dynamicFilter = updates.dynamicFilter;
    }

    shelf.updateTime = Date.now();
    await this.saveShelves();
    logger.info(TAG, `更新书架: ${shelf.name}`);
    return true;
  }

  /**
   * 删除书架
   * 同时删除BookshelfCategoryManager中的对应分类（内容移动到默认分类）
   */
  async deleteShelf(shelfId: string): Promise<boolean> {
    const shelf = this.shelves.find(s => s.id === shelfId);
    if (!shelf || shelf.isSystem) {
      logger.warn(TAG, `无法删除书架: ${shelfId} (不存在或为系统书架)`);
      return false;
    }

    this.shelves = this.shelves.filter(s => s.id !== shelfId);
    await this.saveShelves();
    
    // 同步删除BookshelfCategory（内容会移动到默认分类）
    await this.categoryManager.deleteCategory(shelfId);
    
    logger.info(TAG, `删除书架: ${shelf.name}`);
    return true;
  }

  /**
   * 重新排序书架
   */
  async reorderShelves(shelves: TypeShelf[]): Promise<void> {
    this.shelves = shelves;
    this.shelves.forEach((shelf, index) => {
      shelf.order = index;
    });
    await this.saveShelves();
    logger.info(TAG, `重新排序书架，共 ${shelves.length} 个`);
  }

  /**
   * 获取书架内容数量
   */
  getShelfItemCount(shelf: TypeShelf, mangaCount: number, ebookCount: number, novelCount: number): number {
    let count = 0;
    if (shelf.contentTypes.includes(ShelfContentType.MANGA)) {
      count += mangaCount;
    }
    if (shelf.contentTypes.includes(ShelfContentType.EBOOK)) {
      count += ebookCount;
    }
    if (shelf.contentTypes.includes(ShelfContentType.NOVEL)) {
      count += novelCount;
    }
    return count;
  }

  /**
   * 检查书架是否包含指定内容类型
   */
  shelfContainsType(shelf: TypeShelf, contentType: ShelfContentType): boolean {
    return shelf.contentTypes.includes(contentType);
  }

  /**
   * 获取书架中的内容项列表
   */
  getShelfItems(shelfId: string): CategoryItem[] {
    return this.categoryManager.getCategoryItems(shelfId);
  }

  /**
   * 获取书架中指定类型的内容ID列表
   */
  getShelfItemIdsByType(shelfId: string, contentType: ContentType): string[] {
    return this.categoryManager.getCategoryItemsByType(shelfId, contentType);
  }

  /**
   * 获取书架中的实际内容数量
   */
  getShelfRealItemCount(shelfId: string): number {
    return this.categoryManager.getCategoryItems(shelfId).length;
  }

  /**
   * 将内容移动到书架
   */
  async moveItemToShelf(itemId: string, contentType: ContentType, shelfId: string): Promise<void> {
    // 检查书架是否存在且支持该内容类型
    const shelf = this.getShelf(shelfId);
    if (!shelf) {
      logger.warn(TAG, `书架不存在: ${shelfId}`);
      return;
    }
    
    // 检查内容类型是否匹配
    const shelfContentType = this.contentTypeToShelfContentType(contentType);
    if (!shelf.contentTypes.includes(shelfContentType)) {
      logger.warn(TAG, `书架 ${shelf.name} 不支持该内容类型: ${contentType}`);
      return;
    }
    
    await this.categoryManager.moveItemToCategory(itemId, contentType, shelfId);
    logger.info(TAG, `将 ${itemId} 移动到书架 ${shelf.name}`);
  }

  /**
   * 批量移动内容到书架
   */
  async moveItemsToShelf(items: MoveToShelfItemInfo[], shelfId: string): Promise<void> {
    const shelf = this.getShelf(shelfId);
    if (!shelf) {
      logger.warn(TAG, `书架不存在: ${shelfId}`);
      return;
    }
    
    for (const item of items) {
      const shelfContentType = this.contentTypeToShelfContentType(item.contentType);
      if (shelf.contentTypes.includes(shelfContentType)) {
        await this.categoryManager.moveItemToCategory(item.itemId, item.contentType, shelfId);
      }
    }
    logger.info(TAG, `批量移动 ${items.length} 个内容到书架 ${shelf.name}`);
  }

  /**
   * 获取内容所属的书架ID
   */
  getItemShelfId(itemId: string, contentType: ContentType): string {
    return this.categoryManager.getItemCategory(itemId, contentType);
  }

  /**
   * 检查内容是否在指定书架中
   */
  isItemInShelf(itemId: string, contentType: ContentType, shelfId: string): boolean {
    return this.categoryManager.isItemInCategory(itemId, contentType, shelfId);
  }

  /**
   * 将内容从ContentType转换为ShelfContentType
   */
  private contentTypeToShelfContentType(contentType: ContentType): ShelfContentType {
    switch (contentType) {
      case ContentType.MANGA:
        return ShelfContentType.MANGA;
      case ContentType.EBOOK:
        return ShelfContentType.EBOOK;
      case ContentType.NOVEL:
        return ShelfContentType.NOVEL;
      default:
        return ShelfContentType.MANGA;
    }
  }

  /**
   * 将ShelfContentType转换为ContentType
   */
  shelfContentTypeToContentType(shelfContentType: ShelfContentType): ContentType {
    switch (shelfContentType) {
      case ShelfContentType.MANGA:
        return ContentType.MANGA;
      case ShelfContentType.EBOOK:
        return ContentType.EBOOK;
      case ShelfContentType.NOVEL:
        return ContentType.NOVEL;
      default:
        return ContentType.MANGA;
    }
  }

  /**
   * 获取可以接受指定内容类型的书架列表
   */
  getShelvesForContentType(contentType: ContentType): TypeShelf[] {
    const shelfContentType = this.contentTypeToShelfContentType(contentType);
    return this.getShelves().filter(shelf => 
      !shelf.isSystem && shelf.contentTypes.includes(shelfContentType)
    );
  }

  /**
   * 获取BookshelfCategoryManager实例（用于封面管理等）
   */
  getCategoryManager(): BookshelfCategoryManager {
    return this.categoryManager;
  }

  /**
   * 获取所有动态书架
   */
  getDynamicShelves(): TypeShelf[] {
    return this.shelves.filter(s => s.shelfType === ShelfType.DYNAMIC);
  }
}

// ==================== 动态书架工具函数 ====================

/**
 * 多语言智能分词
 * 兼容中文、英语、日语、韩语四种常用语言
 * @param text 输入文本
 * @returns 分词结果（去重、去除过短token）
 */
export function smartTokenize(text: string): string[] {
  if (!text || text.trim().length === 0) {
    return [];
  }

  const tokens: string[] = [];
  const normalized = text.trim();

  // 按不同语言字符块拆分
  // 正则匹配：连续中文CJK字符块、连续日文假名块、连续韩文块、连续拉丁/数字块
  const blockPattern = /[\u4e00-\u9fff\u3400-\u4dbf]+|[\u3040-\u309f\u30a0-\u30ff]+|[\uac00-\ud7af]+|[a-zA-Z0-9]+/g;
  const blocks = normalized.match(blockPattern);
  if (!blocks) {
    return [];
  }

  for (const block of blocks) {
    const firstChar = block.charCodeAt(0);

    // 中文CJK字符块：生成单字和2-3字组合
    if ((firstChar >= 0x4e00 && firstChar <= 0x9fff) || (firstChar >= 0x3400 && firstChar <= 0x4dbf)) {
      // 整块作为一个token
      if (block.length >= 2) {
        tokens.push(block);
      }
      // 2字组合
      for (let i = 0; i < block.length - 1; i++) {
        tokens.push(block.substring(i, i + 2));
      }
      // 3字组合
      for (let i = 0; i < block.length - 2; i++) {
        tokens.push(block.substring(i, i + 3));
      }
      // 单字（仅当不是太常见的单字时保留）
      for (let i = 0; i < block.length; i++) {
        tokens.push(block.charAt(i));
      }
    }
    // 日文假名块：整块作为token
    else if ((firstChar >= 0x3040 && firstChar <= 0x309f) || (firstChar >= 0x30a0 && firstChar <= 0x30ff)) {
      if (block.length >= 2) {
        tokens.push(block);
      }
      // 2-3字假名组合
      for (let i = 0; i < block.length - 1; i++) {
        tokens.push(block.substring(i, i + 2));
      }
      for (let i = 0; i < block.length - 2; i++) {
        tokens.push(block.substring(i, i + 3));
      }
    }
    // 韩文块：整块和2-3字组合
    else if (firstChar >= 0xac00 && firstChar <= 0xd7af) {
      if (block.length >= 2) {
        tokens.push(block);
      }
      for (let i = 0; i < block.length - 1; i++) {
        tokens.push(block.substring(i, i + 2));
      }
      for (let i = 0; i < block.length - 2; i++) {
        tokens.push(block.substring(i, i + 3));
      }
    }
    // 英文/拉丁块：按驼峰拆分
    else {
      // 整词
      if (block.length >= 2) {
        tokens.push(block.toLowerCase());
      }
      // 驼峰拆分 (e.g. "OnePiece" -> ["One", "Piece"])
      const camelParts = block.replace(/([a-z])([A-Z])/g, '$1 $2').split(' ');
      for (const part of camelParts) {
        if (part.length >= 2) {
          tokens.push(part.toLowerCase());
        }
      }
    }
  }

  // 去重并过滤过短的token（少于2个字符的英文，少于1个字符的CJK）
  const seen = new Set<string>();
  const result: string[] = [];
  for (const token of tokens) {
    if (!seen.has(token) && token.length >= 1) {
      seen.add(token);
      result.push(token);
    }
  }

  return result;
}

/**
 * 动态书架内容匹配信息接口
 * 用于传入匹配检查方法
 */
export interface DynamicMatchItem {
  title: string;
  authors: string[];
  tags: string[];
  sourceName: string;
  isNSFW?: boolean;  // 是否为NSFW内容
}

/**
 * 检查内容是否匹配动态书架的筛选条件
 * 匹配逻辑：OR关系，满足任一条件即匹配
 * - 作者在筛选列表中
 * - 标签与筛选标签有交集
 * - 标题包含筛选关键词
 * - 来源名称在筛选列表中
 * - 标题/标签/作者包含自定义关键词
 */
export function matchesDynamicFilter(item: DynamicMatchItem, filter: DynamicShelfFilter): boolean {
  // 没有任何筛选条件，不匹配
  const hasNsfwFilter = filter.nsfwFilter !== undefined && filter.nsfwFilter !== 'all';
  if (filter.authors.length === 0 && filter.tags.length === 0 &&
    filter.titleKeywords.length === 0 && filter.sourceNames.length === 0 &&
    filter.customKeywords.length === 0 && !hasNsfwFilter) {
    return false;
  }

  // NSFW/SFW 内容分级过滤（AND逻辑：必须满足分级要求）
  if (hasNsfwFilter) {
    if (filter.nsfwFilter === 'nsfw' && item.isNSFW !== true) {
      return false; // 要求NSFW但内容不是NSFW
    }
    if (filter.nsfwFilter === 'sfw' && item.isNSFW === true) {
      return false; // 要求SFW但内容是NSFW
    }
    // 如果没有其他筛选条件，仅凭NSFW过滤即可匹配
    if (filter.authors.length === 0 && filter.tags.length === 0 &&
      filter.titleKeywords.length === 0 && filter.sourceNames.length === 0 &&
      filter.customKeywords.length === 0) {
      return true;
    }
  }

  // 作者匹配
  if (filter.authors.length > 0) {
    for (const author of item.authors) {
      if (filter.authors.includes(author)) {
        return true;
      }
    }
  }

  // 标签匹配
  if (filter.tags.length > 0) {
    for (const tag of item.tags) {
      if (filter.tags.includes(tag)) {
        return true;
      }
    }
  }

  // 标题关键词匹配
  if (filter.titleKeywords.length > 0) {
    const titleLower = item.title.toLowerCase();
    for (const keyword of filter.titleKeywords) {
      if (titleLower.includes(keyword.toLowerCase())) {
        return true;
      }
    }
  }

  // 来源名称匹配
  if (filter.sourceNames.length > 0 && item.sourceName) {
    if (filter.sourceNames.includes(item.sourceName)) {
      return true;
    }
  }

  // 自定义关键词匹配（在标题、作者、标签中搜索）
  if (filter.customKeywords.length > 0) {
    const searchText = [item.title, ...item.authors, ...item.tags].join(' ').toLowerCase();
    for (const keyword of filter.customKeywords) {
      if (searchText.includes(keyword.toLowerCase())) {
        return true;
      }
    }
  }

  return false;
}

/**
 * 获取TypeShelfManager单例
 */
export function getTypeShelfManager(): TypeShelfManager {
  return TypeShelfManager.getInstance();
}
