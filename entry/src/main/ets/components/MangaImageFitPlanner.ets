export enum MangaImageFitMode {
  FIT_WIDTH = 'fit_width',
  FIT_HEIGHT = 'fit_height',
  ORIGINAL = 'original'
}

export class MangaImageFitLayout {
  public x: number = 0;
  public y: number = 0;
  public width: number = 0;
  public height: number = 0;
  public overflowX: boolean = false;
  public overflowY: boolean = false;
  public usedFallback: boolean = false;

  constructor(
    x: number,
    y: number,
    width: number,
    height: number,
    overflowX: boolean,
    overflowY: boolean,
    usedFallback: boolean
  ) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
    this.overflowX = overflowX;
    this.overflowY = overflowY;
    this.usedFallback = usedFallback;
  }
}

export function resolveMangaImageFitMode(value: string): MangaImageFitMode {
  if (value === MangaImageFitMode.FIT_HEIGHT) {
    return MangaImageFitMode.FIT_HEIGHT;
  }
  if (value === MangaImageFitMode.ORIGINAL) {
    return MangaImageFitMode.ORIGINAL;
  }
  return MangaImageFitMode.FIT_WIDTH;
}

export class MangaImageFitPlanner {
  public resolve(
    modeValue: string,
    imageWidth: number,
    imageHeight: number,
    viewportWidth: number,
    viewportHeight: number,
    densityPixels: number
  ): MangaImageFitLayout {
    const safeWidth: number = Math.max(1, viewportWidth);
    const safeHeight: number = Math.max(1, viewportHeight);
    if (imageWidth <= 0 || imageHeight <= 0) {
      return this.createLayout(safeWidth, safeHeight, safeWidth, safeHeight, true);
    }

    const fitMode: MangaImageFitMode = resolveMangaImageFitMode(modeValue);
    let resultWidth: number = safeWidth;
    let resultHeight: number = safeHeight;
    if (fitMode === MangaImageFitMode.FIT_WIDTH) {
      resultHeight = safeWidth * imageHeight / imageWidth;
    } else if (fitMode === MangaImageFitMode.FIT_HEIGHT) {
      resultWidth = safeHeight * imageWidth / imageHeight;
    } else {
      const safeDensity: number = densityPixels > 0 ? densityPixels : 1;
      resultWidth = imageWidth / safeDensity;
      resultHeight = imageHeight / safeDensity;
    }
    return this.createLayout(resultWidth, resultHeight, safeWidth, safeHeight, false);
  }

  private createLayout(
    width: number,
    height: number,
    viewportWidth: number,
    viewportHeight: number,
    usedFallback: boolean
  ): MangaImageFitLayout {
    const x: number = (viewportWidth - width) / 2;
    const y: number = (viewportHeight - height) / 2;
    return new MangaImageFitLayout(
      x,
      y,
      width,
      height,
      width > viewportWidth + 0.5,
      height > viewportHeight + 0.5,
      usedFallback
    );
  }
}
