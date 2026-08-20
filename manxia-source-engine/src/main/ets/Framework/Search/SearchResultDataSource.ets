/**
 * 全局搜索结果 LazyForEach 数据源
 */

import { BasicDataSource } from 'manxia_core/src/main/ets/Utils/BasicDataSource';

export class SearchResultDataSource<T> extends BasicDataSource<T> {
  replaceData(data: T[]): void {
    this.setData(data);
  }
}
