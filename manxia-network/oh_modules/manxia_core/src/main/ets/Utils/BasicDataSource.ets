/**
 * 通用 LazyForEach 数据源实现
 * 基于 ComicInfoDataSource（SearchPage.ets:73）模式泛化
 */
export class BasicDataSourceStableUpdateResult {
  public skipped: boolean = false;
  public reloaded: boolean = false;
  public changedCount: number = 0;
  public totalCount: number = 0;
  public reason: string = '';
}

export class BasicDataSource<T> implements IDataSource {
  private dataArray: T[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): T {
    return this.dataArray[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  public notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  public notifyDataAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  public notifyDataDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }

  public notifyDataChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  public setData(data: T[]): void {
    this.dataArray = data;
    this.notifyDataReload();
  }

  public setDataStable(
    data: T[],
    keyBuilder: (item: T, index: number) => string,
    signatureBuilder: (item: T, index: number) => string
  ): BasicDataSourceStableUpdateResult {
    const result: BasicDataSourceStableUpdateResult = new BasicDataSourceStableUpdateResult();
    result.totalCount = data.length;

    if (this.dataArray.length !== data.length) {
      this.dataArray = data;
      result.reloaded = true;
      result.changedCount = data.length;
      result.reason = 'length_changed';
      this.notifyDataReload();
      return result;
    }

    for (let index = 0; index < data.length; index++) {
      const previousKey: string = keyBuilder(this.dataArray[index], index);
      const nextKey: string = keyBuilder(data[index], index);
      if (previousKey !== nextKey) {
        this.dataArray = data;
        result.reloaded = true;
        result.changedCount = data.length;
        result.reason = 'order_or_key_changed';
        this.notifyDataReload();
        return result;
      }
    }

    const changedIndices: number[] = [];
    for (let index = 0; index < data.length; index++) {
      const previousSignature: string = signatureBuilder(this.dataArray[index], index);
      const nextSignature: string = signatureBuilder(data[index], index);
      if (previousSignature !== nextSignature) {
        changedIndices.push(index);
      }
    }

    this.dataArray = data;
    if (changedIndices.length === 0) {
      result.skipped = true;
      result.reason = 'signature_unchanged';
      return result;
    }

    result.changedCount = changedIndices.length;
    result.reason = 'item_signature_changed';
    for (let index = 0; index < changedIndices.length; index++) {
      this.notifyDataChange(changedIndices[index]);
    }
    return result;
  }

  public getDataArray(): T[] {
    return this.dataArray;
  }
}
