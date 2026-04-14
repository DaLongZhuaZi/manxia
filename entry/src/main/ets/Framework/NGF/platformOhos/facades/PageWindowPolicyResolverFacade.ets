import { DisplayMode } from '../../../../Utils/WindowManager';
import { PageWindowPolicy } from '../../../../Utils/PageWindowPolicy';
import { PageWindowRegistry } from '../../../../Utils/PageWindowRegistry';
import {
  IPageWindowPolicyResolver,
  NGFPageWindowPolicy,
  NGFPageWindowSpec
} from '../contracts/IPageWindowPolicyResolver';
import { NGFDisplayMode } from '../contracts/IPlatformWindowController';

export class PageWindowPolicyResolverFacade implements IPageWindowPolicyResolver {
  private overrides: Map<string, NGFPageWindowSpec> = new Map<string, NGFPageWindowSpec>();

  register(spec: NGFPageWindowSpec): void {
    this.overrides.set(spec.pageName, spec);
  }

  resolve(pageName: string): NGFPageWindowSpec | null {
    const overrideSpec = this.overrides.get(pageName);
    if (overrideSpec) {
      return overrideSpec;
    }

    const legacySpec = PageWindowRegistry.getSpec(pageName);
    if (!legacySpec) {
      return null;
    }

    const fallbackMode = legacySpec.fallbackDisplayMode
      ? this.toNGFDisplayMode(legacySpec.fallbackDisplayMode)
      : NGFDisplayMode.DEFAULT;
    return new NGFPageWindowSpec(pageName, this.toNGFPolicy(legacySpec.policy), fallbackMode);
  }

  has(pageName: string): boolean {
    if (this.overrides.has(pageName)) {
      return true;
    }
    return PageWindowRegistry.getSpec(pageName) !== null;
  }

  private toNGFPolicy(policy: PageWindowPolicy): NGFPageWindowPolicy {
    switch (policy) {
      case PageWindowPolicy.FOLLOW_HOST:
        return NGFPageWindowPolicy.KEEP_HOST;
      case PageWindowPolicy.FULLSCREEN_READER:
        return NGFPageWindowPolicy.FULLSCREEN;
      case PageWindowPolicy.FULLSCREEN_READER_WITH_BARS:
        return NGFPageWindowPolicy.IMMERSIVE;
      case PageWindowPolicy.ROOT_MAIN_MENU:
      case PageWindowPolicy.NAV_STANDARD:
      case PageWindowPolicy.NAV_CUSTOM_HEADER:
      case PageWindowPolicy.TRANSIENT_MODAL:
      default:
        return NGFPageWindowPolicy.DEFAULT;
    }
  }

  private toNGFDisplayMode(mode: DisplayMode): NGFDisplayMode {
    switch (mode) {
      case DisplayMode.FULL_IMMERSIVE:
        return NGFDisplayMode.FULL_IMMERSIVE;
      case DisplayMode.IMMERSIVE_WITH_BARS:
        return NGFDisplayMode.IMMERSIVE_WITH_BARS;
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        return NGFDisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
      case DisplayMode.DEFAULT:
      case DisplayMode.HIDE_STATUS_BAR:
      case DisplayMode.HIDE_NAVIGATION_BAR:
      default:
        return NGFDisplayMode.DEFAULT;
    }
  }
}

export const ngfPageWindowPolicyResolverFacade = new PageWindowPolicyResolverFacade();
