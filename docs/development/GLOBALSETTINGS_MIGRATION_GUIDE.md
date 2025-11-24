# GlobalSettingsPage迁移指南

## 已完成

1. ✅ 导入SettingsManager
2. ✅ 添加settingsManager实例

## 需要修改的方法

### 1. loadGlobalSettings()

**原代码** (第153-189行):
```typescript
private loadGlobalSettings(): void {
  try {
    const savedMode = AppStorage.get<ReadingMode>('global_reading_mode');
    if (savedMode) {
      this.defaultReadingMode = savedMode;
    }
    // ... 其他设置
  }
}
```

**新代码**:
```typescript
private loadGlobalSettings(): void {
  try {
    // 从SettingsManager读取设置
    this.defaultReadingMode = this.settingsManager.getString(
      SettingKeys.GLOBAL_READING_MODE, 
      DEFAULT_READING_SETTINGS.readingMode
    ) as ReadingMode;
    
    this.defaultReadingDirection = this.settingsManager.getString(
      SettingKeys.GLOBAL_READING_DIRECTION,
      DEFAULT_READING_SETTINGS.readingDirection
    ) as ReadingDirection;
    
    this.defaultBrightness = this.settingsManager.getNumber(
      SettingKeys.GLOBAL_BRIGHTNESS,
      DEFAULT_READING_SETTINGS.brightness
    );
    
    this.keepScreenOn = this.settingsManager.getBoolean(
      SettingKeys.GLOBAL_KEEP_SCREEN_ON,
      DEFAULT_READING_SETTINGS.keepScreenOn
    );
    
    this.volumeKeyNavigation = this.settingsManager.getBoolean(
      SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION,
      DEFAULT_READING_SETTINGS.volumeKeyNavigation
    );
    
    this.downloadOnWifiOnly = this.settingsManager.getBoolean(
      SettingKeys.DOWNLOAD_WIFI_ONLY,
      true
    );
    
    this.maxConcurrentDownloads = this.settingsManager.getNumber(
      SettingKeys.MAX_CONCURRENT_DOWNLOADS,
      3
    );
    
    this.enableDownloadNotifications = this.settingsManager.getBoolean(
      SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS,
      true
    );
    
    this.enableUpdateNotifications = this.settingsManager.getBoolean(
      SettingKeys.ENABLE_UPDATE_NOTIFICATIONS,
      true
    );
    
    this.autoCheckUpdates = this.settingsManager.getBoolean(
      SettingKeys.AUTO_CHECK_UPDATES,
      true
    );
    
    this.clearCacheOnExit = this.settingsManager.getBoolean(
      SettingKeys.CLEAR_CACHE_ON_EXIT,
      false
    );
    
    this.enableLogFloatingWindow = this.settingsManager.getBoolean(
      SettingKeys.ENABLE_LOG_FLOATING_WINDOW,
      false
    );
    
    this.advancedModeEnabled = this.settingsManager.getBoolean(
      SettingKeys.ADVANCED_MODE_ENABLED,
      false
    );

    logger.info(TAG, '全局设置加载完成');
  } catch (error) {
    logger.error(TAG, '加载全局设置失败', String(error));
  }
}
```

### 2. saveGlobalSettings()

**原代码** (第195-217行):
```typescript
private saveGlobalSettings(): void {
  try {
    AppStorage.setOrCreate('global_reading_mode', this.defaultReadingMode);
    // ... 其他设置
  }
}
```

