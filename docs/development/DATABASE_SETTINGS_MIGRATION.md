# 设置存储迁移到数据库

## 概述

将应用设置从PersistentStorage迁移到数据库存储，提供更可靠的持久化方案。

## 已完成的工作

### 1. 创建SettingsManager ✅

**文件**: `Framework/Managers/SettingsManager.ets`

**功能**:
- 单例模式管理所有应用设置
- 内存缓存提高性能
- 支持布尔、字符串、数字、JSON类型
- 自动同步到AppStorage

**关键方法**:
```typescript
// 读取设置
getBoolean(key: string, defaultValue: boolean): boolean
getString(key: string, defaultValue: string): string
getNumber(key: string, defaultValue: number): number
getJSON<T>(key: string, defaultValue: T): T

// 保存设置
async setBoolean(key: string, value: boolean): Promise<void>
async setString(key: string, value: string): Promise<void>
async setNumber(key: string, value: number): Promise<void>
async setJSON<T>(key: string, value: T): Promise<void>

// 同步到AppStorage
syncToAppStorage(): void
```

**设置键常量**:
```typescript
SettingKeys.ADVANCED_MODE_ENABLED
SettingKeys.ENABLE_LOG_FLOATING_WINDOW
SettingKeys.GLOBAL_READING_MODE
SettingKeys.GLOBAL_READING_DIRECTION
// ... 等等
```

### 2. 扩展DataManager ✅

**文件**: `Framework/Data/DataManager.ets`

**新增方法**:
```typescript
async getAllSettings(): Promise<UserSettingsDatabaseRecord[]>
async getSetting(key: string): Promise<UserSettingsDatabaseRecord | null>
async saveSetting(key: string, value: string, type: string): Promise<void>
async deleteSetting(key: string): Promise<void>
async clearAllSettings(): Promise<void>
```

### 3. 修改EntryAbility ✅

**文件**: `EntryAbility.ets`

**变更**:
- 导入SettingsManager
- 修改`initializeAppStorage()`为异步方法
- 使用SettingsManager初始化和同步设置

**新的初始化流程**:
```typescript
onCreate() {
  // 1. 初始化设置（从数据库加载）
  await this.initializeAppStorage();
  
  // 2. 设置已同步到AppStorage
  // 3. @StorageLink自动更新组件
}
```

## 待完成的工作

### 修改GlobalSettingsPage

需要将所有设置的保存逻辑改为使用SettingsManager。

#### 修改步骤

1. **导入SettingsManager**:
```typescript
import { SettingsManager, SettingKeys, SettingType } from '../Framework/Managers/SettingsManager';
```

2. **添加settingsManager实例**:
```typescript
private settingsManager: SettingsManager = SettingsManager.getInstance();
```

3. **修改loadGlobalSettings()**:
```typescript
private loadGlobalSettings(): void {
  try {
    // 从SettingsManager读取设置
    this.defaultReadingMode = this.settingsManager.getString(
      SettingKeys.GLOBAL_READING_MODE, 
      DEFAULT_READING_SETTINGS.readingMode
    );
    
    this.advancedModeEnabled = this.settingsManager.getBoolean(
      SettingKeys.ADVANCED_MODE_ENABLED, 
      false
    );
    
    // ... 其他设置
    
    logger.info(TAG, '全局设置加载完成');
  } catch (error) {
    logger.error(TAG, '加载全局设置失败', String(error));
  }
}
```

4. **修改saveGlobalSettings()**:
```typescript
private async saveGlobalSettings(): Promise<void> {
  try {
    // 保存到数据库
    await this.settingsManager.setString(
      SettingKeys.GLOBAL_READING_MODE, 
      this.defaultReadingMode
    );
    
    await this.settingsManager.setBoolean(
      SettingKeys.ADVANCED_MODE_ENABLED, 
      this.advancedModeEnabled
    );
    
    // ... 其他设置
    
    // 同步到AppStorage
    this.settingsManager.syncToAppStorage();
    
    logger.info(TAG, '全局设置保存成功');
  } catch (error) {
    logger.error(TAG, '保存全局设置失败', String(error));
  }
}
```

5. **修改Toggle的onChange**:
```typescript
Toggle({ type: ToggleType.Switch, isOn: this.advancedModeEnabled })
  .onChange(async (isOn: boolean) => {
    this.advancedModeEnabled = isOn;
    
    // 立即保存到数据库
    await this.settingsManager.setBoolean(
      SettingKeys.ADVANCED_MODE_ENABLED, 
      isOn
    );
    
    // 同步到AppStorage
    this.settingsManager.syncToAppStorage();
    
    // 显示重启提示
    this.showRestartDialog = true;
  })
```

