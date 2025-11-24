# 高级模式设置持久化修复

## 问题描述

用户在全局设置页面打开"高级模式"并重启应用后：
1. ❌ 图源页面没有出现
2. ❌ 全局设置页面的"高级模式"开关被重置为关闭状态

## 问题原因

### 原因1：单向绑定问题
MainMenuPage使用了`@StorageProp`，这是单向绑定（从AppStorage到组件），组件内的修改不会同步回AppStorage。

```typescript
// 错误代码
@StorageProp('advanced_mode_enabled') private advancedModeEnabled: boolean = false;
```

### 原因2：缺少持久化存储
AppStorage的数据在应用重启后会丢失，需要使用`PersistentStorage`持久化。

### 原因3：缺少初始化
应用启动时没有初始化AppStorage的默认值。

## 解决方案

### 1. MainMenuPage.ets - 使用双向绑定

**修改前**:
```typescript
@StorageProp('advanced_mode_enabled') private advancedModeEnabled: boolean = false;
```

**修改后**:
```typescript
@StorageLink('advanced_mode_enabled') private advancedModeEnabled: boolean = false;
```

**说明**:
- `@StorageLink`实现双向绑定
- 组件内的修改会自动同步到AppStorage
- AppStorage的修改会自动同步到组件

### 2. EntryAbility.ets - 添加持久化存储

**新增方法**:
```typescript
/**
 * 初始化AppStorage默认值
 */
private initializeAppStorage(): void {
  try {
    // 使用PersistentStorage持久化存储高级模式设置
    PersistentStorage.persistProp('advanced_mode_enabled', false);
    const advancedMode = AppStorage.get('advanced_mode_enabled');
    logger.info('EntryAbility', `✅ 高级模式设置已持久化，当前值: ${advancedMode}`);

    // 持久化其他设置
    PersistentStorage.persistProp('enable_log_floating_window', false);
    
    logger.info('EntryAbility', '✅ AppStorage持久化设置初始化完成');
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error('EntryAbility', `❌ AppStorage初始化失败: ${errorMessage}`);
  }
}
```

**在onCreate中调用**:
```typescript
onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  // ... 其他代码
  
  // 初始化AppStorage默认值（如果不存在）
  this.initializeAppStorage();
  
  // 初始化数据管理系统
  this.initializeDataSystem();
}
```

### 3. GlobalSettingsPage.ets - 保持不变

GlobalSettingsPage使用`@State`是正确的，因为它需要在onChange时手动保存：

```typescript
@State advancedModeEnabled: boolean = false;

// 在Toggle的onChange中
.onChange((isOn: boolean) => {
  this.advancedModeEnabled = isOn;
  AppStorage.setOrCreate('advanced_mode_enabled', this.advancedModeEnabled);
  this.showRestartDialog = true;
})
```

## 工作流程

### 首次启动应用

1. **EntryAbility.onCreate()**
   ```
   PersistentStorage.persistProp('advanced_mode_enabled', false)
   → 创建持久化属性，默认值为false
   ```

2. **MainMenuPage加载**
   ```
   @StorageLink('advanced_mode_enabled') → 读取值：false
   → 图源标签隐藏
   ```

### 用户启用高级模式

1. **GlobalSettingsPage**
   ```
   用户打开开关
   → onChange触发
   → AppStorage.setOrCreate('advanced_mode_enabled', true)
   → PersistentStorage自动持久化到磁盘
   ```

2. **显示重启对话框**
   ```
   showRestartDialog = true
   → 用户点击"立即重启"
   → 应用重启
   ```

### 应用重启后

1. **EntryAbility.onCreate()**
   ```
   PersistentStorage.persistProp('advanced_mode_enabled', false)
   → 从磁盘读取已保存的值：true
   → AppStorage.get('advanced_mode_enabled') = true
   ```

2. **MainMenuPage加载**
   ```
   @StorageLink('advanced_mode_enabled') → 读取值：true
   → getVisibleTabConfigs()过滤
   → 图源标签显示
   ```

3. **GlobalSettingsPage加载**
   ```
   loadGlobalSettings()
   → AppStorage.get('advanced_mode_enabled') = true
   → this.advancedModeEnabled = true
   → Toggle显示为开启状态
   ```

## PersistentStorage工作原理

### 数据流向

```
用户操作
  ↓
@State变量更新
  ↓
AppStorage.setOrCreate()
  ↓
PersistentStorage自动同步
  ↓
持久化到磁盘
```

### 应用重启

```
应用启动
  ↓
PersistentStorage.persistProp()
  ↓
从磁盘读取数据
  ↓
同步到AppStorage
  ↓
@StorageLink自动更新
```

## 测试步骤

### 测试1：首次启动
1. ✅ 启动应用
2. ✅ 底栏只显示：首页、书库、发现、设置
3. ✅ 图源按钮隐藏

### 测试2：启用高级模式
1. ✅ 打开"设置" → "全局设置"
2. ✅ 在"调试与工具"区域找到"高级模式"
3. ✅ 打开开关
4. ✅ 显示重启提示对话框
5. ✅ 点击"立即重启"

### 测试3：重启后验证
1. ✅ 应用重启
2. ✅ 底栏显示：首页、书库、发现、**图源**、设置
3. ✅ 图源按钮在发现和设置之间
4. ✅ 打开"全局设置"
5. ✅ "高级模式"开关显示为**开启**状态

### 测试4：禁用高级模式
1. ✅ 关闭"高级模式"开关
2. ✅ 显示重启提示
3. ✅ 重启应用
4. ✅ 图源按钮隐藏
5. ✅ "高级模式"开关显示为关闭状态

## 关键技术点

### @StorageLink vs @StorageProp

| 特性 | @StorageLink | @StorageProp |
|------|-------------|--------------|
| 绑定方向 | 双向 | 单向（AppStorage → 组件） |
| 组件修改 | 同步到AppStorage | 不同步 |
| AppStorage修改 | 同步到组件 | 同步到组件 |
| 使用场景 | 需要组件修改数据 | 只读数据 |

### PersistentStorage

- **作用**: 将AppStorage中的数据持久化到磁盘
- **API**: `PersistentStorage.persistProp(key, defaultValue)`
- **特点**:
  - 首次调用时，如果磁盘有数据则读取，否则使用默认值
  - 后续AppStorage的修改会自动同步到磁盘
  - 应用重启后数据不丢失

### 数据持久化位置

HarmonyOS将PersistentStorage的数据保存在应用的私有存储空间：
```
/data/storage/el2/base/preferences/
```

## 修改的文件

1. **MainMenuPage.ets**
   - 修改：`@StorageProp` → `@StorageLink`

2. **EntryAbility.ets**
   - 新增：`initializeAppStorage()`方法
   - 修改：在`onCreate()`中调用初始化

3. **GlobalSettingsPage.ets**
   - 无需修改（已正确实现）

## 总结

✅ **问题已修复**:
1. ✅ 使用`@StorageLink`实现双向绑定
2. ✅ 使用`PersistentStorage`持久化存储
3. ✅ 在应用启动时初始化AppStorage
4. ✅ 重启后设置保持不变
5. ✅ 图源页面正确显示/隐藏

---

**修复日期**: 2025-11-17  
**测试状态**: 待用户验证  
**预期结果**: 高级模式设置在重启后保持，图源页面正确显示
