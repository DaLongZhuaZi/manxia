export class SourceIdentity {
  sourceId: number = 0;
  pkg: string = '';
  name: string = '';
  version: string = '';
  configHash: string = '';
  type: string = 'manga';

  isValid(): boolean {
    return this.sourceId > 0 && this.pkg.trim().length > 0;
  }

  signature(): string {
    return `${this.sourceId}|${this.pkg}|${this.version}|${this.configHash}`;
  }
}

export class SourceIdentityFactory {
  static create(
    sourceId: number,
    pkg: string,
    name: string,
    version: string,
    configJson: string,
    type: string
  ): SourceIdentity {
    const identity = new SourceIdentity();
    identity.sourceId = sourceId;
    identity.pkg = pkg.trim();
    identity.name = name.trim();
    identity.version = version.trim();
    identity.configHash = SourceIdentityFactory.hashConfig(configJson);
    identity.type = type.trim().length > 0 ? type.trim() : 'manga';
    return identity;
  }

  static hashConfig(configJson: string): string {
    let hash: number = 2166136261;
    for (let index = 0; index < configJson.length; index++) {
      hash = hash ^ configJson.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    const normalized = hash >>> 0;
    let hex = normalized.toString(16);
    while (hex.length < 8) {
      hex = `0${hex}`;
    }
    return hex;
  }
}
