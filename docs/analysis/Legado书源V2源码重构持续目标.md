# Legado 书源 V2 源码重构持续目标

## 事实基线

机器状态唯一来源是 `tools/legado-compat/state/full-source-validation-state.json`；本文件只定义执行目标、边界和交接规则，不复制可变计数。固定输入为 458 条书源，源包 SHA-256 为 `473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67`，Legado 固定提交为 `95973d186b147fb9ab43a9240021d688e4304fbd`。

当前机器事实仍是：完整真机验证 `0/458`，源级 `semantic_match=0`，设备级聚合状态 `observed_incomplete`；治理总账仍为 `blocked`，因为大量书源尚未完成终态。静态合同、导入数量、历史真机样本、空结果或未执行流程都不能替代运行时语义证据。

## 当前修订

目标 ID：LEGADO-V2-SOURCE-CLOSURE-R3-20260808  
当前修订：2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure  
父任务：COMPAT-006  
工作流：R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS

当前唯一活动源码议题为 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS，状态为 verifying。固定包审计仍确认 67 个标准 CSS 伪类规则字符串、25 条受影响书源；现阶段已覆盖多级链、重复祖先、of-type、嵌套伪类、兄弟组合、空 compound 以及第 267 条真实规则 `@css:a[href~=(-|_)\\d+]:contains(下一页)@href`。本轮确认 ArkWeb owning-compound 投影已统一走 `legadoMatchesJsoupSelector`，不再用原生 `ancestor.matches` 丢失 Jsoup `~=` 正则语义；序号 357/402 的 5 个复杂组合节点已建立 R4 精确 fixture，并通过 13 项 fixture 契约和 47 项五消费者覆盖静态契约断言。新增 R4 readiness 契约共 233 项断言，覆盖 71 个子项：37 个静态完成、34 个明确延期到 R4，153 条已完成证据路径已核验存在；证据为 `tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-243-r4-readiness-20260810.json`，重现脚本为 `tools/legado-compat/Test-LegadoJsoupStandardPseudo243R4ReadinessContract.ps1`。修改后 R3 静态收敛门禁证据为 `tools/legado-compat/evidence/r3-static-convergence-20260810/static-gate-after-r4-readiness-registered.json`，432 个 PowerShell 与 3866 个 JSON 均无语法/解析错误。失败见证、静态合同、current-head 审计、源形状审计、R4 fixture 注册证据、消费者覆盖证据和治理镜像均已登记；这些仍是静态源码证据，R4 运行时、458 条 Harness、Legado 差分、构建和真机验证继续延期。
## 下一持续执行目标

继续以 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS 为唯一源码活动边界：对尚未被现有 fixture 覆盖的真实组合继续做源包扫描和消费者审计；若没有新的可证实主因，不重复制造 fixture 或修改源码。当前新增证据为 `tools/legado-compat/fixtures/legado-arkweb-jsoup-regex-contains-composition-context.json`、`tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-pre-fix-20260810.json`、`tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-post-fix-20260810.json`、`tools/legado-compat/evidence/v2-arkweb-jsoup-regex-contains-composition-current-head-audit-20260810.json`、`tools/legado-compat/evidence/v2-arkweb-jsoup-regex-contains-composition-source-fix-20260810.json`、`tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-source-shape-audit-20260810.json`、`tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-combination-r4-context.json`、`tools/legado-compat/evidence/v2-jsoup-standard-pseudo-combination-r4-fixture-20260810.json`、`tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-fixture-20260810.json`、`tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-consumer-20260810.json`、`tools/legado-compat/Test-LegadoJsoupStandardPseudoCombinationR4FixtureContract.ps1` 和 `tools/legado-compat/Test-LegadoJsoupStandardPseudoCombinationR4ConsumerCoverageContract.ps1`。本轮没有执行运行时、网络、构建、安装、设备或 Legado 差分；243 与历史 242 均保持 verifying，不能报告为语义兼容完成。
## 持续目标

在不依赖旧 `NovelSourceExecutor` 回退的前提下，持续完成漫匣 Legado V2 兼容层的源码级根因治理与证据闭环：

