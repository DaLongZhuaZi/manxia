// 文件路径: entry/src/main/ets/Framework/Utils/PaginationHandler.ets
/**
 * 分页处理器
 * 支持offset、page、cursor三种分页方式
 */

import { logger } from '../../Utils/Logger';

const TAG = 'PaginationHandler';

/**
 * 分页类型
 */
export type PaginationType = 'offset' | 'page' | 'cursor';

/**
 * 分页配置
 */
export interface PaginationConfig {
  type: PaginationType;
  pageSize: number;
  maxPages?: number;
  
  // cursor分页特有
  cursorField?: string;
  hasMoreField?: string;
  initialCursor?: string | null;
}

/**
 * 分页结果
 */
export interface PaginationResult {
  hasMore: boolean;
  nextCursor?: string | null;
  nextOffset?: number;
  nextPage?: number;
  currentPage?: number;
  totalPages?: number;
}

/**
 * 分页状态
 */
export interface PaginationState {
  currentPage: number;
  currentOffset: number;
  currentCursor: string | null;
  hasMore: boolean;
  totalItems?: number;
}

/**
 * 分页处理器（单例）
 */
export class PaginationHandler {
  private static instance: PaginationHandler | null = null;
  
  // 存储各个源的分页状态
  private paginationStates: Map<string, PaginationState> = new Map();

  private constructor() {}

  static getInstance(): PaginationHandler {
    if (!PaginationHandler.instance) {
      PaginationHandler.instance = new PaginationHandler();
    }
    return PaginationHandler.instance;
  }

  /**
   * 初始化分页状态
   */
  initializePagination(sourceId: string, config: PaginationConfig): void {
    const state: PaginationState = {
      currentPage: 1,
      currentOffset: 0,
      currentCursor: config.initialCursor || null,
      hasMore: true
    };
    
    this.paginationStates.set(sourceId, state);
    logger.debug(TAG, `初始化分页状态: sourceId=${sourceId}, type=${config.type}`);
  }

  /**
   * 获取分页状态
   */
  getPaginationState(sourceId: string): PaginationState | null {
    return this.paginationStates.get(sourceId) || null;
  }

  /**
   * 处理offset分页
   */
  handleOffsetPagination(
    sourceId: string,
    config: PaginationConfig,
    itemsReceived?: number
  ): PaginationResult {
    const state = this.paginationStates.get(sourceId);
    if (!state) {
      logger.warn(TAG, `分页状态未初始化: ${sourceId}`);
      return {
        hasMore: false,
        nextOffset: 0,
        currentPage: 1
      };
    }

    const nextOffset = state.currentOffset + config.pageSize;
    const nextPage = state.currentPage + 1;
    
    // 判断是否还有更多数据
    let hasMore = true;
    
    // 方式1: 基于最大页数
    if (config.maxPages && nextPage > config.maxPages) {
      hasMore = false;
    }
    
    // 方式2: 基于返回的数据量
    if (itemsReceived !== undefined && itemsReceived < config.pageSize) {
      hasMore = false;
    }

    // 更新状态
    state.currentOffset = nextOffset;
    state.currentPage = nextPage;
    state.hasMore = hasMore;

    logger.debug(TAG, `Offset分页: page=${nextPage}, offset=${nextOffset}, hasMore=${hasMore}`);

    return {
      hasMore: hasMore,
      nextOffset: nextOffset,
      nextPage: nextPage,
      currentPage: state.currentPage
    };
  }

  /**
   * 处理page分页
   */
  handlePagePagination(
    sourceId: string,
    config: PaginationConfig,
    itemsReceived?: number
  ): PaginationResult {
    const state = this.paginationStates.get(sourceId);
    if (!state) {
      logger.warn(TAG, `分页状态未初始化: ${sourceId}`);
      return {
        hasMore: false,
        nextPage: 1,
        currentPage: 1
      };
    }

    const nextPage = state.currentPage + 1;
    
    // 判断是否还有更多数据
    let hasMore = true;
    
    // 方式1: 基于最大页数
    if (config.maxPages && nextPage > config.maxPages) {
      hasMore = false;
    }
    
    // 方式2: 基于返回的数据量
    if (itemsReceived !== undefined && itemsReceived < config.pageSize) {
      hasMore = false;
    }

    // 更新状态
    state.currentPage = nextPage;
    state.hasMore = hasMore;

    logger.debug(TAG, `Page分页: page=${nextPage}, hasMore=${hasMore}`);

    return {
      hasMore: hasMore,
      nextPage: nextPage,
      currentPage: state.currentPage
    };
  }

