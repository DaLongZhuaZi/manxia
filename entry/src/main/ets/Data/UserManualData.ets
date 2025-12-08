// 文件路径: entry/src/main/ets/Data/UserManualData.ets
/**
 * 使用手册数据
 * 用于首次运行时添加到书库的电子书
 */

import { EBook, EBookFormat, EBookStatus, EBookChapter, EBookMetadata, EBookReadingProgress, DEFAULT_EBOOK_READING_SETTINGS } from '../Models/EBookModels';

const USER_MANUAL_ID = 'user_manual_001';

/**
 * 使用手册章节内容
 */
const CHAPTER_CONTENTS: string[] = [
  // 第1章：欢迎使用漫匣
  `欢迎使用漫匣

漫匣是一款基于 HarmonyOS Next 开发的现代化漫画阅读应用。本应用致力于为您提供流畅、舒适的阅读体验。

主要特性：
• 支持本地漫画和电子书导入
• 多种阅读模式（单页、双页、连续滚动、条漫）
• 智能书库管理
• 阅读进度自动保存
• 深色/浅色主题切换
• 响应式布局，适配手机、平板、折叠屏

感谢您选择漫匣，希望您能享受阅读的乐趣！`,

  // 第2章：快速开始
  `快速开始

一、导入内容

1. 导入本地漫画
   • 进入"书库"页面
   • 点击右上角的"+"按钮
   • 选择"导入漫画"
   • 从文件管理器选择漫画文件夹或压缩包（支持 ZIP、CBZ、CBR 格式）

2. 导入电子书
   • 进入"书库"页面
   • 点击右上角的"+"按钮
   • 选择"导入电子书"
   • 支持 TXT、EPUB、PDF 等格式

二、开始阅读

1. 在"首页"或"书库"中找到您想阅读的内容
2. 点击封面进入详情页
3. 点击"开始阅读"或选择具体章节
4. 阅读过程中，点击屏幕中央可呼出菜单`,

  // 第3章：阅读器操作
  `阅读器操作指南

一、基本操作

• 翻页：左右滑动或点击屏幕左右两侧
• 呼出菜单：点击屏幕中央区域
• 返回：点击左上角返回按钮或使用系统返回手势

二、阅读菜单功能

顶部菜单：
• 返回按钮：退出阅读器
• 章节标题：显示当前章节
• 更多选项：书签、设置等

底部菜单：
• 进度条：快速跳转到指定位置
• 章节列表：切换章节
• 阅读设置：调整亮度、模式等

三、阅读模式

漫画阅读器支持以下模式：
• 单页模式：每次显示一页
• 双页模式：同时显示两页（适合横屏）
• 连续滚动：上下滚动阅读
• 条漫模式：专为条漫优化的垂直滚动

四、手势操作

• 双指缩放：放大/缩小页面
• 长按：添加书签或复制文本
• 音量键：可设置为翻页快捷键`,

  // 第4章：书库管理
  `书库管理

一、筛选与排序

书库页面顶部提供筛选功能：
• 全部：显示所有内容
• 未读：显示未开始阅读的内容
• 阅读中：显示正在阅读的内容

二、视图切换

点击右上角的视图按钮可切换：
• 网格视图：以封面网格形式展示
• 列表视图：以列表形式展示详细信息

三、内容类型切换

书库支持两种内容类型：
• 漫画：导入的漫画内容
• 电子书：导入的 TXT、EPUB 等电子书

点击顶部标签可切换显示类型。

四、多选操作

长按任意项目进入多选模式：
• 选择多个项目
• 批量删除
• 点击空白处退出多选模式

五、删除内容

单个删除：
1. 进入内容详情页
2. 点击"删除"按钮

批量删除：
1. 长按进入多选模式
2. 选择要删除的项目
3. 点击删除按钮`,

  // 第5章：设置说明
  `设置说明

一、进入设置

点击底部导航栏的"设置"标签进入设置页面。

二、全局设置

在设置页面点击"全局设置"可配置：

阅读设置：
• 默认阅读模式
• 默认阅读方向
• 翻页动画效果
• 屏幕常亮
• 音量键翻页

电子书设置：
• 默认字体大小
• 默认行高
• 默认页边距
• 阅读主题

下载设置：
• 仅 Wi-Fi 下载
• 最大并发下载数

三、主题设置

点击"主题设置"可配置：
• 浅色/深色主题
• 跟随系统主题

四、关于

点击"关于"可查看：
• 应用版本信息
• 开发者信息
• 用户协议
• 隐私政策
• 开源许可`,

  // 第6章：常见问题
  `常见问题

Q1：导入的漫画/电子书在哪里？
A：导入的内容会显示在"书库"页面。如果没有看到，请尝试下拉刷新。

Q2：如何更换封面？
A：进入内容详情页，点击封面图片，可以选择新的封面图片。

Q3：阅读进度丢失了怎么办？
A：漫匣会自动保存阅读进度。如果进度丢失，可能是应用数据被清除。建议定期备份数据。

Q4：如何备份数据？
A：进入"设置" > "数据管理"，可以导出和导入应用数据。

Q5：应用闪退怎么办？
A：
1. 尝试重启应用
2. 检查是否有足够的存储空间
3. 尝试清除应用缓存
4. 如问题持续，请通过"问题反馈"联系我们

Q6：如何反馈问题或建议？
A：进入"设置" > "关于" > "问题反馈"，可以加入 QQ 群与开发者交流。

Q7：支持哪些文件格式？
A：
• 漫画：ZIP、CBZ、CBR、文件夹
• 电子书：TXT、EPUB、PDF、MOBI

Q8：如何调整阅读器亮度？
A：在阅读器中点击屏幕中央呼出菜单，底部有亮度调节滑块。`
];

