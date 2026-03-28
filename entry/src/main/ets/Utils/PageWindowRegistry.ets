import { DisplayMode } from './WindowManager';
import {
  PageSafeAreaContract,
  PageTitleBarMode,
  PageWindowPolicy,
  PageWindowSpec
} from './PageWindowPolicy';

function appendPageSpecs(
  target: PageWindowSpec[],
  pageNames: string[],
  policy: PageWindowPolicy,
  managedByMainMenu: boolean,
  titleBarMode: PageTitleBarMode,
  safeAreaContract: PageSafeAreaContract,
  requiresMainMenuReturnTransition: boolean,
  fallbackDisplayMode?: DisplayMode
): void {
  for (let index = 0; index < pageNames.length; index++) {
    target.push({
      pageName: pageNames[index],
      policy,
      managedByMainMenu,
      titleBarMode,
      safeAreaContract,
      requiresMainMenuReturnTransition,
      fallbackDisplayMode
    });
  }
}

export class PageWindowRegistry {
  private static readonly MAIN_MENU_MANAGED_STANDARD_PAGES: string[] = [
    'AboutPage',
    'AdvancedSettingsSubPage',
    'AniListLoginPage',
    'AnimationSettingsSubPage',
    'AvifTestPage',
    'BackupPage',
    'DataManagementPage',
    'DownloadManagerPage',
    'DownloadSyncPage',
    'DummyPage',
    'EBookDetailPage',
    'ErrorManagementSubPage',
    'FontSettingsSubPage',
    'GlobalSettingsPage',
    'HelloWorldPage',
    'HelpCenterPage',
    'InteractionSettingsSubPage',
    'JsvmPlaygroundPage',
    'LifecycleMonitorPage',
    'LogManagerPage',
    'MangaDetailPage',
    'MangaFeedbackPage',
    'MangaSourceTestPage',
    'MainMenuSettingsSubPage',
    'NetworkSettingsSubPage',
    'NetworkFolderPage',
    'NotificationSettingsSubPage',
    'NovelBookshelfPage',
    'NovelDetailPage',
    'NovelDictRulePage',
    'NovelExplorePage',
    'NovelReplaceRulePage',
    'NovelSearchPage',
    'NovelSettingsPage',
    'NovelSourceDebugPage',
    'NovelSourceLoginPage',
    'NovelSourceManagementPage',
    'NovelTxtTocRulePage',
    'OnlineEBookDetailPage',
    'PageSettingsSubPage',
    'ReadingAnalyticsPage',
    'ReadingSettingsSubPage',
    'RssFavoritesPage',
    'RssSourceDebugPage',
    'RssSubscriptionManagementPage',
    'RssSubscriptionPage',
    'SearchPage',
    'SourceDetailPage',
    'SourceLoginPage',
    'SourceManagementPage',
    'SourceSettingsPage',
    'StorageManagementPage',
    'SuwayomiBrowsePage',
    'SuwayomiMangaDetailPage',
    'SuwayomiSourceBrowsePage',
    'SuwayomiSettingsPage',
    'SuwayomiWebUIPage',
    'SystemAnimationDemoPage',
    'SystemResourceDemoPage',
    'SystemStatusPage',
    'TestManagementPage',
    'ThemeSettingsPage',
    'TrackingSettingsSubPage',
    'VersionHistoryPage',
    'WebViewConfigurableSystemTestPage'
  ];

  private static readonly SELF_MANAGED_STANDARD_PAGES: string[] = [
    'CoverSelectionPage',
    'EBookSettingsPage',
    'GlobalSearchPage',
    'MangaSettingsPage',
    'OpenSourceLicensePage',
    'PrivacyPolicyPage',
    'RssSubscriptionDetailPage',
    'UserAgreementPage'
  ];

  private static readonly SELF_MANAGED_CUSTOM_HEADER_PAGES: string[] = [
    'SourceGuidePage',
    'SupportersPage',
    'UnifiedDetailPage'
  ];

