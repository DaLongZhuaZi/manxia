// 文件路径：entry/src/main/ets/pages/SpecialEventPage.ets
// 设计规范：完全沉浸式Stack双层布局，使用UIContext.animateTo入场动画
// 数据来源：entry/src/main/resources/rawfile/update/update_notes.json

import { logger } from '../Utils/Logger';
import { UIContext, curves } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';


const TAG = 'SpecialEventPage';

class UpdateNoteItemModel {
  id: string;
  title: string;
  description: string;
  category: string;
  isImportant: boolean;
  constructor(id: string, title: string, description: string, category: string, isImportant: boolean) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.category = category;
    this.isImportant = isImportant;
  }
}

class UpdateNotesPayloadModel {
  version: string;
  releaseDate: string;
  items: UpdateNoteItemModel[];
  constructor(version: string, releaseDate: string, items: UpdateNoteItemModel[]) {
    this.version = version;
    this.releaseDate = releaseDate;
    this.items = items;
  }
}

@Component
struct UpdateNoticePage {
  // 沉浸式状态属性（强制要求）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 页面入场动画透明度
  @State opacity: number = 0;

  // 数据状态
  private uiContext: UIContext | undefined = undefined;
  private payload: UpdateNotesPayloadModel | undefined = undefined;
  @State updateItems: UpdateNoteItemModel[] = ([] as UpdateNoteItemModel[]);

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
      return;
    }

    this.loadUpdateNotes();

    const animateOptions: { duration: number; curve: Curve } = { duration: 300, curve: Curve.EaseOut } as { duration: number; curve: Curve };
    this.uiContext.animateTo(animateOptions, () => {
      this.opacity = 1;
    });
  }

  private loadUpdateNotes(): void {
    const hostContext = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!hostContext) {
      logger.error(TAG, '无法获取UIAbilityContext');
      return;
    }

    try {
      const rm = hostContext.resourceManager;
      rm.getRawFile('update/update_notes.json').then((buf: ArrayBuffer) => {
        const decoder = new util.TextDecoder('utf-8');
        const jsonStr: string = decoder.decodeToString(buf);

        // 将JSON映射到具名模型，确保名义类型
        const parsed: UpdateNotesPayloadModel = JSON.parse(jsonStr) as UpdateNotesPayloadModel;

        // 基本字段校验（显式属性检查）
        const hasVersion: boolean = Object.keys(parsed as Object).includes('version');
        const hasReleaseDate: boolean = Object.keys(parsed as Object).includes('releaseDate');
        const hasItems: boolean = Object.keys(parsed as Object).includes('items');
        if (!hasVersion || !hasReleaseDate || !hasItems) {
          logger.warn(TAG, '更新说明JSON缺失必要字段');
          return;
        }

        const convertedItems: UpdateNoteItemModel[] = ([] as UpdateNoteItemModel[]);
        const itemsLen: number = parsed.items.length;
        for (let i: number = 0; i < itemsLen; i++) {
          const it: UpdateNoteItemModel = parsed.items[i] as UpdateNoteItemModel;
          const item = new UpdateNoteItemModel(it.id, it.title, it.description, it.category, it.isImportant);
          convertedItems.push(item);
        }

        this.payload = new UpdateNotesPayloadModel(parsed.version, parsed.releaseDate, convertedItems);
        this.updateItems = convertedItems;
        logger.info(TAG, '更新说明JSON加载成功');
      }).catch((e: Object) => {
        logger.error(TAG, '读取rawfile失败');
      });
    } catch (ex: Object) {
      logger.error(TAG, '加载更新说明异常');
    }
  }

  private navigateToMainMenu(): void {
    const router = this.getUIContext()?.getRouter();
    if (router) {
      // 路由到主菜单（根据项目现有路由规范）
      router.replaceUrl({ url: 'pages/MainMenuPage' });
      logger.lifecycle(TAG, '用户已查看更新说明，返回主菜单');
    } else {
      logger.warn(TAG, '获取Router失败'); 
    }
  }

  build() {
    // 完全沉浸式Stack双层布局
    Stack() {
      // 背景层：扩展到系统栏
      Column() {
        // 可在此放置背景图片或渐变，保持沉浸
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 内容层：通过padding预留系统安全区域
      Column() {
        // 标题与版本信息
        Column() {
          Text('更新说明')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)

          if (this.payload !== undefined) {
            Text('版本：' + (this.payload as UpdateNotesPayloadModel).version)
              .fontSize(16)
            Text('发布日期：' + (this.payload as UpdateNotesPayloadModel).releaseDate)
              .fontSize(14)
          }
        }
        .margin({ top: 12 })

        // 列表内容（使用LazyForEach提高性能）
        Scroll() {
          LazyForEach(this.updateItems, (item: UpdateNoteItemModel) => {
            Column() {
              Text(item.title)
                .fontSize(18)
                .fontWeight(item.isImportant ? FontWeight.Bold : FontWeight.Normal)
              Text(item.description)
                .fontSize(14)
                .margin({ top: 4, bottom: 8 })
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          }, (item: UpdateNoteItemModel) => item.id)
        }
        .margin({ top: 12, bottom: 12 })

        // 底部操作按钮（使用AnimatedButton规范）
        AnimatedButton({
          text: '我知道了',
          onClick: () => {
            this.navigateToMainMenu();
          }
        })
        .margin({ top: 12, bottom: 24 })
      }
      .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight, left: 12, right: 12 })
      .opacity(this.opacity)
    }
  }
}