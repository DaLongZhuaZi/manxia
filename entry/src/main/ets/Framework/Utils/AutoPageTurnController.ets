
/**
 * 自动翻页控制器
 * 负责管理漫画的自动翻页功能
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'AutoPageTurnController';

/**
 * 自动翻页状态
 */
export enum AutoPageTurnState {
  STOPPED = 'STOPPED',
  RUNNING = 'RUNNING',
  PAUSED = 'PAUSED'
}

/**
 * 自动翻页配置
 */
export interface AutoPageTurnConfig {
  /** 翻页间隔（秒） */
  interval: number;
  /** 是否自动跳过前情提要 */
  skipIntro: boolean;
  /** 跳过的页数（从章节开头计数） */
  skipIntroPages: number;
  /** 是否在章节结束时自动切换到下一章 */
  autoSwitchChapter: boolean;
}

/**
 * 自动翻页控制器类
 */
export class AutoPageTurnController {
  private state: AutoPageTurnState = AutoPageTurnState.STOPPED;
  private config: AutoPageTurnConfig;
  private timer: number = -1;
  private onPageTurn: (() => void) | null = null;
  private getCurrentPageIndex: (() => number) | null = null;
  private getTotalPages: (() => number) | null = null;
  private onChapterEnd: (() => Promise<boolean> | boolean) | null = null;
  private isFirstPageOfChapter: boolean = true;
  private onPageTurnComplete: (() => void) | null = null;
  private isWaitingForPageTurn: boolean = false;

  constructor(config: AutoPageTurnConfig) {
    this.config = config;
  }

  /**
   * 设置配置
   */
  public setConfig(config: AutoPageTurnConfig): void {
    this.config = config;
    logger.debug(TAG, `更新配置: 间隔=${config.interval}s, 跳过前情=${config.skipIntro}, 跳过页数=${config.skipIntroPages}`);
    
    // 如果正在运行，重启定时器以应用新配置
    if (this.state === AutoPageTurnState.RUNNING) {
      this.stop();
      this.start();
    }
  }

  /**
   * 设置回调函数
   */
  public setCallbacks(
    onPageTurn: () => void,
    getCurrentPageIndex: () => number,
    getTotalPages: () => number
  ): void {
    this.onPageTurn = onPageTurn;
    this.getCurrentPageIndex = getCurrentPageIndex;
    this.getTotalPages = getTotalPages;
  }

  public setChapterEndCallback(callback: (() => Promise<boolean> | boolean) | null): void {
    this.onChapterEnd = callback;
  }

  /**
   * 通知新章节开始
   */
  public notifyNewChapter(): void {
    this.isFirstPageOfChapter = true;
    logger.debug(TAG, '新章节开始，标记为章节首页');
  }

  /**
   * 启动自动翻页
   */
  public start(): void {
    if (this.config.interval <= 0) {
      logger.warn(TAG, '自动翻页间隔为0，无法启动');
      return;
    }

    if (this.state === AutoPageTurnState.RUNNING) {
      logger.warn(TAG, '自动翻页已在运行中');
      return;
    }

    this.state = AutoPageTurnState.RUNNING;
    logger.info(TAG, `启动自动翻页，间隔=${this.config.interval}秒`);

    // 如果是章节首页且启用了跳过前情提要，先跳转
    if (this.isFirstPageOfChapter && this.config.skipIntro && this.config.skipIntroPages > 0) {
      this.skipIntroPages();
    }

    if (this.onPageTurnComplete) {
      logger.debug(TAG, '等待翻页完成回调以安排下一次翻页');
    } else {
      this.scheduleNextTurn();
    }
  }

  /**
   * 暂停自动翻页
   */
  public pause(): void {
    if (this.state !== AutoPageTurnState.RUNNING) {
      return;
    }

    this.state = AutoPageTurnState.PAUSED;
    this.clearTimer();
    logger.info(TAG, '自动翻页已暂停');
  }