1. 每个已声明能力都必须在 Rule IR/Analyzer/Matcher、请求载体、HTTP/ArkWeb transport、标准 JSVM/Native JSVM、JS API、工作流编排和输出投影的实际消费者中具有可追踪的类型化语义。
2. 无法自动执行的能力必须保留规则节点、错误类别和证据路径，并明确归类为 `unsupported_api`、`needs_interaction`、`policy_blocked` 或 `expected_external`。
3. 禁止用导入成功、空结果、未执行流程、网络不可达、缓存或旧执行器回退冒充兼容通过；禁止静默返回空值。
4. 所有静态修复只能保持 `verifying`，只有 R4 的等价类回归、458 条确定性 Harness、Legado 同输入差分、构建和真机门禁才能产生 `passed` 或 `semantic_match`。
5. 每个状态或议题变更都必须原子刷新机器状态、治理镜像、推进台账、证据索引、差分摘要和调查报告执行区块；原始书源、Cookie、账号、正文和密钥不得进入证据。

## 当前议题协议

233 的源码边界是 ArkWeb、标准 JSVM 和 Native JSVM 的 CSS/List 语义，覆盖 `&&`、`||`、`%%` 的首个顶层组合符递归、`@CSS:` 归一化、组合后的 `##` replacement，以及 `java.getString`/`java.getStringList` 的 Java List 形状。冻结 HEAD 的组合失败前合同包含 5 个固定反例；本轮的替换顺序失败前见证另外稳定复现“单个结尾 `#` 被误当 replaceFirst”和“组合后 replaceFirst 被逐操作数应用”两个差异。当前 ArkWeb 合同 12 项、嵌入运行时合同 19 项、替换顺序合同 14 项均已通过，但只证明源码闭合，仍不能提升为 `passed` 或 `semantic_match`。233→234 静态转移一致性门禁已通过并完成证据登记，233 保持 `verifying` 等待 R4；当前源码治理转入 234。

232 的源码边界是已完成静态闭合、等待 R4 的 Legado 规则组合首个顶层组合符语义，覆盖 `%%`、`||`、`&&` 的固定优先级、引号与作用域屏蔽，以及 Analyzer、字符串/DOM 回退、ArkWeb、标准 JSVM 和 Native JSVM 的共享调用路径。其失败前合同 5 项、混合组合合同 10 项、嵌入运行时合同 12 项、current-head 静态审计 40 项和 232→233 转移证据均已登记；审计脚本已改为显式 `ExpectedActiveIssueId`。这些证据只证明源码闭合，仍不能提升为 `passed` 或 `semantic_match`。

012 的源码边界是 IMAGE 请求 Header carrier，覆盖可见图片、预加载和 403 fallback 路径；fallback 必须保留 `Origin`、`Cache-Control`、`Pragma`、`Sec-Fetch-Dest/Mode/Site`、`extraHeaders`、`forceRefresh`、`skipFailureTtl` 和 `legadoImageTrace`。当前不再对 012 追加补丁，等待 R4 验证。

005 的 FILE `downloadUrls`、TEXT/AUDIO/IMAGE/FILE typed handoff、下游消费者以及 `payAction`/`imageDecode` 的结构化结果或拒绝均已登记源码静态证据，保持 R4 待验证边界。

012 的当前源码证据已经完成登记；233 的 CSS/List 组合与替换顺序、234 的嵌套属性正则和 235 的文本伪类证据链均已保留。234→235 静态转移门禁已通过并完成登记，235 当前保持 `verifying`；所有证据均绑定固定 458 条基线，只证明源码闭合，不能提升为 `passed` 或 `semantic_match`，R4 运行时与 Legado 差分仍延期。

1. 固定 Legado `AnalyzeByJSoup`、`AnalyzeRule` 和 Java List 投影实现，确认 CSS 组合、`@CSS:`、`##` replacement、`getString`/`getStringList` 的真实语义。
2. 按冻结书源包扫描 233 的 10 条受影响书源和 25 个 operator-bearing 候选窗口，生成脱敏规则位置索引；网络不可达不得改变静态集合。
3. 对 ArkWeb、标准 JSVM、Native JSVM 的每条调用路径建立失败 fixture 和静态失败合同，检查 CSS/JSON 分流、组合递归、替换时机和 List 方法形状。
4. 234 的失败合同、V2 消费者映射、唯一主因和关闭条件已经齐全并保持 `verifying` 等待 R4；235 已完成独立失败合同、源码修复、静态合同和 234→235 转移门禁，随后已通过 235→236、236→237 静态转移；237 的活动期已结束并保持 `verifying` 等待 R4，当前队列以 037 转移记录为准，R4 仍不启动。
5. 修复必须覆盖所有实际消费者；本轮已完成只读静态合同、UTF-8/JSON/哈希和证据写出隔离检查，生成 current-head/source-fix evidence，并再次刷新全部文档。

