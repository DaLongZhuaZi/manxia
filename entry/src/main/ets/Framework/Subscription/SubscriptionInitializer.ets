import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getSubscriptionManager, SubscriptionManager } from './SubscriptionManager';

const TAG = 'SubscriptionInitializer';

export class SubscriptionInitializer {
  private static instance: SubscriptionInitializer | null = null;
  private readonly manager: SubscriptionManager = getSubscriptionManager();
  private isInitialized: boolean = false;

  private constructor() {
  }

  public static getInstance(): SubscriptionInitializer {
    if (SubscriptionInitializer.instance === null) {
      SubscriptionInitializer.instance = new SubscriptionInitializer();
    }
    return SubscriptionInitializer.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized && this.manager.isReady()) {
      logger.debug(TAG, '统一内容跟踪模块已初始化，跳过重复初始化');
      return;
    }
    logger.info(TAG, '开始初始化统一内容跟踪模块');
    await this.manager.initialize(context);
    this.isInitialized = true;
    logger.info(TAG, '统一内容跟踪模块初始化完成');
  }

  public isReady(): boolean {
    return this.isInitialized && this.manager.isReady();
  }

  public reset(): void {
    this.isInitialized = false;
  }
}

export function getSubscriptionInitializer(): SubscriptionInitializer {
  return SubscriptionInitializer.getInstance();
}
