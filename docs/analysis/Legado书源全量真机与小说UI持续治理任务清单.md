# Legado 书源全量真机与小说 UI 持续治理任务清单

<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:START -->
## 自动化状态镜像

本区块由 `full-source-validation-state.json` 自动生成；它覆盖下方历史叙述中的状态字段，不改写历史证据。

| 项目 | 状态 | 尝试 |
| --- | --- | --- |
| task:GOV-001 | passed | 1 |
| task:COMPAT-001 | planned | 0 |
| task:COMPAT-002 | planned | 2 |
| task:COMPAT-003 | blocked | 3 |
| task:COMPAT-004 | planned | 7 |
| task:COMPAT-005 | planned | 0 |
| task:COMPAT-006 | running | 56 |
| task:COMPAT-007 | planned | 0 |
| task:COMPAT-008 | planned | 0 |
| task:COMPAT-009 | planned | 10 |
| task:UI-001 | blocked | 1 |
| task:UI-002 | planned | 0 |
| task:UI-003 | planned | 3 |
| task:UI-004 | planned | 0 |
| task:UI-005 | planned | 4 |
| task:AUTO-001 | blocked | 24 |
| task:GOV-002 | planned | 1 |
| task:AUTO-028 | blocked | 7 |
| task:COMPAT-034 | passed | 2 |
| task:AUTO-029 | passed | 1 |
| task:COMPAT-035 | planned | 1 |
| task:AUTO-031 | passed | 2 |
| task:AUTO-030 | passed | 3 |
| task:AUTO-032 | passed | 2 |
| task:AUTO-033 | passed | 2 |
| task:AUTO-034 | passed | 1 |
| task:UI-006 | passed | 2 |
| task:V2-IMPORT-005 | passed | 1 |
| task:AUTO-035 | passed | 1 |
| task:AUTO-036 | passed | 1 |
| task:AUTO-037 | passed | 1 |
| task:COMPAT-241 | passed | 1 |
| issue:ISSUE-COMPAT-001 (P0) | planned | 0； |
| issue:ISSUE-COMPAT-002 (P0) | planned | 0； |
| issue:ISSUE-COMPAT-003 (P0) | planned | 0； |
| issue:ISSUE-COMPAT-004 (P1) | planned | 0； |
| issue:ISSUE-COMPAT-005 (P0) | verifying | 2；V2 输出交接源码闭合：BookInfo 保留 Legado FILE downloadUrls，四类输出统一进入 typed handoff；TEXT/AUDIO/IMAGE 由对应 reader/player/image bridge 消费，FILE 候选在缺少 downloader consumer 时保留并返回 missing_consumer，空候选返回 file_download_urls_empty；payAction 与 imageDecode 具有类型化结果或结构化拒绝。43 项静态合同、全量状态契约和源码哈希证据已更新；R4 运行时、原版差分、构建和真机验证仍未执行。 |
| issue:ISSUE-UI-001 (P0) | planned | 0； |
| issue:ISSUE-UI-002 (P1) | planned | 0； |
| issue:ISSUE-COMPAT-006 (P0) | passed | 0； |
| issue:ISSUE-COMPAT-007 (P0) | passed | 0； |
| issue:ISSUE-COMPAT-008 (P1) | passed | 0； |
| issue:ISSUE-COMPAT-009 (P1) | verifying | 8；数据库迁移源码静态闭合；241 通用设备门禁已通过。受控健康重启进程存活且可定位日志未出现 duplicate-column/数据库初始化失败/迁移失败匹配；未观察到 AbsResultSet/框架数据库错误，真实迁移失败传播仍未证明，保持 verifying。 |
| issue:ISSUE-UI-006 (P2) | planned | 0； |
| issue:ISSUE-UI-007 (P1) | passed | 1；Closed: freshly built and installed V2 management UI treats type shortcuts as exact aliases. Device Hypium entered the full source name and recorded the exact filter count as 1 项, not the historical 54 IMAGE cards; the filter-only path issued no source workflow request and closed the Driver. |
| issue:ISSUE-UI-008 (P2) | passed | 1；真机单书源首搜路径复核通过：包子漫画（优+）范围、示例关键词与发现入口均清晰；点击“一人之下”后 V2 搜索返回多条结构化结果，并能继续载入书籍详情和 810 章目录元数据。 |
| issue:ISSUE-COMPAT-010 (P0) | passed | 1；Closed: ordinal 249 now proves the full IMAGE detail presentation chain on device. V2 Search returned HTTP 200/88, BookInfo resolved 6 fields, Toc returned 560 chapters, and the staged detail UI rendered 560章 after the TOC trace; the reader then opened with Driver cleanup confirmed. Asset delivery and original parity remain separately blocked. |
| issue:ISSUE-COMPAT-011 (P0) | verifying | 1；当前静态队列门禁评估 226 个 P0/P1 条目，0 个满足固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件五项证据；保持 ISSUE-COMPAT-011 verifying，R4 deferred。 |
| issue:ISSUE-COMPAT-012 (P0) | verifying | 6；012 的 IMAGE Header carrier 与 403 fallback 源码证据链已闭合，保持 verifying 仅等待 R4；当前唯一活动源码议题已原子转移到 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR，012 不再追加补丁或作为活动锚点。 |
| issue:ISSUE-UI-009 (P1) | passed | 1；真机 V2 书源管理页复核通过：统计摘要与 V2 政策面板均使用“已完整验证 / 总书源”1/458；READY 不被呈现为可读；需交互、不支持、已阻断和旧记录均显式区分；页面文字无溢出或重叠。 |
| issue:ISSUE-AUTO-001 (P1) | passed | 1；单书源输入已通过显式 CLR object[] 信封保证 JSON 顶层数组，Android reference trace 成功产生且测试 finally 已清理私有输入与主机临时输入。 |
| issue:ISSUE-AUTO-002 (P0) | passed | 0； |
| issue:ISSUE-AUTO-003 (P0) | passed | 0； |
| issue:ISSUE-AUTO-004 (P0) | planned | 0； |
| issue:ISSUE-AUTO-005 (P0) | passed | 0； |
| issue:ISSUE-AUTO-006 (P0) | passed | 0； |
| issue:ISSUE-COMPAT-013 (P0) | passed | 1；V2 IMAGE 独立阅读器已在 UIContext.postFrameCallback + FrameCallback.onIdle 边界完成两次重试真机回归：request_started=18/21/24，每次重试仅增加3；渲染期 pathStack 写入、测试干扰和应用级 fatal/kill 均为0。 |
| issue:ISSUE-COMPAT-014 (P0) | verifying | 1；IMAGE transport-failure source closure remains static-verified pending R4: r4 46 error-storm assertions, 18 write-failure cleanup assertions, 27 copied-file cleanup assertions and 13 Download/logs path-alignment assertions pass. Bare and canonical network_transport fingerprints converge; background DNS/TLS suppression and visible/manual bypass stay explicit; ErrorMonitorService bounds only automatic error_<timestamp>_<counter>.txt files in sandbox and managed Download/logs at 20, oldest-first, from finally after successful writes and copy failures, while preserving manual error_detail_, error_report_ and error_logs_ exports. ErrorManagementSubPage now resolves the same managed Download root. R4 ledger boundary, affected set, Legado differential, build and device gates remain deferred. |
| issue:ISSUE-UI-010 (P2) | passed | 3；Closed: when an active source filter yields zero items, the redundant list guide is not rendered. The filter summary retains the active query, zero count and clear action; the empty card remains the sole explanatory result. Fresh signed-HAP Hypium regression passed with source_management_empty_list_guide_present=false and driver_closed=true. |
| issue:ISSUE-COMPAT-015 (P1) | verifying | 1；015 队列静态门禁通过 49 项断言：固定基线、015 唯一活动锚点、014 延后 R4、失败/修复/转移证据、8 个实现文件哈希、fixture/合同哈希和文档镜像一致；无运行时动作，R4 仍延期。 |
| issue:ISSUE-UI-011 (P2) | passed | 0；V2 IMAGE 阅读器错误态已由真机稳定截图、两次重试截图与静态语义契约共同验证：本地化 DNS 提示、可见重试、错误色图标、页码与内容不重叠。 |
| issue:ISSUE-COMPAT-016 (P0) | planned | 1；Six non-Manga independent Ability entry pages still push NavPathStack in aboutToAppear and therefore share the render-boundary risk proven in ISSUE-COMPAT-013. Governance is active until every page uses the stable frame-idle navigation contract and has device evidence. |
| issue:ISSUE-AUTO-007 (P1) | passed | 1；首次定向 Hypium 调用因缺失 Suite#case 前缀执行 0 项；已修正 runner 的精确 class 过滤并在受真机租约与 finally 恢复保护下重跑。4 项 V2 验证超时/取消用例全部通过，未运行额外 suite/case，主应用已恢复。 |
| issue:ISSUE-AUTO-008 (P1) | passed | 1；自动文档生成器曾将执行时间硬编码为 2026-07-30，已改为真实 UTC 时间；新增 RefreshDocumentsOnly 路径及持续真机治理区块。Windows PowerShell 5.1 与 PowerShell 7 均已实际刷新，且明确保留 stage7 历史 failed 状态。 |
| issue:ISSUE-AUTO-010 (P0) | passed | 2；逐源 runner 的公开终态、参考对照、治理发现与证据函数名已与静态契约对齐；在 Windows PowerShell 5.1 和 PowerShell 7 下共 68 项断言通过。真机批次尚未启动。 |
| issue:ISSUE-AUTO-011 (P0) | passed | 3；真机小批次证明逐条 freshness 分类已生效：第 2 条书源被正确记录为 needs_interaction/device_compile_needs_interaction，runner 完成且 scheduledSources=1、infrastructureFailure=none。 |
| issue:ISSUE-AUTO-012 (P0) | passed | 3；真机小批次已通过结构化导航：书源页与书源管理页均在目标结构出现后才继续，导航事件完整记录，未再依赖固定延迟。 |
| issue:ISSUE-AUTO-013 (P0) | passed | 2；真机布局中缺失 visible 字段已按可见处理；runner 成功发现书源节点、头部 4 个动作并进入 V2 书源管理。 |
| issue:ISSUE-AUTO-014 (P0) | passed | 5；真机只读 readiness 审计已重算：458 条存储记录完整，ready=298 且 effective_v2_enabled=298，全量切换按有效路由统计，不再使用持久 legacy 偏好。 |
| issue:ISSUE-COMPAT-FULL-V2-354B00EC3552 (P1) | failed | 0；v2_trace_snapshot_filter_source_card |
| issue:ISSUE-COMPAT-FULL-V2-1495A214694D (P1) | failed | 0；v2_http_403 |
| issue:ISSUE-AUTO-015 (P0) | passed | 2；runner 已修复管理页复用、键盘遮挡、卡片身份验证与当前布局 trace 采集。第8条真机 V2 搜索获得 HTTP 200 非空 trace；第14条进入真实 V2 搜索并分类为 trace_missing，原 ui_text_timeout 未复现。 |
| issue:ISSUE-AUTO-016 (P0) | passed | 2；Resolved: V2 search failures now persist trace evidence and surface a structured failure instead of a false empty result. Targeted device regression captured HTTP 403 trace and original Legado reference returned empty. |
| issue:ISSUE-AUTO-017 (P0) | passed | 2；Resolved: runner now accepts empty output summaries only for trace parsing and classifies HTTP 403 transport traces as failed; targeted V2 device regression verified. |
| issue:ISSUE-COMPAT-FULL-V2-91D473B82011 (P1) | passed | 6；resolved_v2_hypium_retested_passed |
| issue:ISSUE-AUTO-018 (P0) | passed | 2；Resolved: full-source runner now requires the real-device UI outcome to agree with the redacted V2 trace. Source 23 regression now terminates as failed/ui_trace_mismatch rather than passed, and runner exceptions can no longer leave the active source running. |
| issue:ISSUE-COMPAT-FULL-V2-55FA6276FDAC (P1) | failed | 0；v2_http_404 |
| issue:ISSUE-AUTO-019 (P0) | passed | 2；已完成 V2 用户路径 trace 归因治理：用户工作流采用独立执行器和返回结果绑定 trace，shadow 不再写用户证据；数据库刷新采用单调合并；页面重入清空旧卡片并去重同关键词提交；runner 在渲染边界后判定结果。真机第23条验证获得一次 HTTP 200 UI+trace 一致通过；读链路后续 HTTP 404 被正确记录为端点失败，无旧结果或 ui_trace_mismatch。 |
| issue:ISSUE-COMPAT-FULL-V2-A186D7E4EC00 (P1) | passed | 0；resolved_v2_url_template_semantics_and_trace_settlement |
| issue:ISSUE-COMPAT-FULL-V2-1FCD606A1567 (P1) | blocked | 1；已完成原版与 V2 同输入复验：原版 search empty，searchUrl 含合法 JSON webView 选项；V2 真实执行 ArkWeb 返回 HTTP 0 / WEBVIEW_ERROR / Chromium errorCode -102。规则未执行，不能判定语义兼容；保留为端点未确认，禁止降级 HTTP。 |
| issue:ISSUE-COMPAT-FULL-V2-0EF0B6D01C9C (P1) | failed | 0；v2_output_summary_invalid |
| issue:ISSUE-COMPAT-FULL-V2-B7CDFA87E4B1 (P1) | passed | 0；closed_external_original_empty_v2_http_404 |
| issue:ISSUE-COMPAT-FULL-V2-EC62FC81D216 (P1) | expected_external | 0；v2_http_404_visible_and_original_legado_empty_result |
| issue:ISSUE-UI-SOURCE-MANAGEMENT-DENSITY-001 (P1) | failed | 1；source_management_filter_results_obscured_by_fixed_dashboard_and_stale_v2_count |
| issue:ISSUE-COMPAT-FULL-V2-D017E2D5B63C (P1) | failed | 0；v2_http_404 |
| issue:ISSUE-COMPAT-FULL-V2-E8351F8E3EA4 (P1) | failed | 0；v2_trace_missing |
| issue:ISSUE-COMPAT-FULL-V2-9936CC43D835 (P1) | passed | 8；resolved_v2_hypium_retested_passed |
| issue:ISSUE-UI-014 (P1) | passed | 2；source_management_completed_filter_no_longer_shows_loading_footer |
| issue:ISSUE-COMPAT-025 (P0) | passed | 1；ordinal_137_v2_compiles_and_routes_after_java_log_contract_registration; real_user_path_is_now_external_network_unconfirmed_not_v2_full_cutover_blocked |
| issue:ISSUE-UI-015 (P1) | passed | 1；single_source_submit_releases_ime_and_uses_top_anchored_List; device_trace_bounds_y634_inside_result_viewport_y607_and_first_card_is_immediately_visible |
| issue:ISSUE-COMPAT-026 (P0) | needs_interaction | 4；2026-08-04 current-device revalidation cannot reach the old cross-Ability content projection: ordinal 142 returns HTTP 200 but is correctly classified needs_interaction, and the safe policy blocks post-search workflows. This is neither a content-engine failure nor proof that the stale-detail projection is fixed; retain the deterministic regression as the executable proof path. |
| issue:ISSUE-COMPAT-017 (P1) | passed | 2；current_v2_hypium_attempt_21_matches_original_search_and_full_read_workflow |
| issue:ISSUE-AUTO-009 (P0) | passed | 2；Closed: fresh same-input ordinal 35 evidence proves the runner keeps execution verification separate from semantic qualification. Original Legado GET/HTTP 200 is empty; V2 reaches ArkWeb but returns HTTP 0/web_view with the Chromium connection-refused lifecycle, driverClosed=true. The source remains endpoint_unconfirmed/blocked, never passed or semantic_match. State, runner contract and generated ledger now agree. |
| issue:ISSUE-COMPAT-027 (P0) | passed | 1；Closed: bridge and string fallback now share trailing index semantics. Stage0 ran Android reference fixture trace successfully and HarmonyOS conformance passed 42/42; Hypium ordinal 142 is reference-backed semantic_match with V2 search 50 and safe read workflow complete. |
| issue:ISSUE-COMPAT-028 (P1) | blocked | 5；Ordinal 110 was revalidated with a cross-engine sanitized effective-request footprint. Both sides use GET, effective header count 5, and requestHeaderFingerprint 969ee10deb98b28a, while both classify the 403 document as html_access_denied. V2 remains body 263/fingerprint 9fc78f13abf4e9ec and original Legado remains 622/2603693b39157602. Request planning and effective header-set drift are excluded; cross-device/client network identity or external dynamic policy remains unresolved. Toc/content must not be reported readable. |
| issue:ISSUE-AUTO-027 (P0) | passed | 2；Closed: stage0/6/7/8 now force the current main HAP build and persist SHA-256 bindings for the main and ohosTest artifacts. A real stage0 run completed Android instrumentation and HarmonyOS conformance 60/60 before installing the recorded artifacts. |
| issue:ISSUE-AUTO-026 (P1) | passed | 2；The V2 BookInfo non-rule-readable HTTP branch now emits a fixed sanitized diagnostic. The deterministic parser contract and device attempt 36 both persist declared/resolved rule counts, body length, truncated fingerprint, and responseClass=html_access_denied; the Android reference evidence maps the corresponding response class. |
| issue:ISSUE-AUTO-021 (P2) | passed | 4；Closed: the Android reference controller now runs Gradle with its verified Java 17 toolchain rather than the Harmony JDK 21 path. The bounded stage0 androidTest build and emulator instrumentation completed successfully, emitted six sanitized traces, and left no Gradle or Java process behind. |
| issue:ISSUE-COMPAT-032 (P1) | passed | 3；Closed: Android reference and Harmony device traces now agree on the SHA-256 values for user-agent, keep-alive, connection, cache-control and accept-encoding. V2 explicitly injects the pinned Legado accept-encoding baseline only when a source or URL option does not provide one; the device conformance test asserts the redacted reference digest. |
| issue:ISSUE-AUTO-022 (P3) | passed | 1；The dedicated Harmony wire fingerprint harness now suppresses OpenSSL progress stderr. The device rerun emitted only the structured pass result. |
| issue:ISSUE-UI-016 (P1) | passed | 1；书源管理首屏已减负：快捷操作默认收起、V2 说明按需展开、分组模式标签改为显示/展开/收起、未选 V2 标签恢复可读中性色。真机 V2 全量策略、详情展开/收起和无书源卡片安全证据均通过。 |
| issue:ISSUE-AUTO-023 (P0) | blocked | 1；后续 UI Harness 已强制使用无书源卡片截图，且安全模式失败时不再截取全屏；旧截图不再被台账引用。已精确识别旧证据文件，但当前自动化环境拒绝执行文件删除，遗留文件清理由环境策略阻断，不能宣称已物理清除。 |
| issue:ISSUE-AUTO-024 (P1) | passed | 1；安全 UI 审计改用空态文本的稳定 ID，并在 safe-ui-audit 失败时禁止生成全屏失败截图。真机已完成空筛选、截图和 Driver 释放验证。 |
| issue:ISSUE-UI-017 (P1) | passed | 2；筛选零结果时，搜索提交会通过 UIContext FocusController 清焦点；空态不再固定为整页高度，而是在剩余列表区从筛选结果下方开始布局。真机截图确认键盘收起、空态上移、无重叠。 |
| issue:ISSUE-AUTO-025 (P0) | passed | 1；单书源 safe-read Harness 现默认零截图，详情和阅读页不再保存；搜索结果测试 ID 也统一匿名化。ordinal 142 在同源固定原版对照下复跑，Search/BookInfo/Toc/Content 全通过，result.json 无 URL、无截图名且 driver_closed=true。 |
| issue:ISSUE-COMPAT-HYPIUM-5FF0545CC0C5 (P1) | failed | 33；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-033 (P0) | passed | 5；Closed: the installed V2 build exposes IMAGE BookInfo and TOC diagnostics through UnifiedDetail. Fresh ordinal 249 device evidence recorded BookInfo HTTP 200 with 6 resolved fields, TOC HTTP 200 with 560 matched chapters, then collapsed the disclosure and entered the IMAGE reader with Driver cleanup confirmed. |
| issue:ISSUE-COMPAT-HYPIUM-CAE84190B325 (P1) | passed | 10；resolved_v2_hypium_retested_passed |
| issue:ISSUE-COMPAT-HYPIUM-D017E2D5B63C (P1) | failed | 51；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-AUTO-028 (P1) | blocked | 10；2026-08-07: fresh JDK 17 appDebug/androidTest build for LegadoJsonPathReferenceTest started with the isolated seeded cache but emitted only daemon initialization during the bounded interval; it was cancelled without producing a new APK. Old APK was not used for this probe. |
| issue:ISSUE-COMPAT-034 (P0) | passed | 2；Closed: indexed chain class.container@tag.li!0 now delegates to the canonical Legado index grammar. Fresh Hypium ordinal 72 evidence matches original Search 11, first detail target, BookInfo, TOC 75, and completes readable Content with driver_closed=true. |
| issue:ISSUE-AUTO-029 (P0) | passed | 2；已关闭：根因为 entry_test 测试模块未声明 ohos.permission.INTERNET，导致 native HTTP fixture 全部返回 0，而主模块 ArkWeb 不受影响。补齐测试模块权限后，onDeviceTest 已生成新测试 HAP；同一次完整真机门禁通过 aa test、原生 HTTP wire fixture 与 Hypium ArkWeb fixture。 |
| issue:ISSUE-COMPAT-035 (P1) | blocked | 2；Content length, fingerprint and structure comparers are implemented and contract-tested, but strict semantic qualification requires a fresh original Legado content response probe. The old reference log truncates the probe; fresh JDK 17 online/offline instrumentation builds remain unavailable, so no content-parity closure is claimed. |
| issue:ISSUE-COMPAT-HYPIUM-F4F183E0A241 (P1) | failed | 12；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-7B440A3EECC4 (P1) | passed | 2；resolved_v2_hypium_retested_passed |
| issue:ISSUE-COMPAT-POSTFIX-JS-MULTILINE (P1) | passed | 2；json_first_chain_preserves_multiline_postfix_js_and_search_output_on_real_arkweb |
| issue:ISSUE-COMPAT-HYPIUM-DETAIL-CONTROL-REACTIVE (P1) | passed | 1；hypium_reactive_detail_control_wait_verified_on_ordinal_41 |
| issue:ISSUE-COMPAT-HYPIUM-1FCD606A1567 (P0) | failed | 13；v2_hypium_arkweb_execution_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-9936CC43D835 (P1) | failed | 10；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-AUTO-030 (P1) | passed | 4；Closed: project-owned high-port Hypium bootstrap selects a verified available 46000-46999 loopback UI-agent forward port before UiDriver.connect; direct device smoke passed, released the Driver, captured screenshots, and restored the device without editing .venv. |
| issue:ISSUE-AUTO-031 (P1) | passed | 2；Closed: direct runner now publishes redacted preflight, source, document-refresh and terminal run activity; ordinal 154 ended passed/completed with no temporary replace-backup artifacts. |
| issue:ISSUE-AUTO-032 (P0) | passed | 2；Closed: default package resolution now locates exactly one JSON by the pinned SHA-256 instead of relying on a locale-decoded Chinese filename; Windows PowerShell 5.1 contract and ordinal 154 device regression passed. |
| issue:ISSUE-AUTO-033 (P1) | passed | 2；Closed: startup cleanup removes only stale run-activity temporary and replace-backup siblings; Windows PowerShell 5.1 ordinal 154 regression completed with zero such artifacts remaining. |
| issue:ISSUE-COMPAT-FULL-V2-70B76992F7AD (P0) | passed | 2；Closed: V2 now mirrors the pinned Legado plan/transport boundary for enabledCookieJar POST requests. CookieJar:1 is visible in the redacted plan and consumed before wire transmission; POST Content-Type remains wire-only. Fresh original/V2 search traces both use POST and HTTP 500/empty. The original-only Cookie header is persisted session state, not a source rule. Endpoint response parity remains explicitly external_network_unconfirmed. |
| issue:ISSUE-COMPAT-HYPIUM-70B76992F7AD (P2) | blocked | 8；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-C601B6B2D1E1 (P1) | failed | 29；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-AUTO-034 (P1) | passed | 2；Closed: detached full-source Hypium launcher now serializes spaced SDK paths through an encoded command, persists a PID manifest and atomic run activity, and exposes non-blocking status polling with explicit UTF-8 replacement only for diagnostic logs. Ordinal 249 safe-read execution completed without host timeout or stale running state. |
| issue:ISSUE-COMPAT-HYPIUM-8DE69BBE108B (P2) | blocked | 10；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-ACCBB7CD7421 (P1) | passed | 8；resolved_v2_hypium_retested_passed |
| issue:ISSUE-AUTO-035 (P1) | passed | 2；Closed: source and reference JSON persist explicit UTC strings. The apparent 2026-08-04 +08:00 value came only from PowerShell ConvertFrom-Json local-time display; raw evidence is 2026-08-03T...+00:00. New static contract requires explicit UTC serialization. |
| issue:ISSUE-COMPAT-HYPIUM-111F993B9576 (P1) | needs_interaction | 31；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-0DFE5EDEBA78 (P1) | blocked | 46；v2_hypium_book_info_reference_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-D29F0DD86135 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-366AF12D170D (P1) | needs_interaction | 1；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-7836CE630E82 (P1) | blocked | 1；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-C37C70C8CAEF (P1) | blocked | 13；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-036 (P0) | passed | 4；Closed for this root cause cluster: the registry now resolves explicitly registered ancestor contracts for returned-value members (for example source.bookSourceName.includes), injects the runtime-backed source metadata fields, and preserves HMacHex as a structured unsupported API until standard HMAC vectors are proven. Frozen 458-source matrix remains 118 references: 47 exact, 3 prefix, 68 unregistered. Fresh signed HAP was installed on the HarmonyOS device and the Hypium ArkWeb fixture passed all 8 markers with driver_closed=true. |
| issue:ISSUE-UI-018 (P1) | passed | 2；Closed: the default source card now presents a one-line semantic V2 outcome (workflow, transport, HTTP status and output count). The complete redacted multi-workflow trace is reachable through the explicit 详情 action in a scrollable dialog; fresh device Hypium verified exact filtering, dialog open/close and driver cleanup. |
| issue:ISSUE-COMPAT-037 (P0) | passed | 1；已关闭：V2 HMacHex 已按 Legado 的 HMacHex(data, algorithm, key) 修复；HmacMD5 和 HmacSHA256 标准向量已在最终 HAP 的真机 ArkWeb runtime 通过；未知算法返回 CRYPTO_HMAC_FAILED，不再伪造稳定哈希。Registry 已以该真机证据标记 SUPPORTED。 |
| issue:ISSUE-AUTO-036 (P1) | passed | 1；HAP 新鲜度治理已完成真实 HarmonyOS 回归：主 HAP 与 ohosTest HAP 均针对当前源码重建并安装；ohosTest 完整性、新鲜度、aa test 63/63、ArkWeb runtime 与 timeFormat marker 全部通过。 |
| issue:ISSUE-AUTO-037 (P0) | passed | 2；已完成 ArkWeb 真运行时修复与回归：java.t2s、java.getStringList、java.hexDecodeToString 已在 runtime HTML 注入并由 fixture 验证；aa test 63/63，主/测试 HAP 新鲜且完整。 |
| issue:ISSUE-AUTO-038 (P0) | passed | 2；ArkWeb 真运行时已验证 java.encodeURI 与 java.post：编码结果、POST 方法、请求体、X-Legado-Header 和 fixture 响应均符合预期；aa test 63/63，ArkWeb full gate 通过。 |
| issue:ISSUE-AUTO-039 (P1) | passed | 2；ArkWeb 真运行时已验证 java.setContent/getContent 上下文状态闭环和 java.getWebViewUA 非空真实 UA；aa test 63/63，full gate trace 通过。 |
| issue:ISSUE-AUTO-040 (P0) | passed | 1；已修复 JS API 使用矩阵的错误语义：注册表状态现被解析为 SUPPORTED、不可自动执行和未登记三类，避免将 NEEDS_INTERACTION/POLICY_BLOCKED 计为可兼容。 |
| issue:ISSUE-AUTO-041 (P0) | passed | 2；java.webView 与 webViewGetOverrideUrl 已在 ArkWeb 真运行时产生结构化 ARKWEB_NESTED_WEBVIEW_UNSUPPORTED，不再静默返回空；63/63 conformance 通过。 |
| issue:ISSUE-COMPAT-CRYPTO-001 (P0) | passed | 3；已关闭（固定 458 条基线范围）：真机 ArkWeb 已验证 AES、DES64、3DES192 的 ECB/CBC、PKCS5/PKCS7、key/iv、createSymmetricCrypto、aesBase64DecodeToString 与 desEncodeToBase64String；未知 transformation 保持结构化 CRYPTO_SYMMETRIC_FAILED。 |
| issue:ISSUE-AUTO-042 (P0) | passed | 2；对称加密 API 已在真机 runtime 中产生结构化 CRYPTO_SYMMETRIC_UNSUPPORTED，不再以未定义函数或空文本伪装成功；63/63 conformance 通过。 |
| issue:ISSUE-COMPAT-RUNTIME-REPLAY-001 (P0) | passed | 1；已关闭：固定 8 次 replay 上限会在第 9 个合法 bridge 请求误报 PENDING_BRIDGE_TIMEOUT；现改为 128 请求预算并要求每次 pending 必须产生新响应。AES+DES+3DES fixture 已在真机越过旧上限。 |
| issue:ISSUE-COMPAT-CRYPTO-002 (P1) | verifying | 0；Crypto transformation 源码静态闭合；24 项合同与 current-head 哈希审计通过，R4 延后。 |
| issue:ISSUE-COMPAT-UUID-001 (P0) | passed | 1；已关闭（固定 458 条基线范围）：原版 JsExtensions.randomUUID 与 JavaImporter 的 java.util.UUID.randomUUID 均已登记为 SUPPORTED；真机 ArkWeb 验证 UUID v4 字符串及 toString 语义，新的 HAP/ohosTest HAP 已重建安装，aa test 63/63、Hypium 启动重启 smoke 和更新矩阵均通过。 |
| issue:ISSUE-COMPAT-ANDROID-REF-TRANSFORM-001 (P1) | blocked | 2；2026-08-05: 阶段0在同类隔离缓存策略下最终通过并生成新鲜原版 trace；阶段1重跑时仍出现 Gradle 8.13 artifact-transform 临时 workspace 无法移动到 immutable location，随后总控超过1800秒且未执行 finally，已恢复为 blocked。该问题仍是可重试的参考端构建基础设施阻断，不能把阶段1导入门禁误报为通过。 |
| issue:ISSUE-DEVICE-ONBOARDING-BOOKSOURCE-001 (P0) | planned | 1；真机最新 HAP 启动后落在“欢迎您使用漫匣 / 开始引导流程”，当前无法观测先前 458 书源管理页或其持久化状态；在完整书源真机校验前必须建立可复现的测试账户/初始化与导入基线，禁止把启动 smoke 当作书源工作流通过。 |
| issue:ISSUE-COMPAT-HYPIUM-99DFA6FD5C9A (P1) | failed | 9；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-F4FED60D32DD (P1) | failed | 27；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-D8A129D64EEB (P1) | passed | 5；resolved_v2_hypium_retested_passed |
| issue:ISSUE-V2-IMPORT-005-20260805 (P0) | passed | 1；external_ability_settings_hydration_and_post_click_error_classified |
| issue:ISSUE-COMPAT-HYPIUM-271A2439DFEB (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-9BA4850E54E3 (P2) | blocked | 5；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-D11ED7C2CB84 (P1) | failed | 5；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-C0EE28372EF5 (P2) | blocked | 4；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-CC5D833AA5FB (P1) | blocked | 11；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-9EE05687402A (P1) | blocked | 7；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-EXPLORE-TRACE (P1) | passed | 1；Dynamic Explore failures now expose the persisted redacted trace in the no-kind error state; Hypium captures workflow=explore/http=0/error=network and the V2 runner classifies the source as blocked instead of harness failure. |
| issue:ISSUE-COMPAT-STATE-DEVICEQUAL (P0) | passed | 1；Per-source V2 runner reinitialization preserves the independently observed device-persisted aggregate qualification and validates its denominator against the immutable 458-source baseline. |
| issue:ISSUE-COMPAT-HYPIUM-D580BBECC90B (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-14DFBA9D6769 (P1) | failed | 22；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-SAFE-READ-EXPLORE-PRIORITY (P1) | blocked | 2；77 号与 84 号真机复测均证明 safe_read_path 仍提前返回：Explore 可执行，但 Search/BookInfo/Toc/Content/File/Review 被统一记录为 profile_explore_only；这是工作流编排缺口，不是网络或 UI 假阳性。 |
| issue:ISSUE-COMPAT-HYPIUM-SOURCE-CARD-OFFSCREEN (P1) | blocked | 2；Hypium 在虚拟化/滚动列表中无法从名称过滤结果定位 source card 或 picker item：管理页计数为 1 仍 SOURCE_CARD_MISSING，Explore picker 仍 BOOK_SOURCE_PICKER_ITEM_MISSING；必须先滚动到元素。 |
| issue:ISSUE-COMPAT-HYPIUM-EXPLORE-ONLY-DISPATCH (P1) | blocked | 1；书源原始 JSON 仅提供 exploreUrl、searchUrl 为空时，总控把 Search 缺失当作整条书源 policy_blocked，Explore 也被错误标记为未执行。 |
| issue:ISSUE-COMPAT-HYPIUM-2B3E18BAFE29 (P1) | failed | 6；v2_hypium_explore_harness_or_engine_failure |
| issue:ISSUE-COMPAT-HYPIUM-SCROLL-BOUNDED-FALLBACK (P1) | passed | 1；Hypium 滚动辅助函数已修复未初始化 target，并将显式 Scroll 被拒绝后的默认语义滑动限制为最多 3 次；确定性回归和 77/84 号真机复测均无 UnboundLocalError。 |
| issue:ISSUE-COMPAT-HYPIUM-ECBA67AE3061 (P1) | blocked | 6；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-354B00EC3552 (P1) | failed | 22；v2_hypium_semantic_mismatch_reference_success_v2_http_error |
| issue:ISSUE-COMPAT-HYPIUM-1495A214694D (P1) | needs_interaction | 18；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-91D473B82011 (P1) | passed | 6；resolved_v2_hypium_retested_passed |
| issue:ISSUE-COMPAT-HYPIUM-55FA6276FDAC (P1) | failed | 18；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-486D5479FA52 (P1) | failed | 4；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-A186D7E4EC00 (P1) | failed | 11；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-CBA59EE16976 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-AF2B7E284C14 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-EE93D2051DB2 (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-0EF0B6D01C9C (P1) | needs_interaction | 6；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-DEFD8DA018CA (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-BCF630BFA338 (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-C7BFCA452DB7 (P1) | blocked | 4；v2_hypium_book_info_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-347B161D165D (P1) | blocked | 4；v2_hypium_book_info_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-D74743472A0C (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-C4DDDBA1AC23 (P1) | failed | 5；v2_hypium_explore_harness_or_engine_failure |
| issue:ISSUE-COMPAT-HYPIUM-000E6EFE29E2 (P1) | blocked | 5；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-4F46F757C13F (P1) | blocked | 5；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-B7CDFA87E4B1 (P2) | blocked | 5；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-EC62FC81D216 (P2) | blocked | 6；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-DD4B297504C2 (P1) | needs_interaction | 5；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-E8351F8E3EA4 (P2) | blocked | 4；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-60D61FB3BCAC (P1) | blocked | 7；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-9B47A1BFB5E3 (P1) | blocked | 4；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-8D8AA6EFDD42 (P1) | blocked | 5；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-A222F831CF95 (P1) | blocked | 5；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-BECDC35195CD (P1) | blocked | 3；v2_hypium_book_info_reference_insufficient |
| issue:ISSUE-COMPAT-HYPIUM-53AA8425A53B (P1) | failed | 4；v2_hypium_explore_harness_or_engine_failure |
| issue:ISSUE-COMPAT-HYPIUM-A6A261DFAEEE (P2) | blocked | 7；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-1860A0A4C441 (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-4AFA071991DA (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-5C462FFDF9ED (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-0EE99B647B7A (P1) | failed | 7；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-96E4C8F28595 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-864E8DD0E56D (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-125AFD04A299 (P2) | blocked | 5；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-03DEA44B4FED (P1) | blocked | 4；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-EB8311FE2C9B (P2) | blocked | 6；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-C0B5C652621D (P1) | needs_interaction | 5；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-A80DE327AE53 (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-4A1B81C24650 (P1) | failed | 5；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-173FA761E7AE (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-9EDD01C95A0F (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-689396D3D70C (P1) | blocked | 4；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-6C9E06E9921C (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-580EA21B1B95 (P1) | blocked | 6；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-10CFD6498416 (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-C1A08A262392 (P1) | failed | 3；v2_hypium_explore_harness_or_engine_failure |
| issue:ISSUE-COMPAT-HYPIUM-2F66CAA23B12 (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-A6C42CB68AE2 (P1) | needs_interaction | 11；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-93C0FCC9DCBE (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-01BE155E5EAE (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-F494FF40E30A (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-A3230B61B541 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-24A0A2137188 (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-6962CBE223AF (P1) | needs_interaction | 4；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-3E9BBFC8B06B (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-AF9153FC2B67 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-125417A565BA (P1) | failed | 7；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-4D671197734B (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-571C2A7F0967 (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-E9C09CA3D40D (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-6F84C110D6C3 (P1) | needs_interaction | 5；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-EF2291C4B6DA (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-6A28B731A7A2 (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-FDA82F99C0DA (P1) | blocked | 4；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-18BF8AACDC22 (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-1F70917AFB3D (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-37C1D615CA40 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-38B7533DA4D2 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-1E37A383CFC1 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-0AC395791396 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-1206D3E67EBC (P1) | blocked | 5；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-904C227F7977 (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-C90464775B00 (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-A85240C1D537 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-11225871DDD1 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-196C7342F194 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-6F580D66C9E4 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-82952E795E08 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-221FAC3B8479 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-1F3BC515B111 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-8A4AB0A33263 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-4B702C1FB4F6 (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-32FC20A232AB (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-B920B8669ADF (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-3D3A052A80DE (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-A8417AC728AD (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-8739CDE34F74 (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-4B464C8C333A (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-301A285F95A0 (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-58908309DD23 (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-1D3ADF7C57CF (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-66CC78AC6825 (P1) | blocked | 4；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-712C8D5B4397 (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-6AD374B734B8 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-EE4B75B614FA (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-5BBBD5835320 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-9A947698E898 (P1) | failed | 4；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-143DD193CFD0 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-503F1ABBB7F2 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-8255408BDDB2 (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-4B33C6BA1A7D (P1) | failed | 18；v2_hypium_explore_harness_or_engine_failure |
| issue:ISSUE-COMPAT-HYPIUM-B181B448E371 (P0) | blocked | 2；v2_hypium_image_workflow_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-0604B76D3380 (P0) | blocked | 4；v2_hypium_image_workflow_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-639AA3298762 (P1) | blocked | 4；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-459819826591 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-285790525D2A (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-6A2FC987775A (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-8716141F0513 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-35F23BD06544 (P1) | blocked | 2；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-3A84DBD46C52 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-09245A95878B (P1) | blocked | 2；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-88FAE5D55A91 (P1) | blocked | 2；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-7F203C43F830 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-086D4C4A8F06 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-FFB0EE44CD22 (P1) | blocked | 2；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-1347E8C0B2B3 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-E7F200A3189F (P0) | blocked | 2；v2_hypium_image_workflow_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-D8F423D19B99 (P0) | blocked | 2；v2_hypium_image_workflow_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-88D34B10005C (P0) | blocked | 2；v2_hypium_image_workflow_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-869BC8806F2A (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-3B2A23A11AE5 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-7AD5823C1E42 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-87512D4BF841 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-DA0BF6A3D996 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-4231F082EDCC (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-28747226CEBE (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-4626E7F9F7BE (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-92EAB7326CDB (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-7F2085E51D65 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-0525CF601139 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-12342D22500A (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-978D53708BD0 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-A3FE1755284E (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-76810C4300FC (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-8747814A65FF (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-EB90F5761112 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-B2DC4C1FEA06 (P1) | failed | 2；v2_hypium_execution_failure |
| issue:ISSUE-COMPAT-HYPIUM-77B73B9E2B54 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-14D436B7295C (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-5A116AF45DA5 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-C7CA1D9ED00F (P1) | blocked | 3；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-5DC34A0B5BC7 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-5D9DF8549B4B (P1) | blocked | 3；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-3EDFE4A96498 (P2) | blocked | 2；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-94E3484401AC (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-0090868A17BE (P2) | blocked | 3；v2_hypium_external_network_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-C87B3362789E (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-8FD48091BC01 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-77543541459A (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-E3DE6958B2BE (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-6E7A0796A019 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-5789612DF7E0 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-783708961BC7 (P1) | blocked | 2；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-ABD488357AD7 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-2F781AC72F4A (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-7CC0745BF09A (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-5FC8908FAC6F (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-F3CE30C93C64 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-9B3B796AC27E (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-38717D28F9AB (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-EBAF48AA77DB (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-0A40C75B26B3 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-980C6BB0F719 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-836517C834F9 (P1) | failed | 2；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-B876B05B8BF8 (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-6042E4FE781E (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-343D49FEE94D (P1) | failed | 3；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-3424DDD97FC9 (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-57DB1BD333BF (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-092423D29A29 (P1) | blocked | 2；v2_hypium_toc_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-3B3DCFF2E027 (P1) | blocked | 3；v2_hypium_toc_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-2CBA8D116098 (P1) | blocked | 3；v2_hypium_toc_endpoint_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-127EE8AE410F (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-26FE20BD0BBB (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-7215DA78A26F (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-187AFD719FC6 (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-FF1173F3C54E (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-1B52AA8166FA (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-CBADAFB435E7 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-7AEBB664B23B (P1) | blocked | 2；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-7E7A3FC89449 (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-6DC53114C189 (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-4BC256F3D6A8 (P1) | failed | 2；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-3D6AAAE60D30 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-40C6B2FAE25A (P1) | failed | 2；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-38C5CBE3182E (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-6BAD1E7F9C4C (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-CB01ECDF469C (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-4624F2BAF5CB (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-0ED03295536E (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-8A0AA0950061 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-6B0266890675 (P1) | failed | 3；v2_hypium_execution_failure |
| issue:ISSUE-COMPAT-HYPIUM-8B551A252890 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-C75BC2D51395 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-D8DE8170539F (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-1F3C5136DADC (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-539E72947C04 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-AC6C737774EA (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-43095817B16D (P1) | needs_interaction | 3；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-2D29B6E97EC8 (P1) | blocked | 3；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-F7A3A0EA36E2 (P1) | failed | 2；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-07348DC006FC (P1) | failed | 3；v2_hypium_toc_empty_unexpected |
| issue:ISSUE-COMPAT-HYPIUM-7133A70EDFAB (P1) | failed | 2；v2_hypium_safe_read_path_harness_incomplete |
| issue:ISSUE-COMPAT-HYPIUM-037C30A9C338 (P1) | blocked | 3；v2_hypium_v2_full_cutover_blocked |
| issue:ISSUE-COMPAT-HYPIUM-7701494C7C51 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-1AB52DE39D7D (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-587E86A18D86 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-EF880CEDC631 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-00F5BE16642B (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-B75DC6A9622C (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-5D9FEF6DD507 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-54E2B9E5A3D0 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-7218100F527D (P1) | blocked | 3；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-0703D7230D62 (P1) | blocked | 3；v2_hypium_safe_read_path_external_unconfirmed |
| issue:ISSUE-COMPAT-HYPIUM-F550282DA4C8 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-56DD0A25B3F3 (P1) | needs_interaction | 2；v2_hypium_protected_response_requires_interaction |
| issue:ISSUE-COMPAT-HYPIUM-6A82E3EE99C3 (P1) | blocked | 2；v2_hypium_empty_without_reference |
| issue:ISSUE-COMPAT-HYPIUM-47B5BEAF9DBF (P1) | blocked | 4；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-CC0A62D38439 (P1) | blocked | 4；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-HYPIUM-FDE94A75EC96 (P1) | blocked | 4；v2_hypium_search_reference_pending |
| issue:ISSUE-COMPAT-SEMANTIC-PASS-GATE (P1) | passed | 1；Fixed: source-level passed now requires confirmed same-input Legado semantic evidence; unconfirmed search/content parity remains blocked. State-based gate over all 458 records reports zero violations. |
| issue:ISSUE-COMPAT-EVIDENCE-OVERLAY (P0) | passed | 1；定向回归证据与 canonical state 的状态漂移已由 effective evidence 覆盖层治理；审计现在固定基线哈希/Legado 提交并选择最新 completed overlay，基线证据保持不可变。 |
| issue:ISSUE-COMPAT-096-EVIDENCE-CONSUMPTION (P1) | passed | 1；Resolved: the runner now imports the shared evidence projection and consumes complete BookInfo/Toc/Content trace records before parent-process classification. The fixture uses the actual ordinal 096 trace digests; the contract passes and forbids safe_read_path_harness_incomplete. The fresh device rerun was separately classified external_network_unconfirmed because Search could not reach the endpoint. |
| issue:ISSUE-COMPAT-227-IMAGE-WORKFLOW (P0) | verifying | 2；已完成源码层联合修复：LegadoWorkflowOrchestrator 对 IMAGE BookInfo/Toc/Content 记录 outputKind、imageWorkflowOutcome、变量载体、章节 URL 规则、missing/fallback/dropped 计数；目录保留原版缺失 URL 回退但不再静默丢弃。尚未执行构建、全量回归、Legado 差分或真机验证。 |
| issue:ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS (P0) | verifying | 2；历史 R3 228→230 队列转移后一致性门禁通过 21 项断言；当时的机器事实、修订 017 目标、治理镜像、台账、证据索引和差分摘要均指向 228，current-head hash audit 与历史 superseded 分类保留；当前队列已由后续转移证据推进，R4 仍延期。 |
| issue:ISSUE-COMPAT-229-BOOK-SOURCE-IDENTITY-RACE (P0) | verifying | 3；已修复 NovelExplorePage 的发现页跨书源异步竞态，并生成未执行验证的源码证据：源/分类选择递增 generation，分类与书籍请求在 await 后校验 generation 和 sourceId，过期结果与跨源结果拒绝写入，详情入口拒绝跨源结果。当前仅完成源码治理，等用户统一回归与真机验证。 |
| issue:ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT (P1) | verifying | 1；历史 R3 转移一致性门禁通过；230 的终态错误与工作流结算源码闭合保持 verifying，后续队列已由新转移证据推进，R4 运行时/构建/设备/Legado 差分延后。 |
| issue:ISSUE-COMPAT-231-JAVA-JSONPATH-V2-RUNTIME (P0) | verifying | 3；Standard JSVM and Native JSVM embedded paths now use the same JSONPath traversal contract as the extended V2 runtime: nested recursive descent, object and array wildcards, slices, negative indexes and scalar/object projection. Fresh Legado reference differential, affected-set regression and 458-source Harness remain pending. |
| issue:V2-HARNESS-023 (P0) | verifying | 4；静态 effective-overlay 审计已重新执行并保留失败证据：458 条映射和 18 个 overlay 已生成，但历史 baseline 仍缺少 457 条 workflowEvidence/sourceAttemptEvidence，并存在 485 条 WORKFLOW_TRACE_DIGEST_INVALID、262 条 WORKFLOW_MATRIX_DIGEST_INVALID、223 条 TOP_LEVEL_TRACE_DIGEST_MISMATCH、222 条 WORKFLOW_MATRIX_TRACE_DIGEST_MISMATCH、64 条 SOURCE_ATTEMPT_NOT_EQUAL_WORKFLOW_MAX、3 条 OVERLAY_NOT_NEWER_THAN_BASELINE、1 条 RUN activity/state 缺口；该缺口属于旧批次证据不完整，必须由新的 run-scoped full_workflow 批次闭合，不能补写历史文件或提前通过。 |
| issue:V2-HARNESS-026 (P1) | passed | 1；V2 source evidence fresh r1 failed before dispatch because PowerShell treated an inline if expression as a command in the Explore projection. The expression is now assigned through an explicit local variable; fresh r2/r3 completed on device and r3 reconciled sourceAttempt with the maximum workflow attempt. |
| issue:V2-HARNESS-027 (P1) | passed | 1；Workflow evidence projection previously treated any Attempt.trace as Explore evidence, so Search-only terminal sources reported explore.tracePresent=true. The projection now requires trace.workflow to equal the requested workflow and r4 fresh device evidence records false for unexecuted Explore. |
| issue:V2-HARNESS-028-MANUAL-REPAIR-PAUSE (P3) | blocked | 1；2026-08-07: full_workflow batch was intentionally stopped at ordinal 29 for evidence-led joint repair. No terminal result was produced for that source; running workflows were settled as blocked/harness_interrupted_by_user_before_terminal and cannot be used as compatibility evidence. |
| issue:V2-IMAGE-001 (P0) | verifying | 0；V2 编排器已补齐 IMAGE BookInfo/Toc/Content 的结构化输出诊断；目录遵循 Legado 缺失 URL 回退语义并记录 fallback/dropped 计数。源码修复已登记，构建、确定性回归、Legado 差分与真机验证按用户要求暂缓，不能标记兼容通过。 |
| issue:ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR (P1) | verifying | 2；232 的首个组合符源码证据链已闭合，保持 verifying 仅等待 R4；当前唯一活动源码议题已原子转移到 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION，232 不再追加补丁或作为活动锚点。 |
| issue:ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION (P0) | verifying | 3；233 已登记组合失败前合同与替换顺序独立失败前见证；本轮 12+19+14 静态合同、源码修复和 current-head 哈希审计均绑定固定 458 条基线。单个结尾 # 不是 replaceFirst，只有 ## 才设置 replaceFirst，替换发生在组合之后；R4 运行时、原版差分、构建和真机验证延期。 |
| issue:ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR (P0) | verifying | 1；234 嵌套正则属性谓词源码闭合已登记：固定 Legado AnalyzeByJsoup 语义、7 案例失败 fixture、DOM Matcher/字符串回退/ArkWeb 三路径失败见证、跨路径源码修复、38 项静态合同及 current-head 静态合同均通过；静态证据不等同运行时兼容，235 仍为候选，R4 延期。 |
| issue:ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS (P0) | verifying | 1；235 源码静态闭合已完成并保持 verifying；235→236 静态转移门禁已通过，236 已成为唯一活动源码议题。235 仅等待 R4 的运行时、458 条 Harness、Legado 差分、构建和真机验证，不再保留“转移待执行”的陈旧叙述。 |
| issue:ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR (P0) | verifying | 1；236 源码静态闭合已完成并通过 236→237 静态转移；236 保持 verifying 等待 R4，237 已成为唯一活动源码议题。 |
| issue:ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS (P0) | verifying | 1；237 目标交接完整：20 项注册后一致性断言与 8 项重放幂等断言通过；237 保持 verifying，238 仅为下一候选，R4 仍延期。 |
| issue:V2-URL-001 (P0) | verifying | 0；Search/Explore now retain a typed, in-memory LegadoRequestCarrier that separates bare identityUrl from the deferred requestUrlTemplate. URL option JSON is excluded from identity resolution so method, headers, body, charset, WebView, webJs and Cookie behavior remain available to the owning BookInfo/Toc/Content workflow; data: URLs remain opaque. The manager issues opaque carrier tokens, validates source and identity, and rejects missing, mismatched or ambiguous carriers instead of silently dispatching a bare URL. Static contract passed 16/16; runtime regression remains deferred by the current source-governance scope. |
| issue:ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD (P0) | verifying | 2；238 静态闭合保持 verifying；R3-SOURCE-QUEUE-CONTINUATION-037 已建立为下一只读队列审计目标，候选需先通过失败见证/Legado 语义/影响集合/消费者矩阵门禁；R4 deferred。 |
| issue:V2-DATA-001 (P0) | verifying | 0；Cross-workflow SearchBook.variable handoff is now explicit and memory-only; static and historical evidence exist, but same-policy Legado differential remains open. |
| issue:V2-GOV-004-DOCUMENT-TASK-MIRROR (P2) | verifying | 1；任务台账镜像源码静态闭合；430 项合同与 230→V2-GOV-004 转移一致性门禁通过，R4 延后。 |
| issue:ISSUE-AUTO-043-SOURCE-UTF8-BOM (P2) | passed | 0；232 current-head 静态审计发现 LegadoRuleAnalyzer.ets 与 LegadoJsEngine.ets 带 UTF-8 BOM，违反无 BOM 源码证据规则；已保留失败审计并仅移除两个文件开头的 BOM 字节，源码正文与换行未改动，规范化后 232 current-head 审计通过。 |
| issue:ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH (P1) | verifying | 0；037 源码静态闭合保持 verifying；注册后一致性审计 21 项通过，当前文档队列前置审计评估 225 个未通过 P0/P1 条目且 0 个满足五项证据门禁；R4 运行时、原版差分、构建和真机验证继续延期。 |
| issue:ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME (P1) | verifying | 0；当前静态队列门禁评估 226 个 P0/P1 条目，0 个满足固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件五项证据；保持 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME verifying，R4 deferred。 |
| issue:ISSUE-AUTO-044-EVIDENCE-READER-UTF8 (P1) | passed | 0；Static candidate-gate evidence reader now accepts UTF-8 BOM text and classifies binary evidence without false unreadable errors; no runtime action performed. |
| issue:ISSUE-COMPAT-241-ARKTS-INLINE-OBJECT-TYPES (P0) | passed | 1；ArkTS 命名结果合同、JDK21 debug 构建、signed HAP 安装、真机冷启动和书源管理页均已通过；管理页明确为 V2 完整验证 0/458，241 设备门禁关闭但不产生书源语义通过。 |
| issue:V2-HARNESS-029-HILOG-PIPE-BLOCK (P1) | passed | 0；The 009 migration smoke harness previously blocked on an unbounded synchronous hilog snapshot; PID-filtered keyword capture now produces bounded, inspectable device evidence and preserves blocked visibility when no PID or relevant lines exist. |
| issue:V2-HARNESS-030-DEVICE-READINESS-SINGLE-ROW (P1) | passed | 2；单行 SQLite 结果修复、真实手机 readiness 与 13 项静态合同均通过；继续保持 ISSUE-COMPAT-009 为主议题。 |
| issue:V2-HARNESS-031-HYPIUM-DEVICE-READINESS-WARMUP (P1) | passed | 2；Hypium 生命周期的独立 attempt 目录、有限重试、attempts.json 和 driver_closed 门禁均通过 13 项静态合同与手机真实证据。 |
| issue:V2-HARNESS-032-TEXTNODE-CONTRACT-HELPER-DRIFT (P2) | passed | 2；textNodes 门禁已改为验证实际语义：textnodes/owntext 均走 extractDirectTextNodes，最终使用 LegadoTextAccumulator.toTrimmedString；修订后的 V2 full-source runner contract 325 项断言通过，生产实现未被改动。 |
| issue:V2-HARNESS-029-CURRENT-RUN-INTERRUPTION (P2) | blocked | 1；当前 full_workflow 批次在 ordinal 14 被停止；运行中的工作流已结算为 blocked，不能作为兼容通过或语义差分证据。 |
| issue:ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION (P0) | verifying | 0；LegadoExecutionTrace 与 LegadoSourceScriptResult 对 variableChanges/sourceEffectNames/bridgeTraces 及 request/response/bridge 嵌套数组做防御性复制；Analyzer 现收集 JS bridgeTraces，syncVariables 将快照交给工作流；五个 V2 trace 重建路径和同一活动请求的 timeout trace 均保留已有或合并后的 bridgeTraces，静态合同通过，R4 deferred。 |
| issue:ISSUE-AUTO-045-PS51-CONTROLLER-BOM (P1) | passed | 0；Stage 7 Windows PowerShell 5.1 总控脚本缺少 UTF-8 BOM；已仅补 BOM，正文哈希保持不变，静态门禁通过。 |
| issue:ISSUE-AUTO-046-GOVERNANCE-VERIFYING-RECOVERY (P1) | passed | 0；总控恢复逻辑曾把上次重启前已完成静态闭合的 verifying 议题错误降为 planned，导致候选门禁误选历史议题；仅 running 状态现在可恢复为 planned，26 条受影响记录已按 priorStatus=verifying 原子恢复并保留恢复历史。 |
| issue:ISSUE-AUTO-047-GOVERNANCE-ACTIVE-ISSUE-SECTION-DRIFT (P1) | passed | 0；治理台账当前源码活动段落曾残留 037，已改为由 full-source-validation-state.json 驱动的原子镜像；历史队列叙述保留在生成区块之外。 |
| issue:ISSUE-AUTO-048-GOVERNANCE-QUEUE-SELECTION-ANCHOR-DRIFT (P1) | passed | 0；队列选择锚点与计数合同已跟随机器事实迁移到 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS：注册器同步 queueSelectionGate、continuationTarget.queueAudit、governanceSync；计数合同读取 20260810-r8 的 229/0 门禁并校验 Markdown 计数。历史 242/009 仅保留在明确的历史投影中。 |
| issue:ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS (P0) | verifying | 0；ISSUE-COMPAT-243 current static R4 readiness is reconciled to the authoritative 79-subitem ledger: 41 source-closed items, 38 explicit R4 deferrals and 172 existing evidence bindings. The immutable 2026-08-10 snapshot remains 71/37/34; semanticMatchAllowed stays false. |
| issue:ISSUE-AUTO-049-GOVERNANCE-MARKDOWN-ESCAPE-LOSS (P1) | passed | 0；R3 注册后一致性刷新曾因 PowerShell 双引号字符串吞掉 Markdown 反引号，造成文档控制字符和路径/规则文本损坏；已改为 [char]96 规范片段生成并增加 UTF-8、控制字符和精确活动边界门禁。 |
| issue:ISSUE-AUTO-046-DOCUMENT-ACTIVE-ANCHOR (P1) | passed | 0；治理文档一致性检查已改为校验活动 issue ID 并接受生成器的纯文本/Markdown 标记、“当前活动/当前唯一活动”锚点表述；证据 reproductionCommand 也由实际调用参数生成。机器状态、目标 authority、镜像 ID 和固定基线门禁保持不变。 |
| issue:ISSUE-AUTO-050-HDC-DEVICE-UNAVAILABLE (P1) | blocked | 0；HDC 3.2.0d 可执行，但 list targets 返回 [Empty]；未执行安装、启动、Hypium 或书源工作流，真机门禁保持 blocked。 |
| issue:ISSUE-AUTO-051-GOVERNANCE-TARGET-REVISION-DRIFT (P1) | passed | 0；治理修复 ISSUE-AUTO-051：统一 objective、调查文档和当前 r10 队列证据的 targetRevision；r8/r9 降为历史证据。21 项 post-fix 契约与最终 R3 静态收敛门禁通过，保持静态策略、243 verifying、semanticMatchAllowed=false。 |
| issue:ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT (P1) | passed | 0；治理修复 ISSUE-AUTO-052：无候选队列注册器现在将旧候选证据快照到 historicalQueueEvidenceProjection，并清空当前候选字段；29 项 post-fix 契约与最终静态收敛门禁通过，保持 243 verifying、semanticMatchAllowed=false。 |
| issue:ISSUE-AUTO-053-GOVERNANCE-QUEUE-AUDIT-STATUS-DRIFT (P1) | passed | 0；治理修复 ISSUE-AUTO-053：无候选 queueAudit 的 candidateStatus 现在明确为 no_candidate_satisfies_evidence_gate；9 项 post-fix 契约通过，保持 243 verifying、semanticMatchAllowed=false。 |
| issue:ISSUE-AUTO-054-GOVERNANCE-QUEUE-POINTER-ROTATION-DRIFT (P1) | passed | 0；治理修复 ISSUE-AUTO-054：当前治理合同、计数 fixture 和旧注册器改为读取机器 queuePreflight.evidencePath；r11 轮换不再触发 r10/r8 指针漂移，静态合同通过，保持 243 verifying。 |
| issue:ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS (P1) | verifying | 0；244 R4 统一验证全部 8 步完成：干净单一 run（v2-hypium-full-17516-1786713467539）458/458 终态可追溯（step4-full-batch.json）；1 处 semanticDifference（ordinal 8 reference_success_v2_http_error=外部站点 HTTP 503，非实体语义缺陷，不新增根因）；fixed Legado 同输入差分 witness OK、V2 差分除单对象投影格式缺口（归 231）外一致；hvigor 构建、安装、真机冷启动与 Hypium、书源管理页 54/54 渲染完成（ledger completed）。244 仍保持 verifying：最终 passed/semantic_match 需用户批准。 |
<!-- LEGADO_CONTINUOUS_GOVERNANCE_STATUS:END -->

> 建立日期：2026-07-30  
> 固定书源包：458 条，SHA-256 `473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67`  
> 原版 Legado 基线：`95973d186b147fb9ab43a9240021d688e4304fbd`  
> 机器事实源：`tools/legado-compat/state/full-source-validation-state.json`  
> 兼容推进阶段状态：`tools/legado-compat/state/legado-compatibility-state.json`
> 当前执行目标：V2 语义兼容 Harness。仅以同一原始书源、同一输入、同一安全策略下的真机 trace 和原版 Legado 对照作出兼容结论。

### 执行主体

自 2026-08-04 起，本持续治理任务仅由主 Agent 直接执行。不得创建、恢复或调度 Luna 或其他子代理；真机操作、证据采集、代码修改、构建验证、状态更新与文档刷新均由主 Agent 负责。

## 1. 治理目标

1. 对 458 条 Legado 书源逐条执行可恢复的真机验证，不以“成功导入”或单个成功书源替代完整兼容结论。
2. 对搜索、发现、详情、目录、正文、音频、图片、文件、登录、WebView、JS、Review 和交互能力逐层验证。
3. 任何非预期结果必须先登记任务，再定位为漫匣引擎差异、原版同样失败、站点变化、网络原因、需要交互或安全策略限制。
4. 对小说和书源相关页面逐页、逐状态截图，检查视觉一致性、信息层级、操作复杂度、空态/加载态/错误态和可访问性。
5. 每个问题遵循“发现 → 登记 → 复现 → 修复 → 定向验证 → 真机回归 → 证据归档 → 关闭”的生命周期。

## 2. 状态与结论规则

- `planned`：已进入任务清单，尚未开始。
- `running`：正在采集证据、复现或实施治理。
- `verifying`：修复已完成，正在执行自动回归。
- `passed`：实现和真机证据均通过。
- `failed`：存在可复现的漫匣实现问题。
- `expected_external`：原版和漫匣均因站点、DNS、TLS、网络或服务端状态失败。
- `needs_interaction`：需要账号、验证码、设备授权或用户确认，自动化不得伪造成功。
- `policy_blocked`：付费、危险副作用或未知代码被安全策略明确阻断。
- `blocked`：环境或固定基线变化使当前证据不可比较。

HTTP 4xx/5xx、空结果和超时不能直接归类为网络原因。只有原版同输入对照、重试和请求 trace 支持该结论时，才允许标记为 `expected_external`。

### 2.1 V2 Harness 资格规则

- **执行状态**描述此次真机路径是否完成；`passed` 只表示该路径产生了符合契约的 V2 trace，绝不单独表示与原版语义一致。
- **语义资格**是独立字段：`semantic_match` 必须同时具备同输入原版 trace；`execution_verified_no_reference` 仅表示真机执行已验证；`unverified` 是历史记录或尚无足够证据的默认值。
- `semantic_mismatch`、`arkweb_unconfirmed`、`harness_or_engine_failure` 进入引擎/平台根因队列；`external_confirmed`、`endpoint_unconfirmed`、`needs_interaction`、`policy_rejected` 保持证据化限制，均不得记入语义兼容数。
- Harness 以原始 JSON SHA-256、固定 Legado 提交、脱敏 trace、`driverClosed=true` 和原子状态快照为最小证据集。任一项缺失，资格不得提升。
- 历史状态不会追溯性升格。每条旧记录在下一次真机复验时才写入资格；统计页面必须同时展示执行数、已对照语义数和未验证数。

## 3. 当前任务队列

| ID | 方向 | 优先级 | 状态 | 任务 | 完成条件 |
|---|---|---:|---|---|---|
| GOV-001 | 基础设施 | P0 | passed | 建立长期任务清单与机器状态文件 | 重启后可从逐书源、逐页面状态继续 |
| GOV-002 | Harness | P0 | running | 将真机执行状态与原版语义资格分离，并按根因聚类复验历史终态 | 所有终态均有资格；兼容统计只计 `semantic_match`；HTTP 空结果、WebView HTTP 0 与 Harness 失败不可混同 |
| COMPAT-001 | 书源 | P0 | running | 建立 458 条逐书源、逐工作流可恢复真机校验器 | 每条书源均有脱敏状态、工作流结果、重试与错误分类 |
| COMPAT-002 | 书源 | P0 | running | 增加闪退、ANR、进程重启和 Fatal 日志监控，并治理所有独立 Ability 阅读入口的渲染期导航风险 | 每次执行前后验证进程；异常自动保存脱敏证据并登记；同类 Ability 均在帧完成边界压栈 |
| COMPAT-003 | 书源 | P0 | planned | 建立漫匣 V2 与原版 Legado 的逐样本自动差分 | 非预期空结果、HTTP、规则或正文差异均能自动归因 |
| COMPAT-004 | 书源 | P0 | running | 扩展 JS、模板、变量、DOM、编码加密和网络 API 兼容 | 未支持 API 不静默返回空值；每项有 fixture 和真实样本 |
| COMPAT-005 | 书源 | P1 | planned | 治理登录、Cookie、验证码和 WebView 交互链路 | 无凭据时正确提示；有合法会话时与原版语义一致 |
| COMPAT-006 | 书源 | P0 | running | 治理 AUDIO、IMAGE、FILE 与外部类型执行链路 | 类型输出正确交接到播放器、阅读器或下载器 |
| COMPAT-007 | 书源 | P1 | planned | 治理分页、替换、付费章节、图片解码和 Review | 有消费者或明确可见的结构化结果，不得半执行 |
| COMPAT-008 | 书源 | P0 | planned | 全量执行 458 条固定包并持续清零引擎差异 | 每条均为通过、外部预期、需交互或策略阻断；无未解释差异 |
| COMPAT-009 | 基础设施 | P1 | running | 将漫画与小说数据库的增量列迁移改为真正幂等的模式 | 冷启动不再产生重复列名错误；新增列仍能安全迁移；已有数据不丢失 |
| UI-001 | UI | P0 | running | 盘点小说、书源页面及全部可达状态 | 页面、入口、关键状态、弹窗和返回路径全部登记 |
| UI-002 | UI | P0 | running | 建立真机逐页截图与脱敏归档工具 | 可按页面/主题/状态重复截图，原始截图不提交 |
| UI-003 | UI | P0 | running | 审计书源管理、搜索、发现、详情、阅读器主链路 | 每页有视觉、交互、信息架构和一致性结论 |
| UI-004 | UI | P1 | planned | 审计登录、调试、规则管理、设置和异常状态 | 覆盖空态、加载态、错误态、受阻态和弹窗 |
| UI-005 | UI | P0 | running | 逐项实施 UI 治理并做前后截图回归 | 与 APP 主题、标题栏、间距、字体、按钮和反馈体系一致 |
| AUTO-001 | 自动化 | P0 | running | 自动刷新任务清单、问题索引、覆盖率和日报 | 每次运行结束后原子更新，失败返回非零 |

## 4. 首批已确认问题

| 问题 ID | 关联任务 | 严重度 | 状态 | 事实 | 后续治理 |
|---|---|---:|---|---|---|
| ISSUE-COMPAT-001 | COMPAT-001 | P0 | running | 现有阶段 7 在首个成功候选处停止，只能证明引擎可工作，不能证明 458 条兼容 | 新建逐书源状态机，不因单个成功提前结束 |
| ISSUE-COMPAT-002 | COMPAT-003 | P0 | planned | 原版真实端点对照只在阶段 7 失败后抽取有限候选，不是逐书源差分 | 将参考端差分变为按失败样本自动触发 |
| ISSUE-COMPAT-003 | COMPAT-004 | P0 | planned | 固定包中大量规则命中 JS/模板静态标记，当前真实端点覆盖不足 | 建立 API 使用矩阵，按缺失 API 聚类治理 |
| ISSUE-COMPAT-004 | COMPAT-005 | P1 | planned | 登录和交互书源目前以阻断为主，尚未完成完整登录态执行契约 | 分离无凭据验证、合法会话验证和验证码交互 |
| ISSUE-COMPAT-005 | COMPAT-006 | P0 | verifying | 四类输出 typed handoff 的源码与静态契约已闭合；FILE 候选缺少 downloader consumer 时显式拒绝，R4 全量真机输出交接仍未执行 | R4 分类型执行 AUDIO/IMAGE/FILE/外部类型验收 |
| ISSUE-COMPAT-008 | COMPAT-006 | P1 | passed | IMAGE 虚拟图源同步曾因同名 `bookSourceName` 触发漫画源记录唯一键冲突；现使用稳定内部记录名及按虚拟包串行同步 | 真机 19 项 conformance 通过；冷启动未发现 IMAGE 桥接唯一键或同步失败；继续验证实际 IMAGE 工作流 |
| ISSUE-COMPAT-009 | COMPAT-009 | P1 | running | 真机冷启动对已存在列重复执行 `ALTER TABLE`，系统产生“重复列名”错误日志后仍报告迁移完成 | 先用 RdbStore 查询表结构再执行缺失列迁移，并以真机冷启动日志回归验证 |
| ISSUE-UI-001 | UI-001 | P0 | running | 尚无小说与书源页面的完整清单、逐状态截图和统一评分 | 建立页面矩阵、导航脚本和截图基线 |
| ISSUE-UI-002 | UI-003 | P1 | running | 真机书库/书源入口页顶部约三分之一屏为空白，单项内容被压到页面中段；搜索悬浮按钮与底部导航争抢视觉焦点，“图源/书源/管理”职责缺少解释 | 定位共用主页布局、安全区和内容对齐逻辑，治理后做同设备前后截图对比 |
| ISSUE-COMPAT-006 | COMPAT-004 / UI-003 | P0 | running | 脱敏书源 `8D1D878C…4313` 的发现分类在真机直接显示 JavaScript 代码片段，页面随后误报“暂无发现内容” | 追踪 Explore 规则的 JS 求值、分类解析、错误传播和页面反馈，修复后与原版同源对照 |
| ISSUE-UI-007 | UI-005 / COMPAT-006 | P1 | running | 真机输入完整 IMAGE 书源名“包子漫画（优+）”时，管理页将名称中包含的“漫画”误判为类型快捷词，返回 54 条 IMAGE 书源而非精确匹配 | 将类型快捷词改为精确别名匹配；重编译安装后验证完整名称只返回目标卡片，并继续该卡的 V2 搜索、详情、目录与图片阅读工作流 |
| ISSUE-UI-008 | UI-005 | P2 | running | 真机“包子漫画（优+）”专属搜索页在仅展示少量搜索历史时，下半屏大面积留白，未提供首搜示例、发现入口或下一步说明，视觉重心明显上移 | 设计并接入与漫匣主题一致的首搜/空态引导；完成前后截图对比并验证不遮挡搜索、历史与结果态 |
| ISSUE-COMPAT-010 | COMPAT-006 | P0 | passed | 已关闭：ordinal 249 最新真机路径确认 V2 Search=HTTP 200/88、BookInfo=HTTP 200/6 字段、Toc=HTTP 200/560 章；在 TOC trace 到达后，分阶段 IMAGE 详情稳定渲染为 560 章并可继续进入阅读器。 | 关闭；资产交付失败和原版语义对照由 ISSUE-COMPAT-036 单独治理，禁止以本项通过宣称图片已可读。 |
| ISSUE-COMPAT-033 | COMPAT-006 / AUTO-001 | P0 | passed | 已关闭：IMAGE Harness 现等待异步详情 trace，按 `UnifiedContent.sourceUrl`（原始 `bookSourceUrl`）读取 V2 存储键，展开后折叠诊断再进入阅读器。最新真机证据已记录 BookInfo、TOC、Content 三个 V2 trace，并确认 Driver 正确释放。 | 关闭；后续 IMAGE 可读性与原版语义对照由 ISSUE-COMPAT-036 跟踪。 |
| ISSUE-COMPAT-036 | COMPAT-006 | P0 | blocked | IMAGE 语义兼容仍未完成：同一次新鲜阅读器 trace 中 15 个资产管线均在 `network_dns` 终止，HTTP 响应、解码成功均为 0；同时当前没有同输入的原版 Legado IMAGE 全工作流 trace。 | 在可用网络与新的原版 Android reference APK 下执行 Search→BookInfo→Toc→IMAGE Content/asset 对照；只有请求语义、图片页列表和至少一个资产成功链路可复核后，才允许将该书源标为可读或语义兼容。 |
| ISSUE-COMPAT-011 | COMPAT-004 / COMPAT-006 | P0 | running | 新增真机回归证明 V2 在普通 CSS `href/src` 求值阶段就把相对地址转换为绝对地址，而原版 `AnalyzeByJSoup` 保留原始属性值，URL 仅在对应工作流消费点解析 | 将属性提取与 URL 解析分离；回归覆盖普通文本、多值、单 URL 首项、目录链接和多分页目录，再重测 IMAGE 实源 |
| ISSUE-COMPAT-012 | COMPAT-006 | P0 | verifying | 源码审计确认可见页已有标准 Header carrier，但 `ImageCacheManager.preloadImage` 曾使用部分字段投影，丢失 Authorization、Cache-Control、Pragma、Sec-Fetch-*、刷新和失败策略；现已改为复用 `buildOnlineHeaders`，静态合同通过，R4 资产/原版/真机验证仍未执行 | R4 真实 IMAGE 资产链路与同输入 Legado 对照；确认标准头、扩展头及覆盖优先级在 V2 可见页、预加载、阅读器和传输 trace 一致，只有无未解释差异后才可 passed |
| ISSUE-UI-009 | UI-005 | P1 | running | 书源管理页同屏显示“0/0 正常工作/已验证”与“V2 全量切换 · 1 已验证”，统计口径冲突，用户无法判断前者是当前筛选、全局总计还是已验收数据 | 将导入、可编译、V2 路由、真实工作流验证和全量验收拆分为明确指标；真机截图回归不得再出现相互矛盾的统计 |
| ISSUE-AUTO-001 | AUTO-001 / COMPAT-003 | P1 | passed | 单书源原版参考执行器曾把只有一条的输入序列化为 JSON 对象，而 Android test-only runner 严格读取 JSON 数组，导致 instrumentation 在输入阶段失败；现以显式 `object[]` 信封序列化，ordinal 110 原版 reference 已产生脱敏 trace（`search=3`、详情 probe `403 / 622 / 2603693b39157602`），且 finally 已清理私有与主机临时输入 | 关闭。单书源输入必须保持 CLR 数组信封；回归以 `Invoke-LegadoSingleSourceReference.ps1` 的 `traceReceived=true` 为准。 |
| ISSUE-AUTO-002 | AUTO-001 | P0 | passed | 曾以未准备 fixture/rport 的原始 `aa test` 直接运行，产生 5 个空网络响应失败；2026-07-31 已通过正式阶段 0 总控重跑，Android 原版与 HarmonyOS 21 项 conformance 全部通过 | 后续定向验证统一经总控阶段门禁执行；原始 `aa test` 输出不得作为语义结论 |
| ISSUE-AUTO-003 | AUTO-001 | P0 | passed | 重启后 Windows PowerShell 5.1 将无 BOM UTF-8 的中文总控脚本按本地代码页读取，导致无法解析；修复编码后又发现 JSON 顶层数组在 5.1 与 7 的管道枚举语义不同，错误计为 1 条书源 | 已改为 UTF-8 BOM、显式逐元素展开和原生命令退出码捕获；Windows PowerShell 阶段 0/2、原版 Android 与 HarmonyOS 23/23 conformance 已回归通过 |
| ISSUE-AUTO-004 | AUTO-001 | P0 | running | 阶段 7 真机子脚本仍使用 PowerShell 顶层 JSON 数组的管道解析写法，并含有 Windows PowerShell 5.1 的原生命令 stderr 风险；总控本体通过不等于全链路可恢复 | 统一审计总控调用的子脚本编码、数组解析与原生命令捕获；以 Windows PowerShell 执行阶段 7 路径验证后关闭 |
| ISSUE-AUTO-005 | AUTO-001 / COMPAT-006 | P0 | passed | IMAGE 阅读器激活独立窗口后会暂停 WARN 及以下后台日志；新增 `MANXIA_LEGADO_IMAGE_TRACE` 使用 `logger.warn`，真机首图已执行并返回 DNS 错误，但系统日志中没有任何脱敏 trace，导致目标、Header 与错误分类不可复核 | 已新增受统一 Logger 管理且绕过后台暂停的 WARN 证据通道；真机同一 IMAGE 链路产生 224 条事件、28 个 traceId，planned/request/transport_failure/pipeline_result 与原始源哈希、脱敏 Header、`network_dns` 分类均完整可复核 |
| ISSUE-AUTO-006 | AUTO-001 / UI-001 | P0 | passed | 真机 UI 证据截图脚本 `Capture-LegadoUiAuditScreenshot.ps1` 为无 BOM UTF-8，Windows PowerShell 5.1 将其中文按本地代码页解析，在截图前直接产生 ParserError，因此 UI 回归证据链不可恢复执行 | 已固化 UTF-8 BOM、移除 Windows PowerShell 5.1 不支持的 `ConvertFrom-Json -Depth`；5.1 Parser、真机截图、布局解析与脱敏元数据生成均实际通过 |
| ISSUE-COMPAT-013 | COMPAT-002 / COMPAT-006 | P0 | passed | 真机进入 IMAGE 独立漫画阅读器时，ArkUI 曾报告 `MangaReaderAbilityPage` 在初始渲染期间修改 `pathStack` | 已改为稳定 `NavPathStack` + `UIContext.postFrameCallback` + `FrameCallback.onIdle` 的单次入栈。`Test-MangaReaderFrameIdleDeviceEvidence.ps1` 已验证初始/两次重试的 `request_started=18/21/24`，每次重试仅增加 3；`pathStack changed during render=0`、`TestAbility/entry_test/aa test=0`、应用级 fatal/kill=0，APP 进程持续存活。证据：`tools/legado-compat/evidence/compat-013-frameidle-device-gate.json` |
| ISSUE-COMPAT-016 | COMPAT-002 | P0 | running | `NovelReaderAbilityPage`、`EBookReaderAbilityPage`、`FileEditorAbilityPage`、`ReadAloudPlayerAbilityPage`、`RemoteControlAbilityPage`、`SourceDetailAbilityPage` 仍存在在 `aboutToAppear` 中直接写入 `NavPathStack` 的同源风险 | 统一为稳定栈、帧完成边界、generation 失效和单次入栈；每页具备静态契约与真机入口回归，禁止用 Manga 页面修复掩盖其余入口风险 |
| ISSUE-COMPAT-014 | COMPAT-002 / COMPAT-006 | P0 | running | 同一 IMAGE 章节因单一 DNS 故障进入阅读器后，真机结构化台账在数秒内至少新增 180 条错误记录，其中 90 条属于同一 DNS 类，分散于 `OnlineImageLoader`、资产加载、阅读器和两套流监控；同时写入 78 个错误文件。当前精确消息去重会被不同页面目标绕过，在线首屏 8 页预加载又放大了失败 | 建立不含 URL 的传输失败指纹并跨层聚合；同主机 DNS/TLS 等确定性失败触发短时预加载熔断，但当前可见页及用户主动重试不被阻断；回归要求错误台账有界、首图重试可用且真实程序错误仍单独保留 |
| ISSUE-UI-010 | UI-003 / UI-005 | P0 | running | IMAGE 阅读器 DNS 错误态的布局树包含“加载失败”、错误原因和 `1 / 36`，但同一时刻真机截图中这些文字与黑色阅读背景融为一体，仅剩孤立的“重试”按钮；用户无法判断失败原因、当前位置或是否值得重试 | 将图片错误态收敛为高对比、主题无关且不遮挡手势的状态层，展示本地化错误类别与页码；保留可点击重试和返回路径，并完成黑/浅主题及长错误文本截图回归 |
| ISSUE-COMPAT-015 | COMPAT-002 / COMPAT-006 | P1 | running | `MangaReaderPage` 的 Router 回退参数重建只保留部分字段，会丢失 `sourcePkg`、原始 `contentType`、`skipDatabaseLookup`、`chapterTitle` 等 Legado IMAGE 身份；身份恢复后也未统一写回当前参数，可能使非标准入口误走通用图片传输并失去原始书源哈希 | 统一 Router、NavStack、独立 Ability 三条入口的参数解析与身份回写；增加静态契约并在构建后验证三条入口均保持 sourceId/sourcePkg/contentType/raw SHA 语义 |
| ISSUE-UI-011 | UI-003 / UI-005 | P2 | running | IMAGE 阅读器错误态代码使用 `Image($r('sys.symbol.exclamationmark_circle_fill'))` 渲染系统符号，但真机截图中目标图标完全缺失；同时 DNS 原因仍直接展示底层英文错误文本 | 改用 `SymbolGlyph` 渲染系统符号，并把 DNS/TLS/超时/HTTP/普通网络失败映射为短小的本地化说明；真机截图要求图标、标题、两行长文本、重试按钮与页码均不重叠 |
| ISSUE-UI-012 | UI-003 / UI-005 | P0 | passed | Hypium 真机点击稳定书源标签 ID 后，截图仍显示书库内容并高亮书库；可访问性锚点存在但 HDS 自定义标签点击没有可靠提交选择态 | 已在语义点击路径先同步 HdsTabsController，再通知外层 Swiper；Driver 额外等待 260ms Swiper 动画结束。真机稳定截图同时证明书源内容与书源高亮，证据：`tmp/hypium-hds-book-source-selection-stable/result.json` |
| ISSUE-COMPAT-017 | COMPAT-003 | P1 | passed | 真机 ordinal 142 的 V2 曾在 HTTP 200 下返回 8,567 个与关键词无关的候选；同一原始书源、关键词与原版 Legado test-only instrumentation 返回 50 本，且详情、1,660 章目录与正文均完成 | 已分离界面结果预算与完整对照、对齐 `postForm` 媒体类型，并修复大文档 CSS 回退把 `>` 当后代令牌及遗漏隐式 `tbody` 的问题。重建后 Hypium attempt 16 为 `HTTP 200 / search_nonempty / matched=50 / budget=100 / driver_closed=true`，精确对齐原版搜索数量；详情、目录和正文仍由全工作流治理单独验收。证据：`single-source-reference-111F993…json`、`full-source-v2-hypium-device/hypium-111F993…attempt-16/result.json`。 |
| ISSUE-COMPAT-018 | COMPAT-001 / COMPAT-006 / UI-003 | P0 | passed | Hypium 真机 ordinal 81、82 在冷启动后显示正常空结果，但管理页仍显示“加载中 (1/1)”且卡片无 V2 trace；随后同卡显示 V2 全量执行，说明请求可在 458 条原始记录与 V2 编译记录恢复前经旧内核发出，UI 状态与真实执行不一致 | `NovelInitializer` 已改为单飞完成屏障，管理和搜索入口在屏障完成前不可执行；重建安装后同设备两条书源均为 `HTTP 200 / search_empty / V2 trace / driver_closed=true`。证据：`full-source-v2-hypium-device/source-8D8AA6…`、`source-A222F8…` |
| ISSUE-COMPAT-019 | COMPAT-004 / COMPAT-006 | P0 | passed | 真机启用的云端运行时 API 1 会在应用更新后继续覆盖随包 V2 bridge，导致原版已支持的 `java.toNumChapter` 在编译前被误判为 `unsupported_api` | V2 bridge API 提升为 2，API 1 云端运行时自动回退内置资源；`java.toNumChapter` 已按原版 `JsExtensions`、`AppPattern`、`StringUtils` 实现并注册。ordinal 104 冷启动 Hypium 复测已从 `unsupported_api` 变为具有完整 V2 trace 的 `network`，该源保留 `external_network_unconfirmed`，不误报兼容成功。证据：`full-source-v2-hypium-device/source-EB8311FE…` |
| ISSUE-COMPAT-020 | COMPAT-001 / AUTO-001 | P0 | passed | 真机 ordinal 107（小米阅读）曾实际返回 17 条 V2 搜索结果，兼容库也落盘 `search/http/200/none/search:17`（4 个 option、3 个变量副作用），但自动化只能在返回管理页后读取 trace，导致误判 `ui_trace_mismatch` | 单书源结果与错误态均直接呈现同一份脱敏、哈希绑定的 V2 search trace；Hypium 在离开搜索页前采集。新包真机回归获取 `search/http/404/http/search_failed:http`、`driver_closed=true`，状态机正确归类 `external_network_unconfirmed`，不再误报引擎失败。 |
| ISSUE-UI-013 | UI-003 / UI-005 | P1 | passed | 真机 ordinal 107 从单书源搜索返回后，已落盘的 V2 trace 一度显示为“尚未获得可复核的用户路径证据” | 当前包真机回归已在结果页和管理卡片同时展示 `search/http/404/http/search_failed:http`；Hypium 截图与结构化 trace 一致。保留卡片底部“加载中 (1/1)”视觉噪声给独立加载态审计。 |
| ISSUE-UI-015 | UI-003 / UI-005 | P1 | passed | 真机 ordinal 142 的正常单书源结果页曾把 `V2 trace: search · http · HTTP 200 · ...` 作为结果列表首项直接展示，调试实现细节压缩首屏阅读区域并破坏正常搜索页的信息层级 | 已改为默认折叠的“执行诊断”命令，结果、空态和错误态不再自动暴露 raw trace。Hypium 在正常截图后显式展开同一诊断并采集 `HTTP 200 / search_nonempty / matched=50`，`driver_closed=true`。证据：attempt 16 与 `full-source-v2-hypium-device/hypium-111F993…attempt-17/result.json`、`05-search-outcome.jpeg`。 |
| ISSUE-UI-014 | UI-005 | P1 | passed | 真机筛选书源管理页在两张卡片均已显示后，底部仍显示“加载中…(2/2)”。`hasMoreData` 控制可见尾部却是非响应式字段，分页完成后 ArkUI 不会重组尾部 | 已改为 `@State` 并加入静态契约。相同 Hypium 筛选路径重建安装后，`2/2` 卡片保留、加载尾部消失，V2 `HTTP 200 / search:0` 空结果 trace 未回归。证据：`hypium-01BE155…attempt-1/03-source-management.jpeg`、`attempt-2/03-source-management.jpeg`、`novel-source-pagination-state-contract.json`。 |
| ISSUE-COMPAT-021 | COMPAT-003 / AUTO-001 | P1 | running | 真机 ordinal 110 的 V2 搜索稳定落盘 `ark_web/web_view`、`HTTP 0`、`WEBVIEW_TIMEOUT;stage=navigation_dispatched;targetBegin=0`；同一原始 SHA-256、同一关键词的最新原版固定提交 trace 搜索返回 3 条且 `bookInfoReady=true`。第 5 次 Hypium 回归已将该结果分类为 `semantic_mismatch_reference_nonempty_v2_search_uncompleted`，证明这是 V2 ArkWeb 搜索未完成的兼容缺口，不能再归类为外部端点未确认 | 定位 V2 `RequestPlanner` 对该书源选择 ArkWeb 的条件，以及 `LegadoWebViewExecutor` 在 `loadUrl` 后未观察到目标导航的根因；补充等价 fixture 覆盖请求计划、最终 URL、Cookie 回写和导航事件，再以同一原文和原版 trace 回归结案。证据：`single-source-reference-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582.json`、`full-source-v2-hypium-device/hypium-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582-attempt-5/result.json`、`full-source-v2-hypium-device/source-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582.json`。 |
| ISSUE-COMPAT-022 | COMPAT-001 / UI-003 | P1 | passed | 真机 ordinal 112 在 V2 HTTP 200 空搜索后只显示普通空态，未显示 V2 trace，自动化无法证明该空结果没有回退或吞掉错误 | 单书源空态增加脱敏 trace 与稳定 ID；新包真机回归为 `search/http/200/none/search:0`、`driver_closed=true`，截图文本无重叠。证据：`full-source-v2-hypium-device/source-9EDD01…`。 |
| ISSUE-COMPAT-023 | COMPAT-004 / COMPAT-006 / AUTO-001 | P0 | passed | 真机 ordinal 116（炫动小说）使用的 `java.longToast`、`source.key` 已被 V2 运行时实现，却未登记到 JS API 契约，导致编译快照错误标为 `JS_UNSUPPORTED_API`；全量切换受阻时还会被页面渲染为普通空搜索 | 契约注册表补全两个已实现 API；全量切换阻断改为结构化错误，Hypium 归档可识别其类别；修复后 ordinal 116 真机 V2 为 `search/http/200/none/search:0`、`driver_closed=true`。证据：`full-source-v2-hypium-device/source-580EA21…`。 |
| ISSUE-COMPAT-024 | COMPAT-005 / COMPAT-008 | P1 | running | ordinal 127 先前多次以 `HTTP 0 / web_view` 结束，曾定位到应用级 ArkWeb 宿主争用和目标导航事件未确认。attempt 9 在同一真机、同一原文哈希下不再复现：`ark_web / HTTP 200 / search:0 / driver_closed=true`。这证明当前 V2 路径可完成，但书源没有同源原版 reference，因此不能将空结果称为语义兼容，也不能把历史 HTTP 0 当成已根治。 | 保持运行并降为 P1。补充固定原版提交的同源搜索 trace，随后以相同关键词、相同时间窗口复测；若再次出现 HTTP 0，保留 ArkWeb 生命周期证据并重新提升优先级。证据：attempt 7、attempt 9 `result.json`、`source-A6C42CB…json`。 |
| ISSUE-COMPAT-027 | COMPAT-004 | P0 | passed | 2026-08-02 阶段 0 真机 conformance 发现小文档 HTML bridge 将 Legado 规则 `tr!0` 直接交给标准 CSS matcher，排除索引被静默忽略，返回 3 行而不是与字符串回退一致的 2 行 | bridge CSS 查询现先解析 Legado trailing index，再在 DOM 查询后复用同一过滤器。HarmonyOS conformance 42/42 通过；原版 fixture trace 成功；Hypium ordinal 142 为 `semantic_match`，V2 `matched=50` 且详情、目录、正文完成。证据：`harmony-ohosTest-result-stage0.log`、`android-legado-trace-stage0.log`、attempt-19 `result.json`。 |
| ISSUE-COMPAT-028 | COMPAT-004 / COMPAT-005 | P1 | blocked | ordinal 110 的 ArkWeb 搜索仍与固定原版对齐：同一哈希与关键词均为 `search=3`。新原版 reference 已确认详情 403 后的目录结论是 `TocEmptyException`；V2 attempt 40 在相同目标哈希、空 UA、`text/html`、零重定向和 5 个有效 Header 下仍收到不同的 `HTTP 403 / bodyLength 263 / fingerprint 9fc78f13abf4e9ec / responseClass=html_access_denied`，原版对应值为 `403 / 622 / 2603693b39157602 / html_access_denied`。目录、正文均不得标记为可读。 | 保持阻断。请求方法与有效 Header 集已对齐；剩余差异属于外部动态策略/跨客户端响应体差异，继续收集但不把它误报为规则兼容成功。证据：`single-source-reference-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582-post-header-baseline.json`、`full-source-v2-hypium-device/hypium-0DFE5EDEBA78EB238D7E5FC3593497097A4F03790AD491C9F4169F582-attempt-40/result.json`、`LegadoWorkflowOrchestrator.ets`。 |
| ISSUE-AUTO-026 | AUTO-001 / COMPAT-004 | P1 | passed | 403 响应证据链已修复：V2 受保护响应不再覆盖原始诊断，BookInfo/Toc 均落盘固定摘要；Hypium attempt 40 已持久化 `body=263:9fc78f13abf4e9ec`、`responseClass=html_access_denied`、`GET`、5 个有效 Header 及 `requestHeaderFingerprint=969ee10deb98b28a`。 | 关闭字段丢失治理项。后续外站 403 响应体差异继续由 ISSUE-COMPAT-028 阻断，不得因分类已落盘而宣称详情/目录/正文兼容。证据：`v2-book-info-response-class-parser-contract-stage0.json`、`full-source-v2-hypium-device/hypium-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582-attempt-40/result.json`、`full-source-v2-hypium-device/source-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582.json`。 |
| ISSUE-AUTO-027 | AUTO-001 / COMPAT-004 | P0 | passed | 总控已在 stage0/6/7/8 强制重建当前主 HAP，避免已有产物导致旧代码与新 ohosTest HAP 配对。2026-08-03 stage0 真实执行通过：Android instrumentation 与 HarmonyOS conformance 60/60 均通过，主 HAP 与 ohosTest HAP 均在安装前生成 SHA-256 证据。 | 关闭旧主 HAP 误复用缺口。后续阶段继续以 `harmony-hap-artifacts-<stage>.json` 绑定安装产物；若哈希证据缺失，阶段不得标记为设备通过。证据：`harmony-hap-artifacts-stage0.json`、`harmony-ohosTest-result-stage0.log`、`android-legado-trace-stage0.log`、`Test-LegadoV2FullSourceDeviceRunnerContract.ps1`。 |
| ISSUE-AUTO-021 | AUTO-001 / COMPAT-004 | P2 | passed | 总控此前验证了 JDK 17 却仍用 Harmony JDK 21 运行 Legado Gradle。现已统一为 JDK 17；有界 stage 0 `androidTest` 构建与模拟器 instrumentation 实测成功，产生 6 条脱敏 trace，且无残留 Gradle/Java 进程。 | 关闭。后续原版 Android reference 始终使用已验证的 JDK 17 runtime/PATH，并由 native-process 契约覆盖。证据：`android-legado-gradle-stage0.initial.log`、`android-legado-trace-stage0.log`。 |
| ISSUE-COMPAT-029 | COMPAT-003 / COMPAT-004 | P1 | passed | 2026-08-02 受控 fixture 已实测 Android OkHttp 与 Harmony NetStack 都为 HTTP/1.1，均发送 `user-agent`、定制 header、`keep-alive`、`connection`、`cache-control` 与 `accept-encoding`；连续请求均复用连接并能解压 gzip 响应。Android/Harmony trace 未记录 URL、Cookie、Authorization、header 值或连接指纹。故 ordinal 110 的外站 403 不能归因于这些明文 HTTP 语义。 | 明文 HTTP、重定向、Cookie、压缩和连接复用矩阵已由自动门禁覆盖；TLS/ALPN/cipher 与证书验证差异分别移交 ISSUE-COMPAT-030 与 ISSUE-COMPAT-031。证据：`tools/legado-compat/evidence/android-legado-trace-stage0.log`、`tools/legado-compat/evidence/harmony-ohos-trace-stage0.log`、`tools/legado-compat/evidence/fixture-contract.json`。 |
| ISSUE-COMPAT-030 | COMPAT-003 / COMPAT-004 | P1 | passed | 2026-08-02 双端 stage 0 已证明 Android OkHttp 与 Harmony NetStack 都会发送 `Accept-Encoding`、连续请求均复用 HTTP/1.1 连接并正确解压 gzip fixture。随后两端均通过运行期自签名 HTTPS fixture：`TLSv1.3 / HTTP 1.1 / alpnPresent=true / cipherPresent=true`。最终 trace 只保留协议、布尔值、状态与 marker，不含 header 值、Cookie、正文或连接指纹。 | 关闭受控传输的 HTTP/TLS 观察缺口；不将此结论外推为外站 TLS 指纹完全相同。ordinal 110 的外站 403 响应体差异继续由 ISSUE-COMPAT-028 处理。证据：`tools/legado-compat/evidence/android-legado-trace-stage0.log`、`tools/legado-compat/evidence/harmony-ohos-trace-stage0.log`、`tools/legado-compat/evidence/fixture-contract.json`。 |
| ISSUE-COMPAT-031 | COMPAT-003 / COMPAT-004 | passed | 原版固定提交的 `legado/app/src/main/java/io/legado/app/help/http/HttpHelper.kt` 将全局 OkHttpClient 配置为 `unsafeSSLSocketFactory`、`unsafeTrustManager`、`unsafeHostnameVerifier` 与 `followSslRedirects(true)`；V2 现通过 NetStack `remoteValidation: 'skip'` 在 Legado V2 HTTP transport 内复现该验证语义，不影响漫画图源或普通业务网络。2026-08-02 的运行期自签名 HTTPS fixture 经 ADB/HDC 反向转发后，原版 Android 与 Harmony 真机均取得 `HTTP 200 / TLSv1.3 / HTTP 1.1 / alpnPresent=true / cipherPresent=true`；总控退出后证书和私钥均不存在。ordinal 110 的 403 发生在 TLS 已成功后的 HTTP 响应层，不能用 TLS 验证差异解释。 | 关闭 TLS 验证语义缺口；将 TLS/协议失败的细粒度错误分类作为后续通用网络治理项，而非阻断本项。回归由临时证书生成、HTTPS fixture、Android `LEGADO_TLS_TRACE`、Harmony `MANXIA_LEGADO_TLS_TRACE` 和私钥清理共同构成。证据：`tools/legado-compat/evidence/android-legado-trace-stage0.log`、`tools/legado-compat/evidence/harmony-ohos-trace-stage0.log`、`tools/legado-compat/FixtureTlsServer.mjs`。 |
| ISSUE-COMPAT-032 | COMPAT-003 / COMPAT-004 | P1 | passed | Android 原版与 Harmony 真机 trace 已对齐 `user-agent`、`keep-alive`、`connection`、`cache-control`、`accept-encoding` 五类 Header 的 SHA-256 值。此前仅 `accept-encoding` 不同；V2 现仅在书源和 URL option 未显式声明时注入固定 Legado 基线，设备 conformance 对原版脱敏哈希做固定断言。 | 关闭。受控 HTTP Header 值差异已排除；不得将此结论外推为外站响应体或 TLS 指纹完全相同，ordinal 110 的详情响应差异仍由 ISSUE-COMPAT-028 处理。证据：`android-legado-trace-stage0.log`、`harmony-ohos-trace-stage0.log`。 |
| ISSUE-AUTO-022 | AUTO-001 | P3 | passed | 新增 Harmony Header 指纹 Harness 的运行期 TLS 证书生成将 OpenSSL 进度字符写入 stderr，导致测试成功输出混入无意义噪声 | 证书命令已显式丢弃 stderr，真机复跑只保留结构化通过结果；关闭。 |
| ISSUE-UI-016 | UI-003 / UI-005 | P1 | passed | Hypium 真机截图显示书源管理首屏同时堆叠全局统计、V2 全量策略、全部说明、分组和九个快捷操作；首张书源卡片被挤到屏幕底部。分组模式开关显示“全部”但实际是显示模式循环，未选中的“V2 已验证”在白色背景上只留下绿色空轮廓，标签不可读 | 默认收起快捷操作，V2 说明改为按需详情，未选策略恢复中性色文字/边框，分组开关改为“显示/展开/收起”。真机确认 V2 全量策略、详情展开/收起和安全 UI 路径均可用，`driver_closed=true`。证据：`ui-audit-book-source-management-policy-safe-v3/result.json`。 |
| ISSUE-AUTO-023 | AUTO-001 | P0 | blocked | 旧版真实书源管理页全屏截图可能包含书源卡片地址，不应继续作为长期证据 | 新 Harness 仅在空筛选结果状态截图，安全模式失败时不再生成全屏截图。已精确识别旧证据，但当前自动化环境拒绝执行文件删除，物理清理由环境策略阻断；旧截图不在台账中引用。 |
| ISSUE-AUTO-024 | AUTO-001 | P1 | passed | 安全 UI 审计的空态父容器未被 Driver 发现，失败回收可能重建全屏截图 | 空态可见文本具有稳定 ID，safe-ui-audit 以该锚点断言后才截图；失败路径禁止截图。真机通过，`driver_closed=true`。证据：`ui-audit-book-source-management-policy-safe-v3/result.json`。 |
| ISSUE-UI-017 | UI-003 | P1 | passed | 书源管理页筛选零结果时键盘保持展开，空态按整页高度居中并落在下半部 | 搜索提交用 `UIContext` 清焦点；空态改为占用余下列表区域并从筛选结果下方开始。真机截图确认键盘收起、空态上移且无重叠。证据：`ui-audit-book-source-management-policy-safe-v3/result.json`。 |
| ISSUE-AUTO-025 | AUTO-001 | P0 | passed | 单书源安全阅读 Harness 会保存详情/正文截图，搜索结果测试 ID 还会编码目标地址 | 默认关闭视觉证据，详情和阅读页不再截图，搜索结果身份统一匿名化。ordinal 142 在固定原版对照下真机复跑 Search/BookInfo/Toc/Content 均通过；结构化结果无 URL、无截图名，`driver_closed=true`。证据：`full-source-v2-hypium-device/hypium-111F993…attempt-21/result.json`。 |
| ISSUE-AUTO-010 | AUTO-001 / COMPAT-008 | P1 | passed | attempt 18 的 `UnboundLocalError` 和“硬等 Toc trace”均是 Harness 缺陷。驱动现会采集详情页全部脱敏 trace，并区分“BookInfo 终止、Toc 未启动”与“已执行 Toc 空目录”。attempt 22 成功记录 `book_info` 和 `toc` 两条终态、`driver_closed=true`，无悬挂工作流。 | 保持回归契约：55 项静态检查、Python 编译和每次安全阅读路径的原子状态收敛。后续新增工作流不得重新要求不存在的下游 trace。证据：attempt 22、`Invoke-LegadoV2HypiumNavigation.py`、`Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1`。 |
| ISSUE-AUTO-007 | AUTO-001 / COMPAT-001 | P1 | passed | 真机 runner 以导入数据库中的 `engineMode` 作为 V2 前置断言，会将运行时已切换到 V2 的书源提前拦截；包含 `#` 的原始 URL 也不适合作为 Hypium 选择器 ID | 前置门禁仅校验原文哈希和设备记录，实际 V2 路由以同次用户路径 trace 证明；源卡与单源搜索使用可逆安全 token，驱动在提交前断言同一源身份。正式 runner 静态契约 28 项通过。 |
| ISSUE-AUTO-008 | AUTO-001 / COMPAT-001 / COMPAT-008 | P0 | passed | 全量 Hypium runner 曾仅允许 `safe_search_only`，即使真机已完成搜索、详情、目录和正文，也会把后三项统一写为 `policy_blocked`，导致 458 条台账无法表达真实的 V2 阅读语义 | 已接入 `safe_read_path`：仅对非交互、非付费、能力完整的 TEXT 书源在存在搜索结果时执行详情→目录→正文；其他类型、空结果和受限书源维持结构化安全状态。ordinal 142 总控真机回归为 `search/bookInfo/toc/content = passed`、`driverClosed=true`。证据：`full-source-v2-hypium-device/source-111F993…json`。 |
| ISSUE-AUTO-009 | GOV-002 / COMPAT-003 | P0 | running | 状态机曾以单一 `passed` 汇总 HTTP 200 空结果和未对照的真机路径，容易被误读为 Legado 语义兼容；ArkWeb `HTTP 0 / web_view` 又被降级为泛化 `execution_failure`，无法与已知 ArkWeb 生命周期问题聚类 | 已增加独立 `semanticQualification` 与汇总：仅 `semantic_match` 可声称对照通过；无参考路径为 `execution_verified_no_reference`，ArkWeb HTTP 0 为 `arkweb_unconfirmed`。回归要求状态模块、runner 契约、真机 ordinal 35 证据和自动文档均一致，历史记录不得追溯升格。 |
| ISSUE-AUTO-020 | AUTO-001 | passed | 单书源 Hypium runner 未传 `-Device` 时曾直接报 `DEVICE_SN_REQUIRED_FOR_HYPIUM`。现通过 `hdc list targets` 自动解析唯一在线设备；无设备或多设备时返回明确数量错误而不隐式选择。ordinal 110 在未传设备参数下完成 `safe_read_path` 重跑，结果为 `search=passed / book_info=passed / toc=blocked(toc_endpoint_unconfirmed) / driverClosed=true`，证明自动发现、状态收敛与证据写入均生效。 | 关闭。后续 runner 保持唯一设备自动发现与显式多设备阻断。证据：`tools/legado-compat/evidence/full-source-v2-hypium-device/hypium-0DFE5EDEBA78EB238F628778D7E5FC3593497097A4F03790AD491C9F4169F582-attempt-27/result.json`。 |

## 5. 逐书源验证矩阵

每条书源至少记录：

- 原始文档哈希、类型、编译状态、能力标记和所需交互。
- APP 进程是否存活，是否出现崩溃、ANR 或 Fatal 日志。
- Search/Explore、BookInfo、Toc、Content、File、Review 的执行状态。
- 请求方式、状态码、最终地址可观测性、Cookie/变量副作用和规则输出摘要。
- UI 是否显示真实结果，是否出现空白、卡死、错误提示缺失或结果与 trace 不一致。
- 原版 Legado 同源、同关键词、同工作流的脱敏对照结果。
- 最终分类、问题 ID、修复版本和回归证据。

付费、登录、验证码和可能产生副作用的操作只验证规划、提示和安全边界，不自动绕过或提交。

## 6. 小说与书源页面初始清单

| 页面/组件 | 关键状态 | 状态 |
|---|---|---|
| 小说书架与书源标签 | 空态、正常列表、切换、搜索入口 | planned |
| 小说发现页 | 分类、加载、空结果、错误、刷新 | planned |
| 小说搜索页 | 初始、历史、加载、结果、空结果、失败 | planned |
| 统一详情页（小说） | 骨架、成功、目录、来源、加入书架、受阻 | planned |
| 小说阅读页 / 文本阅读器 | 正文、菜单、目录、设置、翻页、错误 | planned |
| 书源管理页 | 列表、筛选、V2 状态、批量操作、导入结果 | planned |
| 备用书源管理页 | 导入、编辑、启停、删除 | planned |
| 书源调试页 | 搜索、详情、目录、正文、trace、错误分类 | planned |
| 书源引擎页 | 能力状态、执行模式、诊断信息 | planned |
| 书源登录页 | 无会话、WebView、验证码、Cookie 回写、失败 | planned |
| 换源对话框 | 加载、候选、对照、确认、失败 | planned |
| 小说设置页 | 主题、阅读、缓存、同步、入口层级 | planned |
| 替换规则、字典规则、TXT 目录规则页 | 列表、编辑、空态、错误、保存反馈 | planned |
| 小说导入及相关弹窗 | 选择、进度、冲突、完成、失败 | planned |

## 7. UI 审计标准

每张截图按以下维度评分并登记问题：

1. 是否与漫匣整体主题、玻璃标题栏、圆角、阴影和色彩系统一致。
2. 标题、主要操作、次要操作和状态信息是否有清晰层级。
3. 是否存在信息堆叠、重复入口、过多按钮、难以理解的专业术语。
4. 空态、加载态、错误态、阻断态是否明确告诉用户发生了什么以及下一步能做什么。
5. 点击区域、返回路径、批量操作和危险操作是否清晰且可撤销。
6. 长文本、超长书源名、小屏、安全区、键盘和滚动场景是否稳定。
7. 字体、间距、图标、按钮高度、列表密度和对齐是否统一。
8. 是否把“导入成功”“编译成功”“可执行”“已真机验证”混为一谈。

## 8. 完成定义

本任务只有在以下条件全部满足后才能关闭：

- 458 条均有可复核的最终分类，没有 `planned/running/failed` 或未解释差分。
- 可治理的漫匣引擎问题全部修复并通过原版差分与真机回归。
- 外部失败、交互限制和安全阻断均有证据，且 UI 能正确解释。
- 小说与书源页面清单全部完成截图、审计、治理和前后对比。
- debug 构建、HarmonyOS 测试、Android 原版对照、真机安装和关键用户路径全部通过。
