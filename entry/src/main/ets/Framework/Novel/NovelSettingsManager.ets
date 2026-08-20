/**
 * 小说设置管理器
 * 管理搜索设置、书源分组等配置
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSettingsManager.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';

const TAG = 'NovelSettingsManager';

/**
 * 小说搜索设置
 */
export interface NovelSearchSettings {
  maxConcurrentSources: number;      // 同时搜索的书源数量
  searchTimeout: number;             // 搜索超时时间(ms)
  enabledGroups: string[];           // 启用的书源分组
  disabledSources: string[];         // 禁用的书源URL列表
  searchHistoryLimit: number;        // 搜索历史记录数量限制
}

/**
 * 书源分组信息
 */
export interface SourceGroup {
  name: string;
  enabled: boolean;
  sourceCount: number;
}

/**
 * 书架排序方式
 */
export type BookshelfSortType = 'lastRead' | 'name' | 'author' | 'addTime' | 'updateTime';

/**
 * 书架设置
 */
export interface BookshelfSettings {
  sortType: BookshelfSortType;
  sortAscending: boolean;
  showReadProgress: boolean;
  gridColumns: number;
  displayMode: 'grid' | 'list';
}

/**
 * 默认搜索设置
 */
export const DEFAULT_SEARCH_SETTINGS: NovelSearchSettings = {
  maxConcurrentSources: 5,
  searchTimeout: 30000,
  enabledGroups: [],
  disabledSources: [],
  searchHistoryLimit: 50
};

/**
 * 默认书架设置
 */
export const DEFAULT_BOOKSHELF_SETTINGS: BookshelfSettings = {
  sortType: 'lastRead',
  sortAscending: false,
  showReadProgress: true,
  gridColumns: 3,
  displayMode: 'grid'
};

/**
 * 历史浏览记录（进入详情页即记录）
 */
export interface BrowseHistoryItem {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  author: string;
  coverUrl: string;
  sourceName: string;
  browseTime: number;  // 浏览时间戳
}

/**
 * 历史浏览记录输入（不包含browseTime）
 */
export interface BrowseHistoryInput {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  author: string;
  coverUrl: string;
  sourceName: string;
}

/**
 * 设置键常量接口
 */
export interface NovelSettingKeysType {
  SEARCH_SETTINGS: string;
  BOOKSHELF_SETTINGS: string;
  SOURCE_GROUPS: string;
  SEARCH_HISTORY: string;
  TXT_TOC_RULES: string;
  DICTIONARY_SETTINGS: string;
  BROWSE_HISTORY: string;
  DICT_RULES: string;
}

/**
 * 设置键常量
 */
export const NOVEL_SETTING_KEYS: NovelSettingKeysType = {
  SEARCH_SETTINGS: 'novel_search_settings',
  BOOKSHELF_SETTINGS: 'novel_bookshelf_settings',
  SOURCE_GROUPS: 'novel_source_groups',
  SEARCH_HISTORY: 'novel_search_history',
  TXT_TOC_RULES: 'novel_txt_toc_rules',
  DICTIONARY_SETTINGS: 'novel_dictionary_settings',
  BROWSE_HISTORY: 'novel_browse_history',
  DICT_RULES: 'novel_dict_rules'
};

/**
 * TXT目录规则
 */
export interface TxtTocRule {
  id: string;
  name: string;
  pattern: string;
  enabled: boolean;
  priority: number;
  example: string;
}

/**
 * TXT目录规则输入（不包含id）
 */
export interface TxtTocRuleInput {
  name: string;
  pattern: string;
  enabled: boolean;
  priority: number;
  example: string;
}

/**
 * TXT目录项
 */
export interface TxtTocItem {
  title: string;
  position: number;
  isVolume: boolean;
}

/**
 * 内置章节规则片段
 */
