import { BackgroundBlurOverlay } from 'manxia_theme/src/main/ets/Framework/Components/BackgroundBlurOverlay';
import { ThemeManager, ThemeType, ThemeChangeCallback } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { READER_ABILITY_WINDOW_BACKGROUND_KEY } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';

@Component
export struct ReaderAbilityBackgroundBlurOverlay {
  @StorageProp('backgroundBlurEnabled') private backgroundBlurEnabled: boolean = false;
  @StorageProp('backgroundBlurBgType') private backgroundBlurBgType: string = 'solid';
  @StorageProp('backgroundBlurBgImage') private backgroundBlurBgImage: string = '';
  @StorageProp('backgroundBlurIconType') private backgroundBlurIconType: string = 'shield';
  @LocalStorageProp(READER_ABILITY_WINDOW_BACKGROUND_KEY) private readerWindowInBackground: boolean = false;
  @State private currentTheme: ThemeType = ThemeType.DARK;

  private themeManager: ThemeManager = ThemeManager.getInstance();
  private themeChangeCallback: ThemeChangeCallback = (theme: ThemeType): void => {
    this.currentTheme = theme;
  };

  aboutToAppear(): void {
    this.currentTheme = this.themeManager.getActualThemeSync();
    this.themeManager.onThemeChange(this.themeChangeCallback);
  }

  aboutToDisappear(): void {
    this.themeManager.offThemeChange(this.themeChangeCallback);
  }

  private shouldShowOverlay(): boolean {
    return this.backgroundBlurEnabled && this.readerWindowInBackground;
  }

  build() {
    BackgroundBlurOverlay({
      isVisible: this.shouldShowOverlay(),
      bgType: this.backgroundBlurBgType,
      customBgImage: this.backgroundBlurBgImage,
      iconType: this.backgroundBlurIconType,
      currentTheme: this.currentTheme
    })
      .zIndex(99999)
  }
}