236 的 `:has` 伪类失败合同、受影响规则集合、V2 全部消费者、current-head 静态审计和 235→236 转移门禁均已完成；236 保持 `verifying` 等待 R4。237 的索引伪类失败见证、消费者矩阵、current-head/source-fix 和 236→237 转移也已完成，237 与 238 均保持 `verifying` 等待 R4；后续 238→037 转移已另行登记，当前活动议题为 037。

234 的源码边界是固定 Legado Jsoup `[attr~=regex]` 语义在 Matcher、超大文档字符串回退、ArkWeb `java.getString/getStringList` 和 Java 内联正则标志之间的一致实现；冻结包影响为 139 个属性正则字符串、至少 51 条书源、4 个内联标志值/2 条书源。当前 234 已登记失败前、源码、13 项静态合同、current-head 和注册重放幂等恢复证据；新增嵌套于 `:not(...)`、`:has(...)`、`:matches(...)` 的属性正则上下文已登记失败前见证、38 项静态合同和 source-fix evidence。234 仍保持 `verifying`，不能直接宣称运行时兼容；幂等恢复门禁的 8 项断言证明重放不会改变状态哈希或尝试次数，但不产生运行时兼容结论。

## 已完成源码边界（历史记录）：235 文本伪类边界

历史阶段曾推进 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，其目标证据为 `tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json`；该议题现已完成源码静态阶段并等待 R4，不再是活动源码锚点：

1. 固定 Legado Jsoup 的 `:contains`、`:containsOwn`、`:matches`、`:matchesOwn` 真实语义和文本投影边界，并绑定冻结 458 条书源的脱敏规则节点。
2. 以 8 案例 fixture 覆盖后代文本、直接文本、Java 正则、内联标志、逗号分组和未知伪类失败闭合；网络不可达不得改变静态集合。
3. 对 DOM Matcher/HTMLElement、大文档字符串回退、ArkWeb `select`/`java.getString`/`java.getStringList` 和固定 Legado handoff 建立统一消费者映射，禁止静默放宽或空值。
4. 19 项静态合同、source-fix evidence 和 current-head 哈希审计已通过；本轮只登记源码闭合，R4 运行时、原版差分、构建、安装和真机验证仍延期。
5. 修复或发现第二主因时，先保存失败前证据并登记唯一治理议题；235 已完成源码静态阶段，235→236 静态转移门禁已通过并登记。

### 235-TP-03 历史细化目标：Jsoup 空白规范化

当前子阶段：`237-IP-01` 至 `237-IP-04` 已完成失败见证、消费者矩阵、current-head/source-fix 审计和 236→237 静态转移；`237-IP-06` 注册后一致性审计与 `237-IP-07` 重放幂等审计也已完成。237 保持 `verifying`，R4 deferred；238→037 转移后，当前活动锚点改由 037 队列审计段落定义。

历史目标处理 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS` 的文本投影空白语义，目标证据为 `tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json`；该目标已完成静态闭合：

1. `235-WS-01` 已固定 Legado Jsoup 1.16.2 `text()`/`ownText()` 的连续空白、换行、制表、NBSP、相邻文本节点和 preserve-whitespace 边界，并登记失败前合同。
2. `235-WS-02` 已将失败合同映射到 `HTMLElement`/`Matcher`、超大文档字符串回退、ArkWeb `legadoOwnText` 和四类文本伪类消费者，并确认唯一主因为缺少共享 Jsoup 文本累加器。
3. `235-WS-03` 已使用共享的类型化空白规范化语义跨三条路径修复；`235-WS-04` 的静态证据与文档审计也已完成，仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。
4. 本目标禁止运行时批次、真实网络、构建、安装、设备和 Legado 差分；这些动作保留到用户单独开启的 R4。

### 236-HP-01 细化目标：Jsoup :has 伪类

236 的静态转移已完成并进入 R4 等待：失败前见证、消费者矩阵、15 项静态合同和 source-fix evidence 均不得写成 passed 或 semantic_match。

## R3-SOURCE-QUEUE-CONTINUATION-037 队列审计

037 源码队列转移已完成：当前唯一活动源码锚点为 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH`，状态为 `verifying`；`ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD` 保持 `verifying` 等待 R4，不重新打开或并行打补丁。037 合并并修复了 safe_read 的 Search/Explore 独立派发、Explore-only 完整读能力门控、缺失/依赖能力结构化结算和导航层非 profile-wide 证据投影。

