# 漫匣 HAR 模块化 — 权威文件→模块清单（v1）

> 生成：2026-08-20 13:40｜以磁盘实际位置为准（真值）。

## 各模块 ets 文件数
- entry: 688
- manxia_core: 96
- manxia_source_engine: 34
- manxia_network: 25
- manxia_novel: 26
- manxia_theme: 12

## 校验结论
- 无跨模块相同相对路径（真重复=0）；编译通过（HAP 14:17）。
- Duplicate file names 警告 = hvigor 多模块合并的评审型提示（同名 basename 跨模块），非致命。
- 阶段 result JSON 的 moved 清单与磁盘实测一致（抽查 stage5 HtmlFormatter 等地对得上）。

## 用途
后续所有阶段以本清单的模块归属为准；新增迁移时据此避免误判。
