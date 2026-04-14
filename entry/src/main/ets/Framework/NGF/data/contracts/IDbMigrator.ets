export interface IDbMigrator {
  currentVersion(): number;
  targetVersion(): number;
  migrate(): Promise<boolean>;
  rollback(toVersion: number): Promise<boolean>;
}
