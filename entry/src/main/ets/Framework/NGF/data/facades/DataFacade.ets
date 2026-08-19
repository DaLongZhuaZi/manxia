import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from '../../../Managers/SettingsManager';
import { IDataFacade, NGFDataQueryResult } from '../contracts/IDataFacade';
import { ngfSettingsStoreFacade } from './SettingsStoreFacade';

const TAG = 'NGFDataFacade';
const SETTINGS_ENTITY_NAME = 'settings';

class NGFDataEntityEnvelope {
  id: string;
  payloadJson: string;

  constructor(id: string, payloadJson: string) {
    this.id = id;
    this.payloadJson = payloadJson;
  }
}

class NGFDataEntityCollection {
  items: Array<NGFDataEntityEnvelope> = [];
}

class NGFDataQueryEnvelope {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

class NGFSettingsQueryEnvelope {
  key: string;
  valueType: string;
  defaultString: string;
  defaultNumber: number;
  defaultBoolean: boolean;

  constructor(key: string, valueType: string, defaultString: string, defaultNumber: number, defaultBoolean: boolean) {
    this.key = key;
    this.valueType = valueType;
    this.defaultString = defaultString;
    this.defaultNumber = defaultNumber;
    this.defaultBoolean = defaultBoolean;
  }
}

class NGFSettingsWriteEnvelope {
  key: string;
  valueType: string;
  stringValue: string;
  numberValue: number;
  booleanValue: boolean;

  constructor(key: string, valueType: string, stringValue: string, numberValue: number, booleanValue: boolean) {
    this.key = key;
    this.valueType = valueType;
    this.stringValue = stringValue;
    this.numberValue = numberValue;
    this.booleanValue = booleanValue;
  }
}

class NGFSettingsResponseEnvelope {
  key: string;
  valueType: string;
  stringValue: string;
  numberValue: number;
  booleanValue: boolean;

  constructor(key: string, valueType: string, stringValue: string, numberValue: number, booleanValue: boolean) {
    this.key = key;
    this.valueType = valueType;
    this.stringValue = stringValue;
    this.numberValue = numberValue;
    this.booleanValue = booleanValue;
  }
}

export class DataFacade implements IDataFacade {
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly entityStores: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();

  async query(entityName: string, queryJson: string): Promise<NGFDataQueryResult> {
    const normalizedEntity = this.normalizeEntityName(entityName);
    if (this.isSettingsEntity(normalizedEntity)) {
      const settingsQuery = this.parseSettingsQueryEnvelope(queryJson);
      if (settingsQuery.key.length <= 0) {
        return new NGFDataQueryResult(false, '');
      }

      const settingsResponse = this.querySettings(settingsQuery);
      return new NGFDataQueryResult(true, JSON.stringify(settingsResponse));
    }

    const queryEnvelope = this.parseQueryEnvelope(queryJson);
    const entityStore = this.ensureEntityStore(normalizedEntity);
    if (queryEnvelope.id.length > 0) {
      const payloadJson = entityStore.get(queryEnvelope.id);
      if (!payloadJson) {
        return new NGFDataQueryResult(false, '');
      }
      const response = new NGFDataEntityEnvelope(queryEnvelope.id, payloadJson);
      return new NGFDataQueryResult(true, JSON.stringify(response));
    }

    return new NGFDataQueryResult(true, this.serializeEntityCollection(entityStore));
  }

  async save(entityName: string, dataJson: string): Promise<boolean> {
    const normalizedEntity = this.normalizeEntityName(entityName);
    if (this.isSettingsEntity(normalizedEntity)) {
      const settingsWrite = this.parseSettingsWriteEnvelope(dataJson);
      if (settingsWrite.key.length <= 0) {
        return false;
      }
      this.writeSettings(settingsWrite);
      return true;
    }

    const envelope = this.parseEntityEnvelope(dataJson);
    const id = envelope.id.length > 0 ? envelope.id : this.generateEntityId(normalizedEntity);
    const payloadJson = envelope.payloadJson.length > 0 ? envelope.payloadJson : dataJson;
    const entityStore = this.ensureEntityStore(normalizedEntity);
    entityStore.set(id, payloadJson);
    return true;
  }

  async remove(entityName: string, id: string): Promise<boolean> {
    const normalizedEntity = this.normalizeEntityName(entityName);
    const normalizedId = id.trim();
    if (normalizedId.length <= 0) {
      return false;
    }

    if (this.isSettingsEntity(normalizedEntity)) {
      try {
        await this.settingsManager.deleteSetting(normalizedId);
        return true;
      } catch {
        logger.warn(TAG, `删除设置失败: key=${normalizedId}`);
        return false;
      }
    }

    const entityStore = this.entityStores.get(normalizedEntity);
    if (!entityStore) {
      return false;
    }
    return entityStore.delete(normalizedId);
  }

  private querySettings(query: NGFSettingsQueryEnvelope): NGFSettingsResponseEnvelope {
    const valueType = query.valueType.toLowerCase();
    if (valueType === 'number') {
      const numberValue = ngfSettingsStoreFacade.getNumber(query.key, query.defaultNumber);
      return new NGFSettingsResponseEnvelope(query.key, 'number', `${numberValue}`, numberValue, false);
    }

    if (valueType === 'boolean') {
      const booleanValue = ngfSettingsStoreFacade.getBoolean(query.key, query.defaultBoolean);
      return new NGFSettingsResponseEnvelope(
        query.key,
        'boolean',
        booleanValue ? 'true' : 'false',
        booleanValue ? 1 : 0,
        booleanValue
      );
    }

    const stringValue = ngfSettingsStoreFacade.getString(query.key, query.defaultString);
    return new NGFSettingsResponseEnvelope(query.key, 'string', stringValue, 0, false);
  }

