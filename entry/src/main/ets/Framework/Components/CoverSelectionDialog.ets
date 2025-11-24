// 文件路径：entry/src/main/ets/Framework/Components/CoverSelectionDialog.ets
/**
 * 封面选择弹窗组件（通用）
 * 提供显示前三张图片并选择其中一张作为封面的UI内容，使用 UniversalDialogManager 展示。
 */
import { UIContext } from '@kit.ArkUI';
import { UniversalDialogManager, ButtonStyle, DialogButton, UniversalDialogOptions } from './UniversalDialog';
import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';
import { logger } from '../../Utils/Logger';

const TAG: string = 'CoverSelectionDialog';

export interface CoverSelectionData {
  title: string;
  candidatePaths: string[]; // 至少1个，最多3个
}

export interface CoverSelectionResult {
  confirmed: boolean;
  selectedPath?: string;
}

/**
 * 构建封面选择弹窗的自定义内容
 */
@Builder
export function buildCoverSelectionContent(data: CoverSelectionData, themeState: ThemeAwareState, selectedIndex: number, onSelect: (index: number) => void): void {
  Column({ space: 12 }) {
    Text('选择封面图片')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', themeState.currentTheme))

    if (data.title && data.title.length > 0) {
      Text(`漫画：${data.title}`)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', themeState.currentTheme))
    }

    // 图片候选网格
    Row({ space: 12 }) {
      ForEach(data.candidatePaths, (path: string, index: number) => {
        Column({ space: 6 }) {
          // 缩略图展示
          Image(path)
            .width(96)
            .height(128)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .borderColor(index === selectedIndex ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('text_muted', themeState.currentTheme))
            .borderWidth(index === selectedIndex ? 2 : 1)
            .onClick(() => onSelect(index))

          // 单选指示
          Radio({ group: 'cover_select', value: `${index}` })
            .checked(index === selectedIndex)
            .onChange((checked: boolean) => {
              if (checked) { onSelect(index); }
            })
          Text(`第${index + 1}张`)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', themeState.currentTheme))
        }
      }, (p: string) => p)
    }
    .width('100%')
  }
}

/**
 * 显示封面选择弹窗，返回用户选择结果
 */
export async function showCoverSelectionDialog(uiContext: UIContext | undefined, themeState: ThemeAwareState, data: CoverSelectionData): Promise<CoverSelectionResult> {
  // 保护性检查
  const candidatesCount: number = data.candidatePaths.length;
  if (candidatesCount === 0) {
    logger.warn(TAG, '候选图片为空，跳过弹窗');
    return { confirmed: false } as CoverSelectionResult;
  }

  return await new Promise<CoverSelectionResult>((resolve: (value: CoverSelectionResult) => void) => {
    let selectedIndex: number = 0;
    const dialogOptions: UniversalDialogOptions = {
      title: '选择漫画封面',
      customBuilder: () => {
        buildCoverSelectionContent(data, themeState, selectedIndex, (index: number): void => {
          if (index >= 0 && index < candidatesCount) {
            selectedIndex = index;
          }
        });
      },
      buttons: [
        {
          text: '取消',
          style: ButtonStyle.SECONDARY,
          action: () => {
            resolve({ confirmed: false } as CoverSelectionResult);
          }
        } as DialogButton,
        {
          text: '设为封面',
          style: ButtonStyle.PRIMARY,
          action: () => {
            const selectedPath: string = data.candidatePaths[selectedIndex];
            resolve({ confirmed: true, selectedPath: selectedPath } as CoverSelectionResult);
          }
        } as DialogButton
      ],
      themeState: themeState
    } as UniversalDialogOptions;

    // 始终使用自定义对话框以展示候选缩略图（系统 ActionMenu 无法渲染自定义内容）
    setTimeout((): void => {
      UniversalDialogManager.show(dialogOptions);
    }, 0);
  });
}

export { TAG };