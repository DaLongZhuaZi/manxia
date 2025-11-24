# 图源预加载设置UI开发指南

## 📋 需求概述

为每个图源添加预加载设置功能，允许用户自定义：
1. 当前章节预加载策略
2. 下一章节预加载策略

## 🎨 UI设计建议

### 方案一：独立设置页面

```
┌─────────────────────────────────┐
│  ← 图源预加载设置                │
├─────────────────────────────────┤
│                                 │
│  📖 当前章节预加载              │
│  ┌───────────────────────────┐ │
│  │ ☑ 启用预加载              │ │
│  │                           │ │
│  │ 预加载页数：[3]  页       │ │
│  │ ━━━━━━━━━━━━━━━━━━━━━━  │ │
│  │ 1              10        20│ │
│  │                           │ │
│  │ ☐ 预加载全部章节          │ │
│  └───────────────────────────┘ │
│                                 │
│  📚 下一章节预加载              │
│  ┌───────────────────────────┐ │
│  │ ☑ 启用预加载              │ │
│  │                           │ │
│  │ 预加载页数：[全部]        │ │
│  │ ━━━━━━━━━━━━━━━━━━━━━━  │ │
│  │ 1              25        50│ │
│  │                           │ │
│  │ ☑ 预加载全部章节          │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │       [保存设置]          │ │
│  └───────────────────────────┘ │
└─────────────────────────────────┘
```

### 方案二：弹窗对话框

```
┌─────────────────────────────────┐
│  预加载设置                      │
├─────────────────────────────────┤
│  当前章节：                      │
│  ☑ 启用  预加载 [3▼] 页         │
│                                 │
│  下一章节：                      │
│  ☑ 启用  预加载 [全部▼]         │
│                                 │
│  [取消]              [保存]     │
└─────────────────────────────────┘
```

## 💻 代码实现

### 1. 创建设置页面组件

