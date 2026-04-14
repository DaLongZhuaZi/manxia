export interface ISettingsStore {
  getString(key: string, defaultValue: string): string;
  getNumber(key: string, defaultValue: number): number;
  getBoolean(key: string, defaultValue: boolean): boolean;
  setString(key: string, value: string): void;
  setNumber(key: string, value: number): void;
  setBoolean(key: string, value: boolean): void;
}
