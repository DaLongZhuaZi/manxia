import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { getContext, isInitialized as isGlobalContextInitialized } from 'manxia_core/src/main/ets/GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { uiContextManager } from 'manxia_theme/src/main/ets/Framework/Managers/UIContextManager';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import { IStorageProvider } from '../contracts/IStorageProvider';

const TAG = 'NGFStorageProviderFacade';

export class StorageProviderFacade implements IStorageProvider {
  private readonly sandboxManager: SandboxManager = SandboxManager.getInstance();

  getCacheDir(): string {
    try {
      return this.sandboxManager.getDirectory('cache');
    } catch {
      const filesDir = this.getFilesDir();
      if (filesDir.length > 0) {
        return `${filesDir}/cache`;
      }
      return '';
    }
  }

  getFilesDir(): string {
    try {
      return this.sandboxManager.getDirectory('files');
    } catch {
      return this.resolveFilesDirFromContext();
    }
  }

  readText(path: string): string {
    if (path.trim().length <= 0) {
      return '';
    }

    try {
      if (!this.exists(path)) {
        return '';
      }

      const file = SafeFileUtils.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(path);
      if (stat.size <= 0) {
        SafeFileUtils.closeSync(file);
        return '';
      }

      const buffer = new ArrayBuffer(Number(stat.size));
      SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch {
      logger.warn(TAG, `读取文本失败: ${path}`);
      return '';
    }
  }

  writeText(path: string, content: string): boolean {
    if (path.trim().length <= 0) {
      return false;
    }

    try {
      this.ensureParentDirectory(path);
      const file = SafeFileUtils.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeSync(file.fd, content);
      SafeFileUtils.closeSync(file);
      return true;
    } catch {
      logger.warn(TAG, `写入文本失败: ${path}`);
      return false;
    }
  }

  exists(path: string): boolean {
    if (path.trim().length <= 0) {
      return false;
    }

    try {
      return SafeFileUtils.accessSync(path);
    } catch {
      return false;
    }
  }

  private resolveFilesDirFromContext(): string {
    const abilityContext = uiContextManager.getAbilityContext();
    if (abilityContext) {
      return abilityContext.filesDir;
    }

    if (isGlobalContextInitialized()) {
      try {
        const globalContext = getContext();
        return globalContext.filesDir;
      } catch {
        return '';
      }
    }

    return '';
  }

  private ensureParentDirectory(path: string): void {
    const normalizedPath = path.replace(/\\/g, '/');
    const lastSlash = normalizedPath.lastIndexOf('/');
    if (lastSlash <= 0) {
      return;
    }

    const parentDir = normalizedPath.substring(0, lastSlash);
    if (parentDir.length <= 0 || this.exists(parentDir)) {
      return;
    }

    try {
      SafeFileUtils.mkdirSync(parentDir, true);
    } catch {
      logger.warn(TAG, `创建父目录失败: ${parentDir}`);
    }
  }
}

export const ngfStorageProviderFacade = new StorageProviderFacade();
