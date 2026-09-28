import {
  Action,
  ActionType,
  ExtractAction,
  ExtractField,
  NavigateAction,
  WaitAction,
  WaitCondition
} from '../WebView/MangaSourceTypes';
import {
  DomSelectionSnapshot,
  RuleFieldMapping,
  SourceEditorTaskType
} from './SourceEditorTypes';

export class SourceRuleGenerator {
  public buildDefaultMappings(selection: DomSelectionSnapshot): RuleFieldMapping[] {
    const mappings: RuleFieldMapping[] = [];
    const titleMapping: RuleFieldMapping = {
      fieldName: 'title',
      label: '标题',
      selector: selection.cssSelector,
      attribute: 'text',
      sampleValue: selection.text
    };
    mappings.push(titleMapping);

    if (selection.href.length > 0) {
      const urlMapping: RuleFieldMapping = {
        fieldName: 'url',
        label: '链接',
        selector: selection.cssSelector,
        attribute: 'href',
        sampleValue: selection.href
      };
      mappings.push(urlMapping);
    }

    if (selection.src.length > 0) {
      const coverMapping: RuleFieldMapping = {
        fieldName: 'cover',
        label: '封面/图片',
        selector: selection.cssSelector,
        attribute: 'src',
        sampleValue: selection.src
      };
      mappings.push(coverMapping);
    }
    return mappings;
  }

  public buildActions(taskType: SourceEditorTaskType, testUrl: string, selection: DomSelectionSnapshot, mappings: RuleFieldMapping[]): Action[] {
    const actions: Action[] = [];
    const navigateAction: NavigateAction = {
      type: ActionType.NAVIGATE,
      description: '打开测试页面',
      url: testUrl,
      waitFor: WaitCondition.LOAD,
      waitAfterLoad: 1200
    };
    actions.push(navigateAction);

    const waitAction: WaitAction = {
      type: ActionType.WAIT,
      description: '等待目标元素出现',
      condition: WaitCondition.ELEMENT,
      selector: selection.cssSelector,
      timeout: 8000
    };
    actions.push(waitAction);

    const fields: ExtractField[] = [];
    for (let i = 0; i < mappings.length; i++) {
      const mapping = mappings[i];
      const field: ExtractField = {
        field: mapping.fieldName,
        selector: mapping.selector,
        attribute: mapping.attribute
      };
      fields.push(field);
    }

    const extractAction: ExtractAction = {
      type: ActionType.EXTRACT,
      description: this.getExtractDescription(taskType),
      selector: selection.cssSelector,
      multiple: taskType === SourceEditorTaskType.SEARCH || taskType === SourceEditorTaskType.CHAPTERS || taskType === SourceEditorTaskType.PAGES,
      fields: fields
    };
    actions.push(extractAction);
    return actions;
  }

  public buildWorkflowJson(taskType: SourceEditorTaskType, testUrl: string, selection: DomSelectionSnapshot, mappings: RuleFieldMapping[]): string {
    const actions = this.buildActions(taskType, testUrl, selection, mappings);
    return JSON.stringify(actions, null, 2);
  }

  private getExtractDescription(taskType: SourceEditorTaskType): string {
    if (taskType === SourceEditorTaskType.SEARCH) {
      return '提取搜索结果';
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return '提取章节列表';
    }
    if (taskType === SourceEditorTaskType.PAGES) {
      return '提取页面图片';
    }
    return '提取详情字段';
  }
}