  private writeSettings(writeEnvelope: NGFSettingsWriteEnvelope): void {
    const valueType = writeEnvelope.valueType.toLowerCase();
    if (valueType === 'number') {
      ngfSettingsStoreFacade.setNumber(writeEnvelope.key, writeEnvelope.numberValue);
      return;
    }

    if (valueType === 'boolean') {
      ngfSettingsStoreFacade.setBoolean(writeEnvelope.key, writeEnvelope.booleanValue);
      return;
    }

    ngfSettingsStoreFacade.setString(writeEnvelope.key, writeEnvelope.stringValue);
  }

  private normalizeEntityName(entityName: string): string {
    const normalized = entityName.trim().toLowerCase();
    if (normalized.length <= 0) {
      return 'default';
    }
    return normalized;
  }

  private isSettingsEntity(entityName: string): boolean {
    return entityName === SETTINGS_ENTITY_NAME;
  }

  private ensureEntityStore(entityName: string): Map<string, string> {
    const existingStore = this.entityStores.get(entityName);
    if (existingStore) {
      return existingStore;
    }

    const createdStore = new Map<string, string>();
    this.entityStores.set(entityName, createdStore);
    return createdStore;
  }

  private generateEntityId(entityName: string): string {
    return `${entityName}_${Date.now()}`;
  }

  private parseQueryEnvelope(queryJson: string): NGFDataQueryEnvelope {
    if (queryJson.trim().length <= 0) {
      return new NGFDataQueryEnvelope('');
    }

    try {
      const parsed = SafeUtils.parseObj(queryJson) as Partial<NGFDataQueryEnvelope>;
      const id = parsed.id && typeof parsed.id === 'string' ? parsed.id : '';
      return new NGFDataQueryEnvelope(id);
    } catch {
      return new NGFDataQueryEnvelope('');
    }
  }

  private parseEntityEnvelope(dataJson: string): NGFDataEntityEnvelope {
    if (dataJson.trim().length <= 0) {
      return new NGFDataEntityEnvelope('', '');
    }

    try {
      const parsed = SafeUtils.parseObj(dataJson) as Partial<NGFDataEntityEnvelope>;
      const id = parsed.id && typeof parsed.id === 'string' ? parsed.id : '';
      const payloadJson = parsed.payloadJson && typeof parsed.payloadJson === 'string'
        ? parsed.payloadJson
        : dataJson;
      return new NGFDataEntityEnvelope(id, payloadJson);
    } catch {
      return new NGFDataEntityEnvelope('', dataJson);
    }
  }

  private parseSettingsQueryEnvelope(queryJson: string): NGFSettingsQueryEnvelope {
    if (queryJson.trim().length <= 0) {
      return new NGFSettingsQueryEnvelope('', 'string', '', 0, false);
    }

    try {
      const parsed = SafeUtils.parseObj(queryJson) as Partial<NGFSettingsQueryEnvelope>;
      const key = parsed.key && typeof parsed.key === 'string' ? parsed.key : '';
      const valueType = parsed.valueType && typeof parsed.valueType === 'string' ? parsed.valueType : 'string';
      const defaultString = parsed.defaultString && typeof parsed.defaultString === 'string'
        ? parsed.defaultString
        : '';
      const defaultNumber = parsed.defaultNumber && typeof parsed.defaultNumber === 'number'
        ? parsed.defaultNumber
        : 0;
      const defaultBoolean = parsed.defaultBoolean && typeof parsed.defaultBoolean === 'boolean'
        ? parsed.defaultBoolean
        : false;
      return new NGFSettingsQueryEnvelope(key, valueType, defaultString, defaultNumber, defaultBoolean);
    } catch {
      return new NGFSettingsQueryEnvelope('', 'string', '', 0, false);
    }
  }

  private parseSettingsWriteEnvelope(dataJson: string): NGFSettingsWriteEnvelope {
    if (dataJson.trim().length <= 0) {
      return new NGFSettingsWriteEnvelope('', 'string', '', 0, false);
    }

    try {
      const parsed = SafeUtils.parseObj(dataJson) as Partial<NGFSettingsWriteEnvelope>;
      const key = parsed.key && typeof parsed.key === 'string' ? parsed.key : '';
      const valueType = parsed.valueType && typeof parsed.valueType === 'string' ? parsed.valueType : 'string';
      const stringValue = parsed.stringValue && typeof parsed.stringValue === 'string' ? parsed.stringValue : '';
      const numberValue = parsed.numberValue && typeof parsed.numberValue === 'number' ? parsed.numberValue : 0;
      const booleanValue = parsed.booleanValue && typeof parsed.booleanValue === 'boolean'
        ? parsed.booleanValue
        : false;
      return new NGFSettingsWriteEnvelope(key, valueType, stringValue, numberValue, booleanValue);
    } catch {
      return new NGFSettingsWriteEnvelope('', 'string', '', 0, false);
    }
  }

  private serializeEntityCollection(store: Map<string, string>): string {
    const collection = new NGFDataEntityCollection();
    store.forEach((payloadJson: string, id: string) => {
      collection.items.push(new NGFDataEntityEnvelope(id, payloadJson));
    });
    return JSON.stringify(collection);
  }
}

export const ngfDataFacade = new DataFacade();
