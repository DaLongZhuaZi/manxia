// 文件路径: entry/src/main/ets/pages/MangaFeedbackPage.ets
/**
 * 漫匣反馈中心。
 *
 * 普通用户不登录、不提交 UUID；页面只提交诊断必需信息和匿名 Issue 内容。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { DialogSurfaceStyleHelper } from 'manxia_features_ui/src/main/ets/Framework/Components/DialogSurfaceStyleHelper';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { AppInfoManager } from 'manxia_core/src/main/ets/Framework/Managers/AppInfoManager';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import {
  FeedbackAttachment,
  FeedbackCenterService,
  FeedbackContextInfo,
  FeedbackDiagnosticInfo,
  FeedbackIssueDetail,
  FeedbackIssuePost,
  FeedbackIssueStatus,
  FeedbackIssueSummary,
  FeedbackIssueType,
  FeedbackUploadSessionPayload,
  FeedbackUploadSession,
  FeedbackUploadCategory,
  FeedbackUploadProgress,
  FeedbackUploadCancelledError
} from '../Framework/Services/FeedbackCenterService';
import { FeedbackTurnstileBridge } from '../Framework/Services/FeedbackTurnstileBridge';
import {
  FeedbackLogExportResult,
  FeedbackLogExportService
} from '../Framework/Services/FeedbackLogExportService';
import {
  FEEDBACK_DRAFT_FILE_NAME,
  FEEDBACK_DRAFT_PART_FILE_NAME,
  FEEDBACK_MAX_ATTACHMENT_BYTES,
  FEEDBACK_PENDING_DIR_NAME
} from 'manxia_network/src/main/ets/Framework/Cache/FeedbackCenterCacheManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'MangaFeedbackPage';
const DRAFT_FILE_NAME: string = FEEDBACK_DRAFT_FILE_NAME;
const DRAFT_PART_FILE_NAME: string = FEEDBACK_DRAFT_PART_FILE_NAME;
const PENDING_DIR_NAME: string = FEEDBACK_PENDING_DIR_NAME;
const MAX_ATTACHMENT_TOTAL_BYTES: number = FEEDBACK_MAX_ATTACHMENT_BYTES;
const MAX_DESCRIPTION_LENGTH: number = 20000;
const DRAFT_SCHEMA_VERSION: number = 2;
const DRAFT_SAVE_DELAY_MS: number = 500;

type FeedbackPageMode = 'list' | 'detail' | 'compose';
type LocalFeedbackAttachmentStatus = 'pending' | 'uploading' | 'failed' | 'completed';
type FeedbackLogRange = 'none' | '15m' | '1h' | '3h' | 'all';
type FeedbackDraftStatus = 'editing' | 'submitting' | 'waiting_upload' | 'failed';
type FeedbackDraftResumeMode = 'compose' | 'detail';

interface LocalFeedbackAttachment {
  localId: string;
  name: string;
  localPath: string;
  size: number;
  mediaType: string;
  category: FeedbackUploadCategory;
  progress: number;
  status: LocalFeedbackAttachmentStatus;
  errorMessage: string;
  isGeneratedLog: boolean;
  uploadSession?: FeedbackUploadSession;
}

interface FeedbackDraft {
  schemaVersion: number;
  draftId: string;
  status: FeedbackDraftStatus;
  updatedAt: number;
  lastError: string;
  resumeMode: FeedbackDraftResumeMode;
  title: string;
  description: string;
  issueType: FeedbackIssueType;
  context: FeedbackContextInfo;
  attachments?: LocalFeedbackAttachment[];
  logRange?: FeedbackLogRange;
  issueNumber?: number;
  postId?: string;
  supplementText?: string;
}

interface FeedbackTurnstileJsProxy {
  onTurnstileToken: (token: string) => void;
  onTurnstileError: (message: string) => void;
}

type FeedbackTurnstileViewStatus = 'loading' | 'ready' | 'error';

interface DraftPathHolder {
  path: string;
}

interface NavDestinationPathInfo {
  param?: Object;
}

interface NavDestinationContext {
  pathStack: NavPathStack;
  pathInfo?: NavDestinationPathInfo;
}

@Component
struct MangaFeedbackPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State mode: FeedbackPageMode = 'list';
  @State issues: FeedbackIssueSummary[] = [];
  @State selectedIssue: FeedbackIssueDetail | null = null;
  @State filterType: FeedbackIssueType | '' = '';
  @State filterStatus: FeedbackIssueStatus | '' = '';
  @State searchInput: string = '';
  @State searchQuery: string = '';
  @State isLoading: boolean = false;
  @State isSubmitting: boolean = false;
  @State statusMessage: string = '';
  @State title: string = '';
  @State description: string = '';
  @State issueType: FeedbackIssueType = 'other';
  @State mangaTitle: string = '';
  @State chapterTitle: string = '';
  @State sourceName: string = '';
  @State supplementText: string = '';
  @State pendingAttachments: LocalFeedbackAttachment[] = [];
  @State uploadProgressText: string = '';
  @State logRange: FeedbackLogRange = 'none';
  @State logRangeText: string = '';
  @State logRangeCount: number = 0;
  @State showTurnstile: boolean = false;
  @State turnstileSessionId: number = 0;
  @State hasSavedDraft: boolean = false;
  @State draftStatus: FeedbackDraftStatus = 'editing';
  @State draftUpdatedAt: number = 0;
  @State draftLastError: string = '';
  @State pageEnterOpacity: number = 0;
  @State pageEnterOffsetY: number = 16;
  @State contentOpacity: number = 1;
  @State contentOffsetY: number = 0;
  @State diagnostic: FeedbackDiagnosticInfo = {
    model: '',
    system_version: '',
    app_version: '',
    build_number: 0,
    device_type: ''
  };

  private readonly scroller: Scroller = new Scroller();
  private readonly feedbackService: FeedbackCenterService = FeedbackCenterService.getInstance();
  private readonly feedbackLogExportService: FeedbackLogExportService = FeedbackLogExportService.getInstance();
  private readonly appInfoManager: AppInfoManager = AppInfoManager.getInstance();
  private readonly componentId: string = 'MangaFeedbackPage';
  private readonly lifecycle: PageLifecycleManager = new PageLifecycleManager(TAG, { enableDebug: true });
  private readonly draftPathHolder: DraftPathHolder = { path: '' };
  private attachmentSequence: number = 0;
  private pendingTurnstileResolver: ((token: string) => void) | null = null;
  private turnstileTimeoutId: number = -1;
  private turnstileRequestSequence: number = 0;
  private uploadCancelRequested: boolean = false;
  private pendingUploadIssueNumber: number = 0;
  private pendingUploadPostId: string = '';
  private contentAnimationToken: number = 0;
  private draftSaveTimerId: number = -1;
  private localDraftSequence: number = 0;
  private draftId: string = '';
  private draftWriteGeneration: number = 0;
  private draftWritePromise: Promise<void> = Promise.resolve();
  private originalThirdPartyCookieAllowed: boolean | null = null;

  aboutToAppear(): void {
    this.configureTurnstileCookiePolicy();
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType): void => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState): void => {
        this.themeState = newState;
      }
    );
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState): void => {
        this.fontState = newState;
        this.appFontFamily = newState.appFontFamily;
      }
    );
    this.appFontFamily = this.fontState.appFontFamily;
    this.loadDiagnosticInfo();
    void this.initializeFeedbackCenter();
    this.startPageEnterAnimation();
  }

  onPageShow(): void {
    this.startPageEnterAnimation();
  }

  aboutToDisappear(): void {
    if (this.draftSaveTimerId !== -1) {
      this.lifecycle.clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    if (this.hasDraftContent()) {
      void this.saveDraft('editing');
    }
    if (this.pendingTurnstileResolver !== null) {
      this.completeTurnstile('');
    }
    this.lifecycle.destroy();
    this.restoreTurnstileCookiePolicy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private configureTurnstileCookiePolicy(): void {
    try {
      this.originalThirdPartyCookieAllowed = webview.WebCookieManager.isThirdPartyCookieAllowed();
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      logger.info(TAG, `Turnstile WebView Cookie 策略已启用: thirdParty=true, original=${this.originalThirdPartyCookieAllowed}`);
    } catch (error) {
      const businessError = error as BusinessError;
      logger.warn(TAG, `Turnstile WebView Cookie 策略设置失败: code=${businessError.code}, message=${businessError.message}`);
    }
  }

  private restoreTurnstileCookiePolicy(): void {
    if (this.originalThirdPartyCookieAllowed === null) {
      return;
    }
    try {
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(this.originalThirdPartyCookieAllowed);
      logger.info(TAG, `Turnstile WebView Cookie 策略已恢复: thirdParty=${this.originalThirdPartyCookieAllowed}`);
    } catch (error) {
      const businessError = error as BusinessError;
      logger.warn(TAG, `Turnstile WebView Cookie 策略恢复失败: code=${businessError.code}, message=${businessError.message}`);
    }
    this.originalThirdPartyCookieAllowed = null;
  }

  private async loadDiagnosticInfo(): Promise<void> {
    try {
      const appInfo = await this.appInfoManager.getAppBaseInfo();
      this.diagnostic = {
        model: `${deviceInfo.brand || ''} ${deviceInfo.productModel || ''}`.trim(),
        system_version: deviceInfo.osFullName || deviceInfo.displayVersion || '',
        app_version: appInfo.versionName,
        build_number: appInfo.versionCode,
        device_type: deviceInfo.deviceType || ''
      };
    } catch (error) {
      logger.warn(TAG, `读取诊断信息失败: ${String(error)}`);
    }
  }

  private async initializeFeedbackCenter(): Promise<void> {
    await this.loadDraft();
    const context = this.getAbilityContext();
    if (context !== null) {
      await this.feedbackService.initializeCache(context);
    }
    await this.loadIssues(false);
  }

  private async loadIssues(animate: boolean = false): Promise<void> {
    this.isLoading = true;
    try {
      const result = await this.feedbackService.listIssues(1, 50, this.searchQuery, this.filterType, this.filterStatus);
      this.issues = result.items;
      this.statusMessage = this.issues.length > 0 ? '' : '还没有公开 Issue，欢迎提出第一个问题。';
      if (animate) {
        this.animateContentIn('issue-list');
      }
    } catch (error) {
      this.statusMessage = `反馈中心暂时不可用：${this.errorMessage(error)}`;
      logger.warn(TAG, `加载 Issue 失败: ${this.errorMessage(error)}`);
    } finally {
      this.isLoading = false;
    }
  }

  private async openIssue(issueNumber: number): Promise<void> {
    this.isLoading = true;
    try {
      this.selectedIssue = await this.feedbackService.getIssue(issueNumber);
      this.switchMode('detail');
      this.supplementText = '';
    } catch (error) {
      this.showToast(`读取 Issue 失败：${this.errorMessage(error)}`);
    } finally {
      this.isLoading = false;
    }
  }

  private async supportSelectedIssue(): Promise<void> {
    const issue = this.selectedIssue;
    if (issue === null || this.isSubmitting) {
      return;
    }
    this.isSubmitting = true;
    try {
      const turnstileToken = await this.requestTurnstileTokenOrAbort();
      const result = await this.feedbackService.supportIssue(issue.issue_number, turnstileToken);
      // 用服务端实时支持数先乐观更新本地状态，保证 UI 立即反映"已支持"。
      this.selectedIssue = this.withLocalSupportState(issue, result.support_count);
      // 再强制网络刷新详情校正（绕过缓存），让支持数与支持状态保持最终一致。
      try {
        this.selectedIssue = await this.feedbackService.getIssue(issue.issue_number, true);
      } catch (_) {
        // 网络刷新失败时保留乐观状态，不阻断提示。
      }
      this.showToast(result.already_supported
        ? `该 Issue 你已支持过，当前支持数 ${result.support_count}`
        : `已加入 Issue，当前支持数 ${result.support_count}`);
    } catch (error) {
      this.showToast(`加入 Issue 失败：${this.errorMessage(error)}`);
    } finally {
      this.isSubmitting = false;
    }
  }

  /**
   * 构造一份本地"已支持"状态的 Issue 详情（乐观更新用），
   * 替换 selectedIssue 引用即可立即触发详情页重渲染。
   */
  private withLocalSupportState(issue: FeedbackIssueDetail, supportCount: number): FeedbackIssueDetail {
    const labelsCopy: string[] = [];
    for (let index = 0; index < issue.labels.length; index++) {
      labelsCopy.push(issue.labels[index]);
    }
    const updated: FeedbackIssueDetail = {
      id: issue.id,
      issue_number: issue.issue_number,
      title: issue.title,
      issue_type: issue.issue_type,
      status: issue.status,
      priority: issue.priority,
      visibility: issue.visibility,
      labels: labelsCopy,
      support_count: supportCount,
      post_count: issue.post_count,
      attachment_count: issue.attachment_count,
      created_at: issue.created_at,
      updated_at: issue.updated_at,
      description: issue.description,
      diagnostic: issue.diagnostic,
      context: issue.context,
      posts: issue.posts,
      attachments: issue.attachments,
      supported_by_device: true
    };
    return updated;
  }

  private async submitSupplement(): Promise<void> {
    const issue = this.selectedIssue;
    const body = this.supplementText.trim();
    if (issue === null || body.length < 2 || this.isSubmitting) {
      if (body.length < 2) {
        this.showToast('补充内容太短');
      }
      return;
    }
    this.isSubmitting = true;
    this.uploadCancelRequested = false;
    this.pendingUploadIssueNumber = issue.issue_number;
    this.pendingUploadPostId = '';
    await this.saveDraft('submitting');
    let postCreated: boolean = false;
    try {
      const turnstileToken = await this.requestTurnstileTokenOrAbort();
      const post = await this.feedbackService.createPost(issue.issue_number, {
        body: body,
        turnstile_token: turnstileToken.length > 0 ? turnstileToken : undefined
      });
      postCreated = true;
      this.pendingUploadPostId = post.id;
      this.supplementText = '';
      if (this.pendingAttachments.length > 0) {
        await this.saveDraft('waiting_upload');
        await this.uploadAttachments(issue.issue_number, post.id);
      }
      this.selectedIssue = await this.feedbackService.getIssue(issue.issue_number, true);
      await this.clearPendingAttachmentFiles();
      this.pendingAttachments = [];
      this.pendingUploadIssueNumber = 0;
      this.pendingUploadPostId = '';
      this.hasSavedDraft = false;
      await this.deleteDraft();
      this.showToast('补充已提交');
    } catch (error) {
      // 补充内容已创建成功时（例如附件上传失败），仍立即刷新当前 Issue 的补充列表。
      if (postCreated) {
        try {
          this.selectedIssue = await this.feedbackService.getIssue(issue.issue_number, true);
        } catch (_) {
          // 刷新失败时保留本地状态，不阻断错误提示。
        }
      }
      const message = this.isUploadCancelled(error) ? '上传已取消，附件仍保留，可稍后重试' : `提交失败，草稿已保留：${this.errorMessage(error)}`;
      await this.saveDraft('failed', message);
      this.showToast(message);
    } finally {
      this.isSubmitting = false;
      this.uploadProgressText = '';
    }
  }

  private async submitIssue(): Promise<void> {
    if (this.pendingUploadIssueNumber > 0 && this.selectedIssue === null) {
      try {
        this.selectedIssue = await this.feedbackService.getIssue(this.pendingUploadIssueNumber);
        this.switchMode('detail');
        this.showToast('已恢复原 Issue，请继续上传附件');
      } catch (error) {
        this.showToast(`原 Issue 暂时无法读取：${this.errorMessage(error)}`);
      }
      return;
    }
    const title = this.title.trim();
    const description = this.description.trim();
    if (title.length < 2) {
      this.showToast('请填写 Issue 标题');
      return;
    }
    if (description.length < 10) {
      this.showToast('问题描述至少需要 10 个字符');
      return;
    }
    if (description.length > MAX_DESCRIPTION_LENGTH || this.isSubmitting) {
      return;
    }

    await this.saveDraft('submitting');
    this.isSubmitting = true;
    this.uploadCancelRequested = false;
    this.uploadProgressText = '';
    let createdIssueNumber: number = 0;
    try {
      const turnstileToken = await this.requestTurnstileTokenOrAbort();
      const issue = await this.feedbackService.createIssue({
        title: title,
        description: description,
        issue_type: this.issueType,
        diagnostic: this.diagnostic,
        context: this.buildContext(),
        turnstile_token: turnstileToken.length > 0 ? turnstileToken : undefined
      });
      createdIssueNumber = issue.issue_number;
      this.pendingUploadIssueNumber = issue.issue_number;
      this.pendingUploadPostId = '';
      this.selectedIssue = issue;
      this.switchMode('detail');
      if (this.pendingAttachments.length > 0) {
        await this.saveDraft('waiting_upload');
        await this.uploadAttachments(issue.issue_number, '');
      }
      await this.deleteDraft();
      this.selectedIssue = await this.feedbackService.getIssue(issue.issue_number, true);
      await this.clearPendingAttachmentFiles();
      this.pendingAttachments = [];
      this.pendingUploadIssueNumber = 0;
      this.pendingUploadPostId = '';
      this.hasSavedDraft = false;
      this.showToast(`Issue #${issue.issue_number} 已提交`);
      await this.loadIssues();
    } catch (error) {
      if (createdIssueNumber > 0) {
        this.switchMode('detail');
        try {
          this.selectedIssue = await this.feedbackService.getIssue(createdIssueNumber, true);
        } catch (_) {
          // 保留创建 Issue 时的本地详情，等待用户重试附件。
        }
      }
      const message = this.isUploadCancelled(error) ? '上传已取消，Issue 已创建，附件仍保留，可稍后重试' : `提交失败，草稿仍保留：${this.errorMessage(error)}`;
      await this.saveDraft('failed', message);
      this.showToast(message);
    } finally {
      this.isSubmitting = false;
      this.uploadProgressText = '';
    }
  }

  private async uploadAttachments(issueNumber: number, postId: string): Promise<void> {
    const attachments = this.pendingAttachments;
    let visibleIndex: number = 0;
    for (let index = 0; index < attachments.length; index++) {
      const attachment = attachments[index];
      if (attachment.status === 'completed') {
        continue;
      }
      visibleIndex += 1;
      this.uploadProgressText = `正在上传 ${visibleIndex}/${attachments.length}：${attachment.name}`;
      this.updateAttachmentState(attachment.localId, 0, 'uploading', '');
      let completedBytes: number = 0;
      try {
        const hashInfo = await this.feedbackService.calculateFileSha256(attachment.localPath);
        let session: FeedbackUploadSession | undefined = attachment.uploadSession;
        let renewedSession: boolean = false;
        while (true) {
          try {
            if (session === undefined || session.requested_size !== hashInfo.size) {
              // 上传会话不再要求人机验证：创建 Issue/补充时已验证，
              // 避免同一次提交流程中重复弹出 CF 验证影响体验。
              const sessionPayload: FeedbackUploadSessionPayload = {
                original_name: attachment.name,
                size: hashInfo.size,
                sha256: hashInfo.sha256,
                media_type: attachment.mediaType,
                category: attachment.category,
                post_id: postId.length > 0 ? postId : undefined
              };
              session = await this.feedbackService.createUploadSession(issueNumber, sessionPayload);
              this.updateAttachmentSession(attachment.localId, session);
              await this.saveDraft();
            }
            completedBytes = session.received_size;
            const progress: FeedbackUploadProgress = {
              completed: completedBytes,
              total: hashInfo.size,
              fileName: attachment.name
            };
            this.updateAttachmentProgress(attachment.localId, progress.completed, progress.total);
            await this.feedbackService.uploadFile(
              attachment.localPath,
              session,
              (nextProgress: FeedbackUploadProgress) => {
                progress.completed = nextProgress.completed;
                progress.total = nextProgress.total;
                completedBytes = nextProgress.completed;
                this.updateAttachmentProgress(attachment.localId, progress.completed, progress.total);
              },
              (): boolean => this.uploadCancelRequested
            );
            this.updateAttachmentState(attachment.localId, hashInfo.size, 'completed', '');
            break;
          } catch (error) {
            if (session !== undefined && !renewedSession && this.isUploadSessionInvalid(error)) {
              renewedSession = true;
              session = undefined;
              completedBytes = 0;
              this.clearAttachmentSession(attachment.localId);
              this.updateAttachmentProgress(attachment.localId, 0, hashInfo.size);
              await this.saveDraft();
              continue;
            }
            if (error instanceof Error) {
              throw error;
            }
            throw new Error(String(error));
          }
        }
      } catch (error) {
        this.updateAttachmentState(attachment.localId, completedBytes, 'failed', this.errorMessage(error));
        if (error instanceof Error) {
          throw error;
        }
        throw new Error(String(error));
      }
    }
  }

  private async retryPendingUploads(): Promise<void> {
    if (this.isSubmitting || this.selectedIssue === null || this.pendingAttachments.length === 0) {
      return;
    }
    if (this.pendingUploadPostId.length === 0 && this.supplementText.trim().length > 0) {
      await this.submitSupplement();
      return;
    }
    this.isSubmitting = true;
    this.uploadCancelRequested = false;
    this.pendingUploadIssueNumber = this.selectedIssue.issue_number;
    await this.saveDraft('waiting_upload');
    try {
      await this.uploadAttachments(this.pendingUploadIssueNumber, this.pendingUploadPostId);
      this.selectedIssue = await this.feedbackService.getIssue(this.pendingUploadIssueNumber);
      await this.clearPendingAttachmentFiles();
      this.pendingAttachments = [];
      this.pendingUploadIssueNumber = 0;
      this.pendingUploadPostId = '';
      this.hasSavedDraft = false;
      await this.deleteDraft();
      this.showToast('附件上传完成');
    } catch (error) {
      const message = this.isUploadCancelled(error) ? '上传已取消，附件仍保留' : `附件上传失败：${this.errorMessage(error)}`;
      await this.saveDraft('failed', message);
      this.showToast(message);
    } finally {
      this.isSubmitting = false;
      this.uploadProgressText = '';
    }
  }

  private cancelUpload(): void {
    if (!this.isSubmitting) {
      return;
    }
    this.uploadCancelRequested = true;
    this.uploadProgressText = '正在取消上传…';
  }

  private isUploadCancelled(error: Object | string | number | boolean | null | undefined): boolean {
    return error instanceof FeedbackUploadCancelledError;
  }

  private async requestTurnstileToken(): Promise<string> {
    // 系统浏览器方案：ArkWeb 内嵌 WebView 在当前网络环境无法通过 Cloudflare
    // Turnstile（challenge 平台域名仅 IPv6 解析 + WebView 环境被风控），
    // 因此改用系统浏览器完成验证，token 通过 manxia://turnstile Deep Link 回传。
    FeedbackTurnstileBridge.getInstance().resetPending();
    const challengeUrl: string = `${FeedbackCenterService.getInstance().getOrigin()}/turnstile-shell?client=system-browser&t=${Date.now()}`;
    logger.info(TAG, '开始系统浏览器 Turnstile 验证: ' + challengeUrl);
    this.openSystemBrowser(challengeUrl);
    this.showToast('请在系统浏览器中完成安全验证，完成后将自动返回');
    return await FeedbackTurnstileBridge.getInstance().waitForToken(60000);
  }

  /**
   * 请求 Turnstile token，未取得有效 token（超时/失败/取消）时直接抛错中止提交。
   */
  private async requestTurnstileTokenOrAbort(): Promise<string> {
    const token = await this.requestTurnstileToken();
    if (token.length === 0) {
      throw new Error('安全验证未完成，请重试');
    }
    return token;
  }

  private openSystemBrowser(url: string): void {
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        logger.warn(TAG, '无法获取宿主 Context，跳过系统浏览器打开');
        return;
      }
      const abilityContext = hostContext as common.UIAbilityContext;
      abilityContext.openLink(url, { appLinkingOnly: false });
      logger.info(TAG, '已拉起系统浏览器打开验证页');
    } catch (error) {
      logger.warn(TAG, '拉起系统浏览器失败: ' + String(error));
    }
  }

  private completeTurnstile(token: string): void {
    this.showTurnstile = false;
    if (this.turnstileTimeoutId !== -1) {
      this.lifecycle.clearTimeout(this.turnstileTimeoutId);
      this.turnstileTimeoutId = -1;
    }
    const resolver = this.pendingTurnstileResolver;
    this.pendingTurnstileResolver = null;
    if (resolver !== null) {
      resolver(token);
    }
  }

  private updateAttachmentProgress(localId: string, completed: number, total: number): void {
    const next: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      if (item.localId === localId) {
        next.push(this.copyAttachment(item, total > 0 ? Math.floor(completed * 100 / total) : 0, item.status, item.errorMessage, item.uploadSession));
      } else {
        next.push(item);
      }
    }
    this.pendingAttachments = next;
  }

  private updateAttachmentState(localId: string, progressBytes: number, status: LocalFeedbackAttachmentStatus, errorMessage: string): void {
    const next: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      if (item.localId === localId) {
        const progress = item.size > 0 ? Math.floor(progressBytes * 100 / item.size) : 0;
        next.push(this.copyAttachment(item, progress, status, errorMessage, item.uploadSession));
      } else {
        next.push(item);
      }
    }
    this.pendingAttachments = next;
  }

  private updateAttachmentSession(localId: string, session: FeedbackUploadSession): void {
    const next: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      if (item.localId === localId) {
        next.push(this.copyAttachment(item, item.progress, item.status, item.errorMessage, session));
      } else {
        next.push(item);
      }
    }
    this.pendingAttachments = next;
  }

  private clearAttachmentSession(localId: string): void {
    const next: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      if (item.localId === localId) {
        next.push(this.copyAttachment(item, item.progress, item.status, item.errorMessage, undefined));
      } else {
        next.push(item);
      }
    }
    this.pendingAttachments = next;
  }

  private isUploadSessionInvalid(error: Object | string | number | boolean | null | undefined): boolean {
    const message = this.errorMessage(error);
    return message.indexOf('HTTP 404:') === 0 || message.indexOf('HTTP 409:') === 0;
  }

  private copyAttachment(
    item: LocalFeedbackAttachment,
    progress: number,
    status: LocalFeedbackAttachmentStatus,
    errorMessage: string,
    uploadSession: FeedbackUploadSession | undefined
  ): LocalFeedbackAttachment {
    return {
      localId: item.localId,
      name: item.name,
      localPath: item.localPath,
      size: item.size,
      mediaType: item.mediaType,
      category: item.category,
      progress: progress,
      status: status,
      errorMessage: errorMessage,
      isGeneratedLog: item.isGeneratedLog,
      uploadSession: uploadSession
    };
  }

  private async selectAttachment(): Promise<void> {
    const context = this.getAbilityContext();
    if (context === null) {
      this.showToast('无法打开文件选择器');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = {
        maxSelectNumber: 5,
        fileSuffixFilters: [
          '.txt', '.log', '.json', '.xml', '.yaml', '.yml', '.md', '.csv',
          '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.avif', '.heic', '.heif',
          '.mp4', '.mov', '.mkv', '.webm', '.avi',
          '.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar', '.cbz'
        ]
      };
      documentPicker.select(options).then((uris: Array<string>) => {
        void this.copyPickedAttachments(uris, context);
      }).catch((error: Error) => {
        logger.warn(TAG, `选择附件失败: ${error.message}`);
      });
    } catch (error) {
      this.showToast(`打开文件选择器失败：${this.errorMessage(error)}`);
    }
  }

  private async attachLogsForRange(range: FeedbackLogRange): Promise<void> {
    const context = this.getAbilityContext();
    if (context === null) {
      this.showToast('无法读取 APP 日志');
      return;
    }
    await this.removeGeneratedLogAttachments();
    if (range === 'none') {
      this.logRange = 'none';
      this.logRangeText = '';
      this.logRangeCount = 0;
      await this.saveDraft();
      return;
    }
    const endTime: number = Date.now();
    let startTime: number | undefined = undefined;
    if (range === '15m') {
      startTime = endTime - 15 * 60 * 1000;
    } else if (range === '1h') {
      startTime = endTime - 60 * 60 * 1000;
    } else if (range === '3h') {
      startTime = endTime - 3 * 60 * 60 * 1000;
    }
    try {
      const result: FeedbackLogExportResult = await this.feedbackLogExportService.exportLogs(context, startTime, endTime);
      if (result.count === 0) {
        await fileIo.unlink(result.path);
        this.showToast('所选时间范围内没有 APP 日志');
        return;
      }
      if (!this.canAddPendingAttachment(result.size)) {
        await fileIo.unlink(result.path);
        this.showToast(`反馈附件总量不能超过 ${this.formatBytes(MAX_ATTACHMENT_TOTAL_BYTES)}`);
        return;
      }
      this.attachmentSequence += 1;
      const next: LocalFeedbackAttachment[] = [];
      for (const item of this.pendingAttachments) {
        next.push(item);
      }
      next.push({
        localId: `app-log-${Date.now()}_${this.attachmentSequence}`,
        name: result.name,
        localPath: result.path,
        size: result.size,
        mediaType: 'text/plain',
        category: 'text',
        progress: 0,
        status: 'pending',
        errorMessage: '',
        isGeneratedLog: true
      });
      this.pendingAttachments = next;
      this.logRange = range;
      this.logRangeText = this.logRangeLabel(range);
      this.logRangeCount = result.count;
      await this.saveDraft();
      this.showToast(`已生成 ${result.count} 条日志`);
    } catch (error) {
      this.showToast(`生成 APP 日志失败：${this.errorMessage(error)}`);
    }
  }

  private async removeGeneratedLogAttachments(): Promise<void> {
    const next: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      if (item.isGeneratedLog) {
        try {
          await fileIo.unlink(item.localPath);
        } catch (_) {
          // 临时日志文件不存在时继续清理状态。
        }
      } else {
        next.push(item);
      }
    }
    this.pendingAttachments = next;
  }

  private logRangeLabel(range: FeedbackLogRange): string {
    if (range === '15m') return '最近 15 分钟';
    if (range === '1h') return '最近 1 小时';
    if (range === '3h') return '最近 3 小时';
    if (range === 'all') return '全部日志';
    return '不附加日志';
  }

  private async copyPickedAttachment(uri: string, context: common.UIAbilityContext): Promise<void> {
    let sourceFile: fileIo.File | null = null;
    let targetFile: fileIo.File | null = null;
    try {
      const name = this.resolvePickedFileName(uri);
      const category = this.resolveFileCategory(name);
      if (category === null) {
        this.showToast(`暂不支持此文件类型：${name}`);
        return;
      }
      sourceFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(sourceFile.fd);
      const maxSize = this.resolveCategoryLimit(category);
      if (stat.size <= 0 || stat.size > maxSize) {
        this.showToast(`${name} 超过 ${this.formatBytes(maxSize)} 限制`);
        return;
      }
      if (!this.canAddPendingAttachment(stat.size)) {
        this.showToast(`反馈附件总量不能超过 ${this.formatBytes(MAX_ATTACHMENT_TOTAL_BYTES)}`);
        return;
      }
      const pendingDir = `${context.filesDir}/${PENDING_DIR_NAME}`;
      await this.ensureDirectory(pendingDir);
      this.attachmentSequence += 1;
      const safeName = this.sanitizeFileName(name);
      const targetPath = `${pendingDir}/${Date.now()}_${this.attachmentSequence}_${safeName}`;
      targetFile = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      let offset: number = 0;
      const bufferSize: number = 1024 * 1024;
      while (offset < stat.size) {
        const remaining: number = stat.size - offset;
        const readSize: number = remaining > bufferSize ? bufferSize : remaining;
        const buffer = new ArrayBuffer(readSize);
        const readBytes = await fileIo.read(sourceFile.fd, buffer, { length: readSize });
        if (readBytes !== readSize) {
          throw new Error('读取附件内容不完整');
        }
        const writtenBytes = await fileIo.write(targetFile.fd, buffer, { length: readBytes });
        if (writtenBytes !== readBytes) {
          throw new Error('保存附件内容不完整');
        }
        offset += readBytes;
      }
      const next: LocalFeedbackAttachment[] = [];
      for (const item of this.pendingAttachments) {
        next.push(item);
      }
      next.push({
        localId: `${Date.now()}_${this.attachmentSequence}`,
        name: name,
        localPath: targetPath,
        size: stat.size,
        mediaType: this.resolveMediaType(name),
        category: category,
        progress: 0,
        status: 'pending',
        errorMessage: '',
        isGeneratedLog: false
      });
      this.pendingAttachments = next;
      await this.saveDraft();
    } catch (error) {
      this.showToast(`保存附件失败：${this.errorMessage(error)}`);
    } finally {
      if (sourceFile !== null) {
        await fileIo.close(sourceFile);
      }
      if (targetFile !== null) {
        await fileIo.close(targetFile);
      }
    }
  }

  private async removeAttachment(item: LocalFeedbackAttachment): Promise<void> {
    try {
      await fileIo.unlink(item.localPath);
    } catch (error) {
      logger.warn(TAG, `删除本地附件失败: ${this.errorMessage(error)}`);
    }
    const next: LocalFeedbackAttachment[] = [];
    for (const current of this.pendingAttachments) {
      if (current.localId !== item.localId) {
        next.push(current);
      }
    }
    this.pendingAttachments = next;
    await this.saveDraft();
  }

  private resolvePickedFileName(uri: string): string {
    try {
      const info = new fileUri.FileUri(uri);
      if (info.name.length > 0) {
        return info.name;
      }
    } catch (_) {
      // 回退到 URI 尾段。
    }
    const lastSlash = uri.lastIndexOf('/');
    return lastSlash >= 0 ? decodeURIComponent(uri.substring(lastSlash + 1)) : 'feedback_attachment.bin';
  }

  private resolveFileCategory(name: string): FeedbackUploadCategory | null {
    const suffix = this.fileSuffix(name);
    if (['txt', 'log', 'json', 'xml', 'yaml', 'yml', 'md', 'csv'].includes(suffix)) {
      return 'text';
    }
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'avif', 'heic', 'heif'].includes(suffix)) {
      return 'image';
    }
    if (['mp4', 'mov', 'mkv', 'webm', 'avi'].includes(suffix)) {
      return 'video';
    }
    if (['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'cbz'].includes(suffix)) {
      return 'archive';
    }
    return null;
  }

  private resolveCategoryLimit(category: FeedbackUploadCategory): number {
    if (category === 'text') {
      return 10 * 1024 * 1024;
    }
    if (category === 'image') {
      return 20 * 1024 * 1024;
    }
    return 80 * 1024 * 1024;
  }

  private pendingAttachmentBytes(): number {
    let total: number = 0;
    for (const item of this.pendingAttachments) {
      total += item.size;
    }
    return total;
  }

  private canAddPendingAttachment(size: number): boolean {
    return size > 0 && this.pendingAttachmentBytes() + size <= MAX_ATTACHMENT_TOTAL_BYTES;
  }

  private resolveMediaType(name: string): string {
    const suffix = this.fileSuffix(name);
    const mediaTypes: Map<string, string> = new Map<string, string>();
    mediaTypes.set('txt', 'text/plain');
    mediaTypes.set('log', 'text/plain');
    mediaTypes.set('json', 'application/json');
    mediaTypes.set('xml', 'application/xml');
    mediaTypes.set('yaml', 'application/yaml');
    mediaTypes.set('yml', 'application/yaml');
    mediaTypes.set('md', 'text/markdown');
    mediaTypes.set('csv', 'text/csv');
    mediaTypes.set('png', 'image/png');
    mediaTypes.set('jpg', 'image/jpeg');
    mediaTypes.set('jpeg', 'image/jpeg');
    mediaTypes.set('gif', 'image/gif');
    mediaTypes.set('webp', 'image/webp');
    mediaTypes.set('bmp', 'image/bmp');
    mediaTypes.set('avif', 'image/avif');
    mediaTypes.set('heic', 'image/heic');
    mediaTypes.set('heif', 'image/heic');
    mediaTypes.set('mp4', 'video/mp4');
    mediaTypes.set('mov', 'video/quicktime');
    mediaTypes.set('avi', 'video/x-msvideo');
    mediaTypes.set('webm', 'video/webm');
    mediaTypes.set('mkv', 'video/x-matroska');
    mediaTypes.set('zip', 'application/zip');
    mediaTypes.set('tar', 'application/x-tar');
    mediaTypes.set('gz', 'application/gzip');
    mediaTypes.set('bz2', 'application/x-bzip2');
    mediaTypes.set('xz', 'application/x-xz');
    mediaTypes.set('7z', 'application/x-7z-compressed');
    mediaTypes.set('rar', 'application/vnd.rar');
    mediaTypes.set('cbz', 'application/zip');
    return mediaTypes.get(suffix) || 'application/octet-stream';
  }

  private fileSuffix(name: string): string {
    const dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  private sanitizeFileName(name: string): string {
    const replaced = name.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_').trim();
    return replaced.length > 0 ? replaced.substring(0, 160) : 'feedback_attachment.bin';
  }

  private buildContext(): FeedbackContextInfo {
    return {
      manga_title: this.mangaTitle.trim(),
      chapter_title: this.chapterTitle.trim(),
      source: this.sourceName.trim()
    };
  }

  private async resetComposeForm(): Promise<void> {
    if (this.draftSaveTimerId !== -1) {
      this.lifecycle.clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    await this.clearPendingAttachmentFiles();
    this.title = '';
    this.description = '';
    this.issueType = 'other';
    this.mangaTitle = '';
    this.chapterTitle = '';
    this.sourceName = '';
    this.uploadProgressText = '';
    this.pendingAttachments = [];
    this.logRange = 'none';
    this.logRangeText = '';
    this.logRangeCount = 0;
    this.supplementText = '';
    this.pendingUploadIssueNumber = 0;
    this.pendingUploadPostId = '';
    this.hasSavedDraft = false;
    this.draftStatus = 'editing';
    this.draftUpdatedAt = 0;
    this.draftLastError = '';
    this.draftId = '';
    await this.deleteDraft();
  }

  private async copyPickedAttachments(uris: Array<string>, context: common.UIAbilityContext): Promise<void> {
    for (const uri of uris) {
      await this.copyPickedAttachment(uri, context);
    }
  }

  private hasDraftContent(): boolean {
    return this.pendingUploadIssueNumber > 0
      || this.title.trim().length > 0
      || this.description.trim().length > 0
      || this.mangaTitle.trim().length > 0
      || this.chapterTitle.trim().length > 0
      || this.sourceName.trim().length > 0
      || this.supplementText.trim().length > 0
      || this.pendingAttachments.length > 0;
  }

  private ensureDraftId(): string {
    if (this.draftId.length === 0) {
      this.localDraftSequence += 1;
      this.draftId = `feedback-draft-${Date.now()}-${this.localDraftSequence}`;
    }
    return this.draftId;
  }

  private resolveDraftStatus(value: FeedbackDraftStatus | undefined): FeedbackDraftStatus {
    if (value === 'submitting' || value === 'waiting_upload' || value === 'failed') {
      return value;
    }
    return 'editing';
  }

  private resolveDraftResumeMode(value: FeedbackDraftResumeMode | undefined): FeedbackDraftResumeMode {
    return value === 'detail' ? 'detail' : 'compose';
  }

  private scheduleDraftSave(): void {
    if (!this.hasDraftContent()) {
      this.hasSavedDraft = false;
      return;
    }
    this.hasSavedDraft = true;
    this.draftStatus = 'editing';
    this.draftLastError = '';
    if (this.draftSaveTimerId !== -1) {
      this.lifecycle.clearTimeout(this.draftSaveTimerId);
    }
    this.draftSaveTimerId = this.lifecycle.setTimeout((): void => {
      this.draftSaveTimerId = -1;
      void this.saveDraft('editing');
    }, DRAFT_SAVE_DELAY_MS);
  }

  private async readDraftFile(path: string): Promise<FeedbackDraft | null> {
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        await fileIo.read(file.fd, buffer);
        const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
        return JSON.parse(text) as FeedbackDraft;
      } finally {
        await fileIo.close(file);
      }
    } catch (_) {
      return null;
    }
  }

  private async loadDraft(): Promise<void> {
    const context = this.getAbilityContext();
    if (context === null) {
      return;
    }
    const path = `${context.filesDir}/${DRAFT_FILE_NAME}`;
    const partPath = `${context.filesDir}/${DRAFT_PART_FILE_NAME}`;
    this.draftPathHolder.path = path;
    let draft = await this.readDraftFile(path);
    if (draft === null) {
      draft = await this.readDraftFile(partPath);
      if (draft !== null) {
        try {
          await fileIo.rename(partPath, path);
        } catch (error) {
          logger.warn(TAG, `恢复草稿临时文件失败: ${this.errorMessage(error)}`);
        }
      }
    }
    if (draft === null) {
      return;
    }
    this.draftId = draft.draftId || '';
    this.draftStatus = this.resolveDraftStatus(draft.status);
    this.draftUpdatedAt = typeof draft.updatedAt === 'number' ? draft.updatedAt : 0;
    this.draftLastError = draft.lastError || '';
    this.title = draft.title || '';
    this.description = draft.description || '';
    this.issueType = draft.issueType || 'other';
    this.mangaTitle = draft.context?.manga_title || '';
    this.chapterTitle = draft.context?.chapter_title || '';
    this.sourceName = draft.context?.source || '';
    this.supplementText = draft.supplementText || '';
    this.pendingUploadIssueNumber = draft.issueNumber || 0;
    this.pendingUploadPostId = draft.postId || '';
    this.logRange = draft.logRange || 'none';
    this.logRangeText = this.logRange === 'none' ? '' : this.logRangeLabel(this.logRange);
    if (draft.attachments) {
      this.pendingAttachments = await this.restoreDraftAttachments(draft.attachments);
    }
    this.hasSavedDraft = this.hasDraftContent();
    if (!this.hasSavedDraft) {
      await this.deleteDraft();
    }
  }

  private async saveDraft(status?: FeedbackDraftStatus, lastError: string = ''): Promise<void> {
    const context = this.getAbilityContext();
    if (context === null) {
      return;
    }
    if (status !== undefined) {
      this.draftStatus = status;
    }
    this.draftLastError = lastError;
    this.hasSavedDraft = this.hasDraftContent();
    if (!this.hasSavedDraft) {
      return;
    }
    const path = this.draftPathHolder.path.length > 0 ? this.draftPathHolder.path : `${context.filesDir}/${DRAFT_FILE_NAME}`;
    this.draftPathHolder.path = path;
    const partPath = `${context.filesDir}/${DRAFT_PART_FILE_NAME}`;
    await this.ensureDirectory(`${context.filesDir}/feedback`);
    const attachments: LocalFeedbackAttachment[] = [];
    for (const item of this.pendingAttachments) {
      attachments.push({
        localId: item.localId,
        name: item.name,
        localPath: item.localPath,
        size: item.size,
        mediaType: item.mediaType,
        category: item.category,
        progress: item.progress,
        status: item.status === 'completed' ? 'completed' : 'pending',
        errorMessage: item.errorMessage,
        isGeneratedLog: item.isGeneratedLog,
        uploadSession: item.uploadSession
      });
    }
    const draft: FeedbackDraft = {
      schemaVersion: DRAFT_SCHEMA_VERSION,
      draftId: this.ensureDraftId(),
      status: this.draftStatus,
      updatedAt: Date.now(),
      lastError: this.draftLastError,
      resumeMode: this.mode === 'detail' || this.pendingUploadIssueNumber > 0 ? 'detail' : this.resolveDraftResumeMode(undefined),
      title: this.title,
      description: this.description,
      issueType: this.issueType,
      context: this.buildContext(),
      attachments: attachments,
      logRange: this.logRange,
      issueNumber: this.pendingUploadIssueNumber > 0 ? this.pendingUploadIssueNumber : undefined,
      postId: this.pendingUploadPostId.length > 0 ? this.pendingUploadPostId : undefined,
      supplementText: this.supplementText
    };
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(JSON.stringify(draft));
    const buffer = new ArrayBuffer(bytes.length);
    new Uint8Array(buffer).set(bytes);
    const writeGeneration = this.draftWriteGeneration;
    const writeDraft: () => Promise<void> = async (): Promise<void> => {
      if (writeGeneration !== this.draftWriteGeneration) {
        return;
      }
      const file = await fileIo.open(partPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, buffer);
      } finally {
        await fileIo.close(file);
      }
      await fileIo.rename(partPath, path);
    };
    this.draftWritePromise = this.draftWritePromise
      .catch((): void => {
        // 让下一次保存可以继续执行，避免一次写入失败卡住整个草稿队列。
      })
      .then(writeDraft);
    await this.draftWritePromise;
    this.draftUpdatedAt = draft.updatedAt;
  }

  private async restoreDraftAttachments(items: LocalFeedbackAttachment[]): Promise<LocalFeedbackAttachment[]> {
    const restored: LocalFeedbackAttachment[] = [];
    let restoredBytes: number = 0;
    for (const item of items) {
      try {
        const stat = await fileIo.stat(item.localPath);
        if (stat.size <= 0 || stat.size > this.resolveCategoryLimit(item.category)) {
          continue;
        }
        if (restoredBytes + stat.size > MAX_ATTACHMENT_TOTAL_BYTES) {
          logger.warn(TAG, `草稿附件总量超过限制，已跳过: ${item.name}`);
          continue;
        }
        const restoredStatus: LocalFeedbackAttachmentStatus = item.status === 'completed'
          ? 'completed'
          : item.status === 'failed' ? 'failed' : 'pending';
        restored.push({
          localId: item.localId,
          name: item.name,
          localPath: item.localPath,
          size: stat.size,
          mediaType: item.mediaType,
          category: item.category,
          progress: restoredStatus === 'completed' ? 100 : item.progress,
          status: restoredStatus,
          errorMessage: item.errorMessage || '',
          isGeneratedLog: item.isGeneratedLog === true,
          uploadSession: item.uploadSession
        });
        restoredBytes += stat.size;
      } catch (_) {
        logger.warn(TAG, `草稿附件不存在，已跳过: ${item.name}`);
      }
    }
    return restored;
  }

  private async clearPendingAttachmentFiles(): Promise<void> {
    for (const item of this.pendingAttachments) {
      try {
        await fileIo.unlink(item.localPath);
      } catch (_) {
        // 本地临时文件不存在时继续清理其它附件。
      }
    }
  }

  private async deleteDraft(): Promise<void> {
    this.draftWriteGeneration += 1;
    try {
      await this.draftWritePromise;
    } catch (_) {
      // 写入失败时仍然继续删除已存在的草稿文件。
    }
    const context = this.getAbilityContext();
    if (this.draftPathHolder.path.length > 0) {
      try {
        await fileIo.unlink(this.draftPathHolder.path);
      } catch (_) {
        // 草稿不存在时无需提示。
      }
    }
    if (context !== null) {
      try {
        await fileIo.unlink(`${context.filesDir}/${DRAFT_PART_FILE_NAME}`);
      } catch (_) {
        // 临时草稿不存在时无需提示。
      }
    }
    this.draftPathHolder.path = '';
    this.draftId = '';
    this.draftStatus = 'editing';
    this.draftUpdatedAt = 0;
    this.draftLastError = '';
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(`路径不是目录: ${path}`);
      }
    } catch (_) {
      await fileIo.mkdir(path, true);
    }
  }

  private startPageEnterAnimation(): void {
    this.pageEnterOpacity = 0;
    this.pageEnterOffsetY = 16;
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.pageEnterOpacity = 1;
      this.pageEnterOffsetY = 0;
    });
  }

  private animateContentIn(trigger: string): void {
    const token = this.contentAnimationToken + 1;
    this.contentAnimationToken = token;
    this.contentOpacity = 0.12;
    this.contentOffsetY = 8;
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      if (token === this.contentAnimationToken) {
        this.contentOpacity = 1;
        this.contentOffsetY = 0;
      }
    });
    logger.debug(TAG, `反馈中心内容动画: trigger=${trigger}`);
  }

  private switchMode(nextMode: FeedbackPageMode): void {
    if (this.mode === nextMode) {
      return;
    }
    this.mode = nextMode;
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: { duration: 220 }
    });
    this.animateContentIn(`mode:${nextMode}`);
  }

  private async resumeDraft(): Promise<void> {
    this.hasSavedDraft = false;
    if (this.pendingUploadIssueNumber > 0) {
      try {
        this.selectedIssue = await this.feedbackService.getIssue(this.pendingUploadIssueNumber);
        this.statusMessage = '已恢复原 Issue，请继续上传附件。';
        this.switchMode('detail');
      } catch (error) {
        this.statusMessage = `原 Issue 暂时无法读取：${this.errorMessage(error)}`;
        this.hasSavedDraft = this.hasDraftContent();
        this.switchMode('compose');
      }
      return;
    }
    this.switchMode('compose');
  }

  private getAbilityContext(): common.UIAbilityContext | null {
    const hostContext = this.getUIContext().getHostContext();
    return hostContext ? hostContext as common.UIAbilityContext : null;
  }

  private formatBytes(value: number): string {
    if (value >= 1024 * 1024) {
      return `${Math.floor(value / 1024 / 1024)} MiB`;
    }
    return `${Math.floor(value / 1024)} KiB`;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
  }

  private errorMessage(error: Object | string | number | boolean | null | undefined): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }

  private goBack(): void {
    if (this.mode === 'list') {
      this.pathStack.pop();
      return;
    }
    if (this.mode === 'detail') {
      this.selectedIssue = null;
      this.switchMode('list');
      return;
    }
    void this.saveDraft('editing');
    this.switchMode(this.selectedIssue === null ? 'list' : 'detail');
  }

  private filteredIssues(): FeedbackIssueSummary[] {
    // 类型和状态已由服务端筛选，保留该方法作为列表渲染的单一入口。
    return this.issues;
  }

  private statusText(value: string): string {
    if (value === 'open') return '开放';
    if (value === 'in_progress') return '处理中';
    if (value === 'resolved') return '已解决';
    if (value === 'closed') return '已关闭';
    if (value === 'merged') return '已合并';
    return value;
  }

  private statusColor(value: string): ResourceColor {
    if (value === 'open' || value === 'resolved') {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (value === 'in_progress') {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (value === 'merged') {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private issueTypeText(value: FeedbackIssueType): string {
    if (value === 'source') return '图源';
    if (value === 'book_source') return '书源';
    if (value === 'software') return '软件';
    if (value === 'ui') return 'UI';
    if (value === 'suggestion') return '建议';
    return '其他';
  }

  private formatDate(value: string): string {
    try {
      return new Date(value).toLocaleString();
    } catch (_) {
      return value;
    }
  }

  private draftStatusText(): string {
    if (this.draftStatus === 'submitting') return '提交中';
    if (this.draftStatus === 'waiting_upload') return '等待附件上传';
    if (this.draftStatus === 'failed') return '上次提交失败';
    return '编辑中';
  }

  private draftUpdatedText(): string {
    if (this.draftUpdatedAt <= 0) {
      return '刚刚保存';
    }
    return `最后保存：${new Date(this.draftUpdatedAt).toLocaleString()}`;
  }

  private handleTitleBarBack(): boolean {
    if (this.showTurnstile) {
      this.completeTurnstile('');
      return true;
    }
    if (this.mode === 'list') {
      return false;
    }
    this.goBack();
    return true;
  }

  @Builder
  private buildTypeChip(value: FeedbackIssueType, label: string): void {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.issueType === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.issueType === value
          ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
    }
      .layoutWeight(1)
      .height(36)
      .backgroundColor(this.issueType === value
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
      .borderRadius(999)
      .border({
        width: 1,
        color: this.issueType === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .stateStyles({
        pressed: {
          .scale({ x: 0.96, y: 0.96 })
          .opacity(0.82)
        }
      })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick(() => {
        this.issueType = value;
        this.scheduleDraftSave();
      });
  }

  @Builder
  private buildFilterChip(value: FeedbackIssueType | '', label: string): void {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.filterType === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.filterType === value
          ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
    }
      .width(72)
      .height(36)
      .backgroundColor(this.filterType === value
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
      .borderRadius(999)
      .border({
        width: 1,
        color: this.filterType === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .stateStyles({
        pressed: {
          .scale({ x: 0.96, y: 0.96 })
          .opacity(0.82)
        }
      })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick(() => {
        this.filterType = value;
        void this.loadIssues(true);
      });
  }

  @Builder
  private buildStatusFilterChip(value: FeedbackIssueStatus | '', label: string): void {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.filterStatus === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.filterStatus === value
          ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
    }
      .width(76)
      .height(36)
      .backgroundColor(this.filterStatus === value
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
      .borderRadius(999)
      .border({
        width: 1,
        color: this.filterStatus === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .stateStyles({
        pressed: {
          .scale({ x: 0.96, y: 0.96 })
          .opacity(0.82)
        }
      })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick(() => {
        this.filterStatus = value;
        void this.loadIssues(true);
      });
  }

  @Builder
  private buildLogRangeChip(value: FeedbackLogRange, label: string, identifier: string): void {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.logRange === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.logRange === value
          ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
    }
      .id(identifier)
      .layoutWeight(1)
      .height(34)
      .backgroundColor(this.logRange === value
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
      .borderRadius(999)
      .border({
        width: 1,
        color: this.logRange === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .stateStyles({
        pressed: {
          .scale({ x: 0.96, y: 0.96 })
          .opacity(0.82)
        }
      })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onClick(() => {
        void this.attachLogsForRange(value);
      });
  }

  private attachmentStatusText(attachment: LocalFeedbackAttachment): string {
    if (attachment.status === 'uploading') return `上传中 ${attachment.progress}%`;
    if (attachment.status === 'completed') return '已完成';
    if (attachment.status === 'failed') return attachment.errorMessage.length > 0 ? `失败：${attachment.errorMessage}` : '上传失败';
    return '待上传';
  }

  @Builder
  private buildIssueCard(issue: FeedbackIssueSummary): void {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text(`#${issue.issue_number}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
        }
        Text(this.issueTypeText(issue.issue_type))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8);
        Blank().layoutWeight(1);
        Text(this.statusText(issue.status))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.statusColor(issue.status))
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .border({ width: 1, color: this.statusColor(issue.status) })
          .borderRadius(999);
      }
      Text(issue.title)
        .fontSize(17)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Row({ space: 8 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(13)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
          Text(`支持 ${issue.support_count}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        }
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(13)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
          Text(`补充 ${issue.post_count}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        }
        Blank().layoutWeight(1);
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
      }
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
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .stateStyles({
        pressed: {
          .scale({ x: 0.985, y: 0.985 })
          .opacity(0.82)
        }
      })
      .animation({ duration: 170, curve: Curve.EaseOut })
      .onClick(() => {
        void this.openIssue(issue.issue_number);
      });
  }

  @Builder
  private buildIssueList(): void {
    Column({ space: 14 }) {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(46)
              .height(46)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .borderRadius(15);
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(23)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
          }
          Column({ space: 3 }) {
            Text('匿名 Issue 协作')
              .fontSize(21)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
            Text('把相同问题聚到一起，让反馈更容易被看见')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Button({ stateEffect: true }) {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
              Text('提出')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
            }
          }
            .id('feedback_create_issue')
            .height(40)
            .padding({ left: 12, right: 13 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(14)
            .stateStyles({
              pressed: {
                .scale({ x: 0.95, y: 0.95 })
                .opacity(0.82)
              }
            })
            .animation({ duration: 160, curve: Curve.EaseOut })
            .onClick(() => {
              this.switchMode('compose');
            });
        }
        Text('可以提出问题，也可以加入已有 Issue。我们只收集诊断所需的机型、系统和 APP 版本。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .lineHeight(19)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        Row({ space: 6 }) {
          Text('匿名参与')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8);
          Text('日志附件默认仅管理员可见')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        });

      if (this.hasSavedDraft) {
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(34)
              .height(34)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(11);
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(17)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)]);
          }
          Column({ space: 3 }) {
            Text('检测到未提交草稿')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
            Text(`${this.draftStatusText()} · ${this.draftUpdatedText()}`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            if (this.draftLastError.length > 0) {
              Text(`上次失败：${this.draftLastError}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme));
            }
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Row({ space: 6 }) {
            Button({ stateEffect: true }) {
              Text('删除')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme));
            }
              .id('feedback_delete_draft')
              .height(34)
              .padding({ left: 10, right: 10 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
              .borderRadius(999)
              .stateStyles({
                pressed: {
                  .scale({ x: 0.95, y: 0.95 })
                  .opacity(0.78)
                }
              })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                void this.resetComposeForm();
              });
            Button({ stateEffect: true }) {
              Text('继续编辑')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
            }
              .id('feedback_resume_draft')
              .height(34)
              .padding({ left: 12, right: 12 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .borderRadius(999)
              .stateStyles({
                pressed: {
                  .scale({ x: 0.95, y: 0.95 })
                  .opacity(0.82)
                }
              })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                void this.resumeDraft();
              });
          }
        }
          .width('100%')
          .padding(12)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .borderRadius(14)
          .border({ width: 1, color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) });
      }

      Column({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
          TextInput({ placeholder: '搜索标题、描述、编号或标签', text: this.searchInput })
            .layoutWeight(1)
            .height(42)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .onChange((value: string) => {
              this.searchInput = value;
            });
          if (this.searchInput.length > 0) {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(15)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
            }
              .id('feedback_clear_search')
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .borderRadius(16)
              .onClick(() => {
                this.searchInput = '';
              });
          }
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
          }
            .id('feedback_search_button')
            .width(42)
            .height(42)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(13)
            .stateStyles({
              pressed: {
                .scale({ x: 0.92, y: 0.92 })
                .opacity(0.82)
              }
            })
            .animation({ duration: 160, curve: Curve.EaseOut })
            .onClick(() => {
              this.searchQuery = this.searchInput.trim();
              void this.loadIssues(true);
            });
        }
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme));
        Row({ space: 8 }) {
          Text('类型')
            .width(34)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
          Flex({
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start,
            space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
          }) {
            this.buildFilterChip('', '全部');
            this.buildFilterChip('source', '图源');
            this.buildFilterChip('book_source', '书源');
            this.buildFilterChip('software', '软件');
            this.buildFilterChip('ui', 'UI');
            this.buildFilterChip('suggestion', '建议');
            this.buildFilterChip('other', '其他');
          }
            .layoutWeight(1)
        }
          .width('100%')
          .alignItems(VerticalAlign.Top);
        Row({ space: 8 }) {
          Text('状态')
            .width(34)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
          Flex({
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start,
            space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
          }) {
            this.buildStatusFilterChip('', '全部');
            this.buildStatusFilterChip('open', '开放');
            this.buildStatusFilterChip('in_progress', '处理中');
            this.buildStatusFilterChip('resolved', '已解决');
            this.buildStatusFilterChip('closed', '已关闭');
            this.buildStatusFilterChip('merged', '已合并');
          }
            .layoutWeight(1)
        }
          .width('100%')
          .alignItems(VerticalAlign.Top);
      }
        .width('100%')
        .padding(12)
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });

      if (this.isLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
          Text('正在加载反馈…')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        }
          .width('100%')
          .padding({ top: 42, bottom: 42 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center);
      } else if (this.filteredIssues().length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(34)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text(this.statusMessage.length > 0 ? this.statusMessage : '没有匹配的 Issue')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          Text('可以换一个关键词或筛选条件')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
          .width('100%')
          .padding({ top: 38, bottom: 38, left: 20, right: 20 })
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          });
      } else {
        Column({ space: 10 }) {
          ForEach(this.filteredIssues(), (issue: FeedbackIssueSummary) => {
            this.buildIssueCard(issue);
          }, (issue: FeedbackIssueSummary) => issue.id);
        }
          .width('100%');
      }
    }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 16, right: 16, bottom: 40 });
  }

  @Builder
  private buildDetail(issue: FeedbackIssueDetail): void {
    Column({ space: 14 }) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
            Text(`#${issue.issue_number}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
          }
          Text(this.issueTypeText(issue.issue_type))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8);
          Blank().layoutWeight(1);
          Text(this.statusText(issue.status))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor(issue.status))
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .border({ width: 1, color: this.statusColor(issue.status) })
            .borderRadius(999);
        }
        Text(issue.title)
          .fontSize(21)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
        Row({ space: 8 }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.star'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
            Text(`支持 ${issue.support_count}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
            Text(`补充 ${issue.post_count}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
          Blank().layoutWeight(1);
          Button({ stateEffect: true }) {
            Row({ space: 5 }) {
              SymbolGlyph(issue.supported_by_device ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
                .fontSize(15)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
              Text(this.isSubmitting ? '处理中…' : (issue.supported_by_device ? '已支持' : '我也遇到'))
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
            }
          }
            .id('feedback_support_issue')
            .height(38)
            .padding({ left: 13, right: 13 })
            .backgroundColor(issue.supported_by_device
              ? ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(999)
            .stateStyles({
              pressed: {
                .scale({ x: 0.95, y: 0.95 })
                .opacity(0.82)
              }
            })
            .animation({ duration: 160, curve: Curve.EaseOut })
            .enabled(!issue.supported_by_device)
            .onClick(() => {
              void this.supportSelectedIssue();
            });
        }
      }
        .width('100%')
        .padding(18)
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        });

      this.buildTimelineCard('匿名用户', issue.description, issue.created_at, []);
      if (issue.posts.length > 0) {
        ForEach(issue.posts, (post: FeedbackIssuePost) => {
          this.buildTimelineCard(post.author_kind === 'admin' ? '管理员' : '匿名用户', post.body, post.created_at, post.attachments);
        }, (post: FeedbackIssuePost) => post.id);
      }
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('诊断信息')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Blank().layoutWeight(1);
          Text('仅收集诊断必需信息')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('机型')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(issue.diagnostic.model || '未提供')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Column({ space: 4 }) {
            Text('系统')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(issue.diagnostic.system_version || '未提供')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Column({ space: 4 }) {
            Text('APP')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(`${issue.diagnostic.app_version || '未提供'} (${issue.diagnostic.build_number})`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
        }
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.highlighter_line'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Column({ space: 2 }) {
            Text('匿名补充')
              .fontSize(15)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
            Text('补充复现步骤或更多线索')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
          }
            .alignItems(HorizontalAlign.Start);
        }
        TextArea({ placeholder: '补充复现步骤、出现频率或更多日志信息…', text: this.supplementText })
          .width('100%')
          .height(110)
          .fontFamily(this.appFontFamily)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .onChange((value: string) => {
            this.supplementText = value;
            this.scheduleDraftSave();
          });
        this.buildAttachmentPicker();
        Button({ stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_up_circle'))
              .fontSize(17)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
            Text('提交补充')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
          }
        }
          .id('feedback_submit_supplement')
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(999)
          .stateStyles({
            pressed: {
              .scale({ x: 0.98, y: 0.98 })
              .opacity(0.82)
            }
          })
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            void this.submitSupplement();
          });
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
    }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 16, right: 16, bottom: 40 });
  }

  @Builder
  private buildTimelineCard(author: string, body: string, createdAt: string, attachments: FeedbackAttachment[]): void {
    Column({ space: 8 }) {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(30)
            .height(30)
            .backgroundColor(author === '管理员'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .borderRadius(999);
          if (author === '管理员') {
            SymbolGlyph($r('sys.symbol.star'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
          } else {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
          }
        }
        Column({ space: 2 }) {
          Text(author)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Text('匿名参与')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
          .margin({ left: 8 })
          .alignItems(HorizontalAlign.Start);
        Blank().layoutWeight(1);
        Text(this.formatDate(createdAt)).fontSize(11).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
      }
      Text(body)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .lineHeight(21)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .copyOption(CopyOptions.LocalDevice);
      if (attachments.length > 0) {
        ForEach(attachments, (attachment: FeedbackAttachment) => {
          Row() {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
            Text(attachment.original_name)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
            Blank().layoutWeight(1);
            Text(this.formatBytes(attachment.size)).fontSize(11).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
          }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(10);
        }, (attachment: FeedbackAttachment) => attachment.id);
      }
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
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      });
  }

  @Builder
  private buildAttachmentPicker(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(34)
            .height(34)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(11);
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(17)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
        }
        Column({ space: 3 }) {
          Text('附件')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Text('日志、图片、视频或压缩包')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
          .alignItems(HorizontalAlign.Start);
        Blank().layoutWeight(1);
        Button({ stateEffect: true }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.folder_badge_plus'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)]);
            Text('选择文件')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
          }
        }
          .id('feedback_select_attachment')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(999)
          .stateStyles({
            pressed: {
              .scale({ x: 0.95, y: 0.95 })
              .opacity(0.8)
            }
          })
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            void this.selectAttachment();
          });
      }
      Column({ space: 7 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('从 APP 日志系统生成')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        }
        Row({ space: 5 }) {
          this.buildLogRangeChip('15m', '15 分钟', 'feedback_log_15m');
          this.buildLogRangeChip('1h', '1 小时', 'feedback_log_1h');
          this.buildLogRangeChip('3h', '3 小时', 'feedback_log_3h');
          this.buildLogRangeChip('all', '全部', 'feedback_log_all');
          this.buildLogRangeChip('none', '清除', 'feedback_log_none');
        }
          .width('100%');
        if (this.logRangeText.length > 0) {
          Text(`${this.logRangeText} · ${this.logRangeCount} 条日志 · 已脱敏`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
        }
        }
          .width('100%')
          .padding(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) });
      ForEach(this.pendingAttachments, (attachment: LocalFeedbackAttachment) => {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(16)
            .fontColor([attachment.status === 'failed'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Column({ space: 3 }) {
            Text(attachment.name)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
            Text(this.attachmentStatusText(attachment))
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(attachment.status === 'failed'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          if (attachment.status === 'failed' && !this.isSubmitting) {
            Button({ stateEffect: true }) {
              Row({ space: 3 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(13)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
                Text('重试')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
              }
            }
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                void this.retryPendingUploads();
              });
          }
          Text(`${attachment.progress}%`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
          Button({ stateEffect: true }) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
              Text('移除')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            }
          }
            .backgroundColor(Color.Transparent)
            .enabled(!this.isSubmitting)
            .onClick(() => {
              void this.removeAttachment(attachment);
            });
        }
          .width('100%')
          .padding({ left: 10, right: 8, top: 8, bottom: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) });
      }, (attachment: LocalFeedbackAttachment) => attachment.localId);
      if (this.uploadProgressText.length > 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
          Text(this.uploadProgressText)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .layoutWeight(1)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
          if (this.isSubmitting) {
            Button({ stateEffect: true }) {
              Text('取消上传')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme));
            }
              .id('feedback_cancel_upload')
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.cancelUpload();
              });
          }
        }
      }
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)]);
        Text('文本/日志 10 MiB，图片 20 MiB，视频/压缩包 80 MiB；提交后需管理员审核。')
          .layoutWeight(1)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
      }
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
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      });
  }

  /*
   * Preserved during the UI parser repair. This block was structurally
   * malformed in the incoming working tree; the active builder below keeps
   * the same state and submission handlers with a single ArkUI root.
   *
  private buildCompose(): void {
    Column({ space: 14 }) {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(42)
              .height(42)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .borderRadius(14);
            SymbolGlyph($r('sys.symbol.highlighter_line'))
              .fontSize(21)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
          }
        Column({ space: 3 }) {
          Text('创建新的匿名 Issue')
            .fontSize(21)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Text('描述清楚问题，其他用户可以加入并补充线索')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
        }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        Button({ stateEffect: true }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)]);
            Text('清空')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme));
          }
        }
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(999)
          .stateStyles({
            pressed: {
              .scale({ x: 0.95, y: 0.95 })
              .opacity(0.8)
            }
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
            void this.resetComposeForm();
          });
      }
      TextInput({ placeholder: '一句话概括问题', text: this.title })
        .width('100%')
        .height(50)
        .id('feedback_issue_title')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .backgroundColor(Color.Transparent)
        .padding({ left: 12, right: 12 })
        .borderRadius(14)
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
        .onChange((value: string) => {
          this.title = value;
          this.scheduleDraftSave();
        });
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('问题类型')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
        }
        Row({ space: 6 }) {
          this.buildTypeChip('source', '图源');
          this.buildTypeChip('book_source', '书源');
          this.buildTypeChip('software', '软件');
          this.buildTypeChip('ui', 'UI');
          this.buildTypeChip('suggestion', '建议');
          this.buildTypeChip('other', '其他');
        }
          .width('100%');
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('问题描述')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Blank().layoutWeight(1);
          Text(`${this.description.length} / ${MAX_DESCRIPTION_LENGTH}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
        TextArea({ placeholder: '请描述复现步骤、预期结果和实际结果…', text: this.description })
          .width('100%')
          .height(170)
          .id('feedback_issue_description')
          .fontFamily(this.appFontFamily)
          .backgroundColor(Color.Transparent)
          .padding(12)
          .borderRadius(14)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .onChange((value: string) => {
            this.description = value;
            this.scheduleDraftSave();
          });
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('问题上下文（可选）')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
        }
        TextInput({ placeholder: '漫画标题', text: this.mangaTitle })
          .height(42)
          .fontFamily(this.appFontFamily)
          .backgroundColor(Color.Transparent)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .onChange((value: string) => {
            this.mangaTitle = value;
            this.scheduleDraftSave();
          });
        TextInput({ placeholder: '章节标题', text: this.chapterTitle })
          .height(42)
          .fontFamily(this.appFontFamily)
          .backgroundColor(Color.Transparent)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .onChange((value: string) => {
            this.chapterTitle = value;
            this.scheduleDraftSave();
          });
        TextInput({ placeholder: '图源名称', text: this.sourceName })
          .height(42)
          .fontFamily(this.appFontFamily)
          .backgroundColor(Color.Transparent)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .onChange((value: string) => {
            this.sourceName = value;
            this.scheduleDraftSave();
          });
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)]);
          Text('自动诊断信息')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
          Blank().layoutWeight(1);
          Text('仅收集必要信息')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        }
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text('机型')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(this.diagnostic.model || '未提供')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Column({ space: 4 }) {
            Text('系统')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(this.diagnostic.system_version || '未提供')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          Column({ space: 4 }) {
            Text('APP')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
            Text(`${this.diagnostic.app_version || '未提供'} (${this.diagnostic.build_number})`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
          }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
        }
        Text('不会收集 UUID、设备序列号、IMEI、手机号或联系方式。')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
        Text('请勿在公开描述中粘贴 Token、Cookie、密码或未经脱敏的私密日志；日志附件默认仅管理员可见。')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme));
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
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        });
      this.buildAttachmentPicker();
        Button({ stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_up_circle'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)]);
            Text(this.isSubmitting ? '提交中…' : '提交 Issue')
              .fontSize(15)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
          }
        }
        .width('100%')
        .height(48)
        .id('feedback_submit_issue_button')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .borderRadius(999)
        .stateStyles({
          pressed: {
            .scale({ x: 0.98, y: 0.98 })
            .opacity(0.82)
          }
        })
        .animation({ duration: 160, curve: Curve.EaseOut })
        .onClick(() => {
          void this.submitIssue();
        });
    }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 16, right: 16, bottom: 40 });
  }

  }

  */

  @Builder
  private buildCompose(): void {
    Column({ space: 14 }) {
      Text('创建新的匿名 Issue')
        .fontSize(21)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
      Text('描述清楚问题，其他用户可以加入并补充线索')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
      Row({ space: 6 }) {
        this.buildTypeChip('source', '图源');
        this.buildTypeChip('book_source', '书源');
        this.buildTypeChip('software', '软件');
        this.buildTypeChip('ui', 'UI');
        this.buildTypeChip('suggestion', '建议');
        this.buildTypeChip('other', '其他');
      }
        .width('100%');
      TextInput({ placeholder: '一句话概括问题', text: this.title })
        .width('100%')
        .height(50)
        .id('feedback_issue_title')
        .fontFamily(this.appFontFamily)
        .onChange((value: string): void => {
          this.title = value;
          this.scheduleDraftSave();
        });
      TextArea({ placeholder: '请描述复现步骤、预期结果和实际结果…', text: this.description })
        .width('100%')
        .height(170)
        .id('feedback_issue_description')
        .fontFamily(this.appFontFamily)
        .onChange((value: string): void => {
          this.description = value;
          this.scheduleDraftSave();
        });
      Row({ space: 8 }) {
        TextInput({ placeholder: '漫画标题', text: this.mangaTitle })
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.mangaTitle = value;
            this.scheduleDraftSave();
          });
        TextInput({ placeholder: '章节标题', text: this.chapterTitle })
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.chapterTitle = value;
            this.scheduleDraftSave();
          });
      }
        .width('100%');
      TextInput({ placeholder: '图源名称', text: this.sourceName })
        .width('100%')
        .onChange((value: string): void => {
          this.sourceName = value;
          this.scheduleDraftSave();
        });
      Text(`设备：${this.diagnostic.model || '未提供'} · 系统：${this.diagnostic.system_version || '未提供'}`)
        .width('100%')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
      this.buildAttachmentPicker();
      Button({ stateEffect: true }) {
        Text(this.isSubmitting ? '提交中…' : '提交 Issue')
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
      }
        .width('100%')
        .height(48)
        .id('feedback_submit_issue_button')
        .enabled(!this.isSubmitting)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .borderRadius(999)
        .onClick((): void => {
          void this.submitIssue();
        });
    }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 16, right: 16, bottom: 40 });
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight));
            if (this.mode === 'list') {
              this.buildIssueList();
            } else if (this.mode === 'detail') {
              if (this.selectedIssue !== null) {
                this.buildDetail(this.selectedIssue);
              } else {
                this.buildIssueList();
              }
            } else {
              this.buildCompose();
            }
            Blank().height(24 + this.navigationBarHeight);
          }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .opacity(this.pageEnterOpacity * this.contentOpacity)
            .translate({ y: this.pageEnterOffsetY + this.contentOffsetY });
        }
          .id('feedback_submit_issue')
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '反馈中心',
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 960,
          pathStack: this.pathStack,
          backAction: (): boolean => this.handleTitleBarBack()
        });
        if (this.showTurnstile) {
          FeedbackTurnstileView({
            visible: true,
            sessionId: this.turnstileSessionId,
            themeState: this.themeState,
            appFontFamily: this.appFontFamily,
            onToken: (token: string): void => {
              this.completeTurnstile(token);
            },
            onCancel: (): void => {
              this.completeTurnstile('');
            }
          });
        }
      }
    }
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onReady((context: NavDestinationContext) => {
        this.pathStack = context.pathStack;
      })
      .onBackPressed((): boolean => {
        if (this.showTurnstile) {
          this.completeTurnstile('');
          return true;
        }
        this.goBack();
        return true;
      })
      .backgroundColor(Color.Transparent);
  }
}