6. **删除旧的AppStorage.setOrCreate调用**:
```typescript
// ❌ 删除这些
AppStorage.setOrCreate('advanced_mode_enabled', this.advancedModeEnabled);
AppStorage.setOrCreate('global_reading_mode', this.defaultReadingMode);

// ✅ 改用SettingsManager
await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, value);
```

### 修改MainMenuPage

MainMenuPage不需要修改，因为它使用`@StorageLink`，会自动从AppStorage读取。

SettingsManager的`syncToAppStorage()`会确保AppStorage中的值是最新的。

## 数据流程

### 应用启动

```
EntryAbility.onCreate()
  ↓
initializeAppStorage()
  ↓
SettingsManager.initialize()
  ↓
DataManager.getAllSettings()
  ↓
从数据库读取所有设置
  ↓
加载到SettingsManager缓存
  ↓
syncToAppStorage()
  ↓
AppStorage更新
  ↓
@StorageLink自动更新组件
```

### 用户修改设置

```
GlobalSettingsPage
  ↓
Toggle.onChange(value)
  ↓
settingsManager.setBoolean(key, value)
  ↓
更新内存缓存
  ↓
DataManager.saveSetting()
  ↓
保存到数据库
  ↓
syncToAppStorage()
  ↓
AppStorage更新
  ↓
@StorageLink自动更新其他组件
```

### 应用重启

```
EntryAbility.onCreate()
  ↓
SettingsManager.initialize()
  ↓
从数据库读取之前保存的设置
  ↓
同步到AppStorage
  ↓
MainMenuPage加载
  ↓
@StorageLink读取AppStorage
  ↓
图源按钮显示/隐藏正确
```

## 优势

### 相比PersistentStorage

1. **更可靠**: 数据库事务保证数据一致性
2. **更灵活**: 支持复杂查询和批量操作
3. **更强大**: 支持JSON等复杂类型
4. **更可控**: 可以手动管理数据库迁移

### 性能优化

1. **内存缓存**: SettingsManager使用Map缓存，减少数据库查询
2. **批量加载**: 启动时一次性加载所有设置
3. **异步保存**: 不阻塞UI线程

## 测试要点

### 功能测试

1. ✅ **首次启动**: 设置使用默认值
2. ✅ **修改设置**: 立即保存到数据库
3. ✅ **重启应用**: 设置正确恢复
4. ✅ **多次修改**: 每次都正确保存
5. ✅ **并发修改**: 数据一致性

### 数据库测试

1. ✅ **插入**: 新设置正确插入
2. ✅ **更新**: 现有设置正确更新
3. ✅ **查询**: 正确读取设置
4. ✅ **删除**: 正确删除设置

### UI测试

1. ✅ **开关同步**: Toggle状态与数据库一致
2. ✅ **立即生效**: 某些设置立即生效
3. ✅ **重启生效**: 某些设置重启后生效

## 数据库表结构

```sql
CREATE TABLE user_settings (
  id TEXT PRIMARY KEY,
  userId TEXT NOT NULL,
  settingKey TEXT NOT NULL,
  settingValue TEXT NOT NULL,
  settingType TEXT NOT NULL,
  description TEXT,
  createTime INTEGER NOT NULL,
  updateTime INTEGER NOT NULL,
  UNIQUE(userId, settingKey)
);
```

## 示例代码

### 保存布尔值设置

```typescript
await settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, true);
```

### 保存字符串设置

```typescript
await settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, 'single_page');
```

### 保存数字设置

```typescript
await settingsManager.setNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, 3);
```

### 读取设置

```typescript
const advancedMode = settingsManager.getBoolean(SettingKeys.ADVANCED_MODE_ENABLED, false);
const readingMode = settingsManager.getString(SettingKeys.GLOBAL_READING_MODE, 'single_page');
const maxDownloads = settingsManager.getNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, 3);
```

## 下一步

1. ✅ 修改GlobalSettingsPage使用SettingsManager
2. ✅ 测试所有设置的保存和读取
3. ✅ 验证重启后设置正确恢复
4. ✅ 确认图源页面显示/隐藏正常

---

**创建日期**: 2025-11-17  
**状态**: 进行中  
**优先级**: 高