  /**
   * 处理cursor分页
   */
  handleCursorPagination(
    sourceId: string,
    response: any,
    config: PaginationConfig
  ): PaginationResult {
    const state = this.paginationStates.get(sourceId);
    if (!state) {
      logger.warn(TAG, `分页状态未初始化: ${sourceId}`);
      return {
        hasMore: false,
        nextCursor: null
      };
    }

    // 从响应中提取cursor和hasMore
    const nextCursor = this.extractField(response, config.cursorField || 'nextCursor');
    const hasMoreFromResponse = this.extractField(response, config.hasMoreField || 'hasMore');
    
    // 判断是否还有更多数据
    let hasMore = false;
    
    if (hasMoreFromResponse !== undefined) {
      hasMore = hasMoreFromResponse === true || hasMoreFromResponse === 'true';
    } else if (nextCursor !== null && nextCursor !== undefined && nextCursor !== '') {
      hasMore = true;
    }

    // 更新状态
    state.currentCursor = nextCursor;
    state.hasMore = hasMore;
    state.currentPage = state.currentPage + 1;

    logger.debug(TAG, `Cursor分页: cursor=${nextCursor}, hasMore=${hasMore}`);

    return {
      hasMore: hasMore,
      nextCursor: nextCursor,
      currentPage: state.currentPage
    };
  }

  /**
   * 从对象中提取字段值（支持嵌套路径）
   */
  private extractField(obj: any, path: string): any {
    if (!obj || !path) {
      return undefined;
    }

    const keys = path.split('.');
    let current = obj;

    for (const key of keys) {
      if (current && typeof current === 'object' && key in current) {
        current = current[key];
      } else {
        return undefined;
      }
    }

    return current;
  }

  /**
   * 重置分页状态
   */
  resetPagination(sourceId: string, config?: PaginationConfig): void {
    if (config) {
      this.initializePagination(sourceId, config);
    } else {
      this.paginationStates.delete(sourceId);
    }
    logger.debug(TAG, `重置分页状态: ${sourceId}`);
  }

  /**
   * 获取当前页码
   */
  getCurrentPage(sourceId: string): number {
    const state = this.paginationStates.get(sourceId);
    return state ? state.currentPage : 1;
  }

  /**
   * 获取当前offset
   */
  getCurrentOffset(sourceId: string): number {
    const state = this.paginationStates.get(sourceId);
    return state ? state.currentOffset : 0;
  }

  /**
   * 获取当前cursor
   */
  getCurrentCursor(sourceId: string): string | null {
    const state = this.paginationStates.get(sourceId);
    return state ? state.currentCursor : null;
  }

  /**
   * 是否还有更多数据
   */
  hasMoreData(sourceId: string): boolean {
    const state = this.paginationStates.get(sourceId);
    return state ? state.hasMore : false;
  }

  /**
   * 计算总页数（如果知道总条目数）
   */
  calculateTotalPages(totalItems: number, pageSize: number): number {
    return Math.ceil(totalItems / pageSize);
  }

  /**
   * 计算offset
   */
  calculateOffset(page: number, pageSize: number): number {
    return (page - 1) * pageSize;
  }

  /**
   * 从offset计算页码
   */
  calculatePageFromOffset(offset: number, pageSize: number): number {
    return Math.floor(offset / pageSize) + 1;
  }

  /**
   * 构建分页参数
   */
  buildPaginationParams(
    sourceId: string,
    config: PaginationConfig
  ): Record<string, string> {
    const state = this.paginationStates.get(sourceId);
    const params: Record<string, string> = {};

    if (!state) {
      return params;
    }

    switch (config.type) {
      case 'offset':
        params['offset'] = String(state.currentOffset);
        params['limit'] = String(config.pageSize);
        break;
      
      case 'page':
        params['page'] = String(state.currentPage);
        params['pageSize'] = String(config.pageSize);
        break;
      
      case 'cursor':
        if (state.currentCursor) {
          params['cursor'] = state.currentCursor;
        }
        params['limit'] = String(config.pageSize);
        break;
    }

    return params;
  }

  /**
   * 清除所有分页状态
   */
  clearAll(): void {
    this.paginationStates.clear();
    logger.info(TAG, '清除所有分页状态');
  }

  /**
   * 获取分页统计信息
   */
  getStatistics(sourceId: string): string {
    const state = this.paginationStates.get(sourceId);
    if (!state) {
      return '无分页状态';
    }

    return `Page: ${state.currentPage}, Offset: ${state.currentOffset}, Cursor: ${state.currentCursor || 'null'}, HasMore: ${state.hasMore}`;
  }
}

export default PaginationHandler;
