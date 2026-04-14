export class NGFDataQueryResult {
  success: boolean;
  dataJson: string;

  constructor(success: boolean, dataJson: string) {
    this.success = success;
    this.dataJson = dataJson;
  }
}

export interface IDataFacade {
  query(entityName: string, queryJson: string): Promise<NGFDataQueryResult>;
  save(entityName: string, dataJson: string): Promise<boolean>;
  remove(entityName: string, id: string): Promise<boolean>;
}
