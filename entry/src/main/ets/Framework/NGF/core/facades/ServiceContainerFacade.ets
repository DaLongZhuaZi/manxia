import { IServiceContainer } from '../contracts/IServiceContainer';

export class ServiceContainerFacade implements IServiceContainer {
  private registrations: Map<string, string> = new Map<string, string>();

  registerSingleton(token: string, implementationName: string): void {
    this.registrations.set(token, implementationName);
  }

  resolve(token: string): string {
    const implementationName = this.registrations.get(token);
    if (implementationName) {
      return implementationName;
    }
    return '';
  }

  contains(token: string): boolean {
    return this.registrations.has(token);
  }
}

export const ngfServiceContainerFacade = new ServiceContainerFacade();
