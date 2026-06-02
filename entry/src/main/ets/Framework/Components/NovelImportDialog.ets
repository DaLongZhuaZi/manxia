import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Components/NovelImportDialog.ets
/**
 * 小说(TXT)导入对话框
 * 提供元数据编辑、章节规则选择、编码检测等功能
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { logger } from '../../Utils/Logger';
import { AppColors, ColorRole } from '../Theme/AppColors';
import { getNovelTxtTocRuleManager, TxtTocRule, TxtChapter } from '../Novel/NovelTxtTocRuleManager';
import { NovelReplaceRuleManager, ReplaceRule, ReplaceScope } from '../Novel/NovelReplaceRuleManager';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';
import { image } from '@kit.ImageKit';

const TAG = 'NovelImportDialog';

/**
 * 文本编码类型
 */
export enum TextEncoding {
  AUTO = 'auto',
  UTF8 = 'utf-8',
  GBK = 'gbk',
  GB2312 = 'gb2312',
  BIG5 = 'big5'
}

/**
 * 小说导入结果
 */
export interface NovelImportDialogResult {
  /** 书名 */
  title: string;
  /** 作者 */
  author: string;
  /** 简介 */
  description: string;
  /** 标签 */
  tags: string[];
  /** 选择的编码 */
  encoding: TextEncoding;
  /** 选择的章节规则ID（空表示自动检测） */
  selectedTocRuleId: string;
  /** 是否自动分章 */
  autoSplitChapters: boolean;
  /** 预览的章节列表 */
  previewChapters: TxtChapter[];
  /** 是否启用替换净化 */
  enableReplaceRules: boolean;
  /** 要删除的广告行号列表 */
  adLinesToRemove: number[];
  /** 封面路径（可选） */
  coverPath?: string;
}

/**
 * 小说导入对话框
 */
