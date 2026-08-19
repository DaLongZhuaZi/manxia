import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 分类书架管理器
 * 类似iOS App Library的分类视图功能
 */
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from '../Managers/SettingsManager';

const TAG = 'BookshelfCategoryManager';
const CATEGORIES_KEY = 'bookshelf_categories';
const ITEM_CATEGORY_MAP_KEY = 'bookshelf_item_category_map';

/**
 * 内容类型枚举
 */
export enum ContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

/**
 * 分类书架接口
 */
export interface BookshelfCategory {
  id: string;                    // 唯一标识
  name: string;                  // 分类名称
  order: number;                 // 排序顺序
  isDefault: boolean;            // 是否为默认分类
  coverImages: string[];         // 封面图片列表（最多显示4个）
  itemCount: number;             // 内容数量
  createTime: number;            // 创建时间
  updateTime: number;            // 更新时间
}

/**
 * 分类内容项
 */
export interface CategoryItem {
  itemId: string;                // 内容ID（漫画ID、电子书ID或小说ID）
  contentType: ContentType;      // 内容类型
  categoryId: string;            // 所属分类ID
  addTime: number;               // 添加时间
}

/**
 * 批量移动内容项信息
 */
export interface MoveItemInfo {
  itemId: string;
  contentType: ContentType;
}

/**
 * 分类书架管理器
 */
