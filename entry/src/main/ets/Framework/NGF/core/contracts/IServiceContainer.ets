export interface IServiceContainer {
  registerSingleton(token: string, implementationName: string): void;
  resolve(token: string): string;
  contains(token: string): boolean;
}
