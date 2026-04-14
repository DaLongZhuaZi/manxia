export interface IOhosContextBridge {
  bindUIContext(contextName: string): void;
  clearUIContext(): void;
  isUIContextReady(): boolean;
  getHostContextName(): string;
}
