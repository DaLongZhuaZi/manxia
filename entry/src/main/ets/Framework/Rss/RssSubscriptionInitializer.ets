import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getRssSubscriptionManager, RssSubscriptionManager } from './RssSubscriptionManager';

const TAG = 'RssSubscriptionInitializer';

export class RssSubscriptionInitializer {
  private static instance: RssSubscriptionInitializer | null = null;
  private isInitialized: boolean = false;
  private manager: RssSubscriptionManager = getRssSubscriptionManager();

  private constructor() {
  }

  static getInstance(): RssSubscriptionInitializer {
    if (!RssSubscriptionInitializer.instance) {
      RssSubscriptionInitializer.instance = new RssSubscriptionInitializer();
    }
    return RssSubscriptionInitializer.instance;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized && this.manager.isReady()) {
      logger.debug(TAG, '订阅源模块已初始化，跳过重复初始化');
      return;
    }
    logger.info(TAG, '开始初始化订阅源模块');
    await this.manager.initialize(context);
    this.isInitialized = true;
    logger.info(TAG, '订阅源模块初始化完成');
  }

  isReady(): boolean {
    return this.isInitialized && this.manager.isReady();
  }

  reset(): void {
    this.isInitialized = false;
  }
}

export function getRssSubscriptionInitializer(): RssSubscriptionInitializer {
  return RssSubscriptionInitializer.getInstance();
}