固定包静态统计为 Search URL 447 条、Explore URL 362 条、双入口 351 条、Explore-only 11 条；6 案例 fixture、29 项静态合同、27 项 current-head 审计及 source-fix 哈希证据全部绑定固定 458 条基线。静态证据只证明源码闭合，不产生运行时兼容结论。

证据：`tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/transition-consistency.json`、`tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/registration.json`、`tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/post-registration-consistency.json`、`tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-source-fix-20260809.json`。注册后一致性审计 21 项断言通过；下一步只读核对未闭合 P0/P1 候选，证据不足则保持 037 verifying。R4 的 fresh `full_workflow`/`safe_read`、真实端点、Legado 差分、构建、安装、设备和 458 条批次继续延期。
## R3-SOURCE-QUEUE-CONTINUATION-037 队列前置审计

037 注册后一致性审计已通过 21 项静态断言；随后对当前机器事实中的 225 个未通过 P0/P1 条目进行只读前置核对，0 个候选同时具备固定 Legado 语义位置、受影响书源/规则节点集合、可复现失败见证、V2 全部消费者矩阵和明确关闭条件。因此 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH` 继续作为唯一活动源码锚点并保持 `verifying`，没有臆选第二议题。

审计证据：`tools/legado-compat/evidence/r3-source-queue-preflight-20260809/current-objective-preflight.json`；重现脚本：`tools/legado-compat/Test-LegadoR3CurrentObjectiveQueuePreflight.ps1`。该审计只读取状态、固定 Legado HEAD、证据元数据和 UTF-8/哈希，不执行运行时、网络、构建、安装、Android/HarmonyOS 设备或 Legado 差分；R4 继续延期。下一动作是为下一个真实根因补齐五项证据门禁，之后才允许一次选择一个活动议题。

历史 R3 门禁脚本 `Test-LegadoR3SourceClosureStaticGate.ps1`、`Test-LegadoR3StaticConvergenceGate.ps1` 和 `Test-LegadoR3CurrentObjectiveQueuePreflight.ps1` 仍绑定旧的 014/009/037 队列，只能作为历史证据读取器，不能对当前 242 机器事实执行；本次误调用产生的队列不匹配快照已隔离至 `tools/legado-compat/evidence/r3-static-gate-20260809-current-mismatch/r3-source-closure-static-gate.json`，旧 `run-015` 路径标记为 `historical_superseded`，现行队列门禁统一使用 `Test-LegadoCurrentStaticSourceCandidateGate.ps1`。

## R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT

当前目标修订为 2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime。静态 JS API 结算已完成：118 个 API token 中 44 个未注册命中已逐个绑定到固定 458 条书源的 140 次出现，并完成固定 Legado 实现、V2 默认 runtime、Native JSVM、工作流和输出消费者分类。结算结果为 SUPPORTED=6、UNSUPPORTED_API=24、NEEDS_INTERACTION=1、NAMESPACE_OR_IMPORT=7、STATIC_MEMBER_REFERENCE=6；这些数字只表示静态证据，不表示运行时兼容。

本轮唯一活动源码议题为 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME（verifying）。java.s2t 的源码修复和静态闭环已完成：固定 Legado JsExtensions.kt:551-552 的 ChineseUtils.s2t(text) 语义、4 条受影响 Search 书源、失败见证、V2 六层消费者矩阵、post-fix contract、source-fix 和 current-head 哈希均已登记。037 与所有历史源码议题保持 verifying，只等待 R4。

### S2T 源码静态闭合

1. tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json 的失败状态已保留；不得用 Native JSVM shim、旧执行器或空结果掩盖历史缺口。
2. legado_runtime.html 的默认 java 对象已补齐 s2t，复用现有 t2s 的映射边界，并在 LegadoJsApiContractRegistry.ets 登记为 SUPPORTED；Analyzer、Rule IR、脚本作用域、工作流和输出消费者保持同一结构化错误契约。
3. 静态 post-fix contract、UTF-8/JSON/哈希和证据隔离检查已通过，状态保持 verifying；不启动 458 条批次、网络、构建、安装、设备或 Legado 运行时差分。
4. R4 统一入口保留为唯一关闭条件：定向/全量 Harness、同输入 Legado 差分、构建和真机证据完成后，才允许改变 passed 或 semantic_match。

证据：tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json、tools/legado-compat/evidence/r3-jsapi-s2t-static-closure-consistency-20260809/consistency.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json。
## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE

当前机器事实的活动源码议题为 `ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS`（`verifying`）。本次只读静态队列门禁评估 `230` 个 P0/P1 条目，0 个同时具备固定 Legado 语义位置、受影响书源/规则集合、可复现失败见证、V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/工作流/输出消费者矩阵和关闭条件。

因此不选择第二根因，不追加源码补丁；下一议题必须先补齐五项证据并原子登记。证据：`tools/legado-compat/evidence/r3-source-queue-preflight-20260814-244-closed/current-static-candidate-preflight.json`；重现脚本：`tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1`。本门禁未执行运行时、网络、构建、安装、设备或 Legado 差分，R4 继续 deferred。
## 治理修订号漂移修复（ISSUE-AUTO-051）

曾发现目标状态、调查文档和队列证据分别使用 `empty-pseudo`、`combination-r4-fixture`、`nested-descendant` 与 `regex-contains` 等不同 `targetRevision`，旧证据无法证明属于同一个源码闭合状态。该问题已登记为 `ISSUE-AUTO-051-GOVERNANCE-TARGET-REVISION-DRIFT` 并静态关闭：`objective.targetRevision`、本文件“当前修订”和机器当前队列已统一为 `2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure`；r8/r9 只保留为历史证据，r10 是唯一当前队列指针。

21 项修订号契约全部通过，最终 R3 静态收敛门禁为 435 个 PowerShell、3874 个 JSON，语法与解析错误均为 0。失败见证、fixture、源修复清单、契约和最终门禁证据分别见 `tools/legado-compat/evidence/contract-legado-governance-target-revision-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-target-revision-drift.json`、`tools/legado-compat/evidence/v2-governance-target-revision-source-fix-20260810.json`、`tools/legado-compat/evidence/contract-legado-governance-target-revision-20260810.json` 和 `tools/legado-compat/evidence/r3-static-convergence-20260810/static-gate-after-target-revision-fix-final2.json`。本修复仅证明治理事实收敛；`semanticMatchAllowed=false`，没有运行时、网络、构建、安装、设备或 Legado 差分动作，R4 仍延期。

## 治理队列审计证据漂移修复（ISSUE-AUTO-052）

无候选队列的注册器曾只更新 `auditEvidencePath` 和门禁状态，却保留上一议题的 `failureWitnessPath`、`sourceFixEvidencePath`、`postFixContractEvidencePath` 等活动字段；这会把历史 011/243 证据误投影为当前候选。`ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT` 已先由 16 项失败见证复现，再通过 29 项 post-fix 静态契约关闭：当前候选证据字段全部为空，旧路径仅保留在 `historicalQueueEvidenceProjection`，`priorActiveIssueId` 继续作为明确历史来源。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-audit-evidence-source-fix-20260810.json`。该治理修复只改变静态队列证据投影，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。
## 治理队列审计状态漂移修复（ISSUE-AUTO-053）

