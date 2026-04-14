/**
 * 系统资源预览页面
 * 展示HarmonyOS系统图标和颜色资源
 * 支持按需加载和分类浏览
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { SYSTEM_SYMBOL_GROUPS, SYSTEM_SYMBOL_TOTAL_COUNT, SystemSymbolResourceGroup } from '../Framework/Resources/SystemSymbolCatalog';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

const TAG = 'SystemResourcePreviewPage';
const GROUP_BATCH_SIZE: number = 8;
const GRID_ITEM_BATCH_SIZE: number = 120;
const SEARCH_RESULT_BATCH_SIZE: number = 160;

/**
 * 资源分类
 */
enum ResourceCategory {
  SYMBOL = 'symbol',
  MEDIA = 'media',
  COLOR = 'color'
}

/**
 * 图标分组
 */
interface ThemeState {
  currentTheme: ThemeType;
}

// Media图标列表（按分组）- 完整列表
const MEDIA_GROUPS: SystemSymbolResourceGroup[] = [
  {
    name: '基础图标',
    items: [
      'ohos_app_icon', 'ohos_ic_back', 'ohos_ic_public_ok', 'ohos_ic_public_ok_filled',
      'ohos_ic_public_arrow_left', 'ohos_ic_public_arrow_right', 'ohos_ic_public_arrow_up',
      'ohos_ic_public_arrow_down', 'ohos_icon_mask_svg'
    ]
  },
  {
    name: '编辑操作',
    items: [
      'ohos_ic_public_cut', 'ohos_ic_public_copy', 'ohos_ic_public_paste',
      'ohos_ic_public_select_all', 'ohos_ic_public_share', 'ohos_ic_public_edit',
      'ohos_ic_public_remove', 'ohos_ic_public_remove_filled', 'ohos_ic_public_add',
      'ohos_ic_public_add_norm_filled', 'ohos_ic_public_minus'
    ]
  },
  {
    name: '搜索保存',
    items: [
      'ohos_ic_public_search_filled', 'ohos_save_button_filled', 'ohos_save_button_line',
      'ohos_ic_public_translate_c2e', 'save_button_picture'
    ]
  },
  {
    name: '关闭取消',
    items: [
      'ohos_ic_bottomsheet_close', 'ohos_ic_public_cancel', 'ohos_ic_public_cancel_filled',
      'ohos_ic_public_close', 'ohos_ic_public_fail', 'ohos_ic_public_input_cancel'
    ]
  },
  {
    name: '通讯信息',
    items: [
      'ohos_ic_public_clock', 'ohos_ic_public_email', 'ohos_ic_public_express',
      'ohos_ic_public_flight', 'ohos_ic_public_location', 'ohos_ic_public_phone',
      'ohos_ic_public_text', 'ohos_ic_public_web', 'ic_public_worldclock_filled'
    ]
  },
  {
    name: '设备图标',
    items: [
      'ohos_ic_public_device_matebook', 'ohos_ic_public_device_pad',
      'ohos_ic_public_device_smartscreen', 'ohos_ic_public_device_smartscreen_filled',
      'ohos_ic_public_device_watch', 'ohos_ic_public_device_phone',
      'ohos_ic_public_device_bluetooth_filled', 'ohos_ic_public_device_earphone_filled',
      'ohos_ic_public_device_earpiece_filled', 'ohos_ic_public_device_speaker_filled',
      'ohos_ic_public_device_sound_filled', 'ohos_ic_public_device_soundx_filled'
    ]
  },
  {
    name: '媒体控制',
    items: [
      'ohos_ic_public_pause', 'ohos_ic_public_play_last', 'ohos_ic_public_play_next',
      'ohos_ic_public_play', 'ohos_ic_public_restore', 'ohos_ic_public_sound_off',
      'ohos_ic_public_sound', 'ohos_ic_public_video_off', 'ohos_ic_public_video',
      'ohos_ic_public_voice_off', 'ohos_ic_public_voice', 'ohos_ic_public_hang_up',
      'safe_volume_notification_icon'
    ]
  },
  {
    name: '相册扫描',
    items: [
      'ohos_ic_public_albums', 'ohos_ic_public_scan', 'ohos_ic_public_camera',
      'ohos_ic_public_cast_stream', 'ohos_ic_public_cast_mirror', 'ohos_ic_eco_hop',
      'ohos_ic_public_more', 'ic_public_camera_beauty'
    ]
  },
  {
    name: '文件类型',
    items: [
      'ohos_ic_normal_white_grid_zip', 'ohos_ic_normal_white_grid_xml',
      'ohos_ic_normal_white_grid_xls', 'ohos_ic_normal_white_grid_wma',
      'ohos_ic_normal_white_grid_wav', 'ohos_ic_normal_white_grid_video',
      'ohos_ic_normal_white_grid_txt', 'ohos_ic_normal_white_grid_pdf',
      'ohos_ic_normal_white_grid_mp3', 'ohos_ic_normal_white_grid_image',
      'ohos_ic_normal_white_grid_html', 'ohos_ic_normal_white_grid_folder',
      'ohos_ic_normal_white_grid_flac', 'ohos_ic_normal_white_grid_doc',
      'ohos_ic_normal_white_grid_compress', 'ohos_ic_normal_white_grid_calendar',
      'ohos_ic_normal_white_grid_audio'
    ]
  },
  {
    name: '标题栏',
    items: [
      'ohos_ic_compnent_titlebar_back', 'ohos_ic_compnent_titlebar_back_filled',
      'ohos_ic_public_drawer_close', 'ohos_ic_public_drawer_close_filled',
      'ohos_ic_public_drawer_open', 'ohos_ic_public_drawer_open_filled'
    ]
  },
  {
    name: '用户认证',
    items: [
      'ohos_user_auth_icon_face', 'ohos_user_auth_icon_fingerprint',
      'app_lock_picture', 'ic_time_limit_picture'
    ]
  },
  {
    name: '窗口菜单',
    items: [
      'ohos_ic_window_menu_screen_t', 'ohos_ic_window_menu_screen_b',
      'ohos_ic_window_menu_waterfall', 'ohos_ic_window_menu_moveto_t',
      'ohos_ic_window_menu_moveto_b', 'ohos_ic_window_menu_back'
    ]
  },
  {
    name: '克隆应用',
    items: [
      'clone_app_badge_1', 'clone_app_badge_2', 'clone_app_badge_3',
      'clone_app_badge_4', 'clone_app_badge_5'
    ]
  },
  {
    name: '拖拽图标',
    items: [
      'Copy_Drag', 'Copy_One_Drag', 'Forbid_Drag', 'Forbid_One_Drag', 'Move_Drag'
    ]
  },
  {
    name: 'AI写作',
    items: [
      'ic_public_ai_write'
    ]
  }
];