const TXT_TOC_NUM_TOKEN: string = '(?:[\\d０-９]{1,5}|[〇零一二两三四五六七八九十百千万萬壹贰叁肆伍陆柒捌玖拾佰仟壱弐参]{1,12}|[IVXLCDMivxlcdm]{1,10})';
const TXT_TOC_LINE_PREFIX: string = '^[ 　\\t]{0,4}';
const TXT_TOC_LINE_SUFFIX: string = '.{0,45}$';
const TXT_TOC_CJK_SPECIAL_TOKEN: string = '(?:序章|序幕|楔子|引子|前言|正文(?!完|结)|终章|終章|最终话|最終話|后记|後記|尾声|尾聲|番外|番外篇|番外編|外传|外傳|外伝|特别篇|特別篇|特別編|短篇|短編|短篇集|短編集|读切|読切|読み切り|おまけ|オマケ|単行本|单行本|コミックス|同人誌|同人志|同人本|正篇|正編|本篇|本編|总集篇|總集篇|総集編|特典|特典漫画|彩页|彩頁|カラー|カラーページ|巻頭カラー|センターカラー|卷首语|巻末おまけ)';
const TXT_TOC_KR_SPECIAL_TOKEN: string = '(?:프롤로그|에필로그|외전|번외|특별편|후기|후일담|단행본|웹툰|만화|본편|특전|보너스|단편|총집편|스페셜|프리뷰|미리보기)';
const TXT_TOC_EN_NUM_LABEL_TOKEN: string = '(?:[Cc]hapter|[Cc]hap\\.?|[Cc]h\\.?|[Ee]pisode|[Ee]p\\.?|[Pp]art|[Vv]olume|[Vv]ol\\.?|[Bb]ook|[Ss]eason|[Ii]ssue|[Nn]o\\.?|[Ff]ile|[Aa]ct|[Ss]tage|[Cc]ase|[Mm]ission|[Qq]uest|[Tt]rack|[Ll]og|[Mm]anga|[Cc]omic|[Ww]ebtoon|[Mm]anhwa|[Mm]anhua|[Tt]ank(?:o|ō)bon|[Dd]oujinshi|[Aa]nthology|[Mm]agazine|[Ss]erial|[Aa]rc)';
const TXT_TOC_EN_SPECIAL_TOKEN: string = '(?:[Pp]rologue|[Ee]pilogue|[Ii]nterlude|[Ff]oreword|[Aa]fterword|[Ee]xtra|[Bb]onus|[Ss]pecial|[Ss]ide[ 　\\t-]*[Ss]tory|[Ss]ide[ 　\\t-]*[Cc]hapter|[Mm]ain[ 　\\t-]*[Ss]tory|[Aa]fter[ 　\\t-]*[Ss]tory|[Oo]make|[Oo]ne[ 　\\t-]*[Ss]hot|[Rr]aw|[Rr]aws|[Ss]can|[Ss]cans|[Ss]canlation|[Tt]ranslator[ 　\\t-]*[Nn]otes?|[Cc]redits?|[Cc]olor[ 　\\t-]*[Pp]ages?|[Cc]over|[Pp]in[ 　\\t-]*[Uu]p|[Dd]ouble[ 　\\t-]*[Pp]age[ 　\\t-]*[Ss]pread|[Ss]pread|[Pp]review|[Tt]easer|[Tt]railer)';
const TXT_TOC_PHOTO_LABEL_TOKEN: string = '(?:写真集|寫真集|写真|寫真|フォトブック|デジタル写真集|デジタルフォトブック|グラビア|コスプレ|撮影会|レイヤー|画集|畫集|插画|插畫|插图|插圖|图集|圖集|套图|套圖|相册|相冊|화보|화보집|디지털화보|사진집|사진|코스프레|포트폴리오|일러스트|[Pp]hotobook|[Pp]hoto[ 　\\t-]*[Bb]ook|[Pp]hoto[ 　\\t-]*[Ss]et|[Dd]igital[ 　\\t-]*[Pp]hoto[ 　\\t-]*(?:[Bb]ook|[Ss]et)|[Gg]ravure|[Cc]osplay|[Cc]oser|[Ii]mage[ 　\\t-]*[Ss]et|[Gg]allery|[Aa]lbum|[Pp]ortfolio|[Ll]ook[ 　\\t-]*[Bb]ook|[Ss]hoot(?:ing)?|[Ii]dol[ 　\\t-]*[Pp]hoto[ 　\\t-]*[Bb]ook|[Aa]rt[ 　\\t-]*[Bb]ook|[Ii]llust(?:ration)?[ 　\\t-]*[Bb]ook|CG[ 　\\t-]*[Ss]et|[Ss]et)';

/**
 * 默认TXT目录规则（内置，来自exportTxtTocRule.json，并扩展多语言漫画/写真标题）
 */
