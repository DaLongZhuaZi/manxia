import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { getContext, isInitialized as isGlobalContextInitialized } from 'manxia_theme/src/main/ets/GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { uiContextManager } from 'manxia_theme/src/main/ets/Framework/Managers/UIContextManager';
import { ISourceRepository } from '../contracts/ISourceRepository';

const TAG = 'NGFSourceRepositoryFacade';

class NGFSourceRepositoryEntry {
  pkg: string;

  constructor(pkg: string) {
    this.pkg = pkg;
  }
}

class NGFSourceRepositoryIndex {
  version: string;
  lastUpdate: number;
  sources: Array<NGFSourceRepositoryEntry>;

  constructor(version: string, lastUpdate: number, sources: Array<NGFSourceRepositoryEntry>) {
    this.version = version;
    this.lastUpdate = lastUpdate;
    this.sources = sources;
  }
}

export class SourceRepositoryFacade implements ISourceRepository {
  private readonly repositoryDirName: string = 'extensions-source';
  private readonly indexFileName: string = 'index.main.json';

  readIndexJson(): string {
    const indexPath = this.getIndexFilePath();
    if (indexPath.length <= 0 || !this.exists(indexPath)) {
      return this.createDefaultIndexJson();
    }

    try {
      return this.readText(indexPath);
    } catch {
      logger.warn(TAG, `读取仓库索引失败: ${indexPath}`);
      return this.createDefaultIndexJson();
    }
  }

  updateIndexJson(content: string): boolean {
    const indexPath = this.getIndexFilePath();
    if (indexPath.length <= 0) {
      return false;
    }

    const normalized = content.trim();
    if (normalized.length <= 0) {
      return false;
    }

    try {
      this.parseIndexJson(normalized);
      this.ensureRepositoryDir();
      return this.writeText(indexPath, normalized);
    } catch {
      logger.warn(TAG, '更新仓库索引失败: JSON格式不合法');
      return false;
    }
  }

  listPackages(): string[] {
    const indexJson = this.readIndexJson();
    try {
      const indexObject = this.parseIndexJson(indexJson);
      const packages: string[] = [];
      for (let i = 0; i < indexObject.sources.length; i++) {
        const pkg = indexObject.sources[i].pkg.trim();
        if (pkg.length > 0) {
          packages.push(pkg);
        }
      }
      return packages;
    } catch {
      return [];
    }
  }

  private parseIndexJson(indexJson: string): NGFSourceRepositoryIndex {
    const parsed = SafeUtils.parseObj(indexJson) as Partial<NGFSourceRepositoryIndex>;
    const version = parsed.version && typeof parsed.version === 'string' ? parsed.version : '1.0.0';
    const lastUpdate = parsed.lastUpdate && typeof parsed.lastUpdate === 'number'
      ? parsed.lastUpdate
      : Date.now();
    const sourceEntries: Array<NGFSourceRepositoryEntry> = [];

    if (parsed.sources && Array.isArray(parsed.sources)) {
      for (let i = 0; i < parsed.sources.length; i++) {
        const item = parsed.sources[i] as Partial<NGFSourceRepositoryEntry>;
        const pkg = item.pkg && typeof item.pkg === 'string' ? item.pkg : '';
        if (pkg.length > 0) {
          sourceEntries.push(new NGFSourceRepositoryEntry(pkg));
        }
      }
    }

    return new NGFSourceRepositoryIndex(version, lastUpdate, sourceEntries);
  }

  private createDefaultIndexJson(): string {
    const defaultIndex = new NGFSourceRepositoryIndex('1.0.0', Date.now(), []);
    return JSON.stringify(defaultIndex);
  }

  private getIndexFilePath(): string {
    const repositoryDir = this.getRepositoryDir();
    if (repositoryDir.length <= 0) {
      return '';
    }
    return `${repositoryDir}/${this.indexFileName}`;
  }

  private getRepositoryDir(): string {
    const filesDir = this.resolveFilesDir();
    if (filesDir.length <= 0) {
      return '';
    }
    return `${filesDir}/${this.repositoryDirName}`;
  }

  private resolveFilesDir(): string {
    const abilityContext = uiContextManager.getAbilityContext();
    if (abilityContext) {
      return abilityContext.filesDir;
    }

    if (isGlobalContextInitialized()) {
      try {
        return getContext().filesDir;
      } catch {
        return '';
      }
    }

    return '';
  }

  private ensureRepositoryDir(): void {
    const repositoryDir = this.getRepositoryDir();
    if (repositoryDir.length <= 0 || this.exists(repositoryDir)) {
      return;
    }

    try {
      SafeFileUtils.mkdirSync(repositoryDir, true);
    } catch {
      logger.warn(TAG, `创建仓库目录失败: ${repositoryDir}`);
    }
  }

  private exists(path: string): boolean {
    try {
      return SafeFileUtils.accessSync(path);
    } catch {
      return false;
    }
  }

  private readText(path: string): string {
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
  }

  private writeText(path: string, content: string): boolean {
    try {
      const file = SafeFileUtils.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileUtils.writeSync(file.fd, content);
      SafeFileUtils.closeSync(file);
      return true;
    } catch {
      return false;
    }
  }
}

export const ngfSourceRepositoryFacade = new SourceRepositoryFacade();
