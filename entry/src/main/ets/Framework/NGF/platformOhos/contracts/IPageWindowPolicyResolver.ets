import { NGFDisplayMode } from './IPlatformWindowController';

export enum NGFPageWindowPolicy {
  DEFAULT = 'default',
  KEEP_HOST = 'keep_host',
  FULLSCREEN = 'fullscreen',
  IMMERSIVE = 'immersive'
}

export class NGFPageWindowSpec {
  pageName: string;
  policy: NGFPageWindowPolicy;
  fallbackMode: NGFDisplayMode;

  constructor(pageName: string, policy: NGFPageWindowPolicy, fallbackMode: NGFDisplayMode) {
    this.pageName = pageName;
    this.policy = policy;
    this.fallbackMode = fallbackMode;
  }
}

export interface IPageWindowPolicyResolver {
  register(spec: NGFPageWindowSpec): void;
  resolve(pageName: string): NGFPageWindowSpec | null;
  has(pageName: string): boolean;
}