**新代码**:
```typescript
private async saveGlobalSettings(): Promise<void> {
  try {
    await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
    await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
    await this.settingsManager.setNumber(SettingKeys.GLOBAL_BRIGHTNESS, this.defaultBrightness);
    await this.settingsManager.setBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, this.keepScreenOn);
    await this.settingsManager.setBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, this.volumeKeyNavigation);
    await this.settingsManager.setBoolean(SettingKeys.DOWNLOAD_WIFI_ONLY, this.downloadOnWifiOnly);
    await this.settingsManager.setNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, this.maxConcurrentDownloads);
    await this.settingsManager.setBoolean(SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS, this.enableDownloadNotifications);
    await this.settingsManager.setBoolean(SettingKeys.ENABLE_UPDATE_NOTIFICATIONS, this.enableUpdateNotifications);
    await this.settingsManager.setBoolean(SettingKeys.AUTO_CHECK_UPDATES, this.autoCheckUpdates);
    await this.settingsManager.setBoolean(SettingKeys.CLEAR_CACHE_ON_EXIT, this.clearCacheOnExit);
    await this.settingsManager.setBoolean(SettingKeys.ENABLE_LOG_FLOATING_WINDOW, this.enableLogFloatingWindow);
    await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, this.advancedModeEnabled);

    // 同步到AppStorage
    this.settingsManager.syncToAppStorage();

    logger.info(TAG, '全局设置保存成功');
  } catch (error) {
    logger.error(TAG, '保存全局设置失败', String(error));
  }
}
```

### 3. 修改所有Toggle的onChange

**高级模式开关** (第638-645行):
```typescript
// 原代码
Toggle({ type: ToggleType.Switch, isOn: this.advancedModeEnabled })
  .onChange((isOn: boolean) => {
    this.advancedModeEnabled = isOn;
    AppStorage.setOrCreate('advanced_mode_enabled', this.advancedModeEnabled);
    this.showRestartDialog = true;
  })

// 新代码
Toggle({ type: ToggleType.Switch, isOn: this.advancedModeEnabled })
  .onChange(async (isOn: boolean) => {
    this.advancedModeEnabled = isOn;
    await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, isOn);
    this.settingsManager.syncToAppStorage();
    this.showRestartDialog = true;
  })
```

**日志悬浮窗开关** (第663-668行):
```typescript
// 原代码
Toggle({ type: ToggleType.Switch, isOn: this.enableLogFloatingWindow })
  .onChange((isOn: boolean) => {
    this.enableLogFloatingWindow = isOn;
    AppStorage.setOrCreate('enable_log_floating_window', this.enableLogFloatingWindow);
  })

// 新代码
Toggle({ type: ToggleType.Switch, isOn: this.enableLogFloatingWindow })
  .onChange(async (isOn: boolean) => {
    this.enableLogFloatingWindow = isOn;
    await this.settingsManager.setBoolean(SettingKeys.ENABLE_LOG_FLOATING_WINDOW, isOn);
    this.settingsManager.syncToAppStorage();
  })
```

### 4. 修改阅读模式按钮的onClick

**单页模式** (第252-255行):
```typescript
// 原代码
.onClick(() => {
  this.defaultReadingMode = ReadingMode.SINGLE_PAGE;
  AppStorage.setOrCreate('global_reading_mode', this.defaultReadingMode);
})

// 新代码
.onClick(async () => {
  this.defaultReadingMode = ReadingMode.SINGLE_PAGE;
  await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
  this.settingsManager.syncToAppStorage();
})
```

**其他模式同理修改**

## 完整修改清单

### 需要删除的代码

所有`AppStorage.setOrCreate()`调用都应该删除，改用`settingsManager.setXXX()`

### 需要添加的代码

1. 所有保存操作后添加：
```typescript
this.settingsManager.syncToAppStorage();
```

2. 所有onClick和onChange改为async:
```typescript
.onClick(async () => { ... })
.onChange(async (value) => { ... })
```

## 测试步骤

1. ✅ 修改设置并保存
2. ✅ 重启应用
3. ✅ 验证设置正确恢复
4. ✅ 检查数据库中的数据

## SQL查询验证

```sql
-- 查看所有设置
SELECT * FROM user_settings WHERE userId = 'default_user';

-- 查看高级模式设置
SELECT * FROM user_settings WHERE settingKey = 'advanced_mode_enabled';
```

---

**状态**: 待实施  
**优先级**: 高