export const DEFAULT_TXT_TOC_RULES: TxtTocRule[] = [
  { id: '-1', name: '目录(去空白)', pattern: '(?<=[　\\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$', enabled: true, priority: 0, example: '第一章 假装第一章前面有空白但我不要' },
  { id: '-2', name: '目录', pattern: '^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$', enabled: true, priority: 1, example: '第一章 标准的粤语就是这样' },
  { id: '-3', name: '目录(匹配简介)', pattern: '(?<=[　\\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$', enabled: true, priority: 2, example: '简介 老夫诸葛村夫' },
  { id: '-4', name: '目录(古典、轻小说备用)', pattern: '^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$', enabled: false, priority: 3, example: '第一章 比上面只多了回和话' },
  { id: '-5', name: '数字(纯数字标题)', pattern: '(?<=[　\\s])\\d+\\.?[ 　\\t]{0,4}$', enabled: false, priority: 4, example: '12' },
  { id: '-6', name: '大写数字(纯数字标题)', pattern: '(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　\\t]{0,4}$', enabled: false, priority: 5, example: '一百七十' },
  { id: '-7', name: '数字混合(纯数字标题)', pattern: '(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\\d]{1,12}[ 　\\t]{0,4}$', enabled: false, priority: 6, example: '12\n一百七十' },
  { id: '-8', name: '数字 分隔符 标题名称', pattern: '^[ 　\\t]{0,4}\\d{1,5}[:：,.， 、_—\\-].{1,30}$', enabled: true, priority: 7, example: '1、这个就是标题' },
  { id: '-9', name: '大写数字 分隔符 标题名称', pattern: '^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\\-].{1,30}$', enabled: true, priority: 8, example: '一、只有前面的数字有差别\n二十四章 我瞎编的标题' },
  { id: '-10', name: '数字混合 分隔符 标题名称', pattern: '^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\\-]|\\d{1,5}章?[:：,.， 、_—\\-]).{0,30}$', enabled: false, priority: 9, example: '1、人参公鸡\n二百二十章 boy next door' },
  { id: '-11', name: '正文 标题/序号', pattern: '^[ 　\\t]{0,4}正文[ 　]{1,4}.{0,20}$', enabled: true, priority: 10, example: '正文 我奶常山赵子龙' },
  { id: '-12', name: 'Chapter/Section/Part/Episode 序号 标题', pattern: '^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\\s{0,4}\\d{1,4}.{0,30}$', enabled: true, priority: 11, example: 'Chapter 1 MyGrandmaIsNB' },
  { id: '-13', name: 'Chapter(去简介)', pattern: '^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\\.|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$', enabled: false, priority: 12, example: 'Chapter 1 MyGrandmaIsNB' },
  { id: '-14', name: '特殊符号 序号 标题', pattern: '(?<=[\\s　])[【〔〖「『〈［\\[](?:第|[Cc]hapter)[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$', enabled: true, priority: 13, example: '【第一章 后面的符号可以没有' },
  { id: '-15', name: '特殊符号 标题(成对)', pattern: '(?<=[\\s　]{0,4})(?:[\\[〈「『〖〔《（【\\(].{1,30}[\\)】）》〕〗』」〉\\]]?|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$', enabled: false, priority: 14, example: '『加个直角引号更专业』\n(11)我奶常山赵子聋' },
  { id: '-16', name: '特殊符号 标题(单个)', pattern: '(?<=[\\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$', enabled: true, priority: 15, example: '☆、晋江作者最喜欢的格式' },
  { id: '-17', name: '章/卷 序号 标题', pattern: '^[ \\t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$', enabled: true, priority: 16, example: '卷五 开源盛世' },
  { id: '-18', name: '顶格标题', pattern: '^\\S.{1,20}$', enabled: false, priority: 17, example: '20字以内顶格写的都是标题' },
  { id: '-19', name: '双标题(前向)', pattern: '(?m)(?<=[ \\t　]{0,4})第[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$(?=[\\s　]{0,8}第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章)', enabled: false, priority: 18, example: '第一章 真正的标题\n第一章 这个不要' },
  { id: '-20', name: '双标题(后向)', pattern: '(?m)(?<=[ \\t　]{0,4}第[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$[\\s　]{0,8})第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$', enabled: false, priority: 19, example: '第一章 这个标题不要\n第一章真正的标题' },
  { id: '-21', name: '书名 括号 序号', pattern: '^[一-龥]{1,20}[ 　\\t]{0,4}[(（][\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\\t]{0,4}$', enabled: true, priority: 20, example: '标题后面数字有括号(12)' },
  { id: '-22', name: '书名 序号', pattern: '^[一-龥]{1,20}[ 　\\t]{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\\t]{0,4}$', enabled: true, priority: 21, example: '标题后面数字没有括号124' },
  { id: '-23', name: '特定字符 标题 特定符号', pattern: '(?<=\\={3,6}).{1,40}?(?=\\=)', enabled: false, priority: 22, example: '===起这种标题干什么===' },
  { id: '-24', name: '字数分割 分节阅读', pattern: '(?<=[ 　\\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\\s{0,4}[\\d零一二两三四五六七八九十百千万]{1,6}\\s{0,4}[页节]).{0,30}$', enabled: true, priority: 23, example: '分节|分页|分段阅读\n第一页' },
  { id: '-25', name: '通用规则', pattern: '(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$|^.{0,6}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,20}$', enabled: false, priority: 24, example: '激进规则,适配更多非常用格式' },
  {
    id: '-26',
    name: '多语言目录(中日韩章节)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:' + TXT_TOC_CJK_SPECIAL_TOKEN + '|' +
      '(?:第\\s{0,4})?' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:章|章节|節|节|回|話|话|卷|巻|冊|册|集(?![合和])|部(?![分赛游])|篇(?!张)|幕|場|场|화|회|장|권|부|편)|' +
      '제\\s{0,4}' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:화|회|장|권|부|편)|시즌\\s{0,4}' + TXT_TOC_NUM_TOKEN + '|' +
      '[上下中前後后][篇部卷編编])' + TXT_TOC_LINE_SUFFIX,
    enabled: true,
    priority: 25,
    example: '第12話 番外編\n第３巻 巻末おまけ\n제12화 외전'
  },
  {
    id: '-27',
    name: '多语言目录(英文章节/卷集)',
    pattern: TXT_TOC_LINE_PREFIX + TXT_TOC_EN_NUM_LABEL_TOKEN + '[ 　\\t]{0,4}(?:#|No\\.?|no\\.?)?[ 　\\t]{0,4}' +
      TXT_TOC_NUM_TOKEN + '(?:[ 　\\t:：,.，、_—\\-].{0,50})?$',
    enabled: true,
    priority: 26,
    example: 'Chapter 12 The Visitor\nVol.03 Bonus\nEpisode #8'
  },
  {
    id: '-28',
    name: '多语言目录(英文特典/扫图术语)',
    pattern: TXT_TOC_LINE_PREFIX + TXT_TOC_EN_SPECIAL_TOKEN + '(?:[ 　\\t-]*(?:' + TXT_TOC_EN_NUM_LABEL_TOKEN +
      '|#)?[ 　\\t]{0,4}' + TXT_TOC_NUM_TOKEN + ')?(?:[ 　\\t:：,.，、_—\\-].{0,50})?$',
    enabled: true,
    priority: 27,
    example: 'Side Story 2\nOmake\nRaw Chapter 10\nScanlation Notes'
  },
  {
    id: '-29',
    name: '多语言目录(日文漫画术语)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:' + TXT_TOC_CJK_SPECIAL_TOKEN + '|' +
      '(?:第\\s{0,4})?' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:話|巻|卷|章|幕|部|編|編目)|' +
      '(?:前編|中編|後編|最終話|最新話|番外編|外伝|特別編|おまけ|オマケ|読み切り|読切|短編|単行本|コミックス|巻末おまけ|カラー|カラーページ))' +
      TXT_TOC_LINE_SUFFIX,
    enabled: true,
    priority: 28,
    example: '第12話 番外編\n後編\n巻末おまけ漫画'
  },
  {
    id: '-30',
    name: '多语言目录(韩文Webtoon术语)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:' + TXT_TOC_KR_SPECIAL_TOKEN + '|' +
      '(?:제\\s{0,4})?' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:화|회|장|권|부|편)|시즌\\s{0,4}' + TXT_TOC_NUM_TOKEN +
      '|에피소드\\s{0,4}' + TXT_TOC_NUM_TOKEN + ')' + TXT_TOC_LINE_SUFFIX,
    enabled: true,
    priority: 29,
    example: '제7화\n시즌 2\n외전 특별편'
  },
  {
    id: '-31',
    name: '漫画写真目录(写真/画集/图集)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:' + TXT_TOC_PHOTO_LABEL_TOKEN + '(?:[ 　\\t]*(?:第\\s{0,4})?' + TXT_TOC_NUM_TOKEN +
      '|[ 　\\t]*(?:#|No\\.?|no\\.?|Vol\\.?|vol\\.?)?[ 　\\t]{0,4}' + TXT_TOC_NUM_TOKEN + ')?|' +
      '(?:Vol\\.?|vol\\.?|Set|set|Gallery|gallery|Album|album)[ 　\\t]{0,4}' + TXT_TOC_NUM_TOKEN +
      '|(?:图集|圖集|套图|套圖|画集|畫集|写真集|화보|사진집)[ 　\\t]{0,4}' + TXT_TOC_NUM_TOKEN + ')' +
      '(?:[ 　\\t:：,.，、_—\\-].{0,45})?$',
    enabled: true,
    priority: 30,
    example: '写真集 Vol.2\nPhoto Set 03\n화보 12\n图集 001'
  },
  {
    id: '-32',
    name: '漫画写真目录(括号标签发布)',
    pattern: TXT_TOC_LINE_PREFIX + '[\\[【(（]?(?:(?:' + TXT_TOC_EN_NUM_LABEL_TOKEN + ')[ 　\\t]{0,4}' +
      TXT_TOC_NUM_TOKEN + '|第\\s{0,4}' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:章|話|话|卷|巻|集)|' +
      '제\\s{0,4}' + TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:화|회|장)|' +
      TXT_TOC_NUM_TOKEN + '\\s{0,4}(?:P|p|页|頁|ページ|쪽))[\\]】)）]?(?:[ 　\\t:：,.，、_—\\-].{0,50})?$',
    enabled: true,
    priority: 31,
    example: '[Ch.001] Title\n【第12話】\n(Vol.02) Extra'
  },
  {
    id: '-33',
    name: '漫画写真目录(页码/图片序号备用)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:[Pp]age|[Pp]\\.?|页|頁|ページ|쪽|컷)[ 　\\t]{0,4}' +
      TXT_TOC_NUM_TOKEN + '(?:[ 　\\t:：,.，、_—\\-].{0,35})?$',
    enabled: false,
    priority: 32,
    example: 'Page 12\nP.003\nページ 8\n12쪽'
  },
  {
    id: '-34',
    name: '漫画写真目录(文件夹序号备用)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:' + TXT_TOC_NUM_TOKEN + '[ 　\\t._—\\-]+.{1,40}|[#＃]' +
      TXT_TOC_NUM_TOKEN + '[ 　\\t._—\\-]*.{0,40})$',
    enabled: false,
    priority: 33,
    example: '001 - cover\n#012 gallery'
  },
  {
    id: '-35',
    name: '多语言目录(漫画发布术语)',
    pattern: TXT_TOC_LINE_PREFIX + '(?:(?:[Mm]anga|[Cc]omic|[Ww]ebtoon|[Mm]anhwa|[Mm]anhua|[Tt]ank(?:o|ō)bon|[Dd]oujinshi|' +
      '[Aa]nthology|[Mm]agazine|[Ss]erial)[ 　\\t]*(?:' + TXT_TOC_EN_NUM_LABEL_TOKEN +
      '|#|No\\.?|no\\.?|Vol\\.?|vol\\.?)?[ 　\\t]{0,4}' + TXT_TOC_NUM_TOKEN + '|' +
      TXT_TOC_EN_SPECIAL_TOKEN + '|' + TXT_TOC_CJK_SPECIAL_TOKEN +
      '(?:[ 　\\t]*(?:第\\s{0,4})?' + TXT_TOC_NUM_TOKEN + ')?|' +
      TXT_TOC_KR_SPECIAL_TOKEN + '(?:[ 　\\t]*(?:제\\s{0,4})?' + TXT_TOC_NUM_TOKEN + ')?)' +
      '(?:[ 　\\t:：,.，、_—\\-].{0,50})?$',
    enabled: true,
    priority: 34,
    example: 'Tankobon Vol.2\nManhwa 12\nTranslator Notes\n同人誌 特典\n총집편'
  },
  {
    id: '-36',
    name: '漫画写真目录(写真发布术语)',
    pattern: TXT_TOC_LINE_PREFIX + TXT_TOC_PHOTO_LABEL_TOKEN +
      '(?:[ 　\\t]*(?:#|No\\.?|no\\.?|Vol\\.?|vol\\.?|Set|set)?[ 　\\t]{0,4}' +
      TXT_TOC_NUM_TOKEN + ')?(?:[ 　\\t:：,.，、_—\\-].{0,45})?$',
    enabled: true,
    priority: 35,
    example: 'Gravure Set 03\nCosplay 12\nデジタル写真集 Vol.2\n포트폴리오 4'
  },
  { id: '-100', name: '默认分章规则', pattern: '', enabled: false, priority: 99, example: '兜底规则，请勿改动此内容' }
];