export { MangaFeedbackPage };

@Component
struct FeedbackTurnstileView {
  @Prop visible: boolean = false;
  @Prop sessionId: number = 0;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @Prop appFontFamily: string = 'HarmonyOS Sans';
  @State status: FeedbackTurnstileViewStatus = 'loading';
  @State statusMessage: string = '正在加载安全验证…';
  onToken: (token: string) => void = (_token: string): void => {};
  onCancel: () => void = (): void => {};
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private readonly challengeUrl: string = `${FeedbackCenterService.getInstance().getOrigin()}/turnstile-shell?client=arkweb-v3`;
  private readonly jsProxy: FeedbackTurnstileJsProxy = {
    onTurnstileToken: (token: string): void => {
      this.onToken(token);
    },
    onTurnstileError: (message: string): void => {
      this.showTurnstileError(message);
    }
  };

  private showTurnstileError(message: string): void {
    this.status = 'error';
    this.statusMessage = message.length > 0 ? message : '安全验证暂时不可用，请点击重试';
    logger.warn(TAG, `Turnstile 验证失败: ${this.statusMessage}`);
  }

  private retryTurnstile(): void {
    this.status = 'loading';
    this.statusMessage = '正在重新加载安全验证…';
    this.loadChallengePage(true);
  }

  private loadChallengePage(isRetry: boolean): void {
    try {
      const retryQuery: string = isRetry ? `&retry=${Date.now()}` : '';
      logger.info(TAG, `开始加载 Turnstile 挑战页: retry=${isRetry}`);
      this.controller.loadUrl(`${this.challengeUrl}${retryQuery}`);
    } catch (error) {
      this.showTurnstileError(`重新加载验证失败：${String(error)}`);
    }
  }

