// 职责: 漫画阅读器 LazyForEach 数据源，避免主阅读组件承载数据源实现细节。

import { MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';
import { WebtoonDataItem } from './MangaWebtoonTypes';

export class MangaPageDataSource implements IDataSource {
  private pages: MangaPage[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(pages: MangaPage[]) {
    this.pages = pages;
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): MangaPage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const position: number = this.listeners.indexOf(listener);
    if (position >= 0) {
      this.listeners.splice(position, 1);
    }
  }

  setPages(pages: MangaPage[]): void {
    this.pages = pages;
    this.notifyDataReload();
  }

  notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  notifyDataAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  notifyDataChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  notifyDataDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

export class ContinuousPageIndexDataSource implements IDataSource {
  private pageIndices: number[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(pageIndices: number[] = []) {
    this.pageIndices = pageIndices;
  }

  totalCount(): number {
    return this.pageIndices.length;
  }

  getData(index: number): number {
    return this.pageIndices[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const position: number = this.listeners.indexOf(listener);
    if (position >= 0) {
      this.listeners.splice(position, 1);
    }
  }

  setPageIndices(pageIndices: number[]): void {
    this.pageIndices = pageIndices;
    this.notifyDataReload();
  }

  notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  notifyDataAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  notifyDataChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  notifyDataDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}

export class WebtoonLazyDataSource implements IDataSource {
  private items: WebtoonDataItem[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: WebtoonDataItem[] = []) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): WebtoonDataItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const position: number = this.listeners.indexOf(listener);
    if (position >= 0) {
      this.listeners.splice(position, 1);
    }
  }

  setItems(items: WebtoonDataItem[]): void {
    this.items = items;
    this.notifyDataReload();
  }

  getItems(): WebtoonDataItem[] {
    return this.items;
  }

  appendItems(newItems: WebtoonDataItem[]): void {
    const startIndex: number = this.items.length;
    this.items = this.items.concat(newItems);
    for (let i = 0; i < newItems.length; i++) {
      this.notifyDataAdd(startIndex + i);
    }
  }

  prependItems(newItems: WebtoonDataItem[]): void {
    this.items = newItems.concat(this.items);
    this.notifyDataReload();
  }

  notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  notifyDataAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  notifyDataChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  notifyDataDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}