  private static readonly SELF_MANAGED_FULLSCREEN_PAGES: string[] = [
    'MangaReaderPage',
    'EBookReaderPage',
    'EBookImageReaderPage',
    'NovelReaderPage',
    'SuwayomiReaderPage',
    'FileEditorPage'
  ];

  private static readonly SELF_MANAGED_FULLSCREEN_WITH_BARS_PAGES: string[] = [
    'ZLibraryReaderPage'
  ];

  private static readonly FOLLOW_HOST_PAGES: string[] = [
    'ReadAloudPlayerPage'
  ];

  private static readonly PAGE_SPECS: PageWindowSpec[] = PageWindowRegistry.buildSpecs();

  private static buildSpecs(): PageWindowSpec[] {
    let specs: PageWindowSpec[] = [];

    appendPageSpecs(
      specs,
      ['MainMenuPage'],
      PageWindowPolicy.ROOT_MAIN_MENU,
      false,
      PageTitleBarMode.SYSTEM,
      PageSafeAreaContract.SYSTEM_TITLEBAR,
      false,
      DisplayMode.DEFAULT
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.MAIN_MENU_MANAGED_STANDARD_PAGES,
      PageWindowPolicy.NAV_STANDARD,
      true,
      PageTitleBarMode.SYSTEM,
      PageSafeAreaContract.SYSTEM_TITLEBAR,
      true,
      DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE
    );

    appendPageSpecs(
      specs,
      ['AnnotationCenterPage'],
      PageWindowPolicy.TRANSIENT_MODAL,
      false,
      PageTitleBarMode.SYSTEM,
      PageSafeAreaContract.SYSTEM_TITLEBAR,
      false,
      DisplayMode.DEFAULT
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.SELF_MANAGED_STANDARD_PAGES,
      PageWindowPolicy.NAV_STANDARD,
      false,
      PageTitleBarMode.SYSTEM,
      PageSafeAreaContract.SYSTEM_TITLEBAR,
      true,
      DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.SELF_MANAGED_CUSTOM_HEADER_PAGES,
      PageWindowPolicy.NAV_CUSTOM_HEADER,
      false,
      PageTitleBarMode.CUSTOM,
      PageSafeAreaContract.CUSTOM_HEADER,
      true,
      DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.SELF_MANAGED_FULLSCREEN_PAGES,
      PageWindowPolicy.FULLSCREEN_READER,
      false,
      PageTitleBarMode.HIDDEN,
      PageSafeAreaContract.FULLSCREEN,
      true,
      DisplayMode.FULL_IMMERSIVE
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.SELF_MANAGED_FULLSCREEN_WITH_BARS_PAGES,
      PageWindowPolicy.FULLSCREEN_READER_WITH_BARS,
      false,
      PageTitleBarMode.HIDDEN,
      PageSafeAreaContract.FULLSCREEN,
      true,
      DisplayMode.IMMERSIVE_WITH_BARS
    );

    appendPageSpecs(
      specs,
      PageWindowRegistry.FOLLOW_HOST_PAGES,
      PageWindowPolicy.FOLLOW_HOST,
      false,
      PageTitleBarMode.HIDDEN,
      PageSafeAreaContract.FOLLOW_HOST,
      true
    );

    return specs;
  }

  static getSpec(pageName: string): PageWindowSpec | null {
    for (let index = 0; index < PageWindowRegistry.PAGE_SPECS.length; index++) {
      const spec = PageWindowRegistry.PAGE_SPECS[index];
      if (spec.pageName === pageName) {
        return spec;
      }
    }
    return null;
  }

  static isManagedByMainMenu(pageName: string): boolean {
    const spec = PageWindowRegistry.getSpec(pageName);
    return spec ? spec.managedByMainMenu : false;
  }

  static requiresMainMenuReturnTransition(pageName: string): boolean {
    const spec = PageWindowRegistry.getSpec(pageName);
    return spec ? spec.requiresMainMenuReturnTransition : false;
  }
}