无候选队列审计曾将 `status=preflight_passed_no_candidate` 与 `candidateGateStatus=no_candidate_satisfies_evidence_gate` 写入 `queueAudit`，却残留 `candidateStatus=source_fix_static_closed`；这把“没有候选”误报为“候选源码修复已闭合”。`ISSUE-AUTO-053-GOVERNANCE-QUEUE-AUDIT-STATUS-DRIFT` 已由 10 项失败见证复现，再通过 9 项 post-fix 静态契约关闭：`queueAudit.candidateStatus` 现在明确为 `no_candidate_satisfies_evidence_gate`，而 `objective.queueSelectionGate` 的活动议题状态保持独立不变。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-audit-status-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-audit-status-source-fix-20260810.json`。本治理修复只改变静态队列状态投影，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。
## 治理队列指针轮换漂移修复（ISSUE-AUTO-054）

队列证据从 `r10` 轮换到新的 `r11` 后，目标修订、队列审计和计数合同仍硬编码历史批次，导致当前机器指针无法通过合同。`ISSUE-AUTO-054-GOVERNANCE-QUEUE-POINTER-ROTATION-DRIFT` 已先由 4 项失败合同见证复现，再通过动态指针 post-fix 静态合同和源修复证据关闭：当前合同与旧注册器统一读取 `full-source-validation-state.json` 的 `governance.queuePreflight.evidencePath`，r8/r9/r10 只保留为历史证据。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-pointer-rotation-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-pointer-rotation-source-fix-20260810.json`。该治理修复只改变静态证据指针解析，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。
## 单议题执行规则

