import { logger } from '../../../../Utils/Logger';
import { IDbMigrator } from '../contracts/IDbMigrator';

const TAG = 'NGFDbMigratorFacade';

export class DbMigratorFacade implements IDbMigrator {
  private readonly schemaVersionKey: string = 'ngf_data_schema_version';
  private readonly baselineVersion: number = 1;
  private readonly latestVersion: number = 1;

  currentVersion(): number {
    const version = AppStorage.get<number>(this.schemaVersionKey);
    if (version && version > 0) {
      return version;
    }
    return this.baselineVersion;
  }

  targetVersion(): number {
    return this.latestVersion;
  }

  async migrate(): Promise<boolean> {
    try {
      AppStorage.setOrCreate(this.schemaVersionKey, this.targetVersion());
      logger.info(TAG, `✅ 数据 schema 迁移完成: v${this.currentVersion()} -> v${this.targetVersion()}`);
      return true;
    } catch {
      logger.warn(TAG, '⚠️ 数据 schema 迁移失败');
      return false;
    }
  }

  async rollback(toVersion: number): Promise<boolean> {
    if (toVersion <= 0) {
      logger.warn(TAG, `⚠️ 回滚版本非法: ${toVersion}`);
      return false;
    }

    try {
      AppStorage.setOrCreate(this.schemaVersionKey, toVersion);
      logger.info(TAG, `✅ 数据 schema 已回滚到: v${toVersion}`);
      return true;
    } catch {
      logger.warn(TAG, `⚠️ 数据 schema 回滚失败: v${toVersion}`);
      return false;
    }
  }
}

export const ngfDbMigratorFacade = new DbMigratorFacade();