```typescript
// SourcePreloadSettingsPage.ets
import { DataManager } from '../Framework/Data/DataManager';
import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';

const TAG = 'SourcePreloadSettingsPage';

interface SourcePreloadSettingsParams {
  sourceId: number;
  sourceName: string;
}

@Entry
@Component
export struct SourcePreloadSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State pageParams: SourcePreloadSettingsParams | null = null;
  
  // 预加载设置
  @State preloadCurrentChapter: boolean = true;
  @State preloadCurrentPages: number = 3;
  @State preloadCurrentAll: boolean = false;
  
  @State preloadNextChapter: boolean = true;
  @State preloadNextPages: number = -1;
  @State preloadNextAll: boolean = true;
  
  @State isLoading: boolean = false;
  @State isSaving: boolean = false;
  
  async aboutToAppear() {
    // 获取页面参数
    this.pageParams = this.pathStack.getParamByName('SourcePreloadSettingsPage')[0] as SourcePreloadSettingsParams;
    
    if (this.pageParams) {
      await this.loadSettings();
    }
  }
  
  /**
   * 加载当前设置
   */
  private async loadSettings(): Promise<void> {
    if (!this.pageParams) return;
    
    try {
      this.isLoading = true;
      const dataManager = DataManager.getInstance();
      const sql = 'SELECT preloadCurrentChapter, preloadCurrentPages, preloadNextChapter, preloadNextPages FROM comic_source WHERE id = ?';
      const records = await dataManager.querySql(sql, [this.pageParams.sourceId]);
      
      if (records && records.length > 0) {
        const record = records[0] as Record<string, number>;
        this.preloadCurrentChapter = (record['preloadCurrentChapter'] || 1) === 1;
        this.preloadCurrentPages = record['preloadCurrentPages'] || 3;
        this.preloadNextChapter = (record['preloadNextChapter'] || 1) === 1;
        this.preloadNextPages = record['preloadNextPages'] || -1;
        
        // 更新UI状态
        this.preloadCurrentAll = this.preloadCurrentPages === -1;
        this.preloadNextAll = this.preloadNextPages === -1;
      }
    } catch (error) {
      logger.error(TAG, `加载预加载设置失败: ${String(error)}`);
      promptAction.showToast({ message: '加载设置失败' });
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.pageParams) return;
    
    try {
      this.isSaving = true;
      
      // 如果选择了"全部"，设置为-1
      const currentPages = this.preloadCurrentAll ? -1 : this.preloadCurrentPages;
      const nextPages = this.preloadNextAll ? -1 : this.preloadNextPages;
      
      const dataManager = DataManager.getInstance();
      await dataManager.updateSourcePreloadSettings(
        this.pageParams.sourceId,
        this.preloadCurrentChapter,
        currentPages,
        this.preloadNextChapter,
        nextPages
      );
      
      promptAction.showToast({ message: '设置已保存' });
      
      // 返回上一页
      setTimeout(() => {
        this.pathStack.pop();
      }, 500);
    } catch (error) {
      logger.error(TAG, `保存预加载设置失败: ${String(error)}`);
      promptAction.showToast({ message: '保存失败' });
    } finally {
      this.isSaving = false;
    }
  }
  
  build() {
    NavDestination() {
      Column() {
        // 顶部工具栏
        Row() {
          Button() {
            Image($r('app.media.ic_arrow_back'))
              .width(24)
              .height(24)
          }
          .onClick(() => this.pathStack.pop())
          
          Text('预加载设置')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .margin({ left: 16 })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 16 })
        
        if (this.isLoading) {
          // 加载中
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
            Text('加载中...')
              .margin({ top: 16 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 设置内容
          Scroll() {
            Column({ space: 24 }) {
              // 当前章节预加载
              Column({ space: 12 }) {
                Text('📖 当前章节预加载')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                
                Column({ space: 16 }) {
                  // 启用开关
                  Row() {
                    Text('启用预加载')
                    Toggle({ type: ToggleType.Switch, isOn: this.preloadCurrentChapter })
                      .onChange((isOn: boolean) => {
                        this.preloadCurrentChapter = isOn;
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween)
                  
                  if (this.preloadCurrentChapter) {
                    // 预加载全部选项
                    Row() {
                      Text('预加载全部章节')
                      Toggle({ type: ToggleType.Checkbox, isOn: this.preloadCurrentAll })
                        .onChange((isOn: boolean) => {
                          this.preloadCurrentAll = isOn;
                        })
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                    
                    if (!this.preloadCurrentAll) {
                      // 页数滑块
                      Column({ space: 8 }) {
                        Row() {
                          Text('预加载页数')
                          Text(`${this.preloadCurrentPages} 页`)
                            .fontColor($r('app.color.text_secondary'))
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceBetween)
                        
                        Slider({
                          value: this.preloadCurrentPages,
                          min: 1,
                          max: 20,
                          step: 1
                        })
                          .onChange((value: number) => {
                            this.preloadCurrentPages = Math.round(value);
                          })
                      }
                    }
                  }
                }
                .padding(16)
                .backgroundColor($r('app.color.background_secondary'))
                .borderRadius(8)
              }
              
              // 下一章节预加载
              Column({ space: 12 }) {
                Text('📚 下一章节预加载')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                
                Column({ space: 16 }) {
                  // 启用开关
                  Row() {
                    Text('启用预加载')
                    Toggle({ type: ToggleType.Switch, isOn: this.preloadNextChapter })
                      .onChange((isOn: boolean) => {
                        this.preloadNextChapter = isOn;
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween)
                  
                  if (this.preloadNextChapter) {
                    // 预加载全部选项
                    Row() {
                      Text('预加载全部章节')
                      Toggle({ type: ToggleType.Checkbox, isOn: this.preloadNextAll })
                        .onChange((isOn: boolean) => {
                          this.preloadNextAll = isOn;
                        })
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                    
                    if (!this.preloadNextAll) {
                      // 页数滑块
                      Column({ space: 8 }) {
                        Row() {
                          Text('预加载页数')
                          Text(`${this.preloadNextPages} 页`)
                            .fontColor($r('app.color.text_secondary'))
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceBetween)
                        
                        Slider({
                          value: this.preloadNextPages > 0 ? this.preloadNextPages : 25,
                          min: 1,
                          max: 50,
                          step: 1
                        })
                          .onChange((value: number) => {
                            this.preloadNextPages = Math.round(value);
                          })
                      }
                    }
                  }
                }
                .padding(16)
                .backgroundColor($r('app.color.background_secondary'))
                .borderRadius(8)
              }
              
              // 说明文字
              Text('提示：预加载可以提升阅读体验，但会增加流量消耗。建议在WiFi环境下使用。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8 })
            }
            .padding(16)
          }
          .layoutWeight(1)
          
          // 保存按钮
          Button(this.isSaving ? '保存中...' : '保存设置')
            .width('90%')
            .height(48)
            .margin({ bottom: 16 })
            .enabled(!this.isSaving)
            .onClick(() => this.saveSettings())
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
  }
}
```