1. 一次只能有一个活动源码根因；不得并行叠加第二个主因。
2. 先读取固定 Legado 实现、受影响书源节点和 V2 全部调用路径，再写失败 fixture/静态契约。
3. 修复后必须保存失败前证据、源码证据、静态合同、current-head 哈希和关闭条件；历史漂移只能标记为历史或被替代，不能覆盖。
4. 发现第二主因、状态与证据不一致或修复引入新差异时，立即停止当前议题，登记新治理任务后再继续；任何队列转移前都必须保留前一议题的 verifying 状态和全部证据绑定，235→236 已按此规则完成。
5. 允许的动作仅包括源码阅读与修改、确定性 fixture、静态合同、PowerShell/JSON/UTF-8/哈希检查和文档刷新。
6. 当前目标禁止 458 条运行时批次、真实端点、网络烟测、构建、签名、安装、Android/HarmonyOS 设备、Legado 运行时差分和任何 R4 回归。

## 阶段状态与交接

| 阶段 | 机器状态 | 当前含义 |
| --- | --- | --- |
| R0 事实冻结与任务归并 | `completed` | 基线、影响集合、原版位置和历史证据已固定 |
| R1 规则语义内核 | `verifying` | 静态规则语义闭合，等待 R4 运行时差分 |
| R2 请求与工作流交接 | `in_progress` | URL carrier、变量作用域、IMAGE 与四类输出 handoff 继续治理 |
| R3 Harness 与证据闭环 | `in_progress` | 七工作流证据、状态镜像和单议题转移继续治理 |
| R4 统一验证交接 | `deferred` | 仅在用户明确开启后执行定向、全量、原版差分、构建和真机验证 |

源码阶段只有在当前 R1-R3 队列中的 P0/P1 项均已完成源码闭合或具备结构化拒绝、每项都有失败前/源码/静态证据、所有文档与机器状态一致并保留 R4 入口时才结束。即使源码阶段结束，也不得宣称 458 条书源已完成 Legado 语义兼容。

机器可读目标：`tools/legado-compat/state/refactor-objective.json`。历史治理结论与完整证据索引见 `tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md`、`docs/analysis/Legado书源引擎证据索引.md` 和 `docs/analysis/Legado书源引擎差分摘要.md`。


### 237-IP-01 至 237-IP-07：Jsoup 索引伪类边界

236→237 注册后一致性审计 20 项断言、注册重放幂等审计 8 项断言均已登记；两者只证明队列与证据的静态一致性，不能提升 237 的运行时状态。

237 固定 Legado Jsoup 1.16.2 的 :nth-of-type、:eq、:lt 语义：同标签 1-based n+b、全元素兄弟 0-based index 和非法数字 fail-closed。六案例 fixture、16 条规则/9 条书源影响集合、DOM Matcher、超大文档字符串回退、ArkWeb 与 Legado 消费矩阵均已登记；当前 source-fix、236→237 转移、注册后一致性和重放幂等只证明源码闭合，237 保持 `verifying` 并等待 R4，不再作为活动源码锚点。

### 238-OC-01 至 238-OC-06：Java NativeObject mContent 重载边界

238 的目标不是新增 CSS 兼容补丁，而是把 Legado `AnalyzeRule` 对普通对象 `mContent` 的直接键读取语义在所有 V2 执行路径中闭合：对象键优先于 JSONPath/CSS coercion，`0`/`false` 不得被当作缺失，数组和换行字符串投影为 Java List，`##` 全局替换与第四段 `replace-first` 保持同一描述符，缺失键仍然阻止错误的 DOM 回退，`$...` 规则继续走 JSONPath。

`238-OC-01` 至 `238-OC-04` 已完成并登记：固定 Git HEAD 的失败见证、20 项基础静态合同、ArkWeb/标准 JSVM/Native JSVM/重复内嵌 native helper 消费矩阵、13 项 current-head 审计和源码修复证据。第一份内嵌 native helper 的局部 `replacement`、组合/JSONPath/CSS 列表投影替换以及两份 helper 的提取边界已统一；所有证据均为静态闭合，`semanticMatchAllowed=false`。

238-OC-05 已完成 237→238 静态转移，238-OC-06 已完成注册后一致性和重放幂等审计；238 成为唯一活动源码议题并保持 `verifying`，R4 仅保留统一验证交接，不启动真实网络、构建、安装、Android/HarmonyOS 设备或 Legado 运行时差分。证据：`tools/legado-compat/evidence/r3-java-object-content-overload-238-target-20260809/target.json`、`tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json`、`tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json`、`tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json`、`tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/transition-consistency.json`、`tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/post-registration-consistency.json`、`tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/registration-idempotency.json`。
