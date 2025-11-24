# 组件开发指南

本指南详细介绍如何在 RimWorld Framework 中开发自定义组件。

## 📋 目录

- [组件基础](#组件基础)
- [组件生命周期](#组件生命周期)
- [动画组件开发](#动画组件开发)
- [状态管理](#状态管理)
- [事件处理](#事件处理)
- [性能优化](#性能优化)
- [最佳实践](#最佳实践)

## 🏗️ 组件基础

### 基础组件结构

```typescript
@Component
export struct MyComponent {
  // 1. 属性声明
  @Prop title: string = '';
  @Prop @Watch('onDataChange') data: DataType[] = [];
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  
  // 2. 私有成员
  private componentId: string = '';
  private subscriptionIds: string[] = [];
  
  // 3. 生命周期方法
  aboutToAppear(): void {
    this.componentId = `component_${Date.now()}`;
    this.initializeComponent();
    this.subscribeToEvents();
  }
  
  aboutToDisappear(): void {
    this.cleanup();
    this.unsubscribeFromEvents();
  }
  
  // 4. 数据监听方法
  onDataChange(): void {
    this.processDataChange();
  }
  
  // 5. 私有方法
  private initializeComponent(): void {
    logger.lifecycle(`组件初始化: ${this.componentId}`);
  }
  
  private cleanup(): void {
    logger.lifecycle(`组件清理: ${this.componentId}`);
  }
  
  private subscribeToEvents(): void {
    const eventBus = EventBus.getInstance();
    const subscriptionId = eventBus.subscribe('DATA_UPDATE', (payload) => {
      this.handleDataUpdate(payload);
    });
    this.subscriptionIds.push(subscriptionId);
  }
  
  private unsubscribeFromEvents(): void {
    const eventBus = EventBus.getInstance();
    this.subscriptionIds.forEach(id => eventBus.unsubscribe(id));
    this.subscriptionIds = [];
  }
  
  // 6. 事件处理方法
  private handleDataUpdate(payload: DataUpdatePayload): void {
    this.isLoading = true;
    // 处理数据更新
    this.isLoading = false;
  }
  
  // 7. UI构建方法
  @Builder
  private buildHeader(): void {
    Row() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(50)
    .padding({ left: 16, right: 16 })
  }
  
  @Builder
  private buildContent(): void {
    if (this.isLoading) {
      this.buildLoadingState();
    } else if (this.errorMessage) {
      this.buildErrorState();
    } else {
      this.buildDataState();
    }
  }
  
  @Builder
  private buildLoadingState(): void {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.brand_primary'))
      
      Text('加载中...')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center)
  }
  
  @Builder
  private buildErrorState(): void {
    Column() {
      Image($r('app.media.icon_error'))
        .width(48)
        .height(48)
      
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor($r('app.color.color_error'))
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center)
  }
  
  @Builder
  private buildDataState(): void {
    List() {
      ForEach(this.data, (item: DataType, index: number) => {
        ListItem() {
          this.buildDataItem(item, index);
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  @Builder
  private buildDataItem(item: DataType, index: number): void {
    Row() {
      Text(item.name)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      
      Text(item.value.toString())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(() => this.onItemClick(item, index))
  }
  
  // 8. 主构建方法
  build() {
    Column() {
      this.buildHeader();
      Divider()
        .color($r('app.color.divider_primary'))
        .strokeWidth(1);
      this.buildContent();
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }
  
  // 9. 公共方法
  public refresh(): void {
    this.isLoading = true;
    // 刷新数据逻辑
  }
  
  public showError(message: string): void {
    this.errorMessage = message;
  }
  
  public clearError(): void {
    this.errorMessage = '';
  }
  
  // 10. 事件回调
  private onItemClick(item: DataType, index: number): void {
    logger.info('列表项点击', { item, index });
    // 处理点击事件
  }
}
```

## 🔄 组件生命周期

### 生命周期方法详解

```typescript
@Component
export struct LifecycleComponent {
  @State private lifecycleStage: string = 'created';
  
  // 1. 组件即将出现
  aboutToAppear(): void {
    this.lifecycleStage = 'appearing';
    logger.lifecycle('组件即将出现');
    
    // 初始化操作
    this.initializeData();
    this.setupEventListeners();
    this.startAnimations();
  }
  
  // 2. 组件即将消失
  aboutToDisappear(): void {
    this.lifecycleStage = 'disappearing';
    logger.lifecycle('组件即将消失');
    
    // 清理操作
    this.cleanupResources();
    this.removeEventListeners();
    this.stopAnimations();
  }
  
  // 3. 组件即将重用（仅在某些场景下调用）
  aboutToReuse(params: Record<string, Object>): void {
    logger.lifecycle('组件即将重用', params);
    
    // 重用时的初始化
    this.resetState();
    this.updateWithParams(params);
  }
  
  private initializeData(): void {
    // 数据初始化逻辑
  }
  
  private setupEventListeners(): void {
    // 事件监听器设置
  }
  
  private startAnimations(): void {
    // 启动动画
  }
  
  private cleanupResources(): void {
    // 资源清理
  }
  
  private removeEventListeners(): void {
    // 移除事件监听器
  }
  
  private stopAnimations(): void {
    // 停止动画
  }
  
  private resetState(): void {
    // 重置组件状态
  }
  
  private updateWithParams(params: Record<string, Object>): void {
    // 根据参数更新组件
  }
  
  build() {
    Column() {
      Text(`生命周期阶段: ${this.lifecycleStage}`)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
    }
  }
}
```

## 🎨 动画组件开发

### 继承 AnimatedComponent

```typescript
@Component
export struct MyAnimatedComponent extends AnimatedComponent {
  @State private scale: number = 0;
  @State private opacity: number = 0;
  @State private rotation: number = 0;
  
  aboutToAppear(): void {
    super.aboutToAppear();
    this.startEntryAnimation();
  }
  
  private startEntryAnimation(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      logger.error('无法获取UIContext');
      return;
    }
    
    // 入场动画序列
    this.animateEntry(uiContext);
  }
  
  private animateEntry(uiContext: UIContext): void {
    // 第一阶段：缩放和透明度
    uiContext.animateTo({
      duration: 300,
      curve: Curve.EaseOut,
      delay: 0
    }, () => {
      this.scale = 1;
      this.opacity = 1;
    });
    
    // 第二阶段：旋转（延迟执行）
    setTimeout(() => {
      uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseInOut
      }, () => {
        this.rotation = 360;
      });
    }, 300);
  }
  
  // 自定义动画方法
  public playBounceAnimation(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) return;
    
    uiContext.animateTo({
      duration: 600,
      curve: Curve.Bounce
    }, () => {
      this.scale = 1.2;
    });
    
    setTimeout(() => {
      uiContext.animateTo({
        duration: 300,
        curve: Curve.EaseOut
      }, () => {
        this.scale = 1;
      });
    }, 600);
  }
  
  public playShakeAnimation(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) return;
    
    const shakeSequence = [10, -10, 8, -8, 6, -6, 4, -4, 2, -2, 0];
    let index = 0;
    
    const shake = () => {
      if (index < shakeSequence.length) {
        uiContext.animateTo({
          duration: 50,
          curve: Curve.Linear
        }, () => {
          this.rotation = shakeSequence[index];
        });
        index++;
        setTimeout(shake, 50);
      }
    };
    
    shake();
  }
  
  build() {
    Column() {
      // 组件内容
      Text('动画组件')
        .fontSize(18)
        .fontColor($r('app.color.text_primary'))
      
      Row() {
        AnimatedButton({
          text: '弹跳动画',
          onClick: () => this.playBounceAnimation()
        })
        
        AnimatedButton({
          text: '摇摆动画',
          onClick: () => this.playShakeAnimation()
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 20 })
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center)
    .scale({ x: this.scale, y: this.scale })
    .opacity(this.opacity)
    .rotate({ angle: this.rotation })
  }
}
```

### 自定义动画组件

```typescript
@Component
export struct CustomAnimatedButton {
  @Prop text: string = '';
  @Prop onClick: () => void = () => {};
  @State private isPressed: boolean = false;
  @State private scale: number = 1;
  @State private backgroundColor: ResourceColor = $r('app.color.brand_primary');
  
  private pressAnimation(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) return;
    
    uiContext.animateTo({
      duration: 100,
      curve: Curve.EaseOut
    }, () => {
      this.scale = 0.95;
      this.backgroundColor = $r('app.color.brand_secondary');
    });
  }
  
  private releaseAnimation(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) return;
    
    uiContext.animateTo({
      duration: 150,
      curve: Curve.EaseOut
    }, () => {
      this.scale = 1;
      this.backgroundColor = $r('app.color.brand_primary');
    });
  }
  
  build() {
    Text(this.text)
      .fontSize(16)
      .fontColor($r('app.color.text_primary'))
      .textAlign(TextAlign.Center)
      .width(120)
      .height(40)
      .backgroundColor(this.backgroundColor)
      .borderRadius(8)
      .scale({ x: this.scale, y: this.scale })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.isPressed = true;
          this.pressAnimation();
        } else if (event.type === TouchType.Up) {
          this.isPressed = false;
          this.releaseAnimation();
          this.onClick();
        }
      })
  }
}
```

## 📊 状态管理

### 状态装饰器使用

```typescript
@Component
export struct StateManagementComponent {
  // 1. 本地状态
  @State private count: number = 0;
  @State private isVisible: boolean = true;
  @State private items: DataItem[] = [];
  
  // 2. 属性传递
  @Prop title: string = '';
  @Prop @Watch('onConfigChange') config: ComponentConfig = new ComponentConfig();
  
  // 3. 双向绑定
  @Link selectedIndex: number;
  
  // 4. 全局状态
  @StorageProp('theme') theme: string = 'light';
  @StorageLink('userPreferences') userPreferences: UserPreferences = new UserPreferences();
  
  // 5. 提供状态
  @Provide('sharedData') sharedData: SharedData = new SharedData();
  
  // 6. 消费状态
  @Consume('parentData') parentData: ParentData;
  
  // 状态变化监听
  onConfigChange(): void {
    logger.info('配置变化', this.config);
    this.updateComponentWithConfig();
  }
  
  private updateComponentWithConfig(): void {
    // 根据配置更新组件
  }
  
  // 状态更新方法
  private incrementCount(): void {
    this.count++;
    logger.stateChange('计数器更新', { newValue: this.count });
  }
  
  private toggleVisibility(): void {
    this.isVisible = !this.isVisible;
    logger.stateChange('可见性切换', { isVisible: this.isVisible });
  }
  
  private addItem(item: DataItem): void {
    this.items.push(item);
    logger.stateChange('添加项目', { itemCount: this.items.length });
  }
  
  private removeItem(index: number): void {
    if (index >= 0 && index < this.items.length) {
      const removedItem = this.items.splice(index, 1)[0];
      logger.stateChange('移除项目', { removedItem, itemCount: this.items.length });
    }
  }
  
  build() {
    Column() {
      Text(`计数: ${this.count}`)
        .fontSize(18)
        .fontColor($r('app.color.text_primary'))
      
      Row() {
        Button('增加')
          .onClick(() => this.incrementCount())
        
        Button('切换显示')
          .onClick(() => this.toggleVisibility())
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      
      if (this.isVisible) {
        List() {
          ForEach(this.items, (item: DataItem, index: number) => {
            ListItem() {
              Row() {
                Text(item.name)
                  .layoutWeight(1)
                
                Button('删除')
                  .onClick(() => this.removeItem(index))
              }
              .width('100%')
              .padding(8)
            }
          })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
```

## 🎯 事件处理

### 事件处理最佳实践

```typescript
@Component
export struct EventHandlingComponent {
  @State private inputValue: string = '';
  @State private selectedItems: number[] = [];
  
  // 输入事件处理
  private onInputChange(value: string): void {
    this.inputValue = value;
    logger.info('输入变化', { value });
    
    // 防抖处理
    this.debounceSearch(value);
  }
  
  private debounceTimer: number = -1;
  private debounceSearch(value: string): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
    }
    
    this.debounceTimer = setTimeout(() => {
      this.performSearch(value);
    }, 300);
  }
  
  private performSearch(value: string): void {
    logger.info('执行搜索', { query: value });
    // 搜索逻辑
  }
  
  // 点击事件处理
  private onItemClick(index: number): void {
    const isSelected = this.selectedItems.includes(index);
    
    if (isSelected) {
      this.selectedItems = this.selectedItems.filter(i => i !== index);
    } else {
      this.selectedItems.push(index);
    }
    
    logger.info('项目选择变化', { 
      index, 
      isSelected: !isSelected, 
      selectedCount: this.selectedItems.length 
    });
  }
  
  // 长按事件处理
  private onItemLongPress(index: number): void {
    logger.info('项目长按', { index });
    
    // 显示上下文菜单
    this.showContextMenu(index);
  }
  
  private showContextMenu(index: number): void {
    // 上下文菜单逻辑
  }
  
  // 手势事件处理
  private onPanGesture(event: GestureEvent): void {
    logger.info('拖拽手势', { 
      offsetX: event.offsetX, 
      offsetY: event.offsetY 
    });
  }
  
  // 键盘事件处理
  private onKeyEvent(event: KeyEvent): void {
    if (event.type === KeyType.Down) {
      switch (event.keyCode) {
        case KeyCode.KEYCODE_ENTER:
          this.onEnterPressed();
          break;
        case KeyCode.KEYCODE_ESCAPE:
          this.onEscapePressed();
          break;
        default:
          break;
      }
    }
  }
  
  private onEnterPressed(): void {
    logger.info('回车键按下');
    // 处理回车逻辑
  }
  
  private onEscapePressed(): void {
    logger.info('ESC键按下');
    // 处理ESC逻辑
  }
  
  build() {
    Column() {
      TextInput({ placeholder: '输入搜索内容' })
        .width('100%')
        .onChange((value: string) => this.onInputChange(value))
        .onKeyEvent((event: KeyEvent) => this.onKeyEvent(event))
      
      List() {
        ForEach([1, 2, 3, 4, 5], (item: number, index: number) => {
          ListItem() {
            Text(`项目 ${item}`)
              .width('100%')
              .height(48)
              .textAlign(TextAlign.Center)
              .backgroundColor(
                this.selectedItems.includes(index) 
                  ? $r('app.color.brand_secondary') 
                  : $r('app.color.background_secondary')
              )
          }
          .onClick(() => this.onItemClick(index))
          .onLongPress(() => this.onItemLongPress(index))
          .gesture(
            PanGesture()
              .onActionUpdate((event: GestureEvent) => this.onPanGesture(event))
          )
        })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
```

## ⚡ 性能优化

### 组件性能优化技巧

```typescript
@Component
export struct OptimizedComponent {
  @State private data: LargeDataSet[] = [];
  @State private visibleRange: { start: number, end: number } = { start: 0, end: 20 };
  
  // 1. 使用 LazyForEach 优化长列表
  @Builder
  private buildOptimizedList(): void {
    List() {
      LazyForEach(this.getDataSource(), (item: LargeDataSet, index: number) => {
        ListItem() {
          this.buildListItem(item, index);
        }
        .reuseId(`item_${item.type}`) // 设置重用ID
      })
    }
    .width('100%')
    .height('100%')
    .onScrollIndex((start: number, end: number) => {
      this.updateVisibleRange(start, end);
    })
  }
  
  private getDataSource(): IDataSource {
    return new LazyDataSource(this.data);
  }
  
  private updateVisibleRange(start: number, end: number): void {
    this.visibleRange = { start, end };
    // 只处理可见范围内的数据
  }
  
  // 2. 组件重用优化
  @Builder
  private buildListItem(item: LargeDataSet, index: number): void {
    Row() {
      // 使用条件渲染减少不必要的组件创建
      if (this.isItemVisible(index)) {
        this.buildItemContent(item);
      } else {
        this.buildPlaceholder();
      }
    }
    .width('100%')
    .height(60)
  }
  
  private isItemVisible(index: number): boolean {
    return index >= this.visibleRange.start && index <= this.visibleRange.end;
  }
  
  @Builder
  private buildItemContent(item: LargeDataSet): void {
    Column() {
      Text(item.title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      
      Text(item.description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }
  
  @Builder
  private buildPlaceholder(): void {
    Row()
      .width('100%')
      .height(60)
      .backgroundColor($r('app.color.background_secondary'))
  }
  
  // 3. 防抖和节流
  private searchTimer: number = -1;
  private onSearchInput(value: string): void {
    // 防抖搜索
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    
    this.searchTimer = setTimeout(() => {
      this.performSearch(value);
    }, 300);
  }
  
  private scrollTimer: number = -1;
  private onScroll(offset: number): void {
    // 节流滚动处理
    if (this.scrollTimer !== -1) {
      return;
    }
    
    this.scrollTimer = setTimeout(() => {
      this.handleScroll(offset);
      this.scrollTimer = -1;
    }, 16); // 60fps
  }
  
  private performSearch(value: string): void {
    // 搜索实现
  }
  
  private handleScroll(offset: number): void {
    // 滚动处理
  }
  
  // 4. 内存管理
  aboutToDisappear(): void {
    // 清理定时器
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
    }
    
    // 清理大数据
    this.data = [];
  }
  
  build() {
    Column() {
      this.buildOptimizedList();
    }
    .width('100%')
    .height('100%')
  }
}

// 懒加载数据源实现
class LazyDataSource implements IDataSource {
  private data: LargeDataSet[];
  
  constructor(data: LargeDataSet[]) {
    this.data = data;
  }
  
  totalCount(): number {
    return this.data.length;
  }
  
  getData(index: number): LargeDataSet {
    return this.data[index];
  }
  
  registerDataChangeListener(listener: DataChangeListener): void {
    // 注册数据变化监听器
  }
  
  unregisterDataChangeListener(listener: DataChangeListener): void {
    // 取消注册数据变化监听器
  }
}
```

## 🎯 最佳实践

### 1. 组件设计原则

- **单一职责**: 每个组件只负责一个功能
- **可复用性**: 设计通用的、可配置的组件
- **可测试性**: 组件逻辑应该易于测试
- **性能优先**: 考虑渲染性能和内存使用

### 2. 代码组织

```typescript
// 文件结构示例
components/
├── common/              # 通用组件
│   ├── Button/
│   │   ├── AnimatedButton.ets
│   │   ├── IconButton.ets
│   │   └── index.ets
│   ├── Input/
│   └── Modal/
├── business/            # 业务组件
│   ├── UserProfile/
│   ├── GameBoard/
│   └── InventoryList/
└── layout/              # 布局组件
    ├── Header/
    ├── Sidebar/
    └── Footer/
```

### 3. 错误处理

```typescript
@Component
export struct ErrorHandlingComponent {
  @State private error: Error | null = null;
  @State private isLoading: boolean = false;
  
  private async loadData(): Promise<void> {
    try {
      this.isLoading = true;
      this.error = null;
      
      const data = await this.fetchData();
      this.processData(data);
      
    } catch (error) {
      this.error = error as Error;
      logger.error('数据加载失败', error);
    } finally {
      this.isLoading = false;
    }
  }
  
  private async fetchData(): Promise<DataType> {
    // 数据获取逻辑
    throw new Error('模拟错误');
  }
  
  private processData(data: DataType): void {
    // 数据处理逻辑
  }
  
  @Builder
  private buildErrorState(): void {
    Column() {
      Image($r('app.media.icon_error'))
        .width(48)
        .height(48)
      
      Text(this.error?.message || '未知错误')
        .fontSize(14)
        .fontColor($r('app.color.color_error'))
        .margin({ top: 8 })
      
      Button('重试')
        .margin({ top: 16 })
        .onClick(() => this.loadData())
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center)
  }
  
  build() {
    Column() {
      if (this.error) {
        this.buildErrorState();
      } else if (this.isLoading) {
        // 加载状态
      } else {
        // 正常状态
      }
    }
  }
}
```

### 4. 测试友好的组件设计

```typescript
@Component
export struct TestableComponent {
  @Prop testId?: string; // 测试ID
  @State private internalState: string = '';
  
  // 提供测试接口
  public getInternalState(): string {
    return this.internalState;
  }
  
  public setInternalState(state: string): void {
    this.internalState = state;
  }
  
  build() {
    Column() {
      Text(this.internalState)
        .id(this.testId ? `${this.testId}_text` : undefined)
      
      Button('更新状态')
        .id(this.testId ? `${this.testId}_button` : undefined)
        .onClick(() => {
          this.internalState = '已更新';
        })
    }
    .id(this.testId)
  }
}
```

---

*最后更新: 2024年12月*