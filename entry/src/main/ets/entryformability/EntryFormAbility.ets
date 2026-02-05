/**
 * 阅读目标卡片 - FormExtensionAbility
 * 管理卡片的生命周期和数据更新
 */
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

const TAG = 'EntryFormAbility';
const DOMAIN = 0x0000;
const FORM_VISIBLE = 1;
const WIDGET_DATA_STORE = 'widget_reading_data';
const FORM_STORAGE = 'form_storage';

/**
 * 阅读目标数据接口
 */
interface ReadingGoalData {
  mangaGoalMinutes: number;
  mangaReadMinutes: number;
  ebookGoalMinutes: number;
  ebookReadMinutes: number;
  novelGoalMinutes: number;
  novelReadMinutes: number;
}

/**
 * 最近阅读项
 */
interface RecentReadItem {
  id: string;
  title: string;
  cover: string;
  type: string;
  progress: number;
  lastReadTime: number;
}

/**
 * 存储的完整数据
 */
interface WidgetData {
  goals: ReadingGoalData;
  recentReads: RecentReadItem[];
  lastUpdateTime: number;
}

/**
 * 卡片更新数据
 */
interface FormUpdateData {
  formId: string;
  dimension: number;
  mangaGoal: number;
  mangaRead: number;
  mangaProgress: number;
  ebookGoal: number;
  ebookRead: number;
  ebookProgress: number;
  novelGoal: number;
  novelRead: number;
  novelProgress: number;
  hasMangaGoal: boolean;
  hasEbookGoal: boolean;
  hasNovelGoal: boolean;
  hasAnyGoal: boolean;
  recentCount: number;
  recent1Title: string;
  recent1Cover: string;
  recent1Progress: number;
  recent1Type: string;
  recent2Title: string;
  recent2Cover: string;
  recent2Progress: number;
  recent2Type: string;
  recent3Title: string;
  recent3Cover: string;
  recent3Progress: number;
  recent3Type: string;
  recent4Title: string;
  recent4Cover: string;
  recent4Progress: number;
  recent4Type: string;
  recent5Title: string;
  recent5Cover: string;
  recent5Progress: number;
  recent5Type: string;
  recent6Title: string;
  recent6Cover: string;
  recent6Progress: number;
  recent6Type: string;
}

