# 漫匣 HAR 模块化 — Stage 6 推进文档（现实基线版 v1）

> 生成：2026-08-20 20:20｜依据：当前代码库实测 + HAR_MODULARIZATION_PROGRESS.md

## 0. 本段说明
本文仅陈述 Stage 6 的**真实现状**与**可执行剩余项**；每个工作项以既定门禁（用户编译+功能回归）收口并独立提交。

## 1. 现实基线（实测快照）
- 模块 ets 文件数：entry=654；manxia-core=101；source-engine=34；network=25；novel=26；theme=19；reader-ui=18；features-ui=11。（entry 由初始 810 降至 654）
- HEAD=7dbc7c1b（已推远端）；本地另有未推的文档提交 77e247c6。
- entry 内仍存在：业务管理器 29 个；pages 共 129（其中 pages/settings 22）；Framework/Data 4（含 DataManager）。
- 关键对象现状：SettingsManager/DataManager/BackupManager/SharedPageBackgroundLayer 仍在 entry；FontAware/ProxyManager/WindowManager（各主题/网络/窗口）已迁出。

## 2. 已完成（Stage 6 既定成果）
### 2.1 模块抽取（均有门禁后提交）
| 模块 | 内容 | 提交 |
|---|-----|-----|
| manxia-theme | 主题集群(U0)+窗口(U2)+字体/UIContext(U5) | 14375c1b 等 |
| manxia-core 扩容 | Models(13)+Framework/Utils(16)，U1 | 7fe17759 |
| manxia-reader-ui | 阅读器流程/组件 17，U3 | ef5a98f1 |
| manxia-features-ui | 设置帮助/备份/编辑器 10，U4 | 4d5e7515 |
### 2.2 契约化（U6 范式：契约进core / 实现自注册 / 消费按接口）
- SettingsManager：SettingKeys+ISettingsManagerFacade+Holder；消费 14 处（约 12 页 + 2 辅助）。
- ProxyManager：ProxyProtocol/Config/TestResult+接口+Holder；对话框消费。
- DataManager：57 数据契约下沉 + IDataManagerFacade/Holder（未接线）。

## 3. 剩余工作清单（现实可执行项，按推荐顺序）
### R1 DataManager 接线段（风险中等，建议独立小块）
- 内容：DataManager implements IDataManagerFacade（3 只读方法已核签名）；启动初始化后 DataManagerHolder.register(this)；试点 1 个消费点改用 Holder。
- 风险/措施：仅 3 方法、签名已核；若 implements 遇签名差异 → 以小步回退到纯新增文件（M11 态）并记录，不连锁改。
### R2 SettingsManager 广度 rollout（量大、机械、低技术风险）
- 现状：通用访问器调用面约 764 处；已切换 ~14 处。
- 做法：分批（每批 N 页，仅限“仅用通用访问器+SettingKeys”的干净页）；含 SettingsManager 参数辅助函数的调用链页归类到批尾，统一升级参数类型为 ISettingsManagerFacade 后再切。
- 完成判据：SettingsManager 不再被任何页面直接 getInstance（能力壳入口除外）。
### R3 第二梯队管理器契约化（按入口面排序逐步）
- 候选：AppInfoManager / NetworkFolderManager / SearchHistoryManager / AnimationSettingsManager / SourceUpdateManager 等（entry 内 29 个中选小面、纯净者先行，每管理器=一次门禁）。
### R4 阻塞页第二波闭包（受 R1-R3 结果驱动）
- 现状：settings(22) 与部分功能页仍被 SettingsManager/DataManager/BackupManager 阻塞而留在 entry。
- 当 R1-R3 使对应咽喉闭合后，重跑闭包，把达标页迁入 features-ui / 新模块。
### R5 收尾
- release 构建复核（已过，随新提交复验）；推送；清理跳档（stage2-*.json 不入库；未迁入文件清单留档）；README 状态更新。

## 4. 推进规则（硬性，防再犯）
1) 每工作项 = 闭包预检 → 最小改动 → 静态自检 → 用户编译+回归门禁 → 独立提交。
2) import 放置：新增 import 必须并入既有 import 区（多行 import 首行是 import{ 时勿插入其中）；再导出必须位于最后一个 import 之后。
3) 类型下沉必须“本地 import + 再导出”两者齐备；块内未导出辅助接口需同步转为 export。
4) 新模块必须 ohpm install；文件操作遇锁 → 软阻塞+级联（用 fs 覆盖写，勿在锁文件上重复修改）。
5) 静态校验口径：residual=0 / dangling=0（精确正则）/ 深路径目标存在 / 无反向依赖 / 无重名。
6) 有风险即停：任何工作项若需连续 2 次以上门禁返修，回退到该项上一提交并重新设计方案（不再叠加修补）。

## 5. 门禁与验收口径
- 每 R 项一次 M-Gate：编译通过 + 该功能域回归 + 关键指标（引用面下降/直连清零）。
- 阶段终点（Stage 6 关闭）：SettingsManager/ProxyManager/DataManager 契约化闭环；settings 与主要功能页进入可用状态迁移；release 构建通过并推送。

## 6. 立即落实建议
- 从 **R1（DataManager 接线段，最小）** 或 **R2 批次1（SettingsManager 广度小批）** 开始；二者都不改模块结构与入口，风险同属低-中，适合逐个门禁推进。

## 7. 当前状态更新（2026-08-20 21:20 收口）
- R1 ✅（M12）：DataManager 接线完成并提交。
- R2 ✅ 批1（M13，3 页）/ 批2（M14，5 页）完成并提交；R2 后续为平台期（剩余页需逐页扩接口，暂缓）。
- release 构建已通过；建议收口前对近期改动复核。
- 本轮未推提交：77e247c6（docs 对账）、0d6140ca（R1）、64296487、3df35054（R2 批1/批2）。


