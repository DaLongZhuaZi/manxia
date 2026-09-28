# 本地漫画跨端接续修复事实记录（2026-08-16）

> 本文档记录 2026-08-16 会话中完成的"本地漫画跨端接续"（接续阅读）修复的事实、根因与结论，
> 供后续回归排查与版本回溯参考。验证结论均来自两设备真机日志与目标设备数据库取证。

## 1. 最终验证结论

- 本地漫画跨端接续全链路已打通，用户实测通过：
  - 源端（192.168.5.124）触发接续 → 目标端（192.168.5.133）自动从源端经局域网 TCP
    独立通道（端口 15224）拉取漫画（21 个文件 / 5.3MB，逐文件 SHA-256 校验通过）；
  - 目标端事务导入 comic_info / chapter / page 三表，路径改写为沙箱
    `files/manga_transfer/<bookId>_<ts>/`；
  - 阅读器以 **Local** 模式打开，20 页完整、翻页正常；
  - **连续多次流转**（第二次接续）也能正常拉起源端遥控器页，不再停留在桌面。

## 2. 根因与修复清单（按发现顺序）

| # | 根因（真机验证） | 修复 |
|---|---|---|
| R1 | `DataManager.getComicById/getComicsByIds` 的 `UNION ALL` SQL 引用了 `online_comic_info` 不存在的列（`status/chapterCount/webUrl/apiUrl/coverLocalPath/contentType`），整条 UNION 失效，真机上 100% 返回空 → "comic_info 里有记录却按 id 查不到"，`resolveWidgetManga`/身份解析器全部 not_found | 改为**逐表查询**（先 `comic_info` 单表，再 `online_comic_info`），新增 `convertOnlineComicInfoToComicInfo` 兜底转换。取证：拉取目标设备 `manxia_comic.db` 复跑原 SQL 报 `no such column: status` |
| R2 | 读库记录按键=列名生成（`pageNumber`/`chapterNumber`），但 `convertRecordToPageInfo/convertRecordToChapterInfo` 读 `record.index/chapterIndex` → 序号恒为 undefined；叠加 page 表 `UNIQUE(chapterId, pageNumber)` + `INSERT OR REPLACE` → 20 页全部序号 0，互相覆盖只剩 1 页（最后写入的 020.jpg） | 转换器优先读 `pageNumber`/`chapterNumber` 列；`PageInfoDatabaseRecord` 增加可选 `pageNumber`；`importRemoteComicData` 增加防御：所有页序号相同时按数组顺序重排 |
| R3 | 目标端残留上次接续的残缺数据（1 页）时，`resolveWidgetManga` 直接命中旧漫画，跳过重新传输（"旧缓存短路"） | `MainMenuPage.navigateFromWidgetContinueRead` 接续分支增加 `DataManager.hasCompleteChapterPages` 完整性校验（逐章比对 page 行数 vs pageCount），不完整则自动重新从源端同步（幂等导入：先 DELETE 后 INSERT） |
| R4 | 源端 `MangaReaderPage` 两处 `syncProgress` 上报 `manga.contentType?.toString()`（归一化为 'manga'，不含 local 标记）→ 接续包 `isLocal=false` → 目标端以 **OnlineUndownloaded** 模式打开本地漫画 → 报错失败 | 改为 `buildSyncSourceType(params.contentType/pageParams.contentType)`：本地内容上报 `local_manga`，接续包正确携带 `isLocal=true` |
| R5 | 连续流转时源端遥控器拉起失败：① 600ms 后才重试，此时源端阅读器上下文已随迁移释放（`The caller has been released`）；② 应用随之进入后台，入口上下文受后台启动管控拦截（`The application does not have permission to call the interface`），后续重试与兜底全部无效 → 源端停在桌面 | 重试时间点改为 `[0, 300, 900, 2500]ms`（**0ms 立即发起**，趁阅读器仍在存活窗口内）；候选上下文链改为**阅读器优先**（入口上下文实测连前台态也报权限错误），逐候选失败自动切换 |

## 3. 关键环境事实（长期有效）

- 设备：源端 `192.168.5.124`（hdc 端口 `44879`，配对重建后端口会变，执行前以 `hdc list targets` 为准）；目标端 `192.168.5.133:45069`。
- 两设备的分布式数据对象通道被平台级封禁（`GetAnonyLocalUdid` 无权限），**局域网 TCP 独立通道（端口 15224）是唯一可靠通道**，接续 Want 中经 `remoteControlLanIp/remoteControlLanPort` 传递地址。
- 目标端 133 用户的 hilog 设置为"关闭"，`ContinuationStateHelper.restoreContinuationState` 在接续恢复期间会临时强制 DEBUG（仅运行时生效，不改用户设置）。
- 源端漫画的页面文件位于公共下载目录（`/storage/Users/currentUser/Download/com.dlzz.manxia/manga/...`），传输前经 `SafeFileUtils.accessSync` 校验后逐文件流式发送。

## 4. 涉及文件

- `entry/src/main/ets/Framework/Data/DataManager.ets`：getComicById/getComicsByIds 逐表化、页面/章节序号读取修复、hasCompleteChapterPages、importRemoteComicData 序号防御。
- `entry/src/main/ets/Framework/Database/DatabaseTypes.ets`：PageInfoDatabaseRecord 增加可选 pageNumber。
- `entry/src/main/ets/pages/MainMenuPage.ets`：接续分支页面完整性校验 + 自动重传。
- `entry/src/main/ets/pages/MangaReaderPage.ets`：syncProgress 按阅读器内容类型上报（buildSyncSourceType）。
- `entry/src/main/ets/Framework/Distributed/ContinuationStateHelper.ets`：源端遥控器 0ms 立即拉起 + 候选上下文链 + 兜底候选链。
- `entry/src/main/ets/Framework/Distributed/RemoteControlSocketChannel.ets`、`MangaTransferTypes.ets`：漫画接续传输协议（前序会话完成）。
- `entry/src/main/ets/Framework/Distributed/ContinuationStateHelper.ets`（前序会话）：接续恢复期间 hilog 强制 DEBUG。

## 5. 验证方式备忘

- 设备日志采集：`hdc -t <id> shell hilog | Tee-Object logs\<name>.txt`（本次会话产物：
  `target*_live.txt`、`afterfix*.txt`，均已停止采集）。
- 数据库取证：`hdc file recv /data/app/el2/100/database/com.dlzz.manxia/entry/rdb/manxia_comic.db*` 后用 sqlite3 复跑可疑 SQL 与检查 `PRAGMA index_list`/`table_info`。
- 构建：`$env:DEVECO_SDK_HOME='F:\DevEco Studio\sdk'; hvigorw.bat assembleHap -p product=default -p buildMode=debug --no-daemon`。
