// 文件路径: entry/src/main/ets/pages/ScraperTestPage.ets
/**
 * 刮削测试页面
 * 用于测试和调试刮削管理器功能
 */

import { logger } from '../Utils/Logger';
import {
  ScraperManager,
  ScraperSource,
  ScraperContentType,
  ScrapedMetadata,
  ScraperSearchResult,
  MultiSourceSearchResult
} from '../Framework/Scraper/index';

const TAG = 'ScraperTestPage';

/**
 * 日志条目
 */
interface LogEntry {
  time: string;
  level: 'info' | 'warn' | 'error' | 'success';
  message: string;
}

/**
 * 搜索模式
 */
enum SearchMode {
  SINGLE = 'single',
  MULTI = 'multi'
}

@Component
export struct ScraperTestPage {
  @State pathStack: NavPathStack = new NavPathStack();
  
  // 搜索状态
  @State searchKeyword: string = '';
  @State selectedSource: ScraperSource = ScraperSource.BANGUMI;
  @State selectedContentType: ScraperContentType = ScraperContentType.MANGA;
  @State searchMode: SearchMode = SearchMode.SINGLE;
  
  // 结果状态
  @State isLoading: boolean = false;
  @State searchResults: ScrapedMetadata[] = [];
  @State selectedResult: ScrapedMetadata | null = null;
  @State totalCount: number = 0;
  
  // 日志状态
  @State logs: LogEntry[] = [];
  @State showLogs: boolean = true;
  
  // Token配置
  @State bangumiToken: string = '';
  @State anilistToken: string = '';
  @State showTokenConfig: boolean = false;
  
  // 刮削管理器
  private scraperManager: ScraperManager = ScraperManager.getInstance();