### 2. 在图源管理页面添加入口

```typescript
// 在图源卡片中添加设置按钮
Button('预加载设置')
  .onClick(() => {
    this.pathStack.pushPathByName('SourcePreloadSettingsPage', {
      sourceId: source.id,
      sourceName: source.name
    });
  })
```

### 3. 注册路由

```typescript
// 在路由配置中添加
{
  name: 'SourcePreloadSettingsPage',
  pageSourceFile: 'src/main/ets/pages/SourcePreloadSettingsPage.ets',
  buildFunction: 'SourcePreloadSettingsPageBuilder'
}
```

## 🎯 功能要点

### 验证逻辑

```typescript
// 页数范围验证
private validatePageCount(pages: number, max: number): boolean {
  if (pages === -1) return true; // 全部
  if (pages === 0) return true;  // 不预加载
  return pages > 0 && pages <= max;
}

// 保存前验证
private validateSettings(): boolean {
  const currentPages = this.preloadCurrentAll ? -1 : this.preloadCurrentPages;
  const nextPages = this.preloadNextAll ? -1 : this.preloadNextPages;
  
  if (!this.validatePageCount(currentPages, 20)) {
    promptAction.showToast({ message: '当前章节预加载页数无效' });
    return false;
  }
  
  if (!this.validatePageCount(nextPages, 50)) {
    promptAction.showToast({ message: '下一章节预加载页数无效' });
    return false;
  }
  
  return true;
}
```

### 默认值处理

```typescript
// 首次打开时的默认值
private getDefaultSettings(): SourcePreloadSettings {
  return {
    preloadCurrentChapter: true,
    preloadCurrentPages: 3,
    preloadNextChapter: true,
    preloadNextPages: -1
  };
}
```

## 📱 用户体验优化

### 1. 实时预览

显示预加载策略的效果预览：
```
当前设置将会：
✓ 在阅读时自动预加载后续 3 页
✓ 在章节加载完成后立即预加载下一章节的全部页面
```

### 2. 流量提示

根据设置计算预估流量消耗：
```typescript
private estimateDataUsage(): string {
  const avgPageSize = 500; // KB
  const currentPages = this.preloadCurrentAll ? 20 : this.preloadCurrentPages;
  const nextPages = this.preloadNextAll ? 30 : this.preloadNextPages;
  
  const totalKB = (currentPages + nextPages) * avgPageSize;
  const totalMB = (totalKB / 1024).toFixed(1);
  
  return `预计每章消耗约 ${totalMB} MB 流量`;
}
```

### 3. 预设方案

提供快速选择：
```
[省流量模式]  当前:1页  下一章:关闭
[平衡模式]    当前:3页  下一章:全部
[激进模式]    当前:全部 下一章:全部
```

## 🧪 测试清单

- [ ] 设置页面正常打开
- [ ] 能正确加载当前设置
- [ ] 开关切换正常工作
- [ ] 滑块调整正常工作
- [ ] "全部"选项正常工作
- [ ] 保存成功并显示提示
- [ ] 保存后返回上一页
- [ ] 设置立即生效（重新打开阅读器）
- [ ] 错误处理正常（网络错误、数据库错误）
- [ ] 多个图源的设置互不影响

## 📚 相关文档

- [预加载功能实现总结.md](./预加载功能实现总结.md)
- DataManager API 文档
- DatabaseManager API 文档

---

**创建日期**: 2025-11-22  
**最后更新**: 2025-11-22 19:57  
**版本**: 1.0.0
