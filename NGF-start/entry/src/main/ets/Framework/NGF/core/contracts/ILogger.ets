export enum NGFLogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error',
  LIFECYCLE = 'lifecycle'
}

export interface ILogger {
  setLevel(level: NGFLogLevel): void;
  getLevel(): NGFLogLevel;
  debug(tag: string, message: string): void;
  info(tag: string, message: string): void;
  warn(tag: string, message: string): void;
  error(tag: string, message: string): void;
  lifecycle(tag: string, message: string): void;
  stateChange(tag: string, fromState: string, toState: string, reason: string): void;
}