  aboutToAppear(): void {
    this.addLog('info', '刮削测试页面已加载');
    this.addLog('info', `已启用的刮削源: ${this.scraperManager.getEnabledSources().join(', ')}`);
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部搜索区域
        this.buildSearchArea()
        
        // 主内容区域
        Row() {
          // 左侧：结果列表
          Column() {
            this.buildResultsList()
          }
          .width('50%')
          .height('100%')
          
          // 右侧：详情和日志
          Column() {
            if (this.selectedResult) {
              this.buildDetailView()
            } else {
              this.buildLogView()
            }
          }
          .width('50%')
          .height('100%')
          .backgroundColor('#F5F5F5')
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .title('刮削测试')
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  @Builder
  buildSearchArea() {
    Column({ space: 12 }) {
      // 搜索输入行
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入搜索关键词...', text: this.searchKeyword })
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.performSearch();
          })
        
        Button('搜索')
          .height(40)
          .width(80)
          .backgroundColor('#2196F3')
          .onClick(() => {
            this.performSearch();
          })
          .enabled(!this.isLoading && this.searchKeyword.length > 0)
        
        Button(this.showTokenConfig ? '隐藏配置' : 'Token配置')
          .height(40)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor('#757575')
          .onClick(() => {
            this.showTokenConfig = !this.showTokenConfig;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 选项行
      Row({ space: 16 }) {
        // 搜索模式
        Row({ space: 8 }) {
          Text('模式:')
            .fontSize(14)
            .fontColor('#666666')
          
          this.buildModeButton('单源', SearchMode.SINGLE)
          this.buildModeButton('多源', SearchMode.MULTI)
        }
        
        // 刮削源选择（单源模式）
        if (this.searchMode === SearchMode.SINGLE) {
          Row({ space: 8 }) {
            Text('源:')
              .fontSize(14)
              .fontColor('#666666')
            
            this.buildSourceButton('Bangumi', ScraperSource.BANGUMI)
            this.buildSourceButton('AniList', ScraperSource.ANILIST)
            this.buildSourceButton('BookOf', ScraperSource.BOOKOF_MOE)
            this.buildSourceButton('Google', ScraperSource.GOOGLE_BOOKS)
          }
        }
        
        // 内容类型
        Row({ space: 8 }) {
          Text('类型:')
            .fontSize(14)
            .fontColor('#666666')
          
          this.buildTypeButton('漫画', ScraperContentType.MANGA)
          this.buildTypeButton('动画', ScraperContentType.ANIME)
          this.buildTypeButton('书籍', ScraperContentType.BOOK)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // Token配置区域
      if (this.showTokenConfig) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('Bangumi Token:')
              .fontSize(12)
              .width(100)
            TextInput({ placeholder: 'Access Token', text: this.bangumiToken })
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .onChange((value: string) => {
                this.bangumiToken = value;
              })
            Button('应用')
              .height(32)
              .fontSize(12)
              .onClick(() => {
                if (this.bangumiToken) {
                  this.scraperManager.setBangumiToken(this.bangumiToken);
                  this.addLog('success', 'Bangumi Token 已设置');
                }
              })
          }
          
          Row({ space: 8 }) {
            Text('AniList Token:')
              .fontSize(12)
              .width(100)
            TextInput({ placeholder: 'Access Token', text: this.anilistToken })
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .onChange((value: string) => {
                this.anilistToken = value;
              })
            Button('应用')
              .height(32)
              .fontSize(12)
              .onClick(() => {
                if (this.anilistToken) {
                  this.scraperManager.setAniListToken(this.anilistToken);
                  this.addLog('success', 'AniList Token 已设置');
                }
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#EEEEEE')
      }

      // 加载指示器
      if (this.isLoading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#2196F3')
          Text('正在搜索...')
            .fontSize(14)
            .fontColor('#2196F3')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(8)
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 1 }, color: '#E0E0E0' })
  }

  @Builder
  buildModeButton(label: string, mode: SearchMode) {
    Text(label)
      .fontSize(12)
      .fontColor(this.searchMode === mode ? '#FFFFFF' : '#666666')
      .backgroundColor(this.searchMode === mode ? '#2196F3' : '#E0E0E0')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .onClick(() => {
        this.searchMode = mode;
      })
  }

  @Builder
  buildSourceButton(label: string, source: ScraperSource) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selectedSource === source ? '#FFFFFF' : '#666666')
      .backgroundColor(this.selectedSource === source ? '#4CAF50' : '#E0E0E0')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .onClick(() => {
        this.selectedSource = source;
      })
  }

  @Builder
  buildTypeButton(label: string, type: ScraperContentType) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selectedContentType === type ? '#FFFFFF' : '#666666')
      .backgroundColor(this.selectedContentType === type ? '#FF9800' : '#E0E0E0')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .onClick(() => {
        this.selectedContentType = type;
      })
  }