  private handleNavigation(url: string): boolean {
    if (!url.startsWith('manxia://turnstile')) {
      return false;
    }
    const marker = 'token=';
    const markerIndex = url.indexOf(marker);
    let token = '';
    if (markerIndex >= 0) {
      try {
        token = decodeURIComponent(url.substring(markerIndex + marker.length));
      } catch (error) {
        logger.warn(TAG, `解析 Turnstile 回传失败: ${String(error)}`);
      }
    }
    if (token.length > 0) {
      this.onToken(token);
    } else {
      this.onCancel();
    }
    return true;
  }

  private inspectTurnstilePageState(): void {
    const script: string = `(() => {
      const frame = document.getElementById('turnstile-frame');
      const frameWindow = frame && frame.contentWindow ? frame.contentWindow : window;
      const frameDocument = frame && frame.contentDocument ? frame.contentDocument : document;
      const container = frameDocument.getElementById('turnstile-widget');
      const state = document.getElementById('turnstile-state');
      const scripts = Array.from(frameDocument.querySelectorAll('script'))
        .map((item) => item.src)
        .filter((src) => src.indexOf('turnstile/v0/api.js') >= 0);
      return JSON.stringify({
        turnstileType: typeof frameWindow.turnstile,
        renderType: frameWindow.turnstile ? typeof frameWindow.turnstile.render : 'none',
        scriptCount: scripts.length,
        scriptSources: scripts,
        containerCount: frameDocument.querySelectorAll('#turnstile-widget').length,
        iframeCount: container ? container.querySelectorAll('iframe').length : 0,
        containerChildCount: container ? container.children.length : 0,
        stateText: state ? state.textContent : '',
        shellState: document.documentElement.getAttribute('data-turnstile-state') || '',
        cookieLength: document.cookie.length,
        turnstileDescriptor: Object.getOwnPropertyDescriptor(frameWindow, 'turnstile') ? 'present' : 'absent'
      });
    })();`;
    try {
      this.controller.runJavaScript(script, (error: BusinessError | null, result: string): void => {
        if (error) {
          logger.warn(TAG, `Turnstile 页面状态读取失败: code=${error.code}, message=${error.message}`);
          return;
        }
        logger.info(TAG, `Turnstile 页面状态: ${result}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      logger.warn(TAG, `Turnstile 页面状态读取调用失败: code=${businessError.code}, message=${businessError.message}`);
    }
  }

  aboutToDisappear(): void {
    try {
      this.controller.stop();
      this.controller.clearHistory();
      logger.info(TAG, 'Turnstile WebView 已停止并清理导航历史');
    } catch (error) {
      logger.warn(TAG, `Turnstile WebView 清理失败: ${String(error)}`);
    }
  }

  build(): void {
    Stack() {
      if (this.visible) {
        Stack() {
        Column({ space: 10 }) {
          Row() {
            Text('安全验证')
              .fontSize(16)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
            Blank().layoutWeight(1);
            Button({ stateEffect: true }) {
              Text('取消')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
            }
              .id('feedback_turnstile_cancel')
              .fontFamily(this.appFontFamily)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.onCancel();
              });
          }
          Stack() {
            Web({ src: this.challengeUrl, controller: this.controller, incognitoMode: true })
              .id('feedback_turnstile_webview')
              .key(`feedback_turnstile_webview_${this.sessionId}`)
              .width('100%')
              .height(270)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .imageAccess(true)
              .databaseAccess(true)
              .onlineImageAccess(true)
              .mixedMode(MixedMode.All)
              .cacheMode(CacheMode.Online)
              .backgroundColor(Color.Transparent)
              .javaScriptProxy({
                object: this.jsProxy,
                name: 'arkts',
                methodList: ['onTurnstileToken', 'onTurnstileError'],
                controller: this.controller
              })
              .onPageBegin((event) => {
                const url: string = event?.url ? event.url : '';
                logger.info(TAG, `Turnstile 页面开始加载: ${url}`);
              })
              .onPageEnd((event) => {
                const url: string = event?.url ? event.url : '';
                if (url === 'about:blank') {
                  logger.info(TAG, 'Turnstile 初始空白页加载完成，等待挑战页切换');
                  return;
                }
                if (this.status !== 'error') {
                  this.status = 'ready';
                  this.statusMessage = '验证组件已加载';
                }
                logger.info(TAG, `Turnstile 页面加载完成: ${url}`);
                setTimeout(() => {
                  this.inspectTurnstilePageState();
                }, 800);
              })
              .onConsole((event) => {
                if (event && event.message) {
                  logger.info(TAG, `Turnstile Web Console [${event.message.getMessageLevel()}]: ${event.message.getMessage()}`);
                }
                return false;
              })
              .onLoadIntercept((event) => {
                const url: string = event.data.getRequestUrl();
                if (url.startsWith('manxia://turnstile')) {
                  logger.info(TAG, 'Turnstile 已通过回调返回原生层');
                }
                return this.handleNavigation(url);
              })
              .onErrorReceive((event) => {
                const errorInfo: string = event.error.getErrorInfo();
                const errorCode: number = event.error.getErrorCode();
                const requestUrl: string = event.request.getRequestUrl();
                const isMainFrame: boolean = event.request.isMainFrame();
                logger.warn(TAG, `Turnstile WebView 资源错误: code=${errorCode}, mainFrame=${isMainFrame}, url=${requestUrl}, info=${errorInfo}`);
                if (isMainFrame) {
                  this.showTurnstileError(`安全验证页面加载失败：${errorInfo}`);
                }
              })
              .onHttpErrorReceive((event) => {
                const responseCode: number = event.response.getResponseCode();
                const requestUrl: string = event.request.getRequestUrl();
                logger.warn(TAG, `Turnstile HTTP 资源错误: code=${responseCode}, mainFrame=${event.request.isMainFrame()}, url=${requestUrl}`);
              });

            if (this.status === 'loading') {
              Column({ space: 8 }) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
                Text(this.statusMessage)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
              }
                .width('100%')
                .height(180)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(Color.Transparent);
            } else if (this.status === 'error') {
              Column({ space: 10 }) {
                Text('安全验证暂时不可用')
                  .fontSize(15)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme));
                Text(this.statusMessage)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .textAlign(TextAlign.Center)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                Button({ stateEffect: true }) {
                  Text('重试')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
                }
                  .height(36)
                  .padding({ left: 22, right: 22 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .borderRadius(18)
                  .onClick(() => {
                    this.retryTurnstile();
                  });
              }
                .width('100%')
                .height(180)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(Color.Transparent);
            }
          }
            .width('100%')
            .height(270);
        }
          .id('feedback_turnstile_card')
          .width('92%')
          .height(350)
          .padding(16)
          .backgroundColor(DialogSurfaceStyleHelper.getPopupCardBackground(this.themeState))
          .linearGradient(DialogSurfaceStyleHelper.getPopupCardGradient(this.themeState))
          .backgroundBlurStyle(
            DialogSurfaceStyleHelper.getPopupCardBlurStyle(),
            DialogSurfaceStyleHelper.getPopupCardBlurOptions()
          )
          .backgroundEffect(DialogSurfaceStyleHelper.getPopupCardBackgroundEffect())
          .borderRadius(DialogSurfaceStyleHelper.getPopupCardRadius())
          .clip(true)
          .border({
            width: DialogSurfaceStyleHelper.getPopupCardBorderWidth(this.themeState),
            color: DialogSurfaceStyleHelper.getPopupCardBorderColor(this.themeState)
          })
          .shadow({
            radius: 24,
            color: DialogSurfaceStyleHelper.getPopupCardShadowColor(this.themeState),
            offsetX: 0,
            offsetY: 10
          });
      }
        .id('feedback_turnstile_dialog')
        .width('100%')
        .height('100%')
        .backgroundColor(DialogSurfaceStyleHelper.getPopupMaskColor())
        .backgroundBlurStyle(
          DialogSurfaceStyleHelper.getPopupMaskBlurStyle(),
          DialogSurfaceStyleHelper.getPopupMaskBlurOptions()
        )
        .backgroundEffect(DialogSurfaceStyleHelper.getPopupMaskBackgroundEffect())
        .alignContent(Alignment.Center);
        }
      }
    }

}