@CustomDialog
export struct NovelImportDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop defaultTitle: string = '';
  @Prop filePath: string = '';
  @Prop folderPath: string = '';  // 文件所在文件夹路径
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  
  // 回调函数
  onConfirm: (result: NovelImportDialogResult) => void = () => {};
  onCancel: () => void = () => {};

  // 表单状态
  @State title: string = '';
  @State author: string = '';
  @State description: string = '';
  @State tagsText: string = '';
  @State selectedEncoding: TextEncoding = TextEncoding.AUTO;
  @State selectedTocRuleId: string = '';
  @State autoSplitChapters: boolean = true;
  
  // 候选项列表
  @State titleCandidates: string[] = [];
  @State authorCandidates: string[] = [];
  @State descriptionCandidates: string[] = [];
  @State tagsCandidates: string[] = [];
  
  // 下拉菜单显示状态
  @State showTitleDropdown: boolean = false;
  @State showAuthorDropdown: boolean = false;
  @State showDescriptionDropdown: boolean = false;
  @State showTagsDropdown: boolean = false;
  
  // 章节预览 - 存储全部章节
  @State allChapters: TxtChapter[] = [];
  @State previewChapters: TxtChapter[] = [];
  @State isLoadingPreview: boolean = false;
  @State previewError: string = '';
  @State fileContent: string = '';
  @State contentPreview: string = '';
  
  // 原始文件缓冲区（用于编码切换）
  private rawFileBuffer: ArrayBuffer | null = null;
  
  // 可用的章节规则
  @State availableTocRules: TxtTocRule[] = [];
  
  // 替换净化规则
  @State availableReplaceRules: ReplaceRule[] = [];
  @State detectedAds: DetectedAdItem[] = [];
  @State enableReplaceRules: boolean = true;
  
  // 封面相关
  @State coverPath: string = '';
  @State customCoverPath: string = '';
  @State isGeneratingCover: boolean = false;
  @State coverRefreshKey: number = 0;
  @State coverFontScale: number = 1.0;
  
  // 当前Tab
  @State currentTab: number = 0;
  
  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;

  private tocRuleManager = getNovelTxtTocRuleManager();
  private replaceRuleManager = NovelReplaceRuleManager.getInstance();

  aboutToAppear(): void {
    this.loadTocRules();
    this.loadReplaceRules();
    this.loadFilePreview();
    this.generateDefaultCover();
  }

  // 封面生成器常量（基于 ebook.webp 图片精确测量）
  private static readonly COVER_WIDTH = 400;
  private static readonly COVER_HEIGHT = 600;
  private static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  private static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  private static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  private static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;

  /**
   * 生成默认封面
   */
  private async generateDefaultCover(): Promise<void> {
    if (!this.folderPath) return;
    
    try {
      this.isGeneratingCover = true;
      const title = this.defaultTitle || '未知书名';
      const coverPath = `${this.folderPath}/cover.webp`;
      
      // 使用 componentSnapshot.createFromBuilder 生成 PixelMap
      const pixelMap = await this.getUIContext().getComponentSnapshot().createFromBuilder(
        () => { this.buildCoverForSnapshot(title); }
      );
      
      if (pixelMap) {
        const success = await this.savePixelMapToFile(pixelMap, coverPath);
        pixelMap.release();
        
        if (success) {
          this.coverPath = coverPath;
          this.coverRefreshKey++;
          logger.info(TAG, `生成默认封面: ${coverPath}`);
        }
      }
    } catch (e) {
      const error = e as Error;
      logger.warn(TAG, `生成默认封面失败: ${String(error)}`);
    } finally {
      this.isGeneratingCover = false;
    }
  }

  /**
   * 重新生成封面
   */
  private async regenerateCover(): Promise<void> {
    if (!this.folderPath) return;
    
    try {
      this.isGeneratingCover = true;
      const title = this.title || this.defaultTitle || '未知书名';
      const coverPath = `${this.folderPath}/cover_${Date.now()}.webp`;
      
      // 删除旧封面
      if (this.coverPath) {
        try {
          await fileIo.unlink(this.coverPath);
        } catch (e) {
          // 忽略删除失败
        }
      }
      
      // 使用 componentSnapshot.createFromBuilder 生成 PixelMap
      const pixelMap = await this.getUIContext().getComponentSnapshot().createFromBuilder(
        () => { this.buildCoverForSnapshot(title); }
      );
      
      if (pixelMap) {
        const success = await this.savePixelMapToFile(pixelMap, coverPath);
        pixelMap.release();
        
        if (success) {
          this.coverPath = coverPath;
          this.customCoverPath = '';
          this.coverRefreshKey++;
          logger.info(TAG, `重新生成封面: ${coverPath}`);
        }
      }
    } catch (e) {
      const error = e as Error;
      logger.warn(TAG, `重新生成封面失败: ${String(error)}`);
    } finally {
      this.isGeneratingCover = false;
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
        .width(NovelImportDialog.COVER_WIDTH)
        .height(NovelImportDialog.COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      // 标题文字层
      Text(this.formatCoverTitle(title))
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(NovelImportDialog.COVER_WIDTH * (NovelImportDialog.TITLE_AREA_RIGHT_PERCENT - NovelImportDialog.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: NovelImportDialog.COVER_HEIGHT * (NovelImportDialog.TITLE_AREA_BOTTOM_PERCENT - NovelImportDialog.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: NovelImportDialog.COVER_WIDTH * NovelImportDialog.TITLE_AREA_LEFT_PERCENT + 12,
          y: NovelImportDialog.COVER_HEIGHT * (NovelImportDialog.TITLE_AREA_TOP_PERCENT + NovelImportDialog.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(NovelImportDialog.COVER_WIDTH)
    .height(NovelImportDialog.COVER_HEIGHT)
  }

  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }

  /**
   * 根据标题长度计算合适的字体大小
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    let baseSize = 24;
    if (length <= 2) baseSize = 70;
    else if (length <= 4) baseSize = 56;
    else if (length <= 6) baseSize = 48;
    else if (length <= 8) baseSize = 36;
    else if (length <= 12) baseSize = 32;
    else if (length <= 16) baseSize = 28;
    
    return baseSize * this.coverFontScale;
  }

  /**
   * 将 PixelMap 保存为图片文件
   */
  private async savePixelMapToFile(pixelMap: image.PixelMap, filePath: string): Promise<boolean> {
    try {
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      try {
        await fileIo.mkdir(dirPath);
      } catch (e) {
        // 目录可能已存在
      }
      
      const imagePacker = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: 'image/webp',
        quality: 90
      };
      
      const arrayBuffer = await imagePacker.packToData(pixelMap, packOptions);
      const file = await fileIo.open(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, arrayBuffer);
      await fileIo.close(file.fd);
      imagePacker.release();
      
      return true;
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `保存封面失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 选择自定义封面
   */
  private async selectCustomCover(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const selectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      
      const result = await photoPicker.select(selectOptions);
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.customCoverPath = result.photoUris[0];
        this.coverRefreshKey++;
        logger.info(TAG, `选择了自定义封面: ${this.customCoverPath}`);
      }
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `选择封面失败: ${String(error)}`);
    }
  }

  /**
   * 规范化封面路径
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) return '';
    if (path.startsWith('/')) return `file://${path}`;
    return path;
  }

  /**
   * 加载替换净化规则
   */
  private async loadReplaceRules(): Promise<void> {
    try {
      await this.replaceRuleManager.initialize();
      this.availableReplaceRules = this.replaceRuleManager.getAllRules();
      logger.info(TAG, `加载了 ${this.availableReplaceRules.length} 条替换规则`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `加载替换规则失败: ${String(error)}`);
    }
  }

  /**
   * 检测文本中的广告内容
   */
  private detectAdsInContent(): void {
    if (!this.fileContent) return;
    
    const detectedItems: DetectedAdItem[] = [];
    const lines = this.fileContent.split('\n');
    const enabledRules = this.replaceRuleManager.getEnabledRules(ReplaceScope.CONTENT);
    
    // 常见广告模式（内置）
    const builtInAdPatterns: AdPatternDef[] = [
      { pattern: /(?:求|跪求|恳请).{0,10}(?:收藏|推荐|订阅|打赏|月票|评论)/i, name: '求收藏推荐' } as AdPatternDef,
      { pattern: /(?:本书|本文|小说).{0,20}(?:首发|独家|连载).{0,20}(?:网站|平台|app)/i, name: '首发声明' } as AdPatternDef,
      { pattern: /(?:更多|更新|最新).{0,10}(?:章节|内容).{0,20}(?:请|搜索|访问)/i, name: '更新提示' } as AdPatternDef,
      { pattern: /(?:手机|电脑).{0,10}(?:阅读|观看).{0,20}(?:网址|地址|链接)/i, name: '阅读提示' } as AdPatternDef,
      { pattern: /(?:正版|盗版).{0,20}(?:支持|打击|举报)/i, name: '版权声明' } as AdPatternDef,
      { pattern: /(?:加入|欢迎).{0,10}(?:书友群|QQ群|微信群)/i, name: '群聊广告' } as AdPatternDef,
      { pattern: /(?:www\.|http:|https:)[^\s]{10,}/i, name: '网址链接' } as AdPatternDef,
      { pattern: /(?:起点|晋江|纵横|17k|潇湘|红袖|番茄|七猫|书旗).{0,10}(?:中文网|小说网|文学)/i, name: '网站名称' } as AdPatternDef,
      { pattern: /(?:本章|下章|上章).{0,10}(?:未完|待续|继续)/i, name: '章节提示' } as AdPatternDef,
      { pattern: /(?:作者|笔者).{0,10}(?:有话说|的话|说)/i, name: '作者有话说' } as AdPatternDef,
    ];
    
    // 检查每一行
    for (let i = 0; i < Math.min(lines.length, 5000); i++) {
      const line = lines[i].trim();
      if (line.length < 5 || line.length > 200) continue;
      
      // 检查内置广告模式
      for (let j = 0; j < builtInAdPatterns.length; j++) {
        const adPattern = builtInAdPatterns[j];
        if (adPattern.pattern.test(line)) {
          detectedItems.push({
            content: line.substring(0, 100),
            lineNumber: i + 1,
            ruleName: adPattern.name,
            selected: true
          } as DetectedAdItem);
          break;
        }
      }
      
      // 检查用户定义的替换规则
      for (let k = 0; k < enabledRules.length; k++) {
        const rule = enabledRules[k];
        try {
          let matches = false;
          if (rule.isRegex) {
            const regex = new RegExp(rule.pattern);
            matches = regex.test(line);
          } else {
            matches = line.includes(rule.pattern);
          }
          
          if (matches) {
            // 避免重复添加
            const exists = detectedItems.some(item => item.lineNumber === i + 1);
            if (!exists) {
              detectedItems.push({
                content: line.substring(0, 100),
                lineNumber: i + 1,
                ruleName: rule.name,
                selected: true
              } as DetectedAdItem);
            }
            break;
          }
        } catch (e) {
          // 忽略无效的正则表达式
        }
      }
    }
    
    this.detectedAds = detectedItems;
    logger.info(TAG, `检测到 ${detectedItems.length} 处疑似广告内容`);
  }

  /**
   * 从文件名、文件夹名和文件内容中提取元数据
   */
  private extractMetadataFromFile(): void {
    const headerContent = this.fileContent ? this.fileContent.substring(0, 10000) : '';
    
    // 提取所有候选项
    this.titleCandidates = this.extractAllTitleCandidates(headerContent);
    this.authorCandidates = this.extractAllAuthorCandidates(headerContent);
    this.descriptionCandidates = this.extractAllDescriptionCandidates(headerContent);
    this.tagsCandidates = this.extractAllTagsCandidates(headerContent);
    
    // 设置默认值（使用第一个候选项）
    if (this.titleCandidates.length > 0) {
      this.title = this.titleCandidates[0];
    } else {
      this.title = this.cleanTitle(this.defaultTitle);
    }
    
    if (this.authorCandidates.length > 0) {
      this.author = this.authorCandidates[0];
    }
    
    if (this.descriptionCandidates.length > 0) {
      this.description = this.descriptionCandidates[0];
    }
    
    if (this.tagsCandidates.length > 0) {
      this.tagsText = this.tagsCandidates[0];
    }
    
    logger.info(TAG, `提取到候选项: 书名${this.titleCandidates.length}个, 作者${this.authorCandidates.length}个, 简介${this.descriptionCandidates.length}个, 标签${this.tagsCandidates.length}个`);
  }

  /**
   * 提取所有书名候选项（100+种模式）
   */
  private extractAllTitleCandidates(content: string): string[] {
    const candidates: string[] = [];
    const seen = new Set<string>();
    
    const addCandidate = (title: string, source: string) => {
      const cleaned = title.trim();
      if (cleaned.length >= 2 && cleaned.length <= 60 && !seen.has(cleaned)) {
        seen.add(cleaned);
        candidates.push(cleaned);
        logger.debug(TAG, `书名候选[${source}]: ${cleaned}`);
      }
    };
    
    // ========== 1. 从文件名提取 (10种模式) ==========
    const filename = this.defaultTitle;
    // 1.1 清理后的文件名
    addCandidate(this.cleanTitle(filename), '文件名');
    // 1.2 《》包裹的书名
    const fileBookMatch = filename.match(/《([^》]+)》/);
    if (fileBookMatch) addCandidate(fileBookMatch[1], '文件名《》');
    // 1.3 「」包裹的书名
    const fileBookMatch2 = filename.match(/「([^」]+)」/);
    if (fileBookMatch2) addCandidate(fileBookMatch2[1], '文件名「」');
    // 1.4 【】包裹的书名
    const fileBookMatch3 = filename.match(/【([^】]+)】/);
    if (fileBookMatch3) addCandidate(fileBookMatch3[1], '文件名【】');
    // 1.5 []包裹的书名
    const fileBookMatch4 = filename.match(/\[([^\]]+)\]/);
    if (fileBookMatch4) addCandidate(fileBookMatch4[1], '文件名[]');
    // 1.6 ()包裹的书名
    const fileBookMatch5 = filename.match(/\(([^)]+)\)/);
    if (fileBookMatch5) addCandidate(fileBookMatch5[1], '文件名()');
    // 1.7 ""包裹的书名
    const fileBookMatch6 = filename.match(/"([^"]+)"/);
    if (fileBookMatch6) addCandidate(fileBookMatch6[1], '文件名""');
    // 1.8 ''包裹的书名
    const fileBookMatch7 = filename.match(/'([^']+)'/);
    if (fileBookMatch7) addCandidate(fileBookMatch7[1], "文件名''");
    // 1.9 作者-书名格式
    const authorTitleMatch = filename.match(/^[^-_]+[-_](.+)$/);
    if (authorTitleMatch) addCandidate(this.cleanTitle(authorTitleMatch[1]), '文件名作者-书名');
    // 1.10 书名-作者格式
    const titleAuthorMatch = filename.match(/^(.+)[-_][^-_]+$/);
    if (titleAuthorMatch) addCandidate(this.cleanTitle(titleAuthorMatch[1]), '文件名书名-作者');
    
    // ========== 2. 从文件夹名提取 (5种模式) ==========
    if (this.folderPath) {
      const folderName = this.folderPath.substring(this.folderPath.lastIndexOf('/') + 1);
      const genericFolders = ['download', 'downloads', 'novel', 'novels', 'book', 'books', 'txt', 'ebook', 'ebooks', 'documents', '下载', '小说', '书籍'];
      if (folderName && !genericFolders.includes(folderName.toLowerCase())) {
        addCandidate(this.cleanTitle(folderName), '文件夹名');
        // 2.2 文件夹名中《》包裹
        const folderBookMatch = folderName.match(/《([^》]+)》/);
        if (folderBookMatch) addCandidate(folderBookMatch[1], '文件夹《》');
        // 2.3 文件夹名中「」包裹
        const folderBookMatch2 = folderName.match(/「([^」]+)」/);
        if (folderBookMatch2) addCandidate(folderBookMatch2[1], '文件夹「」');
      }
    }
    
    // ========== 3. 从文件内容提取 (85+种模式) ==========
    if (content) {
      const lines = content.split('\n').map(l => l.trim()).filter(l => l.length > 0);
      const first100Lines = lines.slice(0, 100);
      
      // 3.1-3.20 书名标识模式
      const titlePatterns: TitlePattern[] = [
        { pattern: /^书名[：:]\s*(.+)$/i, group: 1, name: '书名:' } as TitlePattern,
        { pattern: /^书\s*名[：:]\s*(.+)$/i, group: 1, name: '书 名:' } as TitlePattern,
        { pattern: /^名称[：:]\s*(.+)$/i, group: 1, name: '名称:' } as TitlePattern,
        { pattern: /^小说名[：:]\s*(.+)$/i, group: 1, name: '小说名:' } as TitlePattern,
        { pattern: /^小说名称[：:]\s*(.+)$/i, group: 1, name: '小说名称:' } as TitlePattern,
        { pattern: /^title[：:\s]+(.+)$/i, group: 1, name: 'title:' } as TitlePattern,
        { pattern: /^book\s*name[：:\s]+(.+)$/i, group: 1, name: 'book name:' } as TitlePattern,
        { pattern: /^novel[：:\s]+(.+)$/i, group: 1, name: 'novel:' } as TitlePattern,
        { pattern: /^作品名[：:]\s*(.+)$/i, group: 1, name: '作品名:' } as TitlePattern,
        { pattern: /^作品名称[：:]\s*(.+)$/i, group: 1, name: '作品名称:' } as TitlePattern,
        { pattern: /^作品[：:]\s*(.+)$/i, group: 1, name: '作品:' } as TitlePattern,
        { pattern: /^文名[：:]\s*(.+)$/i, group: 1, name: '文名:' } as TitlePattern,
        { pattern: /^文章名[：:]\s*(.+)$/i, group: 1, name: '文章名:' } as TitlePattern,
        { pattern: /^正文[：:]\s*(.+)$/i, group: 1, name: '正文:' } as TitlePattern,
        { pattern: /^原名[：:]\s*(.+)$/i, group: 1, name: '原名:' } as TitlePattern,
        { pattern: /^中文名[：:]\s*(.+)$/i, group: 1, name: '中文名:' } as TitlePattern,
        { pattern: /^英文名[：:]\s*(.+)$/i, group: 1, name: '英文名:' } as TitlePattern,
        { pattern: /^原作名[：:]\s*(.+)$/i, group: 1, name: '原作名:' } as TitlePattern,
        { pattern: /^译名[：:]\s*(.+)$/i, group: 1, name: '译名:' } as TitlePattern,
        { pattern: /^别名[：:]\s*(.+)$/i, group: 1, name: '别名:' } as TitlePattern,
      ];
      
      for (let i = 0; i < first100Lines.length; i++) {
        const line = first100Lines[i];
        for (let j = 0; j < titlePatterns.length; j++) {
          const tp = titlePatterns[j];
          const match = line.match(tp.pattern);
          if (match && match[tp.group]) {
            addCandidate(match[tp.group].trim(), tp.name);
          }
        }
      }
      
      // 3.21-3.40 《》「」【】等包裹的书名（从内容中提取）
      const bracketPatterns: BracketPattern[] = [
        { pattern: /《([^》]{2,40})》/, name: '内容《》' } as BracketPattern,
        { pattern: /「([^」]{2,40})」/, name: '内容「」' } as BracketPattern,
        { pattern: /『([^』]{2,40})』/, name: '内容『』' } as BracketPattern,
        { pattern: /【([^】]{2,40})】/, name: '内容【】' } as BracketPattern,
        { pattern: /〖([^〗]{2,40})〗/, name: '内容〖〗' } as BracketPattern,
        { pattern: /〈([^〉]{2,40})〉/, name: '内容〈〉' } as BracketPattern,
        { pattern: /﹝([^﹞]{2,40})﹞/, name: '内容﹝﹞' } as BracketPattern,
        { pattern: /"([^"]{2,40})"/, name: '内容""' } as BracketPattern,
        { pattern: /'([^']{2,40})'/, name: "内容''" } as BracketPattern,
        { pattern: /"([^"]{2,40})"/, name: '内容""英文' } as BracketPattern,
        { pattern: /'([^']{2,40})'/, name: "内容''英文" } as BracketPattern,
        { pattern: /\[([^\]]{2,40})\]/, name: '内容[]' } as BracketPattern,
        { pattern: /\(([^)]{2,40})\)/, name: '内容()' } as BracketPattern,
        { pattern: /（([^）]{2,40})）/, name: '内容（）' } as BracketPattern,
      ];
      
      // 只在前20行中查找括号包裹的书名
      const first20Lines = first100Lines.slice(0, 20).join('\n');
      for (let k = 0; k < bracketPatterns.length; k++) {
        const bp = bracketPatterns[k];
        const matches = first20Lines.match(new RegExp(bp.pattern.source, 'g'));
        if (matches) {
          const limitedMatches = matches.slice(0, 3);
          for (let m = 0; m < limitedMatches.length; m++) {
            const innerMatch = limitedMatches[m].match(bp.pattern);
            if (innerMatch && innerMatch[1]) {
              addCandidate(innerMatch[1], bp.name);
            }
          }
        }
      }
      
      // 3.41-3.50 第一行作为书名（如果符合条件）
      if (first100Lines.length > 0) {
        const firstLine = first100Lines[0];
        if (firstLine.length >= 2 && firstLine.length <= 40 && !this.isChapterTitle(firstLine) && !this.isMetadataLine(firstLine)) {
          addCandidate(firstLine, '首行');
        }
        // 检查第二行
        if (first100Lines.length > 1) {
          const secondLine = first100Lines[1];
          if (secondLine.length >= 2 && secondLine.length <= 40 && !this.isChapterTitle(secondLine) && !this.isMetadataLine(secondLine)) {
            addCandidate(secondLine, '第二行');
          }
        }
      }
      
      // 3.51-3.60 特殊格式
      for (let n = 0; n < first100Lines.length; n++) {
        const line = first100Lines[n];
        // 书名：《xxx》作者：xxx 格式
        const combinedMatch = line.match(/书名[：:]\s*《([^》]+)》/);
        if (combinedMatch) addCandidate(combinedMatch[1], '书名:《》');
        
        // 【书名】xxx【作者】xxx 格式
        const bracketTitleMatch = line.match(/【书名】\s*([^【]+)/);
        if (bracketTitleMatch) addCandidate(bracketTitleMatch[1].trim(), '【书名】');
        
        // [书名]xxx 格式
        const squareTitleMatch = line.match(/\[书名\]\s*([^\[]+)/i);
        if (squareTitleMatch) addCandidate(squareTitleMatch[1].trim(), '[书名]');
        
        // ★书名★ 格式
        const starTitleMatch = line.match(/★([^★]{2,40})★/);
        if (starTitleMatch) addCandidate(starTitleMatch[1], '★书名★');
        
        // ◆书名◆ 格式
        const diamondTitleMatch = line.match(/◆([^◆]{2,40})◆/);
        if (diamondTitleMatch) addCandidate(diamondTitleMatch[1], '◆书名◆');
        
        // ●书名● 格式
        const circleTitleMatch = line.match(/●([^●]{2,40})●/);
        if (circleTitleMatch) addCandidate(circleTitleMatch[1], '●书名●');
        
        // ═══书名═══ 格式
        const lineTitleMatch = line.match(/[═=]{2,}\s*([^═=]{2,40})\s*[═=]{2,}/);
        if (lineTitleMatch) addCandidate(lineTitleMatch[1], '═书名═');
        
        // ----书名---- 格式
        const dashTitleMatch = line.match(/[-]{3,}\s*([^-]{2,40})\s*[-]{3,}/);
        if (dashTitleMatch) addCandidate(dashTitleMatch[1], '-书名-');
        
        // 3.61-3.70 网站特定格式
        // 起点/晋江等格式
        const qidianMatch = line.match(/(?:起点|晋江|纵横|17k|潇湘|红袖|言情|飞卢|番茄|七猫|书旗)[：:]\s*(.+)/i);
        if (qidianMatch) addCandidate(qidianMatch[1].trim(), '网站格式');
        
        // 连载于xxx 格式
        const serialMatch = line.match(/《([^》]+)》\s*(?:连载于|首发于|发布于)/);
        if (serialMatch) addCandidate(serialMatch[1], '连载格式');
      }
    }
    
    return candidates;
  }

  /**
   * 提取所有作者候选项（100+种模式）
   */
  private extractAllAuthorCandidates(content: string): string[] {
    const candidates: string[] = [];
    const seen = new Set<string>();
    
    const addCandidate = (author: string, source: string) => {
      const cleaned = author.trim().replace(/^[：:]\s*/, '');
      if (cleaned.length >= 1 && cleaned.length <= 30 && !seen.has(cleaned)) {
        // 过滤明显不是作者名的内容
        if (!/^(第|章|节|卷|序|前言|后记|目录|简介|内容|正文|\d)/.test(cleaned)) {
          seen.add(cleaned);
          candidates.push(cleaned);
          logger.debug(TAG, `作者候选[${source}]: ${cleaned}`);
        }
      }
    };
    
    // ========== 1. 从文件名提取 (10种模式) ==========
    const filename = this.defaultTitle;
    // 1.1 作者-书名 格式
    const authorFirst = filename.match(/^([^-_]+)[-_].+/);
    if (authorFirst && authorFirst[1].length <= 20) addCandidate(authorFirst[1], '文件名作者-');
    // 1.2 书名-作者 格式
    const authorLast = filename.match(/.+[-_]([^-_]+)$/);
    if (authorLast && authorLast[1].length <= 20) addCandidate(this.cleanTitle(authorLast[1]), '文件名-作者');
    // 1.3 (作者) 格式
    const authorParen = filename.match(/\(([^)]{1,20})\)/);
    if (authorParen) addCandidate(authorParen[1], '文件名(作者)');
    // 1.4 [作者] 格式
    const authorBracket = filename.match(/\[([^\]]{1,20})\]/);
    if (authorBracket) addCandidate(authorBracket[1], '文件名[作者]');
    // 1.5 【作者】格式
    const authorSquare = filename.match(/【([^】]{1,20})】/);
    if (authorSquare) addCandidate(authorSquare[1], '文件名【作者】');
    
    // ========== 2. 从文件内容提取 (90+种模式) ==========
    if (content) {
      const lines = content.split('\n').map(l => l.trim()).filter(l => l.length > 0);
      const first100Lines = lines.slice(0, 100);
      
      // 2.1-2.50 作者标识模式
      const authorPatterns: AuthorPattern[] = [
        // 中文标识
        { pattern: /^作者[：:]\s*(.+)$/i, group: 1, name: '作者:' } as AuthorPattern,
        { pattern: /^作\s*者[：:]\s*(.+)$/i, group: 1, name: '作 者:' } as AuthorPattern,
        { pattern: /^著[：:]\s*(.+)$/i, group: 1, name: '著:' } as AuthorPattern,
        { pattern: /^著者[：:]\s*(.+)$/i, group: 1, name: '著者:' } as AuthorPattern,
        { pattern: /^作家[：:]\s*(.+)$/i, group: 1, name: '作家:' } as AuthorPattern,
        { pattern: /^撰文[：:]\s*(.+)$/i, group: 1, name: '撰文:' } as AuthorPattern,
        { pattern: /^撰写[：:]\s*(.+)$/i, group: 1, name: '撰写:' } as AuthorPattern,
        { pattern: /^撰稿[：:]\s*(.+)$/i, group: 1, name: '撰稿:' } as AuthorPattern,
        { pattern: /^编著[：:]\s*(.+)$/i, group: 1, name: '编著:' } as AuthorPattern,
        { pattern: /^编写[：:]\s*(.+)$/i, group: 1, name: '编写:' } as AuthorPattern,
        { pattern: /^编辑[：:]\s*(.+)$/i, group: 1, name: '编辑:' } as AuthorPattern,
        { pattern: /^主编[：:]\s*(.+)$/i, group: 1, name: '主编:' } as AuthorPattern,
        { pattern: /^副主编[：:]\s*(.+)$/i, group: 1, name: '副主编:' } as AuthorPattern,
        { pattern: /^文[：:]\s*(.+)$/i, group: 1, name: '文:' } as AuthorPattern,
        { pattern: /^原作[：:]\s*(.+)$/i, group: 1, name: '原作:' } as AuthorPattern,
        { pattern: /^原著[：:]\s*(.+)$/i, group: 1, name: '原著:' } as AuthorPattern,
        { pattern: /^译者[：:]\s*(.+)$/i, group: 1, name: '译者:' } as AuthorPattern,
        { pattern: /^翻译[：:]\s*(.+)$/i, group: 1, name: '翻译:' } as AuthorPattern,
        { pattern: /^校对[：:]\s*(.+)$/i, group: 1, name: '校对:' } as AuthorPattern,
        { pattern: /^整理[：:]\s*(.+)$/i, group: 1, name: '整理:' } as AuthorPattern,
        { pattern: /^录入[：:]\s*(.+)$/i, group: 1, name: '录入:' } as AuthorPattern,
        { pattern: /^出品[：:]\s*(.+)$/i, group: 1, name: '出品:' } as AuthorPattern,
        { pattern: /^笔名[：:]\s*(.+)$/i, group: 1, name: '笔名:' } as AuthorPattern,
        { pattern: /^网名[：:]\s*(.+)$/i, group: 1, name: '网名:' } as AuthorPattern,
        { pattern: /^ID[：:]\s*(.+)$/i, group: 1, name: 'ID:' } as AuthorPattern,
        // 英文标识
        { pattern: /^by[：:\s]+(.+)$/i, group: 1, name: 'by' } as AuthorPattern,
        { pattern: /^author[：:\s]+(.+)$/i, group: 1, name: 'author:' } as AuthorPattern,
        { pattern: /^written\s+by[：:\s]+(.+)$/i, group: 1, name: 'written by' } as AuthorPattern,
        { pattern: /^writer[：:\s]+(.+)$/i, group: 1, name: 'writer:' } as AuthorPattern,
        { pattern: /^creator[：:\s]+(.+)$/i, group: 1, name: 'creator:' } as AuthorPattern,
        { pattern: /^translator[：:\s]+(.+)$/i, group: 1, name: 'translator:' } as AuthorPattern,
        { pattern: /^translated\s+by[：:\s]+(.+)$/i, group: 1, name: 'translated by' } as AuthorPattern,
        // 特殊格式
        { pattern: /^【作者】\s*(.+)$/i, group: 1, name: '【作者】' } as AuthorPattern,
        { pattern: /^\[作者\]\s*(.+)$/i, group: 1, name: '[作者]' } as AuthorPattern,
        { pattern: /^〖作者〗\s*(.+)$/i, group: 1, name: '〖作者〗' } as AuthorPattern,
        { pattern: /^★作者★\s*(.+)$/i, group: 1, name: '★作者★' } as AuthorPattern,
        { pattern: /^◆作者◆\s*(.+)$/i, group: 1, name: '◆作者◆' } as AuthorPattern,
        { pattern: /^●作者●\s*(.+)$/i, group: 1, name: '●作者●' } as AuthorPattern,
        // 组合格式
        { pattern: /作者[：:]\s*([^\s,，、]+)/i, group: 1, name: '作者:内联' } as AuthorPattern,
        { pattern: /著[：:]\s*([^\s,，、]+)/i, group: 1, name: '著:内联' } as AuthorPattern,
        { pattern: /by\s+([^\s,，、]+)/i, group: 1, name: 'by内联' } as AuthorPattern,
      ];
      
      for (let i = 0; i < first100Lines.length; i++) {
        const line = first100Lines[i];
        for (let j = 0; j < authorPatterns.length; j++) {
          const ap = authorPatterns[j];
          const match = line.match(ap.pattern);
          if (match && match[ap.group]) {
            addCandidate(match[ap.group], ap.name);
          }
        }
        
        // 2.51-2.60 特殊组合格式
        // 书名：《xxx》作者：xxx 格式
        const combinedMatch = line.match(/作者[：:]\s*([^\s《【\[（(]+)/);
        if (combinedMatch) addCandidate(combinedMatch[1], '组合格式');
        
        // xxx 著 格式
        const zhuMatch = line.match(/^([^\s]{2,15})\s+著$/);
        if (zhuMatch) addCandidate(zhuMatch[1], 'xxx著');
        
        // xxx 作 格式
        const zuoMatch = line.match(/^([^\s]{2,15})\s+作$/);
        if (zuoMatch) addCandidate(zuoMatch[1], 'xxx作');
        
        // xxx/著 格式
        const slashZhuMatch = line.match(/([^\s/]{2,15})\/著/);
        if (slashZhuMatch) addCandidate(slashZhuMatch[1], 'xxx/著');
        
        // (xxx著) 格式
        const parenZhuMatch = line.match(/[（(]([^）)]{2,15})著[）)]/);
        if (parenZhuMatch) addCandidate(parenZhuMatch[1], '(xxx著)');
      }
      
      // 2.61-2.70 从书名行提取作者
      const first20Lines = first100Lines.slice(0, 20);
      for (let k = 0; k < first20Lines.length; k++) {
        const line = first20Lines[k];
        // 《书名》xxx 格式（xxx可能是作者）
        const afterBookMatch = line.match(/《[^》]+》\s*([^\s《【\[（(]{2,15})/);
        if (afterBookMatch) addCandidate(afterBookMatch[1], '《》后');
        
        // xxx《书名》格式（xxx可能是作者）
        const beforeBookMatch = line.match(/^([^\s》]{2,15})\s*《/);
        if (beforeBookMatch && !this.isChapterTitle(beforeBookMatch[1])) {
          addCandidate(beforeBookMatch[1], '《》前');
        }
      }
    }
    
    return candidates;
  }

  /**
   * 提取所有简介候选项
   */
  private extractAllDescriptionCandidates(content: string): string[] {
    const candidates: string[] = [];
    const seen = new Set<string>();
    
    const addCandidate = (desc: string, source: string) => {
      const cleaned = desc.trim();
      if (cleaned.length >= 10 && cleaned.length <= 2000 && !seen.has(cleaned.substring(0, 50))) {
        seen.add(cleaned.substring(0, 50));
        candidates.push(cleaned.substring(0, 500));
        logger.debug(TAG, `简介候选[${source}]: ${cleaned.substring(0, 50)}...`);
      }
    };
    
    if (!content) return candidates;
    
    const lines = content.split('\n').map(l => l.trim());
    const first200Lines = lines.slice(0, 200);
    
    // 简介标识模式（50+种）
    const descPatterns: DescPattern[] = [
      { pattern: /^简介[：:]/i, name: '简介:' } as DescPattern,
      { pattern: /^内容简介[：:]/i, name: '内容简介:' } as DescPattern,
      { pattern: /^内容介绍[：:]/i, name: '内容介绍:' } as DescPattern,
      { pattern: /^内容提要[：:]/i, name: '内容提要:' } as DescPattern,
      { pattern: /^文案[：:]/i, name: '文案:' } as DescPattern,
      { pattern: /^摘要[：:]/i, name: '摘要:' } as DescPattern,
      { pattern: /^概要[：:]/i, name: '概要:' } as DescPattern,
      { pattern: /^概述[：:]/i, name: '概述:' } as DescPattern,
      { pattern: /^故事简介[：:]/i, name: '故事简介:' } as DescPattern,
      { pattern: /^故事梗概[：:]/i, name: '故事梗概:' } as DescPattern,
      { pattern: /^剧情简介[：:]/i, name: '剧情简介:' } as DescPattern,
      { pattern: /^剧情介绍[：:]/i, name: '剧情介绍:' } as DescPattern,
      { pattern: /^小说简介[：:]/i, name: '小说简介:' } as DescPattern,
      { pattern: /^小说介绍[：:]/i, name: '小说介绍:' } as DescPattern,
      { pattern: /^作品简介[：:]/i, name: '作品简介:' } as DescPattern,
      { pattern: /^作品介绍[：:]/i, name: '作品介绍:' } as DescPattern,
      { pattern: /^书籍简介[：:]/i, name: '书籍简介:' } as DescPattern,
      { pattern: /^书籍介绍[：:]/i, name: '书籍介绍:' } as DescPattern,
      { pattern: /^本书简介[：:]/i, name: '本书简介:' } as DescPattern,
      { pattern: /^本书介绍[：:]/i, name: '本书介绍:' } as DescPattern,
      { pattern: /^简要[：:]/i, name: '简要:' } as DescPattern,
      { pattern: /^提要[：:]/i, name: '提要:' } as DescPattern,
      { pattern: /^导读[：:]/i, name: '导读:' } as DescPattern,
      { pattern: /^前言[：:]/i, name: '前言:' } as DescPattern,
      { pattern: /^序言[：:]/i, name: '序言:' } as DescPattern,
      { pattern: /^序[：:]/i, name: '序:' } as DescPattern,
      { pattern: /^引言[：:]/i, name: '引言:' } as DescPattern,
      { pattern: /^引子[：:]/i, name: '引子:' } as DescPattern,
      { pattern: /^楔子[：:]/i, name: '楔子:' } as DescPattern,
      // 英文
      { pattern: /^synopsis[：:\s]/i, name: 'synopsis:' } as DescPattern,
      { pattern: /^description[：:\s]/i, name: 'description:' } as DescPattern,
      { pattern: /^summary[：:\s]/i, name: 'summary:' } as DescPattern,
      { pattern: /^abstract[：:\s]/i, name: 'abstract:' } as DescPattern,
      { pattern: /^introduction[：:\s]/i, name: 'introduction:' } as DescPattern,
      { pattern: /^overview[：:\s]/i, name: 'overview:' } as DescPattern,
      { pattern: /^plot[：:\s]/i, name: 'plot:' } as DescPattern,
      // 特殊格式
      { pattern: /^【简介】/i, name: '【简介】' } as DescPattern,
      { pattern: /^【内容简介】/i, name: '【内容简介】' } as DescPattern,
      { pattern: /^【文案】/i, name: '【文案】' } as DescPattern,
      { pattern: /^\[简介\]/i, name: '[简介]' } as DescPattern,
      { pattern: /^\[内容简介\]/i, name: '[内容简介]' } as DescPattern,
      { pattern: /^★简介★/i, name: '★简介★' } as DescPattern,
      { pattern: /^◆简介◆/i, name: '◆简介◆' } as DescPattern,
    ];
    
    for (let i = 0; i < first200Lines.length; i++) {
      const line = first200Lines[i];
      
      for (let k = 0; k < descPatterns.length; k++) {
        const dp = descPatterns[k];
        if (dp.pattern.test(line)) {
          // 收集简介内容
          let descContent = line.replace(dp.pattern, '').trim();
          let j = i + 1;
          while (j < first200Lines.length && j < i + 20) {
            const nextLine = first200Lines[j];
            if (nextLine.length === 0 || this.isChapterTitle(nextLine) || this.isMetadataLine(nextLine)) {
              break;
            }
            descContent += '\n' + nextLine;
            j++;
          }
          if (descContent.length >= 10) {
            addCandidate(descContent, dp.name);
          }
          break;
        }
      }
    }
    
    return candidates;
  }

  /**
   * 提取所有标签候选项
   */
  private extractAllTagsCandidates(content: string): string[] {
    const candidates: string[] = [];
    const seen = new Set<string>();
    
    const addCandidate = (tags: string, source: string) => {
      const cleaned = tags.trim();
      if (cleaned.length >= 2 && cleaned.length <= 200 && !seen.has(cleaned)) {
        seen.add(cleaned);
        candidates.push(cleaned);
        logger.debug(TAG, `标签候选[${source}]: ${cleaned}`);
      }
    };
    
    if (!content) return candidates;
    
    const lines = content.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    const first100Lines = lines.slice(0, 100);
    
    // 标签标识模式（30+种）
    const tagPatterns: TagPattern[] = [
      { pattern: /^标签[：:]\s*(.+)$/i, group: 1, name: '标签:' } as TagPattern,
      { pattern: /^分类[：:]\s*(.+)$/i, group: 1, name: '分类:' } as TagPattern,
      { pattern: /^类型[：:]\s*(.+)$/i, group: 1, name: '类型:' } as TagPattern,
      { pattern: /^类别[：:]\s*(.+)$/i, group: 1, name: '类别:' } as TagPattern,
      { pattern: /^题材[：:]\s*(.+)$/i, group: 1, name: '题材:' } as TagPattern,
      { pattern: /^风格[：:]\s*(.+)$/i, group: 1, name: '风格:' } as TagPattern,
      { pattern: /^关键词[：:]\s*(.+)$/i, group: 1, name: '关键词:' } as TagPattern,
      { pattern: /^关键字[：:]\s*(.+)$/i, group: 1, name: '关键字:' } as TagPattern,
      { pattern: /^主题[：:]\s*(.+)$/i, group: 1, name: '主题:' } as TagPattern,
      { pattern: /^属性[：:]\s*(.+)$/i, group: 1, name: '属性:' } as TagPattern,
      { pattern: /^元素[：:]\s*(.+)$/i, group: 1, name: '元素:' } as TagPattern,
      { pattern: /^设定[：:]\s*(.+)$/i, group: 1, name: '设定:' } as TagPattern,
      { pattern: /^背景[：:]\s*(.+)$/i, group: 1, name: '背景:' } as TagPattern,
      { pattern: /^世界观[：:]\s*(.+)$/i, group: 1, name: '世界观:' } as TagPattern,
      { pattern: /^tags[：:\s]+(.+)$/i, group: 1, name: 'tags:' } as TagPattern,
      { pattern: /^tag[：:\s]+(.+)$/i, group: 1, name: 'tag:' } as TagPattern,
      { pattern: /^category[：:\s]+(.+)$/i, group: 1, name: 'category:' } as TagPattern,
      { pattern: /^genre[：:\s]+(.+)$/i, group: 1, name: 'genre:' } as TagPattern,
      { pattern: /^keywords[：:\s]+(.+)$/i, group: 1, name: 'keywords:' } as TagPattern,
      { pattern: /^【标签】\s*(.+)$/i, group: 1, name: '【标签】' } as TagPattern,
      { pattern: /^【分类】\s*(.+)$/i, group: 1, name: '【分类】' } as TagPattern,
      { pattern: /^【类型】\s*(.+)$/i, group: 1, name: '【类型】' } as TagPattern,
      { pattern: /^\[标签\]\s*(.+)$/i, group: 1, name: '[标签]' } as TagPattern,
      { pattern: /^\[分类\]\s*(.+)$/i, group: 1, name: '[分类]' } as TagPattern,
    ];
    
    for (let i = 0; i < first100Lines.length; i++) {
      const line = first100Lines[i];
      for (let j = 0; j < tagPatterns.length; j++) {
        const tp = tagPatterns[j];
        const match = line.match(tp.pattern);
        if (match && match[tp.group]) {
          addCandidate(match[tp.group], tp.name);
        }
      }
    }
    
    // 从内容中提取常见标签关键词
    const commonTags: string[] = ['玄幻', '都市', '穿越', '重生', '系统', '修仙', '仙侠', '武侠', '科幻', '末世', 
      '悬疑', '推理', '恐怖', '灵异', '言情', '甜宠', '虐恋', '古言', '现言', '总裁', '豪门', '校园',
      '青春', '军事', '历史', '架空', '同人', '耽美', 'BL', '百合', 'GL', '无CP', '女强', '男强',
      '爽文', '慢热', '轻松', '搞笑', '治愈', '致郁', '黑暗', '热血', '冒险', '游戏', '电竞', '娱乐圈'];
    
    const foundTags: string[] = [];
    const contentLower = content.toLowerCase();
    for (let i = 0; i < commonTags.length; i++) {
      const tag = commonTags[i];
      if (contentLower.includes(tag.toLowerCase())) {
        foundTags.push(tag);
      }
    }
    if (foundTags.length > 0) {
      addCandidate(foundTags.join(', '), '内容关键词');
    }
    
    return candidates;
  }

  /**
   * 判断是否是元数据行
   */
  private isMetadataLine(line: string): boolean {
    const metadataPatterns = [
      /^作者[：:]/i, /^书名[：:]/i, /^简介[：:]/i, /^标签[：:]/i, /^分类[：:]/i,
      /^类型[：:]/i, /^状态[：:]/i, /^字数[：:]/i, /^更新[：:]/i, /^来源[：:]/i,
      /^出版[：:]/i, /^ISBN[：:]/i, /^版权[：:]/i
    ];
    return metadataPatterns.some(p => p.test(line));
  }

  /**
   * 简单判断是否是章节标题
   */
  private isChapterTitle(line: string): boolean {
    if (line.length === 0 || line.length > 50) return false;
    const chapterPatterns = [
      /^第[0-9一二三四五六七八九十百千万零〇]+[章节回集卷部篇]/,
      /^Chapter\s+\d+/i,
      /^卷[0-9一二三四五六七八九十百千万零〇]+/,
      /^[0-9]+[.、\s]/,
      /^序章/,
      /^序幕/,
      /^终章/,
      /^尾声/,
      /^番外/,
      /^楔子/,
      /^引子/,
      /^前言/,
      /^后记/,
    ];
    return chapterPatterns.some(p => p.test(line));
  }

  /**
   * 清理标题（去除时间戳前缀和扩展名）
   */
  private cleanTitle(rawTitle: string): string {
    let cleaned = rawTitle;
    // 去除时间戳前缀（如 1234567890_）
    cleaned = cleaned.replace(/^\d{10,}_/, '');
    // 去除日期前缀（如 2024-01-01_）
    cleaned = cleaned.replace(/^\d{4}[-_]\d{2}[-_]\d{2}[-_]/, '');
    // 去除扩展名
    cleaned = cleaned.replace(/\.txt$/i, '');
    // 去除常见的网站后缀
    cleaned = cleaned.replace(/[-_](全本|完结|精校|校对|完本|出书版|精排|排版)$/i, '');
    // 去除网站名
    cleaned = cleaned.replace(/[-_](起点|晋江|纵横|17k|潇湘|红袖|番茄|七猫)$/i, '');
    return cleaned.trim();
  }

  /**
   * 加载章节规则
   */
  private async loadTocRules(): Promise<void> {
    try {
      await this.tocRuleManager.initialize();
      this.availableTocRules = this.tocRuleManager.getAllRules();
      logger.info(TAG, `加载了 ${this.availableTocRules.length} 条章节规则`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `加载章节规则失败: ${String(error)}`);
    }
  }

  /**
   * 加载文件预览
   */
  private async loadFilePreview(): Promise<void> {
    if (!this.filePath) return;
    
    this.isLoadingPreview = true;
    this.previewError = '';
    
    try {
      // 读取原始文件缓冲区
      await this.loadRawFileBuffer();
      
      // 使用当前编码解码内容
      await this.decodeFileContent();
      
      // 提取元数据
      this.extractMetadataFromFile();
      
      // 自动检测章节
      await this.detectChapters();
      
      // 检测广告内容
      this.detectAdsInContent();
    } catch (e) {
      const error = e as Error;
      this.previewError = `读取文件失败: ${String(error)}`;
      logger.error(TAG, this.previewError);
    } finally {
      this.isLoadingPreview = false;
    }
  }

  /**
   * 加载原始文件缓冲区
   */
  private async loadRawFileBuffer(): Promise<void> {
    try {
      let openTarget = this.filePath;
      if (!this.filePath.startsWith('file://') && !this.filePath.startsWith('/')) {
        openTarget = `/${this.filePath}`;
      }
      
      const file = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(file.fd);
      // 读取完整文件内容用于章节检测（最大10MB，超过则只读取前10MB）
      const maxReadSize = 10 * 1024 * 1024; // 10MB
      const readSize = Math.min(stat.size, maxReadSize);
      
      this.rawFileBuffer = new ArrayBuffer(readSize);
      SafeFileUtils.readSync(file.fd, this.rawFileBuffer);
      SafeFileUtils.closeSync(file);
      
      if (stat.size > maxReadSize) {
        logger.warn(TAG, `文件过大(${stat.size}字节)，只读取前${maxReadSize}字节用于章节检测`);
      }
      
      logger.info(TAG, `加载文件缓冲区: ${readSize} 字节`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `加载文件缓冲区失败: ${String(error)}`);
      throw error;
    }
  }

  /**
   * 使用当前选择的编码解码文件内容
   */
  private async decodeFileContent(): Promise<void> {
    if (!this.rawFileBuffer) return;
    
    try {
      let encoding = 'utf-8';
      
      // 根据选择的编码确定解码方式
      switch (this.selectedEncoding) {
        case TextEncoding.UTF8:
          encoding = 'utf-8';
          break;
        case TextEncoding.GBK:
          encoding = 'gbk';
          break;
        case TextEncoding.GB2312:
          encoding = 'gb2312';
          break;
        case TextEncoding.BIG5:
          encoding = 'big5';
          break;
        case TextEncoding.AUTO:
        default:
          // 自动检测编码
          encoding = this.detectEncoding(this.rawFileBuffer);
          break;
      }
      
      const decoder = new util.TextDecoder(encoding);
      this.fileContent = decoder.decodeToString(new Uint8Array(this.rawFileBuffer));
      this.contentPreview = this.fileContent.substring(0, 3000);
      
      logger.info(TAG, `文件解码完成，使用编码: ${encoding}`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `文件解码失败: ${String(error)}`);
      // 回退到UTF-8
      const decoder = new util.TextDecoder('utf-8');
      this.fileContent = decoder.decodeToString(new Uint8Array(this.rawFileBuffer));
      this.contentPreview = this.fileContent.substring(0, 3000);
    }
  }

  /**
   * 自动检测文件编码
   */
  private detectEncoding(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    
    // 检查BOM
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return 'utf-16be';
    }
    
    // 简单的GBK/UTF-8检测
    let utf8Score = 0;
    let gbkScore = 0;
    
    for (let i = 0; i < Math.min(bytes.length, 10000); i++) {
      const b = bytes[i];
      
      // UTF-8多字节序列检测
      if (b >= 0xC0 && b <= 0xDF && i + 1 < bytes.length) {
        if ((bytes[i + 1] & 0xC0) === 0x80) {
          utf8Score++;
          i++;
        }
      } else if (b >= 0xE0 && b <= 0xEF && i + 2 < bytes.length) {
        if ((bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80) {
          utf8Score += 2;
          i += 2;
        }
      }
      
      // GBK双字节检测
      if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
        const b2 = bytes[i + 1];
        if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
          gbkScore++;
          i++;
        }
      }
    }
    
    logger.info(TAG, `编码检测: UTF-8得分=${utf8Score}, GBK得分=${gbkScore}`);
    
    // 如果GBK得分明显高于UTF-8，使用GBK
    if (gbkScore > utf8Score * 2 && gbkScore > 10) {
      return 'gbk';
    }
    
    return 'utf-8';
  }

  /**
   * 切换编码并重新解码
   */
  private async onEncodingChanged(): Promise<void> {
    this.isLoadingPreview = true;
    try {
      await this.decodeFileContent();
      await this.detectChapters();
    } finally {
      this.isLoadingPreview = false;
    }
  }

  /**
   * 检测章节
   */
  private async detectChapters(): Promise<void> {
    if (!this.fileContent) return;
    
    try {
      // 使用选中的规则解析章节（空字符串表示使用所有启用规则）
      const chapters = this.tocRuleManager.parseChaptersByRuleId(this.fileContent, this.selectedTocRuleId);
      this.allChapters = chapters;  // 存储全部章节
      this.previewChapters = chapters;  // 显示全部章节
      logger.info(TAG, `检测到 ${chapters.length} 个章节，使用规则: ${this.selectedTocRuleId || '自动检测'}`);
    } catch (e) {
      const error = e as Error;
      logger.error(TAG, `章节检测失败: ${String(error)}`);
      this.allChapters = [];
      this.previewChapters = [];
    }
  }

  /**
   * 重新检测章节（使用指定规则）
   */
  private async redetectChapters(): Promise<void> {
    this.isLoadingPreview = true;
    try {
      await this.detectChapters();
    } finally {
      this.isLoadingPreview = false;
    }
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    const config: ScraperDialogConfig = {
      initialKeyword: this.title || this.cleanTitle(this.defaultTitle) || '',
      contentType: ScraperContentType.BOOK,
      title: '搜索小说信息'
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });

    this.scraperDialogController.open();
  }

  /**
   * 应用刮削结果
   */
  private applyScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用刮削结果: ${metadata.title}`);

    // 应用标题
    if (metadata.title) {
      this.title = metadata.title;
    }

    // 应用作者
    if (result.applyAuthor && metadata.author) {
      this.author = metadata.author;
    }

    // 应用描述
    if (result.applyDescription && metadata.description) {
      this.description = metadata.description;
    }

    // 应用标签
    if (result.applyTags && metadata.tags && metadata.tags.length > 0) {
      this.tagsText = metadata.tags.join(', ');
    }

    logger.info(TAG, '刮削结果已应用');
  }

  build() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text('小说导入设置')
          .fontSize(20)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 刮削按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

          Text('刮削')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(16)
        .margin({ right: 12 })
        .onClick(() => {
          this.openScraperDialog();
        })
        
        // 关闭按钮
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          .onClick(() => {
            this.onCancel();
            this.controller.close();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // Tab切换
      Row({ space: 0 }) {
        this.buildTabButton('基本信息', 0)
        this.buildTabButton('章节设置', 1)
        this.buildTabButton('替换净化', 2)
        this.buildTabButton('内容预览', 3)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

      // Tab内容
      Scroll() {
        Column({ space: 12 }) {
          if (this.currentTab === 0) {
            this.buildBasicInfoTab()
          } else if (this.currentTab === 1) {
            this.buildChapterSettingsTab()
          } else if (this.currentTab === 2) {
            this.buildReplaceRulesTab()
          } else {
            this.buildContentPreviewTab()
          }
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      // 操作按钮
      Row({ space: 12 }) {
        Button('取消')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            this.onCancel();
            this.controller.close();
          })

        Button('开始导入')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            if (this.validateForm()) {
              // 收集要删除的广告行号
              const adLines: number[] = [];
              if (this.enableReplaceRules) {
                for (let i = 0; i < this.detectedAds.length; i++) {
                  if (this.detectedAds[i].selected) {
                    adLines.push(this.detectedAds[i].lineNumber);
                  }
                }
              }
              
              const result: NovelImportDialogResult = {
                title: this.title.trim() || this.cleanTitle(this.defaultTitle) || '未知书名',
                author: this.author.trim() || '未知作者',
                description: this.description.trim(),
                tags: this.parseTags(this.tagsText),
                encoding: this.selectedEncoding,
                selectedTocRuleId: this.selectedTocRuleId,
                autoSplitChapters: this.autoSplitChapters,
                previewChapters: this.allChapters,
                enableReplaceRules: this.enableReplaceRules,
                adLinesToRemove: adLines,
                coverPath: this.customCoverPath || this.coverPath || undefined
              };
              this.onConfirm(result);
              this.controller.close();
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    }
    .width('95%')
    .height('85%')
    .backgroundColor(DialogSurfaceStyleHelper.getPopupCardBackground(this.themeState))
    .backgroundBlurStyle(
      DialogSurfaceStyleHelper.getPopupCardBlurStyle(),
      DialogSurfaceStyleHelper.getPopupCardBlurOptions()
    )
    .backgroundEffect(DialogSurfaceStyleHelper.getPopupCardBackgroundEffect())
    .borderRadius(26)
    .clip(true)
    .border({
      width: 1,
      color: DialogSurfaceStyleHelper.getPopupCardBorderColor(this.themeState)
    })
    .shadow({
      radius: 26,
      color: DialogSurfaceStyleHelper.getPopupCardShadowColor(this.themeState),
      offsetX: 0,
      offsetY: 10
    })
  }

  @Builder
  buildTabButton(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentTab === index
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .border({
      width: { bottom: this.currentTab === index ? 2 : 0 },
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder
  buildBasicInfoTab() {
    Column({ space: 16 }) {
      // 封面区域
      Row({ space: 16 }) {
        // 封面预览
        Column() {
          if (this.customCoverPath || this.coverPath) {
            Image(this.normalizeCoverPath(this.customCoverPath || this.coverPath) + `?refresh=${this.coverRefreshKey}`)
              .width(80)
              .height(110)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.text_book_closed'))
                .fontSize(32)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              Text('无封面')
                .fontSize(11)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width(80)
            .height(110)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(6)
            .justifyContent(FlexAlign.Center)
          }
        }
        
        // 封面操作按钮
        Column({ space: 8 }) {
          Text('封面')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Row({ space: 8 }) {
            Button('选择')
              .fontSize(12)
              .height(32)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(Color.White)
              .borderRadius(6)
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.selectCustomCover();
              })
            
            Button(this.isGeneratingCover ? '生成中...' : '重新生成')
              .fontSize(12)
              .height(32)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme))
              .fontColor(Color.White)
              .borderRadius(6)
              .fontFamily(this.appFontFamily)
              .enabled(!this.isGeneratingCover)
              .onClick(() => {
                this.regenerateCover();
              })
          }
          
          if (this.customCoverPath) {
            Button('清除')
              .fontSize(12)
              .height(28)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(6)
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.customCoverPath = '';
                this.coverRefreshKey++;
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ bottom: 8 })

      // 提示信息
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(16)
          .fontColor([AppColors.info])
        Text('点击输入框右侧按钮可选择自动提取的候选项')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(AppColors.info)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(AppColors.withAlpha(ColorRole.INFO, 0.1))
      .borderRadius(8)

      // 书名
      Column({ space: 4 }) {
        Row() {
          Text('书名 *')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.titleCandidates.length > 0) {
            Text(`${this.titleCandidates.length}个候选`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.title, placeholder: '请输入书名' })
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .height(44)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.title = value;
            })
          
          // 候选项下拉按钮
          if (this.titleCandidates.length > 0) {
            Button() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            }
            .width(44)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .onClick(() => {
              this.showTitleDropdown = !this.showTitleDropdown;
              this.showAuthorDropdown = false;
              this.showDescriptionDropdown = false;
              this.showTagsDropdown = false;
            })
          }
        }
        .width('100%')
        
        // 书名候选项下拉列表
        if (this.showTitleDropdown && this.titleCandidates.length > 0) {
          this.buildCandidateDropdown(this.titleCandidates, (value: string) => {
            this.title = value;
            this.showTitleDropdown = false;
          })
        }
      }
      .width('100%')

      // 作者
      Column({ space: 4 }) {
        Row() {
          Text('作者')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.authorCandidates.length > 0) {
            Text(`${this.authorCandidates.length}个候选`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.author, placeholder: '请输入作者' })
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .height(44)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.author = value;
            })
          
          // 候选项下拉按钮
          if (this.authorCandidates.length > 0) {
            Button() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            }
            .width(44)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .onClick(() => {
              this.showAuthorDropdown = !this.showAuthorDropdown;
              this.showTitleDropdown = false;
              this.showDescriptionDropdown = false;
              this.showTagsDropdown = false;
            })
          }
        }
        .width('100%')
        
        // 作者候选项下拉列表
        if (this.showAuthorDropdown && this.authorCandidates.length > 0) {
          this.buildCandidateDropdown(this.authorCandidates, (value: string) => {
            this.author = value;
            this.showAuthorDropdown = false;
          })
        }
      }
      .width('100%')

      // 简介
      Column({ space: 4 }) {
        Row() {
          Text('简介')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.descriptionCandidates.length > 0) {
            Text(`${this.descriptionCandidates.length}个候选`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .onClick(() => {
                this.showDescriptionDropdown = !this.showDescriptionDropdown;
                this.showTitleDropdown = false;
                this.showAuthorDropdown = false;
                this.showTagsDropdown = false;
              })
          }
        }
        .width('100%')

        TextArea({ text: this.description, placeholder: '请输入简介...' })
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .padding(12)
          .height(100)
          .width('100%')
          .onChange((value: string) => {
            this.description = value;
          })
        
        // 简介候选项下拉列表
        if (this.showDescriptionDropdown && this.descriptionCandidates.length > 0) {
          this.buildCandidateDropdown(this.descriptionCandidates, (value: string) => {
            this.description = value;
            this.showDescriptionDropdown = false;
          }, true)
        }
      }
      .width('100%')

      // 标签
      Column({ space: 4 }) {
        Row() {
          Text('标签（逗号分隔）')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.tagsCandidates.length > 0) {
            Text(`${this.tagsCandidates.length}个候选`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.tagsText, placeholder: '例如: 玄幻, 都市, 穿越' })
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .height(44)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.tagsText = value;
            })
          
          // 候选项下拉按钮
          if (this.tagsCandidates.length > 0) {
            Button() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            }
            .width(44)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .onClick(() => {
              this.showTagsDropdown = !this.showTagsDropdown;
              this.showTitleDropdown = false;
              this.showAuthorDropdown = false;
              this.showDescriptionDropdown = false;
            })
          }
        }
        .width('100%')
        
        // 标签候选项下拉列表
        if (this.showTagsDropdown && this.tagsCandidates.length > 0) {
          this.buildCandidateDropdown(this.tagsCandidates, (value: string) => {
            this.tagsText = value;
            this.showTagsDropdown = false;
          })
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildCandidateDropdown(candidates: string[], onSelect: (value: string) => void, isLongText: boolean = false) {
    Scroll() {
      Column({ space: 2 }) {
        ForEach(candidates, (candidate: string, index: number) => {
          Row() {
            Text(isLongText ? candidate.substring(0, 100) + (candidate.length > 100 ? '...' : '') : candidate)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(isLongText ? 3 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(index % 2 === 0 
            ? Color.Transparent 
            : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(4)
          .onClick(() => {
            onSelect(candidate);
          })
        })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 200 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .margin({ top: 4 })
    .scrollBar(BarState.Auto)
  }

  @Builder
  buildChapterSettingsTab() {
    Column({ space: 16 }) {
      // 自动分章开关
      Row() {
        Column({ space: 4 }) {
          Text('自动识别章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('使用章节规则自动分割章节')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.autoSplitChapters })
          .selectedColor(AppColors.primary)
          .onChange((isOn: boolean) => {
            this.autoSplitChapters = isOn;
            if (isOn) {
              this.redetectChapters();
            }
          })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)

      // 编码选择
      Column({ space: 8 }) {
        Text('文本编码')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.getEncodingOptions(), (option: EncodingOption) => {
            this.buildEncodingChip(option.label, option.value)
          })
        }
        .width('100%')
      }
      .width('100%')

      // 章节规则选择
      if (this.autoSplitChapters) {
        Column({ space: 8 }) {
          Row() {
            Text('章节规则')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Text(`${this.availableTocRules.filter(r => r.enabled).length} 条启用`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width('100%')

          // 规则列表
          Column({ space: 6 }) {
            // 自动检测选项
            this.buildRuleOption('自动检测', '使用所有启用的规则自动匹配', '')

            ForEach(this.availableTocRules.filter(r => r.enabled).slice(0, 10), (rule: TxtTocRule) => {
              this.buildRuleOption(rule.name, rule.example, rule.id)
            })
          }
          .width('100%')
        }
        .width('100%')
      }

      // 章节预览统计
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('章节预览')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.isLoadingPreview) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          } else {
            Text(`共 ${this.allChapters.length} 章`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .width('100%')

        if (this.allChapters.length > 0) {
          // 使用Scroll包裹章节列表，支持滚动查看全部章节
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.allChapters, (chapter: TxtChapter, index: number) => {
                Row({ space: 8 }) {
                  Text(`${index + 1}.`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .width(40)
                  Text(chapter.title)
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              })
            }
            .width('100%')
          }
          .width('100%')
          .height(200)  // 固定高度，支持滚动
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .scrollBar(BarState.Auto)
        } else if (!this.isLoadingPreview) {
          Text(this.autoSplitChapters ? '未检测到章节，将作为单章节导入' : '已关闭自动分章')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding(12)
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildReplaceRulesTab() {
    Column({ space: 16 }) {
      // 启用替换净化开关
      Row() {
        Column({ space: 4 }) {
          Text('启用替换净化')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('导入时自动删除检测到的广告内容')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.enableReplaceRules })
          .selectedColor(AppColors.primary)
          .onChange((isOn: boolean) => {
            this.enableReplaceRules = isOn;
          })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)

      // 检测到的广告内容
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(18)
            .fontColor([AppColors.warning])
          Text('检测到的疑似广告')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Text(`${this.detectedAds.filter(ad => ad.selected).length}/${this.detectedAds.length} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')

        if (this.detectedAds.length === 0) {
          Row() {
            Text('未检测到疑似广告内容')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding(24)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
        } else {
          // 全选/取消全选按钮
          Row({ space: 8 }) {
            Button('全选')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(Color.Transparent)
              .borderRadius(4)
              .height(28)
              .onClick(() => {
                this.detectedAds = this.detectedAds.map(ad => {
                  const newAd: DetectedAdItem = {
                    content: ad.content,
                    lineNumber: ad.lineNumber,
                    ruleName: ad.ruleName,
                    selected: true
                  };
                  return newAd;
                });
              })
            Button('取消全选')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .backgroundColor(Color.Transparent)
              .borderRadius(4)
              .height(28)
              .onClick(() => {
                this.detectedAds = this.detectedAds.map(ad => {
                  const newAd: DetectedAdItem = {
                    content: ad.content,
                    lineNumber: ad.lineNumber,
                    ruleName: ad.ruleName,
                    selected: false
                  };
                  return newAd;
                });
              })
          }
          .width('100%')

          // 广告列表
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.detectedAds, (ad: DetectedAdItem, index: number) => {
                Row({ space: 8 }) {
                  Checkbox()
                    .select(ad.selected)
                    .selectedColor(AppColors.primary)
                    .onChange((isChecked: boolean) => {
                      const newAds = [...this.detectedAds];
                      const updatedAd: DetectedAdItem = {
                        content: ad.content,
                        lineNumber: ad.lineNumber,
                        ruleName: ad.ruleName,
                        selected: isChecked
                      };
                      newAds[index] = updatedAd;
                      this.detectedAds = newAds;
                    })
                  
                  Column({ space: 2 }) {
                    Row({ space: 4 }) {
                      Text(`行${ad.lineNumber}`)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      Text(`[${ad.ruleName}]`)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(AppColors.warning)
                    }
                    Text(ad.content)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor(index % 2 === 0 
                  ? Color.Transparent 
                  : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(4)
              })
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 300 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
          })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')

      // 替换规则统计
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_shield'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('替换规则')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Text(`${this.availableReplaceRules.filter(r => r.enabled).length} 条启用`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')

        Text('替换规则将在导入时应用，用于净化正文内容中的广告、乱码等')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildContentPreviewTab() {
    Column({ space: 12 }) {
      // 文件信息
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('文件内容预览')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      if (this.previewError) {
        Text(this.previewError)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(AppColors.error)
          .width('100%')
          .padding(12)
          .backgroundColor(AppColors.withAlpha(ColorRole.ERROR, 0.1))
          .borderRadius(8)
      } else if (this.contentPreview) {
        Text(this.contentPreview)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .maxLines(50)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (this.isLoadingPreview) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('正在加载预览...')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(40)
      } else {
        Text('无法加载文件预览')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(40)
      }
    }
    .width('100%')
  }

  @Builder
  buildEncodingChip(label: string, value: TextEncoding) {
    Text(label)
      .fontSize(13)
      .fontFamily(this.appFontFamily)
      .fontColor(this.selectedEncoding === value
        ? AppColors.onPrimary
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.selectedEncoding === value
        ? AppColors.primary
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(16)
      .onClick(() => {
        if (this.selectedEncoding !== value) {
          this.selectedEncoding = value;
          // 切换编码后重新解码并更新预览
          this.onEncodingChanged();
        }
      })
  }

  @Builder
  buildRuleOption(name: string, example: string, ruleId: string) {
    Row({ space: 12 }) {
      Radio({ value: ruleId, group: 'tocRule' })
        .checked(this.selectedTocRuleId === ruleId)
        .onChange((isChecked: boolean) => {
          if (isChecked && this.selectedTocRuleId !== ruleId) {
            this.selectedTocRuleId = ruleId;
            // 切换规则后重新检测章节
            this.redetectChapters();
          }
        })

      Column({ space: 2 }) {
        Text(name)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        if (example) {
          Text(example)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 8, right: 8 })
    .backgroundColor(this.selectedTocRuleId === ruleId
      ? AppColors.withAlpha(ColorRole.PRIMARY, 0.1)
      : Color.Transparent)
    .borderRadius(6)
    .onClick(() => {
      if (this.selectedTocRuleId !== ruleId) {
        this.selectedTocRuleId = ruleId;
        // 切换规则后重新检测章节
        this.redetectChapters();
      }
    })
  }

  /**
   * 获取编码选项
   */
  private getEncodingOptions(): EncodingOption[] {
    return [
      { label: '自动检测', value: TextEncoding.AUTO },
      { label: 'UTF-8', value: TextEncoding.UTF8 },
      { label: 'GBK', value: TextEncoding.GBK },
      { label: 'GB2312', value: TextEncoding.GB2312 },
      { label: 'BIG5', value: TextEncoding.BIG5 }
    ];
  }

  /**
   * 验证表单
   */
  private validateForm(): boolean {
    if (this.title.trim().length === 0 && (!this.defaultTitle || this.defaultTitle.length === 0)) {
      logger.warn(TAG, '书名不能为空');
      return false;
    }
    return true;
  }

  /**
   * 解析标签字符串
   */
  private parseTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }

    return tagsText
      .split(/[,，、]/)
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }
}

/**
 * 编码选项接口
 */
interface EncodingOption {
  label: string;
  value: TextEncoding;
}

/**
 * 标题提取模式接口
 */
interface TitlePattern {
  pattern: RegExp;
  group: number;
  name: string;
}

/**
 * 括号提取模式接口
 */
interface BracketPattern {
  pattern: RegExp;
  name: string;
}

/**
 * 作者提取模式接口
 */
interface AuthorPattern {
  pattern: RegExp;
  group: number;
  name: string;
}

/**
 * 简介提取模式接口
 */
interface DescPattern {
  pattern: RegExp;
  name: string;
}

/**
 * 标签提取模式接口
 */
interface TagPattern {
  pattern: RegExp;
  group: number;
  name: string;
}

/**
 * 检测到的广告项
 */
interface DetectedAdItem {
  content: string;
  lineNumber: number;
  ruleName: string;
  selected: boolean;
}

/**
 * 广告模式定义
 */
interface AdPatternDef {
  pattern: RegExp;
  name: string;
}