export default class EntryFormAbility extends FormExtensionAbility {
  
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm called');

    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY]?.toString() ?? '';
    // FormDimension枚举: 2=2x2, 3=2x4, 4=4x4
    const dimension = want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number ?? 2;

    hilog.info(DOMAIN, TAG, `Creating form: id=${formId}, dimension=${dimension}`);

    this.saveFormInfo(formId, dimension);
    
    // 异步更新真实数据
    this.updateFormData(formId);

    // 返回默认数据
    return formBindingData.createFormBindingData(this.getDefaultData(formId, dimension));
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, `onUpdateForm: ${formId}`);
    this.updateFormData(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, `onFormEvent: formId=${formId}, message=${message}`);
    
    try {
      const eventData = JSON.parse(message) as Record<string, Object>;
      if (eventData['action'] === 'refresh') {
        this.updateFormData(formId);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onFormEvent error: ${JSON.stringify(e)}`);
    }
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, `onRemoveForm: ${formId}`);
    this.removeFormInfo(formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, `onChangeFormVisibility: ${JSON.stringify(newStatus)}`);
    
    for (const formId of Object.keys(newStatus)) {
      if (newStatus[formId] === FORM_VISIBLE) {
        this.updateFormData(formId);
      }
    }
  }

  /**
   * 获取默认数据
   */
  private getDefaultData(formId: string, dimension: number): FormUpdateData {
    return {
      formId: formId,
      dimension: dimension,
      mangaGoal: 0,
      mangaRead: 0,
      mangaProgress: 0,
      ebookGoal: 0,
      ebookRead: 0,
      ebookProgress: 0,
      novelGoal: 0,
      novelRead: 0,
      novelProgress: 0,
      hasMangaGoal: false,
      hasEbookGoal: false,
      hasNovelGoal: false,
      hasAnyGoal: false,
      recentCount: 0,
      recent1Title: '',
      recent1Cover: '',
      recent1Progress: 0,
      recent1Type: '',
      recent2Title: '',
      recent2Cover: '',
      recent2Progress: 0,
      recent2Type: '',
      recent3Title: '',
      recent3Cover: '',
      recent3Progress: 0,
      recent3Type: '',
      recent4Title: '',
      recent4Cover: '',
      recent4Progress: 0,
      recent4Type: '',
      recent5Title: '',
      recent5Cover: '',
      recent5Progress: 0,
      recent5Type: '',
      recent6Title: '',
      recent6Cover: '',
      recent6Progress: 0,
      recent6Type: ''
    };
  }

  /**
   * 更新卡片数据
   */
  private async updateFormData(formId: string): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, FORM_STORAGE);
      // FormDimension枚举: 2=2x2, 3=2x4, 4=4x4
      const dimension = (await pref.get(`dimension_${formId}`, 2)) as number;
      
      const widgetPref = await preferences.getPreferences(this.context, WIDGET_DATA_STORE);
      const dataStr = (await widgetPref.get('widgetData', '')) as string;
      
      const updateData = this.buildFormData(formId, dimension, dataStr);
      const formData = formBindingData.createFormBindingData(updateData);
      
      await formProvider.updateForm(formId, formData);
      hilog.info(DOMAIN, TAG, `Form updated: ${formId}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `updateFormData error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 构建卡片数据
   */
  private buildFormData(formId: string, dimension: number, dataStr: string): FormUpdateData {
    let goals: ReadingGoalData = {
      mangaGoalMinutes: 0, mangaReadMinutes: 0,
      ebookGoalMinutes: 0, ebookReadMinutes: 0,
      novelGoalMinutes: 0, novelReadMinutes: 0
    };
    let recentReads: RecentReadItem[] = [];

    if (dataStr) {
      try {
        const data = JSON.parse(dataStr) as WidgetData;
        goals = data.goals || goals;
        recentReads = data.recentReads || [];
      } catch (e) {
        // ignore
      }
    }

    const mangaProgress = goals.mangaGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.mangaReadMinutes / goals.mangaGoalMinutes * 100)) 
      : 0;
    const ebookProgress = goals.ebookGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.ebookReadMinutes / goals.ebookGoalMinutes * 100)) 
      : 0;
    const novelProgress = goals.novelGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.novelReadMinutes / goals.novelGoalMinutes * 100)) 
      : 0;

    const result: FormUpdateData = {
      formId: formId,
      dimension: dimension,
      mangaGoal: goals.mangaGoalMinutes,
      mangaRead: goals.mangaReadMinutes,
      mangaProgress: mangaProgress,
      ebookGoal: goals.ebookGoalMinutes,
      ebookRead: goals.ebookReadMinutes,
      ebookProgress: ebookProgress,
      novelGoal: goals.novelGoalMinutes,
      novelRead: goals.novelReadMinutes,
      novelProgress: novelProgress,
      hasMangaGoal: goals.mangaGoalMinutes > 0,
      hasEbookGoal: goals.ebookGoalMinutes > 0,
      hasNovelGoal: goals.novelGoalMinutes > 0,
      hasAnyGoal: goals.mangaGoalMinutes > 0 || goals.ebookGoalMinutes > 0 || goals.novelGoalMinutes > 0,
      recentCount: recentReads.length,
      recent1Title: recentReads.length > 0 ? recentReads[0].title : '',
      recent1Cover: recentReads.length > 0 ? recentReads[0].cover : '',
      recent1Progress: recentReads.length > 0 ? recentReads[0].progress : 0,
      recent1Type: recentReads.length > 0 ? recentReads[0].type : '',
      recent2Title: recentReads.length > 1 ? recentReads[1].title : '',
      recent2Cover: recentReads.length > 1 ? recentReads[1].cover : '',
      recent2Progress: recentReads.length > 1 ? recentReads[1].progress : 0,
      recent2Type: recentReads.length > 1 ? recentReads[1].type : '',
      recent3Title: recentReads.length > 2 ? recentReads[2].title : '',
      recent3Cover: recentReads.length > 2 ? recentReads[2].cover : '',
      recent3Progress: recentReads.length > 2 ? recentReads[2].progress : 0,
      recent3Type: recentReads.length > 2 ? recentReads[2].type : '',
      recent4Title: recentReads.length > 3 ? recentReads[3].title : '',
      recent4Cover: recentReads.length > 3 ? recentReads[3].cover : '',
      recent4Progress: recentReads.length > 3 ? recentReads[3].progress : 0,
      recent4Type: recentReads.length > 3 ? recentReads[3].type : '',
      recent5Title: recentReads.length > 4 ? recentReads[4].title : '',
      recent5Cover: recentReads.length > 4 ? recentReads[4].cover : '',
      recent5Progress: recentReads.length > 4 ? recentReads[4].progress : 0,
      recent5Type: recentReads.length > 4 ? recentReads[4].type : '',
      recent6Title: recentReads.length > 5 ? recentReads[5].title : '',
      recent6Cover: recentReads.length > 5 ? recentReads[5].cover : '',
      recent6Progress: recentReads.length > 5 ? recentReads[5].progress : 0,
      recent6Type: recentReads.length > 5 ? recentReads[5].type : ''
    };

    return result;
  }

  /**
   * 保存卡片信息
   */
  private async saveFormInfo(formId: string, dimension: number): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, FORM_STORAGE);
      const formIdsStr = (await pref.get('formIds', '[]')) as string;
      const ids: string[] = JSON.parse(formIdsStr);

      if (!ids.includes(formId)) {
        ids.push(formId);
        await pref.put('formIds', JSON.stringify(ids));
      }
      
      await pref.put(`dimension_${formId}`, dimension);
      await pref.flush();
      
      hilog.info(DOMAIN, TAG, `Form saved: id=${formId}, dimension=${dimension}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `saveFormInfo error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 移除卡片信息
   */
  private async removeFormInfo(formId: string): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, FORM_STORAGE);
      const formIdsStr = (await pref.get('formIds', '[]')) as string;
      const ids: string[] = JSON.parse(formIdsStr);

      const index = ids.indexOf(formId);
      if (index > -1) {
        ids.splice(index, 1);
        await pref.put('formIds', JSON.stringify(ids));
        await pref.delete(`dimension_${formId}`);
        await pref.flush();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `removeFormInfo error: ${JSON.stringify(e)}`);
    }
  }
}