  /**
   * 恢复自动翻页
   */
  public resume(): void {
    if (this.state !== AutoPageTurnState.PAUSED) {
      return;
    }

    this.state = AutoPageTurnState.RUNNING;
    logger.info(TAG, '恢复自动翻页');
    this.scheduleNextTurn();
  }

  /**
   * 停止自动翻页
   */
  public stop(): void {
    if (this.state === AutoPageTurnState.STOPPED) {
      return;
    }

    this.state = AutoPageTurnState.STOPPED;
    this.clearTimer();
    logger.info(TAG, '自动翻页已停止');
  }

  /**
   * 获取当前状态
   */
  public getState(): AutoPageTurnState {
    return this.state;
  }

  /**
   * 是否正在运行
   */
  public isRunning(): boolean {
    return this.state === AutoPageTurnState.RUNNING;
  }

  /**
   * 是否已暂停
   */
  public isPaused(): boolean {
    return this.state === AutoPageTurnState.PAUSED;
  }

  /**
   * 跳过前情提要页
   */
  private skipIntroPages(): void {
    if (!this.getCurrentPageIndex || !this.getTotalPages || !this.onPageTurn) {
      logger.error(TAG, '回调函数未设置，无法跳过前情提要');
      return;
    }

    const currentPage = this.getCurrentPageIndex();
    const totalPages = this.getTotalPages();
    const targetPage = Math.min(this.config.skipIntroPages, totalPages - 1);

    if (currentPage < targetPage) {
      logger.info(TAG, `跳过前情提要：从第${currentPage + 1}页跳转到第${targetPage + 1}页`);
      
      // 通过多次调用onPageTurn来快速翻页
      const pagesToSkip = targetPage - currentPage;
      for (let i = 0; i < pagesToSkip; i++) {
        this.onPageTurn();
      }
    }

    this.isFirstPageOfChapter = false;
  }

  /**
   * 安排下一次翻页
   */
  private scheduleNextTurn(): void {
    if (this.state !== AutoPageTurnState.RUNNING) {
      return;
    }

    this.clearTimer();

    const intervalMs = this.config.interval * 1000;
    this.timer = setTimeout(() => {
      void this.executeTurn();
    }, intervalMs);

    logger.debug(TAG, `下次翻页将在${this.config.interval}秒后执行`);
  }

  /**
   * 执行翻页操作
   */
  private async executeTurn(): Promise<void> {
    if (this.state !== AutoPageTurnState.RUNNING) {
      return;
    }

    if (!this.onPageTurn || !this.getCurrentPageIndex || !this.getTotalPages) {
      logger.error(TAG, '回调函数未设置，无法执行翻页');
      this.stop();
      return;
    }

    const currentPage = this.getCurrentPageIndex();
    const totalPages = this.getTotalPages();

    logger.debug(TAG, `执行自动翻页：当前页=${currentPage + 1}/${totalPages}`);

    // 如果已经是最后一页，停止自动翻页（或切换章节）
    if (currentPage >= totalPages - 1) {
      logger.info(TAG, '已到达章节最后一页');
      if (this.config.autoSwitchChapter) {
        logger.info(TAG, '自动切换到下一章节');
        if (this.onChapterEnd) {
          try {
            const switched = await this.onChapterEnd();
            if (switched) {
              this.notifyNewChapter();
              this.scheduleNextTurn();
              return;
            }
          } catch (error) {
            logger.warn(TAG, `自动切换章节失败: ${String(error)}`);
          }
        }
        this.stop();
      } else {
        this.stop();
      }
      return;
    }

    // 执行翻页
    this.onPageTurn();

    // 安排下一次翻页
    this.scheduleNextTurn();
  }

  /**
   * 清除定时器
   */
  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /**
   * 销毁控制器
   */
  public destroy(): void {
    this.stop();
    this.onPageTurn = null;
    this.getCurrentPageIndex = null;
    this.getTotalPages = null;
    this.onChapterEnd = null;
    logger.info(TAG, '自动翻页控制器已销毁');
  }
}
