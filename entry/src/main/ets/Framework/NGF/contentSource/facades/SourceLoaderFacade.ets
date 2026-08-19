import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { getContext, isInitialized as isGlobalContextInitialized } from '../../../../GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { uiContextManager } from '../../../Managers/UIContextManager';
import { ISourceLoader } from '../contracts/ISourceLoader';

const TAG = 'NGFSourceLoaderFacade';

class NGFSourceLoaderIconCandidate {
  path: string;

  constructor(path: string) {
    this.path = path;
  }
}

export class SourceLoaderFacade implements ISourceLoader {
  private readonly repositoryDirName: string = 'extensions-source';
  private readonly sourceFileName: string = 'source.json';

  exists(pkg: string): boolean {
    const normalizedPkg = this.normalizePkg(pkg);
    if (normalizedPkg.length <= 0) {
      return false;
    }

    const sourceJsonCandidates = this.buildSourceJsonCandidates(normalizedPkg);
    for (let index = 0; index < sourceJsonCandidates.length; index++) {
      if (this.existsPath(sourceJsonCandidates[index])) {
        return true;
      }
    }
    return false;
  }

  loadSourceJson(pkg: string): string {
    const normalizedPkg = this.normalizePkg(pkg);
    if (normalizedPkg.length <= 0) {
      return '';
    }

    const sourceJsonCandidates = this.buildSourceJsonCandidates(normalizedPkg);
    for (let index = 0; index < sourceJsonCandidates.length; index++) {
      const candidatePath = sourceJsonCandidates[index];
      if (!this.existsPath(candidatePath)) {
        continue;
      }

      try {
        const content = this.readText(candidatePath).trim();
        if (content.length > 0) {
          return content;
        }
      } catch {
        logger.warn(TAG, `读取图源配置失败: ${candidatePath}`);
      }
    }

    return '';
  }

  loadIconPath(pkg: string): string {
    const normalizedPkg = this.normalizePkg(pkg);
    if (normalizedPkg.length <= 0) {
      return '';
    }

    const iconCandidates = this.buildIconCandidates(normalizedPkg);
    for (let index = 0; index < iconCandidates.length; index++) {
      const candidate = iconCandidates[index];
      if (this.existsPath(candidate.path)) {
        return candidate.path;
      }
    }

    return '';
  }

  private normalizePkg(pkg: string): string {
    return pkg.trim();
  }

  private buildSourceJsonCandidates(pkg: string): string[] {
    const repositoryDir = this.getRepositoryDir();
    if (repositoryDir.length <= 0) {
      return [];
    }

    const candidates: string[] = [];
    candidates.push(`${repositoryDir}/${pkg}/${this.sourceFileName}`);
    candidates.push(`${repositoryDir}/${pkg}.json`);
    return candidates;
  }

  private buildIconCandidates(pkg: string): Array<NGFSourceLoaderIconCandidate> {
    const repositoryDir = this.getRepositoryDir();
    if (repositoryDir.length <= 0) {
      return [];
    }

    const iconCandidates: Array<NGFSourceLoaderIconCandidate> = [];
    const iconFormats: string[] = ['webp', 'png', 'jpg'];

    for (let index = 0; index < iconFormats.length; index++) {
      const ext = iconFormats[index];
      iconCandidates.push(new NGFSourceLoaderIconCandidate(`${repositoryDir}/icons/${pkg}.${ext}`));
    }
    for (let index = 0; index < iconFormats.length; index++) {
      const ext = iconFormats[index];
      iconCandidates.push(new NGFSourceLoaderIconCandidate(`${repositoryDir}/${pkg}/icon.${ext}`));
    }

    return iconCandidates;
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

  private existsPath(path: string): boolean {
    try {
      return SafeFileUtils.accessSync(path);
    } catch {
      return false;
    }
  }

  private readText(path: string): string {
    const file = SafeFileUtils.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = SafeFileUtils.statSync(path);
      if (stat.size <= 0) {
        return '';
      }
      const buffer = new ArrayBuffer(Number(stat.size));
      SafeFileUtils.readSync(file.fd, buffer);
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }
}

export const ngfSourceLoaderFacade = new SourceLoaderFacade();
