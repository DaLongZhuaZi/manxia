# 凭据登录对话框编译错误修复

## 问题描述

在实现`CredentialLoginDialog.ets`时遇到了7个编译错误：

1. **颜色资源错误** (5个)
   - `comp_divider` 不在允许的颜色类型中
   - `text_tertiary` 不在允许的颜色类型中

2. **图标资源错误** (2个)
   - `ohos_ic_public_view` 系统图标不存在
   - `ohos_ic_public_view_off` 系统图标不存在

## 修复方案

### 1. 添加缺失的颜色类型

**文件**: `entry/src/main/ets/Framework/Components/ThemeAware.ets`

#### 修改内容

在`getTestManagementThemedColor`方法的颜色类型定义中添加：

```typescript
'comp_divider' | 'text_tertiary'
```

在颜色映射表中添加：

```typescript
'comp_divider': { 
  light: 'test_management_divider_light', 
  dark: 'test_management_divider_dark' 
},
'text_tertiary': { 
  light: 'test_management_text_placeholder_light', 
  dark: 'test_management_text_placeholder_dark' 
}
```

#### 映射说明

- **comp_divider**: 映射到现有的`divider`颜色资源
- **text_tertiary**: 映射到现有的`text_placeholder`颜色资源

### 2. 修复图标资源

**文件**: `entry/src/main/ets/Framework/Components/CredentialLoginDialog.ets`

#### 修改内容

将不存在的系统图标替换为正确的符号图标：

**修改前**:
```typescript
Image(this.showPassword ? $r('sys.media.ohos_ic_public_view') : $r('sys.media.ohos_ic_public_view_off'))
```

**修改后**:
```typescript
Image(this.showPassword ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
```

#### 图标说明

- **sys.symbol.eye**: 显示密码图标（眼睛）
- **sys.symbol.eye_slash**: 隐藏密码图标（带斜线的眼睛）

这些是HarmonyOS系统提供的符号图标，无需额外资源文件。

## 验证结果

修复后，所有7个编译错误已解决：

✅ `comp_divider` 颜色类型已添加  
✅ `text_tertiary` 颜色类型已添加  
✅ 密码显示/隐藏图标已修复  

## 相关文件

- `entry/src/main/ets/Framework/Components/ThemeAware.ets`
- `entry/src/main/ets/Framework/Components/CredentialLoginDialog.ets`

## 注意事项

1. **颜色复用**: 新增的颜色类型复用了现有的颜色资源，保持了一致性
2. **图标兼容**: 使用系统符号图标，确保跨平台兼容性
3. **向后兼容**: 修改不影响现有代码，只是扩展了颜色类型定义

## 测试建议

1. 在亮色主题下测试对话框显示
2. 在暗色主题下测试对话框显示
3. 测试密码显示/隐藏功能
4. 验证分隔线和占位符文本颜色正确显示
