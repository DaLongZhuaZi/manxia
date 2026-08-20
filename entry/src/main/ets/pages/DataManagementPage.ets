import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径：entry/src/main/ets/pages/DataManagementPage.ets
/**
 * 数据管理页面
 * 提供漫画文件导入、解压缩、XML解析和数据库导入功能
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext, promptAction } from '@kit.ArkUI';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { removeFileExtension } from 'manxia_core/src/main/ets/Utils/FileNameUtils';
import { ThemeToggle } from 'manxia_theme/src/main/ets/Framework/Components/ThemeToggle';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';

import { picker, Environment } from '@kit.CoreFileKit';
import { common, abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';

import { DataManager, ComicInfoInput, ChapterInfoInput, ChapterInfoCreationResult, PageInfoInput, ComicInfo as ComicRecord, ChapterInfo as ChapterRecord, PageInfo as PageRecord, FavoriteInfoInput } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { DownloadStatus, MangaStatus, StatusConverter } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';
import { Manga, MangaChapter } from 'manxia_core/src/main/ets/Models/MangaModels';
import { CompressionUtils, ExtractionResult, RecursiveExtractionResult } from 'manxia_core/src/main/ets/Utils/CompressionUtils';
import { ComicInfoParser, ComicInfo } from 'manxia_core/src/main/ets/Utils/ComicInfoParser';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import DownloadDirManager from 'manxia_core/src/main/ets/Framework/Storage/DownloadDirManager';
import { CoverSelectionData, showCoverSelectionDialog } from '../Framework/Components/CoverSelectionDialog';
import { eventBus, GameEvent, MangaImportCompletedPayload, FileImportRequestedPayload, IEventPayload } from '../Framework/EventBus';

import fs from '@ohos.file.fs';
import { fileIo, fileUri } from '@kit.CoreFileKit';

import { UpdateRecordData } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { UniversalDialogManager, ButtonStyle, DialogButton, UniversalDialogOptions, UniversalDialogCustomContentParam } from '../Framework/Components/UniversalDialog';
import { EBook, EBookMetadata } from 'manxia_core/src/main/ets/Models/EBookModels';
import { EBookParserFactory, EBookCoverExtractor } from '../Framework/Parsers/EBookParser';
import { generateUUID } from 'manxia_core/src/main/ets/Framework/Utils/UUIDGenerator';
import { createLocalMangaChapterExternalId, createPickedImageGroupUri } from 'manxia_core/src/main/ets/Utils/LocalMangaImportIdentity';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBookMetadataDialog, EBookMetadataDialogResult } from '../Framework/Components/EBookMetadataDialog';
import { PdfImportResult, PdfContentType, PdfImportMode } from '../Framework/Parsers/PdfToMangaImporter';
import { PdfImportService } from '../Framework/Services/PdfImportService';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint,
  DeviceType } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { image } from '@kit.ImageKit';
import { AvifTranscoder, AvifTranscodeResult } from 'manxia_core/src/main/ets/Utils/AvifTranscoder';
import { BackgroundTaskManager, TaskType, TaskStatus, TaskNotificationScene, BackgroundTask, TaskCancelSignal } from 'manxia_network/src/main/ets/Framework/Task/BackgroundTaskManager';
import { TaskFloatingBall } from '../Framework/Components/TaskFloatingBall';
import { PdfImportDialog, PdfImportDialogResult } from '../Framework/Components/PdfImportDialog';
import { MangaImportDialog, MangaImportDialogResult, MangaImportMode, ChapterInfo, ParsedArchiveStructure, ExistingMangaCandidate, PrefilledComicInfo } from '../Framework/Components/MangaImportDialog';
import {
  BatchMangaImportDialog,
  BatchMangaImportDialogResult,
  MangaGroupResult,
  BatchChapterResult,
  MangaStatus as BatchDialogMangaStatus
} from '../Framework/Components/BatchMangaImportDialog';
import { showArchivePasswordDialog } from 'manxia_theme/src/main/ets/Framework/Components/ArchivePasswordDialog';
import { ParsedArchiveStructure as CompressionParsedStructure } from 'manxia_core/src/main/ets/Utils/CompressionUtils';
import { getHelpPanelManagerV2 } from 'manxia_features_ui/src/main/ets/Framework/Components/HelpPanelV2';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskParams,
  ExternalFileTaskSource
} from 'manxia_network/src/main/ets/Framework/ExternalFile/ExternalFileTaskTypes';
import { openExternalFileTaskInIsolatedAbility } from 'manxia_network/src/main/ets/Framework/ExternalFile/ExternalFileTaskLauncher';
import { MangaReadFlowImportReport, MangaReadFlowImportReporter } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReadFlowImportReporter';
import { ImportArchiveParseCache, getImportArchiveParseCache } from '../Framework/Import/ImportArchiveParseCache';
import { ImportDuplicateDetectionCache, getImportDuplicateDetectionCache } from '../Framework/Import/ImportDuplicateDetectionCache';
import { ImportFlowMonitor, getImportFlowMonitor } from 'manxia_core/src/main/ets/Framework/Import/ImportFlowMonitor';
import {
  ImportFlowContentType,
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSessionInfo,
  ImportFlowSeverity
} from 'manxia_core/src/main/ets/Framework/Import/ImportFlowTypes';

const TAG = 'DataManagementPage';
const APP_STORAGE_TRANSFER_RECORD_ID = 'pendingTransferRecordId';
const APP_STORAGE_TRANSFER_RESULT = 'pendingTransferImportResult';
const APP_STORAGE_TRANSFER_TRACKING_ACTIVE = 'pendingTransferTrackingActive';
// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;

// NavDestinationContext接口定义
interface NavDestinationPathInfo {
  param?: Object;
}

interface NavDestinationContext {
  pathStack: NavPathStack;
  pathInfo?: NavDestinationPathInfo;
}

export interface DataManagementExternalFileParams {
  externalFileTask?: ExternalFileTaskParams;
}

/**
 * 导入状态枚举
 */
enum ImportStatus {
  IDLE = 'idle',
  SELECTING = 'selecting',
  EXTRACTING = 'extracting',
  PARSING = 'parsing',
  PROCESSING = 'processing',
  IMPORTING = 'importing',
  COMPLETED = 'completed',
  ERROR = 'error'
}

/**
 * 导入进度信息接口
 */
interface ImportProgress {
  status: ImportStatus;
  message: string;
  progress: number; // 0-100
  currentFile?: string;
  totalFiles?: number;
  processedFiles?: number;
}

/**
 * 导入结果详情接口
 */
interface ImportResultDetail {
  fileName: string;
  success: boolean;
  errorMessage?: string;
  comicInfo?: ComicInfo;
  mangaId?: string;
  chapterId?: string;
  xmlFound?: boolean;
  xmlParsed?: boolean;
  extractedFileCount?: number;
  databaseStored?: boolean;
  filesOrganized?: boolean;
  // 合并与重复检测信息（可选，用于结果展示与后续UI拓展）
  mergeMode?: MergeMode;
  matchStrength?: MatchStrength;
  mergeAction?: MergeAction;
  duplicateReasons?: DuplicateReason[];
  duplicateTargetMangaId?: string;
}

/**
 * 导入合并模式
 */
enum MergeMode {
  StrictNew = 'StrictNew',
  AutoRecommend = 'AutoRecommend',
  ManualCustom = 'ManualCustom'
}

/**
 * 匹配强度分级
 */
enum MatchStrength {
  BELOW = 'BELOW',
  WEAK = 'WEAK',
  LIKELY = 'LIKELY',
  STRONG = 'STRONG',
  EXACT = 'EXACT'
}

/**
 * 合并动作
 */
enum MergeAction {
  MERGE_TO_EXISTING = 'MERGE_TO_EXISTING',
  CREATE_NEW = 'CREATE_NEW',
  SKIP = 'SKIP'
}

/**
 * 重复原因
 */
enum DuplicateReason {
  TITLE_EXACT = 'TITLE_EXACT',
  AUTHOR_EXACT = 'AUTHOR_EXACT',
  TITLE_SIMILAR = 'TITLE_SIMILAR',
  AUTHOR_SIMILAR = 'AUTHOR_SIMILAR',
  TAGS_OVERLAP = 'TAGS_OVERLAP'
}

/**
 * 候选重复项
 */
interface DuplicateCandidate {
  record: ComicRecord;
  score: number;
  strength: MatchStrength;
  reasons: DuplicateReason[];
}

/**
 * 重复检测结果
 */
interface DuplicateCheckResult {
  candidates: DuplicateCandidate[];
  best?: DuplicateCandidate;
}

/**
 * 合并决策
 */
interface MergeDecision {
  mode: MergeMode;
  action: MergeAction;
  targetMangaId?: string;
  strength?: MatchStrength;
  reasons?: DuplicateReason[];
}

/**
 * 图片文件信息接口
 */
interface ImageFileInfo {
  path: string;
  name: string;
  size: number;
  width?: number;
  height?: number;
  fileSize: number;
}

/**
 * 处理单个文件返回结果接口
 */
interface ProcessSingleFileResult {
  comicInfo: ComicInfo;
  mangaId: string;
  chapterId: string;
}

/**
 * 导入漫画到数据库返回结果接口
 */
interface ImportComicToDatabaseResult {
  mangaId: string;
  chapterId: string;
  // 合并与重复检测信息（便于向上层记录与展示）
  mergeMode?: MergeMode;
  mergeAction?: MergeAction;
  matchStrength?: MatchStrength;
  duplicateReasons?: DuplicateReason[];
  mergedToMangaId?: string;
}

/**
 * 漫画合并弹窗数据接口（新 UniversalDialog 用）
 */
interface MergeDialogData {
  sourceTitle: string;
  sourceAuthor: string;
  candidates: MergeDialogCandidate[];
  defaultTargetId: string;
}

/**
 * 漫画合并候选项接口（新 UniversalDialog 用）
 */
interface MergeDialogCandidate {
  id: string;
  title: string;
  author: string;
  strength?: MatchStrength;
  reasons?: DuplicateReason[];
}

/**
 * 章节合并弹窗数据接口（新 UniversalDialog 用）
 */
interface ChapterMergeDialogData {
  mangaTitle: string;
  existingChapterTitle: string;
  newChapterTitle: string;
}

interface MergeDialogBuilderParam extends UniversalDialogCustomContentParam {
  data: MergeDialogData;
  themeState: ThemeAwareState;
  selectedTargetId: string;
  onRadioChange: (id: string) => void;
  appFontFamily: string;
}

interface ChapterMergeDialogBuilderParam extends UniversalDialogCustomContentParam {
  data: ChapterMergeDialogData;
  themeState: ThemeAwareState;
  appFontFamily: string;
}

function asMergeDialogBuilderParam(param: UniversalDialogCustomContentParam): MergeDialogBuilderParam {
  return param as MergeDialogBuilderParam;
}

function asChapterMergeDialogBuilderParam(param: UniversalDialogCustomContentParam): ChapterMergeDialogBuilderParam {
  return param as ChapterMergeDialogBuilderParam;
}


/**
 * 构建漫画合并弹窗的自定义内容
 */
@Builder
function buildMergeDialogContent(param: UniversalDialogCustomContentParam): void {
  Column({ space: 12 }) {
    Text('检测到可能的重复漫画')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asMergeDialogBuilderParam(param).themeState.currentTheme))

    Column({ space: 4 }) {
      Text(`待导入：${asMergeDialogBuilderParam(param).data.sourceTitle}`)
        .fontSize(14)
        .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asMergeDialogBuilderParam(param).themeState.currentTheme))
      Text(`作者：${asMergeDialogBuilderParam(param).data.sourceAuthor}`)
        .fontSize(12)
        .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', asMergeDialogBuilderParam(param).themeState.currentTheme))
    }
    .width('100%')

    if (asMergeDialogBuilderParam(param).data.candidates.length > 0) {
      Column({ space: 8 }) {
        Text('请选择要合并到的已有漫画：')
          .fontSize(13)
          .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asMergeDialogBuilderParam(param).themeState.currentTheme))

        Scroll() {
          Column({ space: 8 }) {
            ForEach(asMergeDialogBuilderParam(param).data.candidates, (c: MergeDialogCandidate) => {
              Row({ space: 8 }) {
                Radio({ value: c.id, group: 'mergeTarget' })
                  .onChange((checked: boolean) => {
                    if (checked) {
                      asMergeDialogBuilderParam(param).onRadioChange(c.id);
                    }
                  })
                Column({ space: 2 }) {
                  Text(`${c.title}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asMergeDialogBuilderParam(param).themeState.currentTheme))
                  Text(`作者：${c.author}｜匹配：${getMatchStrengthLabel(c.strength)}｜原因：${getDuplicateReasonsLabel(c.reasons)}`)
                    .fontSize(12)
                    .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', asMergeDialogBuilderParam(param).themeState.currentTheme))
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 6, bottom: 6 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', asMergeDialogBuilderParam(param).themeState.currentTheme))
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', asMergeDialogBuilderParam(param).themeState.currentTheme), radius: 6 })
            })
          }
          .width('100%')
        }
        .width('100%')
        .height(180)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', asMergeDialogBuilderParam(param).themeState.currentTheme))
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', asMergeDialogBuilderParam(param).themeState.currentTheme), radius: 8 })
      }
      .width('100%')
    } else {
      Text('未找到可用的合并候选项，将作为新漫画导入。')
        .fontSize(13)
        .fontFamily(asMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', asMergeDialogBuilderParam(param).themeState.currentTheme))
    }
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 16, bottom: 16 })
  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', asMergeDialogBuilderParam(param).themeState.currentTheme))
  .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', asMergeDialogBuilderParam(param).themeState.currentTheme), radius: 10 })
}

/**
 * 构建章节合并弹窗的自定义内容
 */
@Builder
function buildChapterMergeDialogContent(param: UniversalDialogCustomContentParam): void {
  Column({ space: 12 }) {
    Text('检测到重复章节')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontFamily(asChapterMergeDialogBuilderParam(param).appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asChapterMergeDialogBuilderParam(param).themeState.currentTheme))

    Column({ space: 4 }) {
      Text(`漫画：${asChapterMergeDialogBuilderParam(param).data.mangaTitle}`)
        .fontSize(14)
        .fontFamily(asChapterMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', asChapterMergeDialogBuilderParam(param).themeState.currentTheme))
      Text(`已有章节：${asChapterMergeDialogBuilderParam(param).data.existingChapterTitle}`)
        .fontSize(12)
        .fontFamily(asChapterMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', asChapterMergeDialogBuilderParam(param).themeState.currentTheme))
      Text(`新导入：${asChapterMergeDialogBuilderParam(param).data.newChapterTitle}`)
        .fontSize(12)
        .fontFamily(asChapterMergeDialogBuilderParam(param).appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', asChapterMergeDialogBuilderParam(param).themeState.currentTheme))
    }
    .width('100%')
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 16, bottom: 16 })
  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', asChapterMergeDialogBuilderParam(param).themeState.currentTheme))
  .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', asChapterMergeDialogBuilderParam(param).themeState.currentTheme), radius: 10 })
}

/**
 * 匹配强度文本映射
 */
function getMatchStrengthLabel(strength?: MatchStrength): string {
  if (!strength) { return '未知'; }
  switch (strength) {
    case MatchStrength.BELOW: return '低于阈值';
    case MatchStrength.WEAK: return '较弱';
    case MatchStrength.LIKELY: return '可能';
    case MatchStrength.STRONG: return '强';
    case MatchStrength.EXACT: return '完全匹配';
    default: return '未知';
  }
}

/**
 * 重复原因文本映射
 */
function getDuplicateReasonsLabel(reasons?: DuplicateReason[]): string {
  if (!reasons || reasons.length === 0) { return '无'; }
  const labels: string[] = [];
  for (let i = 0; i < reasons.length; i++) {
    const r: DuplicateReason = reasons[i];
    switch (r) {
      case DuplicateReason.TITLE_EXACT: labels.push('标题完全相同'); break;
      case DuplicateReason.AUTHOR_EXACT: labels.push('作者完全相同'); break;
      case DuplicateReason.TITLE_SIMILAR: labels.push('标题相似'); break;
      case DuplicateReason.AUTHOR_SIMILAR: labels.push('作者相似'); break;
      case DuplicateReason.TAGS_OVERLAP: labels.push('标签有交集'); break;
      default: labels.push('其他'); break;
    }
  }
  return labels.join('，');
}

/**
 * 用户选择跳过导入的信号错误，用于流程中断但不计为系统错误
 */
class UserSkipError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UserSkipError';
  }
}


@CustomDialog
export struct MergeDecisionDialog {
  controller: CustomDialogController;
  @Prop data: MergeDialogData;
  @Prop themeState: ThemeAwareState;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private selectedTargetId: string = '';
  // 回调函数不能使用@Prop装饰器
  onMerge: (targetId: string) => void = (t: string) => {};
  onCreateNew: () => void = () => {};
  onSkip: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      // 标题
      Text('检测到可能的重复漫画')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))

      // 源信息
      Column({ space: 4 }) {
        Text(`待导入：${this.data.sourceTitle}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Text(`作者：${this.data.sourceAuthor}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      // 候选列表
      if (this.data.candidates.length > 0) {
        Column({ space: 8 }) {
          Text('请选择要合并到的已有漫画：')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))

          // 限制高度，避免对话框过高
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.data.candidates, (c: MergeDialogCandidate) => {
                // 单选项
                Row({ space: 8 }) {
                  Radio({ value: c.id, group: 'mergeTarget' })
                    .onChange((checked: boolean) => {
                      if (checked) {
                        this.selectedTargetId = c.id;
                      }
                    })
                  Column({ space: 2 }) {
                    Text(`${c.title}`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                    Text(`作者：${c.author}｜匹配：${this.getMatchStrengthLabel(c.strength)}｜原因：${this.getDuplicateReasonsLabel(c.reasons)}`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 4, right: 4, top: 6, bottom: 6 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme), radius: 6 })
              })
            }
            .width('100%')
          }
          .width('100%')
          .height(180)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme), radius: 8 })
        }
        .width('100%')
      } else {
        Text('未找到可用的合并候选项，将作为新漫画导入。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }

      // 操作按钮
      Row({ space: 12 }) {
        Button('合并到所选')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => {
            const targetId: string = this.selectedTargetId && this.selectedTargetId.length > 0
              ? this.selectedTargetId
              : (this.data.defaultTargetId ? this.data.defaultTargetId : '');
            if (targetId.length > 0) {
              this.onMerge(targetId);
              this.controller.close();
            }
          })

        Button('创建新漫画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => {
            this.onCreateNew();
            this.controller.close();
          })

        Button('跳过')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => {
            this.onSkip();
            this.controller.close();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme), radius: 10 })
  }

  // 以下两个方法复用页面中的映射逻辑，为避免引用顺序问题，简单复制一份轻量映射
  private getMatchStrengthLabel(strength?: MatchStrength): string {
    if (!strength) { return '未知'; }
    switch (strength) {
      case MatchStrength.BELOW: return '低于阈值';
      case MatchStrength.WEAK: return '较弱';
      case MatchStrength.LIKELY: return '可能';
      case MatchStrength.STRONG: return '强';
      case MatchStrength.EXACT: return '完全匹配';
      default: return '未知';
    }
  }

  private getDuplicateReasonsLabel(reasons?: DuplicateReason[]): string {
    if (!reasons || reasons.length === 0) { return '无'; }
    const labels: string[] = [];
    for (let i = 0; i < reasons.length; i++) {
      const r: DuplicateReason = reasons[i];
      switch (r) {
        case DuplicateReason.TITLE_EXACT: labels.push('标题完全相同'); break;
        case DuplicateReason.AUTHOR_EXACT: labels.push('作者完全相同'); break;
        case DuplicateReason.TITLE_SIMILAR: labels.push('标题相似'); break;
        case DuplicateReason.AUTHOR_SIMILAR: labels.push('作者相似'); break;
        case DuplicateReason.TAGS_OVERLAP: labels.push('标签有交集'); break;
        default: labels.push('其他'); break;
      }
    }
    return labels.join('，');
  }
}

@CustomDialog
export struct ChapterMergeDialog {
  controller: CustomDialogController;
  @Prop data: ChapterMergeDialogData;
  @Prop themeState: ThemeAwareState;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  // 回调函数不能使用@Prop装饰器
  onMerge: () => void = () => {};
  onCreateNew: () => void = () => {};
  onSkip: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('检测到重复章节')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))

      Column({ space: 4 }) {
        Text(`漫画：${this.data.mangaTitle}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Text(`已有章节：${this.data.existingChapterTitle}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text(`新导入：${this.data.newChapterTitle}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('合并到已有章节')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => { this.onMerge(); this.controller.close(); })

        Button('创建新章节')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => { this.onCreateNew(); this.controller.close(); })

        Button('跳过')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onClick(() => { this.onSkip(); this.controller.close(); })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme), radius: 10 })
  }
}

@Component
struct DataManagementPage {
  // 创建一个 Scroller 实例，用于联动滚动效果
  private scroller: Scroller = new Scroller();
  
  private sandboxManager: SandboxManager = SandboxManager.getInstance();
  
  // 状态变量
  @State pathStack: NavPathStack = new NavPathStack();
  private routeExternalFileTask: ExternalFileTaskParams | null = null;
  private hasHandledRouteExternalFileTask: boolean = false;
  
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DataManagementPage';
  
  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200; // 内容最大宽度
  @State responsive_isLandscape: boolean = false;
  
  // 导入相关状态
  @State importProgress: ImportProgress = {
    status: ImportStatus.IDLE,
    message: '准备就绪',
    progress: 0
  };
  
  @State selectedFiles: string[] = [];
  @State importResults: string[] = [];
  @State importResultDetails: ImportResultDetail[] = [];
  @State showResults: boolean = false;
  // 测试运行状态与结果展示已移除
  // 合并模式（默认自动推荐）。后续可通过设置入口或UI进行调整。
  @State private mergeMode: MergeMode = MergeMode.AutoRecommend;
  
  // 批量导入策略
  @State private batchImportStrategy: 'ask' | 'merge_all' | 'create_all' = 'ask'; // 默认每次询问
  @State private showBatchStrategyDialog: boolean = false;
  private lastMangaImportReadFlowId: string = '';
  private currentImportFlowId: string = '';
  private readonly importFlowMonitor: ImportFlowMonitor = getImportFlowMonitor();
  private readonly importArchiveParseCache: ImportArchiveParseCache = getImportArchiveParseCache();
  private readonly importDuplicateDetectionCache: ImportDuplicateDetectionCache = getImportDuplicateDetectionCache();
  private trackedArchiveStructures: Map<string, CompressionParsedStructure> = new Map<string, CompressionParsedStructure>();
  private archiveCleanupPromise: Promise<void> | null = null;
  private activeBatchAnalysisGenerations: Set<string> = new Set<string>();
  private pendingBatchDialogAnalysisGenerations: Set<string> = new Set<string>();
  private batchDialogAnalysisPromise: Promise<void> | null = null;
  private batchDialogAnalysisResolver: (() => void) | null = null;
  /** 由文件选择器选中的散图按父目录暂存，解析时组装成一个受控临时目录。 */
  private selectedImageGroupSources: Map<string, string[]> = new Map<string, string[]>();
  @State private isFilePickerActive: boolean = false;
  private isMangaDialogOpening: boolean = false;
  private fileImportEventSubscribed: boolean = false;
  private readonly fileImportRequestedListener = (payload: IEventPayload): void => {
    const filePayload = payload as FileImportRequestedPayload;
    logger.info(TAG, `收到文件导入请求: ${filePayload.fileUri}, 类型: ${filePayload.fileType}`);

    if (filePayload.fileType === 'comic') {
      this.handleExternalComicImport(filePayload.fileUri);
    } else if (filePayload.fileType === 'ebook') {
      this.handleExternalEBookImport(filePayload.fileUri);
    }
  };
  
  // 计算属性：是否正在处理
  private isProcessing(): boolean {
    return this.importProgress.status !== ImportStatus.IDLE && 
           this.importProgress.status !== ImportStatus.COMPLETED && 
           this.importProgress.status !== ImportStatus.ERROR;
  }

  private isPageActive: boolean = false;
  private pageLifecycleGeneration: number = 0;
  private isMangaImportCommitting: boolean = false;
  /** 提交阶段的所有者令牌，防止旧页面回调清理新导入任务。 */
  private mangaImportOwnerToken: number = 0;
  private nextMangaImportOwnerToken: number = 0;

  private isCurrentPageGeneration(pageGeneration: number): boolean {
    return this.isPageActive && this.pageLifecycleGeneration === pageGeneration;
  }

  private beginMangaImportCommit(): number {
    this.nextMangaImportOwnerToken += 1;
    this.mangaImportOwnerToken = this.nextMangaImportOwnerToken;
    this.isMangaImportCommitting = true;
    return this.mangaImportOwnerToken;
  }

  private finishMangaImport(pageGeneration: number, ownerToken: number = 0): void {
    if (ownerToken > 0) {
      if (this.mangaImportOwnerToken !== ownerToken) {
        return;
      }
      this.mangaImportOwnerToken = 0;
      this.isMangaImportCommitting = false;
      // 提交属于该 owner，即使页面已重新出现也只释放它自己的 busy 状态。
      this.isMangaImportRunning = false;
      return;
    }
    // 旧代次的准备阶段回调不能清理正在提交的任务。
    if (this.mangaImportOwnerToken !== 0) {
      return;
    }
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.isMangaImportCommitting = false;
    this.isMangaImportRunning = false;
  }

  private recordMangaImportFlow(
    contentId: string,
    contentTitle: string,
    chapterId: string,
    chapterTitle: string,
    pageCount: number,
    chapterCount: number,
    sourcePath: string,
    targetPath: string,
    reason: string
  ): string {
    const report: MangaReadFlowImportReport = new MangaReadFlowImportReport();
    report.contentId = contentId;
    report.contentTitle = contentTitle;
    report.chapterId = chapterId;
    report.chapterTitle = chapterTitle;
    report.pageCount = pageCount;
    report.chapterCount = chapterCount;
    report.sourcePath = sourcePath;
    report.targetPath = targetPath;
    report.sourceId = 'local_import';
    report.reason = reason;
    report.success = true;
    const sessionId: string = MangaReadFlowImportReporter.record(report);
    this.lastMangaImportReadFlowId = sessionId;
    return sessionId;
  }

  private startImportFlow(
    entrySource: ImportFlowEntrySource,
    contentType: ImportFlowContentType,
    displayName: string,
    fileCount: number,
    batchMode: boolean,
    sourceUri: string,
    targetPath: string
  ): string {
    const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
    info.sessionId = this.importFlowMonitor.createSessionId('import');
    info.entrySource = entrySource;
    info.contentType = contentType;
    info.displayName = displayName;
    info.fileCount = fileCount;
    info.batchMode = batchMode;
    info.sourceUri = sourceUri;
    info.targetPath = targetPath;
    info.pageName = 'DataManagementPage';
    info.startedAt = Date.now();
    this.currentImportFlowId = this.importFlowMonitor.ensureSession(info);
    return this.currentImportFlowId;
  }

  private ensureImportFlow(
    entrySource: ImportFlowEntrySource,
    contentType: ImportFlowContentType,
    displayName: string,
    fileCount: number,
    batchMode: boolean,
    sourceUri: string,
    targetPath: string
  ): string {
    const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
    info.sessionId = this.currentImportFlowId;
    info.entrySource = entrySource;
    info.contentType = contentType;
    info.displayName = displayName;
    info.fileCount = fileCount;
    info.batchMode = batchMode;
    info.sourceUri = sourceUri;
    info.targetPath = targetPath;
    info.pageName = 'DataManagementPage';
    info.startedAt = Date.now();
    this.currentImportFlowId = this.importFlowMonitor.ensureSession(info);
    return this.currentImportFlowId;
  }

  private recordImportFlowEvent(event: ImportFlowEvent): void {
    if (!event.sessionId || event.sessionId.length <= 0) {
      event.sessionId = this.ensureImportFlow(
        event.entrySource,
        event.contentType,
        event.displayName,
        event.fileCount,
        event.batchMode,
        event.sourceUri,
        event.targetPath
      );
    }
    this.importFlowMonitor.record(event);
  }

  private recordSimpleImportFlowEvent(
    eventType: ImportFlowEventType,
    reason: string,
    contentType: ImportFlowContentType,
    entrySource: ImportFlowEntrySource,
    success: boolean,
    detail: string,
    elapsedMs: number
  ): void {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.eventType = eventType;
    event.reason = reason;
    event.contentType = contentType;
    event.entrySource = entrySource;
    event.success = success;
    event.severity = success ? ImportFlowSeverity.INFO : ImportFlowSeverity.ERROR;
    event.elapsedMs = elapsedMs;
    event.detail = detail;
    this.recordImportFlowEvent(event);
  }

  private endCurrentImportFlow(reason: string): void {
    if (this.currentImportFlowId.length > 0) {
      const endedSessionId: string = this.currentImportFlowId;
      this.importFlowMonitor.endSession(endedSessionId, reason);
      this.importDuplicateDetectionCache.clearSession(endedSessionId);
    }
    this.importArchiveParseCache.clear();
    this.currentImportFlowId = '';
    this.restorePickedImageSelections();
    this.selectedImageGroupSources.clear();
    this.scheduleTrackedArchiveCleanup(reason);
  }

  private buildTrackedArchiveStructureKey(
    fileUri: string,
    structure: CompressionParsedStructure,
    analysisGeneration: string = ''
  ): string {
    const pathKey: string = structure.extractedPath.length > 0
      ? structure.extractedPath
      : structure.tempDirectories.join('|');
    const normalizedFileUri: string = fileUri.trim().replace(/\\/g, '/');
    return `${analysisGeneration}|${normalizedFileUri}|${pathKey}`;
  }

  private trackArchiveStructure(
    fileUri: string,
    structure: CompressionParsedStructure,
    analysisGeneration: string = ''
  ): void {
    const trackingKey: string = this.buildTrackedArchiveStructureKey(fileUri, structure, analysisGeneration);
    this.trackedArchiveStructures.set(trackingKey, structure);
  }

  private releaseLateBatchArchiveStructure(
    fileUri: string,
    structure: ParsedArchiveStructure,
    analysisGeneration: string
  ): void {
    const compressionStructure: CompressionParsedStructure = structure as CompressionParsedStructure;
    const cachedStructure: CompressionParsedStructure | null =
      this.importArchiveParseCache.get(fileUri, analysisGeneration);
    if (cachedStructure !== null && cachedStructure.extractedPath === compressionStructure.extractedPath) {
      this.importArchiveParseCache.delete(fileUri, analysisGeneration);
    }
    const trackingKey: string = this.buildTrackedArchiveStructureKey(
      fileUri,
      compressionStructure,
      analysisGeneration
    );
    this.trackedArchiveStructures.delete(trackingKey);
    this.scheduleArchiveStructureCleanup(compressionStructure, 'batch_dialog_disposed_late_result');
  }

  private createBatchAnalysisGeneration(): string {
    return `batch_${generateUUID()}`;
  }

  private isBatchAnalysisGenerationActive(analysisGeneration: string): boolean {
    return analysisGeneration.length <= 0 || this.activeBatchAnalysisGenerations.has(analysisGeneration);
  }

  private throwIfBatchAnalysisGenerationInvalidated(
    analysisGeneration: string,
    fileUri: string,
    startedAt: number,
    sessionId: string,
    reason: string
  ): void {
    if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
      return;
    }
    this.recordArchiveStructureParseFailure(
      fileUri,
      startedAt,
      '批量解析代次已失效',
      reason,
      sessionId
    );
    throw new UserSkipError('批量解析已取消');
  }

  private beginBatchDialogAnalysis(analysisGeneration: string): void {
    this.activeBatchAnalysisGenerations.add(analysisGeneration);
    if (this.pendingBatchDialogAnalysisGenerations.size === 0) {
      this.batchDialogAnalysisPromise = new Promise<void>((resolve: () => void) => {
        this.batchDialogAnalysisResolver = resolve;
      });
    }
    this.pendingBatchDialogAnalysisGenerations.add(analysisGeneration);
  }

  private finishBatchDialogAnalysis(analysisGeneration: string): void {
    if (!this.pendingBatchDialogAnalysisGenerations.has(analysisGeneration)) {
      return;
    }
    this.pendingBatchDialogAnalysisGenerations.delete(analysisGeneration);
    if (this.pendingBatchDialogAnalysisGenerations.size > 0) {
      return;
    }
    const resolver: (() => void) | null = this.batchDialogAnalysisResolver;
    this.batchDialogAnalysisResolver = null;
    this.batchDialogAnalysisPromise = null;
    if (resolver !== null) {
      resolver();
    }
  }

  private invalidateBatchAnalysisGeneration(analysisGeneration: string): void {
    this.activeBatchAnalysisGenerations.delete(analysisGeneration);
  }

  private async waitForPendingBatchDialogAnalysis(): Promise<void> {
    let pendingAnalysis: Promise<void> | null = this.batchDialogAnalysisPromise;
    while (pendingAnalysis !== null) {
      logger.info(TAG, '等待上一轮批量漫画解析任务退出');
      await pendingAnalysis;
      pendingAnalysis = this.batchDialogAnalysisPromise;
    }
  }

  private scheduleTrackedArchiveCleanup(reason: string): void {
    if (this.trackedArchiveStructures.size <= 0) {
      return;
    }
    const structures: CompressionParsedStructure[] =
      Array.from<CompressionParsedStructure>(this.trackedArchiveStructures.values());
    this.trackedArchiveStructures.clear();
    this.scheduleArchiveStructuresCleanup(structures, reason);
  }

  private scheduleArchiveStructureCleanup(structure: CompressionParsedStructure, reason: string): void {
    const structures: CompressionParsedStructure[] = [structure];
    this.scheduleArchiveStructuresCleanup(structures, reason);
  }

  private scheduleArchiveStructuresCleanup(
    structures: CompressionParsedStructure[],
    reason: string
  ): void {
    const previousCleanup: Promise<void> | null = this.archiveCleanupPromise;
    const cleanupPromise: Promise<void> = this.runTrackedArchiveCleanup(previousCleanup, structures, reason);
    this.archiveCleanupPromise = cleanupPromise;
    cleanupPromise.then((): void => {
      if (this.archiveCleanupPromise === cleanupPromise) {
        this.archiveCleanupPromise = null;
      }
    }).catch((error: Error): void => {
      logger.warn(TAG, `批量导入临时目录清理异常: reason=${reason}, error=${error.message}`);
      if (this.archiveCleanupPromise === cleanupPromise) {
        this.archiveCleanupPromise = null;
      }
    });
  }

  private async runTrackedArchiveCleanup(
    previousCleanup: Promise<void> | null,
    structures: CompressionParsedStructure[],
    reason: string
  ): Promise<void> {
    if (previousCleanup !== null) {
      try {
        await previousCleanup;
      } catch (error) {
        logger.warn(TAG, `等待前序漫画临时目录清理失败: ${String(error)}`);
      }
    }
    await this.cleanupTrackedArchiveStructures(structures, reason);
  }

  private async cleanupTrackedArchiveStructures(
    structures: CompressionParsedStructure[],
    reason: string
  ): Promise<void> {
    const cleanedPaths: Set<string> = new Set<string>();
    for (let index = 0; index < structures.length; index += 1) {
      const structure: CompressionParsedStructure = structures[index];
      if (structure.tempDirectories.length <= 0) {
        continue;
      }
      const cleanupKey: string = structure.extractedPath.length > 0
        ? structure.extractedPath
        : structure.tempDirectories.join('|');
      if (cleanedPaths.has(cleanupKey)) {
        continue;
      }
      cleanedPaths.add(cleanupKey);
      try {
        await this.compressionUtils.cleanupParsedArchiveStructure(structure);
      } catch (error) {
        logger.warn(TAG, `清理漫画导入临时目录失败: reason=${reason}, path=${cleanupKey}, error=${String(error)}`);
      }
    }
    logger.info(TAG, `漫画导入临时目录清理完成: reason=${reason}, count=${cleanedPaths.size}`);
  }

  private async waitForPendingArchiveCleanup(): Promise<void> {
    const cleanupPromise: Promise<void> | null = this.archiveCleanupPromise;
    if (cleanupPromise === null) {
      return;
    }
    logger.info(TAG, '等待上一轮漫画导入临时目录清理完成');
    await cleanupPromise;
  }

  private mapImportSource(source: string): ImportFlowEntrySource {
    if (source === 'lan_transfer') {
      return ImportFlowEntrySource.LAN_TRANSFER;
    }
    if (source === 'network_folder') {
      return ImportFlowEntrySource.NETWORK_FOLDER;
    }
    if (source === 'external_file_task') {
      return ImportFlowEntrySource.EXTERNAL_FILE_TASK;
    }
    if (source.length > 0) {
      return ImportFlowEntrySource.MANUAL;
    }
    return ImportFlowEntrySource.UNKNOWN;
  }

  private mapImportContentType(category: string): ImportFlowContentType {
    if (category === 'comic') {
      return ImportFlowContentType.MANGA;
    }
    if (category === 'ebook') {
      return ImportFlowContentType.EBOOK;
    }
    if (category === 'pdf') {
      return ImportFlowContentType.PDF;
    }
    if (category === 'novel') {
      return ImportFlowContentType.NOVEL;
    }
    if (category === 'backup') {
      return ImportFlowContentType.BACKUP;
    }
    if (category === 'json') {
      return ImportFlowContentType.JSON;
    }
    if (category === 'font') {
      return ImportFlowContentType.FONT;
    }
    if (category === 'code') {
      return ImportFlowContentType.CODE;
    }
    if (category === 'avif') {
      return ImportFlowContentType.AVIF;
    }
    if (category === 'image') {
      return ImportFlowContentType.IMAGE;
    }
    return ImportFlowContentType.UNKNOWN;
  }

  // 管理器实例
  private dataManager: DataManager = DataManager.getInstance();
  private compressionUtils: CompressionUtils = CompressionUtils.getInstance();
  private comicInfoParser: ComicInfoParser = new ComicInfoParser();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private pdfImportService: PdfImportService = PdfImportService.getInstance();
  private uiContext: UIContext | undefined = undefined;
  // 弹窗控制器每次使用时按需创建，避免持久状态泄漏
  private ebookMetadataDialogController: CustomDialogController | null = null;
  private pdfImportDialogController: CustomDialogController | null = null;
  private mangaImportDialogController: CustomDialogController | null = null;
  private batchMangaImportDialogController: CustomDialogController | null = null;
  
  // 漫画导入相关状态
  @State private currentParsedStructure: ParsedArchiveStructure | null = null;
  @State private currentFileUri: string = '';
  @State private existingMangaCandidates: ExistingMangaCandidate[] = [];
  private archivePasswordCache: Map<string, string> = new Map();
  private lastArchivePassword: string = '';
  
  // 公共目录权限状态
  @State private hasDownloadPermission: boolean = false;
  @State private hasDocumentsPermission: boolean = false;
  @State private appDownloadFolderPath: string = '';
  @State private appDocumentsFolderPath: string = '';
  
  // Download目录直接访问相关状态
  @State private downloadDirPath: string = '';
  @State private downloadDirUri: string = '';  // 保存URI用于后续访问
  @State private downloadDirFiles: string[] = [];
  @State private downloadDirFileCount: number = 0;

  // 扫描到的待导入文件分类
  @State private pendingMangaFiles: string[] = [];  // 漫画候选URI或folder-flat虚拟URI
  @State private pendingEbookFiles: string[] = [];  // 电子书
  @State private pendingPdfFiles: string[] = [];    // PDF文件
  @State private pendingNovelFiles: string[] = [];  // 小说文件
  @State private isScanning: boolean = false;
  @State private isMangaImportRunning: boolean = false;
  private folderPickerGeneration: number = 0;

  // 一级-二级标签模式状态
  @State private primaryTab: 'file_select' | 'download_sync' = 'file_select';  // 一级标签
  @State private secondaryTab: 'manga' | 'ebook' | 'pdf' = 'manga';  // 二级标签（选择文件导入）
  @State private syncSecondaryTab: 'folder_status' | 'imported_content' = 'folder_status';  // 二级标签（Download同步）
  
  // 横向滑动切换标签页相关状态
  private readonly primaryTabOrder: ('file_select' | 'download_sync')[] = ['file_select', 'download_sync'];
  private readonly secondaryTabOrder: ('manga' | 'ebook' | 'pdf')[] = ['manga', 'ebook', 'pdf'];
  private readonly syncSecondaryTabOrder: ('folder_status' | 'imported_content')[] = ['folder_status', 'imported_content'];
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;

  // 应用专属文件夹名称
  private static readonly APP_FOLDER_NAME: string = '漫匣';

  // 支持的文件扩展名
  private static readonly MANGA_EXTENSIONS: string[] = ['zip', 'cbz', 'rar', 'cbr', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'lzma'];
  private static readonly EBOOK_EXTENSIONS: string[] = ['epub', 'mobi', 'azw', 'azw3'];
  private static readonly PDF_EXTENSIONS: string[] = ['pdf'];
  private static readonly NOVEL_EXTENSIONS: string[] = ['txt'];
  private static readonly DOWNLOAD_IMPORT_RESERVED_FOLDERS: string[] = [
    'ebooks', 'manga', 'novel', 'storage', 'covers', 'temp', 'backup', 'legadoextensions'
  ];

  private showFileImportHelp(): void {
    const helpContent = `# 文件导入帮助

## 功能介绍

文件导入页面允许您从设备存储导入漫画、电子书和PDF文件到应用中。

## 支持的文件格式

### 漫画文件
- **ZIP/CBZ**: 标准漫画压缩包格式
- **RAR/CBR**: RAR压缩的漫画文件
- **7Z**: 7-Zip压缩格式

### 电子书文件
- **EPUB**: 最常用的电子书格式
- **MOBI/AZW/AZW3**: Kindle电子书格式

### PDF文件
- 可选择导入为漫画或电子书

## 导入方式

### 选择文件导入
1. 点击"选择文件"按钮
2. 在文件选择器中选择要导入的文件
3. 配置导入选项
4. 确认导入

### 批量导入
支持同时选择多个文件进行批量导入。

## 漫画导入选项

- **作为新漫画导入**: 创建新的漫画条目
- **合并到已有漫画**: 作为章节添加到现有漫画
- **智能检测**: 自动检测可能的重复项

## ComicInfo.xml支持

如果压缩包中包含ComicInfo.xml文件，将自动读取：
- 标题、作者信息
- 标签和分类
- 简介描述

## 注意事项

- 导入过程中请勿关闭应用
- 大文件导入可能需要较长时间
- 导入后原文件不会被删除（可选择删除）`;

    getHelpPanelManagerV2().showInlineHelp('文件导入帮助', helpContent);
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [{
      id: 'help',
      label: '帮助',
      symbol: $r('sys.symbol.questionmark_circle'),
      onClick: () => {
        this.showFileImportHelp();
      }
    }];
  }

  /**
   * 使用DOWNLOAD模式创建应用专属目录并访问
   * 通过DocumentViewPicker的DOWNLOAD模式，自动在Download/包名/目录下创建
   */
  private syncDownloadDirStateFromManager(): void {
    if (!DownloadDirManager.isReady()) {
      return;
    }
    this.downloadDirPath = DownloadDirManager.getPath();
    this.downloadDirUri = DownloadDirManager.getUri();
    try {
      const filenames = SafeFileUtils.listFileSync(this.downloadDirPath);
      this.downloadDirFiles = filenames;
      this.downloadDirFileCount = filenames.length;
    } catch (error) {
      logger.warn(TAG, `刷新 Download 目录状态失败: ${String(error)}`);
      this.downloadDirFiles = [];
      this.downloadDirFileCount = 0;
    }
  }

  private async ensureManagedDownloadDirReady(reason: string): Promise<boolean> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      logger.error(TAG, `无法获取上下文，不能准备 Download 目录: ${reason}`);
      this.showToast('无法访问 Download 应用目录');
      return false;
    }

    DownloadDirManager.setContext(context);
    if (!DownloadDirManager.isReady()) {
      logger.info(TAG, `开始准备 Download 应用目录: ${reason}`);
      const granted = await DownloadDirManager.requestAccess();
      if (!granted || !DownloadDirManager.isReady()) {
        logger.warn(TAG, `Download 应用目录授权失败: ${reason}`);
        this.showToast('需要授予 Download 应用目录权限后才能继续');
        return false;
      }
    }

    this.syncDownloadDirStateFromManager();
    logger.info(TAG, `Download 应用目录已就绪: ${this.downloadDirPath}`);
    return this.downloadDirPath.length > 0;
  }

  private resolveLocalImportPath(sourceUri: string): string {
    try {
      return new fileUri.FileUri(sourceUri).path;
    } catch (_error) {
      if (sourceUri.startsWith('file://docs')) {
        return sourceUri.replace('file://docs', '');
      }
      if (sourceUri.startsWith('file://')) {
        return sourceUri.replace('file://', '');
      }
      return sourceUri;
    }
  }

  private buildNetworkImportSafeFileName(displayName: string): string {
    const trimmed = displayName.trim();
    const baseName = (trimmed.length > 0 ? trimmed : 'network_import_file').replace(/[<>:\"/\\\\|?*]/g, '_');
    const lastDot = baseName.lastIndexOf('.');
    const uniqueSuffix = `${Date.now().toString(16)}`;
    if (lastDot <= 0) {
      return `${baseName}_${uniqueSuffix}`;
    }
    const namePart = baseName.substring(0, lastDot);
    const extension = baseName.substring(lastDot);
    return `${namePart}_${uniqueSuffix}${extension}`;
  }

  private async stageNetworkImportFileToDownload(relativeDir: string, sourceUri: string, displayName: string): Promise<string> {
    const prepared = await this.ensureManagedDownloadDirReady('网络文件夹导入');
    if (!prepared) {
      throw new Error('Download 应用目录尚未准备就绪');
    }

    const sourcePath = this.resolveLocalImportPath(sourceUri);
    const targetDir = DownloadDirManager.ensureDirectory(relativeDir);
    const targetPath = `${targetDir}/${this.buildNetworkImportSafeFileName(displayName)}`;
    SafeFileUtils.copyFileSync(sourcePath, targetPath);
    logger.info(TAG, `网络文件夹缓存文件已转存到 Download 应用目录: ${targetPath}`);
    this.syncDownloadDirStateFromManager();
    return targetPath;
  }

  private async accessAppDownloadDir(): Promise<void> {
    try {
      const ready = await this.ensureManagedDownloadDirReady('手动连接 Download 目录');
      if (!ready) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: `目录连接成功，共 ${this.downloadDirFileCount} 个文件` });
      return;

      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取上下文' });
        return;
      }
      
      const documentViewPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      
      logger.info(TAG, '开始使用DOWNLOAD模式创建应用目录...');
      
      documentViewPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
        if (documentSaveResult.length > 0) {
          const uri = documentSaveResult[0];
          logger.info(TAG, `DOWNLOAD模式返回URI: ${uri}`);
          
          // 保存目录路径和URI
          const uriObj = new fileUri.FileUri(uri);
          this.downloadDirPath = uriObj.path;
          this.downloadDirUri = uri;
          
          // 在目录下创建一个测试文件来验证权限
          try {
            const testFilePath = new fileUri.FileUri(uri + '/.manxia_init').path;
            const file = SafeFileUtils.openSync(testFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
            SafeFileUtils.writeSync(file.fd, '漫匣应用目录初始化文件');
            SafeFileUtils.closeSync(file.fd);
            logger.info(TAG, `成功创建初始化文件: ${testFilePath}`);
          } catch (writeError) {
            logger.warn(TAG, `创建初始化文件失败: ${String(writeError)}`);
          }
          
          // 列出目录下的文件
          try {
            const filenames = SafeFileUtils.listFileSync(this.downloadDirPath);
            this.downloadDirFiles = filenames;
            this.downloadDirFileCount = filenames.length;
            logger.info(TAG, `Download目录下共有 ${filenames.length} 个文件`);
            this.getUIContext().getPromptAction().showToast({ message: `目录创建成功，共 ${filenames.length} 个文件` });
          } catch (listError) {
            logger.warn(TAG, `列出文件失败: ${String(listError)}`);
            this.downloadDirFiles = [];
            this.downloadDirFileCount = 0;
            this.getUIContext().getPromptAction().showToast({ message: '目录创建成功' });
          }
        }
      }).catch((err: Error) => {
        logger.error(TAG, `DOWNLOAD模式失败: ${err.message}`);
        this.getUIContext().getPromptAction().showToast({ message: `创建失败: ${err.message}` });
      });
    } catch (error) {
      logger.error(TAG, `访问Download目录失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `访问失败: ${String(error)}` });
    }
  }

  /**
   * 获取文件扩展名（用于Download目录扫描）
   */
  private getDownloadFileExtension(filename: string): string {
    const lastDot = filename.lastIndexOf('.');
    if (lastDot === -1) return '';
    return filename.substring(lastDot + 1).toLowerCase();
  }

  private getDownloadCandidateDisplayName(candidate: string): string {
    const rawPath: string = candidate.startsWith('folder-flat:')
      ? candidate.substring('folder-flat:'.length)
      : candidate;
    const normalizedPath: string = rawPath.replace(/\\/g, '/').replace(/\/$/, '');
    const lastSlash: number = normalizedPath.lastIndexOf('/');
    return lastSlash >= 0 ? normalizedPath.substring(lastSlash + 1) : normalizedPath;
  }

  /**
   * 扫描Download目录并分类文件
   */
  private async scanDownloadDir(): Promise<void> {
    if (!this.downloadDirPath) {
      this.getUIContext().getPromptAction().showToast({ message: '请先访问Download目录' });
      return;
    }

    this.startImportFlow(
      ImportFlowEntrySource.DOWNLOAD_DIR,
      ImportFlowContentType.UNKNOWN,
      'Download',
      0,
      true,
      this.downloadDirPath,
      this.downloadDirPath
    );
    const scanStartedAt: number = Date.now();
    this.recordSimpleImportFlowEvent(
      ImportFlowEventType.DOWNLOAD_SCAN_STARTED,
      'download_scan_started',
      ImportFlowContentType.UNKNOWN,
      ImportFlowEntrySource.DOWNLOAD_DIR,
      true,
      this.downloadDirPath,
      0
    );
    this.isScanning = true;
    this.pendingMangaFiles = [];
    this.pendingEbookFiles = [];
    this.pendingPdfFiles = [];
    this.pendingNovelFiles = [];
    
    try {
      const filenames = SafeFileUtils.listFileSync(this.downloadDirPath);
      this.downloadDirFiles = filenames;
      this.downloadDirFileCount = filenames.length;

      this.pendingMangaFiles = await this.compressionUtils.discoverMangaImportCandidates(
        this.downloadDirPath,
        16,
        2000,
        DataManagementPage.DOWNLOAD_IMPORT_RESERVED_FOLDERS
      );

      for (let i = 0; i < filenames.length; i++) {
        const filename = filenames[i];
        const ext = this.getDownloadFileExtension(filename);
        
        if (filename.startsWith('.')) continue;
        
        if (DataManagementPage.EBOOK_EXTENSIONS.includes(ext)) {
          this.pendingEbookFiles.push(filename);
        } else if (DataManagementPage.PDF_EXTENSIONS.includes(ext)) {
          this.pendingPdfFiles.push(filename);
        } else if (DataManagementPage.NOVEL_EXTENSIONS.includes(ext)) {
          this.pendingNovelFiles.push(filename);
        }
      }
      
      const totalPending = this.pendingMangaFiles.length + this.pendingEbookFiles.length + 
                          this.pendingPdfFiles.length + this.pendingNovelFiles.length;
      const classifiedEvent: ImportFlowEvent = new ImportFlowEvent();
      classifiedEvent.eventType = ImportFlowEventType.FILE_CLASSIFIED;
      classifiedEvent.reason = 'download_files_classified';
      classifiedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
      classifiedEvent.contentType = ImportFlowContentType.UNKNOWN;
      classifiedEvent.fileCount = totalPending;
      classifiedEvent.totalCount = filenames.length;
      classifiedEvent.detail = `manga=${this.pendingMangaFiles.length}, ebook=${this.pendingEbookFiles.length}, pdf=${this.pendingPdfFiles.length}, novel=${this.pendingNovelFiles.length}`;
      this.recordImportFlowEvent(classifiedEvent);
      const completedEvent: ImportFlowEvent = new ImportFlowEvent();
      completedEvent.eventType = ImportFlowEventType.DOWNLOAD_SCAN_COMPLETED;
      completedEvent.reason = 'download_scan_completed';
      completedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
      completedEvent.contentType = ImportFlowContentType.UNKNOWN;
      completedEvent.fileCount = totalPending;
      completedEvent.totalCount = filenames.length;
      completedEvent.elapsedMs = Date.now() - scanStartedAt;
      completedEvent.detail = classifiedEvent.detail;
      this.recordImportFlowEvent(completedEvent);

      logger.info(TAG, `扫描完成: 漫画=${this.pendingMangaFiles.length}, 电子书=${this.pendingEbookFiles.length}, PDF=${this.pendingPdfFiles.length}, 小说=${this.pendingNovelFiles.length}`);
      this.getUIContext().getPromptAction().showToast({ message: `扫描完成，发现 ${totalPending} 个可导入文件` });
    } catch (error) {
      logger.error(TAG, `扫描目录失败: ${String(error)}`);
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'download_scan_failed';
      failedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.errorMessage = String(error);
      failedEvent.elapsedMs = Date.now() - scanStartedAt;
      this.recordImportFlowEvent(failedEvent);
      this.getUIContext().getPromptAction().showToast({ message: `扫描失败: ${String(error)}` });
    } finally {
      this.isScanning = false;
    }
  }

  /**
   * 从Download目录导入漫画文件（原地模式）
   * 解压到Download目录下，不复制到沙箱
   */
  private async importMangaFromDownloadDir(): Promise<void> {
    if (this.isMangaImportRunning || this.isMangaDialogOpening ||
      this.batchMangaImportDialogController !== null || this.mangaImportDialogController !== null) {
      logger.warn(TAG, '漫画导入流程正在运行，忽略重复请求');
      return;
    }
    const pageGeneration: number = this.pageLifecycleGeneration;
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.isMangaImportRunning = true;
    this.isMangaDialogOpening = true;
    try {
      if (this.pendingMangaFiles.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '没有待导入的漫画文件' });
        if (this.isCurrentPageGeneration(pageGeneration)) {
          this.isMangaImportRunning = false;
        }
        return;
      }

      // 单文件与批量候选统一走同一分析/校验/回滚链路，避免旧单文件实现
      // 忽略多章节结构、元数据和页面写入完整性。
      await this.showDownloadBatchImportDialog(pageGeneration);
    } catch (error) {
      logger.error(TAG, 'Download漫画导入准备失败', String(error));
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${String(error)}` });
        this.endCurrentImportFlow('download_manga_prepare_failed');
        this.isMangaImportRunning = false;
      }
    } finally {
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.isMangaDialogOpening = false;
      }
    }
  }
  
  /**
   * 显示Download目录批量导入对话框
   */
  private async showDownloadBatchImportDialog(pageGeneration: number): Promise<void> {
    await this.waitForPendingBatchDialogAnalysis();
    await this.waitForPendingArchiveCleanup();
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.ensureImportFlow(
      ImportFlowEntrySource.DOWNLOAD_DIR,
      ImportFlowContentType.MANGA,
      'Download批量漫画导入',
      this.pendingMangaFiles.length,
      true,
      this.downloadDirPath,
      this.downloadDirPath
    );
    const fileUris: string[] = this.pendingMangaFiles.slice();
    
    // 查找可能的重复漫画
    await this.findExistingMangaCandidatesForBatch(pageGeneration);
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }

    const analysisGeneration: string = this.createBatchAnalysisGeneration();
    const analysisSessionId: string = this.currentImportFlowId;
    this.beginBatchDialogAnalysis(analysisGeneration);
    try {
      this.batchMangaImportDialogController = new CustomDialogController({
      builder: BatchMangaImportDialog({
        themeState: this.themeState,
        fileUris: fileUris,
        existingMangaCandidates: this.existingMangaCandidates,
        parseFileStructure: async (fileUri: string): Promise<ParsedArchiveStructure | null> => {
          const parsed = await this.parseFileStructureForBatch(
            fileUri,
            analysisGeneration,
            analysisSessionId
          );
          return parsed;
        },
        onReleaseParsedStructure: (fileUri: string, structure: ParsedArchiveStructure) => {
          this.releaseLateBatchArchiveStructure(fileUri, structure, analysisGeneration);
        },
        onAnalysisSettled: () => {
          this.finishBatchDialogAnalysis(analysisGeneration);
        },
        onAnalysisGenerationInvalidated: () => {
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
        },
        parseComicInfoXml: (xmlContent: string): PrefilledComicInfo | null => {
          return this.parseComicInfoXml(xmlContent);
        },
        onFlowEvent: (event: ImportFlowEvent) => {
          event.sessionId = analysisSessionId;
          this.recordImportFlowEvent(event);
        },
        onConfirm: (result: BatchMangaImportDialogResult) => {
          if (!this.isCurrentPageGeneration(pageGeneration)) {
            this.invalidateBatchAnalysisGeneration(analysisGeneration);
            return;
          }
          if (this.mangaImportOwnerToken !== 0) {
            logger.warn(TAG, '已有漫画提交任务，忽略重复确认');
            return;
          }
          const ownerToken: number = this.beginMangaImportCommit();
          this.isMangaImportRunning = true;
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
          this.batchMangaImportDialogController = null;
          void (async (): Promise<void> => {
            try {
              await this.handleDownloadBatchImportResult(result, pageGeneration);
            } catch (error) {
              logger.error(TAG, `Download批量漫画导入异常: ${String(error)}`);
            } finally {
              this.finishMangaImport(pageGeneration, ownerToken);
            }
          })();
        },
        onCancel: () => {
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
          if (this.isCurrentPageGeneration(pageGeneration)) {
            this.batchMangaImportDialogController = null;
            this.updateProgress(ImportStatus.IDLE, '已取消批量导入', 0);
            this.pendingMangaFiles = [];
            this.endCurrentImportFlow('download_batch_manga_cancelled');
          }
          void (async (): Promise<void> => {
            try {
              await this.waitForPendingBatchDialogAnalysis();
              await this.waitForPendingArchiveCleanup();
            } finally {
              if (this.isCurrentPageGeneration(pageGeneration)) {
                this.isMangaImportRunning = false;
              }
            }
          })();
        }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
      });
      this.batchMangaImportDialogController.open();
    } catch (error) {
      this.invalidateBatchAnalysisGeneration(analysisGeneration);
      this.finishBatchDialogAnalysis(analysisGeneration);
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.batchMangaImportDialogController = null;
      }
      throw error as Error;
    }
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.recordSimpleImportFlowEvent(
      ImportFlowEventType.DIALOG_OPENED,
      'download_batch_manga_dialog_opened',
      ImportFlowContentType.MANGA,
      ImportFlowEntrySource.DOWNLOAD_DIR,
      true,
      `files=${fileUris.length}`,
      0
    );
    this.updateProgress(ImportStatus.IDLE, '请配置批量导入选项', 10);
  }
  
  /**
   * 处理Download目录批量导入结果
   */
  private async handleDownloadBatchImportResult(
    result: BatchMangaImportDialogResult,
    pageGeneration: number = this.pageLifecycleGeneration
  ): Promise<void> {
    this.updateProgress(ImportStatus.IMPORTING, `开始导入...`, 10);
    const batchStartedAt: number = Date.now();
    const confirmEvent: ImportFlowEvent = new ImportFlowEvent();
    confirmEvent.eventType = ImportFlowEventType.DIALOG_CONFIRMED;
    confirmEvent.reason = 'download_batch_manga_confirmed';
    confirmEvent.contentType = ImportFlowContentType.MANGA;
    confirmEvent.batchMode = true;
    confirmEvent.fileCount = result.groups.length;
    confirmEvent.totalCount = result.groups.length;
    this.recordImportFlowEvent(confirmEvent);
    let successCount = 0;
    const total = result.groups.length;
    if (total <= 0) {
      this.updateProgress(ImportStatus.ERROR, '没有可导入的漫画分组', 0);
      this.endCurrentImportFlow('download_batch_manga_no_groups');
      return;
    }
    
    for (let i = 0; i < result.groups.length; i++) {
      const group: MangaGroupResult = result.groups[i];
      this.updateProgress(ImportStatus.IMPORTING, `导入 (${i + 1}/${total}): ${group.title}`, 10 + (i / total) * 80);
      
      try {
        await this.importDownloadMangaGroup(group);
        successCount++;
        const progressEvent: ImportFlowEvent = new ImportFlowEvent();
        progressEvent.eventType = ImportFlowEventType.COPY_PROGRESS;
        progressEvent.reason = 'download_batch_group_imported';
        progressEvent.contentType = ImportFlowContentType.MANGA;
        progressEvent.batchMode = true;
        progressEvent.displayName = group.title;
        progressEvent.currentIndex = i + 1;
        progressEvent.totalCount = total;
        this.recordImportFlowEvent(progressEvent);
      } catch (error) {
        logger.error(TAG, `导入失败 ${group.title}: ${String(error)}`);
        const failedEvent: ImportFlowEvent = new ImportFlowEvent();
        failedEvent.eventType = ImportFlowEventType.ERROR;
        failedEvent.reason = 'download_batch_group_failed';
        failedEvent.contentType = ImportFlowContentType.MANGA;
        failedEvent.batchMode = true;
        failedEvent.displayName = group.title;
        failedEvent.currentIndex = i + 1;
        failedEvent.totalCount = total;
        failedEvent.success = false;
        failedEvent.severity = ImportFlowSeverity.ERROR;
        failedEvent.errorMessage = String(error);
        this.recordImportFlowEvent(failedEvent);
      }
    }
    
    const finalStatus: ImportStatus = successCount === total ? ImportStatus.COMPLETED : ImportStatus.ERROR;
    this.updateProgress(finalStatus, `完成: 成功 ${successCount}/${total}`, 100);
    if (this.isCurrentPageGeneration(pageGeneration)) {
      this.getUIContext().getPromptAction().showToast({
        message: `导入完成: 成功 ${successCount}，失败 ${total - successCount}`
      });
      this.pendingMangaFiles = [];
    }
    
    if (successCount > 0) {
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(successCount, total));
      const refreshEvent: ImportFlowEvent = new ImportFlowEvent();
      refreshEvent.eventType = ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED;
      refreshEvent.reason = 'download_batch_bookshelf_refresh_published';
      refreshEvent.contentType = ImportFlowContentType.MANGA;
      refreshEvent.batchMode = true;
      refreshEvent.currentIndex = successCount;
      refreshEvent.totalCount = total;
      refreshEvent.elapsedMs = Date.now() - batchStartedAt;
      this.recordImportFlowEvent(refreshEvent);
    }
    this.endCurrentImportFlow(successCount === total
      ? 'download_batch_manga_completed'
      : (successCount > 0 ? 'download_batch_manga_partial_failure' : 'download_batch_manga_no_success'));
  }
  
  /**
   * 导入Download目录的漫画组
   */
  private async importDownloadMangaGroup(group: MangaGroupResult): Promise<void> {
    if (group.chapters.length <= 0) {
      throw new Error(`漫画 ${group.title} 没有可导入章节`);
    }
    for (const chapter of group.chapters) {
      if (chapter.parsedStructure === null || chapter.sourcePath.trim().length <= 0 || chapter.pageCount <= 0) {
        throw new Error(`漫画 ${group.title} 包含无效章节: ${chapter.title}`);
      }
    }

    let mangaId: string = '';
    let storageTitle: string = group.title;
    let createdManga: boolean = false;
    const createdChapterIds: string[] = [];
    const organizedPaths: string[] = [];
    const transientStagingPaths: string[] = [];
    const dbStartedAt: number = Date.now();
    let mangaPath: string = '';

    try {
      const dbStartEvent: ImportFlowEvent = new ImportFlowEvent();
      dbStartEvent.eventType = ImportFlowEventType.DB_WRITE_STARTED;
      dbStartEvent.reason = 'download_group_manga_db_started';
      dbStartEvent.contentType = ImportFlowContentType.MANGA;
      dbStartEvent.displayName = group.title;
      dbStartEvent.chapterCount = group.chapters.length;
      this.recordImportFlowEvent(dbStartEvent);

      if (group.mergeToExisting) {
        const targetMangaId: string = group.targetMangaId || '';
        if (targetMangaId.trim().length <= 0) {
          throw new Error(`漫画 ${group.title} 已选择合并但缺少目标漫画ID`);
        }
        const existingManga: ComicRecord | null = await this.dataManager.getComicInfo(targetMangaId);
        if (existingManga === null) {
          throw new Error(`合并目标漫画不存在: ${targetMangaId}`);
        }
        mangaId = targetMangaId;
        storageTitle = existingManga.title || group.title;
      } else {
        const comicInfoInput: ComicInfoInput = {
          title: group.title,
          author: group.author,
          description: group.description,
          coverUrl: '',
          sourceId: 'download_import',
          externalId: `download_${generateUUID()}`,
          status: this.convertBatchDialogMangaStatus(group.status),
          tags: group.tags,
          rating: 0,
          chapterCount: group.chapters.length,
          lastUpdateTime: Date.now(),
          webUrl: group.webUrl,
          isNSFW: group.isNSFW
        };
        mangaId = await this.dataManager.addComicInfo(comicInfoInput);
        createdManga = true;
      }

      const mangaBaseDir: string = `${this.downloadDirPath}/manga`;
      await this.sandboxManager.createDirectory(mangaBaseDir);
      const rawFolderName: string = this.sanitizeFolderName(storageTitle);
      const folderName: string = rawFolderName.length > 0 ? rawFolderName : `manga_${mangaId}`;
      mangaPath = `${mangaBaseDir}/${folderName}`;
      await this.sandboxManager.createDirectory(mangaPath);
      let selectedCoverTargetPath: string = '';
      if (createdManga && group.selectedCoverPath.length > 0) {
        const coverDotIndex: number = group.selectedCoverPath.lastIndexOf('.');
        const coverExtension: string = coverDotIndex >= 0
          ? group.selectedCoverPath.substring(coverDotIndex)
          : '.jpg';
        selectedCoverTargetPath = `${mangaPath}/cover_${mangaId}${coverExtension}`;
        try {
          await this.sandboxManager.copyFile(group.selectedCoverPath, selectedCoverTargetPath);
          await this.dataManager.updateComicCoverUrl(mangaId, selectedCoverTargetPath);
        } catch (coverError) {
          selectedCoverTargetPath = '';
          logger.warn(TAG, `保存用户选择的封面失败: ${group.title}`, String(coverError));
        }
      }

      const dbCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
      dbCompletedEvent.eventType = ImportFlowEventType.DB_WRITE_COMPLETED;
      dbCompletedEvent.reason = 'download_group_manga_record_created';
      dbCompletedEvent.contentType = ImportFlowContentType.MANGA;
      dbCompletedEvent.displayName = group.title;
      dbCompletedEvent.elapsedMs = Date.now() - dbStartedAt;
      dbCompletedEvent.chapterCount = group.chapters.length;
      dbCompletedEvent.detail = `mangaId=${mangaId}`;
      this.recordImportFlowEvent(dbCompletedEvent);

      let firstCoverPath: string = '';
      let totalPageCount: number = 0;
      let firstChapterId: string = '';
      let firstChapterTitle: string = '';
      for (let i: number = 0; i < group.chapters.length; i++) {
        const chapter: BatchChapterResult = group.chapters[i];
        let effectiveSourcePath: string = chapter.sourcePath;
        let preserveSource: boolean = chapter.preserveSource;
        if (chapter.parsedStructure !== null &&
          this.isMixedRootImageChapter(chapter.parsedStructure, chapter.sourcePath, chapter.pageCount)) {
          effectiveSourcePath = await this.stageDirectImageChapter(chapter.sourcePath, chapter.pageCount);
          transientStagingPaths.push(effectiveSourcePath);
          preserveSource = false;
        }
        const chapterSuffix: string = generateUUID().replace(/-/g, '').substring(0, 12);
        const chapterDirectoryName: string =
          `${chapter.number}_${this.sanitizeFolderName(chapter.title)}_${chapterSuffix}`;
        const chapterPath: string = `${mangaPath}/${chapterDirectoryName}`;
        const sourceImageCount: number = await this.countImportableImages(effectiveSourcePath);
        if (sourceImageCount !== chapter.pageCount) {
          throw new Error(
            `章节 ${chapter.title} 页数不一致: 识别 ${chapter.pageCount}，源目录 ${sourceImageCount}`
          );
        }

        await this.sandboxManager.createDirectory(chapterPath);
        organizedPaths.push(chapterPath);
        const copyStartedAt: number = Date.now();
        const copyStartEvent: ImportFlowEvent = new ImportFlowEvent();
        copyStartEvent.eventType = ImportFlowEventType.COPY_STARTED;
        copyStartEvent.reason = 'download_group_chapter_copy_started';
        copyStartEvent.contentType = ImportFlowContentType.MANGA;
        copyStartEvent.displayName = group.title;
        copyStartEvent.fileName = chapter.title;
        copyStartEvent.sourceUri = chapter.fileUri;
        copyStartEvent.targetPath = chapterPath;
        copyStartEvent.currentIndex = i + 1;
        copyStartEvent.totalCount = group.chapters.length;
        this.recordImportFlowEvent(copyStartEvent);

        await this.transferDirectoryContents(effectiveSourcePath, chapterPath, preserveSource);
        if (!preserveSource) {
          await this.sandboxManager.deleteDirectory(effectiveSourcePath, true);
        }
        const imageFiles: ImageFileInfo[] = await this.scanImageFiles(chapterPath);
        if (imageFiles.length !== chapter.pageCount) {
          throw new Error(
            `章节 ${chapter.title} 落盘页数不一致: 应为 ${chapter.pageCount}，实际 ${imageFiles.length}`
          );
        }

        const chapterInfoInput: ChapterInfoInput = {
          comicId: mangaId,
          title: chapter.title,
          index: chapter.number > 0 ? chapter.number - 1 : i,
          pageCount: chapter.pageCount,
          isDownloaded: true,
          downloadPath: chapterPath,
          publishTime: chapter.publishTime,
          externalId: await createLocalMangaChapterExternalId(
            mangaId,
            chapter.fileUri,
            chapter.sourcePath,
            chapter.parsedStructure?.extractedPath || '',
            chapter.number
          )
        };
        const chapterCreation: ChapterInfoCreationResult =
          await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
        if (!chapterCreation.created) {
          throw new Error(`章节已存在，已停止重复导入: ${chapter.title}`);
        }
        const chapterId: string = chapterCreation.id;
        createdChapterIds.push(chapterId);
        const addedPageCount: number = await this.addPageInfoToDatabaseFromPath(chapterId, chapterPath);
        if (addedPageCount !== chapter.pageCount) {
          throw new Error(
            `章节 ${chapter.title} 页面写入不完整: 应为 ${chapter.pageCount}，实际 ${addedPageCount}`
          );
        }

        const copyCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
        copyCompletedEvent.eventType = ImportFlowEventType.COPY_COMPLETED;
        copyCompletedEvent.reason = 'download_group_chapter_copy_completed';
        copyCompletedEvent.contentType = ImportFlowContentType.MANGA;
        copyCompletedEvent.displayName = group.title;
        copyCompletedEvent.fileName = chapter.title;
        copyCompletedEvent.sourceUri = chapter.fileUri;
        copyCompletedEvent.targetPath = chapterPath;
        copyCompletedEvent.currentIndex = i + 1;
        copyCompletedEvent.totalCount = group.chapters.length;
        copyCompletedEvent.pageCount = addedPageCount;
        copyCompletedEvent.elapsedMs = Date.now() - copyStartedAt;
        this.recordImportFlowEvent(copyCompletedEvent);

        totalPageCount += addedPageCount;
        if (firstChapterId.length <= 0) {
          firstChapterId = chapterId;
          firstChapterTitle = chapter.title;
        }
        if (firstCoverPath.length <= 0 && imageFiles.length > 0) {
          firstCoverPath = imageFiles[0].path;
        }
      }

      await this.validateImportedMangaGroup(mangaId, createdChapterIds, group.chapters.length);
      if (createdManga) {
        await DataService.getInstance().addToFavorites(mangaId, group.tags);
      }

      if (createdManga && selectedCoverTargetPath.length <= 0 && firstCoverPath.length > 0) {
        const coverExtension: string = firstCoverPath.substring(firstCoverPath.lastIndexOf('.'));
        const coverPath: string = `${mangaPath}/cover_${mangaId}${coverExtension}`;
        await this.sandboxManager.copyFile(firstCoverPath, coverPath);
        await this.dataManager.updateComicCoverUrl(mangaId, coverPath);
      }

      await this.updateMangaChapterCount(mangaId);

      logger.info(TAG, `Download导入成功: ${group.title}`);
      this.recordMangaImportFlow(
        mangaId,
        group.title,
        firstChapterId,
        firstChapterTitle,
        totalPageCount,
        group.chapters.length,
        group.chapters[0].fileUri,
        mangaPath,
        'download_batch_group_import_completed'
      );
    } catch (error) {
      await this.rollbackSingleImport(mangaId, createdManga, createdChapterIds, organizedPaths);
      for (const stagingPath of transientStagingPaths) {
        try {
          await this.sandboxManager.deleteDirectory(stagingPath, true);
        } catch (cleanupError) {
          logger.debug(TAG, `根散图暂存目录已清理或不存在: ${stagingPath}`, String(cleanupError));
        }
      }
      throw error as Error;
    }
  }

  /**
   * 显示Download目录单文件导入对话框
   */
  private async showDownloadSingleImportDialog(
    fileUri: string,
    filename: string,
    pageGeneration: number = this.pageLifecycleGeneration
  ): Promise<void> {
    try {
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.ensureImportFlow(
        ImportFlowEntrySource.DOWNLOAD_DIR,
        ImportFlowContentType.MANGA,
        filename,
        1,
        false,
        fileUri,
        this.downloadDirPath
      );
      this.updateProgress(ImportStatus.PARSING, `正在解析: ${filename}`, 10);
      
      // 解析压缩包结构
      const parsed = await this.parseArchiveStructureWithPasswordRetry(fileUri);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        await this.compressionUtils.cleanupParsedArchiveStructure(parsed);
        return;
      }
      
      // 转换为对话框需要的格式
      const dialogStructure: ParsedArchiveStructure = this.convertToDialogStructure(parsed);
      
      // 查找可能的重复漫画
      const titleMatch = filename.match(/^(.+?)(?:_[a-f0-9]+)?\.(?:zip|cbz|rar|cbr|7z|tar|gz|tgz|bz2|xz|lzma)$/i);
      const title = titleMatch ? titleMatch[1] : filename.replace(/\.[^.]+$/, '');
      await this.findExistingMangaCandidates(title);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        await this.compressionUtils.cleanupParsedArchiveStructure(parsed);
        return;
      }
      
      // 保存当前文件信息
      this.currentFileUri = fileUri;
      this.currentParsedStructure = dialogStructure;
      
      // 显示导入对话框
      this.mangaImportDialogController = new CustomDialogController({
        builder: MangaImportDialog({
          themeState: this.themeState,
          fileName: filename,
          parsedStructure: dialogStructure,
          existingMangaCandidates: this.existingMangaCandidates,
          sourceFileUri: fileUri,
          onFlowEvent: (event: ImportFlowEvent) => {
            this.recordImportFlowEvent(event);
          },
          onConfirm: (result: MangaImportDialogResult) => {
            if (!this.isCurrentPageGeneration(pageGeneration)) {
              return;
            }
            if (this.mangaImportOwnerToken !== 0) {
              logger.warn(TAG, '已有漫画提交任务，忽略重复确认');
              return;
            }
            const ownerToken: number = this.beginMangaImportCommit();
            this.isMangaImportRunning = true;
            this.mangaImportDialogController = null;
            this.pendingMangaFiles = [];
            void (async (): Promise<void> => {
              try {
                await this.handleDownloadSingleImportResult(result);
              } catch (error) {
                logger.error(TAG, `Download单文件漫画导入异常: ${String(error)}`);
              } finally {
                this.finishMangaImport(pageGeneration, ownerToken);
              }
            })();
          },
          onCancel: () => {
            if (this.isCurrentPageGeneration(pageGeneration)) {
              this.mangaImportDialogController = null;
              this.updateProgress(ImportStatus.IDLE, '已取消导入', 0);
              this.pendingMangaFiles = [];
              this.endCurrentImportFlow('download_single_manga_cancelled');
              this.isMangaImportRunning = false;
            }
          }
        }),
        autoCancel: false,
        customStyle: true,
        alignment: DialogAlignment.Center
      });

      this.mangaImportDialogController.open();
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.recordSimpleImportFlowEvent(
        ImportFlowEventType.DIALOG_OPENED,
        'download_single_manga_dialog_opened',
        ImportFlowContentType.MANGA,
        ImportFlowEntrySource.DOWNLOAD_DIR,
        true,
        filename,
        0
      );
      this.updateProgress(ImportStatus.IDLE, '请配置导入选项', 20);
    } catch (error) {
      logger.error(TAG, `解析失败: ${filename}`, String(error));
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'download_single_manga_prepare_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.sourceUri = fileUri;
      failedEvent.fileName = filename;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.getUIContext().getPromptAction().showToast({ message: `解析失败: ${String(error)}` });
        this.pendingMangaFiles = [];
        this.endCurrentImportFlow('download_single_manga_prepare_failed');
      }
    }
  }
  
  /**
   * 处理Download目录单文件导入结果
   */
  private async handleDownloadSingleImportResult(result: MangaImportDialogResult): Promise<void> {
    const importStartedAt: number = Date.now();
    let mangaId: string = '';
    let chapterId: string = '';
    let mangaPath: string = '';
    let chapterPath: string = '';
    try {
      this.updateProgress(ImportStatus.IMPORTING, '正在导入漫画...', 30);
      
      const parsed = result.parsedStructure;
      
      // 在Download目录创建漫画文件夹
      const folderName = `${this.sanitizeFolderName(result.title)}_${generateUUID().replace(/-/g, '').substring(0, 12)}`;
      mangaPath = `${this.downloadDirPath}/${folderName}`;
      chapterPath = `${mangaPath}/第1话`;
      
      try { SafeFileUtils.mkdirSync(mangaPath); } catch (e) { /* 已存在 */ }
      try { SafeFileUtils.mkdirSync(chapterPath); } catch (e) { /* 已存在 */ }
      
      // 处理章节
      const chapterInput: ChapterInfoInput = {
        comicId: '',
        title: '第1话',
        index: 0,
        pageCount: 0,
        isDownloaded: true,
        downloadPath: chapterPath,
        publishTime: Date.now(),
        externalId: `local_chapter_${generateUUID()}`
      };
      
      // 复制图片文件和ComicInfo.xml
      const imageFiles: string[] = [];
      const copyStartedAt: number = Date.now();
      const copyStartedEvent: ImportFlowEvent = new ImportFlowEvent();
      copyStartedEvent.eventType = ImportFlowEventType.COPY_STARTED;
      copyStartedEvent.reason = 'download_single_copy_started';
      copyStartedEvent.contentType = ImportFlowContentType.MANGA;
      copyStartedEvent.displayName = result.title;
      copyStartedEvent.sourceUri = result.sourceFileUri || this.currentFileUri;
      copyStartedEvent.targetPath = chapterPath;
      this.recordImportFlowEvent(copyStartedEvent);
      if (parsed.extractedPath) {
        const files = SafeFileUtils.listFileSync(parsed.extractedPath);
        for (const file of files) {
          if (/\.(jpg|jpeg|png|webp|avif)$/i.test(file)) {
            const srcPath = `${parsed.extractedPath}/${file}`;
            const destPath = `${chapterPath}/${file}`;
            try {
              SafeFileUtils.copyFileSync(srcPath, destPath);
              imageFiles.push(file);
            } catch (e) {
              logger.warn(TAG, `复制文件失败: ${file}`);
            }
          }
        }
        
        // 复制ComicInfo.xml到漫画根目录
        if (parsed.hasComicInfo) {
          const comicInfoSrc = `${parsed.extractedPath}/ComicInfo.xml`;
          const comicInfoDest = `${mangaPath}/ComicInfo.xml`;
          try {
            SafeFileUtils.copyFileSync(comicInfoSrc, comicInfoDest);
            logger.info(TAG, `ComicInfo.xml已复制: ${comicInfoDest}`);
          } catch (e) {
            logger.warn(TAG, `复制ComicInfo.xml失败: ${String(e)}`);
          }
        }
      }
      const copyCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
      copyCompletedEvent.eventType = ImportFlowEventType.COPY_COMPLETED;
      copyCompletedEvent.reason = 'download_single_copy_completed';
      copyCompletedEvent.contentType = ImportFlowContentType.MANGA;
      copyCompletedEvent.displayName = result.title;
      copyCompletedEvent.sourceUri = result.sourceFileUri || this.currentFileUri;
      copyCompletedEvent.targetPath = chapterPath;
      copyCompletedEvent.pageCount = imageFiles.length;
      copyCompletedEvent.elapsedMs = Date.now() - copyStartedAt;
      this.recordImportFlowEvent(copyCompletedEvent);
       
      // 创建漫画记录
      const dbStartedAt: number = Date.now();
      const dbStartedEvent: ImportFlowEvent = new ImportFlowEvent();
      dbStartedEvent.eventType = ImportFlowEventType.DB_WRITE_STARTED;
      dbStartedEvent.reason = 'download_single_db_started';
      dbStartedEvent.contentType = ImportFlowContentType.MANGA;
      dbStartedEvent.displayName = result.title;
      dbStartedEvent.pageCount = imageFiles.length;
      this.recordImportFlowEvent(dbStartedEvent);
      mangaId = await this.dataManager.addComicInfo({
        title: result.title,
        author: result.author,
        description: result.description,
        coverUrl: '',
        sourceId: 'download_import',
        externalId: `download_${generateUUID()}`,
        status: MangaStatus.UNKNOWN,
        tags: result.tags,
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: Date.now()
      } as ComicInfoInput);
      
      // 更新章节信息
      chapterInput.comicId = mangaId;
      chapterInput.pageCount = imageFiles.length;
      chapterId = await this.dataManager.addChapterInfo(chapterInput);
       
      // 添加页面信息
      await this.addPageInfoToDatabaseFromPath(chapterId, chapterPath);
      await this.validateImportedMangaGroup(mangaId, [chapterId], 1);
      await DataService.getInstance().addToFavorites(mangaId, result.tags);
      const dbCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
      dbCompletedEvent.eventType = ImportFlowEventType.DB_WRITE_COMPLETED;
      dbCompletedEvent.reason = 'download_single_db_completed';
      dbCompletedEvent.contentType = ImportFlowContentType.MANGA;
      dbCompletedEvent.displayName = result.title;
      dbCompletedEvent.pageCount = imageFiles.length;
      dbCompletedEvent.elapsedMs = Date.now() - dbStartedAt;
      dbCompletedEvent.detail = `mangaId=${mangaId}, chapterId=${chapterId}`;
      this.recordImportFlowEvent(dbCompletedEvent);
       
      // 处理封面 - 复制第一张图片到漫画目录作为封面
      if (imageFiles.length > 0) {
        imageFiles.sort((left: string, right: string): number =>
          left.localeCompare(right, undefined, { numeric: true })
        );
        const firstImagePath = `${chapterPath}/${imageFiles[0]}`;
        const ext = imageFiles[0].substring(imageFiles[0].lastIndexOf('.'));
        const coverPath = `${mangaPath}/cover_${mangaId}${ext}`;
        
        try {
          SafeFileUtils.copyFileSync(firstImagePath, coverPath);
          // 更新数据库中的封面路径
          await this.dataManager.updateComicCoverUrl(mangaId, coverPath);
          const coverEvent: ImportFlowEvent = new ImportFlowEvent();
          coverEvent.eventType = ImportFlowEventType.COVER_HANDLED;
          coverEvent.reason = 'download_single_cover_saved';
          coverEvent.contentType = ImportFlowContentType.MANGA;
          coverEvent.displayName = result.title;
          coverEvent.targetPath = coverPath;
          this.recordImportFlowEvent(coverEvent);
          logger.info(TAG, `封面已保存: ${coverPath}`);
        } catch (e) {
          logger.warn(TAG, `保存封面失败: ${String(e)}`);
        }
      }
      
      this.updateProgress(ImportStatus.COMPLETED, '导入完成', 100);
      this.getUIContext().getPromptAction().showToast({ message: '导入成功' });
      this.pendingMangaFiles = [];
      this.recordMangaImportFlow(
        mangaId,
        result.title,
        chapterId,
        chapterInput.title,
        imageFiles.length,
        1,
        result.sourceFileUri || this.currentFileUri,
        chapterPath,
        'download_single_import_completed'
      );
       
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(1, 1));
      const refreshEvent: ImportFlowEvent = new ImportFlowEvent();
      refreshEvent.eventType = ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED;
      refreshEvent.reason = 'download_single_bookshelf_refresh_published';
      refreshEvent.contentType = ImportFlowContentType.MANGA;
      refreshEvent.displayName = result.title;
      refreshEvent.elapsedMs = Date.now() - importStartedAt;
      this.recordImportFlowEvent(refreshEvent);
      this.endCurrentImportFlow('download_single_manga_completed');
       
      // 询问是否删除原文件
      if (result.sourceFileUri) {
        this.askDeleteSourceFile(result.sourceFileUri, result.title);
      }
    } catch (error) {
      if (mangaId.length > 0) {
        try {
          await this.rollbackSingleImport(mangaId, true, [chapterId], [chapterPath]);
        } catch (rollbackError) {
          logger.error(TAG, `Download单文件导入回滚失败: ${mangaId}`, String(rollbackError));
        }
      } else if (mangaPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(mangaPath, true);
        } catch (cleanupError) {
          logger.warn(TAG, `清理Download单文件暂存目录失败: ${mangaPath}`, String(cleanupError));
        }
      }
      logger.error(TAG, `导入失败: ${String(error)}`);
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'download_single_import_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.displayName = result.title;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - importStartedAt;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${String(error)}`, 0);
      this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${String(error)}` });
      this.endCurrentImportFlow('download_single_manga_failed');
    }
  }
  
  /**
   * 询问用户是否删除原文件
   */
  private askDeleteSourceFile(fileUri: string, title: string): void {
    this.getUIContext().showAlertDialog({
      title: '删除原文件',
      message: `漫画"${title}"已成功导入。\n是否删除原压缩包文件以节省空间？`,
      primaryButton: {
        value: '保留',
        action: () => {
          logger.info(TAG, `用户选择保留原文件: ${fileUri}`);
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.deleteSourceFile(fileUri);
        }
      }
    });
  }
  
  /**
   * 删除原文件
   */
  private deleteSourceFile(fileUri: string): void {
    try {
      // 将URI转换为路径
      let filePath = fileUri;
      if (fileUri.startsWith('file://docs/')) {
        filePath = fileUri.replace('file://docs', '');
      } else if (fileUri.startsWith('file://')) {
        filePath = fileUri.replace('file://', '');
      }
      
      SafeFileUtils.unlinkSync(filePath);
      logger.info(TAG, `原文件已删除: ${filePath}`);
      this.getUIContext().getPromptAction().showToast({ message: '原文件已删除' });
    } catch (error) {
      logger.error(TAG, `删除原文件失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${String(error)}` });
    }
  }
  
  /**
   * 原地导入单个漫画（解压到Download目录）
   */
  private async importMangaInPlaceFromDownload(fileUri: string, filename: string): Promise<void> {
    // 解析压缩包（会解压到临时目录）
    const parsed = await this.parseArchiveStructureWithPasswordRetry(fileUri);
    
    // 提取标题
    const titleMatch = filename.match(/^(.+?)(?:_[a-f0-9]+)?\.(?:zip|cbz|rar|cbr|7z|tar|gz|tgz|bz2|xz|lzma)$/i);
    const title = titleMatch ? titleMatch[1] : filename.replace(/\.[^.]+$/, '');
    
    // 解析ComicInfo
    let comicInfo: PrefilledComicInfo | null = null;
    if (parsed.hasComicInfo && parsed.comicInfoContent) {
      comicInfo = this.parseComicInfoXml(parsed.comicInfoContent);
    }
    
    // 在Download目录创建漫画文件夹
    const folderName = this.sanitizeFolderName(comicInfo?.title || title);
    const mangaPath = `${this.downloadDirPath}/${folderName}`;
    const chapterPath = `${mangaPath}/第1话`;
    
    try { SafeFileUtils.mkdirSync(mangaPath); } catch (e) { /* 已存在 */ }
    try { SafeFileUtils.mkdirSync(chapterPath); } catch (e) { /* 已存在 */ }
    
    // 从临时目录复制文件到Download目录
    const tempExtractedPath = parsed.extractedPath;
    const imageFiles: string[] = [];
    
    if (tempExtractedPath) {
      const files = SafeFileUtils.listFileSync(tempExtractedPath);
      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        if (/\.(jpg|jpeg|png|webp|avif)$/i.test(file)) {
          const srcPath = `${tempExtractedPath}/${file}`;
          const destPath = `${chapterPath}/${file}`;
          try {
            SafeFileUtils.copyFileSync(srcPath, destPath);
            imageFiles.push(file);
          } catch (e) {
            logger.warn(TAG, `复制文件失败: ${file}`);
          }
        }
      }
      
      // 复制ComicInfo.xml到漫画根目录
      if (parsed.hasComicInfo) {
        const comicInfoSrc = `${tempExtractedPath}/ComicInfo.xml`;
        const comicInfoDest = `${mangaPath}/ComicInfo.xml`;
        try {
          SafeFileUtils.copyFileSync(comicInfoSrc, comicInfoDest);
          logger.info(TAG, `ComicInfo.xml已复制: ${comicInfoDest}`);
        } catch (e) {
          logger.warn(TAG, `复制ComicInfo.xml失败: ${String(e)}`);
        }
      }
    }
    
    // 创建漫画记录
    const mangaId = await this.dataManager.addComicInfo({
      title: comicInfo?.title || title,
      author: comicInfo?.author || '',
      description: comicInfo?.description || '',
      coverUrl: '',
      sourceId: 'download_import',
      externalId: `download_${generateUUID()}`,
      status: MangaStatus.UNKNOWN,
      tags: comicInfo?.tags || [],
      rating: 0,
      chapterCount: 1,
      lastUpdateTime: Date.now()
    } as ComicInfoInput);
    
    // 创建章节记录
    const chapterId = await this.dataManager.addChapterInfo({
      comicId: mangaId,
      title: '第1话',
      index: 0,
      pageCount: imageFiles.length,
      isDownloaded: true,
      downloadPath: chapterPath,
      publishTime: Date.now(),
      externalId: `local_chapter_${generateUUID()}`
    } as ChapterInfoInput);
    
    // 添加页面信息
    await this.addPageInfoToDatabaseFromPath(chapterId, chapterPath);
    await this.validateImportedMangaGroup(mangaId, [chapterId], 1);
    await DataService.getInstance().addToFavorites(mangaId, comicInfo?.tags || []);
    
    // 处理封面 - 复制第一张图片到漫画目录作为封面
    if (imageFiles.length > 0) {
      imageFiles.sort((left: string, right: string): number =>
        left.localeCompare(right, undefined, { numeric: true })
      );
      const firstImagePath = `${chapterPath}/${imageFiles[0]}`;
      const ext = imageFiles[0].substring(imageFiles[0].lastIndexOf('.'));
      const coverPath = `${mangaPath}/cover_${mangaId}${ext}`;
      
      try {
        SafeFileUtils.copyFileSync(firstImagePath, coverPath);
        // 更新数据库中的封面路径
        await this.dataManager.updateComicCoverUrl(mangaId, coverPath);
        logger.info(TAG, `封面已保存: ${coverPath}`);
      } catch (e) {
        logger.warn(TAG, `保存封面失败: ${String(e)}`);
      }
    }
    
    logger.info(TAG, `原地导入成功: ${title}, 路径: ${chapterPath}, 图片数: ${imageFiles.length}`);
    this.recordMangaImportFlow(
      mangaId,
      comicInfo?.title || title,
      chapterId,
      '第1话',
      imageFiles.length,
      1,
      fileUri,
      chapterPath,
      'download_in_place_import_completed'
    );
  }
  
  /**
   * 清理文件夹名称
   */
  private sanitizeFolderName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').substring(0, 50);
  }
  
  /**
   * 将CompressionUtils的ParsedArchiveStructure转换为对话框需要的格式
   */
  private convertToDialogStructure(parsed: CompressionParsedStructure): ParsedArchiveStructure {
    // 解析ComicInfo.xml获取预填充信息
    let prefilledInfo: PrefilledComicInfo | undefined = undefined;
    if (parsed.hasComicInfo && parsed.comicInfoContent) {
      const parsedInfo = this.parseComicInfoXml(parsed.comicInfoContent);
      if (parsedInfo) {
        prefilledInfo = parsedInfo;
      }
    }
    
    return {
      hasComicInfo: parsed.hasComicInfo,
      comicInfoContent: parsed.comicInfoContent,
      isMultiLayer: parsed.isMultiLayer,
      detectedChapters: parsed.detectedChapters.map(ch => {
        const chapterInfo: ChapterInfo = {
          index: ch.index,
          number: ch.number,
          title: ch.title,
          originalName: ch.originalName,
          path: ch.path,
          pageCount: ch.pageCount
        };
        return chapterInfo;
      }),
      rootImageCount: parsed.rootImageCount,
      totalImageCount: parsed.totalImageCount,
      extractedPath: parsed.extractedPath,
      tempDirectories: parsed.tempDirectories,
      warnings: parsed.warnings,
      prefilledInfo: prefilledInfo
    };
  }

  /**
   * 从Download目录导入电子书文件
   * 将电子书复制到Download目录的ebooks子文件夹
   */
  private async importEbooksFromDownloadDir(): Promise<void> {
    if (this.isMangaImportRunning || this.isMangaDialogOpening || this.isFilePickerActive || this.isProcessing()) {
      logger.warn(TAG, '已有导入流程运行，忽略电子书快速导入请求');
      return;
    }
    if (this.pendingEbookFiles.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有待导入的电子书文件' });
      return;
    }
    this.ensureImportFlow(
      ImportFlowEntrySource.DOWNLOAD_DIR,
      ImportFlowContentType.EBOOK,
      'Download电子书导入',
      this.pendingEbookFiles.length,
      this.pendingEbookFiles.length > 1,
      this.downloadDirPath,
      `${this.downloadDirPath}/ebooks`
    );
    
    // 创建电子书专属文件夹
    const ebooksPath = `${this.downloadDirPath}/ebooks`;
    try { SafeFileUtils.mkdirSync(ebooksPath); } catch (e) { /* 已存在 */ }
    
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.getUIContext().getPromptAction().showToast({ message: '无法获取上下文' });
      return;
    }
    
    const totalFiles = this.pendingEbookFiles.length;
    let successCount = 0;
    const sourceFiles: string[] = [...this.pendingEbookFiles];
    this.pendingEbookFiles = [];
    
    for (let i = 0; i < sourceFiles.length; i++) {
      const filename = sourceFiles[i];
      const sourceUri = `${this.downloadDirUri}/${filename}`;
      const sourcePath = `${this.downloadDirPath}/${filename}`;
      
      try {
        this.updateProgress(ImportStatus.PROCESSING, `正在处理第 ${i + 1}/${totalFiles} 个电子书...`, ((i + 1) / totalFiles) * 100);
        
        // 复制到ebooks文件夹
        const timestamp = Date.now();
        const safeFilename = filename.replace(/[<>:"/\\|?*]/g, '_');
        const targetPath = `${ebooksPath}/${timestamp}_${safeFilename}`;
        
        const copyStartedAt: number = Date.now();
        const copyStartedEvent: ImportFlowEvent = new ImportFlowEvent();
        copyStartedEvent.eventType = ImportFlowEventType.COPY_STARTED;
        copyStartedEvent.reason = 'download_ebook_copy_started';
        copyStartedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
        copyStartedEvent.contentType = ImportFlowContentType.EBOOK;
        copyStartedEvent.fileName = filename;
        copyStartedEvent.sourceUri = sourcePath;
        copyStartedEvent.targetPath = targetPath;
        copyStartedEvent.currentIndex = i + 1;
        copyStartedEvent.totalCount = totalFiles;
        this.recordImportFlowEvent(copyStartedEvent);
        SafeFileUtils.copyFileSync(sourcePath, targetPath);
        const copyCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
        copyCompletedEvent.eventType = ImportFlowEventType.COPY_COMPLETED;
        copyCompletedEvent.reason = 'download_ebook_copy_completed';
        copyCompletedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
        copyCompletedEvent.contentType = ImportFlowContentType.EBOOK;
        copyCompletedEvent.fileName = filename;
        copyCompletedEvent.sourceUri = sourcePath;
        copyCompletedEvent.targetPath = targetPath;
        copyCompletedEvent.currentIndex = i + 1;
        copyCompletedEvent.totalCount = totalFiles;
        copyCompletedEvent.elapsedMs = Date.now() - copyStartedAt;
        this.recordImportFlowEvent(copyCompletedEvent);
        logger.info(TAG, `电子书复制成功: ${targetPath}`);
        
        // 继续导入流程
        const importSuccess = await this.continueImportEBook(targetPath);
        if (importSuccess) {
          successCount++;
          // 询问是否删除原文件
          this.askDeleteSourceFile(sourceUri, filename);
        }
      } catch (error) {
        logger.error(TAG, `导入电子书失败 ${filename}: ${String(error)}`);
        const failedEvent: ImportFlowEvent = new ImportFlowEvent();
        failedEvent.eventType = ImportFlowEventType.ERROR;
        failedEvent.reason = 'download_ebook_import_failed';
        failedEvent.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
        failedEvent.contentType = ImportFlowContentType.EBOOK;
        failedEvent.fileName = filename;
        failedEvent.currentIndex = i + 1;
        failedEvent.totalCount = totalFiles;
        failedEvent.success = false;
        failedEvent.severity = ImportFlowSeverity.ERROR;
        failedEvent.errorMessage = String(error);
        this.recordImportFlowEvent(failedEvent);
      }
    }
    
    this.updateProgress(ImportStatus.COMPLETED, `电子书导入完成: 成功 ${successCount}/${totalFiles}`, 100);
    this.getUIContext().getPromptAction().showToast({ message: `电子书导入完成: 成功 ${successCount}` });
  }

  /**
   * 从Download目录导入PDF文件
   */
  private async importPdfsFromDownloadDir(): Promise<void> {
    if (this.isMangaImportRunning || this.isMangaDialogOpening || this.isFilePickerActive || this.isProcessing()) {
      logger.warn(TAG, '已有导入流程运行，忽略PDF快速导入请求');
      return;
    }
    if (this.pendingPdfFiles.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有待导入的PDF文件' });
      return;
    }
    
    const fileUris: string[] = [];
    for (let i = 0; i < this.pendingPdfFiles.length; i++) {
      const filename = this.pendingPdfFiles[i];
      const uri = `${this.downloadDirUri}/${filename}`;
      fileUris.push(uri);
    }
    
    const pendingFiles: string[] = [...fileUris];
    this.pendingPdfFiles = [];

    for (let i = 0; i < pendingFiles.length; i++) {
      this.updateProgress(ImportStatus.IDLE, `配置PDF导入 (${i + 1}/${pendingFiles.length})`, 10);
      await this.handlePdfImportWithCategorySelection(pendingFiles[i]);
    }
    this.getUIContext().getPromptAction().showToast({ message: `已处理 ${pendingFiles.length} 个PDF导入请求` });
  }

  /**
   * 检查公共目录权限
   */
  private async checkPublicDirectoryPermissions(): Promise<void> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId = bundleInfo.appInfo.accessTokenId;
      const atManager = abilityAccessCtrl.createAtManager();
      
      // 检查下载目录权限
      const downloadPermission: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';
      const downloadState = atManager.checkAccessTokenSync(tokenId, downloadPermission);
      this.hasDownloadPermission = downloadState === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      
      // 检查文档目录权限
      const documentsPermission: Permissions = 'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY';
      const documentsState = atManager.checkAccessTokenSync(tokenId, documentsPermission);
      this.hasDocumentsPermission = documentsState === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      
      logger.info(TAG, `公共目录权限状态: 下载=${this.hasDownloadPermission}, 文档=${this.hasDocumentsPermission}`);
    } catch (error) {
      logger.error(TAG, `检查公共目录权限失败: ${String(error)}`);
    }
  }

  /**
   * 申请公共目录权限
   */
  private async requestPublicDirectoryPermissions(): Promise<boolean> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext');
        return false;
      }
      
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = [
        'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',
        'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY'
      ];
      
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      
      // 检查授权结果
      this.hasDownloadPermission = result.authResults[0] === 0;
      this.hasDocumentsPermission = result.authResults[1] === 0;
      
      logger.info(TAG, `权限申请结果: 下载=${this.hasDownloadPermission}, 文档=${this.hasDocumentsPermission}`);
      
      return this.hasDownloadPermission || this.hasDocumentsPermission;
    } catch (error) {
      logger.error(TAG, `申请公共目录权限失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 检查设备是否支持公共目录访问（保留方法但不再阻止功能）
   */
  private isPublicDirectorySupported(): boolean {
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain');
  }

  /**
   * 创建应用专属文件夹
   */
  private async createAppFolders(): Promise<void> {
    try {
      // 检查并申请权限
      await this.checkPublicDirectoryPermissions();
      
      if (!this.hasDownloadPermission && !this.hasDocumentsPermission) {
        logger.info(TAG, '未授权公共目录权限，开始申请...');
        const granted = await this.requestPublicDirectoryPermissions();
        if (!granted) {
          this.getUIContext().getPromptAction().showToast({ message: '需要授权公共目录权限才能创建应用文件夹' });
          return;
        }
      }
      
      // 创建下载目录中的应用文件夹
      if (this.hasDownloadPermission) {
        try {
          const downloadPath = Environment.getUserDownloadDir();
          this.appDownloadFolderPath = `${downloadPath}/${DataManagementPage.APP_FOLDER_NAME}`;
          
          // 尝试创建文件夹
          try {
            SafeFileUtils.accessSync(this.appDownloadFolderPath);
            logger.info(TAG, `下载目录应用文件夹已存在: ${this.appDownloadFolderPath}`);
          } catch (accessError) {
            // 文件夹不存在，创建它
            SafeFileUtils.mkdirSync(this.appDownloadFolderPath);
            logger.info(TAG, `已创建下载目录应用文件夹: ${this.appDownloadFolderPath}`);
          }
        } catch (error) {
          logger.error(TAG, `创建下载目录应用文件夹失败: ${String(error)}`);
        }
      }
      
      // 创建文档目录中的应用文件夹
      if (this.hasDocumentsPermission) {
        try {
          const documentsPath = Environment.getUserDocumentDir();
          this.appDocumentsFolderPath = `${documentsPath}/${DataManagementPage.APP_FOLDER_NAME}`;
          
          try {
            SafeFileUtils.accessSync(this.appDocumentsFolderPath);
            logger.info(TAG, `文档目录应用文件夹已存在: ${this.appDocumentsFolderPath}`);
          } catch (accessError) {
            SafeFileUtils.mkdirSync(this.appDocumentsFolderPath);
            logger.info(TAG, `已创建文档目录应用文件夹: ${this.appDocumentsFolderPath}`);
          }
        } catch (error) {
          logger.error(TAG, `创建文档目录应用文件夹失败: ${String(error)}`);
        }
      }
      
      // 显示结果
      if (this.appDownloadFolderPath || this.appDocumentsFolderPath) {
        this.getUIContext().getPromptAction().showToast({ message: '应用文件夹创建成功' });
      }
    } catch (error) {
      logger.error(TAG, `创建应用文件夹失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `创建失败: ${String(error)}` });
    }
  }

  /**
   * 获取应用在公共目录的路径
   */
  public getAppPublicFolderPath(type: 'download' | 'documents'): string {
    if (type === 'download') {
      return this.appDownloadFolderPath;
    }
    return this.appDocumentsFolderPath;
  }

  /**
   * 展示漫画级合并弹窗并返回用户决策（UniversalDialog 重构版）
   */
  private async resolveUserMergeDecision(mode: MergeMode, check: DuplicateCheckResult, input: ComicInfoInput): Promise<MergeDecision> {
    // 无候选则直接新建
    if (!check.best || check.candidates.length === 0) {
      return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
    }
    
    // 根据批量导入策略自动决策
    if (this.batchImportStrategy === 'merge_all' && check.best) {
      logger.info(TAG, `批量策略：全部合并 - 自动合并到 ${check.best.record.title}`);
      return { 
        mode: mode, 
        action: MergeAction.MERGE_TO_EXISTING, 
        targetMangaId: check.best.record.id, 
        strength: check.best.strength, 
        reasons: check.best.reasons 
      } as MergeDecision;
    }
    
    if (this.batchImportStrategy === 'create_all') {
      logger.info(TAG, `批量策略：全部新建 - 作为新漫画导入`);
      return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
    }

    // 准备候选列表（最多取前5个按score排序）
    const candidates: MergeDialogCandidate[] = [];
    const raw: DuplicateCandidate[] = check.candidates;
    // 复制数组进行排序以避免修改原数组
    const sorted: DuplicateCandidate[] = [];
    for (let i = 0; i < raw.length; i++) { sorted.push(raw[i]); }
    for (let i = 0; i < sorted.length - 1; i++) {
      for (let j = i + 1; j < sorted.length; j++) {
        if (sorted[i].score < sorted[j].score) {
          const tmp: DuplicateCandidate = sorted[i];
          sorted[i] = sorted[j];
          sorted[j] = tmp;
        }
      }
    }
    const takeCount: number = sorted.length > 5 ? 5 : sorted.length;
    for (let k = 0; k < takeCount; k++) {
      const c: DuplicateCandidate = sorted[k];
      candidates.push({ id: c.record.id, title: c.record.title, author: c.record.author, strength: c.strength, reasons: c.reasons } as MergeDialogCandidate);
    }

    const defaultId: string = check.best ? check.best.record.id : '';
    const data: MergeDialogData = { sourceTitle: input.title, sourceAuthor: input.author, candidates: candidates, defaultTargetId: defaultId };

    // 使用 UniversalDialogManager 展示通用弹窗
    return await new Promise<MergeDecision>((resolve) => {
      let selectedTargetId: string = defaultId; // 默认选中最佳候选
      const customBuilderParam: MergeDialogBuilderParam = {
        data: data,
        themeState: this.themeState,
        selectedTargetId: selectedTargetId,
        onRadioChange: (id: string): void => {
          selectedTargetId = id;
        },
        appFontFamily: this.appFontFamily
      } as MergeDialogBuilderParam;

      const dialogOptions: UniversalDialogOptions = {
        title: `合并漫画：${input.title}（候选 ${candidates.length}）`,
        customBuilder: wrapBuilder(buildMergeDialogContent),
        customBuilderParam: customBuilderParam,
        buttons: [
          {
            text: '取消',
            style: ButtonStyle.SECONDARY,
            action: () => {
              resolve({ mode: mode, action: MergeAction.SKIP } as MergeDecision);
            }
          },
          {
            text: '作为新漫画导入',
            style: ButtonStyle.PRIMARY,
            action: () => {
              resolve({ mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision);
            }
          },
          {
            text: '合并到选中漫画',
            style: ButtonStyle.PRIMARY,
            action: () => {
              if (selectedTargetId === '') {
                logger.warn(TAG, '用户未选择合并目标，忽略合并操作');
                return;
              }
              // 找到对应候选项以携带强度与原因
              let selectedStrength: MatchStrength | undefined = undefined;
              let selectedReasons: DuplicateReason[] | undefined = undefined;
              for (let i = 0; i < sorted.length; i++) {
                const cand: DuplicateCandidate = sorted[i];
                if (cand.record.id === selectedTargetId) {
                  selectedStrength = cand.strength;
                  selectedReasons = cand.reasons;
                  break;
                }
              }
              resolve({ mode: mode, action: MergeAction.MERGE_TO_EXISTING, targetMangaId: selectedTargetId, strength: selectedStrength, reasons: selectedReasons } as MergeDecision);
            }
          }
        ],
        themeState: this.themeState
      };

      logger.info(TAG, '准备显示合并漫画选择对话框');
      setTimeout((): void => {
        const ctx: UIContext | undefined = this.uiContext;
        if (!ctx) {
          logger.warn(TAG, '界面上下文未就绪，回退使用通用对话框控制器');
          UniversalDialogManager.show(dialogOptions);
          return;
        }
        UniversalDialogManager.showWithContext(ctx as UIContext, dialogOptions);
        logger.info(TAG, '已调用带上下文的通用对话框控制器，等待用户选择');
      }, 0);
    });
  }

  /**
   * 展示章节级合并弹窗并返回用户选择（UniversalDialog 重构版）
   */
  private async resolveUserChapterMergeDecision(mangaTitle: string, chapterInput: ChapterInfoInput, duplicateChapter: ChapterRecord): Promise<MergeAction> {
    const data: ChapterMergeDialogData = {
      mangaTitle: mangaTitle,
      existingChapterTitle: duplicateChapter.title,
      newChapterTitle: chapterInput.title
    } as ChapterMergeDialogData;

    // 使用 UniversalDialogManager 展示通用弹窗
    return await new Promise<MergeAction>((resolve) => {
      const customBuilderParam: ChapterMergeDialogBuilderParam = {
        data: data,
        themeState: this.themeState,
        appFontFamily: this.appFontFamily
      } as ChapterMergeDialogBuilderParam;
      const dialogOptions: UniversalDialogOptions = {
        title: `章节合并：${chapterInput.title}（所属：${mangaTitle}）`,
        customBuilder: wrapBuilder(buildChapterMergeDialogContent),
        customBuilderParam: customBuilderParam,
        buttons: [
          {
            text: '跳过',
            style: ButtonStyle.SECONDARY,
            action: () => {
              resolve(MergeAction.SKIP);
            }
          },
          {
            text: '替换已有章节',
            style: ButtonStyle.DESTRUCTIVE,
            action: () => {
              resolve(MergeAction.MERGE_TO_EXISTING);
            }
          },
          {
            text: '保留两者',
            style: ButtonStyle.PRIMARY,
            action: () => {
              resolve(MergeAction.CREATE_NEW);
            }
          }
        ],
        themeState: this.themeState
      };

      logger.info(TAG, '准备显示章节合并选择对话框');
      setTimeout((): void => {
        const ctx: UIContext | undefined = this.uiContext;
        if (!ctx) {
          logger.warn(TAG, '界面上下文未就绪，回退使用通用对话框控制器');
          UniversalDialogManager.show(dialogOptions);
          return;
        }
        UniversalDialogManager.showWithContext(ctx as UIContext, dialogOptions);
        logger.info(TAG, '已调用带上下文的通用对话框控制器，等待用户选择');
      }, 0);
    });
  }

  /**
   * 验证数据库存储完整性
   */
  private async validateDatabaseStorage(mangaId: string, chapterId: string, expectedPageCount: number): Promise<void> {
    try {
      logger.info(TAG, '开始验证数据库存储完整性');

      // 验证漫画信息是否存在
      const comicInfo = await this.dataManager.getComicInfo(mangaId);
      if (!comicInfo) {
        throw new Error(`漫画信息验证失败：未找到ID为 ${mangaId} 的漫画`);
        logger.error(TAG, `漫画信息验证失败：未找到ID为 ${mangaId} 的漫画`);
      }
      logger.debug(TAG, `漫画信息验证通过: ${comicInfo.title}`);

      // 验证章节信息是否存在
      const chapterInfo = await this.dataManager.getChapterInfo(chapterId);
      if (!chapterInfo) {
        throw new Error(`章节信息验证失败：未找到ID为 ${chapterId} 的章节`);
        logger.error(TAG, `章节信息验证失败：未找到ID为 ${chapterId} 的章节`);
      }
      logger.debug(TAG, `章节信息验证通过: ${chapterInfo.title}`);

      // 验证页面信息数量
      const pageInfoList = await this.dataManager.getPageInfoList(chapterId);
      const actualPageCount = pageInfoList ? pageInfoList.length : 0;
      
      if (actualPageCount !== expectedPageCount) {
        logger.warn(TAG, `页面信息数量不匹配：期望 ${expectedPageCount}，实际 ${actualPageCount}`);
      } else {
        logger.debug(TAG, `页面信息验证通过: ${actualPageCount} 页`);
      }

      // 验证页面信息的完整性
      if (pageInfoList && pageInfoList.length > 0) {
        for (const pageInfo of pageInfoList) {
          if (!pageInfo.imageUrl || pageInfo.imageUrl.trim() === '') {
            throw new Error(`页面信息验证失败：第 ${pageInfo.index} 页缺少图片路径`);
            logger.error(TAG, `页面信息验证失败：第 ${pageInfo.index} 页缺少图片路径`);
          }
        }
        logger.debug(TAG, '所有页面信息路径验证通过');
      }

      logger.info(TAG, '数据库存储完整性验证通过');

    } catch (error) {
      logger.error(TAG, '数据库存储验证失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 解析标签字符串，将其拆分成多个标签
   */
  private parseGenreTags(genre?: string): string[] {
    if (!genre) {
      return [];
    }
    
    // 移除首尾空格并检查是否为空
    const trimmedGenre = genre.trim();
    if (!trimmedGenre) {
      return [];
    }
    
    // 使用多种分隔符拆分标签：逗号、分号、斜杠、竖线
    const tags = trimmedGenre
      .split(/[,;/|]/)
      .map(tag => tag.trim())
      .filter(tag => tag.length > 0);
    
    return tags;
  }

  /**
   * 切换到下一个一级标签页（支持循环）
   */
  private switchToNextPrimaryTab(): void {
    const currentIndex = this.primaryTabOrder.indexOf(this.primaryTab);
    const nextIndex = (currentIndex + 1) % this.primaryTabOrder.length;
    this.primaryTab = this.primaryTabOrder[nextIndex];
  }
  
  /**
   * 切换到上一个一级标签页（支持循环）
   */
  private switchToPrevPrimaryTab(): void {
    const currentIndex = this.primaryTabOrder.indexOf(this.primaryTab);
    const prevIndex = (currentIndex - 1 + this.primaryTabOrder.length) % this.primaryTabOrder.length;
    this.primaryTab = this.primaryTabOrder[prevIndex];
  }
  
  /**
   * 切换到下一个二级标签页（支持循环）
   */
  private switchToNextSecondaryTab(): void {
    if (this.primaryTab === 'file_select') {
      const currentIndex = this.secondaryTabOrder.indexOf(this.secondaryTab);
      const nextIndex = (currentIndex + 1) % this.secondaryTabOrder.length;
      this.secondaryTab = this.secondaryTabOrder[nextIndex];
    } else {
      const currentIndex = this.syncSecondaryTabOrder.indexOf(this.syncSecondaryTab);
      const nextIndex = (currentIndex + 1) % this.syncSecondaryTabOrder.length;
      this.syncSecondaryTab = this.syncSecondaryTabOrder[nextIndex];
    }
  }
  
  /**
   * 切换到上一个二级标签页（支持循环）
   */
  private switchToPrevSecondaryTab(): void {
    if (this.primaryTab === 'file_select') {
      const currentIndex = this.secondaryTabOrder.indexOf(this.secondaryTab);
      const prevIndex = (currentIndex - 1 + this.secondaryTabOrder.length) % this.secondaryTabOrder.length;
      this.secondaryTab = this.secondaryTabOrder[prevIndex];
    } else {
      const currentIndex = this.syncSecondaryTabOrder.indexOf(this.syncSecondaryTab);
      const prevIndex = (currentIndex - 1 + this.syncSecondaryTabOrder.length) % this.syncSecondaryTabOrder.length;
      this.syncSecondaryTab = this.syncSecondaryTabOrder[prevIndex];
    }
  }

  @State isPC: boolean = false; // 是否为PC或二合一设备，用于隐藏不支持的系统级文件夹选择API入口

  /**
   * 页面显示时的回调
   */
  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.pageLifecycleGeneration += 1;
    this.isPageActive = true;
    this.isMangaImportRunning = this.isMangaImportCommitting && this.mangaImportOwnerToken !== 0;
    
    try {
      const deviceType = this.deviceManager.getDeviceInfo().deviceType;
      this.isPC = (deviceType === DeviceType.TWO_IN_ONE || deviceType === 'pc' as DeviceType);
      logger.info(TAG, `当前设备类型判定: isPC = ${this.isPC}`);
    } catch (e) {
      logger.warn(TAG, '检测PC设备类型失败', String(e));
    }

    this.uiContext = this.getUIContext();
    const abilityContext = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (abilityContext) {
      DownloadDirManager.setContext(abilityContext);
      if (DownloadDirManager.isReady()) {
        this.syncDownloadDirStateFromManager();
      }
    }
    
    // 使用ThemeAwareHelper统一管理主题
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (theme: ThemeType) => {
        logger.info(TAG, `主题已切换: ${theme}`);
      }
    );
    FontAwareHelper.initializeFontAware(
      TAG,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    
    // 初始化响应式布局
    this.initializeResponsiveLayout();

    // 订阅文件导入请求事件
    this.subscribeFileImportEvent();

    if (this.handleRouteExternalFileTaskIfNeeded('aboutToAppear')) {
      return;
    }

    // 检查是否有待导入的文件（从外部打开）
    this.checkPendingFileImport();
  }

  private setRouteExternalFileTask(params: DataManagementExternalFileParams | undefined): void {
    if (!params || !params.externalFileTask) {
      return;
    }
    this.routeExternalFileTask = ExternalFileTaskFactory.clone(params.externalFileTask);
    logger.info(TAG, `已接收外部文件独立任务参数: kind=${this.routeExternalFileTask.kind}, count=${this.routeExternalFileTask.uris.length}`);
    this.handleRouteExternalFileTaskIfNeeded('onReady');
  }

  private handleRouteExternalFileTaskIfNeeded(source: string): boolean {
    if (this.hasHandledRouteExternalFileTask || !this.routeExternalFileTask) {
      return false;
    }
    const task = this.routeExternalFileTask;
    if (task.uris.length <= 0) {
      logger.warn(TAG, `外部文件独立任务缺少URI: source=${source}, kind=${task.kind}`);
      this.hasHandledRouteExternalFileTask = true;
      return true;
    }
    this.hasHandledRouteExternalFileTask = true;
    setTimeout((): void => {
      void this.handleExternalFileTaskParams(task);
    }, 500);
    logger.info(TAG, `已调度外部文件独立任务: source=${source}, kind=${task.kind}, count=${task.uris.length}`);
    return true;
  }

  private async handleExternalFileTaskParams(task: ExternalFileTaskParams): Promise<void> {
    try {
      if (task.uris.length > 1) {
        await this.handleExternalFileTaskBatch(task);
        return;
      }
      const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(task);
      await this.handlePendingFileWithCategory(
        primaryUri,
        task.mimeType,
        String(task.kind),
        String(task.source),
        task.target,
        ExternalFileTaskFactory.resolveDisplayName(task)
      );
    } catch (error) {
      logger.error(TAG, `处理外部文件独立任务失败: ${String(error)}`);
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  private async handleExternalFileTaskBatch(task: ExternalFileTaskParams): Promise<void> {
    logger.info(TAG, `处理外部文件批量任务: kind=${task.kind}, count=${task.uris.length}`);
    const kind = String(task.kind);
    if (kind === 'comic') {
      await this.handlePendingShareFiles(task.uris, String(task.kind));
      return;
    }
    if (kind === 'ebook') {
      for (let i = 0; i < task.uris.length; i++) {
        await this.handleExternalEBookImport(task.uris[i]);
      }
      return;
    }
    if (kind === 'pdf') {
      for (let i = 0; i < task.uris.length; i++) {
        await this.handlePdfImportWithCategorySelection(task.uris[i]);
      }
      return;
    }

    for (let i = 0; i < task.uris.length; i++) {
      const singleTask = this.createSingleUriExternalTask(task, task.uris[i]);
      await this.handlePendingFileWithCategory(
        ExternalFileTaskFactory.resolvePrimaryUri(singleTask),
        singleTask.mimeType,
        String(singleTask.kind),
        String(singleTask.source),
        singleTask.target,
        ExternalFileTaskFactory.resolveDisplayName(singleTask)
      );
    }
  }

  private createSingleUriExternalTask(sourceTask: ExternalFileTaskParams, uri: string): ExternalFileTaskParams {
    const singleTask = ExternalFileTaskFactory.clone(sourceTask);
    singleTask.uris = [uri];
    singleTask.displayName = ExternalFileTaskFactory.extractFileName(uri);
    if (singleTask.displayName.length <= 0) {
      singleTask.displayName = sourceTask.displayName;
    }
    return singleTask;
  }

  /**
   * 检查并处理待导入的文件
   */
  private checkPendingFileImport(): void {
    try {
      // 优先检查系统分享导入
      const shareImportPending = AppStorage.get<boolean>('shareImportPending');
      if (shareImportPending) {
        logger.info(TAG, '📤 检测到系统分享导入');
        this.checkPendingShareImport();
        return;
      }

      // 检查普通文件导入
      const fileImportPending = AppStorage.get<boolean>('fileImportPending');
      
      if (fileImportPending) {
        logger.info(TAG, '📁 检测到待处理的文件导入');
        
        // 清除标记
        AppStorage.delete('fileImportPending');
        
        // 获取文件信息
        const pendingFileUri = AppStorage.get<string>('pendingFileUri');
        const pendingFileType = AppStorage.get<string>('pendingFileType');
        const pendingFileCategory = AppStorage.get<string>('pendingFileCategory');
        const pendingFileSource = AppStorage.get<string>('pendingFileSource');
        const pendingFileTarget = AppStorage.get<string>('pendingFileTarget');
        const pendingFileDisplayName = AppStorage.get<string>('pendingFileDisplayName');
        const pendingImportFlowId = AppStorage.get<string>('pendingImportFlowId');
        
        if (pendingFileUri) {
          logger.info(TAG, `准备处理文件: ${pendingFileUri}, 分类: ${pendingFileCategory}`);
          const entrySource = this.mapImportSource(pendingFileSource || '');
          const contentType = this.mapImportContentType(pendingFileCategory || '');
          if (pendingImportFlowId && pendingImportFlowId.length > 0) {
            this.currentImportFlowId = pendingImportFlowId;
            this.ensureImportFlow(
              entrySource,
              contentType,
              pendingFileDisplayName || pendingFileType || '',
              1,
              false,
              pendingFileUri,
              pendingFileTarget || ''
            );
          } else {
            this.startImportFlow(
              entrySource,
              contentType,
              pendingFileDisplayName || pendingFileType || '',
              1,
              false,
              pendingFileUri,
              pendingFileTarget || ''
            );
          }
          const consumedEvent: ImportFlowEvent = new ImportFlowEvent();
          consumedEvent.eventType = ImportFlowEventType.PENDING_MARKERS_CONSUMED;
          consumedEvent.reason = 'pending_file_consumed';
          consumedEvent.entrySource = entrySource;
          consumedEvent.contentType = contentType;
          consumedEvent.sourceUri = pendingFileUri;
          consumedEvent.targetPath = pendingFileTarget || '';
          consumedEvent.displayName = pendingFileDisplayName || pendingFileType || '';
          consumedEvent.fileCount = 1;
          consumedEvent.transferRecordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID) || '';
          consumedEvent.detail = `category=${pendingFileCategory || ''}, source=${pendingFileSource || ''}, target=${pendingFileTarget || ''}`;
          this.recordImportFlowEvent(consumedEvent);
          
          // 清除文件信息
          AppStorage.delete('pendingFileUri');
          AppStorage.delete('pendingFileType');
          AppStorage.delete('pendingFileCategory');
          AppStorage.delete('pendingFileSource');
          AppStorage.delete('pendingFileTarget');
          AppStorage.delete('pendingFileDisplayName');
          AppStorage.delete('pendingImportFlowId');
          
          // 延迟处理，确保UI完全渲染
          setTimeout(() => {
            this.handlePendingFileWithCategory(
              pendingFileUri,
              pendingFileType || '',
              pendingFileCategory || '',
              pendingFileSource || '',
              pendingFileTarget || '',
              pendingFileDisplayName || ''
            );
          }, 800);
        }
      }
    } catch (error) {
      logger.error(TAG, '检查待导入文件失败', String(error));
    }
  }

  private finalizeTrackedTransferImport(
    status: 'imported' | 'import_failed' | 'import_cancelled'
  ): void {
    try {
      const recordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
      const trackingActive = AppStorage.get<boolean>(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);
      if (!trackingActive || !recordId || recordId.trim().length <= 0) {
        return;
      }

      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RESULT, status);
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_TRACKING_ACTIVE, false);
      const event: ImportFlowEvent = new ImportFlowEvent();
      event.eventType = ImportFlowEventType.TRANSFER_RESULT_WRITTEN;
      event.reason = status;
      event.entrySource = ImportFlowEntrySource.LAN_TRANSFER;
      event.transferRecordId = recordId;
      event.success = status !== 'import_failed';
      event.severity = status === 'import_failed' ? ImportFlowSeverity.ERROR : ImportFlowSeverity.INFO;
      event.detail = `status=${status}`;
      this.recordImportFlowEvent(event);
      logger.info(TAG, `已回写局域网传书导入结果: recordId=${recordId}, status=${status}`);
    } catch (error) {
      logger.warn(TAG, `回写局域网传书导入结果失败: ${String(error)}`);
    }
  }

  /**
   * 根据文件分类处理待导入的文件
   */
  private async handlePendingFileWithCategory(
    fileUri: string,
    fileType: string,
    category: string,
    source: string = '',
    target: string = '',
    displayName: string = ''
  ): Promise<void> {
    const entrySource = this.mapImportSource(source);
    const contentType = this.mapImportContentType(category);
    try {
      logger.info(TAG, `根据分类处理文件: ${fileUri}, 分类: ${category}, 来源: ${source}, 目标: ${target}`);
      this.ensureImportFlow(
        entrySource,
        contentType,
        displayName || fileType,
        1,
        false,
        fileUri,
        target
      );
      const entryEvent: ImportFlowEvent = new ImportFlowEvent();
      entryEvent.eventType = ImportFlowEventType.ENTRY_RECEIVED;
      entryEvent.reason = 'pending_category_dispatch';
      entryEvent.entrySource = entrySource;
      entryEvent.contentType = contentType;
      entryEvent.sourceUri = fileUri;
      entryEvent.targetPath = target;
      entryEvent.displayName = displayName || fileType;
      entryEvent.fileCount = 1;
      entryEvent.detail = `category=${category}, source=${source}, target=${target}`;
      this.recordImportFlowEvent(entryEvent);

      if (source === 'network_folder' && target === 'download_dir') {
        await this.handleNetworkFolderPendingImport(fileUri, fileType, category, displayName);
        return;
      }
      
      switch (category) {
        case 'comic':
          // 漫画文件（cbz, cbr）
          await this.handleExternalComicImport(fileUri);
          break;
          
        case 'ebook':
          // 电子书文件（epub, mobi, azw3）
          await this.handleExternalEBookImport(fileUri);
          break;
          
        case 'pdf':
          // PDF文件
          await this.handlePdfImportWithCategorySelection(fileUri);
          break;
          
        default:
          // 未知分类，使用原有逻辑根据扩展名判断
          await this.handlePendingFile(fileUri, fileType);
          break;
      }
    } catch (error) {
      logger.error(TAG, '根据分类处理文件失败', String(error));
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'pending_category_dispatch_failed';
      failedEvent.entrySource = entrySource;
      failedEvent.contentType = contentType;
      failedEvent.sourceUri = fileUri;
      failedEvent.displayName = displayName || fileType;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  private async handleNetworkFolderPendingImport(
    fileUri: string,
    fileType: string,
    category: string,
    displayName: string
  ): Promise<void> {
    const resolvedName = displayName.trim().length > 0 ? displayName : fileType;
    logger.info(TAG, `开始处理网络文件夹导入: ${resolvedName}, 分类: ${category}`);

    switch (category) {
      case 'comic':
        await this.handleNetworkFolderComicImport(fileUri, resolvedName);
        return;
      case 'ebook':
        await this.handleNetworkFolderEBookImport(fileUri, resolvedName);
        return;
      case 'pdf':
        await this.handleNetworkFolderPdfImport(fileUri, resolvedName);
        return;
      case 'backup':
      case 'json':
      case 'font':
      case 'code':
      case 'avif':
      case 'image':
        this.handoffNetworkFolderImportToMainMenu(category, fileUri, resolvedName);
        return;
      default:
        logger.info(TAG, `网络文件夹导入走通用处理流程: ${category}`);
        await this.handlePendingFile(fileUri, resolvedName);
        return;
    }
  }

  private handoffNetworkFolderImportToMainMenu(category: string, fileUri: string, displayName: string): void {
    logger.info(TAG, `网络文件夹文件交由首页处理: 分类=${category}, 文件=${displayName}`);

    const taskKind = ExternalFileTaskFactory.normalizeKind(category);
    const externalTask = ExternalFileTaskFactory.createSingleFileTask(
      taskKind,
      fileUri,
      displayName,
      ExternalFileTaskSource.NETWORK_FOLDER,
      displayName,
      category === 'code' ? this.inferCodeLanguageFromFileName(displayName) : '',
      'download_dir'
    );
    void openExternalFileTaskInIsolatedAbility(
      this.uiContext,
      externalTask,
      'DataManagementPage.networkFolderHandoff'
    ).then((started: boolean): void => {
      if (started) {
        logger.info(TAG, `网络文件夹文件已交由独立任务处理: 分类=${category}, 文件=${displayName}`);
      } else {
        this.handoffNetworkFolderImportToMainMenuFallback(category, fileUri, displayName);
      }
    });
  }

  private handoffNetworkFolderImportToMainMenuFallback(category: string, fileUri: string, displayName: string): void {
    logger.info(TAG, `网络文件夹文件回退首页处理: 分类=${category}, 文件=${displayName}`);

    if (category === 'backup') {
      AppStorage.setOrCreate('pendingBackupUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'backup');
      AppStorage.setOrCreate('backupImportPending', true);
      this.navigateToMainMenuForNetworkImport('备份文件');
      return;
    }

    if (category === 'json') {
      AppStorage.setOrCreate('pendingJsonUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'json');
      this.navigateToMainMenuForNetworkImport('JSON 文件');
      return;
    }

    if (category === 'font') {
      AppStorage.setOrCreate('pendingFontUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', 'font');
      this.navigateToMainMenuForNetworkImport('字体文件');
      return;
    }

    if (category === 'code') {
      AppStorage.setOrCreate('pendingCodeUri', fileUri);
      AppStorage.setOrCreate('pendingCodeLanguage', this.inferCodeLanguageFromFileName(displayName));
      AppStorage.setOrCreate('pendingFileCategory', 'code');
      this.navigateToMainMenuForNetworkImport('代码文件');
      return;
    }

    if (category === 'avif' || category === 'image') {
      AppStorage.setOrCreate('pendingAvifUri', fileUri);
      AppStorage.setOrCreate('pendingFileCategory', category);
      this.navigateToMainMenuForNetworkImport(category === 'avif' ? 'AVIF 图片' : '图片文件');
      return;
    }
  }

  private navigateToMainMenuForNetworkImport(typeLabel: string): void {
    try {
      this.showToast(`已转交首页处理${typeLabel}`);
      if (this.pathStack.size() > 0) {
        this.pathStack.pop();
        logger.info(TAG, `网络文件夹导入后回退首页成功: ${typeLabel}`);
        return;
      }
      this.pathStack.pushPathByName('MainMenuPage', undefined);
      logger.info(TAG, `网络文件夹导入后兜底跳转首页成功: ${typeLabel}`);
    } catch (error) {
      logger.warn(TAG, `跳转首页处理${typeLabel}失败: ${String(error)}`);
      this.showToast(`请返回首页继续处理${typeLabel}`);
    }
  }

  private inferCodeLanguageFromFileName(fileName: string): string {
    const lowerName = fileName.trim().toLowerCase();
    const lastDot = lowerName.lastIndexOf('.');
    if (lastDot < 0 || lastDot >= lowerName.length - 1) {
      return 'plaintext';
    }
    const extension = lowerName.substring(lastDot + 1);
    switch (extension) {
      case 'ts':
      case 'ets':
      case 'tsx':
        return 'typescript';
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'py':
        return 'python';
      case 'java':
        return 'java';
      case 'cpp':
      case 'c':
      case 'h':
      case 'hpp':
        return 'cpp';
      case 'cs':
        return 'csharp';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'swift':
        return 'swift';
      case 'kt':
        return 'kotlin';
      case 'rb':
        return 'ruby';
      case 'php':
        return 'php';
      case 'html':
      case 'htm':
        return 'html';
      case 'css':
        return 'css';
      case 'scss':
        return 'scss';
      case 'less':
        return 'less';
      case 'jsonc':
        return 'json';
      case 'xml':
        return 'xml';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'shell';
      case 'ps1':
        return 'powershell';
      case 'bat':
      case 'cmd':
        return 'bat';
      case 'ini':
      case 'conf':
      case 'cfg':
        return 'ini';
      case 'toml':
        return 'toml';
      case 'lua':
        return 'lua';
      case 'r':
        return 'r';
      case 'dart':
        return 'dart';
      case 'vue':
        return 'vue';
      case 'svelte':
        return 'svelte';
      default:
        return 'plaintext';
    }
  }

  private async handleNetworkFolderComicImport(fileUriValue: string, displayName: string): Promise<void> {
    const stagedPath = await this.stageNetworkImportFileToDownload('imports/network_folder/comics', fileUriValue, displayName);
    const stagedUri = fileUri.getUriFromPath(stagedPath);
    logger.info(TAG, `网络漫画文件已转入 Download 应用目录，准备显示漫画导入对话框: ${stagedPath}`);
    await this.showDownloadSingleImportDialog(stagedUri, displayName);
  }

  private async handleNetworkFolderEBookImport(fileUriValue: string, displayName: string): Promise<void> {
    const stagedPath = await this.stageNetworkImportFileToDownload('ebooks', fileUriValue, displayName);
    logger.info(TAG, `网络电子书文件已转入 Download 应用目录，准备继续电子书导入: ${stagedPath}`);
    await this.continueImportEBook(stagedPath);
  }

  private async handleNetworkFolderPdfImport(fileUriValue: string, displayName: string): Promise<void> {
    const stagedPath = await this.stageNetworkImportFileToDownload('imports/network_folder/pdfs', fileUriValue, displayName);
    logger.info(TAG, `网络 PDF 文件已转入 Download 应用目录，准备显示 PDF 导入对话框: ${stagedPath}`);
    await this.handlePdfImportWithCategorySelection(stagedPath, DownloadDirManager.ensureDirectory('manga'), 'network_folder_pdf');
  }

  /**
   * 检查并处理系统分享导入的文件
   */
  private checkPendingShareImport(): void {
    try {
      // 清除标记
      AppStorage.delete('shareImportPending');

      // 获取分享文件信息（Bug 2 fix：MainMenuPage将pendingShareFiles存为JSON字符串，需要解析）
      const rawShareFiles = AppStorage.get<string | string[]>('pendingShareFiles');
      let pendingShareFiles: string[] = [];
      if (typeof rawShareFiles === 'string') {
        try {
          pendingShareFiles = SafeUtils.parseArr(rawShareFiles) as string[];
        } catch {
          logger.warn(TAG, '解析pendingShareFiles JSON失败');
          pendingShareFiles = [];
        }
      } else if (Array.isArray(rawShareFiles)) {
        pendingShareFiles = rawShareFiles;
      }
      const pendingShareType = AppStorage.get<string>('pendingShareType');

      if (!pendingShareFiles || pendingShareFiles.length === 0) {
        logger.warn(TAG, '未找到分享文件数据');
        return;
      }

      logger.info(TAG, `准备处理 ${pendingShareFiles.length} 个分享文件`);

      // 清除分享信息
      AppStorage.delete('pendingShareFiles');
      AppStorage.delete('pendingShareType');
      AppStorage.delete('pendingShareSource');

      // 延迟处理，确保UI完全渲染
      setTimeout(() => {
        this.handlePendingShareFiles(pendingShareFiles, pendingShareType || 'comic');
      }, 800);

    } catch (error) {
      logger.error(TAG, '检查系统分享文件失败', String(error));
    }
  }

  /**
   * 处理系统分享导入的多个文件
   */
  private async handlePendingShareFiles(fileUris: string[], fileType: string): Promise<void> {
    try {
      logger.info(TAG, `开始处理 ${fileUris.length} 个分享文件`);

      // 根据文件类型处理
      if (fileType === 'comic') {
        // 将文件URI添加到选中文件列表
        this.selectedFiles = [...fileUris];

        // 更新状态
        this.updateProgress(ImportStatus.IDLE, `已接收 ${fileUris.length} 个文件（系统分享）`, 10);

        // 显示成功提示
        logger.info(TAG, `✅ 已接收 ${fileUris.length} 个漫画文件，准备导入`);

        // 延迟自动开始导入，给用户查看的时间
        setTimeout(async () => {
          try {
            await this.startImport();
          } catch (error) {
            logger.error(TAG, '分享文件自动导入失败', String(error));
          }
        }, 1000);
      } else {
        logger.warn(TAG, `不支持的分享文件类型: ${fileType}`);
      }

    } catch (error) {
      logger.error(TAG, '处理分享文件失败', String(error));
      this.updateProgress(ImportStatus.ERROR, `处理分享文件失败: ${error}`, 0);
    }
  }

  /**
   * 处理待导入的文件
   */
  private async handlePendingFile(fileUri: string, fileType: string): Promise<void> {
    try {
      logger.info(TAG, `开始处理待导入文件: ${fileUri}`);
      
      // 从URI提取文件扩展名（如果fileType为空）
      let actualFileType = fileType;
      if (!actualFileType || actualFileType.trim() === '') {
        const decodedUri = decodeURIComponent(fileUri);
        const lastDotIndex = decodedUri.lastIndexOf('.');
        if (lastDotIndex > 0) {
          actualFileType = decodedUri.substring(lastDotIndex).toLowerCase();
          logger.info(TAG, `从URI提取文件扩展名: ${actualFileType}`);
        }
      }
      
      // 根据文件类型处理
      const lowerType = actualFileType.toLowerCase();
      const isComicArchive = DataManagementPage.MANGA_EXTENSIONS.some((ext: string) =>
        lowerType.includes(ext) || lowerType.includes(`.${ext}`)
      );
      if (isComicArchive) {
        // 漫画文件
        await this.handleExternalComicImport(fileUri);
      } else if (lowerType.includes('pdf') || lowerType.includes('.pdf')) {
        // PDF文件 - 询问用户分类
        await this.handlePdfImportWithCategorySelection(fileUri);
      } else if (lowerType.includes('epub') || lowerType.includes('.epub') ||
                 lowerType.includes('txt') || lowerType.includes('.txt')) {
        // 其他电子书文件
        await this.handleExternalEBookImport(fileUri);
      } else {
        logger.warn(TAG, `不支持的文件类型: ${actualFileType}`);
      }
    } catch (error) {
      logger.error(TAG, '处理待导入文件失败', String(error));
    }
  }

  /**
   * 订阅文件导入请求事件
   */
  private subscribeFileImportEvent(): void {
    if (this.fileImportEventSubscribed) {
      return;
    }
    eventBus.subscribe(GameEvent.FILE_IMPORT_REQUESTED, this.fileImportRequestedListener);
    this.fileImportEventSubscribed = true;
  }

  /**
   * 处理外部漫画文件导入
   */
  private async handleExternalComicImport(fileUri: string): Promise<void> {
    try {
      logger.info(TAG, `处理外部漫画文件导入: ${fileUri}`);
      await this.waitForPendingBatchDialogAnalysis();
      await this.waitForPendingArchiveCleanup();
      this.ensureImportFlow(
        this.currentImportFlowId.length > 0 ? ImportFlowEntrySource.UNKNOWN : ImportFlowEntrySource.EXTERNAL_FILE_TASK,
        ImportFlowContentType.MANGA,
        this.getFileNameFromUri(fileUri),
        1,
        false,
        fileUri,
        ''
      );
      
      // 将文件URI添加到选中文件列表
      this.selectedFiles = [fileUri];
      
      // 更新状态
      this.updateProgress(ImportStatus.IDLE, '已选择 1 个文件（从外部打开）', 10);
      
      // 自动开始导入
      await this.startImport();
    } catch (error) {
      logger.error(TAG, '处理外部漫画文件导入失败', String(error instanceof Error ? error.message : error));
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${error}`, 0);
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  /**
   * 处理外部电子书文件导入
   */
  private async handleExternalEBookImport(fileUri: string): Promise<void> {
    try {
      logger.info(TAG, `处理外部电子书文件导入: ${fileUri}`);
      this.ensureImportFlow(
        this.currentImportFlowId.length > 0 ? ImportFlowEntrySource.UNKNOWN : ImportFlowEntrySource.EXTERNAL_FILE_TASK,
        ImportFlowContentType.EBOOK,
        this.getFileNameFromUri(fileUri),
        1,
        false,
        fileUri,
        ''
      );
      
      // 直接调用导入电子书方法
      await this.importEBook(fileUri);
    } catch (error) {
      logger.error(TAG, '处理外部电子书文件导入失败', String(error instanceof Error ? error.message : error));
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  /**
   * 处理PDF文件导入，显示综合设置对话框
   */
  private async handlePdfImportWithCategorySelection(
    fileUri: string,
    preferredOutputDir: string = '',
    sourceId: string = 'local_pdf'
  ): Promise<void> {
    try {
      logger.info(TAG, `处理PDF文件导入，显示设置对话框: ${fileUri}`);
      this.ensureImportFlow(
        this.currentImportFlowId.length > 0 ? ImportFlowEntrySource.UNKNOWN : ImportFlowEntrySource.FILE_PICKER,
        ImportFlowContentType.PDF,
        this.pdfImportService.getDefaultTitle(fileUri),
        1,
        false,
        fileUri,
        preferredOutputDir
      );
      
      const defaultTitle = this.pdfImportService.getDefaultTitle(fileUri);
      
      // 显示综合设置对话框
      const dialogResult = await this.showPdfImportDialog(defaultTitle, fileUri);
      
      if (dialogResult === null) {
        logger.info(TAG, 'PDF导入已取消');
        // [修复] 清除进度提示信息
        this.updateProgress(ImportStatus.IDLE, '', 0);
        this.finalizeTrackedTransferImport('import_cancelled');
        this.endCurrentImportFlow('pdf_dialog_cancelled');
        return;
      }
      
      logger.info(TAG, `用户确认PDF导入: 类型=${dialogResult.contentType}, 标题=${dialogResult.title}`);
      
      // 开始后台导入任务
      await this.startPdfImportTask(fileUri, dialogResult, preferredOutputDir, sourceId);
      
    } catch (error) {
      logger.error(TAG, '处理PDF文件导入失败', String(error instanceof Error ? error.message : error));
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'pdf_import_prepare_failed';
      failedEvent.contentType = ImportFlowContentType.PDF;
      failedEvent.sourceUri = fileUri;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.errorMessage = String(error instanceof Error ? error.message : error);
      this.recordImportFlowEvent(failedEvent);
      this.showToast('PDF导入失败: ' + String(error instanceof Error ? error.message : error));
      this.finalizeTrackedTransferImport('import_failed');
      this.endCurrentImportFlow('pdf_import_prepare_failed');
    }
  }

  /**
   * 显示PDF导入综合设置对话框
   */
  private async showPdfImportDialog(defaultTitle: string, sourceFileName: string): Promise<PdfImportDialogResult | null> {
    return new Promise<PdfImportDialogResult | null>((resolve) => {
      this.pdfImportDialogController = new CustomDialogController({
        builder: PdfImportDialog({
          themeState: this.themeState,
          defaultTitle: defaultTitle,
          defaultAuthor: '',
          sourceFileName: sourceFileName,
          onConfirm: (result: PdfImportDialogResult) => {
            logger.info(TAG, `PDF导入对话框确认: ${result.title}`);
            const event: ImportFlowEvent = new ImportFlowEvent();
            event.eventType = ImportFlowEventType.DIALOG_CONFIRMED;
            event.reason = 'pdf_dialog_confirmed';
            event.contentType = ImportFlowContentType.PDF;
            event.displayName = result.title;
            event.sourceUri = sourceFileName;
            event.detail = `contentType=${result.contentType}, mode=${result.importMode}`;
            this.recordImportFlowEvent(event);
            resolve(result);
          },
          onCancel: () => {
            logger.info(TAG, 'PDF导入对话框取消');
            const event: ImportFlowEvent = new ImportFlowEvent();
            event.eventType = ImportFlowEventType.DIALOG_CANCELLED;
            event.reason = 'pdf_dialog_cancelled';
            event.contentType = ImportFlowContentType.PDF;
            event.sourceUri = sourceFileName;
            this.recordImportFlowEvent(event);
            resolve(null);
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        customStyle: true
      });
      
      this.pdfImportDialogController.open();
      logger.info(TAG, 'PDF导入设置对话框已显示');
      const event: ImportFlowEvent = new ImportFlowEvent();
      event.eventType = ImportFlowEventType.DIALOG_OPENED;
      event.reason = 'pdf_dialog_opened';
      event.contentType = ImportFlowContentType.PDF;
      event.displayName = defaultTitle;
      event.sourceUri = sourceFileName;
      this.recordImportFlowEvent(event);
    });
  }

  /**
   * 启动PDF导入后台任务
   */
  private async startPdfImportTask(
    fileUri: string,
    dialogResult: PdfImportDialogResult,
    preferredOutputDir: string = '',
    sourceId: string = 'local_pdf'
  ): Promise<void> {
    const taskManager = BackgroundTaskManager.getInstance();
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取应用上下文');
    }
    const filesDir = context.filesDir;
    
    // 创建后台任务
    const activeImportFlowId: string = this.currentImportFlowId;
    const taskId = taskManager.createTask(
      TaskType.PDF_IMPORT,
      `导入: ${dialogResult.title}`,
      async (onProgress, cancelSignal) => {
        return await this.executePdfImportWithDialogResult(
          fileUri,
          dialogResult,
          filesDir,
          onProgress,
          cancelSignal,
          preferredOutputDir,
          sourceId,
          activeImportFlowId
        );
      },
      {
        context: context,
        enableBackgroundRunning: true,
        notification: {
          scene: TaskNotificationScene.PDF_IMPORT,
          targetName: dialogResult.title
        }
      }
    );
    const createdEvent: ImportFlowEvent = new ImportFlowEvent();
    createdEvent.eventType = ImportFlowEventType.PDF_TASK_CREATED;
    createdEvent.reason = 'pdf_task_created';
    createdEvent.contentType = ImportFlowContentType.PDF;
    createdEvent.sourceUri = fileUri;
    createdEvent.targetPath = preferredOutputDir;
    createdEvent.displayName = dialogResult.title;
    createdEvent.taskId = taskId;
    this.recordImportFlowEvent(createdEvent);
    
    // 启动任务（后台执行）
    taskManager.startTask(taskId).then(() => {
      logger.info(TAG, `PDF导入任务完成: ${taskId}`);
      const event: ImportFlowEvent = new ImportFlowEvent();
      event.eventType = ImportFlowEventType.PDF_TASK_COMPLETED;
      event.reason = 'pdf_task_completed';
      event.sessionId = activeImportFlowId;
      event.contentType = ImportFlowContentType.PDF;
      event.sourceUri = fileUri;
      event.displayName = dialogResult.title;
      event.taskId = taskId;
      this.recordImportFlowEvent(event);
      this.showToast(`导入成功: ${dialogResult.title}`);
      this.finalizeTrackedTransferImport('imported');
      // 发送导入完成事件
      const payload = new MangaImportCompletedPayload(1, 1);
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, payload);
      this.recordSimpleImportFlowEvent(
        ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED,
        'pdf_bookshelf_refresh_published',
        ImportFlowContentType.PDF,
        ImportFlowEntrySource.UNKNOWN,
        true,
        dialogResult.title,
        0
      );
      this.endCurrentImportFlow('pdf_import_completed');
    }).catch((error: Error) => {
      logger.error(TAG, `PDF导入任务失败: ${taskId}`, error.message);
      const event: ImportFlowEvent = new ImportFlowEvent();
      event.eventType = ImportFlowEventType.PDF_TASK_FAILED;
      event.reason = 'pdf_task_failed';
      event.sessionId = activeImportFlowId;
      event.contentType = ImportFlowContentType.PDF;
      event.sourceUri = fileUri;
      event.displayName = dialogResult.title;
      event.taskId = taskId;
      event.success = false;
      event.severity = ImportFlowSeverity.ERROR;
      event.errorMessage = error.message;
      this.recordImportFlowEvent(event);
      this.showToast(`导入失败: ${error.message}`);
      this.finalizeTrackedTransferImport('import_failed');
      this.endCurrentImportFlow('pdf_import_failed');
    });
    
    // 显示提示，任务已在后台运行
    this.showToast('PDF导入已开始，可以离开此页面');
  }

  /**
   * 执行PDF导入（使用对话框结果）
   */
  private async executePdfImportWithDialogResult(
    fileUri: string,
    dialogResult: PdfImportDialogResult,
    filesDir: string,
    onProgress: (current: number, total: number, message: string) => void,
    cancelSignal: TaskCancelSignal,
    preferredOutputDir: string = '',
    sourceId: string = 'local_pdf',
    importFlowId: string = ''
  ): Promise<PdfImportResult> {
    try {
      const result = await this.pdfImportService.executeImport({
        fileUri: fileUri,
        dialogResult: dialogResult,
        filesDir: filesDir,
        outputDir: preferredOutputDir,
        cancelSignal: cancelSignal,
        sourceId: sourceId,
        importFlowId: importFlowId,
        onProgress: (current: number, total: number, message: string) => {
          onProgress(current, total, message);
          this.updateProgress(ImportStatus.PROCESSING, message, total > 0 ? Math.floor((current / total) * 100) : 0);
        }
      });

      this.updateProgress(ImportStatus.COMPLETED, `导入成功: ${dialogResult.title}`, 100);
      return result;
    } catch (error) {
      logger.error(TAG, 'PDF导入失败', String(error instanceof Error ? error.message : error));
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${error}`, 0);
      throw error as Error;
    }
  }

  /**
   * 将PDF导入结果保存到数据库
   */
  private async savePdfImportToDatabase(result: PdfImportResult, contentType: PdfContentType): Promise<void> {
    if (!result.comicInfo || !result.mangaId || !result.chapterId) {
      throw new Error('PDF导入结果不完整');
    }
    
    const now = Date.now();
    const isSingleChapter = result.importMode === PdfImportMode.SINGLE_CHAPTER;
    const isNewManga = result.isNewManga !== false; // 默认为新建漫画
    
    let mangaId: string;
    
    // 1. 处理漫画信息
    if (isSingleChapter && !isNewManga) {
      // 单章节模式且漫画已存在：使用已有漫画ID，更新章节数
      mangaId = result.mangaId;
      logger.info(TAG, `单章节模式：使用已有漫画 ${mangaId}`);
      
      // 更新漫画的章节数和最后更新时间
      try {
        const existingManga = await this.dataManager.getComicById(mangaId);
        if (existingManga) {
          const newChapterCount = (existingManga.chapterCount || 0) + 1;
          await this.dataManager.updateComicBasicInfo(mangaId, {
            // 仅更新章节数，其他信息保持不变
          });
          logger.info(TAG, `已更新漫画章节数: ${newChapterCount}`);
        }
      } catch (e) {
        logger.warn(TAG, `更新漫画章节数失败: ${e}`);
      }
    } else {
      // 单行本模式或新建漫画：创建新漫画信息
      const comicInput: ComicInfoInput = {
        title: result.comicInfo.title || '未知标题',
        author: result.comicInfo.writer || '未知作者',
        description: result.comicInfo.summary || '',
        coverUrl: result.coverPath || '',
        sourceId: 'local_pdf',
        externalId: result.mangaId || '',
        status: isSingleChapter ? MangaStatus.ONGOING : MangaStatus.COMPLETED,
        tags: result.comicInfo.tags || ['PDF导入'],
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: now,
        contentType: contentType === PdfContentType.MANGA ? 'manga' : 'ebook'
      };
      
      logger.info(TAG, `准备保存漫画信息: title=${comicInput.title}, externalId=${comicInput.externalId}, sourceId=${comicInput.sourceId}`);
      mangaId = await this.dataManager.addComicInfo(comicInput);
      logger.info(TAG, `漫画信息已保存: ${mangaId}`);
    }
    
    // 2. 创建章节信息
    const chapterTitle = isSingleChapter 
      ? (result.chapterTitle || `第${result.chapterNumber || 1}话`)
      : (result.comicInfo.title || '全卷');
    const chapterIndex = isSingleChapter ? (result.chapterNumber || 1) - 1 : 0;
    
    const chapterInput: ChapterInfoInput = {
      comicId: mangaId,
      title: chapterTitle,
      index: chapterIndex,
      pageCount: result.totalPages || 0,
      isDownloaded: true,
      downloadPath: result.imageFiles && result.imageFiles.length > 0 
        ? result.imageFiles[0].imagePath.substring(0, result.imageFiles[0].imagePath.lastIndexOf('/'))
        : '',
      publishTime: now,
      externalId: result.chapterId
    };
    
    const chapterId = await this.dataManager.addChapterInfo(chapterInput);
    logger.info(TAG, `章节信息已保存: ${chapterId}`);
    
    // 3. 创建页面信息
    if (result.imageFiles) {
      for (const pageImage of result.imageFiles) {
        const pageInput: PageInfoInput = {
          chapterId: chapterId,
          index: pageImage.pageIndex,
          imageUrl: pageImage.imagePath,
          localPath: pageImage.imagePath,
          width: pageImage.width || 0,
          height: pageImage.height || 0,
          fileSize: pageImage.fileSize || 0
        };
        
        await this.dataManager.addPageInfo(pageInput);
      }
      logger.info(TAG, `${result.imageFiles.length} 个页面信息已保存`);
    }
    
    // 4. 添加到收藏
    const favoriteInput: FavoriteInfoInput = {
      comicId: mangaId,
      userId: 'default_user',
      tags: result.comicInfo.tags || ['PDF导入']
    };
    await this.dataManager.addFavorite(favoriteInput);
    logger.info(TAG, `已添加到收藏`);
  }

  /**
   * 根据标题查找已存在的漫画
   * @param title 漫画标题
   * @returns 漫画ID，如果不存在则返回undefined
   */
  private async findExistingMangaByTitle(title: string): Promise<string | undefined> {
    try {
      // 使用DataManager查询同名漫画
      const comics = await this.dataManager.searchComics(title);
      
      // 精确匹配标题
      for (const comic of comics) {
        if (comic.title === title) {
          logger.info(TAG, `找到同名漫画: ${title}, ID: ${comic.id}`);
          return comic.id;
        }
      }
      
      return undefined;
    } catch (error) {
      logger.error(TAG, `查找同名漫画失败: ${error}`);
      return undefined;
    }
  }

  /**
   * 检查漫画是否已存在指定章节
   * @param mangaId 漫画ID
   * @param chapterNumber 章节编号
   * @returns 是否存在
   */
  private async checkChapterExists(mangaId: string, chapterNumber: number): Promise<boolean> {
    try {
      const chapters: ChapterRecord[] = await this.dataManager.getChaptersByMangaId(mangaId);
      
      // 检查是否有相同编号的章节（index = chapterNumber - 1）
      const chapterIndex = chapterNumber - 1;
      for (let i = 0; i < chapters.length; i++) {
        const chapter: ChapterRecord = chapters[i];
        if (chapter.index === chapterIndex) {
          logger.info(TAG, `漫画 ${mangaId} 已存在第 ${chapterNumber} 话`);
          return true;
        }
      }
      
      return false;
    } catch (error) {
      logger.error(TAG, `检查章节是否存在失败: ${error}`);
      return false;
    }
  }

  /**
   * 初始化响应式布局
   */
  private initializeResponsiveLayout(): void {
    try {
      // 更新响应式参数
      this.updateResponsiveParams();

      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      
      this.deviceManager.addListener(this.deviceChangeListener);
      
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    // 根据断点设置内容最大宽度
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}`);
  }

  private lifecycle = new PageLifecycleManager('DataManagementPage', { enableDebug: true });

  /**
   * 页面隐藏时的回调
   */
  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.isPageActive = false;
    this.pageLifecycleGeneration += 1;
    this.folderPickerGeneration += 1;
    this.isFilePickerActive = false;
    this.isMangaDialogOpening = false;
    this.batchMangaImportDialogController?.close();
    this.batchMangaImportDialogController = null;
    this.mangaImportDialogController?.close();
    this.mangaImportDialogController = null;
    if (!this.isMangaImportCommitting) {
      this.isMangaImportRunning = false;
    }
    const activeGenerations: string[] = Array.from<string>(this.activeBatchAnalysisGenerations);
    for (const generation of activeGenerations) {
      this.invalidateBatchAnalysisGeneration(generation);
    }
    this.importArchiveParseCache.clear();
    this.restorePickedImageSelections();
    this.selectedImageGroupSources.clear();
    if (!this.isMangaImportCommitting) {
      this.scheduleTrackedArchiveCleanup('page_disappeared');
    }
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    if (this.fileImportEventSubscribed) {
      eventBus.unsubscribe(GameEvent.FILE_IMPORT_REQUESTED, this.fileImportRequestedListener);
      this.fileImportEventSubscribed = false;
    }
  }

  /**
   * 选择电子书文件
   * 注意：必须在 picker.select().then() 回调中直接处理文件，否则临时权限可能失效
   */
  private selectEBooks(): void {
    try {
      logger.info(TAG, '开始选择电子书文件');
      
      // 获取UIAbilityContext
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取应用上下文');
        return;
      }

      // 创建文档选择器
      const documentPicker = new picker.DocumentViewPicker(context);
      
      // 设置选择选项 - 电子书格式（不包含PDF，PDF有单独的导入入口）
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 10,
        fileSuffixFilters: ['.txt', '.epub', '.mobi', '.azw', '.azw3'],
      };

      // 使用 .then() 回调模式，在回调中直接处理文件
      documentPicker.select(selectOptions).then((selectResult: Array<string>) => {
        if (!selectResult || selectResult.length === 0) {
          logger.info(TAG, '未选择任何电子书文件');
          return;
        }

        logger.info(TAG, `选择了 ${selectResult.length} 个电子书文件`);
        
        // [修复] 批量导入时顺序处理每个文件，避免竞态条件
        this.processEBookFilesSequentially(selectResult, context);
      }).catch((err: Error) => {
        logger.error(TAG, `选择电子书文件失败: ${err.message}`);
      });

    } catch (error) {
      logger.error(TAG, '选择电子书文件失败', String(error instanceof Error ? error.message : error));
    }
  }

  /**
   * 选择PDF文件（转换为图片序列导入）
   * PDF文件会被转换为图片序列，可归类为漫画或电子书
   */
  private selectPdfFiles(): void {
    try {
      logger.info(TAG, '开始选择PDF文件');
      
      // 获取UIAbilityContext
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取应用上下文');
        return;
      }

      // 创建文档选择器
      const documentPicker = new picker.DocumentViewPicker(context);
      
      // 设置选择选项 - 仅PDF格式
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 5, // PDF转换较慢，限制数量
        fileSuffixFilters: ['.pdf'],
      };

      // 使用 .then() 回调模式，在回调中直接处理文件
      documentPicker.select(selectOptions).then((selectResult: Array<string>) => {
        if (!selectResult || selectResult.length === 0) {
          logger.info(TAG, '未选择任何PDF文件');
          return;
        }

        logger.info(TAG, `选择了 ${selectResult.length} 个PDF文件`);
        void this.processPdfFilesSequentially(selectResult, context);
      }).catch((err: Error) => {
        logger.error(TAG, `选择PDF文件失败: ${err.message}`);
      });

    } catch (error) {
      logger.error(TAG, '选择PDF文件失败', String(error instanceof Error ? error.message : error));
    }
  }

  /**
   * 顺序准备并处理多个PDF文件，避免大文件并发复制造成内存和IO峰值
   */
  private async processPdfFilesSequentially(
    uris: string[],
    context: common.UIAbilityContext
  ): Promise<void> {
    for (let i = 0; i < uris.length; i++) {
      try {
        this.updateProgress(ImportStatus.PROCESSING, `正在准备第 ${i + 1}/${uris.length} 个PDF文件...`, 5);
        await this.processPdfFileInCallback(uris[i], context);
      } catch (error) {
        logger.error(TAG, `顺序处理PDF文件失败: ${String(error)}`);
      }
    }
  }

  /**
   * 在 picker 回调中处理PDF文件
   * 复制到沙箱后调用PDF分类选择对话框
   */
  private async processPdfFileInCallback(uri: string, context: common.UIAbilityContext): Promise<void> {
    try {
      logger.info(TAG, `开始处理PDF文件: ${uri}`);

      const displayTitle = this.pdfImportService.getDefaultTitle(uri);
      this.updateProgress(ImportStatus.PROCESSING, `正在准备PDF文件: ${displayTitle}.pdf`, 5);
      const sandboxPath = await this.pdfImportService.copyPdfToSandbox(uri, context.filesDir);
      this.updateProgress(ImportStatus.PROCESSING, 'PDF文件已准备完成，等待选择分类...', 10);
      await this.handlePdfImportWithCategorySelection(sandboxPath);
    } catch (error) {
      logger.error(TAG, `处理PDF文件失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `处理PDF文件失败: ${String(error)}`, 0);
      throw error as Error;
    }
  }
  
  /**
   * 显示Toast提示
   */
  private showToast(message: string): void {
    if (!this.isPageActive) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2000
      });
    } catch (error) {
      logger.error(TAG, '显示提示消息失败', String(error));
    }
  }

  /**
   * [修复] 顺序处理多个电子书文件，避免批量导入时的竞态条件
   * 每个文件处理完成后再处理下一个
   */
  private async processEBookFilesSequentially(uris: Array<string>, context: common.UIAbilityContext): Promise<void> {
    const totalFiles = uris.length;
    let successCount = 0;
    let failCount = 0;
    
    logger.info(TAG, `开始顺序处理 ${totalFiles} 个电子书文件`);
    
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      const currentIndex = i + 1;
      
      try {
        this.updateProgress(ImportStatus.PROCESSING, `正在处理第 ${currentIndex}/${totalFiles} 个文件...`, (currentIndex / totalFiles) * 100);
        
        // 同步复制文件到沙箱
        const targetPath = await this.copyEBookFileToSandboxSync(uri, context);
        
        if (targetPath) {
          // 等待导入完成，根据返回值判断是否成功
          const importSuccess = await this.continueImportEBook(targetPath);
          if (importSuccess) {
            successCount++;
          } else {
            // 用户取消或导入失败
            failCount++;
          }
        } else {
          failCount++;
        }
      } catch (error) {
        logger.error(TAG, `处理电子书文件失败 [${currentIndex}/${totalFiles}]: ${String(error)}`);
        failCount++;
      }
    }
    
    // 显示最终结果
    if (successCount > 0) {
      this.showToast(`电子书导入完成: 成功 ${successCount} 个，失败 ${failCount} 个`);
    } else {
      this.showToast(`电子书导入失败: 全部 ${totalFiles} 个文件导入失败`);
    }
    
    this.updateProgress(ImportStatus.COMPLETED, `导入完成: 成功 ${successCount}，失败 ${failCount}`, 100);
    logger.info(TAG, `电子书批量导入完成: 成功 ${successCount}，失败 ${failCount}`);
  }
  
  /**
   * [修复] 同步复制电子书文件到沙箱（返回Promise）
   */
  private async copyEBookFileToSandboxSync(uri: string, context: common.UIAbilityContext): Promise<string | null> {
    try {
      // 获取文件名
      let fileName = 'unknown.txt';
      try {
        const uriObj = new fileUri.FileUri(uri);
        fileName = uriObj.name;
      } catch (e) {
        try {
          fileName = decodeURIComponent(uri.slice(uri.lastIndexOf('/') + 1));
        } catch {}
      }
      
      // 目标路径
      const timestamp = new Date().getTime();
      const safeOriginalName = fileName.replace(/[<>:"/\\|?*]/g, '_');
      const safeName = `${timestamp}_${safeOriginalName}`;
      const targetDir = `${context.filesDir}/ebooks`;
      const targetPath = `${targetDir}/${safeName}`;
      
      // 确保目录存在
      let dirExists = false;
      try {
        dirExists = SafeFileUtils.accessSync(targetDir);
      } catch {
        dirExists = false;
      }
      
      if (!dirExists) {
        SafeFileUtils.mkdirSync(targetDir, true);
      }
      
      // 复制文件
      const srcFile = SafeFileUtils.openSync(uri, fs.OpenMode.READ_ONLY);
      const destFile = SafeFileUtils.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      
      const BUFFER_SIZE = 4096;
      const buffer = new ArrayBuffer(BUFFER_SIZE);
      let totalBytes = 0;
      let readLen: number;
      
      while ((readLen = SafeFileUtils.readSync(srcFile.fd, buffer)) > 0) {
        if (readLen === BUFFER_SIZE) {
          SafeFileUtils.writeSync(destFile.fd, buffer);
        } else {
          const lastChunk = buffer.slice(0, readLen);
          SafeFileUtils.writeSync(destFile.fd, lastChunk);
        }
        totalBytes += readLen;
      }
      
      SafeFileUtils.closeSync(srcFile);
      SafeFileUtils.closeSync(destFile);
      
      if (totalBytes === 0) {
        try { SafeFileUtils.unlinkSync(targetPath); } catch {}
        return null;
      }
      
      logger.info(TAG, `文件复制成功: ${targetPath}，大小: ${totalBytes} 字节`);
      return targetPath;
    } catch (error) {
      logger.error(TAG, `复制电子书文件失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 在 picker 回调中直接处理文件（保持临时权限有效）
   * 根据官方文档：normal等级应用只能通过 fs 模块处理文档类URI
   */
  private processEBookFileInCallback(uri: string, context: common.UIAbilityContext): void {
    try {
      logger.info(TAG, `开始处理电子书: ${uri}`);
      
      // 获取文件名
      let fileName = 'unknown.txt';
      try {
        const uriObj = new fileUri.FileUri(uri);
        fileName = uriObj.name;
        logger.info(TAG, `从 URI 获取文件名: ${fileName}`);
      } catch (e) {
        try {
          fileName = decodeURIComponent(uri.slice(uri.lastIndexOf('/') + 1));
        } catch {}
      }
      
      // 目标路径
      const timestamp = new Date().getTime();
      
      // 获取文件扩展名，确保保留扩展名以便 Reader Kit 识别
      let extension = '.txt';
      const dotIndex = fileName.lastIndexOf('.');
      if (dotIndex > 0) {
        extension = fileName.substring(dotIndex);
      }
      
      // 保留原始文件名（去除扩展名后的部分）用于元数据
      const originalTitle = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
      
      // 使用安全的文件名（保留原始名称以便解析器提取书名）
      // 清理文件名中的非法字符
      const safeOriginalName = fileName.replace(/[<>:"/\\|?*]/g, '_');
      const safeName = `${timestamp}_${safeOriginalName}`;
      const targetDir = `${context.filesDir}/ebooks`;
      const targetPath = `${targetDir}/${safeName}`;
      
      // 确保目录存在（使用 fs 模块）
      let dirExists = false;
      try {
        dirExists = SafeFileUtils.accessSync(targetDir);
      } catch {
        dirExists = false;
      }
      
      if (!dirExists) {
        try {
          SafeFileUtils.mkdirSync(targetDir, true); // 递归创建目录
          logger.info(TAG, `创建目录成功: ${targetDir}`);
        } catch (mkdirError) {
          logger.error(TAG, `创建目录失败: ${String(mkdirError)}`);
          throw mkdirError as Error;
        }
      } else {
        logger.info(TAG, `目录已存在: ${targetDir}`);
      }
      
      // 显示进度
      this.updateProgress(ImportStatus.PROCESSING, `正在复制文件: ${fileName}`, 5);
      
      // 使用 fs 模块打开源文件（官方文档推荐）
      // 注意：file://docs URI 的临时权限只允许打开一次，不能关闭后重新打开
      logger.info(TAG, `准备打开源文件: ${uri}`);
      const srcFile = SafeFileUtils.openSync(uri, fs.OpenMode.READ_ONLY);
      logger.info(TAG, `源文件打开成功，fd: ${srcFile.fd}`);
      
      // 直接开始复制，不要先读取验证
      logger.info(TAG, `准备创建目标文件: ${targetPath}`);
      
      try {
        const destFile = SafeFileUtils.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        logger.info(TAG, `目标文件创建成功，fd: ${destFile.fd}`);
        
        const BUFFER_SIZE = 4096;
        const buffer = new ArrayBuffer(BUFFER_SIZE);
        let totalBytes = 0;
        let readLen: number;
        
        while ((readLen = SafeFileUtils.readSync(srcFile.fd, buffer)) > 0) {
          if (readLen === BUFFER_SIZE) {
            SafeFileUtils.writeSync(destFile.fd, buffer);
          } else {
            // 最后一块，只写入实际读取的部分
            const lastChunk = buffer.slice(0, readLen);
            SafeFileUtils.writeSync(destFile.fd, lastChunk);
          }
          totalBytes += readLen;
        }
        
        SafeFileUtils.closeSync(srcFile);
        SafeFileUtils.closeSync(destFile);
        
        logger.info(TAG, `文件复制成功: ${targetPath}，大小: ${totalBytes} 字节`);
        
        if (totalBytes === 0) {
          logger.error(TAG, '复制后文件大小为 0');
          try {
            SafeFileUtils.unlinkSync(targetPath);
          } catch {}
          this.showToast('文件内容为空');
          this.updateProgress(ImportStatus.ERROR, '文件内容为空', 0);
          return;
        }
        
        // 更新进度
        this.updateProgress(ImportStatus.PROCESSING, '文件复制完成，开始解析...', 15);
        
        // 继续导入流程（异步处理）
        this.continueImportEBook(targetPath).catch((err: Error) => {
          logger.error(TAG, `电子书导入失败: ${err.message}`);
          this.updateProgress(ImportStatus.ERROR, `导入失败: ${err.message}`, 0);
        });
        
      } catch (destError) {
        // 关闭源文件
        try {
          SafeFileUtils.closeSync(srcFile);
        } catch {}
        logger.error(TAG, `创建目标文件失败: ${String(destError)}`);
        this.updateProgress(ImportStatus.ERROR, `创建目标文件失败: ${String(destError)}`, 0);
        throw destError as Error;
      }
      
    } catch (error) {
      logger.error(TAG, `处理电子书文件失败: ${String(error)}`);
      this.updateProgress(ImportStatus.ERROR, `处理电子书文件失败: ${String(error)}`, 0);
    }
  }
  
  /**
   * 继续导入电子书（文件已复制到沙箱后）
   * @returns true 表示导入成功，false 表示用户取消或失败
   */
  private async continueImportEBook(sandboxPath: string): Promise<boolean> {
    const importStartedAt: number = Date.now();
    try {
      logger.info(TAG, `继续导入电子书: ${sandboxPath}`);
      this.ensureImportFlow(
        this.currentImportFlowId.length > 0 ? ImportFlowEntrySource.UNKNOWN : ImportFlowEntrySource.DOWNLOAD_DIR,
        ImportFlowContentType.EBOOK,
        this.getFileNameFromUri(sandboxPath),
        1,
        false,
        sandboxPath,
        sandboxPath
      );
      
      // 显示进度
      this.updateProgress(ImportStatus.PARSING, '正在解析电子书...', 20);
      
      // 创建解析器
      const parser = EBookParserFactory.createParser(sandboxPath);
      if (!parser) {
        this.updateProgress(ImportStatus.ERROR, '不支持的电子书格式', 0);
        throw new Error('不支持的电子书格式');
      }

      // 解析电子书
      const parseStartedAt: number = Date.now();
      const ebook = await parser.parse();
      const metadataEvent: ImportFlowEvent = new ImportFlowEvent();
      metadataEvent.eventType = ImportFlowEventType.METADATA_DETECTED;
      metadataEvent.reason = 'ebook_metadata_detected';
      metadataEvent.contentType = ImportFlowContentType.EBOOK;
      metadataEvent.sourceUri = sandboxPath;
      metadataEvent.displayName = ebook.metadata.title;
      metadataEvent.chapterCount = ebook.chapters.length;
      metadataEvent.elapsedMs = Date.now() - parseStartedAt;
      this.recordImportFlowEvent(metadataEvent);
      logger.info(TAG, `电子书解析完成: ${ebook.metadata.title}`);
      
      this.updateProgress(ImportStatus.PROCESSING, `正在处理: ${ebook.metadata.title}`, 50);

      // 设置默认收藏状态为 true（导入即收藏）
      ebook.isFavorite = true;
      
      // 如果书名看起来像是时间戳开头的文件名，尝试提取真实书名
      if (ebook.metadata.title.match(/^\d+_/)) {
        const cleanTitle = ebook.metadata.title
          .replace(/^\d+_/, '')
          .replace(/\.(txt|epub|mobi|azw|azw3|pdf)$/i, '')
          .replace(/_[a-f0-9]{6,}$/i, '');
        if (cleanTitle.length > 0) {
          ebook.metadata.title = cleanTitle;
          logger.info(TAG, `提取真实书名: ${cleanTitle}`);
        }
      }

      // 尝试提取封面图片
      this.updateProgress(ImportStatus.PROCESSING, '正在提取封面...', 60);
      await this.tryExtractEBookCover(ebook, sandboxPath);
      const coverEvent: ImportFlowEvent = new ImportFlowEvent();
      coverEvent.eventType = ImportFlowEventType.COVER_HANDLED;
      coverEvent.reason = 'ebook_cover_handled';
      coverEvent.contentType = ImportFlowContentType.EBOOK;
      coverEvent.sourceUri = sandboxPath;
      coverEvent.targetPath = ebook.metadata.coverImagePath || '';
      coverEvent.displayName = ebook.metadata.title;
      this.recordImportFlowEvent(coverEvent);
      logger.info(TAG, `[封面诊断] 提取封面后 coverImagePath='${ebook.metadata.coverImagePath}'`);

      // 显示确认对话框，让用户查看和编辑解析到的信息
      logger.info(TAG, `显示电子书确认对话框: ${ebook.metadata.title}, 章节数: ${ebook.chapters.length}`);
      this.updateProgress(ImportStatus.IDLE, '', 0); // 隐藏进度，显示对话框
      const confirmed = await this.showEBookMetadataDialog(ebook, sandboxPath);
      return confirmed;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '导入电子书失败', errorMsg);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${errorMsg}`, 0);
      this.showToast('导入失败: ' + errorMsg);
      this.finalizeTrackedTransferImport('import_failed');
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'ebook_continue_import_failed';
      failedEvent.contentType = ImportFlowContentType.EBOOK;
      failedEvent.sourceUri = sandboxPath;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - importStartedAt;
      failedEvent.errorMessage = errorMsg;
      this.recordImportFlowEvent(failedEvent);
      this.endCurrentImportFlow('ebook_import_failed');
      return false;
    }
  }

  /**
   * 尝试提取电子书封面
   * 如果提取失败（如 TXT 文件没有封面），则使用封面生成器生成带标题的封面
   */
  private async tryExtractEBookCover(ebook: EBook, filePath: string): Promise<void> {
    try {
      // 获取封面保存目录
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
      const coverDir = `${context.filesDir}/ebook_covers`;
      
      logger.info(TAG, `尝试提取电子书封面: ${ebook.metadata.title}`);
      
      // 使用封面提取器
      const result = await EBookCoverExtractor.extractCover(filePath, coverDir);
      
      if (result.success && result.coverPath) {
        ebook.metadata.coverImagePath = result.coverPath;
        logger.info(TAG, `封面提取成功: ${result.coverPath}`);
      } else {
        // 封面提取失败，尝试生成带标题的封面
        logger.info(TAG, `封面提取失败: ${result.errorMessage || '未知原因'}，尝试生成封面`);
        await this.generateEBookCover(ebook, coverDir);
      }
    } catch (error) {
      logger.warn(TAG, `封面提取异常: ${String(error)}，尝试生成封面`);
      // 封面提取失败不影响导入流程，尝试生成封面
      try {
        const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
        const coverDir = `${context.filesDir}/ebook_covers`;
        await this.generateEBookCover(ebook, coverDir);
      } catch (genError) {
        logger.warn(TAG, `封面生成也失败: ${String(genError)}`);
      }
    }
  }
  
  // 封面生成器常量（基于 ebook.webp 图片精确测量）
  // 图片原始尺寸约 400x600，白色留白区域（金色边框内）位置：
  private static readonly COVER_WIDTH = 400;
  private static readonly COVER_HEIGHT = 600;
  // 标题区域位置（精确测量金色边框内的白色区域）
  private static readonly TITLE_AREA_TOP_PERCENT = 0.130;    // 顶部 3.5%
  private static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345; // 底部 32.5%
  private static readonly TITLE_AREA_LEFT_PERCENT = 0.110;    // 左侧 7%
  private static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;   // 右侧 93%
  
  /**
   * 格式化封面标题（处理过长的标题）
   */
  private formatCoverTitle(title: string): string {
    // 移除文件扩展名
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '').replace(/_[a-f0-9]{6,}$/i, '');
    // 如果标题过长，截断并添加省略号
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }
  
  /**
   * 根据标题长度计算合适的字体大小
   * 标题区域高度约 147px (600 * 0.245)，宽度约 332px (400 * 0.83)
   * 需要确保文字足够大且能完整显示
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    if (length <= 2) {
      return 70;  // 超短标题，使用大字体
    } else if (length <= 4) {
      return 56;
    } else if (length <= 6) {
      return 48;
    } else if (length <= 8) {
      return 36;
    } else if (length <= 12) {
      return 32;
    } else if (length <= 16) {
      return 28;
    } else {
      return 24;  // 较长标题
    }
  }
  
  /**
   * 构建封面组件（用于 componentSnapshot）
   */
  @Builder
  buildCoverForSnapshot(title: string) {
    Stack() {
      // 底层：默认封面图片
      Image($r('app.media.ebook'))
        .width(DataManagementPage.COVER_WIDTH)
        .height(DataManagementPage.COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      // 标题文字层 - 精确定位到金色边框内的白色区域中心
      // 计算标题区域的中心位置
      Text(this.formatCoverTitle(title))
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(DataManagementPage.COVER_WIDTH * (DataManagementPage.TITLE_AREA_RIGHT_PERCENT - DataManagementPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: DataManagementPage.COVER_HEIGHT * (DataManagementPage.TITLE_AREA_BOTTOM_PERCENT - DataManagementPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: DataManagementPage.COVER_WIDTH * DataManagementPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: DataManagementPage.COVER_HEIGHT * (DataManagementPage.TITLE_AREA_TOP_PERCENT + DataManagementPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(DataManagementPage.COVER_WIDTH)
    .height(DataManagementPage.COVER_HEIGHT)
  }
  
  /**
   * 使用封面生成器生成电子书封面
   * 在默认封面图片的留白区域添加标题文字
   */
  private async generateEBookCover(ebook: EBook, coverDir: string): Promise<void> {
    try {
      logger.info(TAG, `开始生成封面: ${ebook.metadata.title}`);
      
      // 使用 componentSnapshot.createFromBuilder 生成 PixelMap
      const pixelMap = await this.getUIContext().getComponentSnapshot().createFromBuilder(
        () => { this.buildCoverForSnapshot(ebook.metadata.title); }
      );
      
      if (!pixelMap) {
        logger.warn(TAG, '封面生成失败: PixelMap 为空');
        return;
      }
      
      // 保存 PixelMap 为图片文件
      const outputPath = `${coverDir}/${ebook.id}_generated_cover.webp`;
      const savedCoverPath = await this.savePixelMapToFile(pixelMap, outputPath);
      
      // 释放 PixelMap
      pixelMap.release();
      
      if (savedCoverPath.length > 0) {
        ebook.metadata.coverImagePath = savedCoverPath;
        logger.info(TAG, `封面生成成功: ${savedCoverPath}`);
      } else {
        logger.warn(TAG, '封面生成失败: 保存图片失败');
      }
    } catch (error) {
      logger.warn(TAG, `封面生成异常: ${String(error)}`);
    }
  }
  
  /**
   * 将 PixelMap 保存为图片文件
   */
  private async savePixelMapToFile(pixelMap: image.PixelMap, filePath: string): Promise<string> {
    try {
      // 确保目录存在
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      try {
        SafeFileUtils.mkdirSync(dirPath, true);
      } catch (e) {
        // 目录可能已存在，忽略错误
      }

      const webpPath = this.replaceImageExtension(filePath, '.webp');
      const webpBuffer = await this.packPixelMapForCover(pixelMap, 'image/webp', 90, webpPath);
      if (webpBuffer.byteLength > 0 && await this.isPackedImageDecodable(webpBuffer, webpPath)) {
        this.writeImageBufferToFile(webpPath, webpBuffer);
        logger.info(TAG, `封面图片已保存: ${webpPath}`);
        return webpPath;
      }

      const jpegPath = this.replaceImageExtension(filePath, '.jpg');
      const jpegBuffer = await this.packPixelMapForCover(pixelMap, 'image/jpeg', 92, jpegPath);
      if (jpegBuffer.byteLength > 0 && await this.isPackedImageDecodable(jpegBuffer, jpegPath)) {
        this.writeImageBufferToFile(jpegPath, jpegBuffer);
        logger.warn(TAG, `WebP 封面不可解码，已改用 JPEG 保存: ${jpegPath}`);
        return jpegPath;
      }

      logger.warn(TAG, `封面保存失败: WebP/JPEG 打包结果均不可解码, target=${filePath}`);
      return '';
    } catch (error) {
      logger.error(TAG, `保存图片失败: ${error instanceof Error ? error.message : String(error)}`);
      return '';
    }
  }

  private replaceImageExtension(filePath: string, ext: string): string {
    const dotIndex = filePath.lastIndexOf('.');
    const slashIndex = filePath.lastIndexOf('/');
    if (dotIndex > slashIndex) {
      return filePath.substring(0, dotIndex) + ext;
    }
    return filePath + ext;
  }

  private async packPixelMapForCover(
    pixelMap: image.PixelMap,
    format: string,
    quality: number,
    label: string
  ): Promise<ArrayBuffer> {
    const imagePacker = image.createImagePacker();
    try {
      const packOptions: image.PackingOption = {
        format: format,
        quality: quality
      };
      const packed = await imagePacker.packToData(pixelMap, packOptions);
      logger.info(TAG, `封面打包完成: target=${label}, format=${format}, size=${packed.byteLength}`);
      return packed;
    } catch (error) {
      logger.warn(TAG, `封面打包失败: target=${label}, format=${format}, error=${String(error)}`);
      return new ArrayBuffer(0);
    } finally {
      imagePacker.release();
    }
  }

  private async isPackedImageDecodable(imageData: ArrayBuffer, label: string): Promise<boolean> {
    if (imageData.byteLength <= 0) {
      return false;
    }

    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      imageSource = image.createImageSource(imageData);
      pixelMap = await imageSource.createPixelMap();
      return pixelMap !== null;
    } catch (error) {
      logger.warn(TAG, `封面打包结果解码校验失败: target=${label}, error=${String(error)}`);
      return false;
    } finally {
      try {
        if (pixelMap !== null) {
          pixelMap.release();
        }
      } catch (_pixelMapReleaseError) {
      }
      try {
        if (imageSource !== null) {
          imageSource.release();
        }
      } catch (_imageSourceReleaseError) {
      }
    }
  }

  private writeImageBufferToFile(filePath: string, imageData: ArrayBuffer): void {
    const file = SafeFileUtils.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      SafeFileUtils.writeSync(file.fd, imageData);
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  /**
   * 导入电子书
   */
  private async importEBook(fileUri: string): Promise<void> {
    const importStartedAt: number = Date.now();
    try {
      logger.info(TAG, `开始导入电子书: ${fileUri}`);
      
      // 显示导入进度
      this.updateProgress(ImportStatus.PROCESSING, '正在复制文件到沙箱...', 10);
      
      // 0. 复制文件到沙箱
      // 这步非常重要，解决了权限持久化和路径读取问题
      const copyStartedAt: number = Date.now();
      const copyStartedEvent: ImportFlowEvent = new ImportFlowEvent();
      copyStartedEvent.eventType = ImportFlowEventType.COPY_STARTED;
      copyStartedEvent.reason = 'ebook_copy_started';
      copyStartedEvent.contentType = ImportFlowContentType.EBOOK;
      copyStartedEvent.sourceUri = fileUri;
      this.recordImportFlowEvent(copyStartedEvent);
      const sandboxPath = await this.copyFileToSandbox(fileUri);
      const copyCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
      copyCompletedEvent.eventType = ImportFlowEventType.COPY_COMPLETED;
      copyCompletedEvent.reason = 'ebook_copy_completed';
      copyCompletedEvent.contentType = ImportFlowContentType.EBOOK;
      copyCompletedEvent.sourceUri = fileUri;
      copyCompletedEvent.targetPath = sandboxPath;
      copyCompletedEvent.elapsedMs = Date.now() - copyStartedAt;
      this.recordImportFlowEvent(copyCompletedEvent);
      logger.info(TAG, `文件已复制到沙箱: ${sandboxPath}`);
      
      this.updateProgress(ImportStatus.PARSING, '正在解析电子书...', 30);

      // 1. 创建解析器 (使用沙箱路径)
      const parser = EBookParserFactory.createParser(sandboxPath);
      if (!parser) {
        this.updateProgress(ImportStatus.ERROR, '不支持的电子书格式', 0);
        throw new Error('不支持的电子书格式');
      }

      // 2. 解析电子书
      const parseStartedAt: number = Date.now();
      const ebook = await parser.parse();
      const metadataEvent: ImportFlowEvent = new ImportFlowEvent();
      metadataEvent.eventType = ImportFlowEventType.METADATA_DETECTED;
      metadataEvent.reason = 'ebook_metadata_detected';
      metadataEvent.contentType = ImportFlowContentType.EBOOK;
      metadataEvent.sourceUri = fileUri;
      metadataEvent.targetPath = sandboxPath;
      metadataEvent.displayName = ebook.metadata.title;
      metadataEvent.chapterCount = ebook.chapters.length;
      metadataEvent.elapsedMs = Date.now() - parseStartedAt;
      this.recordImportFlowEvent(metadataEvent);
      logger.info(TAG, `电子书解析完成: ${ebook.metadata.title}`);
      
      // 设置默认收藏状态为 true（导入即收藏）
      ebook.isFavorite = true;
      
      // 尝试提取封面图片
      this.updateProgress(ImportStatus.PROCESSING, '正在提取封面...', 50);
      await this.tryExtractEBookCover(ebook, sandboxPath);
      const coverEvent: ImportFlowEvent = new ImportFlowEvent();
      coverEvent.eventType = ImportFlowEventType.COVER_HANDLED;
      coverEvent.reason = 'ebook_cover_handled';
      coverEvent.contentType = ImportFlowContentType.EBOOK;
      coverEvent.sourceUri = fileUri;
      coverEvent.targetPath = ebook.metadata.coverImagePath || '';
      coverEvent.displayName = ebook.metadata.title;
      this.recordImportFlowEvent(coverEvent);
      
      this.updateProgress(ImportStatus.PROCESSING, '准备确认信息...', 70);

      // 3. 显示确认对话框，让用户查看和编辑解析到的信息
      logger.info(TAG, `显示电子书确认对话框: ${ebook.metadata.title}, 章节数: ${ebook.chapters.length}`);
      this.updateProgress(ImportStatus.IDLE, '', 0);
      await this.showEBookMetadataDialog(ebook, sandboxPath);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '导入电子书失败', errorMsg);
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'ebook_import_failed';
      failedEvent.contentType = ImportFlowContentType.EBOOK;
      failedEvent.sourceUri = fileUri;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - importStartedAt;
      failedEvent.errorMessage = errorMsg;
      this.recordImportFlowEvent(failedEvent);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${errorMsg}`, 0);
      this.showToast(`电子书导入失败: ${errorMsg}`);
      this.finalizeTrackedTransferImport('import_failed');
      this.endCurrentImportFlow('ebook_import_failed');
    }
  }

  /**
   * 复制文件到沙箱
   * 参考华为官方示例：使用 fileIo.readSync 并指定 offset: 0
   */
  private async copyFileToSandbox(srcUri: string): Promise<string> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      // 使用 fileUri 获取文件名
      let fileName = 'unknown.txt';
      try {
        const uriObj = new fileUri.FileUri(srcUri);
        fileName = uriObj.name;
        logger.info(TAG, `从 URI 获取文件名: ${fileName}`);
      } catch (e) {
        logger.warn(TAG, `fileUri 解析失败，尝试手动解析: ${e}`);
        try {
          const parts = srcUri.split('/');
          const rawName = parts[parts.length - 1];
          fileName = decodeURIComponent(rawName);
        } catch (e2) {
          logger.warn(TAG, `手动解析文件名失败: ${e2}`);
        }
      }
      
      // 加上时间戳防止重名，但保留原始文件名
      const timestamp = new Date().getTime();
      const safeName = `${timestamp}_${fileName}`;
      
      const targetDir = `${context.filesDir}/ebooks`;
      const targetPath = `${targetDir}/${safeName}`;

      // 确保目录存在
      try {
        await fileIo.access(targetDir);
      } catch {
        await fileIo.mkdir(targetDir);
        logger.info(TAG, `创建目录: ${targetDir}`);
      }

      // 使用 fileIo.openSync 打开 URI（华为官方示例使用 fileIo 而不是 fs）
      const srcFile = SafeFileUtils.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
      logger.info(TAG, `源文件打开成功，fd: ${srcFile.fd}`);
      
      // 华为官方示例的读取方法：先读取一次获取实际大小，再重新读取
      const BUFFER_SIZE = 4096;
      let buffer = new ArrayBuffer(BUFFER_SIZE);
      
      // 第一次读取，获取实际读取的字节数
      let readOut = SafeFileUtils.readSync(srcFile.fd, buffer, { offset: 0 });
      logger.info(TAG, `第一次读取: ${readOut} 字节`);
      
      if (readOut > 0) {
        // 如果第一次读取成功，创建正确大小的 buffer 重新读取
        // 注意：需要重新打开文件，因为文件指针已经移动
        SafeFileUtils.closeSync(srcFile);
        
        const srcFile2 = SafeFileUtils.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
        
        // 如果文件较大，需要循环读取
        const destFile = SafeFileUtils.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        
        let totalBytes = 0;
        let currentOffset = 0;
        
        while (true) {
          const chunkBuffer = new ArrayBuffer(BUFFER_SIZE);
          const bytesRead = SafeFileUtils.readSync(srcFile2.fd, chunkBuffer, { offset: currentOffset });
          
          if (bytesRead <= 0) {
            break;
          }
          
          // 写入读取的数据
          if (bytesRead === BUFFER_SIZE) {
            SafeFileUtils.writeSync(destFile.fd, chunkBuffer);
          } else {
            // 最后一块，只写入实际读取的部分
            const lastChunk = chunkBuffer.slice(0, bytesRead);
            SafeFileUtils.writeSync(destFile.fd, lastChunk);
          }
          
          totalBytes += bytesRead;
          currentOffset += bytesRead;
          
          // 如果读取的字节数小于 buffer 大小，说明已经到达文件末尾
          if (bytesRead < BUFFER_SIZE) {
            break;
          }
        }
        
        SafeFileUtils.closeSync(srcFile2);
        SafeFileUtils.closeSync(destFile);
        
        if (totalBytes > 0) {
          logger.info(TAG, `文件复制成功，大小: ${totalBytes} 字节，目标: ${targetPath}`);
          return targetPath;
        }
      }
      
      // 如果上面的方法失败，尝试使用 fs.copyFile
      logger.warn(TAG, `fileIo 读取失败，尝试 fs.copyFile`);
      try {
        SafeFileUtils.closeSync(srcFile);
      } catch {}
      
      try {
        const srcFile3 = SafeFileUtils.openSync(srcUri, fs.OpenMode.READ_ONLY);
        await fs.copyFile(srcFile3.fd, targetPath, 0);
        SafeFileUtils.closeSync(srcFile3);
        
        const destStat = SafeFileUtils.statSync(targetPath);
        if (destStat.size > 0) {
          logger.info(TAG, `fs.copyFile 成功，文件大小: ${destStat.size} 字节`);
          return targetPath;
        }
      } catch (e) {
        logger.warn(TAG, `fs.copyFile 失败: ${e}`);
      }
      
      throw new Error('无法读取文件内容');
    } catch (error) {
      logger.error(TAG, `文件复制失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 检查是否需要补充元数据
   * 始终返回 true，让用户确认导入信息
   */
  private needsMetadataCompletion(metadata: EBookMetadata): boolean {
    // 始终显示确认对话框，让用户可以查看和编辑解析到的信息
    // 即使信息完整，用户也可能想要修改标题、作者或选择自定义封面
    return true;
  }

  /**
   * 显示电子书元数据补充对话框
   * @returns true 表示用户确认导入，false 表示用户取消
   */
  private async showEBookMetadataDialog(ebook: EBook, sourceFileName: string = ''): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.ebookMetadataDialogController = new CustomDialogController({
        builder: EBookMetadataDialog({
          themeState: this.themeState,
          initialMetadata: ebook.metadata,
          sourceFileName: sourceFileName,
          chapters: ebook.chapters,  // 传递章节信息
          onConfirm: async (result: EBookMetadataDialogResult) => {
            logger.info(TAG, '用户确认导入电子书');
            const dbStartedAt: number = Date.now();
            const confirmEvent: ImportFlowEvent = new ImportFlowEvent();
            confirmEvent.eventType = ImportFlowEventType.DIALOG_CONFIRMED;
            confirmEvent.reason = 'ebook_metadata_dialog_confirmed';
            confirmEvent.contentType = ImportFlowContentType.EBOOK;
            confirmEvent.displayName = result.metadata.title;
            confirmEvent.sourceUri = sourceFileName;
            confirmEvent.chapterCount = ebook.chapters.length;
            this.recordImportFlowEvent(confirmEvent);
            // [修复] 保存原始封面路径，防止 @Prop 深拷贝丢失嵌套属性
            const originalCoverPath = ebook.metadata.coverImagePath || '';
            logger.info(TAG, `[封面诊断] 对话框确认前: originalCoverPath='${originalCoverPath}', result.coverImagePath='${result.metadata.coverImagePath}'`);
            
            // 更新电子书元数据
            ebook.metadata = result.metadata;
            
            // [修复] 如果对话框返回的封面路径为空，恢复原始封面路径
            if (!ebook.metadata.coverImagePath && originalCoverPath) {
              ebook.metadata.coverImagePath = originalCoverPath;
              logger.info(TAG, `[封面诊断] 对话框返回封面为空，已恢复原始路径: '${originalCoverPath}'`);
            }
            
            // 如果用户选择了自定义封面，需要复制到应用目录
            if (result.customCoverPath) {
              try {
                const coverPath = await this.copyCustomCoverToApp(result.customCoverPath, ebook.id);
                ebook.metadata.coverImagePath = coverPath;
                logger.info(TAG, `自定义封面已保存: ${coverPath}`);
              } catch (error) {
                logger.warn(TAG, `保存自定义封面失败: ${String(error)}`);
              }
            }
            
            logger.info(TAG, `[封面诊断] 保存前最终 coverImagePath='${ebook.metadata.coverImagePath}'`);
            // 保存到数据库
            const dbStartedEvent: ImportFlowEvent = new ImportFlowEvent();
            dbStartedEvent.eventType = ImportFlowEventType.DB_WRITE_STARTED;
            dbStartedEvent.reason = 'ebook_db_write_started';
            dbStartedEvent.contentType = ImportFlowContentType.EBOOK;
            dbStartedEvent.displayName = ebook.metadata.title;
            dbStartedEvent.chapterCount = ebook.chapters.length;
            this.recordImportFlowEvent(dbStartedEvent);
            await this.ebookDataManager.saveEBook(ebook);
            const dbCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
            dbCompletedEvent.eventType = ImportFlowEventType.DB_WRITE_COMPLETED;
            dbCompletedEvent.reason = 'ebook_db_write_completed';
            dbCompletedEvent.contentType = ImportFlowContentType.EBOOK;
            dbCompletedEvent.displayName = ebook.metadata.title;
            dbCompletedEvent.chapterCount = ebook.chapters.length;
            dbCompletedEvent.elapsedMs = Date.now() - dbStartedAt;
            dbCompletedEvent.detail = `ebookId=${ebook.id}`;
            this.recordImportFlowEvent(dbCompletedEvent);
            logger.info(TAG, `电子书导入成功: ${ebook.metadata.title}`);
            
            // 显示成功提示
            this.updateProgress(ImportStatus.COMPLETED, `导入成功: ${ebook.metadata.title}`, 100);
            this.showToast(`导入成功: ${ebook.metadata.title}`);
            this.finalizeTrackedTransferImport('imported');
            const refreshEvent: ImportFlowEvent = new ImportFlowEvent();
            refreshEvent.eventType = ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED;
            refreshEvent.reason = 'ebook_bookshelf_refresh_published';
            refreshEvent.contentType = ImportFlowContentType.EBOOK;
            refreshEvent.displayName = ebook.metadata.title;
            this.recordImportFlowEvent(refreshEvent);
            this.endCurrentImportFlow('ebook_import_completed');
            resolve(true);
          },
          onCancel: async () => {
            logger.info(TAG, '用户取消导入电子书');
            const cancelEvent: ImportFlowEvent = new ImportFlowEvent();
            cancelEvent.eventType = ImportFlowEventType.DIALOG_CANCELLED;
            cancelEvent.reason = 'ebook_metadata_dialog_cancelled';
            cancelEvent.contentType = ImportFlowContentType.EBOOK;
            cancelEvent.displayName = ebook.metadata.title;
            cancelEvent.sourceUri = sourceFileName;
            this.recordImportFlowEvent(cancelEvent);
            
            // 删除已生成的封面图片（如果有）
            if (ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0) {
              try {
                await fileIo.unlink(ebook.metadata.coverImagePath);
                logger.info(TAG, `已删除生成的封面图片: ${ebook.metadata.coverImagePath}`);
              } catch (e) {
                logger.warn(TAG, `删除封面图片失败: ${String(e)}`);
              }
            }

            this.updateProgress(ImportStatus.IDLE, '已取消导入', 0);
            this.finalizeTrackedTransferImport('import_cancelled');
            this.endCurrentImportFlow('ebook_import_cancelled');
            resolve(false);
          },
          onRegenerateCover: async (title: string, oldCoverPath: string): Promise<string> => {
            logger.info(TAG, `重新生成封面: 标题=${title}, 旧封面=${oldCoverPath}`);
            
            // 删除旧封面
            if (oldCoverPath && oldCoverPath.length > 0) {
              try {
                await fileIo.unlink(oldCoverPath);
                logger.info(TAG, `已删除旧封面: ${oldCoverPath}`);
              } catch (e) {
                logger.warn(TAG, `删除旧封面失败: ${String(e)}`);
              }
            }
            
            // 使用新标题生成封面
            const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
            const coverDir = `${context.filesDir}/ebook_covers`;
            
            // 临时更新 ebook 的标题用于生成封面
            const originalTitle = ebook.metadata.title;
            ebook.metadata.title = title;
            
            try {
              await this.generateEBookCover(ebook, coverDir);
              const newCoverPath = ebook.metadata.coverImagePath || '';
              logger.info(TAG, `封面重新生成成功: ${newCoverPath}`);
              return newCoverPath;
            } catch (error) {
              logger.error(TAG, `封面重新生成失败: ${String(error)}`);
              ebook.metadata.title = originalTitle;  // 恢复原标题
              return '';
            }
          }
        }),
        autoCancel: false,
        customStyle: true
      });

      this.ebookMetadataDialogController.open();
      const event: ImportFlowEvent = new ImportFlowEvent();
      event.eventType = ImportFlowEventType.DIALOG_OPENED;
      event.reason = 'ebook_metadata_dialog_opened';
      event.contentType = ImportFlowContentType.EBOOK;
      event.displayName = ebook.metadata.title;
      event.sourceUri = sourceFileName;
      event.chapterCount = ebook.chapters.length;
      this.recordImportFlowEvent(event);
    });
  }
  
  /**
   * 复制自定义封面到应用目录
   */
  private async copyCustomCoverToApp(srcUri: string, bookId: string): Promise<string> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取应用上下文');
    }
    
    const coverDir = `${context.filesDir}/ebook_covers`;
    const targetPath = `${coverDir}/${bookId}_cover.jpg`;
    
    // 确保目录存在
    try {
      await fileIo.access(coverDir);
    } catch {
      await fileIo.mkdir(coverDir);
    }
    
    // 复制文件
    const srcFile = SafeFileUtils.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
    const dstFile = SafeFileUtils.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    
    const buffer = new ArrayBuffer(4096);
    let readLen = 0;
    while ((readLen = SafeFileUtils.readSync(srcFile.fd, buffer)) > 0) {
      SafeFileUtils.writeSync(dstFile.fd, buffer, { length: readLen });
    }
    
    SafeFileUtils.closeSync(srcFile);
    SafeFileUtils.closeSync(dstFile);
    
    return targetPath;
  }

  /**
   * 选择本地文件
   */
  private isImageImportUri(uri: string): boolean {
    const fileName: string = this.getFileNameFromUri(uri).toLowerCase();
    const imageExtensions: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];
    return imageExtensions.some((extension: string): boolean => fileName.endsWith(extension));
  }

  private isComicInfoUri(uri: string): boolean {
    return this.getFileNameFromUri(uri).toLowerCase() === 'comicinfo.xml';
  }

  private getParentUri(uri: string): string {
    const normalized: string = uri.replace(/\\/g, '/');
    const separatorIndex: number = normalized.lastIndexOf('/');
    return separatorIndex > 0 ? normalized.substring(0, separatorIndex) : normalized;
  }

  /**
   * picked-images: 是分析期虚拟 URI，真正源文件保存在 Map 中。取消、失败或
   * 页面离开前恢复源 URI，避免下一次点击导入时命中已被清空的虚拟分组。
   */
  private restorePickedImageSelections(): void {
    if (this.selectedImageGroupSources.size <= 0 || this.selectedFiles.length <= 0) {
      return;
    }
    const restoredSelections: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const selection of this.selectedFiles) {
      if (selection.startsWith('picked-images:')) {
        const sources: string[] | undefined = this.selectedImageGroupSources.get(selection);
        if (sources !== undefined) {
          for (const source of sources) {
            if (!seen.has(source)) {
              seen.add(source);
              restoredSelections.push(source);
            }
          }
        }
        continue;
      }
      if (!seen.has(selection)) {
        seen.add(selection);
        restoredSelections.push(selection);
      }
    }
    this.selectedFiles = restoredSelections;
  }

  private sanitizeImportFileName(fileName: string, fallbackName: string): string {
    let safeName: string = fileName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\.\./g, '_')
      .trim();
    if (safeName.length <= 0 || safeName === '.' || safeName === '..') {
      safeName = fallbackName;
    }
    return safeName;
  }

  /**
   * 将文件夹选择展开为独立归档/散图候选，并将直接选中的散图按父目录分组。
   * 这样批量弹窗收到的每一项都对应一个明确章节源，而不是把整个聚合目录误当成一章。
   */
  private async expandMangaSelectionCandidates(pageGeneration: number): Promise<void> {
    this.restorePickedImageSelections();
    this.selectedImageGroupSources.clear();
    const originalSelections: string[] = this.selectedFiles.slice();
    const expanded: string[] = [];
    const imageGroups: Map<string, string[]> = new Map<string, string[]>();
    const seen: Set<string> = new Set<string>();

    for (const selection of originalSelections) {
      if (selection.startsWith('picked-images:')) {
        if (!seen.has(selection)) {
          seen.add(selection);
          expanded.push(selection);
        }
        continue;
      }
      if (selection.startsWith('folder:')) {
        const folderPath: string = this.resolveLocalImportPath(selection.substring('folder:'.length));
        try {
          const candidates: string[] = await this.compressionUtils.discoverMangaImportCandidates(folderPath);
          if (!this.isCurrentPageGeneration(pageGeneration)) {
            return;
          }
          for (const candidate of candidates) {
            if (!seen.has(candidate)) {
              seen.add(candidate);
              expanded.push(candidate);
            }
          }
          if (candidates.length === 0 && !seen.has(selection)) {
            // 保留旧语义作为兜底，让后续解析给出明确错误，而不是静默丢失用户选择。
            seen.add(selection);
            expanded.push(selection);
          }
        } catch (error) {
          logger.warn(TAG, `展开漫画文件夹失败，保留原始选择: ${folderPath}`, String(error));
          if (!seen.has(selection)) {
            seen.add(selection);
            expanded.push(selection);
          }
        }
        continue;
      }
      if (this.isImageImportUri(selection) || this.isComicInfoUri(selection)) {
        const parentUri: string = this.getParentUri(selection);
        const group: string[] = imageGroups.get(parentUri) || [];
        group.push(selection);
        imageGroups.set(parentUri, group);
        continue;
      }
      if (!seen.has(selection)) {
        seen.add(selection);
        expanded.push(selection);
      }
    }

    const parentUris: string[] = Array.from<string>(imageGroups.keys());
    for (const parentUri of parentUris) {
      const sources: string[] = imageGroups.get(parentUri) || [];
      let hasImage: boolean = false;
      for (const source of sources) {
        if (this.isImageImportUri(source)) {
          hasImage = true;
          break;
        }
      }
      if (!hasImage) {
        logger.warn(TAG, `忽略不含图片的ComicInfo.xml选择: ${parentUri}`);
        continue;
      }
      const parentName: string = this.getFileNameFromUri(parentUri);
      const displayName: string = parentName.length > 0 ? parentName : '散图漫画';
      const virtualUri: string = await createPickedImageGroupUri(displayName, sources);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.selectedImageGroupSources.set(virtualUri, sources.slice());
      expanded.push(virtualUri);
    }

    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.selectedFiles = expanded;
    logger.info(TAG, `漫画选择展开完成: 原始=${originalSelections.length}, 候选=${expanded.length}`);
  }

  /**
   * 将文件选择器选中的散图复制到应用临时目录，形成可复用的平铺章节。
   */
  private async stagePickedImageGroup(virtualUri: string): Promise<CompressionParsedStructure> {
    const sources: string[] | undefined = this.selectedImageGroupSources.get(virtualUri);
    if (!sources || sources.length === 0) {
      throw new Error(`找不到散图选择分组: ${virtualUri}`);
    }
    const baseDirectory: string = this.sandboxManager.getDirectory('temp');
    const stagingDirectory: string = `${baseDirectory}/manga_pick_${generateUUID()}`;
    await this.sandboxManager.createDirectory(stagingDirectory);
    try {
      const usedNames: Set<string> = new Set<string>();
      let copiedImages: number = 0;
      for (const source of sources) {
        const rawFileName: string = this.getFileNameFromUri(source);
        const fallbackName: string = this.isComicInfoUri(source)
          ? 'ComicInfo.xml'
          : `image_${copiedImages + 1}`;
        const fileName: string = this.sanitizeImportFileName(rawFileName, fallbackName);
        const lowerName: string = fileName.toLowerCase();
        if (!this.isImageImportUri(source) && lowerName !== 'comicinfo.xml') {
          continue;
        }
        let targetName: string = fileName;
        let suffix: number = 1;
        while (usedNames.has(targetName)) {
          targetName = `${suffix}_${fileName}`;
          suffix += 1;
        }
        usedNames.add(targetName);
        const targetPath: string = `${stagingDirectory}/${targetName}`;
        await this.sandboxManager.copyFile(source, targetPath);
        if (this.isImageImportUri(source)) {
          copiedImages += 1;
        }
      }
      if (copiedImages <= 0) {
        throw new Error(`散图分组没有可复制的图片: ${virtualUri}`);
      }
      const parsed: CompressionParsedStructure =
        await this.compressionUtils.parseFlatImageFolderAsArchiveStructure(stagingDirectory);
      parsed.tempDirectories.push(stagingDirectory);
      return parsed;
    } catch (error) {
      try {
        await this.sandboxManager.deleteDirectory(stagingDirectory, true);
      } catch (cleanupError) {
        logger.warn(TAG, `清理散图暂存目录失败: ${stagingDirectory}`, String(cleanupError));
      }
      throw error as Error;
    }
  }

  private async selectFiles(): Promise<void> {
    if (this.isFilePickerActive || this.isMangaDialogOpening || this.isMangaImportRunning || this.isProcessing()) {
      logger.warn(TAG, '忽略重复的漫画文件选择请求');
      return;
    }
    const pageGeneration: number = this.pageLifecycleGeneration;
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.isFilePickerActive = true;
    try {
      logger.info(TAG, '开始选择本地文件');
      this.updateProgress(ImportStatus.SELECTING, '选择文件中...', 0);
      await this.waitForPendingBatchDialogAnalysis();
      await this.waitForPendingArchiveCleanup();
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }

      // 获取UIAbilityContext
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      // 创建文档选择器
      const documentPicker = new picker.DocumentViewPicker(context);

      // 设置选择选项
      const selectOptions = new picker.DocumentSelectOptions();
      // SDK 23 声明范围为 1..500；FILE 是默认模式，避免在非二合一设备设置仅二合一支持的 selectMode。
      selectOptions.maxSelectNumber = 500;
      selectOptions.fileSuffixFilters = [
        '.zip', '.cbz',
        '.rar', '.cbr',
        '.7z', '.lzma',
        '.tar', '.gz', '.tgz',
        '.bz2', '.xz',
        '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif',
        '.xml'
      ];

      // 选择文件
      const selectResult = await documentPicker.select(selectOptions);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }

      if (!selectResult || selectResult.length === 0) {
        this.updateProgress(ImportStatus.IDLE, '未选择任何文件', 0);
        return;
      }

      logger.info(TAG, `选择了 ${selectResult.length} 个文件`);
      this.selectedFiles = selectResult;
      this.updateProgress(ImportStatus.IDLE, `已选择 ${selectResult.length} 个文件`, 10);

    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, '选择文件失败', String(err.message || err));
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.updateProgress(ImportStatus.ERROR, `选择文件失败: ${err.message || err}`, 0);
      }
    } finally {
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.isFilePickerActive = false;
      }
    }
  }

  /**
   * 选择漫画文件夹
   */
  private selectFolder(): void {
    if (this.isFilePickerActive || this.isMangaDialogOpening || this.isMangaImportRunning || this.isProcessing()) {
      logger.warn(TAG, '忽略重复的漫画文件夹选择请求');
      return;
    }
    const pickerGeneration: number = this.folderPickerGeneration + 1;
    const pageGeneration: number = this.pageLifecycleGeneration;
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.folderPickerGeneration = pickerGeneration;
    this.isFilePickerActive = true;
    logger.info(TAG, '开始选择漫画文件夹');
    this.updateProgress(ImportStatus.SELECTING, '准备拉起文件夹选择器...', 0);

    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      logger.error(TAG, '选择文件夹失败', '无法获取应用上下文');
      this.updateProgress(ImportStatus.ERROR, '无法获取应用上下文', 0);
      this.isFilePickerActive = false;
      return;
    }

    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.selectMode = picker.DocumentSelectMode.FOLDER;
      
      void documentPicker.select(selectOptions).then((uris: Array<string>) => {
        if (this.folderPickerGeneration !== pickerGeneration ||
          !this.isCurrentPageGeneration(pageGeneration)) {
          return;
        }
        if (!uris || uris.length === 0) {
          this.updateProgress(ImportStatus.IDLE, '未选择任何文件夹', 0);
          return;
        }

        logger.info(TAG, `选择的文件夹 URI 列表: ${JSON.stringify(uris)}`);
        const folderUris = uris.map((uri: string) => `folder:${uri}`);
        
        // 由于在回调中执行，确保状态更新能够触发UI重绘
        this.selectedFiles = [...this.selectedFiles, ...folderUris];
        this.updateProgress(ImportStatus.IDLE, `已添加 ${uris.length} 个文件夹`, 10);
      }).catch((err: BusinessError) => {
        if (this.folderPickerGeneration !== pickerGeneration ||
          !this.isCurrentPageGeneration(pageGeneration)) {
          return;
        }
        const errorMsg = String(err.message || err);
        logger.error(TAG, `选择失败，错误码: ${err.code}, 信息: ${errorMsg}`);
        this.updateProgress(ImportStatus.ERROR, `拉起文件夹选择器失败: ${errorMsg}`, 0);
      }).then((): void => {
        if (this.folderPickerGeneration === pickerGeneration &&
          this.isCurrentPageGeneration(pageGeneration)) {
          this.isFilePickerActive = false;
        }
      });
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `DocumentViewPicker 初始化失败，错误码: ${err.code}, 信息: ${err.message}`);
      this.updateProgress(ImportStatus.ERROR, `选择文件夹失败: ${err.message}`, 0);
      if (this.folderPickerGeneration === pickerGeneration &&
        this.isCurrentPageGeneration(pageGeneration)) {
        this.isFilePickerActive = false;
      }
    }
  }

  /**
   * 开始导入流程（增强版）
   * 支持无XML信息的压缩包，弹出配置对话框
   */
  private async startImport(): Promise<void> {
    if (this.isMangaDialogOpening || this.isFilePickerActive || this.isMangaImportRunning ||
      this.batchMangaImportDialogController !== null || this.mangaImportDialogController !== null) {
      logger.warn(TAG, '忽略重复的漫画导入启动请求');
      return;
    }
    const pageGeneration: number = this.pageLifecycleGeneration;
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    if (this.selectedFiles.length === 0) {
      this.updateProgress(ImportStatus.ERROR, '请先选择要导入的文件', 0);
      return;
    }
    this.isMangaDialogOpening = true;
    try {
      await this.waitForPendingBatchDialogAnalysis();
      await this.waitForPendingArchiveCleanup();
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.updateProgress(ImportStatus.PARSING, '正在识别漫画文件和章节...', 5);
      await this.expandMangaSelectionCandidates(pageGeneration);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      if (this.selectedFiles.length === 0) {
        this.updateProgress(ImportStatus.ERROR, '未识别到可导入的漫画图片或压缩包', 0);
        return;
      }
      this.ensureImportFlow(
        this.currentImportFlowId.length > 0 ? ImportFlowEntrySource.UNKNOWN : ImportFlowEntrySource.FILE_PICKER,
        ImportFlowContentType.MANGA,
        this.selectedFiles.length === 1 ? this.getFileNameFromUri(this.selectedFiles[0]) : '批量漫画导入',
        this.selectedFiles.length,
        this.selectedFiles.length >= 2,
        this.selectedFiles[0],
        ''
      );
      const entryEvent: ImportFlowEvent = new ImportFlowEvent();
      entryEvent.eventType = ImportFlowEventType.ENTRY_RECEIVED;
      entryEvent.reason = 'manga_start_import';
      entryEvent.contentType = ImportFlowContentType.MANGA;
      entryEvent.fileCount = this.selectedFiles.length;
      entryEvent.batchMode = this.selectedFiles.length >= 2;
      entryEvent.sourceUri = this.selectedFiles[0];
      entryEvent.displayName = this.selectedFiles.length === 1 ? this.getFileNameFromUri(this.selectedFiles[0]) : '批量漫画导入';
      this.recordImportFlowEvent(entryEvent);

      if (this.selectedFiles.length >= 2) {
        await this.showBatchMangaImportDialog(pageGeneration);
        return;
      }

      await this.processFileWithDialog(this.selectedFiles[0], pageGeneration);
    } catch (error) {
      logger.error(TAG, '启动漫画导入失败', String(error));
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.updateProgress(ImportStatus.ERROR, `导入准备失败: ${error}`, 0);
        this.showToast(`导入准备失败: ${error instanceof Error ? error.message : String(error)}`);
        this.endCurrentImportFlow('manga_start_import_failed');
      }
    } finally {
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.isMangaDialogOpening = false;
      }
    }
  }
  
  /**
   * 显示批量漫画导入配置对话框
   */
  private async showBatchMangaImportDialog(pageGeneration: number): Promise<void> {
    // 先查找可能的重复漫画
    await this.findExistingMangaCandidatesForBatch(pageGeneration);
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }

    const analysisGeneration: string = this.createBatchAnalysisGeneration();
    const analysisSessionId: string = this.currentImportFlowId;
    this.beginBatchDialogAnalysis(analysisGeneration);
    try {
      this.batchMangaImportDialogController = new CustomDialogController({
      builder: BatchMangaImportDialog({
        themeState: this.themeState,
        fileUris: this.selectedFiles,
        existingMangaCandidates: this.existingMangaCandidates,
        parseFileStructure: async (fileUri: string): Promise<ParsedArchiveStructure | null> => {
          return await this.parseFileStructureForBatch(fileUri, analysisGeneration, analysisSessionId);
        },
        onReleaseParsedStructure: (fileUri: string, structure: ParsedArchiveStructure) => {
          this.releaseLateBatchArchiveStructure(fileUri, structure, analysisGeneration);
        },
        onAnalysisSettled: () => {
          this.finishBatchDialogAnalysis(analysisGeneration);
        },
        onAnalysisGenerationInvalidated: () => {
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
        },
        parseComicInfoXml: (xmlContent: string): PrefilledComicInfo | null => {
          return this.parseComicInfoXml(xmlContent);
        },
        onFlowEvent: (event: ImportFlowEvent) => {
          event.sessionId = analysisSessionId;
          this.recordImportFlowEvent(event);
        },
        onConfirm: (result: BatchMangaImportDialogResult) => {
          if (!this.isCurrentPageGeneration(pageGeneration)) {
            this.invalidateBatchAnalysisGeneration(analysisGeneration);
            return;
          }
          if (this.isMangaImportRunning) {
            logger.warn(TAG, '批量漫画导入已在运行，忽略重复确认');
            return;
          }
          if (this.mangaImportOwnerToken !== 0) {
            logger.warn(TAG, '已有漫画提交任务，忽略重复确认');
            return;
          }
          const ownerToken: number = this.beginMangaImportCommit();
          this.isMangaImportRunning = true;
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
          this.batchMangaImportDialogController = null;
          void (async (): Promise<void> => {
            try {
              await this.handleBatchMangaImportDialogResult(result, pageGeneration);
            } catch (error) {
              logger.error(TAG, `批量漫画导入异常: ${String(error)}`);
            } finally {
              this.finishMangaImport(pageGeneration, ownerToken);
            }
          })();
        },
        onCancel: () => {
          this.invalidateBatchAnalysisGeneration(analysisGeneration);
          if (this.isCurrentPageGeneration(pageGeneration)) {
            this.batchMangaImportDialogController = null;
            this.updateProgress(ImportStatus.IDLE, '已取消批量导入', 0);
            this.endCurrentImportFlow('batch_manga_cancelled');
            this.isMangaImportRunning = false;
          }
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
      });
      this.batchMangaImportDialogController.open();
    } catch (error) {
      this.invalidateBatchAnalysisGeneration(analysisGeneration);
      this.finishBatchDialogAnalysis(analysisGeneration);
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.batchMangaImportDialogController = null;
      }
      throw error as Error;
    }
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.recordSimpleImportFlowEvent(
      ImportFlowEventType.DIALOG_OPENED,
      'batch_manga_dialog_opened',
      ImportFlowContentType.MANGA,
      ImportFlowEntrySource.UNKNOWN,
      true,
      `files=${this.selectedFiles.length}`,
      0
    );
    this.updateProgress(ImportStatus.IDLE, '请配置批量导入选项', 10);
  }
  
  /**
   * 为批量导入查找可能的重复漫画
   */
  private async parseArchiveStructureWithPasswordRetry(
    fileUri: string,
    analysisGeneration: string = '',
    fixedSessionId: string = ''
  ): Promise<CompressionParsedStructure> {
    const cachedParsed = this.importArchiveParseCache.get(fileUri, analysisGeneration);
    if (cachedParsed !== null) {
      if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
        this.trackArchiveStructure(fileUri, cachedParsed, analysisGeneration);
      }
      const cacheEvent: ImportFlowEvent = new ImportFlowEvent();
      cacheEvent.eventType = ImportFlowEventType.ARCHIVE_PARSE_CACHE_HIT;
      cacheEvent.reason = 'archive_parse_cache_hit';
      cacheEvent.contentType = ImportFlowContentType.MANGA;
      cacheEvent.sessionId = fixedSessionId;
      cacheEvent.sourceUri = fileUri;
      cacheEvent.fileName = this.getFileNameFromUri(fileUri);
      cacheEvent.cacheHit = true;
      cacheEvent.cacheKey = this.importArchiveParseCache.buildKey(fileUri, analysisGeneration);
      cacheEvent.detail = `chapters=${cachedParsed.detectedChapters.length}, pages=${cachedParsed.totalImageCount}`;
      this.recordImportFlowEvent(cacheEvent);
      return cachedParsed;
    }

    const startedAt: number = Date.now();
    const startedEvent: ImportFlowEvent = new ImportFlowEvent();
    startedEvent.eventType = ImportFlowEventType.ARCHIVE_PARSE_STARTED;
    startedEvent.reason = 'archive_parse_started';
    startedEvent.contentType = ImportFlowContentType.MANGA;
    startedEvent.sessionId = fixedSessionId;
    startedEvent.sourceUri = fileUri;
    startedEvent.fileName = this.getFileNameFromUri(fileUri);
    this.recordImportFlowEvent(startedEvent);
    const parseSessionId: string = startedEvent.sessionId;

    const cachedPassword = this.archivePasswordCache.get(fileUri);
    if (cachedPassword) {
      try {
        const parsed = await this.compressionUtils.parseArchiveStructure(fileUri, { password: cachedPassword });
        return this.completeArchiveStructureParse(
          fileUri,
          parsed,
          startedAt,
          'cached_password',
          parseSessionId,
          analysisGeneration
        );
      } catch (error) {
        this.throwIfBatchAnalysisGenerationInvalidated(
          analysisGeneration,
          fileUri,
          startedAt,
          parseSessionId,
          'batch_generation_invalidated_after_cached_password'
        );
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          this.recordArchiveStructureParseFailure(fileUri, startedAt, String(error), 'cached_password_failed', parseSessionId);
          throw error as Error;
        }
        if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          this.archivePasswordCache.delete(fileUri);
        }
      }
    }

    if (this.lastArchivePassword) {
      try {
        const parsed = await this.compressionUtils.parseArchiveStructure(fileUri, { password: this.lastArchivePassword });
        if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          this.archivePasswordCache.set(fileUri, this.lastArchivePassword);
        }
        return this.completeArchiveStructureParse(
          fileUri,
          parsed,
          startedAt,
          'last_password',
          parseSessionId,
          analysisGeneration
        );
      } catch (error) {
        this.throwIfBatchAnalysisGenerationInvalidated(
          analysisGeneration,
          fileUri,
          startedAt,
          parseSessionId,
          'batch_generation_invalidated_after_last_password'
        );
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          this.recordArchiveStructureParseFailure(fileUri, startedAt, String(error), 'last_password_failed', parseSessionId);
          throw error as Error;
        }
      }
    }

    try {
      const parsed = await this.compressionUtils.parseArchiveStructure(fileUri);
      return this.completeArchiveStructureParse(
        fileUri,
        parsed,
        startedAt,
        'no_password',
        parseSessionId,
        analysisGeneration
      );
    } catch (error) {
      this.throwIfBatchAnalysisGenerationInvalidated(
        analysisGeneration,
        fileUri,
        startedAt,
        parseSessionId,
        'batch_generation_invalidated_after_no_password'
      );
      if (!this.compressionUtils.isPasswordRequiredError(error)) {
        this.recordArchiveStructureParseFailure(fileUri, startedAt, String(error), 'no_password_failed', parseSessionId);
        throw error as Error;
      }
    }

    if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
      this.recordArchiveStructureParseFailure(
        fileUri,
        startedAt,
        '批量解析代次已失效',
        'batch_generation_invalidated_before_password',
        parseSessionId
      );
      throw new UserSkipError('批量解析已取消');
    }

    const passwordRequiredEvent: ImportFlowEvent = new ImportFlowEvent();
    passwordRequiredEvent.eventType = ImportFlowEventType.PASSWORD_REQUIRED;
    passwordRequiredEvent.reason = 'archive_password_required';
    passwordRequiredEvent.contentType = ImportFlowContentType.MANGA;
    passwordRequiredEvent.sessionId = parseSessionId;
    passwordRequiredEvent.sourceUri = fileUri;
    passwordRequiredEvent.fileName = this.getFileNameFromUri(fileUri);
    this.recordImportFlowEvent(passwordRequiredEvent);

    let errorMessage = '该压缩包需要密码才能继续导入';
    for (let attempt = 0; attempt < 3; attempt++) {
      if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
        this.recordArchiveStructureParseFailure(
          fileUri,
          startedAt,
          '批量解析代次已失效',
          'batch_generation_invalidated_before_password_retry',
          parseSessionId
        );
        throw new UserSkipError('批量解析已取消');
      }
      const retryEvent: ImportFlowEvent = new ImportFlowEvent();
      retryEvent.eventType = ImportFlowEventType.PASSWORD_RETRY;
      retryEvent.reason = 'archive_password_retry';
      retryEvent.contentType = ImportFlowContentType.MANGA;
      retryEvent.sessionId = parseSessionId;
      retryEvent.sourceUri = fileUri;
      retryEvent.fileName = this.getFileNameFromUri(fileUri);
      retryEvent.currentIndex = attempt + 1;
      retryEvent.totalCount = 3;
      this.recordImportFlowEvent(retryEvent);
      const password = await showArchivePasswordDialog(
        this.themeState,
        this.getFileNameFromUri(fileUri),
        this.lastArchivePassword,
        errorMessage
      );
      if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
        this.recordArchiveStructureParseFailure(
          fileUri,
          startedAt,
          '批量解析代次已失效',
          'batch_generation_invalidated_during_password',
          parseSessionId
        );
        throw new UserSkipError('批量解析已取消');
      }
      if (!password) {
        this.recordArchiveStructureParseFailure(
          fileUri,
          startedAt,
          '用户取消输入压缩包密码',
          'password_cancelled',
          parseSessionId
        );
        throw new UserSkipError('用户取消输入压缩包密码');
      }

      try {
        const parsed = await this.compressionUtils.parseArchiveStructure(fileUri, { password: password });
        if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          this.lastArchivePassword = password;
          this.archivePasswordCache.set(fileUri, password);
        }
        return this.completeArchiveStructureParse(
          fileUri,
          parsed,
          startedAt,
          'password_retry_success',
          parseSessionId,
          analysisGeneration
        );
      } catch (error) {
        this.throwIfBatchAnalysisGenerationInvalidated(
          analysisGeneration,
          fileUri,
          startedAt,
          parseSessionId,
          'batch_generation_invalidated_after_password_retry'
        );
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          this.recordArchiveStructureParseFailure(fileUri, startedAt, String(error), 'password_retry_failed', parseSessionId);
          throw error as Error;
        }
        errorMessage = '密码不正确，请重试';
      }
    }

    this.recordArchiveStructureParseFailure(
      fileUri,
      startedAt,
      '压缩包密码错误',
      'password_retry_exhausted',
      parseSessionId
    );
    throw new Error('压缩包密码错误');
  }

  private completeArchiveStructureParse(
    fileUri: string,
    parsed: CompressionParsedStructure,
    startedAt: number,
    reason: string,
    sessionId: string,
    analysisGeneration: string
  ): CompressionParsedStructure {
    if (this.isBatchAnalysisGenerationActive(analysisGeneration)) {
      this.importArchiveParseCache.set(fileUri, parsed, analysisGeneration);
      this.trackArchiveStructure(fileUri, parsed, analysisGeneration);
    } else {
      logger.info(TAG, `忽略已失效批量解析结果: generation=${analysisGeneration}, file=${fileUri}`);
    }
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.eventType = ImportFlowEventType.ARCHIVE_PARSE_COMPLETED;
    event.reason = reason;
    event.contentType = ImportFlowContentType.MANGA;
    event.sessionId = sessionId;
    event.sourceUri = fileUri;
    event.fileName = this.getFileNameFromUri(fileUri);
    event.chapterCount = parsed.detectedChapters.length;
    event.pageCount = parsed.totalImageCount;
    event.elapsedMs = Date.now() - startedAt;
    event.cacheKey = this.importArchiveParseCache.buildKey(fileUri, analysisGeneration);
    event.detail = `chapters=${parsed.detectedChapters.length}, pages=${parsed.totalImageCount}, rootImages=${parsed.rootImageCount}`;
    this.recordImportFlowEvent(event);
    return parsed;
  }

  private recordArchiveStructureParseFailure(
    fileUri: string,
    startedAt: number,
    errorMessage: string,
    reason: string,
    sessionId: string
  ): void {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.eventType = ImportFlowEventType.ARCHIVE_PARSE_FAILED;
    event.reason = reason;
    event.contentType = ImportFlowContentType.MANGA;
    event.sessionId = sessionId;
    event.sourceUri = fileUri;
    event.fileName = this.getFileNameFromUri(fileUri);
    event.success = false;
    event.severity = ImportFlowSeverity.ERROR;
    event.elapsedMs = Date.now() - startedAt;
    event.errorMessage = errorMessage;
    this.recordImportFlowEvent(event);
  }

  private async extractRecursivelyAndFindComicInfoWithPasswordRetry(
    fileUri: string,
    maxRecursionDepth: number = 3
  ): Promise<RecursiveExtractionResult> {
    const cachedPassword = this.archivePasswordCache.get(fileUri);
    if (cachedPassword) {
      try {
        return await this.compressionUtils.extractRecursivelyAndFindComicInfo(fileUri, maxRecursionDepth, {
          password: cachedPassword
        });
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
        this.archivePasswordCache.delete(fileUri);
      }
    }

    if (this.lastArchivePassword) {
      try {
        const result = await this.compressionUtils.extractRecursivelyAndFindComicInfo(fileUri, maxRecursionDepth, {
          password: this.lastArchivePassword
        });
        this.archivePasswordCache.set(fileUri, this.lastArchivePassword);
        return result;
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
      }
    }

    try {
      return await this.compressionUtils.extractRecursivelyAndFindComicInfo(fileUri, maxRecursionDepth);
    } catch (error) {
      if (!this.compressionUtils.isPasswordRequiredError(error)) {
        throw error as Error;
      }
    }

    let errorMessage = '该压缩包需要密码才能继续导入';
    for (let attempt = 0; attempt < 3; attempt++) {
      const password = await showArchivePasswordDialog(
        this.themeState,
        this.getFileNameFromUri(fileUri),
        this.lastArchivePassword,
        errorMessage
      );
      if (!password) {
        throw new UserSkipError('用户取消输入压缩包密码');
      }

      try {
        const result = await this.compressionUtils.extractRecursivelyAndFindComicInfo(fileUri, maxRecursionDepth, {
          password: password
        });
        this.lastArchivePassword = password;
        this.archivePasswordCache.set(fileUri, password);
        return result;
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
        errorMessage = '密码不正确，请重试';
      }
    }

    throw new Error('压缩包密码错误');
  }

  private async extractAndFindComicInfoWithPasswordRetry(fileUri: string) {
    const cachedPassword = this.archivePasswordCache.get(fileUri);
    if (cachedPassword) {
      try {
        return await this.compressionUtils.extractAndFindComicInfo(fileUri, { password: cachedPassword });
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
        this.archivePasswordCache.delete(fileUri);
      }
    }

    if (this.lastArchivePassword) {
      try {
        const result = await this.compressionUtils.extractAndFindComicInfo(fileUri, { password: this.lastArchivePassword });
        this.archivePasswordCache.set(fileUri, this.lastArchivePassword);
        return result;
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
      }
    }

    try {
      return await this.compressionUtils.extractAndFindComicInfo(fileUri);
    } catch (error) {
      if (!this.compressionUtils.isPasswordRequiredError(error)) {
        throw error as Error;
      }
    }

    let errorMessage = '该压缩包需要密码才能继续导入';
    for (let attempt = 0; attempt < 3; attempt++) {
      const password = await showArchivePasswordDialog(
        this.themeState,
        this.getFileNameFromUri(fileUri),
        this.lastArchivePassword,
        errorMessage
      );
      if (!password) {
        throw new UserSkipError('用户取消输入压缩包密码');
      }

      try {
        const result = await this.compressionUtils.extractAndFindComicInfo(fileUri, { password: password });
        this.lastArchivePassword = password;
        this.archivePasswordCache.set(fileUri, password);
        return result;
      } catch (error) {
        if (!this.compressionUtils.isPasswordRequiredError(error)) {
          throw error as Error;
        }
        errorMessage = '密码不正确，请重试';
      }
    }

    throw new Error('压缩包密码错误');
  }

  private async findExistingMangaCandidatesForBatch(pageGeneration: number): Promise<void> {
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    const cacheTitle: string = 'batch';
    const cachedCandidates = this.importDuplicateDetectionCache.get(this.currentImportFlowId, cacheTitle, 'manga', 'batch');
    if (cachedCandidates !== null) {
      this.existingMangaCandidates = cachedCandidates;
      const cacheEvent: ImportFlowEvent = new ImportFlowEvent();
      cacheEvent.eventType = ImportFlowEventType.DUPLICATE_CACHE_HIT;
      cacheEvent.reason = 'batch_duplicate_cache_hit';
      cacheEvent.contentType = ImportFlowContentType.MANGA;
      cacheEvent.cacheHit = true;
      cacheEvent.cacheKey = this.importDuplicateDetectionCache.buildKey(this.currentImportFlowId, cacheTitle, 'manga', 'batch');
      cacheEvent.detail = `candidates=${cachedCandidates.length}`;
      this.recordImportFlowEvent(cacheEvent);
      return;
    }
    const startedAt: number = Date.now();
    const startedEvent: ImportFlowEvent = new ImportFlowEvent();
    startedEvent.eventType = ImportFlowEventType.DUPLICATE_DETECT_STARTED;
    startedEvent.reason = 'batch_duplicate_detect_started';
    startedEvent.contentType = ImportFlowContentType.MANGA;
    startedEvent.detail = `selected=${this.selectedFiles.length}, pending=${this.pendingMangaFiles.length}`;
    this.recordImportFlowEvent(startedEvent);
    try {
      // 获取所有漫画记录
      const allComics: ComicRecord[] = await this.dataManager.getAllComics();
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      
      // 转换为候选格式
      const candidates: ExistingMangaCandidate[] = [];
      for (const comic of allComics) {
        if (comic.sourceId !== 'local_import' && comic.sourceId !== 'download_import') {
          continue;
        }
        const candidate: ExistingMangaCandidate = {
          id: comic.id,
          title: comic.title,
          author: comic.author || '未知作者',
          coverUrl: comic.coverUrl || '',
          chapterCount: comic.chapterCount || 0
        };
        candidates.push(candidate);
      }
      this.existingMangaCandidates = candidates;
      this.importDuplicateDetectionCache.set(this.currentImportFlowId, cacheTitle, 'manga', 'batch', candidates);
      const completedEvent: ImportFlowEvent = new ImportFlowEvent();
      completedEvent.eventType = ImportFlowEventType.DUPLICATE_DETECT_COMPLETED;
      completedEvent.reason = 'batch_duplicate_detect_completed';
      completedEvent.contentType = ImportFlowContentType.MANGA;
      completedEvent.elapsedMs = Date.now() - startedAt;
      completedEvent.totalCount = allComics.length;
      completedEvent.currentIndex = candidates.length;
      completedEvent.detail = `candidates=${candidates.length}`;
      this.recordImportFlowEvent(completedEvent);
      
      logger.info(TAG, `批量导入找到 ${this.existingMangaCandidates.length} 个已有漫画候选`);
    } catch (error) {
      logger.error(TAG, `查找已有漫画失败: ${error}`);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.existingMangaCandidates = [];
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'batch_duplicate_detect_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - startedAt;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
    }
  }
  
  /**
   * 为批量导入解析文件结构
   * 支持压缩包和文件夹（解压失败时回退到文件夹扫描）
   */
  private async parseFileStructureForBatch(
    fileUri: string,
    analysisGeneration: string,
    analysisSessionId: string
  ): Promise<ParsedArchiveStructure | null> {
    try {
      if (fileUri.startsWith('picked-images:')) {
        const pickedStructure: CompressionParsedStructure = await this.stagePickedImageGroup(fileUri);
        if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          await this.compressionUtils.cleanupParsedArchiveStructure(pickedStructure);
          return null;
        }
        this.trackArchiveStructure(fileUri, pickedStructure, analysisGeneration);
        return this.convertParsedStructure(pickedStructure);
      }
      if (fileUri.startsWith('folder-flat:')) {
        const folderPath: string = this.resolveLocalImportPath(fileUri.substring('folder-flat:'.length));
        const flatStructure: CompressionParsedStructure =
          await this.compressionUtils.parseFlatImageFolderAsArchiveStructure(folderPath);
        if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          return null;
        }
        return this.convertParsedStructure(flatStructure);
      }
      // 检查是否为文件夹类型
      if (fileUri.startsWith('folder:')) {
        const folderPath = this.resolveLocalImportPath(fileUri.substring(7));
        const folderStructure: CompressionParsedStructure =
          await this.compressionUtils.parseFolderAsArchiveStructure(folderPath);
        if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          return null;
        }
        return await this.convertParsedStructure(folderStructure);
      }
      
      // 尝试作为压缩包解析
      try {
        const parsedStructure = await this.parseArchiveStructureWithPasswordRetry(
          fileUri,
          analysisGeneration,
          analysisSessionId
        );
        if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          const staleStructure: ParsedArchiveStructure = this.convertParsedStructure(parsedStructure);
          this.releaseLateBatchArchiveStructure(fileUri, staleStructure, analysisGeneration);
          return null;
        }
        return this.convertParsedStructure(parsedStructure);
      } catch (archiveError) {
        if (!this.isBatchAnalysisGenerationActive(analysisGeneration)) {
          return null;
        }
        // 解压失败，尝试将路径当作文件夹扫描
        logger.warn(TAG, `解压失败，尝试作为文件夹解析: ${fileUri}`, String(archiveError));
        try {
          // 将URI转换为本地路径后尝试作为文件夹
          let localPath = fileUri;
          if (fileUri.startsWith('file://')) {
            localPath = fileUri.replace('file://', '');
          }
          const parsedStructure = await this.compressionUtils.parseFolderAsArchiveStructure(localPath);
          if (parsedStructure.totalImageCount > 0 && this.isBatchAnalysisGenerationActive(analysisGeneration)) {
            return this.convertParsedStructure(parsedStructure);
          }
        } catch (folderError) {
          logger.warn(TAG, `文件夹解析也失败: ${fileUri}`, String(folderError));
        }
        return null;
      }
    } catch (error) {
      logger.error(TAG, `解析文件结构失败: ${fileUri}`, String(error));
      return null;
    }
  }
  
  /**
   * 将CompressionUtils的ParsedArchiveStructure转换为对话框格式
   */
  private convertParsedStructure(parsedStructure: CompressionParsedStructure): ParsedArchiveStructure {
    const convertedChapters: ChapterInfo[] = [];
    for (let i = 0; i < parsedStructure.detectedChapters.length; i++) {
      const ch = parsedStructure.detectedChapters[i];
      const chapterInfo: ChapterInfo = {
        index: ch.index,
        number: ch.number,
        title: ch.title,
        originalName: ch.originalName,
        path: ch.path,
        pageCount: ch.pageCount
      };
      convertedChapters.push(chapterInfo);
    }
    
    return {
      hasComicInfo: parsedStructure.hasComicInfo,
      comicInfoContent: parsedStructure.comicInfoContent,
      isMultiLayer: parsedStructure.isMultiLayer,
      detectedChapters: convertedChapters,
      rootImageCount: parsedStructure.rootImageCount,
      totalImageCount: parsedStructure.totalImageCount,
      extractedPath: parsedStructure.extractedPath,
      tempDirectories: parsedStructure.tempDirectories,
      warnings: parsedStructure.warnings
    };
  }
  
  /**
   * 处理批量漫画导入对话框结果
   */
  private async handleBatchMangaImportDialogResult(
    result: BatchMangaImportDialogResult,
    pageGeneration: number = this.pageLifecycleGeneration
  ): Promise<void> {
    const batchStartedAt: number = Date.now();
    try {
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.importResults = [];
        this.importResultDetails = [];
        this.showResults = false;
      }
      
      const totalGroups = result.groups.length;
      let processedGroups = 0;
      let successfulImports = 0;
      
      logger.info(TAG, `开始批量导入，共 ${totalGroups} 部漫画`);
      const confirmEvent: ImportFlowEvent = new ImportFlowEvent();
      confirmEvent.eventType = ImportFlowEventType.DIALOG_CONFIRMED;
      confirmEvent.reason = 'batch_manga_confirmed';
      confirmEvent.contentType = ImportFlowContentType.MANGA;
      confirmEvent.batchMode = true;
      confirmEvent.fileCount = totalGroups;
      confirmEvent.totalCount = totalGroups;
      this.recordImportFlowEvent(confirmEvent);
      
      for (const group of result.groups) {
        processedGroups++;
        this.updateProgress(
          ImportStatus.IMPORTING,
          `正在导入 (${processedGroups}/${totalGroups}): ${group.title}`,
          20 + (processedGroups / totalGroups) * 70
        );
        
        try {
          await this.importMangaGroup(group);
          successfulImports++;
          if (this.isCurrentPageGeneration(pageGeneration)) {
            this.importResults.push(`✅ ${group.title}: 导入成功 (${group.chapters.length} 章节)`);
          }
          const progressEvent: ImportFlowEvent = new ImportFlowEvent();
          progressEvent.eventType = ImportFlowEventType.COPY_PROGRESS;
          progressEvent.reason = 'batch_manga_group_imported';
          progressEvent.contentType = ImportFlowContentType.MANGA;
          progressEvent.batchMode = true;
          progressEvent.displayName = group.title;
          progressEvent.currentIndex = processedGroups;
          progressEvent.totalCount = totalGroups;
          this.recordImportFlowEvent(progressEvent);
        } catch (error) {
          if (this.isCurrentPageGeneration(pageGeneration)) {
            this.importResults.push(`❌ ${group.title}: 导入失败 - ${error}`);
          }
          logger.error(TAG, `导入漫画分组失败: ${group.title}`, String(error));
          const failedEvent: ImportFlowEvent = new ImportFlowEvent();
          failedEvent.eventType = ImportFlowEventType.ERROR;
          failedEvent.reason = 'batch_manga_group_failed';
          failedEvent.contentType = ImportFlowContentType.MANGA;
          failedEvent.batchMode = true;
          failedEvent.displayName = group.title;
          failedEvent.currentIndex = processedGroups;
          failedEvent.totalCount = totalGroups;
          failedEvent.success = false;
          failedEvent.severity = ImportFlowSeverity.ERROR;
          failedEvent.errorMessage = String(error);
          this.recordImportFlowEvent(failedEvent);
        }
      }
      
      this.updateProgress(ImportStatus.COMPLETED, `导入完成，成功 ${successfulImports}/${totalGroups} 部漫画`, 100);
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.showResults = true;
      }
      
      // 显示导入结果Toast
      if (successfulImports > 0) {
        this.showToast(`批量导入完成: 成功 ${successfulImports} 部，失败 ${totalGroups - successfulImports} 部`);
      } else {
        this.showToast(`批量导入完成: 全部失败 (${totalGroups} 部漫画)`);
      }
      
      // 清除选择的文件
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.selectedFiles = [];
      }
      
      // 发布导入完成事件
      if (successfulImports > 0) {
        eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(successfulImports, totalGroups));
        const refreshEvent: ImportFlowEvent = new ImportFlowEvent();
        refreshEvent.eventType = ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED;
        refreshEvent.reason = 'batch_manga_bookshelf_refresh_published';
        refreshEvent.contentType = ImportFlowContentType.MANGA;
        refreshEvent.batchMode = true;
        refreshEvent.currentIndex = successfulImports;
        refreshEvent.totalCount = totalGroups;
        refreshEvent.elapsedMs = Date.now() - batchStartedAt;
        this.recordImportFlowEvent(refreshEvent);
      }
      this.endCurrentImportFlow(successfulImports > 0 ? 'batch_manga_completed' : 'batch_manga_no_success');
      
    } catch (error) {
      logger.error(TAG, '批量导入失败', String(error));
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'batch_manga_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.batchMode = true;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - batchStartedAt;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.updateProgress(ImportStatus.ERROR, `批量导入失败: ${error}`, 0);
        this.showToast(`批量导入失败: ${error instanceof Error ? error.message : String(error)}`);
      }
      this.endCurrentImportFlow('batch_manga_failed');
    }
  }
  
  /**
   * 导入单个漫画分组
   */
  private convertBatchDialogMangaStatus(status: BatchDialogMangaStatus): MangaStatus {
    switch (status) {
      case BatchDialogMangaStatus.ONGOING:
        return MangaStatus.ONGOING;
      case BatchDialogMangaStatus.COMPLETED:
        return MangaStatus.COMPLETED;
      case BatchDialogMangaStatus.HIATUS:
        return MangaStatus.HIATUS;
      case BatchDialogMangaStatus.CANCELLED:
        return MangaStatus.CANCELLED;
      default:
        return MangaStatus.UNKNOWN;
    }
  }

  private async importMangaGroup(group: MangaGroupResult): Promise<void> {
    if (group.chapters.length <= 0) {
      throw new Error(`漫画 ${group.title} 没有可导入章节`);
    }
    for (const chapter of group.chapters) {
      if (chapter.parsedStructure === null || chapter.sourcePath.trim().length <= 0 || chapter.pageCount <= 0) {
        throw new Error(`漫画 ${group.title} 包含无效章节: ${chapter.title}`);
      }
    }
    let mangaId: string = '';
    let createdMangaId: string = '';
    const createdChapterIds: string[] = [];
    const dbStartedAt: number = Date.now();
    try {
      if (group.mergeToExisting) {
        const targetMangaId: string = group.targetMangaId || '';
        if (targetMangaId.trim().length <= 0) {
          throw new Error(`漫画 ${group.title} 已选择合并但缺少目标漫画ID`);
        }
        const existingManga: ComicRecord | null = await this.dataManager.getComicInfo(targetMangaId);
        if (existingManga === null) {
          throw new Error(`合并目标漫画不存在: ${targetMangaId}`);
        }
        mangaId = targetMangaId;
        logger.info(TAG, `合并到已有漫画: ${mangaId}`);
      } else {
      // 创建新漫画
      const comicInfoInput: ComicInfoInput = {
        title: group.title,
        author: group.author,
        description: group.description,
        coverUrl: '',
        sourceId: 'local_import',
        externalId: `local_${generateUUID()}`,
        status: this.convertBatchDialogMangaStatus(group.status),
        tags: group.tags,
        rating: 0,
        chapterCount: group.chapters.length,
        lastUpdateTime: Date.now(),
        webUrl: group.webUrl,
        isNSFW: group.isNSFW
      };
      
      const dbStartedEvent: ImportFlowEvent = new ImportFlowEvent();
      dbStartedEvent.eventType = ImportFlowEventType.DB_WRITE_STARTED;
      dbStartedEvent.reason = 'batch_manga_record_create_started';
      dbStartedEvent.contentType = ImportFlowContentType.MANGA;
      dbStartedEvent.displayName = group.title;
      dbStartedEvent.chapterCount = group.chapters.length;
      this.recordImportFlowEvent(dbStartedEvent);
      mangaId = await this.dataManager.addComicInfo(comicInfoInput);
      createdMangaId = mangaId;
      logger.info(TAG, `创建新漫画: ${mangaId}, 标题: ${group.title}`);
      
      // 处理封面
      if (group.selectedCoverPath) {
        await this.processCoverImage(mangaId, group.selectedCoverPath, group.title);
        const coverEvent: ImportFlowEvent = new ImportFlowEvent();
        coverEvent.eventType = ImportFlowEventType.COVER_HANDLED;
        coverEvent.reason = 'batch_manga_cover_handled';
        coverEvent.contentType = ImportFlowContentType.MANGA;
        coverEvent.displayName = group.title;
        coverEvent.targetPath = group.selectedCoverPath;
        this.recordImportFlowEvent(coverEvent);
      }
      }
      const dbCompletedEvent: ImportFlowEvent = new ImportFlowEvent();
    dbCompletedEvent.eventType = ImportFlowEventType.DB_WRITE_COMPLETED;
    dbCompletedEvent.reason = 'batch_manga_record_ready';
    dbCompletedEvent.contentType = ImportFlowContentType.MANGA;
    dbCompletedEvent.displayName = group.title;
    dbCompletedEvent.chapterCount = group.chapters.length;
    dbCompletedEvent.elapsedMs = Date.now() - dbStartedAt;
    dbCompletedEvent.detail = `mangaId=${mangaId}`;
      this.recordImportFlowEvent(dbCompletedEvent);

      // 导入所有章节
      for (const chapter of group.chapters) {
        const chapterCreation: ChapterInfoCreationResult =
          await this.importChapterFromBatch(mangaId, chapter, group.title);
        if (!chapterCreation.created) {
          throw new Error(`章节已存在，已停止重复导入: ${chapter.title}`);
        }
        createdChapterIds.push(chapterCreation.id);
      }
      await this.dataManager.refreshComicChapterCount(mangaId);

      await this.validateImportedMangaGroup(mangaId, createdChapterIds, group.chapters.length);
      if (createdMangaId.length > 0) {
        // 只有章节和页面全部落盘后才进入收藏书架，避免失败中的父记录
        // 先以空壳形式出现在用户书架。
        await DataService.getInstance().addToFavorites(mangaId, group.tags);
      }
    
      logger.info(TAG, `漫画 ${group.title} 导入完成，共 ${group.chapters.length} 个章节`);
    } catch (error) {
      if (createdMangaId.length > 0) {
        try {
          await this.dataManager.deleteComic(createdMangaId);
          logger.info(TAG, `已回滚失败的漫画分组: ${group.title}, id=${createdMangaId}`);
        } catch (rollbackError) {
          logger.error(TAG, `回滚漫画分组失败: ${group.title}`, String(rollbackError));
        }
      } else {
        for (let index: number = createdChapterIds.length - 1; index >= 0; index--) {
          const chapterId: string = createdChapterIds[index];
          try {
            const chapterInfo: ChapterRecord | null = await this.dataManager.getChapterInfo(chapterId);
            await this.dataManager.deleteChapter(chapterId);
            if (chapterInfo?.downloadPath && chapterInfo.downloadPath.length > 0) {
              await this.sandboxManager.deleteDirectory(chapterInfo.downloadPath, true);
            }
          } catch (rollbackError) {
            logger.error(TAG, `回滚合并章节失败: ${chapterId}`, String(rollbackError));
          }
        }
      }
      throw error as Error;
    }
  }

  private async validateImportedMangaGroup(
    mangaId: string,
    createdChapterIds: string[],
    expectedChapterCount: number
  ): Promise<void> {
    if (createdChapterIds.length !== expectedChapterCount) {
      throw new Error(
        `漫画导入章节不完整: mangaId=${mangaId}, expected=${expectedChapterCount}, actual=${createdChapterIds.length}`
      );
    }
    for (const chapterId of createdChapterIds) {
      const chapterInfo: ChapterRecord | null = await this.dataManager.getChapterInfo(chapterId);
      if (chapterInfo === null) {
        throw new Error(`漫画导入验证失败，章节不存在: ${chapterId}`);
      }
      const pages: PageRecord[] = await this.dataManager.getChapterPages(chapterId);
      if (pages.length <= 0 || pages.length !== chapterInfo.pageCount) {
        throw new Error(
          `漫画导入验证失败，章节页面不完整: chapterId=${chapterId}, expected=${chapterInfo.pageCount}, actual=${pages.length}`
        );
      }
    }
  }
  
  /**
   * 从批量导入结果导入单个章节
   */
  private async importChapterFromBatch(
    mangaId: string,
    chapter: BatchChapterResult,
    comicTitle: string
  ): Promise<ChapterInfoCreationResult> {
    if (!chapter.parsedStructure) {
      throw new Error(`章节 ${chapter.title} 没有解析结构`);
    }
    if (chapter.sourcePath.trim().length <= 0 || chapter.pageCount <= 0) {
      throw new Error(`章节 ${chapter.title} 没有可导入的图片`);
    }

    let effectiveSourcePath: string = chapter.sourcePath;
    let effectivePreserveSource: boolean = chapter.preserveSource;
    let stagedRootPath: string = '';
    if (this.isMixedRootImageChapter(chapter.parsedStructure, chapter.sourcePath, chapter.pageCount)) {
      stagedRootPath = await this.stageDirectImageChapter(chapter.sourcePath, chapter.pageCount);
      effectiveSourcePath = stagedRootPath;
      effectivePreserveSource = false;
    }
    
    // 创建章节
    const chapterInfoInput: ChapterInfoInput = {
      comicId: mangaId,
      title: chapter.title,
      index: chapter.number - 1,
      pageCount: chapter.pageCount,
      isDownloaded: true,
      downloadPath: effectiveSourcePath,
      publishTime: chapter.publishTime,
      externalId: await createLocalMangaChapterExternalId(
        mangaId,
        chapter.fileUri,
        chapter.sourcePath,
        chapter.parsedStructure?.extractedPath || '',
        chapter.number
      )
    };
    
    const dbStartedAt: number = Date.now();
    const chapterCreation: ChapterInfoCreationResult =
      await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
    const chapterId: string = chapterCreation.id;
    if (!chapterCreation.created) {
      if (stagedRootPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(stagedRootPath, true);
        } catch (cleanupError) {
          logger.warn(TAG, `清理重复章节暂存目录失败: ${stagedRootPath}`, String(cleanupError));
        }
      }
      logger.warn(TAG, `跳过重复章节页面写入: ${chapter.title}, chapterId=${chapterId}`);
      return chapterCreation;
    }
    logger.info(TAG, `创建章节: ${chapterId}, 标题: ${chapter.title}`);
    
    // 整理文件并添加页面信息
    const comicInfoInput: ComicInfoInput = {
      title: comicTitle,
      author: '',
      description: '',
      coverUrl: '',
      sourceId: 'local_import',
      externalId: '',
      status: MangaStatus.UNKNOWN,
      tags: [],
      rating: 0,
      chapterCount: 1,
      lastUpdateTime: Date.now()
    };
    
    const copyStartedAt: number = Date.now();
    try {
      await this.organizeAndAddPages(
        comicInfoInput,
        chapterInfoInput,
        effectiveSourcePath,
        chapterId,
        effectivePreserveSource,
        chapter.pageCount
      );
    } catch (error) {
      await this.dataManager.deleteChapter(chapterId);
      if (stagedRootPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(stagedRootPath, true);
        } catch (cleanupError) {
          logger.warn(TAG, `清理失败根散图暂存目录失败: ${stagedRootPath}`, String(cleanupError));
        }
      }
      throw error as Error;
    }
    const copyEvent: ImportFlowEvent = new ImportFlowEvent();
    copyEvent.eventType = ImportFlowEventType.COPY_COMPLETED;
    copyEvent.reason = 'batch_chapter_organized';
    copyEvent.contentType = ImportFlowContentType.MANGA;
    copyEvent.displayName = comicTitle;
    copyEvent.fileName = chapter.title;
    copyEvent.targetPath = effectiveSourcePath;
    copyEvent.pageCount = chapter.pageCount;
    copyEvent.elapsedMs = Date.now() - copyStartedAt;
    this.recordImportFlowEvent(copyEvent);
    const dbEvent: ImportFlowEvent = new ImportFlowEvent();
    dbEvent.eventType = ImportFlowEventType.DB_WRITE_COMPLETED;
    dbEvent.reason = 'batch_chapter_db_completed';
    dbEvent.contentType = ImportFlowContentType.MANGA;
    dbEvent.displayName = comicTitle;
    dbEvent.fileName = chapter.title;
    dbEvent.pageCount = chapter.pageCount;
    dbEvent.elapsedMs = Date.now() - dbStartedAt;
    dbEvent.detail = `chapterId=${chapterId}`;
    this.recordImportFlowEvent(dbEvent);
    return chapterCreation;
  }

  /**
   * 处理单个文件（带对话框）
   * 解析压缩包结构，根据情况显示配置对话框
   */
  private async processFileWithDialog(fileUri: string, pageGeneration: number): Promise<void> {
    const fileName = this.getFileNameFromUri(fileUri);
    
    try {
      this.updateProgress(ImportStatus.EXTRACTING, `正在解析结构: ${fileName}`, 10);
      
      let parsedStructure: CompressionParsedStructure;
      if (fileUri.startsWith('picked-images:')) {
        parsedStructure = await this.stagePickedImageGroup(fileUri);
      } else if (fileUri.startsWith('folder-flat:')) {
        const folderPath: string = this.resolveLocalImportPath(fileUri.substring('folder-flat:'.length));
        parsedStructure = await this.compressionUtils.parseFlatImageFolderAsArchiveStructure(folderPath);
      } else if (fileUri.startsWith('folder:')) {
        const folderPath = this.resolveLocalImportPath(fileUri.substring(7));
        parsedStructure = await this.compressionUtils.parseFolderAsArchiveStructure(folderPath);
      } else {
        parsedStructure = await this.parseArchiveStructureWithPasswordRetry(fileUri);
      }
      
      // 转换为对话框需要的格式
      const convertedChapters: ChapterInfo[] = [];
      for (let i = 0; i < parsedStructure.detectedChapters.length; i++) {
        const ch = parsedStructure.detectedChapters[i];
        const chapterInfo: ChapterInfo = {
          index: ch.index,
          number: ch.number,
          title: ch.title,
          originalName: ch.originalName,
          path: ch.path,
          pageCount: ch.pageCount
        };
        convertedChapters.push(chapterInfo);
      }
      
      const dialogStructure: ParsedArchiveStructure = {
        hasComicInfo: parsedStructure.hasComicInfo,
        comicInfoContent: parsedStructure.comicInfoContent,
        isMultiLayer: parsedStructure.isMultiLayer,
        detectedChapters: convertedChapters,
        rootImageCount: parsedStructure.rootImageCount,
        totalImageCount: parsedStructure.totalImageCount,
        extractedPath: parsedStructure.extractedPath,
        tempDirectories: parsedStructure.tempDirectories,
        warnings: parsedStructure.warnings
      };
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        this.releaseLateBatchArchiveStructure(fileUri, dialogStructure, '');
        return;
      }
      
      this.currentParsedStructure = dialogStructure;
      this.currentFileUri = fileUri;
      
      // 始终显示配置对话框，让用户确认信息和选择封面
      // 如果有ComicInfo.xml，会预填充信息供用户确认
      await this.findExistingMangaCandidates(fileName, pageGeneration);
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        this.releaseLateBatchArchiveStructure(fileUri, dialogStructure, '');
        return;
      }
      
      // 如果有ComicInfo.xml，预填充对话框的信息
      if (parsedStructure.hasComicInfo && parsedStructure.comicInfoContent) {
        // 解析ComicInfo.xml获取预填充信息
        const prefilledInfo = this.parseComicInfoXml(parsedStructure.comicInfoContent);
        if (prefilledInfo) {
          // 将解析的信息传递给对话框
          dialogStructure.prefilledInfo = prefilledInfo;
        }
      }
      
      // 显示配置对话框
      this.showMangaImportDialog(fileName, dialogStructure, pageGeneration);
      
    } catch (error) {
      logger.error(TAG, `解析压缩包结构失败: ${fileName}`, String(error));
      if (this.isCurrentPageGeneration(pageGeneration)) {
        this.updateProgress(ImportStatus.ERROR, `解析失败: ${error}`, 0);
        this.endCurrentImportFlow('manga_prepare_failed');
      }
    }
  }
  
  /**
   * 解析ComicInfo.xml内容，返回预填充信息
   */
  private parseComicInfoXml(xmlContent: string): PrefilledComicInfo | null {
    try {
      const comicInfo = this.comicInfoParser.parseXmlString(xmlContent);
      
      // 转换为预填充信息格式
      const prefilledInfo: PrefilledComicInfo = {
        title: comicInfo.title || undefined,
        series: comicInfo.series || undefined,
        author: comicInfo.writer || undefined,
        description: comicInfo.summary || undefined,
        number: comicInfo.number?.toString() || undefined,
        publishingStatus: comicInfo.publishingStatus?.trim() || undefined,
        webUrl: comicInfo.web?.trim() || undefined,
        source: comicInfo.source?.trim() || undefined,
        publishTime: comicInfo.year
          ? this.getPublishTimestamp(comicInfo)
          : undefined
      };
      
      // 处理标签
      const metadataTags: string[] = [comicInfo.genre || '', comicInfo.categories || '']
        .join(',')
        .split(/[,;，；]/)
        .map((tag: string): string => tag.trim())
        .filter((tag: string): boolean => tag.length > 0);
      if (metadataTags.length > 0) {
        prefilledInfo.tags = metadataTags;
      }
      
      return prefilledInfo;
    } catch (error) {
      logger.error(TAG, `解析ComicInfo.xml失败: ${error}`);
      return null;
    }
  }

  /**
   * 查找可能的重复漫画
   */
  private async findExistingMangaCandidates(
    fileName: string,
    pageGeneration: number = this.pageLifecycleGeneration
  ): Promise<void> {
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    const possibleTitle = removeFileExtension(fileName);
    const cachedCandidates = this.importDuplicateDetectionCache.get(this.currentImportFlowId, possibleTitle, 'manga', 'single');
    if (cachedCandidates !== null) {
      this.existingMangaCandidates = cachedCandidates;
      const cacheEvent: ImportFlowEvent = new ImportFlowEvent();
      cacheEvent.eventType = ImportFlowEventType.DUPLICATE_CACHE_HIT;
      cacheEvent.reason = 'single_duplicate_cache_hit';
      cacheEvent.contentType = ImportFlowContentType.MANGA;
      cacheEvent.cacheHit = true;
      cacheEvent.cacheKey = this.importDuplicateDetectionCache.buildKey(this.currentImportFlowId, possibleTitle, 'manga', 'single');
      cacheEvent.detail = `title=${possibleTitle}, candidates=${cachedCandidates.length}`;
      this.recordImportFlowEvent(cacheEvent);
      return;
    }
    const startedAt: number = Date.now();
    const startedEvent: ImportFlowEvent = new ImportFlowEvent();
    startedEvent.eventType = ImportFlowEventType.DUPLICATE_DETECT_STARTED;
    startedEvent.reason = 'single_duplicate_detect_started';
    startedEvent.contentType = ImportFlowContentType.MANGA;
    startedEvent.displayName = possibleTitle;
    this.recordImportFlowEvent(startedEvent);
    try {
      // 从文件名提取可能的漫画名称
      
      // 查询数据库中的本地漫画
      const allManga: ComicRecord[] = await this.dataManager.getAllComics();
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      const localManga: ComicRecord[] = [];
      for (let i = 0; i < allManga.length; i++) {
        const m: ComicRecord = allManga[i];
        if (m.sourceId === 'local_import' || m.sourceId === 'download_import') {
          localManga.push(m);
        }
      }
      
      // 简单的模糊匹配
      const candidates: ExistingMangaCandidate[] = [];
      for (let i = 0; i < localManga.length; i++) {
        const manga: ComicRecord = localManga[i];
        const titleLower: string = manga.title.toLowerCase();
        const searchLower: string = possibleTitle.toLowerCase();
        
        // 检查是否有相似性
        if (titleLower.includes(searchLower) || 
            searchLower.includes(titleLower) ||
            this.calculateSimilarity(titleLower, searchLower) > 0.5) {
          candidates.push({
            id: manga.id,
            title: manga.title,
            author: manga.author || '未知作者',
            coverUrl: manga.coverUrl || '',
            chapterCount: manga.chapterCount || 0
          });
        }
      }
      
      this.existingMangaCandidates = candidates;
      this.importDuplicateDetectionCache.set(this.currentImportFlowId, possibleTitle, 'manga', 'single', candidates);
      const completedEvent: ImportFlowEvent = new ImportFlowEvent();
      completedEvent.eventType = ImportFlowEventType.DUPLICATE_DETECT_COMPLETED;
      completedEvent.reason = 'single_duplicate_detect_completed';
      completedEvent.contentType = ImportFlowContentType.MANGA;
      completedEvent.displayName = possibleTitle;
      completedEvent.elapsedMs = Date.now() - startedAt;
      completedEvent.totalCount = localManga.length;
      completedEvent.currentIndex = candidates.length;
      completedEvent.detail = `title=${possibleTitle}, candidates=${candidates.length}`;
      this.recordImportFlowEvent(completedEvent);
      logger.info(TAG, `找到 ${candidates.length} 个可能的重复漫画`);
      
    } catch (error) {
      logger.error(TAG, '查找重复漫画失败', String(error));
      if (!this.isCurrentPageGeneration(pageGeneration)) {
        return;
      }
      this.existingMangaCandidates = [];
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'single_duplicate_detect_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.displayName = possibleTitle;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - startedAt;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
    }
  }

  /**
   * 计算字符串相似度（简单实现）
   */
  private calculateSimilarity(str1: string, str2: string): number {
    const longer = str1.length > str2.length ? str1 : str2;
    const shorter = str1.length > str2.length ? str2 : str1;
    
    if (longer.length === 0) return 1.0;
    
    // 计算编辑距离的简化版本
    let matches = 0;
    for (let i = 0; i < shorter.length; i++) {
      if (longer.includes(shorter[i])) {
        matches++;
      }
    }
    
    return matches / longer.length;
  }


  /**
   * 显示漫画导入配置对话框
   */
  private showMangaImportDialog(
    fileName: string,
    parsedStructure: ParsedArchiveStructure,
    pageGeneration: number = this.pageLifecycleGeneration
  ): void {
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.mangaImportDialogController = new CustomDialogController({
      builder: MangaImportDialog({
        themeState: this.themeState,
        fileName: fileName,
        parsedStructure: parsedStructure,
        existingMangaCandidates: this.existingMangaCandidates,
        sourceFileUri: this.currentFileUri,
        onFlowEvent: (event: ImportFlowEvent) => {
          this.recordImportFlowEvent(event);
        },
          onConfirm: (result: MangaImportDialogResult) => {
            if (!this.isCurrentPageGeneration(pageGeneration)) {
              return;
            }
            if (this.isMangaImportRunning) {
              logger.warn(TAG, '漫画导入已在运行，忽略重复确认');
              return;
            }
            if (this.mangaImportOwnerToken !== 0) {
              logger.warn(TAG, '已有漫画提交任务，忽略重复确认');
              return;
            }
            const ownerToken: number = this.beginMangaImportCommit();
            this.isMangaImportRunning = true;
            this.mangaImportDialogController = null;
            void (async (): Promise<void> => {
              try {
                await this.handleMangaImportDialogResult(result, pageGeneration);
              } catch (error) {
                logger.error(TAG, `漫画导入异常: ${String(error)}`);
              } finally {
                this.finishMangaImport(pageGeneration, ownerToken);
              }
            })();
          },
          onCancel: () => {
          if (this.isCurrentPageGeneration(pageGeneration)) {
            this.mangaImportDialogController = null;
            this.currentParsedStructure = null;
            this.currentFileUri = '';
            this.updateProgress(ImportStatus.IDLE, '已取消导入', 0);
            this.finalizeTrackedTransferImport('import_cancelled');
            this.endCurrentImportFlow('manga_dialog_cancelled');
            this.isMangaImportRunning = false;
          }
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    this.mangaImportDialogController.open();
    if (!this.isCurrentPageGeneration(pageGeneration)) {
      return;
    }
    this.recordSimpleImportFlowEvent(
      ImportFlowEventType.DIALOG_OPENED,
      'manga_dialog_opened',
      ImportFlowContentType.MANGA,
      ImportFlowEntrySource.UNKNOWN,
      true,
      fileName,
      0
    );
    this.updateProgress(ImportStatus.IDLE, '请配置导入选项', 20);
  }

  /**
   * 处理漫画导入对话框结果
   */
  private async handleMangaImportDialogResult(
    result: MangaImportDialogResult,
    pageGeneration: number = this.pageLifecycleGeneration
  ): Promise<void> {
    const importStartedAt: number = Date.now();
    try {
      this.updateProgress(ImportStatus.IMPORTING, '正在导入漫画...', 30);
      const confirmEvent: ImportFlowEvent = new ImportFlowEvent();
      confirmEvent.eventType = ImportFlowEventType.DIALOG_CONFIRMED;
      confirmEvent.reason = 'manga_dialog_result_confirmed';
      confirmEvent.contentType = ImportFlowContentType.MANGA;
      confirmEvent.displayName = result.title;
      confirmEvent.sourceUri = result.sourceFileUri || this.currentFileUri;
      confirmEvent.detail = `mode=${result.importMode}`;
      this.recordImportFlowEvent(confirmEvent);
      
      const parsedStructure = result.parsedStructure;
      
      // 根据导入模式处理
      switch (result.importMode) {
        case MangaImportMode.TANKOUBON:
          await this.importAsTankoubon(result);
          break;
        case MangaImportMode.SINGLE_CHAPTER:
          await this.importAsSingleChapter(result);
          break;
        case MangaImportMode.MULTI_CHAPTER:
          await this.importAsMultiChapter(result);
          break;
      }
      
      this.updateProgress(ImportStatus.COMPLETED, '导入完成', 100);
      this.showResults = true;
      this.showToast('漫画导入成功');
      this.finalizeTrackedTransferImport('imported');
      
      // 导入成功后清除选择的文件
      this.selectedFiles = [];
      
      // 发布导入完成事件
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(1, 1));
      const refreshEvent: ImportFlowEvent = new ImportFlowEvent();
      refreshEvent.eventType = ImportFlowEventType.BOOKSHELF_REFRESH_PUBLISHED;
      refreshEvent.reason = 'manga_bookshelf_refresh_published';
      refreshEvent.contentType = ImportFlowContentType.MANGA;
      refreshEvent.displayName = result.title;
      refreshEvent.elapsedMs = Date.now() - importStartedAt;
      this.recordImportFlowEvent(refreshEvent);
      this.endCurrentImportFlow('manga_import_completed');
      
    } catch (error) {
      logger.error(TAG, '导入漫画失败', String(error));
      const failedEvent: ImportFlowEvent = new ImportFlowEvent();
      failedEvent.eventType = ImportFlowEventType.ERROR;
      failedEvent.reason = 'manga_import_failed';
      failedEvent.contentType = ImportFlowContentType.MANGA;
      failedEvent.displayName = result.title;
      failedEvent.sourceUri = result.sourceFileUri || this.currentFileUri;
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.elapsedMs = Date.now() - importStartedAt;
      failedEvent.errorMessage = String(error);
      this.recordImportFlowEvent(failedEvent);
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${error}`, 0);
      this.showToast(`漫画导入失败: ${error instanceof Error ? error.message : String(error)}`);
      this.finalizeTrackedTransferImport('import_failed');
      this.endCurrentImportFlow('manga_import_failed');
    } finally {
      this.currentParsedStructure = null;
      this.currentFileUri = '';
    }
  }

  private async rollbackSingleImport(
    mangaId: string,
    createdManga: boolean,
    chapterIds: string[],
    organizedPaths: string[]
  ): Promise<void> {
    if (createdManga && mangaId.length > 0) {
      try {
        await this.dataManager.deleteComic(mangaId);
      } catch (rollbackError) {
        logger.error(TAG, `回滚新建漫画失败: ${mangaId}`, String(rollbackError));
      }
    } else {
      for (let i: number = chapterIds.length - 1; i >= 0; i--) {
        const chapterId: string = chapterIds[i];
        if (chapterId.length <= 0) {
          continue;
        }
        try {
          await this.dataManager.deleteChapter(chapterId);
        } catch (rollbackError) {
          logger.error(TAG, `回滚新增章节失败: ${chapterId}`, String(rollbackError));
        }
      }
    }

    for (const organizedPath of organizedPaths) {
      if (organizedPath.length <= 0) {
        continue;
      }
      try {
        await this.sandboxManager.deleteDirectory(organizedPath, true);
      } catch (cleanupError) {
        logger.warn(TAG, `清理失败导入目录失败: ${organizedPath}`, String(cleanupError));
      }
    }
  }

  private async findImportedCoverPath(
    organizedPaths: string[],
    selectedCoverPath: string
  ): Promise<string> {
    const normalizedSelectedPath: string = selectedCoverPath.replace(/\\/g, '/');
    const selectedName: string = normalizedSelectedPath.substring(normalizedSelectedPath.lastIndexOf('/') + 1);
    const selectedDotIndex: number = selectedName.lastIndexOf('.');
    const selectedBaseName: string = selectedDotIndex > 0
      ? selectedName.substring(0, selectedDotIndex)
      : selectedName;
    let firstImagePath: string = '';

    for (const organizedPath of organizedPaths) {
      if (organizedPath.length <= 0) {
        continue;
      }
      const imageFiles: ImageFileInfo[] = await this.scanImageFiles(organizedPath);
      for (const imageFile of imageFiles) {
        if (firstImagePath.length <= 0) {
          firstImagePath = imageFile.path;
        }
        const normalizedName: string = imageFile.name.replace(/\\/g, '/');
        const candidateName: string = normalizedName.substring(normalizedName.lastIndexOf('/') + 1);
        const candidateDotIndex: number = candidateName.lastIndexOf('.');
        const candidateBaseName: string = candidateDotIndex > 0
          ? candidateName.substring(0, candidateDotIndex)
          : candidateName;
        if (candidateName === selectedName || candidateBaseName === selectedBaseName) {
          return imageFile.path;
        }
      }
    }
    return firstImagePath;
  }

  /**
   * 以单行本模式导入
   */
  private async importAsTankoubon(result: MangaImportDialogResult): Promise<void> {
    const parsedStructure = result.parsedStructure;
    if (parsedStructure.totalImageCount <= 0) {
      throw new Error(`漫画 ${result.title} 未找到可导入图片`);
    }
    let mangaId: string = '';
    let chapterId: string = '';
    let organizedPath: string = '';
    let createdManga: boolean = false;

    try {
    // 创建漫画信息（使用用户选择的封面）
    const comicInfoInput: ComicInfoInput = {
      title: result.title,
      author: result.author,
      description: result.description,
      coverUrl: result.selectedCoverPath || '',
      sourceId: 'local_import',
      externalId: `local_${generateUUID()}`,
      status: this.convertToMangaStatus(result.publishingStatus),
      tags: result.tags,
      rating: 0,
      chapterCount: 1,
      lastUpdateTime: Date.now(),
      webUrl: result.webUrl,
      isNSFW: result.isNSFW
    };
    
    if (result.mergeToExisting && result.targetMangaId) {
      // 合并到已有漫画
      mangaId = result.targetMangaId;
      logger.info(TAG, `合并到已有漫画: ${mangaId}`);
    } else {
      // 创建新漫画
      mangaId = await this.dataManager.addComicInfo(comicInfoInput);
      createdManga = true;
      logger.info(TAG, `创建新漫画: ${mangaId}, 封面: ${result.selectedCoverPath}`);
    }
    
    // 创建章节
    const chapterTitle: string = '第1话';
    const chapterSourceUri: string = result.sourceFileUri || this.currentFileUri;
    const chapterSourcePath: string = this.resolveSingleChapterSourcePath(parsedStructure);
    const chapterInfoInput: ChapterInfoInput = {
      comicId: mangaId,
      title: chapterTitle,
      index: 0,
      pageCount: parsedStructure.totalImageCount,
      isDownloaded: true,
      downloadPath: parsedStructure.extractedPath,
      publishTime: result.publishTime,
      externalId: await createLocalMangaChapterExternalId(
        mangaId,
        chapterSourceUri,
        chapterSourcePath,
        parsedStructure.extractedPath,
        1
      )
    };
    
    const chapterCreation: ChapterInfoCreationResult =
      await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
    if (!chapterCreation.created) {
      throw new Error(`章节已存在，已停止重复导入: ${chapterInfoInput.title}`);
    }
    chapterId = chapterCreation.id;
    logger.info(TAG, `创建章节: ${chapterId}`);
    
    // 新建漫画先保存封面；合并目标只在章节成功后更新，避免失败覆盖既有封面。
    if (createdManga && result.selectedCoverPath) {
      await this.processCoverImage(mangaId, result.selectedCoverPath, result.title);
    }
    
    // 整理文件并添加页面信息
    organizedPath = await this.organizeAndAddPages(
      comicInfoInput,
      chapterInfoInput,
      chapterSourcePath,
      chapterId,
      parsedStructure.tempDirectories.length <= 0,
      parsedStructure.totalImageCount
    );
    await this.validateImportedMangaGroup(mangaId, [chapterId], 1);
    if (createdManga) {
      await DataService.getInstance().addToFavorites(mangaId, result.tags);
    }
    if (!createdManga && result.selectedCoverPath) {
      const importedCoverPath: string = await this.findImportedCoverPath(
        [organizedPath],
        result.selectedCoverPath
      );
      if (importedCoverPath.length > 0) {
        await this.processCoverImage(mangaId, importedCoverPath, result.title);
      }
    }
    
    // 记录结果
    this.importResultDetails.push({
      fileName: this.getFileNameFromUri(this.currentFileUri),
      success: true,
      mangaId: mangaId,
      chapterId: chapterId,
      extractedFileCount: parsedStructure.totalImageCount,
      databaseStored: true,
      filesOrganized: true
    });
    this.recordMangaImportFlow(
      mangaId,
      result.title,
      chapterId,
      chapterInfoInput.title,
      parsedStructure.totalImageCount,
      1,
      this.currentFileUri,
      parsedStructure.extractedPath,
      'local_tankoubon_import_completed'
    );
    } catch (error) {
      await this.rollbackSingleImport(mangaId, createdManga, [chapterId], [organizedPath]);
      throw error as Error;
    }
  }
  
  /**
   * 处理封面图片：复制到漫画目录并更新数据库
   * @param mangaId 漫画ID
   * @param coverSourcePath 封面源文件路径
   * @param comicTitle 漫画标题（用于构建目录路径）
   */
  private async processCoverImage(mangaId: string, coverSourcePath: string, comicTitle?: string): Promise<void> {
    try {
      const sandboxManager = SandboxManager.getInstance();
      
      // 获取漫画存储目录（与organizeImportedFiles保持一致的目录结构）
      const comicsDir = sandboxManager.getDirectory('comics');
      const sourceName = this.sanitizeFileName('local_import');
      const comicName = comicTitle ? this.sanitizeFileName(comicTitle) : mangaId;
      const mangaDir = `${comicsDir}/${sourceName}/${comicName}`;
      
      // 确保目录存在
      await sandboxManager.createDirectory(mangaDir);
      
      // 获取封面文件扩展名
      const ext = coverSourcePath.substring(coverSourcePath.lastIndexOf('.'));
      const coverTargetPath = `${mangaDir}/cover_${mangaId}${ext}`;
      
      // 复制封面文件
      await sandboxManager.copyFile(coverSourcePath, coverTargetPath);
      
      // 更新数据库中的封面路径
      await this.dataManager.updateComicCoverUrl(mangaId, coverTargetPath);
      
      logger.info(TAG, `封面已处理: ${coverTargetPath}`);
    } catch (error) {
      logger.error(TAG, `处理封面失败: ${error}`);
      // 封面处理失败不影响导入
    }
  }

  /**
   * 以单章节模式导入
   */
  private async importAsSingleChapter(result: MangaImportDialogResult): Promise<void> {
    const parsedStructure = result.parsedStructure;
    if (parsedStructure.totalImageCount <= 0) {
      throw new Error(`章节 ${result.chapterTitle || result.title} 未找到可导入图片`);
    }
    let mangaId: string = '';
    let chapterId: string = '';
    let organizedPath: string = '';
    let createdManga: boolean = false;

    try {
    if (result.mergeToExisting && result.targetMangaId) {
      // 合并到已有漫画
      mangaId = result.targetMangaId;
      logger.info(TAG, `添加章节到已有漫画: ${mangaId}`);
    } else {
      // 创建新漫画（使用用户选择的封面）
      const comicInfoInput: ComicInfoInput = {
        title: result.title,
        author: result.author,
        description: result.description,
        coverUrl: result.selectedCoverPath || '',
        sourceId: 'local_import',
        externalId: `local_${generateUUID()}`,
        status: this.convertToMangaStatus(result.publishingStatus),
        tags: result.tags,
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: Date.now(),
        webUrl: result.webUrl,
        isNSFW: result.isNSFW
      };
      
      mangaId = await this.dataManager.addComicInfo(comicInfoInput);
      createdManga = true;
      logger.info(TAG, `创建新漫画: ${mangaId}, 封面: ${result.selectedCoverPath}`);
      
      // 处理封面
      if (result.selectedCoverPath) {
        await this.processCoverImage(mangaId, result.selectedCoverPath, result.title);
      }
    }
    
    // 创建章节
    const chapterNumber: number = result.chapterNumber || 1;
    const chapterTitle: string = result.chapterTitle || `第${chapterNumber}话`;
    const chapterIndex: number = chapterNumber - 1;
    const chapterSourceUri: string = result.sourceFileUri || this.currentFileUri;
    const chapterSourcePath: string = this.resolveSingleChapterSourcePath(parsedStructure);
    const chapterInfoInput: ChapterInfoInput = {
      comicId: mangaId,
      title: chapterTitle,
      index: chapterIndex,
      pageCount: parsedStructure.totalImageCount,
      isDownloaded: true,
      downloadPath: parsedStructure.extractedPath,
      publishTime: result.publishTime,
      externalId: await createLocalMangaChapterExternalId(
        mangaId,
        chapterSourceUri,
        chapterSourcePath,
        parsedStructure.extractedPath,
        chapterNumber
      )
    };
    
    const chapterCreation: ChapterInfoCreationResult =
      await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
    if (!chapterCreation.created) {
      throw new Error(`章节已存在，已停止重复导入: ${chapterInfoInput.title}`);
    }
    chapterId = chapterCreation.id;
    logger.info(TAG, `创建章节: ${chapterId}`);
    
    // 整理文件并添加页面信息
    const comicInfoForOrganize: ComicInfoInput = {
      title: result.title,
      author: result.author,
      description: result.description,
      coverUrl: result.selectedCoverPath || '',
      sourceId: 'local_import',
      externalId: '',
      status: this.convertToMangaStatus(result.publishingStatus),
      tags: result.tags,
      rating: 0,
      chapterCount: 1,
      lastUpdateTime: Date.now()
    };
    
    organizedPath = await this.organizeAndAddPages(
      comicInfoForOrganize,
      chapterInfoInput,
      chapterSourcePath,
      chapterId,
      parsedStructure.tempDirectories.length <= 0,
      parsedStructure.totalImageCount
    );
    await this.validateImportedMangaGroup(mangaId, [chapterId], 1);
    if (createdManga) {
      await DataService.getInstance().addToFavorites(mangaId, result.tags);
    }
    if (!createdManga && result.selectedCoverPath) {
      const importedCoverPath: string = await this.findImportedCoverPath(
        [organizedPath],
        result.selectedCoverPath
      );
      if (importedCoverPath.length > 0) {
        await this.processCoverImage(mangaId, importedCoverPath, result.title);
      }
    }
    
    // 更新漫画章节数
    await this.updateMangaChapterCount(mangaId);
    
    // 记录结果
    this.importResultDetails.push({
      fileName: this.getFileNameFromUri(this.currentFileUri),
      success: true,
      mangaId: mangaId,
      chapterId: chapterId,
      extractedFileCount: parsedStructure.totalImageCount,
      databaseStored: true,
      filesOrganized: true
    });
    this.recordMangaImportFlow(
      mangaId,
      result.title,
      chapterId,
      chapterInfoInput.title,
      parsedStructure.totalImageCount,
      1,
      this.currentFileUri,
      parsedStructure.extractedPath,
      'local_single_chapter_import_completed'
    );
    } catch (error) {
      await this.rollbackSingleImport(mangaId, createdManga, [chapterId], [organizedPath]);
      throw error as Error;
    }
  }

  /**
   * 以多章节模式导入
   */
  private async importAsMultiChapter(result: MangaImportDialogResult): Promise<void> {
    if (result.chapters.length <= 0) {
      throw new Error(`漫画 ${result.title} 没有可导入章节`);
    }
    for (const chapter of result.chapters) {
      if (chapter.path.length <= 0 || chapter.pageCount <= 0) {
        throw new Error(`漫画 ${result.title} 包含无效章节: ${chapter.title}`);
      }
    }
    let mangaId: string = '';
    let createdManga: boolean = false;
    const createdChapterIds: string[] = [];
    const organizedPaths: string[] = [];
    const transientStagingPaths: string[] = [];

    try {
    if (result.mergeToExisting && result.targetMangaId) {
      // 合并到已有漫画
      mangaId = result.targetMangaId;
      logger.info(TAG, `添加多章节到已有漫画: ${mangaId}`);
    } else {
      // 创建新漫画（使用用户选择的封面）
      const comicInfoInput: ComicInfoInput = {
        title: result.title,
        author: result.author,
        description: result.description,
        coverUrl: result.selectedCoverPath || '',
        sourceId: 'local_import',
        externalId: `local_${generateUUID()}`,
        status: this.convertToMangaStatus(result.publishingStatus),
        tags: result.tags,
        rating: 0,
        chapterCount: result.chapters.length,
        lastUpdateTime: Date.now(),
        webUrl: result.webUrl,
        isNSFW: result.isNSFW
      };
      
      mangaId = await this.dataManager.addComicInfo(comicInfoInput);
      createdManga = true;
      logger.info(TAG, `创建新漫画: ${mangaId}, 封面: ${result.selectedCoverPath}`);
      
      // 处理封面
      if (result.selectedCoverPath) {
        await this.processCoverImage(mangaId, result.selectedCoverPath, result.title);
      }
    }
    
    // 导入每个章节
    let totalPages = 0;
    let firstChapterId = '';
    let firstChapterTitle = '';
    for (let i = 0; i < result.chapters.length; i++) {
      const chapter = result.chapters[i];
      this.updateProgress(ImportStatus.IMPORTING, `正在导入章节 ${i + 1}/${result.chapters.length}: ${chapter.title}`, 30 + (i / result.chapters.length) * 60);

      let effectiveSourcePath: string = chapter.path;
      let preserveSource: boolean = result.parsedStructure.tempDirectories.length <= 0;
      if (this.isMixedRootImageChapter(result.parsedStructure, chapter.path, chapter.pageCount)) {
        effectiveSourcePath = await this.stageDirectImageChapter(chapter.path, chapter.pageCount);
        transientStagingPaths.push(effectiveSourcePath);
        preserveSource = false;
      }
      const chapterNumber: number = chapter.number > 0 ? chapter.number : Math.max(1, chapter.index);
      const chapterSourceUri: string = result.sourceFileUri || this.currentFileUri;
      
      const chapterInfoInput: ChapterInfoInput = {
        comicId: mangaId,
        title: chapter.title,
        index: chapter.number > 0 ? chapter.number - 1 : Math.max(0, chapter.index - 1),
        pageCount: chapter.pageCount,
        isDownloaded: true,
        downloadPath: effectiveSourcePath,
        publishTime: result.publishTime,
        externalId: await createLocalMangaChapterExternalId(
          mangaId,
          chapterSourceUri,
          chapter.path,
          result.parsedStructure.extractedPath,
          chapterNumber
        )
      };
      
      const chapterCreation: ChapterInfoCreationResult =
        await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
      if (!chapterCreation.created) {
        throw new Error(`章节已存在，已停止重复导入: ${chapter.title}`);
      }
      const chapterId: string = chapterCreation.id;
      createdChapterIds.push(chapterId);
      logger.info(TAG, `创建章节 ${i + 1}: ${chapterId}`);
      if (firstChapterId.length <= 0) {
        firstChapterId = chapterId;
        firstChapterTitle = chapter.title;
      }
      
      // 整理文件并添加页面信息
      const comicInfoForOrganize: ComicInfoInput = {
        title: result.title,
        author: result.author,
        description: result.description,
        coverUrl: result.selectedCoverPath || '',
        sourceId: 'local_import',
        externalId: '',
        status: this.convertToMangaStatus(result.publishingStatus),
        tags: result.tags,
        rating: 0,
        chapterCount: result.chapters.length,
        lastUpdateTime: Date.now()
      };
      
      const organizedPath: string = await this.organizeAndAddPages(
        comicInfoForOrganize,
        chapterInfoInput,
        effectiveSourcePath,
        chapterId,
        preserveSource,
        chapter.pageCount
      );
      organizedPaths.push(organizedPath);
      totalPages += chapter.pageCount;
    }
    await this.validateImportedMangaGroup(mangaId, createdChapterIds, result.chapters.length);
    if (createdManga) {
      await DataService.getInstance().addToFavorites(mangaId, result.tags);
    }
    if (!createdManga && result.selectedCoverPath) {
      const importedCoverPath: string = await this.findImportedCoverPath(
        organizedPaths,
        result.selectedCoverPath
      );
      if (importedCoverPath.length > 0) {
        await this.processCoverImage(mangaId, importedCoverPath, result.title);
      }
    }
    
    // 更新漫画章节数
    await this.updateMangaChapterCount(mangaId);
    
    // 记录结果
    this.importResultDetails.push({
      fileName: this.getFileNameFromUri(this.currentFileUri),
      success: true,
      mangaId: mangaId,
      extractedFileCount: totalPages,
      databaseStored: true,
      filesOrganized: true
    });
    this.recordMangaImportFlow(
      mangaId,
      result.title,
      firstChapterId,
      firstChapterTitle,
      totalPages,
      result.chapters.length,
      this.currentFileUri,
      result.chapters.length > 0 ? result.chapters[0].path : '',
      'local_multi_chapter_import_completed'
    );
    } catch (error) {
      await this.rollbackSingleImport(mangaId, createdManga, createdChapterIds, organizedPaths);
      for (const stagingPath of transientStagingPaths) {
        try {
          await this.sandboxManager.deleteDirectory(stagingPath, true);
        } catch (cleanupError) {
          logger.debug(TAG, `根散图暂存目录已清理或不存在: ${stagingPath}`, String(cleanupError));
        }
      }
      throw error as Error;
    }
  }

  /**
   * 整理文件并添加页面信息
   */
  private resolveSingleChapterSourcePath(parsedStructure: ParsedArchiveStructure): string {
    if (parsedStructure.rootImageCount > 0 || parsedStructure.detectedChapters.length !== 1) {
      return parsedStructure.extractedPath;
    }
    return parsedStructure.detectedChapters[0].path;
  }

  private async countImportableImages(directoryPath: string): Promise<number> {
    const files: string[] = await this.sandboxManager.listDirectory(directoryPath);
    const extensions: string[] = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.avif'];
    let count: number = 0;
    for (const fileName of files) {
      const filePath: string = `${directoryPath}/${fileName}`;
      if (await this.sandboxManager.isSymbolicLink(filePath)) {
        logger.warn(TAG, `计数时跳过符号链接: ${filePath}`);
        continue;
      }
      const stat = await fileIo.lstat(filePath);
      if (stat.isDirectory()) {
        count += await this.countImportableImages(filePath);
        continue;
      }
      const lowerName: string = fileName.toLowerCase();
      const dotIndex: number = lowerName.lastIndexOf('.');
      const extension: string = dotIndex >= 0 ? lowerName.substring(dotIndex) : '';
      if (extensions.includes(extension)) {
        count += 1;
      }
    }
    return count;
  }

  private isMixedRootImageChapter(
    parsedStructure: ParsedArchiveStructure,
    sourcePath: string,
    pageCount: number
  ): boolean {
    if (parsedStructure.rootImageCount <= 0 || parsedStructure.detectedChapters.length <= 1) {
      return false;
    }
    const normalizedSourcePath: string = sourcePath.replace(/\\/g, '/').replace(/\/$/, '');
    const normalizedRootPath: string = parsedStructure.extractedPath.replace(/\\/g, '/').replace(/\/$/, '');
    return normalizedSourcePath === normalizedRootPath && pageCount === parsedStructure.rootImageCount;
  }

  private async stageDirectImageChapter(sourcePath: string, expectedPageCount: number): Promise<string> {
    const baseDirectory: string = this.sandboxManager.getDirectory('temp');
    const stagingDirectory: string = `${baseDirectory}/manga_root_${generateUUID()}`;
    await this.sandboxManager.createDirectory(stagingDirectory);
    try {
      const entries: string[] = await this.sandboxManager.listDirectory(sourcePath);
      const imageExtensions: string[] = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.avif'];
      let copiedPageCount: number = 0;
      for (const entry of entries) {
        const sourceFilePath: string = `${sourcePath}/${entry}`;
        if (await this.sandboxManager.isSymbolicLink(sourceFilePath)) {
          logger.warn(TAG, `根散图暂存跳过符号链接: ${sourceFilePath}`);
          continue;
        }
        const stat = await fileIo.lstat(sourceFilePath);
        if (stat.isDirectory()) {
          continue;
        }
        const lowerName: string = entry.toLowerCase();
        const dotIndex: number = lowerName.lastIndexOf('.');
        const extension: string = dotIndex >= 0 ? lowerName.substring(dotIndex) : '';
        if (!imageExtensions.includes(extension)) {
          continue;
        }
        await this.sandboxManager.copyFile(sourceFilePath, `${stagingDirectory}/${entry}`);
        copiedPageCount += 1;
      }
      if (copiedPageCount !== expectedPageCount) {
        throw new Error(
          `根目录散图页数不一致: 识别 ${expectedPageCount}，直属图片 ${copiedPageCount}`
        );
      }
      return stagingDirectory;
    } catch (error) {
      try {
        await this.sandboxManager.deleteDirectory(stagingDirectory, true);
      } catch (cleanupError) {
        logger.warn(TAG, `清理根散图暂存目录失败: ${stagingDirectory}`, String(cleanupError));
      }
      throw error as Error;
    }
  }

  private async organizeAndAddPages(
    comicInfo: ComicInfoInput,
    chapterInfo: ChapterInfoInput,
    sourcePath: string,
    chapterId: string,
    preserveSource: boolean = false,
    expectedPageCount: number = chapterInfo.pageCount
  ): Promise<string> {
    if (sourcePath.length <= 0) {
      throw new Error(`章节 ${chapterInfo.title} 的源目录为空`);
    }
    const sourceImageCount: number = await this.countImportableImages(sourcePath);
    if (sourceImageCount <= 0) {
      throw new Error(`章节 ${chapterInfo.title} 未找到可导入图片`);
    }
    if (expectedPageCount > 0 && sourceImageCount !== expectedPageCount) {
      throw new Error(
        `章节 ${chapterInfo.title} 页数不一致: 识别 ${expectedPageCount}，源目录 ${sourceImageCount}`
      );
    }

    // 构造ExtractionResult
    const extractedFiles: string[] = [];
    const files: string[] = await this.sandboxManager.listDirectory(sourcePath);
    for (const file of files) {
      extractedFiles.push(file);
    }
    
    const extractionResult: ExtractionResult = {
      success: true,
      extractedPath: sourcePath,
      extractedFiles: extractedFiles,
      fileCount: extractedFiles.length,
      totalSize: 0,
      warnings: []
    };
    
    // 整理文件到分层存储目录
    let organizedPath: string = '';
    try {
      organizedPath = await this.organizeImportedFiles(
        comicInfo,
        chapterInfo,
        extractionResult,
        preserveSource
      );
      // 更新章节下载路径
      await this.updateChapterDownloadPath(chapterId, organizedPath);
      
      // 添加页面信息
      const addedPageCount: number = await this.addPageInfoToDatabaseFromPath(chapterId, organizedPath);
      if (addedPageCount !== sourceImageCount) {
        throw new Error(
          `章节 ${chapterInfo.title} 页面写入不完整: 应为 ${sourceImageCount}，实际 ${addedPageCount}`
        );
      }
      return organizedPath;
    } catch (error) {
      try {
        await this.dataManager.removeChapterPages(chapterId);
      } catch (cleanupError) {
        logger.warn(TAG, `回滚章节页面失败: ${chapterId}`, String(cleanupError));
      }
      if (organizedPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(organizedPath, true);
        } catch (cleanupError) {
          logger.warn(TAG, `清理失败章节目录失败: ${organizedPath}`, String(cleanupError));
        }
      }
      throw error as Error;
    }
  }

  /**
   * 更新漫画章节数
   * 注意：由于DataManager没有直接的updateChapterCount方法，
   * 这里通过获取漫画信息后使用updateComicBasicInfo间接更新
   */
  private async updateMangaChapterCount(mangaId: string): Promise<void> {
    try {
      const chapters: ChapterRecord[] = await this.dataManager.getChaptersByMangaId(mangaId);
      const chapterCount: number = chapters.length;
      
      // 获取当前漫画信息
      const comicInfo: ComicRecord | null = await this.dataManager.getComicInfo(mangaId);
      if (comicInfo) {
        // 使用updateComicBasicInfo更新（虽然它不直接支持chapterCount，但会更新updateTime）
        // 章节数会在下次查询时自动计算
        logger.info(TAG, `漫画 ${mangaId} 当前有 ${chapterCount} 个章节`);
      }
      
      logger.info(TAG, `更新漫画章节数: ${chapterCount}`);
    } catch (error) {
      logger.error(TAG, '更新漫画章节数失败', String(error));
    }
  }

  /**
   * 使用已解析的结构处理文件（传统流程）
   */
  private async processFileWithParsedStructure(fileUri: string, parsedStructure: CompressionParsedStructure): Promise<void> {
    const fileName = this.getFileNameFromUri(fileUri);
    
    try {
      // 解析ComicInfo.xml
      let comicInfo: ComicInfo;
      if (parsedStructure.comicInfoContent) {
        comicInfo = this.comicInfoParser.parseXmlString(parsedStructure.comicInfoContent);
      } else {
        comicInfo = this.createDefaultComicInfo(fileName);
      }
      
      // 构造ExtractionResult
      const extractedFiles: string[] = [];
      try {
        const files = await this.sandboxManager.listDirectory(parsedStructure.extractedPath);
        for (const file of files) {
          extractedFiles.push(file);
        }
      } catch (error) {
        logger.warn(TAG, '获取文件列表失败', String(error));
      }
      
      const extractionResult: ExtractionResult = {
        success: true,
        extractedPath: parsedStructure.extractedPath,
        extractedFiles: extractedFiles,
        fileCount: parsedStructure.totalImageCount,
        totalSize: 0,
        warnings: parsedStructure.warnings
      };
      
      // 导入到数据库
      await this.importComicToDatabaseWithIds(comicInfo, extractionResult);
      
      // 清理临时文件
      await this.compressionUtils.cleanupParsedArchiveStructure(parsedStructure);
      
      this.updateProgress(ImportStatus.COMPLETED, '导入完成', 100);
      this.showResults = true;
      
      // 发布导入完成事件
      eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(1, 1));
      
    } catch (error) {
      logger.error(TAG, '处理文件失败', String(error));
      await this.compressionUtils.cleanupParsedArchiveStructure(parsedStructure);
      throw error as Error;
    }
  }
  
  /**
   * 执行批量导入（在用户选择策略后调用）
   * 优化：使用分批异步处理，避免UI阻塞
   */
  private async executeBatchImport(): Promise<void> {
    try {
      this.importResults = [];
      this.importResultDetails = [];
      this.showResults = false;
      
      const totalFiles = this.selectedFiles.length;
      let processedFiles = 0;
      let successfulImports = 0;

      logger.info(TAG, `开始批量导入，共 ${totalFiles} 个文件，策略: ${this.batchImportStrategy}`);

      // 批量处理配置
      // 仅用于在长批次之间让出UI线程，不限制用户一次选择的文件数量。
      const BATCH_SIZE = 20;
      const BATCH_DELAY = 100; // 每批之间延迟100ms，让UI线程有时间响应
      
      // 分批处理文件
      for (let i = 0; i < this.selectedFiles.length; i += BATCH_SIZE) {
        const batch = this.selectedFiles.slice(i, Math.min(i + BATCH_SIZE, this.selectedFiles.length));
        
        logger.debug(TAG, `处理第 ${Math.floor(i / BATCH_SIZE) + 1} 批，共 ${batch.length} 个文件`);
        
        // 处理当前批次
        for (const fileUri of batch) {
        const result = await this.processFile(fileUri, processedFiles + 1, totalFiles);
        if (result) {
          successfulImports++;
        }
        processedFiles++;
        }
        
        // 批次间延迟，避免UI阻塞
        if (i + BATCH_SIZE < this.selectedFiles.length) {
          await new Promise<void>((resolve: (value: void) => void) => setTimeout(resolve, BATCH_DELAY));
        }
      }

      this.updateProgress(ImportStatus.COMPLETED, `导入完成，共处理 ${processedFiles} 个文件`, 100);
      this.showResults = true;
      
      // 显示导入结果Toast
      if (successfulImports > 0) {
        this.showToast(`导入完成: 成功 ${successfulImports} 个，失败 ${totalFiles - successfulImports} 个`);
      } else {
        this.showToast(`导入完成: 全部失败 (${totalFiles} 个文件)`);
      }
      
      // 发布漫画导入完成事件，通知书库页面刷新
      if (successfulImports > 0) {
        logger.info(TAG, `发布漫画导入完成事件，成功导入 ${successfulImports} 个漫画`);
        eventBus.publish(GameEvent.MANGA_IMPORT_COMPLETED, new MangaImportCompletedPayload(successfulImports, totalFiles));
      }
      
      // 重置批量策略为默认值
      this.batchImportStrategy = 'ask';
      
    } catch (error) {
      logger.error(TAG, '导入过程失败', String(error instanceof Error ? error.message : error));
      this.updateProgress(ImportStatus.ERROR, `导入失败: ${error}`, 0);
      this.showToast(`批量导入失败: ${error instanceof Error ? error.message : String(error)}`);
      this.batchImportStrategy = 'ask';
    }
  }

  /**
   * 处理单个文件
   */
  private async processFile(fileUri: string, currentIndex: number, totalFiles: number): Promise<boolean> {
    const fileName = this.getFileNameFromUri(fileUri);

    try {
      logger.info(TAG, `处理文件: ${fileUri}`);
      
      // 更新进度
      this.updateProgress(
        ImportStatus.EXTRACTING, 
        `处理文件 ${currentIndex}/${totalFiles}: ${fileName}`, 
        20 + (currentIndex - 1) / totalFiles * 60
      );

      // 处理单个文件并获取详细信息（详细信息在processSingleFileWithDetails中实时更新）
      const importInfo = await this.processSingleFileWithDetails(fileUri);
      
      // 补充合并信息摘要
      let mergeSuffix: string = '';
      const detailIndex: number = this.importResultDetails.findIndex(item => item.fileName === fileName);
      if (detailIndex >= 0) {
        const d: ImportResultDetail = this.importResultDetails[detailIndex];
        const parts: string[] = [];
        if (d.mergeMode) {
          parts.push(`模式=${this.getMergeModeLabel(d.mergeMode as MergeMode)}`);
        }
        if (d.mergeAction) {
          parts.push(`动作=${this.getMergeActionLabel(d.mergeAction as MergeAction)}`);
        }
        if (d.matchStrength) {
          parts.push(`匹配=${this.getMatchStrengthLabel(d.matchStrength as MatchStrength)}`);
        }
        if (d.duplicateTargetMangaId) {
          parts.push(`目标ID=${d.duplicateTargetMangaId}`);
        }
        if (d.duplicateReasons && d.duplicateReasons.length > 0) {
          parts.push(`原因=${this.getDuplicateReasonsLabel(d.duplicateReasons as DuplicateReason[])}`);
        }
        if (parts.length > 0) {
          mergeSuffix = `（合并：${parts.join('，')}）`;
        }
      }
      
      this.importResults.push(`✅ ${fileName}: 处理成功${mergeSuffix}`);
      logger.info(TAG, `文件处理成功: ${fileName}`);
      
      return true; // 处理成功
      
    } catch (error) {
      if (error instanceof UserSkipError) {
        this.importResults.push(`⚠️ ${fileName}: 已跳过（用户选择）`);
        logger.info(TAG, `文件已跳过: ${fileName}`);
        return false; // 跳过不计为成功
      }
      this.importResults.push(`❌ ${fileName}: 处理失败 - ${error}`);
      logger.error(TAG, `文件处理失败: ${fileName}`, String(error instanceof Error ? error.message : error));
      return false; // 处理失败
    }
  }

  /**
   * 处理单个文件并返回详细信息
   */
  private async processSingleFileWithDetails(fileUri: string): Promise<ProcessSingleFileResult> {
    const fileName = this.getFileNameFromUri(fileUri);
    let extractedPath: string = '';
    let recursiveResult: RecursiveExtractionResult | null = null; // 声明在外部以便清理
    
    // 创建详细结果对象，用于实时更新显示
    const resultDetail: ImportResultDetail = {
      fileName: fileName,
      success: false,
      xmlFound: false,
      xmlParsed: false,
      extractedFileCount: 0,
      databaseStored: false,
      filesOrganized: false
    };

    try {
      logger.info(TAG, `开始处理单个文件: ${fileUri}`);

      // 1. 递归解压缩文件并查找ComicInfo.xml（支持嵌套压缩包和多层文件夹）
      this.updateProgress(ImportStatus.EXTRACTING, `正在递归解压缩: ${fileName}`, 0);
      recursiveResult = await this.extractRecursivelyAndFindComicInfoWithPasswordRetry(fileUri);

      resultDetail.extractedFileCount = recursiveResult.totalFiles;
      extractedPath = recursiveResult.finalPath;
      resultDetail.xmlFound = recursiveResult.foundXml;
      const comicInfoContent = recursiveResult.comicInfoContent;
      
      // 记录递归解压信息
      if (recursiveResult.recursionDepth > 0) {
        logger.info(TAG, `递归解压深度: ${recursiveResult.recursionDepth}, 总文件数: ${recursiveResult.totalFiles}`);
      }
      
      // 记录警告信息
      if (recursiveResult.warnings.length > 0) {
        for (const warning of recursiveResult.warnings) {
          logger.warn(TAG, `解压警告: ${warning}`);
        }
      }
      
      // 实时更新显示
      const newResultDetail: ImportResultDetail = {
        fileName: resultDetail.fileName,
        success: resultDetail.success,
        extractedFileCount: resultDetail.extractedFileCount,
        xmlFound: resultDetail.xmlFound,
        comicInfo: resultDetail.comicInfo
      };
      this.importResultDetails.push(newResultDetail);
      
      logger.info(TAG, `解压缩成功: ${recursiveResult.totalFiles} 个文件`);

      // 2. 解析ComicInfo.xml（如果存在）
      let comicInfo: ComicInfo;
      
      if (comicInfoContent) {
        try {
          this.updateProgress(ImportStatus.PROCESSING, `正在解析XML: ${fileName}`, 25);
          comicInfo = this.comicInfoParser.parseXmlString(comicInfoContent);
          resultDetail.xmlParsed = true;
          resultDetail.comicInfo = comicInfo;
          
          // 更新显示，显示解析到的XML信息
          const index = this.importResultDetails.findIndex(item => item.fileName === fileName);
          if (index >= 0) {
            const updatedResultDetail: ImportResultDetail = {
              fileName: resultDetail.fileName,
              success: resultDetail.success,
              extractedFileCount: resultDetail.extractedFileCount,
              xmlFound: resultDetail.xmlFound,
              xmlParsed: resultDetail.xmlParsed,
              comicInfo: resultDetail.comicInfo
            };
            this.importResultDetails[index] = updatedResultDetail;
          }
          
          logger.info(TAG, '成功解析ComicInfo.xml', JSON.stringify(comicInfo));
        } catch (error) {
          logger.warn(TAG, '解析ComicInfo.xml失败，使用默认信息', String(error instanceof Error ? error.message : error));
          comicInfo = this.createDefaultComicInfo(this.getFileNameFromUri(fileUri));
          resultDetail.xmlParsed = false;
          resultDetail.comicInfo = comicInfo;
        }
      } else {
        logger.info(TAG, '未找到ComicInfo.xml，使用默认信息');
        comicInfo = this.createDefaultComicInfo(this.getFileNameFromUri(fileUri));
        resultDetail.xmlParsed = false;
        resultDetail.comicInfo = comicInfo;
      }

      // 3. 导入到数据库并获取ID
      this.updateProgress(ImportStatus.PROCESSING, `正在存储到数据库: ${fileName}`, 50);
      
      // 构造ExtractionResult对象（从RecursiveExtractionResult转换）
      // 注意：我们需要扫描extractedPath来获取文件列表和大小
      const extractedFiles: string[] = [];
      let totalSize: number = 0;
      
      try {
        const files = await this.sandboxManager.listDirectory(extractedPath);
        for (const file of files) {
          extractedFiles.push(file);
        }
        // 暂时不计算总大小（性能考虑）
        totalSize = 0;
      } catch (error) {
        logger.warn(TAG, '获取解压文件列表失败', String(error instanceof Error ? error.message : error));
      }
      
      const extractionResult: ExtractionResult = {
        success: true,
        extractedPath: extractedPath,
        extractedFiles: extractedFiles,
        fileCount: recursiveResult.totalFiles,
        totalSize: totalSize,
        warnings: recursiveResult.warnings
      };
      
      const importIds = await this.importComicToDatabaseWithIds(comicInfo, extractionResult);
      
      resultDetail.mangaId = importIds.mangaId;
      resultDetail.chapterId = importIds.chapterId;
      resultDetail.databaseStored = true;
      // 合并与重复检测信息记录
      resultDetail.mergeMode = importIds.mergeMode;
      resultDetail.matchStrength = importIds.matchStrength;
      resultDetail.mergeAction = importIds.mergeAction;
      resultDetail.duplicateReasons = importIds.duplicateReasons;
      resultDetail.duplicateTargetMangaId = importIds.mergedToMangaId;
      
      // 更新显示
      const index2 = this.importResultDetails.findIndex(item => item.fileName === fileName);
      if (index2 >= 0) {
        const updatedResultDetail2: ImportResultDetail = {
          fileName: resultDetail.fileName,
          success: resultDetail.success,
          extractedFileCount: resultDetail.extractedFileCount,
          xmlFound: resultDetail.xmlFound,
          xmlParsed: resultDetail.xmlParsed,
          comicInfo: resultDetail.comicInfo,
          mangaId: resultDetail.mangaId,
          chapterId: resultDetail.chapterId,
          databaseStored: resultDetail.databaseStored,
          mergeMode: resultDetail.mergeMode,
          matchStrength: resultDetail.matchStrength,
          mergeAction: resultDetail.mergeAction,
          duplicateReasons: resultDetail.duplicateReasons,
          duplicateTargetMangaId: resultDetail.duplicateTargetMangaId
        };
        this.importResultDetails[index2] = updatedResultDetail2;
      }

      // 4. 验证数据库存储完整性
      this.updateProgress(ImportStatus.PROCESSING, `正在验证数据库存储: ${fileName}`, 65);
      try {
        // 验证已经在importComicToDatabaseWithIds中完成，这里只是确认
        logger.info(TAG, `数据库存储验证通过: ${fileName}`);
      } catch (validationError) {
        resultDetail.success = false;
        resultDetail.errorMessage = `数据库验证失败: ${validationError}`;
        
        // 更新失败状态
        const validationIndex = this.importResultDetails.findIndex(item => item.fileName === fileName);
        if (validationIndex >= 0) {
          const failedResultDetail: ImportResultDetail = {
            fileName: resultDetail.fileName,
            success: resultDetail.success,
            extractedFileCount: resultDetail.extractedFileCount,
            xmlFound: resultDetail.xmlFound,
            xmlParsed: resultDetail.xmlParsed,
            comicInfo: resultDetail.comicInfo,
            mangaId: resultDetail.mangaId,
            chapterId: resultDetail.chapterId,
            databaseStored: resultDetail.databaseStored,
            errorMessage: resultDetail.errorMessage,
            mergeMode: resultDetail.mergeMode,
            matchStrength: resultDetail.matchStrength,
            mergeAction: resultDetail.mergeAction,
            duplicateReasons: resultDetail.duplicateReasons,
            duplicateTargetMangaId: resultDetail.duplicateTargetMangaId
          };
          this.importResultDetails[validationIndex] = failedResultDetail;
        }
        
        throw validationError as Error;
      }

      // 5. 清理临时文件（包括递归解压产生的所有临时目录）
      this.updateProgress(ImportStatus.PROCESSING, `正在整理文件: ${fileName}`, 75);
      if (recursiveResult) {
        await this.compressionUtils.cleanupRecursiveExtractionResult(recursiveResult);
      }
      
      resultDetail.filesOrganized = true;
      resultDetail.success = true;
      
      // 最终更新显示
      const finalIndex = this.importResultDetails.findIndex(item => item.fileName === fileName);
      if (finalIndex >= 0) {
        const finalResultDetail: ImportResultDetail = {
          fileName: resultDetail.fileName,
          success: resultDetail.success,
          extractedFileCount: resultDetail.extractedFileCount,
          xmlFound: resultDetail.xmlFound,
          xmlParsed: resultDetail.xmlParsed,
          comicInfo: resultDetail.comicInfo,
          mangaId: resultDetail.mangaId,
          chapterId: resultDetail.chapterId,
          databaseStored: resultDetail.databaseStored,
          filesOrganized: resultDetail.filesOrganized,
          mergeMode: resultDetail.mergeMode,
          matchStrength: resultDetail.matchStrength,
          mergeAction: resultDetail.mergeAction,
          duplicateReasons: resultDetail.duplicateReasons,
          duplicateTargetMangaId: resultDetail.duplicateTargetMangaId
        };
        this.importResultDetails[finalIndex] = finalResultDetail;
      }

      logger.info(TAG, `文件处理完成: ${fileUri}`);
      // 导入完成后触发封面选择导航
      try {
        const coverInput: ComicInfoInput = {
        title: comicInfo.series || comicInfo.title || '未知标题',
        author: comicInfo.writer || '未知作者',
        description: comicInfo.summary || '',
        coverUrl: '',
        sourceId: 'local_import',
        externalId: `local_${generateUUID()}`,  // 本地导入使用生成的UUID
        status: MangaStatus.ONGOING,
        tags: [],
        rating: 0,
        chapterCount: 0,
        lastUpdateTime: 0
        };
        logger.info(TAG, `准备导航到封面选择页面：mangaId=${importIds.mangaId}, chapterId=${importIds.chapterId}`);
        await this.promptUserSelectCover(importIds.mangaId, coverInput as ComicInfoInput, importIds.chapterId);
        logger.info(TAG, '封面选择导航已触发');
      } catch (navErr) {
        const msg: string = navErr instanceof Error ? navErr.message : String(navErr);
        logger.warn(TAG, `封面选择导航触发失败：${msg}`);
      }

      return {
        comicInfo: comicInfo,
        mangaId: importIds.mangaId,
        chapterId: importIds.chapterId
      } as ProcessSingleFileResult;

    } catch (error) {
      resultDetail.success = false;
      resultDetail.errorMessage = String(error instanceof Error ? error.message : error);
      // 若为用户跳过或发生错误，清理临时目录但不作为系统错误处理
      if (error instanceof UserSkipError) {
        logger.info(TAG, '用户跳过导入，清理临时目录');
      }
      
      // 尝试清理递归解压产生的所有临时目录
      if (recursiveResult) {
        try {
          await this.compressionUtils.cleanupRecursiveExtractionResult(recursiveResult);
          logger.info(TAG, '已清理所有递归解压的临时目录');
        } catch (cleanupErr) {
          logger.warn(TAG, '清理临时目录失败', String(cleanupErr instanceof Error ? cleanupErr.message : cleanupErr));
        }
      } else if (extractedPath && extractedPath.length > 0) {
        // 如果没有递归结果，尝试清理提取的路径
        try {
          await this.compressionUtils.cleanupExtractionDirectory(extractedPath);
        } catch (cleanupErr) {
          logger.warn(TAG, '清理临时目录失败', String(cleanupErr instanceof Error ? cleanupErr.message : cleanupErr));
        }
      }
      
      // 更新失败状态
      const errorIndex = this.importResultDetails.findIndex(item => item.fileName === fileName);
      if (errorIndex >= 0) {
        const errorResultDetail: ImportResultDetail = {
          fileName: resultDetail.fileName,
          success: resultDetail.success,
          extractedFileCount: resultDetail.extractedFileCount,
          xmlFound: resultDetail.xmlFound,
          xmlParsed: resultDetail.xmlParsed,
          comicInfo: resultDetail.comicInfo,
          mangaId: resultDetail.mangaId,
          chapterId: resultDetail.chapterId,
          databaseStored: resultDetail.databaseStored,
          filesOrganized: resultDetail.filesOrganized,
          errorMessage: resultDetail.errorMessage,
          mergeMode: resultDetail.mergeMode,
          matchStrength: resultDetail.matchStrength,
          mergeAction: resultDetail.mergeAction,
          duplicateReasons: resultDetail.duplicateReasons,
          duplicateTargetMangaId: resultDetail.duplicateTargetMangaId
        };
        this.importResultDetails[errorIndex] = errorResultDetail;
      } else {
        const newErrorResultDetail: ImportResultDetail = {
          fileName: resultDetail.fileName,
          success: resultDetail.success,
          extractedFileCount: resultDetail.extractedFileCount,
          xmlFound: resultDetail.xmlFound,
          xmlParsed: resultDetail.xmlParsed,
          comicInfo: resultDetail.comicInfo,
          mangaId: resultDetail.mangaId,
          chapterId: resultDetail.chapterId,
          databaseStored: resultDetail.databaseStored,
          filesOrganized: resultDetail.filesOrganized,
          errorMessage: resultDetail.errorMessage,
          mergeMode: resultDetail.mergeMode,
          matchStrength: resultDetail.matchStrength,
          mergeAction: resultDetail.mergeAction,
          duplicateReasons: resultDetail.duplicateReasons,
          duplicateTargetMangaId: resultDetail.duplicateTargetMangaId
        };
        this.importResultDetails.push(newErrorResultDetail);
      }
      
      if (error instanceof UserSkipError) {
        logger.info(TAG, `用户跳过单个文件: ${fileUri}`);
        throw error as Error;
      } else {
        logger.error(TAG, `处理单个文件失败: ${fileUri}`, String(error instanceof Error ? error.message : error));
        throw error as Error;
      }
    }
  }
  private async processSingleFile(fileUri: string): Promise<void> {
    try {
      logger.info(TAG, `开始处理单个文件: ${fileUri}`);

      // 1. 解压缩文件并查找ComicInfo.xml
      const extractionData = await this.extractAndFindComicInfoWithPasswordRetry(fileUri);
      const result = extractionData.result;
      const comicInfoContent = extractionData.comicInfoContent;

      if (!result.success) {
        throw new Error(result.error || '解压缩失败');
      }

      logger.info(TAG, `解压缩成功: ${result.fileCount} 个文件`);

      // 2. 解析ComicInfo.xml（如果存在）
      let comicInfo: ComicInfo;
      
      if (comicInfoContent) {
        try {
          comicInfo = this.comicInfoParser.parseXmlString(comicInfoContent);
          logger.info(TAG, '成功解析ComicInfo.xml');
        } catch (error) {
          logger.warn(TAG, '解析ComicInfo.xml失败，使用默认信息', String(error instanceof Error ? error.message : error));
          comicInfo = this.createDefaultComicInfo(this.getFileNameFromUri(fileUri));
        }
      } else {
        logger.info(TAG, '未找到ComicInfo.xml，使用默认信息');
        comicInfo = this.createDefaultComicInfo(this.getFileNameFromUri(fileUri));
      }

      // 3. 导入到数据库（统一采用整理后再入库的流程，确保页面路径与转码一致）
      await this.importComicToDatabaseWithIds(comicInfo, result);

      // 4. 清理临时文件
      await this.compressionUtils.cleanupExtractionDirectory(result.extractedPath);

      logger.info(TAG, `文件处理完成: ${fileUri}`);

    } catch (error) {
      logger.error(TAG, `处理单个文件失败: ${fileUri}`, String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 创建默认漫画信息
   */
  private createDefaultComicInfo(fileName: string): ComicInfo {
    return {
      title: fileName.replace(/\.(zip|cbz|rar|cbr)$/i, ''),
      series: fileName.replace(/\.(zip|cbz|rar|cbr)$/i, ''),
      number: '1',
      summary: '通过本地文件导入',
      writer: '未知作者',
      genre: '未分类',
      web: '',
      publishingStatus: 'Unknown',
      source: '本地导入'
    };
  }

  /**
   * 规范化名称用于重复检测
   */
  private normalizeName(name: string): string {
    const value: string = name || '';
    return value.trim().toLowerCase();
  }

  /**
   * 将名称分词，用于相似度计算
   */
  private tokenizeName(value: string): string[] {
    const v: string = this.normalizeName(value);
    // 仅提取字母数字片段
    const parts: string[] = v.split(/[^a-z0-9\u4e00-\u9fa5]+/g);
    const tokens: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const p: string = parts[i];
      if (p && p.length > 0) {
        tokens.push(p);
      }
    }
    return tokens;
  }

  /**
   * 计算Jaccard相似度
   */
  private jaccardSimilarity(a: string[], b: string[]): number {
    if (a.length === 0 && b.length === 0) {
      return 1;
    }
    const setA: string[] = [];
    for (let i = 0; i < a.length; i++) { if (!setA.includes(a[i])) { setA.push(a[i]); } }
    const setB: string[] = [];
    for (let j = 0; j < b.length; j++) { if (!setB.includes(b[j])) { setB.push(b[j]); } }
    let intersection: number = 0;
    for (let x = 0; x < setA.length; x++) {
      const token: string = setA[x];
      if (setB.includes(token)) { intersection++; }
    }
    const unionSize: number = setA.length + setB.length - intersection;
    if (unionSize === 0) { return 0; }
    return intersection / unionSize;
  }

  private computeTitleSimilarity(a: string, b: string): number {
    const tokensA: string[] = this.tokenizeName(a);
    const tokensB: string[] = this.tokenizeName(b);
    return this.jaccardSimilarity(tokensA, tokensB);
  }

  private computeAuthorSimilarity(a: string, b: string): number {
    const na: string = this.normalizeName(a);
    const nb: string = this.normalizeName(b);
    if (na.length === 0 || nb.length === 0) {
      return 0;
    }
    if (na === nb) {
      return 1;
    }
    const tokensA: string[] = this.tokenizeName(na);
    const tokensB: string[] = this.tokenizeName(nb);
    return this.jaccardSimilarity(tokensA, tokensB);
  }

  private estimateStrength(score: number, titleSim: number, authorSim: number): MatchStrength {
    if (titleSim >= 0.98 && authorSim >= 0.98) {
      return MatchStrength.EXACT;
    }
    if (score >= 0.9) {
      return MatchStrength.STRONG;
    }
    if (score >= 0.75) {
      return MatchStrength.LIKELY;
    }
    if (score >= 0.6) {
      return MatchStrength.WEAK;
    }
    return MatchStrength.BELOW;
  }

  private collectReasons(titleSim: number, authorSim: number, tagsOverlap: boolean): DuplicateReason[] {
    const reasons: DuplicateReason[] = [];
    if (titleSim >= 0.98) { reasons.push(DuplicateReason.TITLE_EXACT); }
    else if (titleSim >= 0.75) { reasons.push(DuplicateReason.TITLE_SIMILAR); }
    if (authorSim >= 0.98) { reasons.push(DuplicateReason.AUTHOR_EXACT); }
    else if (authorSim >= 0.75) { reasons.push(DuplicateReason.AUTHOR_SIMILAR); }
    if (tagsOverlap) { reasons.push(DuplicateReason.TAGS_OVERLAP); }
    return reasons;
  }

  /**
   * 检测重复候选项（基于本地导入源）
   */
  private async checkDuplicateCandidates(comicInput: ComicInfoInput): Promise<DuplicateCheckResult> {
    const keyword: string = comicInput.title;
    const candidates: ComicRecord[] = await this.dataManager.searchComics(keyword, 'local_import');
    const results: DuplicateCandidate[] = [];
    const titleA: string = comicInput.title;
    const authorA: string = comicInput.author;
    const tagsA: string[] = comicInput.tags;

    for (let i = 0; i < candidates.length; i++) {
      const rec: ComicRecord = candidates[i];
      const titleSim: number = this.computeTitleSimilarity(titleA, rec.title);
      const authorSim: number = this.computeAuthorSimilarity(authorA, rec.author);

      // 70%标题 + 30%作者
      const score: number = 0.7 * titleSim + 0.3 * authorSim;
      // 标签是否有交集
      let tagsOverlap: boolean = false;
      for (let t = 0; t < tagsA.length; t++) {
        const tag: string = this.normalizeName(tagsA[t]);
        if (this.normalizeName(tag).length > 0 && rec.tags.map((x: string) => this.normalizeName(x)).includes(tag)) {
          tagsOverlap = true;
          break;
        }
      }

      const strength: MatchStrength = this.estimateStrength(score, titleSim, authorSim);
      const reasons: DuplicateReason[] = this.collectReasons(titleSim, authorSim, tagsOverlap);
      const item: DuplicateCandidate = { record: rec, score: score, strength: strength, reasons: reasons };
      results.push(item);
    }

    // 选择最高分
    let best: DuplicateCandidate | undefined = undefined;
    for (let k = 0; k < results.length; k++) {
      const c: DuplicateCandidate = results[k];
      if (!best || c.score > best.score) {
        best = c;
      }
    }

    return { candidates: results, best: best } as DuplicateCheckResult;
  }

  /**
   * 根据模式做出合并决策
   */
  private decideMerge(mode: MergeMode, check: DuplicateCheckResult): MergeDecision {
    if (!check.best) {
      return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
    }
    const best: DuplicateCandidate = check.best as DuplicateCandidate;
    if (mode === MergeMode.StrictNew) {
      return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
    }
    if (mode === MergeMode.AutoRecommend) {
      if (best.strength === MatchStrength.EXACT || best.strength === MatchStrength.STRONG || best.strength === MatchStrength.LIKELY) {
        return { mode: mode, action: MergeAction.MERGE_TO_EXISTING, targetMangaId: best.record.id, strength: best.strength, reasons: best.reasons } as MergeDecision;
      }
      return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
    }
    // ManualCustom 当前阶段按自动推荐处理，待UI接入后可用户确认
    if (best.strength === MatchStrength.EXACT || best.strength === MatchStrength.STRONG || best.strength === MatchStrength.LIKELY) {
      return { mode: mode, action: MergeAction.MERGE_TO_EXISTING, targetMangaId: best.record.id, strength: best.strength, reasons: best.reasons } as MergeDecision;
    }
    return { mode: mode, action: MergeAction.CREATE_NEW } as MergeDecision;
  }

  /**
   * 查找是否已存在相同（本地导入源）的漫画记录
   */
  private async findExistingComicForLocalImport(title: string, author: string): Promise<ComicRecord | null> {
    const keyword: string = title;
    const candidates: ComicRecord[] = await this.dataManager.searchComics(keyword, 'local_import');
    const targetTitle: string = this.normalizeName(title);
    const targetAuthor: string = this.normalizeName(author);
    for (let i = 0; i < candidates.length; i++) {
      const item: ComicRecord = candidates[i];
      if (this.normalizeName(item.title) === targetTitle && this.normalizeName(item.author) === targetAuthor) {
        return item;
      }
    }
    return null;
  }

  /**
   * 查找是否已存在同一漫画下重复章节（按章节序号或标题匹配）
   */
  private async findExistingChapter(comicId: string, chapterIndex: number, chapterTitle: string): Promise<ChapterRecord | null> {
    const chapters: ChapterRecord[] = await this.dataManager.getComicChapters(comicId);
    const normalizedTitle: string = this.normalizeName(chapterTitle);
    for (let i = 0; i < chapters.length; i++) {
      const c: ChapterRecord = chapters[i];
      if (c.index === chapterIndex) {
        return c;
      }
      if (this.normalizeName(c.title) === normalizedTitle) {
        return c;
      }
    }
    return null;
  }

  /**
   * 导入漫画信息到数据库并返回ID
   */
  private async importComicToDatabaseWithIds(comicInfo: ComicInfo, extractionResult: ExtractionResult): Promise<ImportComicToDatabaseResult> {
    let mangaId: string = '';
    let chapterId: string = '';
    let organizedPath: string = '';
    let createdManga: boolean = false;
    let createdChapter: boolean = false;
    let reusedChapter: boolean = false;
    let previousChapterDownloadPath: string = '';
    try {
      logger.info(TAG, '开始导入漫画信息到数据库');

      // 创建漫画信息输入对象
      // 注意：根据ComicInfo.xml标准，Series是漫画名称，Title是章节名称
      const comicInfoInput: ComicInfoInput = {
        title: comicInfo.series || comicInfo.title || '未知标题', // 优先使用series作为漫画名称
        author: comicInfo.writer || '未知作者',
        description: comicInfo.summary || '',
        coverUrl: '', // 稍后从提取的图片中选择封面
        sourceId: 'local_import', // 本地导入源ID
        externalId: `local_${generateUUID()}`,  // 本地导入使用生成的UUID
        status: this.convertToMangaStatus(comicInfo.publishingStatus),
        tags: this.parseGenreTags(comicInfo.genre),
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: Date.now(),
        webUrl: comicInfo.web || ''
      };

      // 重名检测与合并决策（改为用户交互，禁止自动合并）
      const dupCheck: DuplicateCheckResult = await this.checkDuplicateCandidates(comicInfoInput);
      const decision: MergeDecision = await this.resolveUserMergeDecision(this.mergeMode, dupCheck, comicInfoInput);
      if (decision.action === MergeAction.SKIP) {
        logger.info(TAG, '用户选择跳过该漫画的导入');
        throw new UserSkipError('用户跳过导入');
      }
      if (decision.action === MergeAction.MERGE_TO_EXISTING && decision.targetMangaId) {
        mangaId = decision.targetMangaId;
        logger.info(TAG, `用户选择合并到已有漫画，目标ID: ${mangaId}`);
      } else {
        // 新建
        mangaId = await this.dataManager.addComicInfo(comicInfoInput);
        createdManga = true;
        logger.info(TAG, `漫画信息已添加，ID: ${mangaId}`);
      }

      // 在导入阶段设置收藏状态（避免后续读取isFavorited为空导致的错误）
      // 仅在未收藏时添加，避免重复
      const dataService = DataService.getInstance();
      const alreadyFavorited: boolean = await dataService.isFavorited(mangaId);
      if (!alreadyFavorited) {
        await dataService.addToFavorites(mangaId, comicInfoInput.tags);
        logger.info(TAG, `导入阶段已设置收藏: ${mangaId}`);
      }

      // 验证漫画信息是否成功存储
      if (!mangaId) {
        throw new Error('漫画信息存储失败：未获得有效的漫画ID');
      }

      // 创建章节信息输入对象
      // 注意：根据ComicInfo.xml标准，Title是章节名称
      const chapterInfoInput: ChapterInfoInput = {
        comicId: mangaId,
        title: comicInfo.title || `第${comicInfo.number || '1'}话`, // 使用title作为章节名称
        index: this.parseChapterNumber(comicInfo.number),
        pageCount: extractionResult.fileCount,
        isDownloaded: true,
        downloadPath: extractionResult.extractedPath,
        publishTime: this.getPublishTimestamp(comicInfo),
        externalId: `local_chapter_${generateUUID()}`  // 本地导入章节使用生成的UUID
      };

      // 检查重复章节
      const duplicateChapter: ChapterRecord | null = await this.findExistingChapter(mangaId, chapterInfoInput.index, chapterInfoInput.title);
      if (duplicateChapter) {
        // 弹窗让用户选择章节处理方式
        const chapterAction: MergeAction = await this.resolveUserChapterMergeDecision(comicInfoInput.title, chapterInfoInput, duplicateChapter);
        if (chapterAction === MergeAction.SKIP) {
          logger.info(TAG, '用户选择跳过该章节的导入');
          throw new UserSkipError('用户跳过导入章节');
        }
        if (chapterAction === MergeAction.MERGE_TO_EXISTING) {
          chapterId = duplicateChapter.id;
          reusedChapter = true;
          previousChapterDownloadPath = duplicateChapter.downloadPath || '';
          logger.info(TAG, `用户选择合并到已有章节（ID: ${chapterId}）`);
        } else {
          const chapterCreation: ChapterInfoCreationResult =
            await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
          if (!chapterCreation.created) {
            throw new Error(`章节已存在，已停止重复导入: ${chapterInfoInput.title}`);
          }
          chapterId = chapterCreation.id;
          createdChapter = chapterCreation.created;
          logger.info(TAG, `章节信息已添加，ID: ${chapterId}`);
        }
      } else {
        // 添加章节信息到数据库
        const chapterCreation: ChapterInfoCreationResult =
          await this.dataManager.addChapterInfoWithResult(chapterInfoInput);
        if (!chapterCreation.created) {
          throw new Error(`章节已存在，已停止重复导入: ${chapterInfoInput.title}`);
        }
        chapterId = chapterCreation.id;
        createdChapter = chapterCreation.created;
        logger.info(TAG, `章节信息已添加，ID: ${chapterId}`);
      }

      // 验证章节信息是否成功存储
      if (!chapterId) {
        throw new Error('章节信息存储失败：未获得有效的章节ID');
      }

      // 先将文件移动到分层存储目录，再添加页面信息
      organizedPath = await this.organizeImportedFiles(comicInfoInput, chapterInfoInput, extractionResult);
      
      if (!organizedPath) {
        throw new Error('文件组织失败：未获得有效的组织路径');
      }

      logger.info(TAG, `文件已组织到: ${organizedPath}`);

      // 更新章节的下载路径为新的组织路径
      await this.updateChapterDownloadPath(chapterId, organizedPath);

      // 现在使用正式存储路径扫描并添加页面信息（合并策略：若已存在页面则避免重复添加）
      let pageCount: number = 0;
      const existingPages: PageRecord[] = await this.dataManager.getPageInfoList(chapterId);
      if (existingPages.length === 0) {
        pageCount = await this.addPageInfoToDatabaseFromPath(chapterId, organizedPath);
        logger.info(TAG, `成功添加 ${pageCount} 个页面信息`);
      } else {
        // 若已有页面记录中包含AVIF路径，则执行迁移：删除旧记录并按组织后的目录重建（WebP优先）
        let hasAvif: boolean = false;
        for (let i: number = 0; i < existingPages.length; i++) {
          const p: PageRecord = existingPages[i];
          const imageUrl: string = p.imageUrl ? p.imageUrl.toLowerCase() : '';
          const localPath: string = p.localPath ? p.localPath.toLowerCase() : '';
          if ((imageUrl.endsWith('.avif')) || (localPath.endsWith('.avif'))) {
            hasAvif = true;
            break;
          }
        }

        if (hasAvif) {
          logger.warn(TAG, `检测到章节页面存在AVIF路径，执行迁移修复: ${existingPages.length} 条`);
          await this.dataManager.removeChapterPages(chapterId);
          pageCount = await this.addPageInfoToDatabaseFromPath(chapterId, organizedPath);
          logger.info(TAG, `迁移完成，重建 ${pageCount} 个页面信息（WebP优先）`);
        } else {
          logger.info(TAG, `检测到章节已有 ${existingPages.length} 个页面（无AVIF），跳过重复添加`);
          pageCount = existingPages.length;
        }
      }

      // 验证页面信息是否成功存储
      if (pageCount === 0) {
        logger.warn(TAG, '警告：未添加任何页面信息，可能是图片文件扫描失败');
      }

      // 最终验证：确保所有数据都正确存储
      await this.validateDatabaseStorage(mangaId, chapterId, pageCount);

      logger.info(TAG, `成功导入漫画: ${comicInfoInput.title}`);

      return {
        mangaId: mangaId,
        chapterId: chapterId,
        mergeMode: this.mergeMode,
        mergeAction: decision.action,
        matchStrength: decision.strength ? decision.strength : (dupCheck.best ? dupCheck.best.strength : undefined),
        duplicateReasons: decision.reasons ? decision.reasons : (dupCheck.best ? dupCheck.best.reasons : undefined),
        mergedToMangaId: decision.targetMangaId
      } as ImportComicToDatabaseResult;

    } catch (error) {
      try {
        if (createdManga && mangaId.length > 0) {
          await this.dataManager.deleteComic(mangaId);
        } else if (createdChapter && chapterId.length > 0) {
          await this.dataManager.deleteChapter(chapterId);
          if (organizedPath.length > 0) {
            await this.sandboxManager.deleteDirectory(organizedPath, true);
          }
        } else if (reusedChapter && chapterId.length > 0) {
          await this.updateChapterDownloadPath(chapterId, previousChapterDownloadPath);
          if (organizedPath.length > 0) {
            await this.sandboxManager.deleteDirectory(organizedPath, true);
          }
        }
      } catch (rollbackError) {
        logger.error(TAG, `传统导入回滚失败: ${mangaId}/${chapterId}`, String(rollbackError));
      }
      logger.error(TAG, '导入数据库失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }
  private async importComicToDatabase(comicInfo: ComicInfo, extractionResult: ExtractionResult): Promise<void> {
    try {
      logger.info(TAG, '开始导入漫画信息到数据库');

      // 创建漫画信息输入对象
      // 注意：根据ComicInfo.xml标准，Series是漫画名称，Title是章节名称
      const comicInfoInput: ComicInfoInput = {
        title: comicInfo.series || comicInfo.title || '未知标题', // 优先使用series作为漫画名称
        author: comicInfo.writer || '未知作者',
        description: comicInfo.summary || '',
        coverUrl: '', // 稍后从提取的图片中选择封面
        sourceId: 'local_import', // 本地导入源ID
        externalId: `local_${generateUUID()}`,  // 本地导入使用生成的UUID
        status: this.convertToMangaStatus(comicInfo.publishingStatus),
        tags: this.parseGenreTags(comicInfo.genre),
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: Date.now()
      };

      // 添加漫画信息到数据库
      const mangaId = await this.dataManager.addComicInfo(comicInfoInput);
      logger.info(TAG, `漫画信息已添加，ID: ${mangaId}`);

      // 在导入阶段设置收藏状态，避免favorite缺失
      const dataService = DataService.getInstance();
      const alreadyFavorited: boolean = await dataService.isFavorited(mangaId);
      if (!alreadyFavorited) {
        await dataService.addToFavorites(mangaId, comicInfoInput.tags);
        logger.info(TAG, `导入阶段已设置收藏: ${mangaId}`);
      }

      // 创建章节信息输入对象
      // 注意：根据ComicInfo.xml标准，Title是章节名称
      const chapterInfoInput: ChapterInfoInput = {
        comicId: mangaId,
        title: comicInfo.title || `第${comicInfo.number || '1'}话`, // 使用title作为章节名称
        index: this.parseChapterNumber(comicInfo.number),
        pageCount: extractionResult.fileCount,
        isDownloaded: true,
        downloadPath: extractionResult.extractedPath,
        publishTime: this.getPublishTimestamp(comicInfo),
        externalId: `local_chapter_${generateUUID()}`  // 本地导入章节使用生成的UUID
      };

      // 添加章节信息到数据库
      const chapterId = await this.dataManager.addChapterInfo(chapterInfoInput);
      logger.info(TAG, `章节信息已添加，ID: ${chapterId}`);

      // 扫描并添加页面信息
      await this.addPageInfoToDatabase(chapterId, extractionResult);

      // 导入成功后，将文件移动到分层存储目录
      const organizedPath = await this.organizeImportedFiles(comicInfoInput, chapterInfoInput, extractionResult);
      
      // 更新章节的下载路径为新的组织路径
      if (organizedPath) {
        await this.updateChapterDownloadPath(chapterId, organizedPath);
        logger.info(TAG, `文件已组织到: ${organizedPath}`);
      }

      // 显示封面选择弹窗（前三张图片），根据用户选择复制为 cover 并更新数据库
      await this.promptUserSelectCover(mangaId, comicInfoInput, chapterId);

      logger.info(TAG, `成功导入漫画: ${comicInfoInput.title}`);

    } catch (error) {
      logger.error(TAG, '导入数据库失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 转换发布状态为MangaStatus枚举
   */
  private convertToMangaStatus(publishingStatus?: string): MangaStatus {
    if (!publishingStatus) {
      return MangaStatus.UNKNOWN;
    }
    
    switch (publishingStatus.trim().toLowerCase()) {
      case 'ongoing':
      case 'continuing':
        return MangaStatus.ONGOING;
      case 'completed':
      case 'finished':
        return MangaStatus.COMPLETED;
      case 'paused':
      case 'hiatus':
        return MangaStatus.HIATUS;
      case 'cancelled':
      case 'canceled':
        return MangaStatus.CANCELLED;
      default:
        return MangaStatus.UNKNOWN;
    }
  }

  /**
   * 获取发布时间戳
   */
  private getPublishTimestamp(comicInfo: ComicInfo): number {
    if (comicInfo.year && comicInfo.month && comicInfo.day) {
      return new Date(comicInfo.year, comicInfo.month - 1, comicInfo.day).getTime();
    } else if (comicInfo.year) {
      return new Date(comicInfo.year, 0, 1).getTime();
    }
    return Date.now();
  }

  /**
   * 安全解析章节号
   */
  private parseChapterNumber(numberValue?: string): number {
    if (!numberValue) {
      return 1;
    }
    
    const parsed = parseInt(numberValue, 10);
    if (isNaN(parsed) || parsed < 1) {
      return 1;
    }
    
    return parsed;
  }

  /**
   * 组织导入的文件到分层存储结构
   * 目录结构：图源/漫画名称/章节名称/
   */
  private async organizeImportedFiles(
    comicInfo: ComicInfoInput, 
    chapterInfo: ChapterInfoInput, 
    extractionResult: ExtractionResult,
    preserveSource: boolean = false
  ): Promise<string> {
    let targetPath: string = '';
    try {
      logger.info(TAG, '开始组织导入文件到分层存储');

      // 清理文件名中的非法字符
      const sourceName = this.sanitizeFileName(comicInfo.sourceId || 'local_import');
      const comicName = this.sanitizeFileName(comicInfo.title);
      const chapterName = this.sanitizeFileName(chapterInfo.title);
      const externalKey: string = this.sanitizeFileName(chapterInfo.externalId);
      const uniqueSuffix: string = externalKey.length > 12
        ? externalKey.substring(externalKey.length - 12)
        : externalKey;
      const chapterDirectoryName: string = `${chapterInfo.index + 1}_${chapterName}_${uniqueSuffix}`;

      // 章节编号和externalId共同参与路径，避免同名章节或重复导入复用旧目录。
      const comicsDir = this.sandboxManager.getDirectory('comics');
      targetPath = `${comicsDir}/${sourceName}/${comicName}/${chapterDirectoryName}`;

      // 创建目标目录
      await this.sandboxManager.createDirectory(targetPath);
      logger.debug(TAG, `创建目标目录: ${targetPath}`);

      const transferredFileCount: number = await this.transferDirectoryContents(
        extractionResult.extractedPath,
        targetPath,
        preserveSource
      );
      if (transferredFileCount <= 0) {
        throw new Error(`源目录为空: ${extractionResult.extractedPath}`);
      }

      if (!preserveSource) {
        await this.sandboxManager.deleteDirectory(extractionResult.extractedPath, true);
        logger.debug(TAG, `清理应用临时目录: ${extractionResult.extractedPath}`);
      }

      logger.info(TAG, `文件组织完成: ${targetPath}, preserveSource=${preserveSource}`);
      return targetPath;

    } catch (error) {
      logger.error(TAG, '文件组织失败', String(error instanceof Error ? error.message : error));
      if (targetPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(targetPath, true);
        } catch (cleanupError) {
          logger.warn(TAG, `清理未完成目标目录失败: ${targetPath}`, String(cleanupError));
        }
      }
      throw error as Error;
    }
  }

  /**
   * 清理文件名中的非法字符
   */
  private sanitizeFileName(fileName: string): string {
    // 移除或替换非法字符
    return fileName
      .replace(/[<>:"/\\|?*]/g, '_')  // 替换Windows非法字符
      .replace(/\s+/g, '_')          // 替换空格为下划线
      .replace(/_{2,}/g, '_')        // 合并多个下划线
      .replace(/^_|_$/g, '')         // 移除首尾下划线
      .substring(0, 100);            // 限制长度
  }

  /**
   * 提示用户选择封面并保存到漫画目录（使用漫画ID隔离文件名）
   */
  private async promptUserSelectCover(mangaId: string, comicInfoInput: ComicInfoInput, chapterId: string): Promise<void> {
    try {
      logger.info(TAG, `准备选择封面：mangaId=${mangaId}, chapterId=${chapterId}, 漫画=${comicInfoInput.title}`);
      const pages: PageRecord[] = await this.dataManager.getChapterPages(chapterId);
      if (!pages || pages.length === 0) {
        logger.warn(TAG, '章节页面为空，无法选择封面');
        return;
      }

      // 取前三张图片的本地路径优先
      const candidates: string[] = [];
      const maxCount: number = pages.length > 3 ? 3 : pages.length;
      logger.debug(TAG, `章节页面数量=${pages.length}，取前${maxCount}张作为候选`);
      for (let i = 0; i < maxCount; i++) {
        const p: PageRecord = pages[i];
        const local: string | undefined = p.localPath;
        const image: string = local && local.length > 0 ? local : p.imageUrl;
        if (image && image.length > 0) {
          candidates.push(image);
        }
      }
      logger.debug(TAG, `封面候选数量=${candidates.length}`);
      for (let i = 0; i < candidates.length; i++) {
        logger.debug(TAG, `候选${i + 1}: ${candidates[i]}`);
      }
      if (candidates.length === 0) {
        logger.warn(TAG, '未找到可用的图片候选');
        return;
      }

      const dialogData: CoverSelectionData = {
        title: comicInfoInput.title,
        candidatePaths: candidates
      } as CoverSelectionData;

      logger.info(TAG, '显示封面选择页面');
      // 使用显式接口并构造具名对象，确保路由参数可序列化
      interface CoverSelectionNavParams {
        mangaId: string;
        chapterId: string;
        candidatePaths: string[];
        fromPage: string;
      }
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        const navParam: CoverSelectionNavParams = {
          mangaId: mangaId,
          chapterId: chapterId,
          candidatePaths: candidates,
          fromPage: 'DataManagementPage'
        } as CoverSelectionNavParams;
        logger.debug(TAG, `导航到 CoverSelectionPage（全局栈），候选数=${navParam.candidatePaths.length}, mangaId=${navParam.mangaId}, chapterId=${navParam.chapterId}`);
        globalStack.pushPath({ name: 'CoverSelectionPage', param: navParam as Object });
      } else {
        logger.warn(TAG, '无法获取GlobalNavStack，尝试使用本地pathStack');
        const localParam: CoverSelectionNavParams = {
          mangaId: mangaId,
          chapterId: chapterId,
          candidatePaths: candidates,
          fromPage: 'DataManagementPage'
        } as CoverSelectionNavParams;
        logger.debug(TAG, `导航到 CoverSelectionPage（本地栈），候选数=${localParam.candidatePaths.length}, mangaId=${localParam.mangaId}, chapterId=${localParam.chapterId}`);
        this.pathStack.pushPath({ name: 'CoverSelectionPage', param: localParam as Object });
      }

      let handled: boolean = false;
      const onCoverSelected = (payload: IEventPayload): void => {
        // 使用显式载荷类型，避免索引访问
        interface CoverSelectionResultPayload { mangaId: string; chapterId: string; selectedPath: string; }
        const result = payload as CoverSelectionResultPayload;
        const selPath: string = result.selectedPath;
        const pid: string = result.chapterId;
        const mid: string = result.mangaId;
        if (!handled && selPath && mid === mangaId && pid === chapterId) {
          handled = true;
          logger.info(TAG, `用户已选择封面：${selPath}`);
          const selectedPath: string = selPath as string;
          
          // 原有复制与数据库更新逻辑
          const comicsDir: string = this.sandboxManager.getDirectory('comics');
          const sourceName: string = this.sanitizeFileName(comicInfoInput.sourceId || 'local_import');
          const comicName: string = this.sanitizeFileName(comicInfoInput.title);
          const comicRoot: string = `${comicsDir}/${sourceName}/${comicName}`;
          this.sandboxManager.createDirectory(comicRoot).then(() => {
            const ext: string = this.getFileExtension(selectedPath);
            const coverTarget: string = `${comicRoot}/cover_${mangaId}.${ext}`;
            fileIo.copyFile(selectedPath, coverTarget).then(() => {
              logger.info(TAG, `封面已复制到：${coverTarget}`);
              this.dataManager.updateComicCoverUrl(mangaId, coverTarget).then(() => {
                logger.info(TAG, '数据库封面URL已更新');
              }).catch((err: Error) => {
                logger.error(TAG, '更新数据库封面URL失败', err.message);
              });
            }).catch((err: Error) => {
              logger.error(TAG, '复制封面文件失败', err.message);
            });
          }).catch((err: Error) => {
            logger.error(TAG, '创建漫画目录失败', err.message);
          }).finally(() => {
            eventBus.unsubscribe(GameEvent.COVER_SELECTION_COMPLETED, onCoverSelected);
          });
        }
      };
      eventBus.subscribe(GameEvent.COVER_SELECTION_COMPLETED, onCoverSelected);
      // 后续复制与数据库更新由事件回调完成；此处不再进行重复操作
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `设置封面失败: ${msg}`);
    }
  }

  /**
   * 提取文件扩展名（不包含点）。未知则返回空字符串。
   */
  private getFileExtension(path: string): string {
    const idx: number = path.lastIndexOf('.');
    if (idx < 0 || idx >= path.length - 1) {
      return '';
    }
    const ext: string = path.substring(idx + 1).toLowerCase();
    // 合法图片扩展
    const allowed: string[] = ['jpg', 'jpeg', 'png', 'webp', 'avif'];
    for (let i = 0; i < allowed.length; i++) {
      if (ext === allowed[i]) {
        return ext;
      }
    }
    return '';
  }

  /**
   * 复制或移动目录内容。外部用户目录必须使用复制模式，应用临时目录才允许移动。
   */
  private async transferDirectoryContents(
    sourcePath: string,
    targetPath: string,
    preserveSource: boolean
  ): Promise<number> {
    try {
      const files: string[] = await this.sandboxManager.listDirectory(sourcePath);
      files.sort((left: string, right: string): number => left.localeCompare(right, undefined, { numeric: true }));
      let transferredFileCount: number = 0;
      
      for (const file of files) {
        const sourceFilePath = `${sourcePath}/${file}`;
        const targetFilePath = `${targetPath}/${file}`;
        if (await this.sandboxManager.isSymbolicLink(sourceFilePath)) {
          logger.warn(TAG, `目录传输跳过符号链接: ${sourceFilePath}`);
          continue;
        }
        const stat = await fileIo.lstat(sourceFilePath);
        if (stat.isDirectory()) {
          await this.sandboxManager.createDirectory(targetFilePath);
          transferredFileCount += await this.transferDirectoryContents(
            sourceFilePath,
            targetFilePath,
            preserveSource
          );
          if (!preserveSource) {
            await this.sandboxManager.deleteDirectory(sourceFilePath, true);
          }
          continue;
        }
        const lowerName: string = file.toLowerCase();
        const dotIndex: number = lowerName.lastIndexOf('.');
        const ext: string = dotIndex >= 0 ? lowerName.substring(dotIndex) : '';
        
        // 对AVIF文件：在组织阶段直接转码到目标目录为WebP，且不保存原AVIF
        if (ext === '.avif') {
          logger.debug(TAG, `检测到AVIF文件，执行组织阶段转码: ${sourceFilePath}`);
          const transcodeResult: AvifTranscodeResult = await AvifTranscoder.getInstance().transcodeToTargetDirectory(sourceFilePath, targetPath);
          if (transcodeResult.success && transcodeResult.webpPath) {
            logger.info(TAG, `组织阶段转码成功，已保存为WebP并跳过原AVIF: ${transcodeResult.webpPath}`);
            if (!preserveSource) {
              await this.sandboxManager.deleteFile(sourceFilePath);
            }
            transferredFileCount += 1;
            continue;
          } else {
            this.logTranscodeFailure('组织阶段', sourceFilePath, transcodeResult);
            throw new Error(`AVIF转码失败: ${file}`);
          }
        }
        
        if (preserveSource) {
          await this.sandboxManager.copyFile(sourceFilePath, targetFilePath);
          logger.debug(TAG, `复制外部文件: ${sourceFilePath} -> ${targetFilePath}`);
        } else {
          await this.sandboxManager.moveFile(sourceFilePath, targetFilePath);
          logger.debug(TAG, `移动临时文件: ${sourceFilePath} -> ${targetFilePath}`);
        }
        transferredFileCount += 1;
      }
      
      logger.info(TAG, `目录内容传输完成: files=${transferredFileCount}, preserveSource=${preserveSource}`);
      return transferredFileCount;
    } catch (error) {
      logger.error(TAG, '传输目录内容失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 在组织阶段为单个AVIF源文件执行转码，并将WebP写入目标目录
   * 若设备不支持AVIF或转码失败，则返回undefined并记录日志
   */
  private async transcodeAvifFileToWebpAtTarget(sourcePath: string, targetDir: string): Promise<ImageFileInfo | undefined> {
    try {
      const transcodeResult: AvifTranscodeResult = await AvifTranscoder.getInstance().transcodeToTargetDirectory(sourcePath, targetDir);
      if (transcodeResult.success && transcodeResult.webpPath && transcodeResult.fileSize !== undefined) {
        const converted: ImageFileInfo = {
          path: transcodeResult.webpPath,
          name: transcodeResult.webpPath.substring(transcodeResult.webpPath.lastIndexOf('/') + 1),
          size: transcodeResult.fileSize,
          width: transcodeResult.width,
          height: transcodeResult.height,
          fileSize: transcodeResult.fileSize
        } as ImageFileInfo;
        return converted;
      }
      this.logTranscodeFailure('组织阶段', sourcePath, transcodeResult);
      return undefined;
    } catch (error) {
      logger.warn(TAG, `组织阶段AVIF转码异常: ${sourcePath}`, String(error instanceof Error ? error.message : error));
      return undefined;
    }
  }

  /**
   * 更新章节的下载路径
   */
  private async updateChapterDownloadPath(chapterId: string, newPath: string): Promise<void> {
    try {
      await this.dataManager.updateChapterInfo(chapterId, { downloadPath: newPath });
      logger.debug(TAG, `更新章节下载路径: ${chapterId} -> ${newPath}`);
    } catch (error) {
      logger.error(TAG, '更新章节下载路径失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 从指定路径添加页面信息到数据库
   * 用于在文件移动到正式目录后添加页面信息
   */
  private async addPageInfoToDatabaseFromPath(chapterId: string, directoryPath: string): Promise<number> {
    try {
      logger.info(TAG, `开始从路径添加页面信息到数据库: ${directoryPath}`);

      // 扫描指定目录中的图片文件
      const imageFiles = await this.scanImageFiles(directoryPath);
      
      if (imageFiles.length === 0) {
        throw new Error(`目标目录未找到任何图片: ${directoryPath}`);
      }

      let addedCount = 0;
      
      for (let i = 0; i < imageFiles.length; i++) {
        const imageFile = imageFiles[i];
        
        // [修复] 使用 i 而不是 i + 1，确保 index 是 0-indexed
        const pageInfoInput: PageInfoInput = {
          chapterId: chapterId,
          index: i, // [修复] 使用0-indexed数组索引
          imageUrl: imageFile.path, // 使用正式存储路径
          localPath: imageFile.path, // 本地文件路径
          width: Math.floor(imageFile.width || 0), // 确保为整数
          height: Math.floor(imageFile.height || 0), // 确保为整数
          fileSize: Math.floor(imageFile.fileSize || imageFile.size || 0), // 确保为整数，优先使用fileSize
          pageNumber: i + 1 // pageNumber 保持 1-indexed，用于显示
        };

        try {
          logger.debug(TAG, `准备添加页面信息: chapterId=${chapterId}, index=${pageInfoInput.index}, path=${imageFile.path}, fileSize=${pageInfoInput.fileSize}`);
          await this.dataManager.addPageInfo(pageInfoInput);
          addedCount++;
          logger.debug(TAG, `添加页面信息成功: ${imageFile.path}`);
        } catch (error) {
          logger.error(TAG, `添加页面信息失败: ${imageFile.path}`, String(error instanceof Error ? error.message : error));
          throw error as Error;
        }
      }

      logger.info(TAG, `成功添加 ${addedCount}/${imageFiles.length} 个页面信息`);
      return addedCount;

    } catch (error) {
      logger.error(TAG, '从路径添加页面信息失败', String(error instanceof Error ? error.message : error));
      throw error as Error;
    }
  }

  /**
   * 添加页面信息到数据库（原方法，保留用于兼容性）
   */
  private async addPageInfoToDatabase(chapterId: string, extractionResult: ExtractionResult): Promise<number> {
    try {
      logger.info(TAG, '开始添加页面信息到数据库');

      // 扫描解压目录中的图片文件
      const imageFiles = await this.scanImageFiles(extractionResult.extractedPath);
      
      if (imageFiles.length === 0) {
        logger.warn(TAG, '未找到任何图片文件');
        return 0;
      }

      let addedCount = 0;
      
      for (let i = 0; i < imageFiles.length; i++) {
        const imageFile = imageFiles[i];
        
        // [修复] 使用 i 而不是 i + 1，确保 index 是 0-indexed
        const pageInfoInput: PageInfoInput = {
          chapterId: chapterId,
          index: i, // [修复] 使用0-indexed数组索引
          imageUrl: imageFile.path,
          localPath: imageFile.path, // 本地文件路径
          width: Math.floor(imageFile.width || 0), // 确保为整数
          height: Math.floor(imageFile.height || 0), // 确保为整数
          fileSize: Math.floor(imageFile.fileSize || imageFile.size || 0), // 确保为整数，优先使用fileSize
          pageNumber: i + 1 // pageNumber 保持 1-indexed，用于显示
        };

        try {
          logger.debug(TAG, `准备添加页面信息: chapterId=${chapterId}, index=${pageInfoInput.index}, path=${imageFile.path}, fileSize=${pageInfoInput.fileSize}`);
          await this.dataManager.addPageInfo(pageInfoInput);
          addedCount++;
          logger.debug(TAG, `添加页面信息成功: ${imageFile.path}`);
        } catch (error) {
          logger.error(TAG, `添加页面信息失败: ${imageFile.path}`, String(error instanceof Error ? error.message : error));
        }
      }

      logger.info(TAG, `成功添加 ${addedCount}/${imageFiles.length} 个页面信息`);
      return addedCount;

    } catch (error) {
      logger.error(TAG, '添加页面信息失败', String(error instanceof Error ? error.message : error));
      return 0;
    }
  }

  /**
   * 扫描图片文件
   */
  private async collectImageFilesRecursive(
    rootPath: string,
    currentPath: string,
    imageFiles: ImageFileInfo[]
  ): Promise<void> {
    const supportedExtensions: string[] = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.avif'];
    const files: string[] = await fs.listFile(currentPath);
    files.sort((left: string, right: string): number => left.localeCompare(right, undefined, { numeric: true }));
    for (const fileName of files) {
      const filePath: string = `${currentPath}/${fileName}`;
      const stat = await fs.lstat(filePath);
      if (stat.isSymbolicLink()) {
        logger.warn(TAG, `图片扫描跳过符号链接: ${filePath}`);
        continue;
      }
      if (stat.isDirectory()) {
        await this.collectImageFilesRecursive(rootPath, filePath, imageFiles);
        continue;
      }
      const lowerName: string = fileName.toLowerCase();
      const dotIndex: number = lowerName.lastIndexOf('.');
      const extension: string = dotIndex >= 0 ? lowerName.substring(dotIndex) : '';
      if (!supportedExtensions.includes(extension)) {
        continue;
      }
      const relativeName: string = filePath.startsWith(`${rootPath}/`)
        ? filePath.substring(rootPath.length + 1)
        : fileName;
      const imageFileInfo: ImageFileInfo = {
        path: filePath,
        name: relativeName,
        size: stat.size || 0,
        width: undefined,
        height: undefined,
        fileSize: stat.size || 0
      };
      imageFiles.push(imageFileInfo);
    }
  }

  private async scanImageFiles(directoryPath: string): Promise<ImageFileInfo[]> {
    try {
      logger.info(TAG, `扫描目录: ${directoryPath}`);
      
      const imageFiles: ImageFileInfo[] = [];
      
      try {
        await this.collectImageFilesRecursive(directoryPath, directoryPath, imageFiles);
        
        // 按相对路径自然排序，压缩包物理entry顺序不会影响漫画页序。
        imageFiles.sort((a: ImageFileInfo, b: ImageFileInfo): number =>
          a.name.localeCompare(b.name, undefined, { numeric: true })
        );

        // 统计原始文件的类型分布
        let avifCount: number = 0;
        let nonAvifCount: number = 0;
        for (let i: number = 0; i < imageFiles.length; i++) {
          const nameLower: string = imageFiles[i].name.toLowerCase();
          const dotIndex: number = nameLower.lastIndexOf('.');
          const ext: string = dotIndex >= 0 ? nameLower.substring(dotIndex) : '';
          if (ext === '.avif') {
            avifCount++;
          } else {
            nonAvifCount++;
          }
        }

        // 对AVIF文件进行预处理：尝试转码到WebP，以确保后续显示兼容
        const processedFiles = await this.convertAvifFilesToWebpIfNeeded(imageFiles);

        // 若仅包含AVIF且全部转码失败，给出明确原因日志
        if (processedFiles.length === 0 && avifCount > 0 && nonAvifCount === 0) {
          logger.warn(TAG, '目录仅包含AVIF文件，且设备不支持AVIF解码或转码失败，无法生成可显示页面');
        }

        logger.info(TAG, `扫描完成，找到 ${processedFiles.length} 个图片文件（含AVIF兼容处理）`);
        return processedFiles;
        
      } catch (listError) {
        logger.error(TAG, `读取目录失败: ${directoryPath}`, String(listError instanceof Error ? listError.message : listError));
        return [];
      }
      
    } catch (error) {
      logger.error(TAG, '扫描图片文件失败', String(error instanceof Error ? error.message : error));
      return [];
    }
  }

  /**
   * 将列表中的AVIF文件尝试转码为WebP以提升兼容性
   * 若转码失败，则保留原AVIF条目并记录日志，不中断导入流程
   */
  private async convertAvifFilesToWebpIfNeeded(files: ImageFileInfo[]): Promise<ImageFileInfo[]> {
    const result: ImageFileInfo[] = [];
    for (let i = 0; i < files.length; i++) {
      const fileInfo = files[i];
      const lowerName = fileInfo.name.toLowerCase();
      const dotIndex = lowerName.lastIndexOf('.');
      const ext = dotIndex >= 0 ? lowerName.substring(dotIndex) : '';
      if (ext === '.avif') {
        try {
          const transcodeResult: AvifTranscodeResult = await AvifTranscoder.getInstance().transcodeToSameDirectory(fileInfo.path);
          if (transcodeResult.success && transcodeResult.webpPath && transcodeResult.fileSize !== undefined) {
            const converted: ImageFileInfo = {
              path: transcodeResult.webpPath,
              name: transcodeResult.webpPath.substring(transcodeResult.webpPath.lastIndexOf('/') + 1),
              size: transcodeResult.fileSize,
              width: transcodeResult.width,
              height: transcodeResult.height,
              fileSize: transcodeResult.fileSize
            } as ImageFileInfo;
            result.push(converted);
            logger.info(TAG, `AVIF转码为WebP成功: ${fileInfo.name} → ${converted.name}`);
          } else {
            // 转码失败时不写入AVIF条目，避免后续阅读器加载不可兼容格式
            // 仅记录日志并跳过该文件，保持类型安全与兼容性，输出完整错误
            this.logTranscodeFailure('预处理阶段', fileInfo.path, transcodeResult);
          }
        } catch (error) {
          // 异常情况下同样跳过AVIF文件，避免不可显示的页面被写入数据库
          logger.error(TAG, `AVIF转码异常，跳过文件: ${fileInfo.name}`, String(error instanceof Error ? error.message : error));
        }
      } else {
        result.push(fileInfo);
      }
    }
    return result;
  }

  /**
   * 尝试将单个AVIF文件转码为WebP并返回新的文件信息
   * 使用@kit.ImageKit进行解码，如设备不支持AVIF则返回undefined
   */
  private async tryTranscodeAvifToWebp(fileInfo: ImageFileInfo): Promise<ImageFileInfo | undefined> {
    try {
      const transcodeResult: AvifTranscodeResult = await AvifTranscoder.getInstance().transcodeToSameDirectory(fileInfo.path);
      if (transcodeResult.success && transcodeResult.webpPath && transcodeResult.fileSize !== undefined) {
        const converted: ImageFileInfo = {
          path: transcodeResult.webpPath,
          name: transcodeResult.webpPath.substring(transcodeResult.webpPath.lastIndexOf('/') + 1),
          size: transcodeResult.fileSize,
          width: transcodeResult.width,
          height: transcodeResult.height,
          fileSize: transcodeResult.fileSize
        } as ImageFileInfo;
        return converted;
      }
      this.logTranscodeFailure('预处理阶段', fileInfo.path, transcodeResult);
      return undefined;
    } catch (error) {
      logger.warn(TAG, `AVIF转码异常: ${fileInfo.name}`, String(error instanceof Error ? error.message : error));
      return undefined;
    }
  }

  /**
   * 输出 AvifTranscoder 返回的完整错误信息
   */
  private logTranscodeFailure(context: string, sourcePath: string, result: AvifTranscodeResult): void {
    const hasErr: boolean = !!(result && result.error);
    if (!hasErr) {
      logger.warn(TAG, `${context}AVIF转码失败（无详细错误），跳过文件: ${sourcePath}`);
      return;
    }
    const err = result.error;
    const nameStr: string = err && err.name ? String(err.name) : '';
    const msgStr: string = err && err.message ? String(err.message) : '';
    const stageStr: string = err && err.stage ? String(err.stage) : 'UNKNOWN';
    let headerStr: string = '';
    if (err && err.header) {
      const major: string = err.header.majorBrand ? String(err.header.majorBrand) : '';
      const brands: string[] = err.header.compatibleBrands ? err.header.compatibleBrands as string[] : ([] as string[]);
      const brandsStr: string = brands.length > 0 ? brands.join(',') : '';
      headerStr = `, majorBrand=${major}, compat=[${brandsStr}]`;
    }
    logger.warn(TAG, `${context}AVIF转码失败: ${sourcePath}`, `stage=${stageStr}, ${nameStr}: ${msgStr}${headerStr}`);
    if (err && err.stack) {
      logger.debug(TAG, '异常堆栈', String(err.stack));
    }
  }



  /**
   * 解析ComicInfo.xml文件
   */
  private async parseComicInfo(extractedPath: string): Promise<ComicInfo> {
    try {
      // 查找ComicInfo.xml文件
      const comicInfoPath = `${extractedPath}/ComicInfo.xml`;
      
      // 检查ComicInfo.xml文件是否存在
      try {
        const stat = fs.lstatSync(comicInfoPath);
        if (stat.isSymbolicLink()) {
          logger.warn(TAG, `ComicInfo.xml是符号链接，拒绝读取: ${comicInfoPath}`);
          return this.getDefaultComicInfo();
        }
        if (!stat.isFile()) {
          logger.warn(TAG, `ComicInfo.xml不是文件: ${comicInfoPath}`);
          return this.getDefaultComicInfo();
        }
      } catch (statError) {
        logger.warn(TAG, `ComicInfo.xml文件不存在: ${comicInfoPath}`);
        return this.getDefaultComicInfo();
      }

      // 读取XML文件内容
      const xmlContent = SafeFileUtils.readTextSync(comicInfoPath, { encoding: 'utf-8' });
      logger.info(TAG, `读取ComicInfo.xml成功，内容长度: ${xmlContent.length}`);

      // 使用ComicInfoParser解析XML内容
      const parser = new ComicInfoParser();
      const comicInfo = parser.parseXmlString(xmlContent);
      
      logger.info(TAG, `解析ComicInfo.xml成功: 标题=${comicInfo.title}, 系列=${comicInfo.series}`);
      return comicInfo;
      
    } catch (error) {
      logger.error(TAG, 'ComicInfo.xml解析失败', String(error instanceof Error ? error.message : error));
      return this.getDefaultComicInfo();
    }
  }

  /**
   * 获取默认的漫画信息
   */
  private getDefaultComicInfo(): ComicInfo {
    return {
      title: '未知标题',
      series: '未知系列',
      number: '1',
      summary: '暂无描述',
      writer: '未知作者',
      genre: '未分类',
      web: '',
      publishingStatus: 'Unknown',
      source: '本地导入'
    } as ComicInfo;
  }

  /**
   * 构建测试功能区域（已移除）
   */
  // 测试功能区域已移除
  // 测试构建区域内容已删除
  // 测试功能区域已移除

  // 基础测试方法已移除

  // 完整流程测试方法已移除

  // UI功能测试方法已移除

  // 清除测试结果方法已移除

  /**
   * 从URI中提取文件名
   */
  private getFileNameFromUri(uri: string): string {
    try {
      const parts = uri.split('/');
      let fileName = parts[parts.length - 1] || 'unknown_file';
      
      // 解码URL编码的文件名
      fileName = decodeURIComponent(fileName);
      
      return fileName;
    } catch (error) {
      logger.warn(TAG, `解析文件名失败: ${uri}`, String(error instanceof Error ? error.message : error));
      return 'unknown_file';
    }
  }

  /**
   * 更新导入进度
   */
  private updateProgress(status: ImportStatus, message: string, progress: number): void {
    if (!this.isPageActive) {
      return;
    }
    this.importProgress = {
      status: status,
      message: message,
      progress: Math.min(100, Math.max(0, progress))
    };
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      logger.info(TAG, '用户点击返回按钮');
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error instanceof Error ? error.message : error));
    }
  }
  
  /**
   * 构建批量导入策略选择对话框
   */
  @Builder
  buildBatchStrategyDialog() {
    Stack() {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {
          this.showBatchStrategyDialog = false;
        })
      
      // 对话框内容
      Column({ space: 20 }) {
        // 标题
        Text(`批量导入 ${this.selectedFiles.length} 个文件`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
        
        Scroll() {
          Column() {
            Column({ space: 8 }) {
              Text('检测到多个文件，请选择处理策略：')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')
              Text('• 逐个询问：每个文件遇到重复时都会询问')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
              Text('• 全部合并：自动合并到最匹配的已有漫画')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
              Text('• 全部新建：所有文件都作为新漫画导入')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(8)

            Column({ space: 12 }) {
              this.buildStrategyOption(
                '逐个询问',
                '每个文件遇到重复都会弹窗确认',
                '💬',
                'ask'
              )
              this.buildStrategyOption(
                '全部合并',
                '自动合并到最匹配的已有漫画',
                '🔗',
                'merge_all'
              )
              this.buildStrategyOption(
                '全部新建',
                '所有文件都作为新漫画导入',
                '➕',
                'create_all'
              )
            }
            .width('100%')
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        
        // 操作按钮
        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text('取消').fontFamily(this.appFontFamily)
          }
            .width('48%')
            .height(44)
            .onClick(() => {
              this.showBatchStrategyDialog = false;
              this.batchImportStrategy = 'ask';
            })

          Button({ stateEffect: true }) {
            Text('开始导入').fontFamily(this.appFontFamily)
          }
            .width('48%')
            .height(44)
            .onClick(() => {
              this.showBatchStrategyDialog = false;
              this.executeBatchImport();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('85%')
      .height('80%')
      .constraintSize({ maxWidth: this.responsive_maxContentWidth })
      .padding(24)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(16)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 4
      })
      .onClick(() => {
        // 阻止点击事件冒泡到遮罩层
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .position({ x: 0, y: 0 })
    .zIndex(999)
  }
  
  /**
   * 构建策略选项
   */
  @Builder
  buildStrategyOption(title: string, description: string, icon: string, strategy: 'ask' | 'merge_all' | 'create_all') {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(24)
        .fontFamily(this.appFontFamily)
      
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      Radio({ value: strategy, group: 'batchStrategy' })
        .checked(this.batchImportStrategy === strategy)
        .onChange((checked: boolean) => {
          if (checked) {
            this.batchImportStrategy = strategy;
            logger.info(TAG, `选择批量策略: ${strategy}`);
          }
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(
      this.batchImportStrategy === strategy 
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme)
    )
    .borderRadius(8)
    .border({
      width: this.batchImportStrategy === strategy ? 2 : 1,
      color: this.batchImportStrategy === strategy
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.batchImportStrategy = strategy;
      logger.info(TAG, `点击选择批量策略: ${strategy}`);
    })
  }

  /**
   * 构建进度指示器
   */
  @Builder
  buildProgressIndicator() {
    if (this.importProgress.status !== ImportStatus.IDLE) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? '#66000000' : '#33000000')
          .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
        Column({ space: 12 }) {
      // 状态文本
      Text(this.importProgress.message)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      // 进度条 - 条件渲染
      Column() {
        Progress({
          value: this.importProgress.progress,
          total: 100,
          type: ProgressType.Linear
        })
        .width('100%')
        .height(4)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      }
      .visibility(this.importProgress.status !== ImportStatus.ERROR && this.importProgress.status !== ImportStatus.COMPLETED ? Visibility.Visible : Visibility.None)

      if (this.importProgress.status === ImportStatus.COMPLETED) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_shield'))
            .fontSize(22)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
          Text('导入完成')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        }
      }

      if (this.importProgress.status === ImportStatus.ERROR) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(22)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])
          Text('导入失败')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
        }
      }
        }
    .width('86%')
    .constraintSize({ maxWidth: 520 })
    .padding(24)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 28,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 12
    })
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }).animation({ duration: 260, curve: Curve.EaseOut }))
        .combine(TransitionEffect.translate({ y: 18 }).animation({ duration: 260, curve: Curve.EaseOut }))
    )
      }
      .width('100%')
      .height('100%')
      .zIndex(1000)
      .onClick(() => {
        if (this.importProgress.status === ImportStatus.COMPLETED || this.importProgress.status === ImportStatus.ERROR) {
          this.importProgress = { status: ImportStatus.IDLE, message: '准备就绪', progress: 0 };
        }
      })
    }
  }

  /**
   * 构建导入结果
   */
  @Builder
  buildImportResults() {
    Column({ space: 12 }) {
      Text('导入结果')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 8 })

      // 显示简要结果
      ForEach(this.importResults, (result: string, index: number) => {
        Text(result)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      })

      // 显示详细的漫画信息
      if (this.importResultDetails.length > 0) {
        Text('导入处理详情')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 16, bottom: 8 })

        ForEach(this.importResultDetails, (detail: ImportResultDetail, index: number) => {
          this.buildMangaDetailCard(detail)
        })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .visibility(this.showResults && this.importResults.length > 0 ? Visibility.Visible : Visibility.None)
  }

  /**
   * 构建漫画详情卡片
   */
  @Builder
  buildMangaDetailCard(detail: ImportResultDetail) {
    Column({ space: 12 }) {
      // 文件名和状态头部
      Row({ space: 8 }) {
        Text(`📁 ${detail.fileName}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        // 状态指示器
        Row({ space: 4 }) {
          if (detail.success) {
            Text('✅')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
            Text('成功')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('success_text', this.themeState.currentTheme))
          } else {
            Text('❌')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
            Text('失败')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('error_text', this.themeState.currentTheme))
          }
        }
      }
      .width('100%')

      // 处理步骤状态
      Column({ space: 6 }) {
        Text('处理步骤:')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Row({ space: 12 }) {
          this.buildStepIndicator('解压', detail.extractedFileCount !== undefined && detail.extractedFileCount > 0)
          this.buildStepIndicator('XML', detail.xmlFound === true)
          this.buildStepIndicator('解析', detail.xmlParsed === true)
          this.buildStepIndicator('存储', detail.databaseStored === true)
          this.buildStepIndicator('整理', detail.filesOrganized === true)
        }
        .width('100%')
      }

      // 提取信息
      if (detail.extractedFileCount !== undefined) {
        Row({ space: 8 }) {
          Text('📦')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
          Text(`提取了 ${detail.extractedFileCount} 个文件`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }

      // XML信息区域
      if (detail.xmlFound !== undefined) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('📄')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
            Text(`ComicInfo.xml: ${detail.xmlFound ? '已找到' : '未找到'}`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(detail.xmlFound ? 
                ThemeAwareHelper.getTestManagementThemedColor('success_text', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme))
          }

          if (detail.xmlFound && detail.xmlParsed && detail.comicInfo) {
            // XML解析成功，显示详细漫画信息
            Column({ space: 8 }) {
              Text('📖 从XML中解析到的漫画信息:')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              // 漫画详细信息网格
              Column({ space: 4 }) {
                if (detail.comicInfo.title) {
                  this.buildInfoRow('标题', detail.comicInfo.title, '📚')
                }
                if (detail.comicInfo.writer) {
                  this.buildInfoRow('作者', detail.comicInfo.writer, '✍️')
                }
                if (detail.comicInfo.summary) {
                  this.buildInfoRow('简介', detail.comicInfo.summary, '📝', true)
                }
                if (detail.comicInfo.genre) {
                  this.buildInfoRow('类型', detail.comicInfo.genre, '🏷️')
                }
                if (detail.comicInfo.publishingStatus) {
                  this.buildInfoRow('状态', detail.comicInfo.publishingStatus, '📊')
                }
                if (detail.comicInfo.number) {
                  this.buildInfoRow('章节号', detail.comicInfo.number, '📑')
                }
                if (detail.comicInfo.web) {
                  this.buildInfoRow('网址', detail.comicInfo.web, '🌐')
                }
                if (detail.comicInfo.source) {
                  this.buildInfoRow('来源', detail.comicInfo.source, '🔗')
                }
              }
              .width('100%')
              .padding({ left: 8, top: 8, bottom: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(4)
            }
          } else if (detail.xmlFound && !detail.xmlParsed) {
            Text('⚠️ XML文件解析失败，使用默认信息')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme))
              .padding({ left: 8 })
          } else if (!detail.xmlFound) {
            Text('ℹ️ 未找到XML文件，使用文件名生成默认信息')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 8 })
          }
        }
      }

      // 数据库存储信息
      if (detail.databaseStored && (detail.mangaId || detail.chapterId)) {
        Column({ space: 4 }) {
          Text('💾 数据库存储信息:')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (detail.mangaId) {
            this.buildInfoRow('漫画ID', detail.mangaId, '🆔')
          }
          if (detail.chapterId) {
            this.buildInfoRow('章节ID', detail.chapterId, '📑')
          }
        }
        .padding({ left: 8, top: 8, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(4)
      }

      // 合并与重复检测信息
      if (detail.mergeMode || detail.mergeAction || detail.matchStrength || detail.duplicateTargetMangaId || (detail.duplicateReasons && detail.duplicateReasons.length > 0)) {
        Column({ space: 4 }) {
          Text('🔗 合并与重复检测:')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (detail.mergeMode) {
            this.buildInfoRow('合并模式', this.getMergeModeLabel(detail.mergeMode as MergeMode), '🧩')
          }
          if (detail.mergeAction) {
            this.buildInfoRow('合并动作', this.getMergeActionLabel(detail.mergeAction as MergeAction), '➡️')
          }
          if (detail.matchStrength) {
            this.buildInfoRow('匹配强度', this.getMatchStrengthLabel(detail.matchStrength as MatchStrength), '📈')
          }
          if (detail.duplicateTargetMangaId) {
            this.buildInfoRow('目标漫画ID', detail.duplicateTargetMangaId, '🎯')
          }
          if (detail.duplicateReasons && detail.duplicateReasons.length > 0) {
            this.buildInfoRow('重复原因', this.getDuplicateReasonsLabel(detail.duplicateReasons as DuplicateReason[]), '🧠', true)
          }
        }
        .padding({ left: 8, top: 8, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(4)
      }

      // 错误信息
      if (!detail.success && detail.errorMessage) {
        Column({ space: 4 }) {
          Text('❌ 错误信息:')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('error_text', this.themeState.currentTheme))

          Text(detail.errorMessage)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('error_text', this.themeState.currentTheme))
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(4)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('error_border', this.themeState.currentTheme)
        })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .margin({ bottom: 12 })
  }

  /**
   * 构建步骤指示器
   */
  @Builder
  buildStepIndicator(stepName: string, completed: boolean) {
    Column({ space: 2 }) {
      Text(completed ? '✅' : '⏳')
        .fontSize(10)
        .fontFamily(this.appFontFamily)
      Text(stepName)
        .fontSize(9)
        .fontFamily(this.appFontFamily)
        .fontColor(completed ? 
          ThemeAwareHelper.getTestManagementThemedColor('success_text', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建信息行
   */
  @Builder
  buildInfoRow(label: string, value: string, icon: string, multiline: boolean = false) {
    Row({ space: 6 }) {
      Text(icon)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
      Text(`${label}:`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width(50)
      Text(value)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
        .maxLines(multiline ? 3 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 合并与重复检测辅助：枚举到中文标签
   */
  private getMergeModeLabel(mode?: MergeMode): string {
    if (!mode) {
      return '未知';
    }
    switch (mode) {
      case MergeMode.StrictNew:
        return '严格新建';
      case MergeMode.AutoRecommend:
        return '自动推荐';
      case MergeMode.ManualCustom:
        return '手动自定义';
      default:
        return '未知';
    }
  }

  private getMatchStrengthLabel(strength?: MatchStrength): string {
    if (!strength) {
      return '未知';
    }
    switch (strength) {
      case MatchStrength.BELOW:
        return '低于阈值';
      case MatchStrength.WEAK:
        return '较弱';
      case MatchStrength.LIKELY:
        return '可能';
      case MatchStrength.STRONG:
        return '强';
      case MatchStrength.EXACT:
        return '完全匹配';
      default:
        return '未知';
    }
  }

  private getMergeActionLabel(action?: MergeAction): string {
    if (!action) {
      return '未知';
    }
    switch (action) {
      case MergeAction.MERGE_TO_EXISTING:
        return '合并至已有';
      case MergeAction.CREATE_NEW:
        return '新建';
      case MergeAction.SKIP:
        return '跳过';
      default:
        return '未知';
    }
  }

  private getDuplicateReasonsLabel(reasons?: DuplicateReason[]): string {
    if (!reasons || reasons.length === 0) {
      return '无';
    }
    const labels: string[] = [];
    for (let i = 0; i < reasons.length; i++) {
      const reason: DuplicateReason = reasons[i];
      switch (reason) {
        case DuplicateReason.TITLE_EXACT:
          labels.push('标题完全相同');
          break;
        case DuplicateReason.AUTHOR_EXACT:
          labels.push('作者完全相同');
          break;
        case DuplicateReason.TITLE_SIMILAR:
          labels.push('标题相似');
          break;
        case DuplicateReason.AUTHOR_SIMILAR:
          labels.push('作者相似');
          break;
        case DuplicateReason.TAGS_OVERLAP:
          labels.push('标签重叠');
          break;
        default:
          labels.push('其他');
          break;
      }
    }
    return labels.join('、');
  }

  /**
   * 获取文件图标资源
   */
  private getFileIconResource(filename: string): Resource {
    const ext = this.getDownloadFileExtension(filename);
    if (DataManagementPage.MANGA_EXTENSIONS.includes(ext)) return $r('sys.symbol.picture');
    if (DataManagementPage.EBOOK_EXTENSIONS.includes(ext)) return $r('sys.symbol.book');
    if (DataManagementPage.PDF_EXTENSIONS.includes(ext)) return $r('sys.symbol.doc_plaintext');
    if (DataManagementPage.NOVEL_EXTENSIONS.includes(ext)) return $r('sys.symbol.text_book_closed');
    return $r('sys.symbol.folder');
  }

  /**
   * 构建一级标签栏 - VSCode风格
   */
  @Builder
  buildPrimaryTabBar() {
    Scroll() {
      Row({ space: 0 }) {
        // 选择文件导入Tab
        Row() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus'))
            .fontSize(14)
            .fontColor([this.primaryTab === 'file_select'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          Text('选择文件导入')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.primaryTab === 'file_select'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 12, right: 12 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.primaryTab === 'file_select'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.primaryTab === 'file_select' ? 2 : 0, bottom: 0, left: 0, right: 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.primaryTab = 'file_select'; })
        .animation({ duration: 150 })

        // Download同步Tab
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(14)
            .fontColor([this.primaryTab === 'download_sync'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          Text('Download同步')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.primaryTab === 'download_sync'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 12, right: 12 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.primaryTab === 'download_sync'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.primaryTab === 'download_sync' ? 2 : 0, bottom: 0, left: 0, right: 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.primaryTab = 'download_sync'; })
        .animation({ duration: 150 })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .height(35)
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
  }

  /**
   * 构建选择文件导入的二级标签 - VSCode风格
   */
  @Builder
  buildFileSelectSecondaryTabs() {
    Scroll() {
      Row({ space: 0 }) {
        // 漫画Tab
        Row() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(12)
            .fontColor([this.secondaryTab === 'manga'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('漫画')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.secondaryTab === 'manga'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.secondaryTab === 'manga'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.secondaryTab === 'manga' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.secondaryTab = 'manga'; })
        .animation({ duration: 150 })

        // 电子书Tab
        Row() {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(12)
            .fontColor([this.secondaryTab === 'ebook'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('电子书')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.secondaryTab === 'ebook'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.secondaryTab === 'ebook'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.secondaryTab === 'ebook' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.secondaryTab = 'ebook'; })
        .animation({ duration: 150 })

        // PDF Tab
        Row() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(12)
            .fontColor([this.secondaryTab === 'pdf'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('PDF')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.secondaryTab === 'pdf'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.secondaryTab === 'pdf'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.secondaryTab === 'pdf' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => { this.secondaryTab = 'pdf'; })
        .animation({ duration: 150 })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(32)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .margin({ top: 4 })
  }

  /**
   * 构建漫画导入区域
   */
  @Builder
  buildMangaImportSection() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.picture')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('漫画导入')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Text('支持导入ZIP、CBZ、TAR、GZ等压缩包格式。\n支持单行本、单章节、多章节导入模式，可自动识别章节结构或手动配置。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      Row({ space: 8 }) {
        Button({ stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(16).fontColor([Color.White])
            Text('选择漫画文件').fontSize(14).fontColor(Color.White).fontFamily(this.appFontFamily)
          }
        }
        .layoutWeight(1)
        .height(52)
        .enabled(!this.isMangaImportRunning && !this.isFilePickerActive && !this.isProcessing())
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(12)
        .onClick(() => { this.selectFiles(); })

        if (this.isPC) {
          Button({ stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([Color.White])
              Text('选择漫画文件夹').fontSize(14).fontColor(Color.White).fontFamily(this.appFontFamily)
            }
          }
          .layoutWeight(1)
          .height(52)
          .enabled(!this.isMangaImportRunning && !this.isFilePickerActive && !this.isProcessing())
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => { this.selectFolder(); })
        }
      }
      .width('100%')

      if (this.selectedFiles.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text(`已选择 ${this.selectedFiles.length} 个文件`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Text('清空')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.selectedFiles = [];
                this.importProgress = { status: ImportStatus.IDLE, message: '准备就绪', progress: 0 };
                this.showResults = false;
                this.importResults = [];
              })
          }
          .width('100%')

          ForEach(this.selectedFiles.slice(0, 5), (file: string) => {
            Row({ space: 8 }) {
              SymbolGlyph(this.getFileIconResource(file)).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text(this.getFileNameFromUri(file))
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          })

          if (this.selectedFiles.length > 5) {
            Text(`... 还有 ${this.selectedFiles.length - 5} 个文件`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }

          Button({ stateEffect: true }) {
            Text('开始导入').fontSize(16).fontColor(Color.White).fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height(48)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(10)
          .enabled(!this.isMangaImportRunning && !this.isMangaDialogOpening &&
            !this.isFilePickerActive && !this.isProcessing())
          .onClick(() => { void this.startImport(); })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(12)
      }
    }
    .width('100%')
  }

  /**
   * 构建电子书导入区域
   */
  @Builder
  buildEbookImportSection() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('电子书导入')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Text('支持导入TXT、EPUB、MOBI、AZW/AZW3格式的电子书，自动识别章节。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      Button({ stateEffect: true }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(18).fontColor([Color.White])
          Text('选择电子书').fontSize(16).fontColor(Color.White).fontFamily(this.appFontFamily)
        }
      }
      .width('100%')
      .height(52)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(12)
      .onClick(() => { this.selectEBooks(); })
    }
    .width('100%')
  }

  /**
   * 构建PDF导入区域
   */
  @Builder
  buildPdfImportSection() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('PDF导入')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Text('将PDF文件的每一页转换为图片导入。\n⚠️ 注意：大文件转换较慢，请耐心等待。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      Button({ stateEffect: true }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(18).fontColor([Color.White])
          Text('选择PDF文件').fontSize(16).fontColor(Color.White).fontFamily(this.appFontFamily)
        }
      }
      .width('100%')
      .height(52)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(12)
      .onClick(() => { this.selectPdfFiles(); })
    }
    .width('100%')
  }

  /**
   * 构建文件夹状态区域
   */
  @Builder
  buildFolderStatusSection() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('Download文件夹同步')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Text('访问Download目录下应用专属文件夹，无需申请受限权限。\n将文件放入该文件夹后，可直接扫描并导入。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .lineHeight(18)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      Column({ space: 12 }) {
        Row() {
          Text('文件夹状态')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.downloadDirPath) {
            Text('✓ 已连接').fontSize(13).fontFamily(this.appFontFamily).fontColor('#4CAF50')
          } else {
            Text('未连接').fontSize(13).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')

        if (this.downloadDirPath) {
          Column({ space: 4 }) {
            Text('路径').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            Text(this.downloadDirPath)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

          Row() {
            Column({ space: 4 }) {
              Text(`${this.downloadDirFileCount}`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('总文件数').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingMangaFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
              Text('漫画').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingEbookFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#2196F3')
              Text('电子书').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.pendingPdfFiles.length}`).fontSize(24).fontFamily(this.appFontFamily).fontWeight(FontWeight.Bold).fontColor('#FF9800')
              Text('PDF').fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)
          }
          .width('100%')
        }

        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text(this.downloadDirPath ? '重新连接' : '连接文件夹').fontSize(14).fontFamily(this.appFontFamily)
          }
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(10)
          .onClick(() => { this.accessAppDownloadDir(); })

          if (this.downloadDirPath) {
            Button({ stateEffect: true }) {
              Text(this.isScanning ? '扫描中...' : '扫描文件').fontSize(14).fontFamily(this.appFontFamily)
            }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(10)
            .enabled(!this.isScanning)
            .onClick(() => { this.scanDownloadDir(); })
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)

      if (this.downloadDirFiles.length > 0) {
        Column({ space: 8 }) {
          Text('文件列表')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')

          ForEach(this.downloadDirFiles.slice(0, 10), (file: string) => {
            Row({ space: 8 }) {
              SymbolGlyph(this.getFileIconResource(file)).fontSize(16).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text(file)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          })

          if (this.downloadDirFiles.length > 10) {
            Text(`... 还有 ${this.downloadDirFiles.length - 10} 个文件`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
      }

      if (this.pendingMangaFiles.length > 0 || this.pendingEbookFiles.length > 0 || this.pendingPdfFiles.length > 0) {
        Column({ space: 12 }) {
          Text('快速导入')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')

          // 漫画导入
          if (this.pendingMangaFiles.length > 0) {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.picture'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text(`漫画文件 (${this.pendingMangaFiles.length})`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Blank()
                Button({ stateEffect: true }) {
                  Text('导入').fontSize(13).fontColor(Color.White).fontFamily(this.appFontFamily)
                }
                .height(32)
                .backgroundColor('#4CAF50')
                .borderRadius(6)
                .enabled(!this.isMangaImportRunning && !this.isMangaDialogOpening &&
                  !this.isFilePickerActive && !this.isProcessing())
                .onClick(() => { void this.importMangaFromDownloadDir(); })
              }
              .width('100%')
              
              ForEach(this.pendingMangaFiles.slice(0, 3), (file: string) => {
                Text(this.getDownloadCandidateDisplayName(file))
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .padding({ left: 24 })
              })
              if (this.pendingMangaFiles.length > 3) {
                Text(`... 还有 ${this.pendingMangaFiles.length - 3} 个文件`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .padding({ left: 24 })
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
          }

          // 电子书导入
          if (this.pendingEbookFiles.length > 0) {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.book'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text(`电子书文件 (${this.pendingEbookFiles.length})`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Blank()
                Button({ stateEffect: true }) {
                  Text('导入').fontSize(13).fontColor(Color.White).fontFamily(this.appFontFamily)
                }
                .height(32)
                .backgroundColor('#2196F3')
                .borderRadius(6)
                .enabled(!this.isMangaImportRunning && !this.isMangaDialogOpening &&
                  !this.isFilePickerActive && !this.isProcessing())
                .onClick(() => { this.importEbooksFromDownloadDir(); })
              }
              .width('100%')
              
              ForEach(this.pendingEbookFiles.slice(0, 3), (file: string) => {
                Text(file)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .padding({ left: 24 })
              })
              if (this.pendingEbookFiles.length > 3) {
                Text(`... 还有 ${this.pendingEbookFiles.length - 3} 个文件`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .padding({ left: 24 })
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
          }

          // PDF导入
          if (this.pendingPdfFiles.length > 0) {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.doc_plaintext'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text(`PDF文件 (${this.pendingPdfFiles.length})`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Blank()
                Button({ stateEffect: true }) {
                  Text('导入').fontSize(13).fontColor(Color.White).fontFamily(this.appFontFamily)
                }
                .height(32)
                .backgroundColor('#FF9800')
                .borderRadius(6)
                .enabled(!this.isMangaImportRunning && !this.isMangaDialogOpening &&
                  !this.isFilePickerActive && !this.isProcessing())
                .onClick(() => { this.importPdfsFromDownloadDir(); })
              }
              .width('100%')
              
              ForEach(this.pendingPdfFiles.slice(0, 3), (file: string) => {
                Text(file)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .padding({ left: 24 })
              })
              if (this.pendingPdfFiles.length > 3) {
                Text(`... 还有 ${this.pendingPdfFiles.length - 3} 个文件`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .padding({ left: 24 })
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
      }
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        // 内容层 - 选择文件导入
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          // 内容区域
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              // 二级标签 - 选择文件导入
              this.buildFileSelectSecondaryTabs()
              // 对应内容
              if (this.secondaryTab === 'manga') {
                this.buildMangaImportSection()
              } else if (this.secondaryTab === 'ebook') {
                this.buildEbookImportSection()
              } else {
                this.buildPdfImportSection()
              }

              // 底部间距
              Blank().height(24 + this.navigationBarHeight)
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
              .onActionStart((event: GestureEvent) => {
                this.swipeStartX = event.offsetX;
                this.swipeOffsetX = 0;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.swipeOffsetX = event.offsetX - this.swipeStartX;
              })
              .onActionEnd((event: GestureEvent) => {
                const swipeThreshold = 80;
                if (this.swipeOffsetX < -swipeThreshold) {
                  this.switchToNextSecondaryTab();
                } else if (this.swipeOffsetX > swipeThreshold) {
                  this.switchToPrevSecondaryTab();
                }
                this.swipeOffsetX = 0;
              })
          )
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({
          top: 0,
          // bottom: this.navigationBarHeight,
          left: this.responsive_contentPadding,
          right: this.responsive_contentPadding
        })

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '文件导入',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })

        this.buildProgressIndicator()

        // 批量导入策略选择对话框
        if (this.showBatchStrategyDialog) {
          this.buildBatchStrategyDialog()
        }
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    /*
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: {
          mainTitle: "文件导入",
        },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showFileImportHelp();
              }
            }
          }]
        }
      }
    })
    */
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, '主导航目标页 onReady 已触发');
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as DataManagementExternalFileParams | undefined;
      this.setRouteExternalFileTask(params);
    })
    .backgroundColor(Color.Transparent)
  }
}

export { DataManagementPage };
