import { ISourceRegistry } from '../contracts/ISourceRegistry';

class NGFSourceRegistryEntry {
  sourceId: string;
  pkg: string;
  registeredAt: number;

  constructor(sourceId: string, pkg: string, registeredAt: number) {
    this.sourceId = sourceId;
    this.pkg = pkg;
    this.registeredAt = registeredAt;
  }
}

export class SourceRegistryFacade implements ISourceRegistry {
  private entries: Map<string, NGFSourceRegistryEntry> = new Map<string, NGFSourceRegistryEntry>();

  registerSource(sourceId: string, pkg: string): boolean {
    const normalizedSourceId = sourceId.trim();
    const normalizedPkg = pkg.trim();
    if (normalizedSourceId.length <= 0 || normalizedPkg.length <= 0) {
      return false;
    }

    const existing = this.entries.get(normalizedSourceId);
    if (existing && existing.pkg === normalizedPkg) {
      return true;
    }

    this.entries.set(
      normalizedSourceId,
      new NGFSourceRegistryEntry(normalizedSourceId, normalizedPkg, Date.now())
    );
    return true;
  }

  unregisterSource(sourceId: string): boolean {
    const normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.length <= 0) {
      return false;
    }
    if (!this.entries.has(normalizedSourceId)) {
      return false;
    }
    this.entries.delete(normalizedSourceId);
    return true;
  }

  hasSource(sourceId: string): boolean {
    const normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.length <= 0) {
      return false;
    }
    return this.entries.has(normalizedSourceId);
  }

  listSourceIds(): string[] {
    return Array.from(this.entries.keys());
  }
}

export const ngfSourceRegistryFacade = new SourceRegistryFacade();