const SYMBOL_GROUPS: SystemSymbolResourceGroup[] = SYSTEM_SYMBOL_GROUPS;

// 系统颜色列表
const SYSTEM_COLORS: string[] = [
  'ohos_id_color_foreground', 'ohos_id_color_foreground_dark',
  'ohos_id_color_background', 'ohos_id_color_background_dark',
  'ohos_id_color_emphasize', 'ohos_id_color_emphasize_dark',
  'ohos_id_color_warning', 'ohos_id_color_alert',
  'ohos_id_color_primary', 'ohos_id_color_secondary', 'ohos_id_color_tertiary',
  'ohos_id_color_text_primary', 'ohos_id_color_text_secondary',
  'ohos_id_color_component_normal', 'ohos_id_color_component_activated',
  'ohos_id_color_list_separator', 'ohos_id_color_click_effect', 'ohos_id_color_hover'
];

@ComponentV2
export struct SystemResourcePreviewPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  private themeManager: ThemeManager = ThemeManager.getInstance();
  pathStack: NavPathStack = new NavPathStack();
  
  @Local private selectedCategory: ResourceCategory = ResourceCategory.SYMBOL;
  @Local private selectedGroupIndex: number = 0;
  @Local private searchText: string = '';
  @Local private visibleGroupCount: number = GROUP_BATCH_SIZE;
  @Local private visibleGridItemCount: number = GRID_ITEM_BATCH_SIZE;
  @Local private visibleSearchResultCount: number = SEARCH_RESULT_BATCH_SIZE;
  @Local private isSearching: boolean = false; // 是否正在搜索
  @Local private searchResults: string[] = []; // 搜索结果
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  
  aboutToAppear(): void {
    logger.info(TAG, '系统资源预览页面初始化');
    this.resetSegmentedLoading();
    // 使用getActualTheme获取实际显示的主题
    this.themeManager.getActualTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
  }
  
  aboutToDisappear(): void {
    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
  }
  
  private resetSegmentedLoading(): void {
    this.visibleGroupCount = GROUP_BATCH_SIZE;
    this.visibleGridItemCount = GRID_ITEM_BATCH_SIZE;
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
  }

  private resetGridItemLoading(): void {
    this.visibleGridItemCount = GRID_ITEM_BATCH_SIZE;
  }

  private getVisibleItems<T>(items: T[], limit: number): T[] {
    if (limit >= items.length) {
      return items;
    }

    const visibleItems: T[] = [];
    const maxCount = Math.min(items.length, limit);
    for (let index = 0; index < maxCount; index++) {
      visibleItems.push(items[index]);
    }
    return visibleItems;
  }

  private getVisibleGroupCount(): number {
    return Math.min(this.getCurrentGroups().length, this.visibleGroupCount);
  }

  private hasMoreGroups(): boolean {
    return this.getVisibleGroupCount() < this.getCurrentGroups().length;
  }

  /**
   * 加载更多分组（分段）
   */
  private loadMoreGroups(): void {
    const groups = this.getCurrentGroups();
    if (this.visibleGroupCount < groups.length) {
      this.visibleGroupCount = Math.min(groups.length, this.visibleGroupCount + GROUP_BATCH_SIZE);
    }
  }

  private getVisibleGroups(): SystemSymbolResourceGroup[] {
    return this.getVisibleItems<SystemSymbolResourceGroup>(this.getCurrentGroups(), this.visibleGroupCount);
  }
  
  /**
   * 获取当前分类的分组列表
   */
  private getCurrentGroups(): SystemSymbolResourceGroup[] {
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      return SYMBOL_GROUPS;
    } else if (this.selectedCategory === ResourceCategory.MEDIA) {
      return MEDIA_GROUPS;
    }
    return [];
  }
  
  /**
   * 获取当前Symbol分组的项目
   */
  private getSymbolItems(): string[] {
    if (this.selectedGroupIndex < SYMBOL_GROUPS.length) {
      return SYMBOL_GROUPS[this.selectedGroupIndex].items;
    }
    return [];
  }
  
  /**
   * 获取当前Media分组的项目
   */
  private getMediaItems(): string[] {
    if (this.selectedGroupIndex < MEDIA_GROUPS.length) {
      return MEDIA_GROUPS[this.selectedGroupIndex].items;
    }
    return [];
  }

  private getCurrentGridItems(): string[] {
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      return this.getSymbolItems();
    }
    if (this.selectedCategory === ResourceCategory.MEDIA) {
      return this.getMediaItems();
    }
    return [];
  }

  private getVisibleCurrentGridItems(): string[] {
    return this.getVisibleItems<string>(this.getCurrentGridItems(), this.visibleGridItemCount);
  }

  private getCurrentGridItemCount(): number {
    return this.getCurrentGridItems().length;
  }

  private getVisibleCurrentGridItemCount(): number {
    return Math.min(this.getCurrentGridItemCount(), this.visibleGridItemCount);
  }

  private hasMoreCurrentGridItems(): boolean {
    return this.getVisibleCurrentGridItemCount() < this.getCurrentGridItemCount();
  }

  private loadMoreCurrentGridItems(): void {
    const totalCount = this.getCurrentGridItemCount();
    if (this.visibleGridItemCount < totalCount) {
      this.visibleGridItemCount = Math.min(totalCount, this.visibleGridItemCount + GRID_ITEM_BATCH_SIZE);
    }
  }

  private getVisibleSearchResults(): string[] {
    return this.getVisibleItems<string>(this.searchResults, this.visibleSearchResultCount);
  }

  private getVisibleSearchResultCount(): number {
    return Math.min(this.searchResults.length, this.visibleSearchResultCount);
  }

  private hasMoreSearchResults(): boolean {
    return this.getVisibleSearchResultCount() < this.searchResults.length;
  }

  private loadMoreSearchResults(): void {
    if (this.visibleSearchResultCount < this.searchResults.length) {
      this.visibleSearchResultCount = Math.min(
        this.searchResults.length,
        this.visibleSearchResultCount + SEARCH_RESULT_BATCH_SIZE
      );
    }
  }

  private getMediaResourceCount(): number {
    let total = 0;
    for (const group of MEDIA_GROUPS) {
      total += group.items.length;
    }
    return total;
  }

  private getCategoryLabel(category: ResourceCategory): string {
    if (category === ResourceCategory.SYMBOL) {
      return `Symbol ${SYSTEM_SYMBOL_TOTAL_COUNT}`;
    }
    if (category === ResourceCategory.MEDIA) {
      return `Media ${this.getMediaResourceCount()}`;
    }
    return `Color ${SYSTEM_COLORS.length}`;
  }


  private getSelectedGroupSummaryText(): string {
    const groups = this.getCurrentGroups();
    if (this.selectedGroupIndex >= 0 && this.selectedGroupIndex < groups.length) {
      const currentGroup = groups[this.selectedGroupIndex];
      return currentGroup.name + ' | ' + currentGroup.items.length.toString() + ' items';
    }
    return '';
  }
  
  /**
   * 执行搜索
   */
  private performSearch(): void {
    if (!this.searchText || this.searchText.trim() === '') {
      this.isSearching = false;
      this.searchResults = [];
      this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
      return;
    }
    
    this.isSearching = true;
    const keyword = this.searchText.toLowerCase().trim();
    const results: string[] = [];
    
    if (this.selectedCategory === ResourceCategory.SYMBOL) {
      // 搜索所有Symbol分组
      for (const group of SYMBOL_GROUPS) {
        for (const item of group.items) {
          if (item.toLowerCase().includes(keyword)) {
            results.push(item);
          }
        }
      }
    } else if (this.selectedCategory === ResourceCategory.MEDIA) {
      // 搜索所有Media分组
      for (const group of MEDIA_GROUPS) {
        for (const item of group.items) {
          if (item.toLowerCase().includes(keyword)) {
            results.push(item);
          }
        }
      }
    } else {
      // 搜索颜色
      for (const color of SYSTEM_COLORS) {
        if (color.toLowerCase().includes(keyword)) {
          results.push(color);
        }
      }
    }
    
    this.searchResults = results;
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
    logger.info(TAG, `搜索 "${keyword}" 找到 ${results.length} 个结果`);
  }
  
  /**
   * 清除搜索
   */
  private clearSearch(): void {
    this.searchText = '';
    this.isSearching = false;
    this.searchResults = [];
    this.visibleSearchResultCount = SEARCH_RESULT_BATCH_SIZE;
  }
  
  /**
   * 复制资源名称到剪贴板
   */
  private copyToClipboard(resourceType: string, resourceName: string): void {
    const fullName = `$r('sys.${resourceType}.${resourceName}')`;
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, fullName);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      promptAction.showToast({ message: `已复制: ${fullName}` });
      logger.info(TAG, `复制到剪贴板: ${fullName}`);
    }).catch((err: Error) => {
      logger.error(TAG, `复制失败: ${err.message}`);
      promptAction.showToast({ message: '复制失败' });
    });
  }
  
  /**
   * 构建搜索框
   */
  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      Search({ value: this.searchText, placeholder: '搜索资源名称...' })
        .searchButton('搜索')
        .width('100%')
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .placeholderFont({ size: 14 })
        .textFont({ size: 14 })
        .onChange((value: string) => {
          this.searchText = value;
          if (value === '') {
            this.clearSearch();
          }
        })
        .onSubmit((value: string) => {
          this.searchText = value;
          this.performSearch();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
  
  /**
   * 构建搜索结果网格（Symbol/Media）
   */
  @Builder
  buildSearchResultGrid() {
    Column({ space: 8 }) {
      // 搜索结果统计
      Row() {
        Text(`找到 ${this.searchResults.length} 个结果，已加载 ${this.getVisibleSearchResultCount()}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        Button('清除')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearSearch();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      
      if (this.searchResults.length === 0) {
        // 无结果提示
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
          Text('未找到匹配的资源')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 搜索结果网格
        Scroll() {
          Grid() {
            ForEach(this.getVisibleSearchResults(), (itemName: string) => {
              GridItem() {
                Column({ space: 6 }) {
                  if (this.selectedCategory === ResourceCategory.SYMBOL) {
                    SymbolGlyph($r(`sys.symbol.${itemName}`))
                      .fontSize(26)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  } else if (this.selectedCategory === ResourceCategory.MEDIA) {
                    Image($r(`sys.media.${itemName}`))
                      .width(26)
                      .height(26)
                      .objectFit(ImageFit.Contain)
                  } else {
                    // 颜色预览
                    Row()
                      .width(26)
                      .height(26)
                      .borderRadius(4)
                      .backgroundColor($r(`sys.color.${itemName}`))
                  }
                  
                  Text(itemName)
                    .fontSize(9)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .padding(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .borderRadius(8)
                .onClick(() => {
                  const resourceType = this.selectedCategory === ResourceCategory.SYMBOL ? 'symbol' : 
                    (this.selectedCategory === ResourceCategory.MEDIA ? 'media' : 'color');
                  this.copyToClipboard(resourceType, itemName);
                })
              }
              .aspectRatio(1)
            })
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.hasMoreSearchResults()) {
          Button(`加载更多结果 (${this.getVisibleSearchResultCount()}/${this.searchResults.length})`)
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .height(36)
            .borderRadius(18)
            .margin({ left: 16, right: 16, bottom: 8 })
            .onClick(() => {
              this.loadMoreSearchResults();
            })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
    ))
  }
  
  /**
   * 构建分类选择器
   */
  @Builder
  buildCategorySelector() {
    Row({ space: 12 }) {
      Button(this.getCategoryLabel(ResourceCategory.SYMBOL))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.SYMBOL 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.SYMBOL;
          this.selectedGroupIndex = 0;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
      
      Button(this.getCategoryLabel(ResourceCategory.MEDIA))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.MEDIA 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.MEDIA;
          this.selectedGroupIndex = 0;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
      
      Button(this.getCategoryLabel(ResourceCategory.COLOR))
        .fontSize(14)
        .fontColor(this.selectedCategory === ResourceCategory.COLOR 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectedCategory = ResourceCategory.COLOR;
          this.isSearching = false;
          this.searchResults = [];
          this.resetSegmentedLoading();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Start)
  }
  
  /**
   * 构建分组选择器
   */
  @Builder
  buildGroupSelector() {
    Column({ space: 8 }) {

      Row() {
        Text(this.getSelectedGroupSummaryText())
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Blank()

        Text(this.getVisibleGroupCount().toString() + '/' + this.getCurrentGroups().length.toString() + ' groups')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.getVisibleGroups(), (group: SystemSymbolResourceGroup, index: number) => {
            Button(`${group.name} ${group.items.length}`)
              .fontSize(13)
              .fontColor(this.selectedGroupIndex === index 
                ? Color.White
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(this.selectedGroupIndex === index 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(16)
              .height(32)
              .onClick(() => {
                this.selectedGroupIndex = index;
                this.resetGridItemLoading();
              })
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(40)

      if (this.hasMoreGroups()) {
        Button(`加载更多分组 (${this.getVisibleGroupCount()}/${this.getCurrentGroups().length})`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .height(32)
          .borderRadius(16)
          .margin({ left: 16, right: 16, top: 2 })
          .onClick(() => {
            this.loadMoreGroups();
          })
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
  
  /**
   * 构建Symbol图标网格
   */
  @Builder
  buildSymbolGrid() {
    Column({ space: 8 }) {
      Scroll() {
        Grid() {
          ForEach(this.getVisibleCurrentGridItems(), (itemName: string) => {
            GridItem() {
              Column({ space: 6 }) {
                SymbolGlyph($r(`sys.symbol.${itemName}`))
                  .fontSize(26)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                
                Text(itemName)
                  .fontSize(9)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .padding(6)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard('symbol', itemName);
              })
            }
            .aspectRatio(1)
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(10)
        .columnsGap(10)
        .padding(12)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.hasMoreCurrentGridItems()) {
        Button(`加载更多图标 (${this.getVisibleCurrentGridItemCount()}/${this.getCurrentGridItemCount()})`)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .height(36)
          .borderRadius(18)
          .margin({ left: 16, right: 16, bottom: 8 })
          .onClick(() => {
            this.loadMoreCurrentGridItems();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  /**
   * 构建Media图标网格
   */
  @Builder
  buildMediaGrid() {
    Column({ space: 8 }) {
      Scroll() {
        Grid() {
          ForEach(this.getVisibleCurrentGridItems(), (itemName: string) => {
            GridItem() {
              Column({ space: 6 }) {
                Image($r(`sys.media.${itemName}`))
                  .width(28)
                  .height(28)
                  .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                
                Text(itemName)
                  .fontSize(9)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .padding(6)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard('media', itemName);
              })
            }
            .aspectRatio(1)
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(10)
        .columnsGap(10)
        .padding(12)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.hasMoreCurrentGridItems()) {
        Button(`加载更多图标 (${this.getVisibleCurrentGridItemCount()}/${this.getCurrentGridItemCount()})`)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .height(36)
          .borderRadius(18)
          .margin({ left: 16, right: 16, bottom: 8 })
          .onClick(() => {
            this.loadMoreCurrentGridItems();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  /**
   * 构建颜色列表
   */
  @Builder
  buildColorList() {
    List() {
      ForEach(SYSTEM_COLORS, (colorName: string) => {
        ListItem() {
          Row({ space: 12 }) {
            // 颜色预览
            Column()
              .width(48)
              .height(48)
              .backgroundColor($r(`sys.color.${colorName}`))
              .borderRadius(8)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
            
            // 颜色名称
            Column({ space: 4 }) {
              Text(colorName)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Text(`$r('sys.color.${colorName}')`)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.copyToClipboard('color', colorName);
          })
        }
        .margin({ bottom: 8 })
      })
    }
    .padding(16)
    .width('100%')
    .layoutWeight(1)
  }
  
  build() {
    NavDestination() {
      Column() {
        // 搜索框
        this.buildSearchBar()
        
        // 分类选择器
        this.buildCategorySelector()
        
        // 根据是否在搜索状态显示不同内容
        if (this.isSearching) {
          // 搜索结果
          this.buildSearchResultGrid()
        } else {
          // 正常浏览模式
          if (this.selectedCategory === ResourceCategory.SYMBOL) {
            // 分组选择器
            this.buildGroupSelector()
            // Symbol图标网格
            this.buildSymbolGrid()
          } else if (this.selectedCategory === ResourceCategory.MEDIA) {
            // 分组选择器
            this.buildGroupSelector()
            // Media图标网格
            this.buildMediaGrid()
          } else {
            // 颜色列表
            this.buildColorList()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .title('系统资源预览')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onBackPressed(() => {
      if (this.isSearching) {
        this.clearSearch();
        return true;
      }
      this.pathStack.pop();
      return true;
    })
  }
}