  @Builder
  buildResultsList() {
    Column() {
      // 标题栏
      Row() {
        Text(`搜索结果 (${this.searchResults.length}${this.totalCount > 0 ? '/' + this.totalCount : ''})`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        
        Blank()
        
        if (this.searchResults.length > 0) {
          Text('清空')
            .fontSize(12)
            .fontColor('#F44336')
            .onClick(() => {
              this.searchResults = [];
              this.selectedResult = null;
              this.totalCount = 0;
              this.addLog('info', '已清空搜索结果');
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#FAFAFA')

      // 结果列表
      if (this.searchResults.length === 0) {
        Column() {
          Text('暂无搜索结果')
            .fontSize(14)
            .fontColor('#999999')
          Text('请输入关键词进行搜索')
            .fontSize(12)
            .fontColor('#BBBBBB')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.searchResults, (item: ScrapedMetadata, index: number) => {
            ListItem() {
              this.buildResultItem(item, index)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: '#EEEEEE' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  buildResultItem(item: ScrapedMetadata, index: number) {
    Row({ space: 12 }) {
      // 封面
      if (item.coverUrl) {
        Image(item.coverUrl)
          .width(50)
          .height(70)
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
          .backgroundColor('#EEEEEE')
      } else {
        Column() {
          Text('无封面')
            .fontSize(10)
            .fontColor('#999999')
        }
        .width(50)
        .height(70)
        .backgroundColor('#EEEEEE')
        .borderRadius(4)
        .justifyContent(FlexAlign.Center)
      }

      // 信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (item.author) {
          Text(`作者: ${item.author}`)
            .fontSize(12)
            .fontColor('#666666')
            .maxLines(1)
        }
        
        Row({ space: 8 }) {
          // 来源标签
          Text(this.getSourceLabel(item.source))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor(this.getSourceColor(item.source))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
          
          // 评分
          if (item.score) {
            Text(`⭐ ${item.score.toFixed(1)}`)
              .fontSize(11)
              .fontColor('#FF9800')
          }
          
          // 状态
          if (item.status && item.status !== 'unknown') {
            Text(this.getStatusLabel(item.status))
              .fontSize(10)
              .fontColor('#4CAF50')
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedResult?.id === item.id ? '#E3F2FD' : '#FFFFFF')
    .onClick(() => {
      this.selectedResult = item;
      this.addLog('info', `选中: ${item.title} (${item.source})`);
    })
  }

  @Builder
  buildDetailView() {
    Column() {
      // 标题栏
      Row() {
        Text('详情信息')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        
        Blank()
        
        Text('查看日志')
          .fontSize(12)
          .fontColor('#2196F3')
          .onClick(() => {
            this.selectedResult = null;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#EEEEEE')

      // 详情内容
      Scroll() {
        Column({ space: 12 }) {
          // 封面和基本信息
          Row({ space: 16 }) {
            if (this.selectedResult?.coverUrl) {
              Image(this.selectedResult.coverUrl)
                .width(100)
                .height(140)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
            }
            
            Column({ space: 6 }) {
              Text(this.selectedResult?.title || '')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
              
              if (this.selectedResult?.titleNative) {
                Text(this.selectedResult.titleNative)
                  .fontSize(12)
                  .fontColor('#666666')
              }
              
              if (this.selectedResult?.author) {
                Text(`作者: ${this.selectedResult.author}`)
                  .fontSize(12)
                  .fontColor('#666666')
              }
              
              if (this.selectedResult?.score) {
                Text(`评分: ${this.selectedResult.score.toFixed(1)} / ${this.selectedResult.scoreMax || 10}`)
                  .fontSize(12)
                  .fontColor('#FF9800')
              }
              
              Text(`来源: ${this.getSourceLabel(this.selectedResult?.source || ScraperSource.BANGUMI)}`)
                .fontSize(12)
                .fontColor('#2196F3')
              
              Text(`ID: ${this.selectedResult?.externalId || ''}`)
                .fontSize(10)
                .fontColor('#999999')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)

          // 描述
          if (this.selectedResult?.description) {
            Column({ space: 4 }) {
              Text('简介')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
              Text(this.selectedResult.description)
                .fontSize(12)
                .fontColor('#666666')
                .maxLines(10)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .alignItems(HorizontalAlign.Start)
          }

          // 标签
          if (this.selectedResult?.genres && this.selectedResult.genres.length > 0) {
            Column({ space: 4 }) {
              Text('分类')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.selectedResult.genres, (genre: string) => {
                  Text(genre)
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#9C27B0')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(12)
                    .margin({ right: 6, bottom: 6 })
                })
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .alignItems(HorizontalAlign.Start)
          }

          // 原始数据
          Column({ space: 4 }) {
            Text('原始数据 (JSON)')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
            
            Scroll() {
              Text(JSON.stringify(this.selectedResult?.rawData || {}, null, 2))
                .fontSize(10)
                .fontColor('#333333')
                .fontFamily('monospace')
            }
            .height(200)
            .width('100%')
            .backgroundColor('#F5F5F5')
            .borderRadius(4)
            .padding(8)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildLogView() {
    Column() {
      // 标题栏
      Row() {
        Text(`日志 (${this.logs.length})`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        
        Blank()
        
        Text('清空')
          .fontSize(12)
          .fontColor('#F44336')
          .onClick(() => {
            this.logs = [];
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#EEEEEE')

      // 日志列表
      List() {
        ForEach(this.logs, (log: LogEntry, index: number) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(log.time)
                .fontSize(10)
                .fontColor('#999999')
                .width(60)
              
              Text(this.getLogIcon(log.level))
                .fontSize(12)
              
              Text(log.message)
                .fontSize(11)
                .fontColor(this.getLogColor(log.level))
                .layoutWeight(1)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#FAFAFA')
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 业务方法 ====================

  private async performSearch(): Promise<void> {
    if (!this.searchKeyword.trim()) {
      this.addLog('warn', '请输入搜索关键词');
      return;
    }

    this.isLoading = true;
    this.searchResults = [];
    this.selectedResult = null;
    this.totalCount = 0;

    const startTime = Date.now();
    this.addLog('info', `开始搜索: "${this.searchKeyword}" (模式: ${this.searchMode}, 类型: ${this.selectedContentType})`);

    try {
      if (this.searchMode === SearchMode.SINGLE) {
        // 单源搜索
        this.addLog('info', `使用刮削源: ${this.selectedSource}`);
        const result = await this.scraperManager.searchWithSource(
          this.selectedSource,
          this.searchKeyword,
          this.selectedContentType
        );

        if (result.success) {
          this.searchResults = result.results;
          this.totalCount = result.totalCount || result.results.length;
          this.addLog('success', `搜索成功: 找到 ${result.results.length} 条结果`);
        } else {
          this.addLog('error', `搜索失败: ${result.errorMessage}`);
        }
      } else {
        // 多源搜索
        this.addLog('info', `使用多源并行搜索...`);
        const result = await this.scraperManager.searchMultipleSources(
          this.searchKeyword,
          this.selectedContentType
        );

        // 记录每个源的结果
        result.results.forEach((sourceResult, source) => {
          if (sourceResult.success) {
            this.addLog('success', `${source}: 找到 ${sourceResult.results.length} 条结果`);
          } else {
            this.addLog('error', `${source}: ${sourceResult.errorMessage}`);
          }
        });

        this.searchResults = result.mergedResults;
        this.totalCount = result.mergedResults.length;
        this.addLog('info', `合并去重后: ${result.mergedResults.length} 条结果`);
      }

      const elapsed = Date.now() - startTime;
      this.addLog('info', `搜索完成，耗时: ${elapsed}ms`);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addLog('error', `搜索异常: ${errorMsg}`);
    } finally {
      this.isLoading = false;
    }
  }

  private addLog(level: 'info' | 'warn' | 'error' | 'success', message: string): void {
    const now = new Date();
    const time = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`;
    
    this.logs = [{
      time: time,
      level: level,
      message: message
    }, ...this.logs.slice(0, 99)]; // 保留最近100条

    // 同时输出到系统日志
    switch (level) {
      case 'error':
        logger.error(TAG, message);
        break;
      case 'warn':
        logger.warn(TAG, message);
        break;
      default:
        logger.info(TAG, message);
    }
  }

  private getSourceLabel(source: ScraperSource): string {
    switch (source) {
      case ScraperSource.BANGUMI:
        return 'Bangumi';
      case ScraperSource.ANILIST:
        return 'AniList';
      case ScraperSource.BOOKOF_MOE:
        return 'BookOf.Moe';
      case ScraperSource.GOOGLE_BOOKS:
        return 'Google Books';
      default:
        return source;
    }
  }

  private getSourceColor(source: ScraperSource): string {
    switch (source) {
      case ScraperSource.BANGUMI:
        return '#F09199';
      case ScraperSource.ANILIST:
        return '#02A9FF';
      case ScraperSource.BOOKOF_MOE:
        return '#8BC34A';
      case ScraperSource.GOOGLE_BOOKS:
        return '#4285F4';
      default:
        return '#757575';
    }
  }

  private getStatusLabel(status: string): string {
    switch (status) {
      case 'completed':
        return '已完结';
      case 'ongoing':
        return '连载中';
      case 'upcoming':
        return '即将发布';
      case 'hiatus':
        return '休刊中';
      case 'cancelled':
        return '已取消';
      default:
        return status;
    }
  }

  private getLogIcon(level: string): string {
    switch (level) {
      case 'success':
        return '✅';
      case 'error':
        return '❌';
      case 'warn':
        return '⚠️';
      default:
        return 'ℹ️';
    }
  }

  private getLogColor(level: string): string {
    switch (level) {
      case 'success':
        return '#4CAF50';
      case 'error':
        return '#F44336';
      case 'warn':
        return '#FF9800';
      default:
        return '#333333';
    }
  }
}