/**
 * 创建使用手册章节列表
 */
function createUserManualChapters(): EBookChapter[] {
  const chapterTitles: string[] = [
    '欢迎使用漫匣',
    '快速开始',
    '阅读器操作指南',
    '书库管理',
    '设置说明',
    '常见问题'
  ];

  const chapters: EBookChapter[] = [];
  let position = 0;

  for (let i = 0; i < chapterTitles.length; i++) {
    const content = CHAPTER_CONTENTS[i];
    const chapter: EBookChapter = {
      id: `${USER_MANUAL_ID}_chapter_${i + 1}`,
      bookId: USER_MANUAL_ID,
      chapterNumber: i + 1,
      title: chapterTitles[i],
      content: content,
      startPosition: position,
      endPosition: position + content.length,
      wordCount: content.length,
      createTime: Date.now()
    };
    chapters.push(chapter);
    position += content.length;
  }

  return chapters;
}

/**
 * 创建使用手册元数据
 */
function createUserManualMetadata(): EBookMetadata {
  return {
    title: '漫匣使用手册',
    author: 'DaLongZhuaZi',
    publisher: '漫匣开发团队',
    publishDate: '2025',
    isbn: '',
    language: 'zh-CN',
    description: '漫匣应用的使用指南，介绍各项功能和操作方法。',
    coverImagePath: 'app.media.mangabook',
    tags: ['使用手册', '帮助', '教程'],
    rating: 5
  };
}

/**
 * 创建使用手册电子书对象
 */
export function createUserManualEBook(): EBook {
  const chapters = createUserManualChapters();
  const metadata = createUserManualMetadata();
  
  // 计算总字数
  let totalWordCount = 0;
  for (const chapter of chapters) {
    totalWordCount += chapter.wordCount;
  }

  const now = Date.now();

  return new EBook(
    USER_MANUAL_ID,
    EBookFormat.TXT,
    '', // 内置电子书，无文件路径
    0,  // 无文件大小
    metadata,
    chapters,
    EBookStatus.UNREAD,
    {
      bookId: USER_MANUAL_ID,
      currentChapterId: chapters[0].id,
      currentChapterIndex: 0,
      currentPosition: 0,
      domPos: '',
      progress: 0,
      lastReadTime: 0,
      totalReadingTime: 0
    },
    DEFAULT_EBOOK_READING_SETTINGS,
    now,
    now,
    true, // 默认收藏
    totalWordCount
  );
}

/**
 * 获取使用手册ID
 */
export function getUserManualId(): string {
  return USER_MANUAL_ID;
}
