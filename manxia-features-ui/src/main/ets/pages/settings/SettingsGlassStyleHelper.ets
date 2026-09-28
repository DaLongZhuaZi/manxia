import { ThemeManager, GlassLevel, GlassStyleToken } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';

export class SettingsGlassStyleHelper {
  private static readonly themeManager: ThemeManager = ThemeManager.getInstance();

  private static getGlassToken(level: GlassLevel): GlassStyleToken {
    return SettingsGlassStyleHelper.themeManager.getGlassToken(level);
  }

  static getCardBackground(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).backgroundColor;
  }

  static getCardBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).blurStyle;
  }

  static getCardBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).blurOptions;
  }

  static getCardRadius(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).radius;
  }

  static getCardBorderColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).borderColor;
  }

  static getCardBorderWidth(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).borderWidth;
  }

  static getCardShadowColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.CARD).shadowColor;
  }

  static getFloatingBackground(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).backgroundColor;
  }

  static getFloatingBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).blurStyle;
  }

  static getFloatingBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).blurOptions;
  }

  static getFloatingRadius(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).radius;
  }

  static getFloatingBorderColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).borderColor;
  }

  static getFloatingBorderWidth(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).borderWidth;
  }

  static getFloatingShadowColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FLOATING).shadowColor;
  }

  static getFeaturedBackground(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).backgroundColor;
  }

  static getFeaturedBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).blurStyle;
  }

  static getFeaturedBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).blurOptions;
  }

  static getFeaturedBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).backgroundEffect;
  }

  static getFeaturedRadius(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).radius;
  }

  static getFeaturedBorderColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).borderColor;
  }

  static getFeaturedBorderWidth(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).borderWidth;
  }

  static getFeaturedShadowColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.FEATURED).shadowColor;
  }

  static getNavigationBackground(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).backgroundColor;
  }

  static getNavigationBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).blurStyle;
  }

  static getNavigationBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).blurOptions;
  }

  static getNavigationRadius(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).radius;
  }

  static getNavigationBorderColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).borderColor;
  }

  static getNavigationBorderWidth(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).borderWidth;
  }

  static getNavigationShadowColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.NAVIGATION).shadowColor;
  }

  static getSheetBackground(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).backgroundColor;
  }

  static getSheetBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).blurStyle;
  }

  static getSheetBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).blurOptions;
  }

  static getSheetRadius(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).radius;
  }

  static getSheetBorderColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).borderColor;
  }

  static getSheetBorderWidth(): number {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).borderWidth;
  }

  static getSheetShadowColor(): string {
    return SettingsGlassStyleHelper.getGlassToken(GlassLevel.SHEET).shadowColor;
  }

  static getTitleBarIconBackground(): string {
    return SettingsGlassStyleHelper.getFloatingBackground();
  }
}
