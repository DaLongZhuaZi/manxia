# 标注系统剩余内容任务计划与实施结果

## 目标
在不改动手写笔专项代码的前提下，先完成“非手写笔”剩余能力的工程闭环，重点保障：
- 标注数据完整备份。
- 标注数据可选恢复。
- 旧备份路径兼容恢复。

## 任务计划（非手写笔）

### T1. 备份模型扩展（P0）
- 任务：在备份数据结构中新增统一标注数据段（书签/划线/想法）。
- 状态：已完成。
- 结果：新增 `annotations.records`、`UnifiedAnnotationBackupItem`，并扩展备份选项 `includeAnnotations`。

### T2. 增强备份链路接入（P0）
- 任务：增强备份导出/恢复纳入统一标注，并支持冲突策略。
- 状态：已完成。
- 结果：
  - 导出：从 `unified_annotation` 表导出完整字段。
  - 恢复：根据 `skip/replace/merge` 策略恢复，`merge` 时保留较新记录。
  - 自动建表：恢复前确保 `unified_annotation` 表与索引存在。

### T3. 旧版备份链路兼容（P0）
- 任务：旧版 `BackupManager` 也支持统一标注导入导出。
- 状态：已完成。
- 结果：老格式备份同样可携带并恢复标注，避免历史备份路径丢数据。

### T4. 备份/恢复界面补齐（P0）
- 任务：在备份选项和恢复选项中展示“统一标注”开关与数量。
- 状态：已完成。
- 结果：
  - 备份弹窗新增“统一标注”选项，默认开启。
  - 恢复弹窗新增“统一标注（书签/划线/想法）”选项与数量展示。

### T5. 元数据统计补齐（P1）
- 任务：备份元数据中统计标注条数，便于用户识别备份完整性。
- 状态：已完成。
- 结果：`itemCounts.annotations` 已接入。

## 本次实际改动文件
- `entry/src/main/ets/Models/BackupModels.ets`
- `entry/src/main/ets/Framework/Managers/EnhancedBackupManager.ets`
- `entry/src/main/ets/Framework/Managers/BackupManager.ets`
- `entry/src/main/ets/components/backup/BackupOptionsDialog.ets`
- `entry/src/main/ets/components/backup/RestoreOptionsDialog.ets`

## 备份恢复纳管范围（当前）
- 书签（bookmark）
- 划线（highlight）
- 想法（thought）
- 字段范围：定位锚点、引用文本、样式 JSON、关联想法 ID、创建/更新时间

## 验收清单
- 新建标注后执行备份，备份文件中存在 `annotations.records`。
- 清空应用数据后恢复，灵感页可看到已恢复标注。
- 小说阅读器重新进入后，划线样式与想法内容与备份前一致。
- 旧格式备份恢复路径不报错，且可恢复标注数据（若备份中存在）。