export class BookshelfCategoryManager {
  private static instance: BookshelfCategoryManager | null = null;
  private settingsManager: SettingsManager;
  private categories: BookshelfCategory[] = [];
  private itemCategoryMap: Map<string, CategoryItem> = new Map(); // key: contentType_itemId
  private initialized: boolean = false;

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
  }

  static getInstance(): BookshelfCategoryManager {
    if (!BookshelfCategoryManager.instance) {
      BookshelfCategoryManager.instance = new BookshelfCategoryManager();
    }
    return BookshelfCategoryManager.instance;
  }

  /**
   * 初始化管理器
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      // 加载分类列表
      const categoriesJson: string = this.settingsManager.getString(CATEGORIES_KEY, '[]');
      this.categories = SafeUtils.parseArr(categoriesJson) as BookshelfCategory[];

      // 加载内容-分类映射
      const mapJson: string = this.settingsManager.getString(ITEM_CATEGORY_MAP_KEY, '{}');
      const mapObj: Record<string, CategoryItem> = SafeUtils.parseObj(mapJson) as Record<string, CategoryItem>;
      this.itemCategoryMap = new Map(Object.entries(mapObj));

      // 确保有默认分类
      if (!this.categories.some(c => c.isDefault)) {
        await this.createDefaultCategory();
      }

      this.initialized = true;
      logger.info(TAG, `初始化完成，共 ${this.categories.length} 个分类`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      // 创建默认分类
      await this.createDefaultCategory();
      this.initialized = true;
    }
  }

  /**
   * 创建默认分类
   */
  private async createDefaultCategory(): Promise<void> {
    const defaultCategory: BookshelfCategory = {
      id: 'default',
      name: '默认书架',
      order: 0,
      isDefault: true,
      coverImages: [],
      itemCount: 0,
      createTime: Date.now(),
      updateTime: Date.now()
    };
    this.categories = [defaultCategory];
    await this.saveCategories();
  }

  /**
   * 保存分类列表
   */
  private async saveCategories(): Promise<void> {
    try {
      // 检查SettingsManager是否已初始化
      if (!this.settingsManager.isInitialized()) {
        logger.warn(TAG, '跳过保存分类：SettingsManager未初始化');
        return;
      }
      await this.settingsManager.setString(CATEGORIES_KEY, JSON.stringify(this.categories));
    } catch (error) {
      logger.error(TAG, `保存分类失败: ${error}`);
    }
  }

  /**
   * 保存内容-分类映射
   */
  private async saveItemCategoryMap(): Promise<void> {
    try {
      // 检查SettingsManager是否已初始化
      if (!this.settingsManager.isInitialized()) {
        logger.warn(TAG, '跳过保存映射：SettingsManager未初始化');
        return;
      }
      const mapObj: Record<string, CategoryItem> = {};
      this.itemCategoryMap.forEach((value, key) => {
        mapObj[key] = value;
      });
      await this.settingsManager.setString(ITEM_CATEGORY_MAP_KEY, JSON.stringify(mapObj));
    } catch (error) {
      logger.error(TAG, `保存映射失败: ${error}`);
    }
  }

  /**
   * 获取所有分类
   */
  getCategories(): BookshelfCategory[] {
    return this.categories.slice().sort((a, b) => a.order - b.order);
  }

  /**
   * 获取分类
   */
  getCategory(categoryId: string): BookshelfCategory | undefined {
    return this.categories.find(c => c.id === categoryId);
  }

  /**
   * 获取默认分类
   */
  getDefaultCategory(): BookshelfCategory | undefined {
    return this.categories.find(c => c.isDefault);
  }

  /**
   * 创建新分类
   */
  async createCategory(name: string): Promise<BookshelfCategory> {
    const maxOrder = this.categories.reduce((max, c) => Math.max(max, c.order), 0);
    const newCategory: BookshelfCategory = {
      id: `category_${Date.now()}`,
      name: name,
      order: maxOrder + 1,
      isDefault: false,
      coverImages: [],
      itemCount: 0,
      createTime: Date.now(),
      updateTime: Date.now()
    };
    this.categories.push(newCategory);
    await this.saveCategories();
    logger.info(TAG, `创建分类: ${name}`);
    return newCategory;
  }

  /**
   * 使用指定ID创建新分类（用于TypeShelfManager集成）
   */
  async createCategoryWithId(id: string, name: string): Promise<BookshelfCategory> {
    // 检查是否已存在
    if (this.categories.some(c => c.id === id)) {
      logger.warn(TAG, `分类已存在: ${id}`);
      const existing = this.categories.find(c => c.id === id);
      if (existing) {
        return existing;
      }
    }
    
    const maxOrder = this.categories.reduce((max, c) => Math.max(max, c.order), 0);
    const newCategory: BookshelfCategory = {
      id: id,
      name: name,
      order: maxOrder + 1,
      isDefault: false,
      coverImages: [],
      itemCount: 0,
      createTime: Date.now(),
      updateTime: Date.now()
    };
    this.categories.push(newCategory);
    await this.saveCategories();
    logger.info(TAG, `创建分类(ID: ${id}): ${name}`);
    return newCategory;
  }

  /**
   * 更新分类名称
   */
  async updateCategoryName(categoryId: string, newName: string): Promise<boolean> {
    const category = this.categories.find(c => c.id === categoryId);
    if (category) {
      category.name = newName;
      category.updateTime = Date.now();
      await this.saveCategories();
      logger.info(TAG, `更新分类名称: ${newName}`);
      return true;
    }
    return false;
  }

  /**
   * 删除分类（内容移动到默认分类）
   */
  async deleteCategory(categoryId: string): Promise<boolean> {
    const category = this.categories.find(c => c.id === categoryId);
    if (!category || category.isDefault) {
      return false;
    }

    // 将该分类的所有内容移动到默认分类
    const defaultCategory = this.getDefaultCategory();
    if (defaultCategory) {
      this.itemCategoryMap.forEach((item, key) => {
        if (item.categoryId === categoryId) {
          item.categoryId = defaultCategory.id;
        }
      });
      await this.saveItemCategoryMap();
      await this.updateCategoryCounts();
    }

    // 删除分类
    this.categories = this.categories.filter(c => c.id !== categoryId);
    await this.saveCategories();
    logger.info(TAG, `删除分类: ${category.name}`);
    return true;
  }



  /**
   * 获取内容所属分类
   */
  getItemCategory(itemId: string, contentType: ContentType): string {
    const key = `${contentType}_${itemId}`;
    const item = this.itemCategoryMap.get(key);
    return item?.categoryId || 'default';
  }

  /**
   * 将内容移动到分类
   */
  async moveItemToCategory(itemId: string, contentType: ContentType, categoryId: string): Promise<void> {
    const key = `${contentType}_${itemId}`;
    const existingItem = this.itemCategoryMap.get(key);
    
    if (existingItem) {
      existingItem.categoryId = categoryId;
    } else {
      const newItem: CategoryItem = {
        itemId: itemId,
        contentType: contentType,
        categoryId: categoryId,
        addTime: Date.now()
      };
      this.itemCategoryMap.set(key, newItem);
    }

    await this.saveItemCategoryMap();
    await this.updateCategoryCounts();
    logger.info(TAG, `移动内容到分类: ${itemId} -> ${categoryId}`);
  }

  /**
   * 批量移动内容到分类
   */
  async moveItemsToCategory(items: MoveItemInfo[], categoryId: string): Promise<void> {
    for (const item of items) {
      const key = `${item.contentType}_${item.itemId}`;
      const existingItem = this.itemCategoryMap.get(key);
      
      if (existingItem) {
        existingItem.categoryId = categoryId;
      } else {
        const newItem: CategoryItem = {
          itemId: item.itemId,
          contentType: item.contentType,
          categoryId: categoryId,
          addTime: Date.now()
        };
        this.itemCategoryMap.set(key, newItem);
      }
    }

    await this.saveItemCategoryMap();
    await this.updateCategoryCounts();
    logger.info(TAG, `批量移动 ${items.length} 个内容到分类: ${categoryId}`);
  }

  /**
   * 获取分类中的所有内容ID
   */
  getCategoryItems(categoryId: string): CategoryItem[] {
    const items: CategoryItem[] = [];
    this.itemCategoryMap.forEach((item) => {
      if (item.categoryId === categoryId) {
        items.push(item);
      }
    });
    return items;
  }

  /**
   * 获取分类中指定类型的内容ID
   */
  getCategoryItemsByType(categoryId: string, contentType: ContentType): string[] {
    const itemIds: string[] = [];
    this.itemCategoryMap.forEach((item) => {
      if (item.categoryId === categoryId && item.contentType === contentType) {
        itemIds.push(item.itemId);
      }
    });
    return itemIds;
  }

  /**
   * 更新分类的封面图片
   */
  async updateCategoryCovers(categoryId: string, coverImages: string[]): Promise<void> {
    const category = this.categories.find(c => c.id === categoryId);
    if (category) {
      category.coverImages = coverImages.slice(0, 4); // 最多4张
      category.updateTime = Date.now();
      await this.saveCategories();
    }
  }

  /**
   * 更新所有分类的内容数量
   */
  async updateCategoryCounts(): Promise<void> {
    // 重置所有分类的计数
    this.categories.forEach(c => {
      c.itemCount = 0;
    });

    // 统计每个分类的内容数量
    this.itemCategoryMap.forEach((item) => {
      const category = this.categories.find(c => c.id === item.categoryId);
      if (category) {
        category.itemCount++;
      }
    });

    await this.saveCategories();
  }

  /**
   * 从分类中移除内容
   */
  async removeItemFromCategory(itemId: string, contentType: ContentType): Promise<void> {
    const key = `${contentType}_${itemId}`;
    this.itemCategoryMap.delete(key);
    await this.saveItemCategoryMap();
    await this.updateCategoryCounts();
  }

  /**
   * 检查内容是否在指定分类中
   */
  isItemInCategory(itemId: string, contentType: ContentType, categoryId: string): boolean {
    const key = `${contentType}_${itemId}`;
    const item = this.itemCategoryMap.get(key);
    return item?.categoryId === categoryId;
  }

  /**
   * 获取未分类的内容（属于默认分类或未设置分类）
   */
  getUncategorizedItemKey(itemId: string, contentType: ContentType): boolean {
    const key = `${contentType}_${itemId}`;
    const item = this.itemCategoryMap.get(key);
    return !item || item.categoryId === 'default';
  }

  /**
   * 自动更新分类封面（使用分类中前4个内容的封面）
   * @param categoryId 分类ID
   * @param coverPaths 封面路径数组（按添加顺序）
   */
  async autoUpdateCategoryCovers(categoryId: string, coverPaths: string[]): Promise<void> {
    const category = this.categories.find(c => c.id === categoryId);
    if (category) {
      // 取前4个有效封面
      const validCovers = coverPaths.filter(p => p && p.length > 0).slice(0, 4);
      category.coverImages = validCovers;
      category.updateTime = Date.now();
      await this.saveCategories();
      logger.info(TAG, `更新分类 ${categoryId} 封面: ${validCovers.length} 张`);
    }
  }

  /**
   * 获取分类中所有内容的ID列表（按添加时间排序）
   */
  getCategoryItemsSorted(categoryId: string): CategoryItem[] {
    const items: CategoryItem[] = [];
    this.itemCategoryMap.forEach((item) => {
      if (item.categoryId === categoryId) {
        items.push(item);
      }
    });
    // 按添加时间排序
    return items.sort((a, b) => b.addTime - a.addTime);
  }

  /**
   * 交换两个分类的顺序
   */
  async swapCategoryOrder(categoryId1: string, categoryId2: string): Promise<void> {
    const cat1 = this.categories.find(c => c.id === categoryId1);
    const cat2 = this.categories.find(c => c.id === categoryId2);
    if (cat1 && cat2) {
      const tempOrder = cat1.order;
      cat1.order = cat2.order;
      cat2.order = tempOrder;
      await this.saveCategories();
      logger.info(TAG, `交换分类顺序: ${categoryId1} <-> ${categoryId2}`);
    }
  }

  /**
   * 移动分类到指定位置
   */
  async moveCategoryToPosition(categoryId: string, newPosition: number): Promise<void> {
    const category = this.categories.find(c => c.id === categoryId);
    if (!category) return;

    const oldPosition = category.order;
    if (oldPosition === newPosition) return;

    // 更新其他分类的顺序
    this.categories.forEach(c => {
      if (c.id === categoryId) {
        c.order = newPosition;
      } else if (oldPosition < newPosition) {
        // 向后移动：中间的分类向前移
        if (c.order > oldPosition && c.order <= newPosition) {
          c.order--;
        }
      } else {
        // 向前移动：中间的分类向后移
        if (c.order >= newPosition && c.order < oldPosition) {
          c.order++;
        }
      }
    });

    await this.saveCategories();
    logger.info(TAG, `移动分类 ${categoryId} 到位置 ${newPosition}`);
  }

  /**
   * 重新排序分类（用于拖动排序后保存）
   */
  async reorderCategories(categories: BookshelfCategory[]): Promise<void> {
    this.categories = categories;
    await this.saveCategories();
    logger.info(TAG, `重新排序分类，共 ${categories.length} 个`);
  }

  /**
   * 清理孤立的书架映射记录
   * 删除那些在映射中存在但实际内容已不存在的记录
   * @param validMangaIds 有效的漫画ID列表
   * @param validEbookIds 有效的电子书ID列表
   * @param validNovelIds 有效的小说ID列表
   * @returns 清理的记录数
   */
  async cleanupOrphanedMappings(
    validMangaIds: string[],
    validEbookIds: string[],
    validNovelIds: string[]
  ): Promise<number> {
    const keysToDelete: string[] = [];
    
    this.itemCategoryMap.forEach((item, key) => {
      let isValid = false;
      
      switch (item.contentType) {
        case ContentType.MANGA:
          isValid = validMangaIds.includes(item.itemId);
          break;
        case ContentType.EBOOK:
          isValid = validEbookIds.includes(item.itemId);
          break;
        case ContentType.NOVEL:
          isValid = validNovelIds.includes(item.itemId);
          break;
      }
      
      if (!isValid) {
        keysToDelete.push(key);
        logger.info(TAG, `发现孤立映射: ${key}, contentType=${item.contentType}, itemId=${item.itemId}`);
      }
    });
    
    if (keysToDelete.length > 0) {
      for (const key of keysToDelete) {
        this.itemCategoryMap.delete(key);
      }
      await this.saveItemCategoryMap();
      await this.updateCategoryCounts();
      logger.info(TAG, `清理了 ${keysToDelete.length} 个孤立映射`);
    }
    
    return keysToDelete.length;
  }
}