/**
 * 字典规则
 */
export interface DictRule {
  name: string;
  urlRule: string;
  showRule: string;
  enabled: boolean;
  sortNumber: number;
}

/**
 * 默认字典规则（内置）
 */
export const DEFAULT_DICT_RULES: DictRule[] = [
  {
    name: '百度汉语',
    urlRule: 'https://dict.baidu.com/s?wd={{key}}',
    showRule: '@js:var jsoup = org.jsoup.Jsoup.parse(result)\njsoup.select("script,#word-header,#term-header,.more-button,.disactive,#download-wrapper,#upload-dialog,#right-panel,#success-dialog,.toast-wrap,div[style^=color],.baike-feedback,#cishumean-wrapper,#syn_ant_wrapper,#baike-wrapper").remove()\njsoup.select("#content-panel").html()',
    enabled: true,
    sortNumber: 0
  },
  {
    name: '海词英文',
    urlRule: 'https://apii.dict.cn/mini.php?q={{key}}',
    showRule: 'tag.body@all',
    enabled: true,
    sortNumber: 1
  }
];

/**
 * 字典设置
 */
export interface DictionarySettings {
  enabled: boolean;
  defaultDictionary: string;
  autoLookup: boolean;
  showPinyin: boolean;
  showDefinition: boolean;
}

/**
 * 默认字典设置
 */
export const DEFAULT_DICTIONARY_SETTINGS: DictionarySettings = {
  enabled: false,
  defaultDictionary: 'builtin',
  autoLookup: false,
  showPinyin: true,
  showDefinition: true
};

/**
 * 小说设置管理器类
 */
export class NovelSettingsManager {
  private static instance: NovelSettingsManager | null = null;
  private settingsManager: SettingsManager;
  private searchSettings: NovelSearchSettings = DEFAULT_SEARCH_SETTINGS;
  private bookshelfSettings: BookshelfSettings = DEFAULT_BOOKSHELF_SETTINGS;
  private txtTocRules: TxtTocRule[] = DEFAULT_TXT_TOC_RULES;
  private dictRules: DictRule[] = DEFAULT_DICT_RULES;
  private dictionarySettings: DictionarySettings = DEFAULT_DICTIONARY_SETTINGS;
  private searchHistory: string[] = [];
  private browseHistory: BrowseHistoryItem[] = [];
  private browseHistoryLimit: number = 100;  // 历史浏览记录数量限制
  private browseHistoryListeners: Array<() => void> = [];  // 历史浏览变化监听器
  private isLoaded: boolean = false;

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
  }

  static getInstance(): NovelSettingsManager {
    if (!NovelSettingsManager.instance) {
      NovelSettingsManager.instance = new NovelSettingsManager();
    }
    return NovelSettingsManager.instance;
  }

  /**
   * 加载所有设置
   */
  async loadSettings(): Promise<void> {
    if (this.isLoaded) return;

    try {
      // 加载搜索设置
      this.searchSettings = this.settingsManager.getJSON<NovelSearchSettings>(
        NOVEL_SETTING_KEYS.SEARCH_SETTINGS,
        DEFAULT_SEARCH_SETTINGS
      );

      // 加载书架设置
      this.bookshelfSettings = this.settingsManager.getJSON<BookshelfSettings>(
        NOVEL_SETTING_KEYS.BOOKSHELF_SETTINGS,
        DEFAULT_BOOKSHELF_SETTINGS
      );

      // 加载TXT目录规则
      this.txtTocRules = this.settingsManager.getJSON<TxtTocRule[]>(
        NOVEL_SETTING_KEYS.TXT_TOC_RULES,
        DEFAULT_TXT_TOC_RULES
      );

      // 加载字典规则
      this.dictRules = this.settingsManager.getJSON<DictRule[]>(
        NOVEL_SETTING_KEYS.DICT_RULES,
        DEFAULT_DICT_RULES
      );

      // 加载字典设置
      this.dictionarySettings = this.settingsManager.getJSON<DictionarySettings>(
        NOVEL_SETTING_KEYS.DICTIONARY_SETTINGS,
        DEFAULT_DICTIONARY_SETTINGS
      );

      // 加载搜索历史
      this.searchHistory = this.settingsManager.getJSON<string[]>(
        NOVEL_SETTING_KEYS.SEARCH_HISTORY,
        []
      );

      // 加载历史浏览记录
      this.browseHistory = this.settingsManager.getJSON<BrowseHistoryItem[]>(
        NOVEL_SETTING_KEYS.BROWSE_HISTORY,
        []
      );

      this.isLoaded = true;
      logger.info(TAG, '小说设置加载完成');
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
  }

  // ==================== 搜索设置 ====================

  /**
   * 获取搜索设置
   */
  getSearchSettings(): NovelSearchSettings {
    return this.cloneSearchSettings(this.searchSettings);
  }

  private cloneSearchSettings(settings: NovelSearchSettings): NovelSearchSettings {
    const result: NovelSearchSettings = {
      maxConcurrentSources: settings.maxConcurrentSources,
      searchTimeout: settings.searchTimeout,
      enabledGroups: settings.enabledGroups.slice(),
      disabledSources: settings.disabledSources.slice(),
      searchHistoryLimit: settings.searchHistoryLimit
    };
    return result;
  }

  /**
   * 更新搜索设置
   */
  async updateSearchSettings(settings: NovelSearchSettings): Promise<void> {
    this.searchSettings = this.cloneSearchSettings(settings);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
    logger.info(TAG, '搜索设置已更新');
  }

  /**
   * 获取最大并发搜索数
   */
  getMaxConcurrentSources(): number {
    return this.searchSettings.maxConcurrentSources;
  }

  /**
   * 设置最大并发搜索数
   */
  async setMaxConcurrentSources(count: number): Promise<void> {
    this.searchSettings.maxConcurrentSources = Math.max(1, Math.min(50, count));
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
  }

  /**
   * 检查书源是否被禁用
   */
  isSourceDisabled(sourceUrl: string): boolean {
    return this.searchSettings.disabledSources.includes(sourceUrl);
  }

  /**
   * 禁用书源
   */
  async disableSource(sourceUrl: string): Promise<void> {
    if (!this.searchSettings.disabledSources.includes(sourceUrl)) {
      this.searchSettings.disabledSources.push(sourceUrl);
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
    }
  }

  /**
   * 启用书源
   */
  async enableSource(sourceUrl: string): Promise<void> {
    const index = this.searchSettings.disabledSources.indexOf(sourceUrl);
    if (index !== -1) {
      this.searchSettings.disabledSources.splice(index, 1);
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
    }
  }

  // ==================== 书源分组管理 ====================

  /**
   * 检查分组是否启用
   */
  isGroupEnabled(groupName: string): boolean {
    // 如果没有设置启用分组，则默认全部启用
    if (this.searchSettings.enabledGroups.length === 0) {
      return true;
    }
    return this.searchSettings.enabledGroups.includes(groupName);
  }

  /**
   * 启用分组
   */
  async enableGroup(groupName: string): Promise<void> {
    if (!this.searchSettings.enabledGroups.includes(groupName)) {
      this.searchSettings.enabledGroups.push(groupName);
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
    }
  }

  /**
   * 禁用分组
   */
  async disableGroup(groupName: string): Promise<void> {
    const index = this.searchSettings.enabledGroups.indexOf(groupName);
    if (index !== -1) {
      this.searchSettings.enabledGroups.splice(index, 1);
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
    }
  }

  /**
   * 设置启用的分组列表
   */
  async setEnabledGroups(groups: string[]): Promise<void> {
    this.searchSettings.enabledGroups = groups;
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_SETTINGS, this.searchSettings);
  }

  // ==================== 书架设置 ====================

  /**
   * 获取书架设置
   */
  getBookshelfSettings(): BookshelfSettings {
    return this.cloneBookshelfSettings(this.bookshelfSettings);
  }

  private cloneBookshelfSettings(settings: BookshelfSettings): BookshelfSettings {
    const result: BookshelfSettings = {
      sortType: settings.sortType,
      sortAscending: settings.sortAscending,
      showReadProgress: settings.showReadProgress,
      gridColumns: settings.gridColumns,
      displayMode: settings.displayMode
    };
    return result;
  }

  /**
   * 更新书架设置
   */
  async updateBookshelfSettings(settings: BookshelfSettings): Promise<void> {
    this.bookshelfSettings = this.cloneBookshelfSettings(settings);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.BOOKSHELF_SETTINGS, this.bookshelfSettings);
    logger.info(TAG, '书架设置已更新');
  }

  // ==================== TXT目录规则 ====================

  /**
   * 获取TXT目录规则
   */
  getTxtTocRules(): TxtTocRule[] {
    return this.txtTocRules.slice();
  }

  /**
   * 添加TXT目录规则
   */
  async addTxtTocRule(rule: TxtTocRuleInput): Promise<string> {
    const id = `rule_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    const newRule: TxtTocRule = {
      id: id,
      name: rule.name,
      pattern: rule.pattern,
      enabled: rule.enabled,
      priority: rule.priority,
      example: rule.example
    };
    this.txtTocRules.push(newRule);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.TXT_TOC_RULES, this.txtTocRules);
    return id;
  }

  /**
   * 更新TXT目录规则
   */
  async updateTxtTocRule(id: string, rule: TxtTocRule): Promise<void> {
    const index = this.txtTocRules.findIndex((r: TxtTocRule) => r.id === id);
    if (index !== -1) {
      this.txtTocRules[index] = {
        id: rule.id,
        name: rule.name,
        pattern: rule.pattern,
        enabled: rule.enabled,
        priority: rule.priority,
        example: rule.example
      };
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.TXT_TOC_RULES, this.txtTocRules);
    }
  }

  /**
   * 删除TXT目录规则
   */
  async deleteTxtTocRule(id: string): Promise<void> {
    this.txtTocRules = this.txtTocRules.filter(r => r.id !== id);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.TXT_TOC_RULES, this.txtTocRules);
  }

  /**
   * 解析TXT文件目录
   */
  parseTxtToc(content: string): TxtTocItem[] {
    const toc: TxtTocItem[] = [];
    const lines = content.split('\n');
    let position = 0;

    // 按优先级排序规则
    const enabledRules = this.txtTocRules.filter((r: TxtTocRule) => r.enabled);
    const sortedRules = enabledRules.sort((a: TxtTocRule, b: TxtTocRule) => a.priority - b.priority);

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineLength = line.length + 1;

      for (let j = 0; j < sortedRules.length; j++) {
        const rule = sortedRules[j];
        try {
          const regex = new RegExp(rule.pattern);
          if (regex.test(line.trim())) {
            const item: TxtTocItem = {
              title: line.trim(),
              position: position,
              isVolume: rule.priority === 0
            };
            toc.push(item);
            break;
          }
        } catch (e) {
          // 忽略无效正则
        }
      }

      position += lineLength;
    }

    return toc;
  }

  // ==================== 字典设置 ====================

  /**
   * 获取字典设置
   */
  getDictionarySettings(): DictionarySettings {
    return this.cloneDictionarySettings(this.dictionarySettings);
  }

  private cloneDictionarySettings(settings: DictionarySettings): DictionarySettings {
    const result: DictionarySettings = {
      enabled: settings.enabled,
      defaultDictionary: settings.defaultDictionary,
      autoLookup: settings.autoLookup,
      showPinyin: settings.showPinyin,
      showDefinition: settings.showDefinition
    };
    return result;
  }

  /**
   * 更新字典设置
   */
  async updateDictionarySettings(settings: DictionarySettings): Promise<void> {
    this.dictionarySettings = this.cloneDictionarySettings(settings);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.DICTIONARY_SETTINGS, this.dictionarySettings);
    logger.info(TAG, '字典设置已更新');
  }

  // ==================== 搜索历史 ====================

  /**
   * 获取搜索历史
   */
  getSearchHistory(): string[] {
    return this.searchHistory.slice();
  }

  /**
   * 添加搜索历史
   */
  async addSearchHistory(keyword: string): Promise<void> {
    // 移除重复项
    this.searchHistory = this.searchHistory.filter(k => k !== keyword);
    // 添加到开头
    this.searchHistory.unshift(keyword);
    // 限制数量
    if (this.searchHistory.length > this.searchSettings.searchHistoryLimit) {
      this.searchHistory = this.searchHistory.slice(0, this.searchSettings.searchHistoryLimit);
    }
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_HISTORY, this.searchHistory);
  }

  /**
   * 清空搜索历史
   */
  async clearSearchHistory(): Promise<void> {
    this.searchHistory = [];
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_HISTORY, []);
  }

  /**
   * 删除单条搜索历史
   */
  async removeSearchHistory(keyword: string): Promise<void> {
    this.searchHistory = this.searchHistory.filter(k => k !== keyword);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.SEARCH_HISTORY, this.searchHistory);
  }

  // ==================== 历史浏览 ====================

  /**
   * 获取历史浏览记录
   */
  getBrowseHistory(): BrowseHistoryItem[] {
    return this.browseHistory.slice();
  }

  /**
   * 添加历史浏览记录（进入详情页时调用）
   */
  async addBrowseHistory(item: BrowseHistoryInput): Promise<void> {
    // 生成唯一标识
    const key = `${item.sourceId}_${item.bookUrl}`;
    
    // 移除重复项（同一书源同一书籍）
    this.browseHistory = this.browseHistory.filter(h => 
      `${h.sourceId}_${h.bookUrl}` !== key
    );
    
    // 添加到开头
    const newItem: BrowseHistoryItem = {
      sourceId: item.sourceId,
      bookUrl: item.bookUrl,
      bookName: item.bookName,
      author: item.author,
      coverUrl: item.coverUrl,
      sourceName: item.sourceName,
      browseTime: Date.now()
    };
    this.browseHistory.unshift(newItem);
    
    // 限制数量
    if (this.browseHistory.length > this.browseHistoryLimit) {
      this.browseHistory = this.browseHistory.slice(0, this.browseHistoryLimit);
    }
    
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.BROWSE_HISTORY, this.browseHistory);
    
    // 通知监听器
    this.notifyBrowseHistoryListeners();
  }

  /**
   * 删除单条历史浏览记录
   */
  async removeBrowseHistory(sourceId: string, bookUrl: string): Promise<void> {
    const key = `${sourceId}_${bookUrl}`;
    this.browseHistory = this.browseHistory.filter(h => 
      `${h.sourceId}_${h.bookUrl}` !== key
    );
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.BROWSE_HISTORY, this.browseHistory);
    
    // 通知监听器
    this.notifyBrowseHistoryListeners();
  }

  /**
   * 清空历史浏览记录
   */
  async clearBrowseHistory(): Promise<void> {
    this.browseHistory = [];
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.BROWSE_HISTORY, []);
    
    // 通知监听器
    this.notifyBrowseHistoryListeners();
  }

  /**
   * 添加历史浏览变化监听器
   */
  addBrowseHistoryListener(listener: () => void): void {
    this.browseHistoryListeners.push(listener);
  }

  /**
   * 移除历史浏览变化监听器
   */
  removeBrowseHistoryListener(listener: () => void): void {
    const index = this.browseHistoryListeners.indexOf(listener);
    if (index !== -1) {
      this.browseHistoryListeners.splice(index, 1);
    }
  }

  /**
   * 通知所有历史浏览变化监听器
   */
  private notifyBrowseHistoryListeners(): void {
    for (const listener of this.browseHistoryListeners) {
      try {
        listener();
      } catch (e) {
        logger.warn(TAG, `历史浏览监听器执行失败: ${String(e)}`);
      }
    }
  }

  // ==================== 字典规则 ====================

  /**
   * 获取字典规则列表
   */
  getDictRules(): DictRule[] {
    return this.dictRules.slice();
  }

  /**
   * 获取启用的字典规则列表
   */
  getEnabledDictRules(): DictRule[] {
    return this.dictRules.filter(r => r.enabled).sort((a, b) => a.sortNumber - b.sortNumber);
  }

  /**
   * 更新字典规则列表
   */
  async updateDictRules(rules: DictRule[]): Promise<void> {
    this.dictRules = rules.slice();
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.DICT_RULES, this.dictRules);
    logger.info(TAG, `字典规则已更新，共 ${rules.length} 条`);
  }

  /**
   * 添加字典规则
   */
  async addDictRule(rule: DictRule): Promise<void> {
    this.dictRules.push(rule);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.DICT_RULES, this.dictRules);
  }

  /**
   * 删除字典规则
   */
  async removeDictRule(name: string): Promise<void> {
    this.dictRules = this.dictRules.filter(r => r.name !== name);
    await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.DICT_RULES, this.dictRules);
  }

  /**
   * 切换字典规则启用状态
   */
  async toggleDictRule(name: string, enabled: boolean): Promise<void> {
    const rule = this.dictRules.find(r => r.name === name);
    if (rule) {
      rule.enabled = enabled;
      await this.settingsManager.setJSON(NOVEL_SETTING_KEYS.DICT_RULES, this.dictRules);
    }
  }
}

export function getNovelSettingsManager(): NovelSettingsManager {
  return NovelSettingsManager.getInstance();
}
