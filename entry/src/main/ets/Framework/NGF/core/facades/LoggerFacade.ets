import { logger, LogLevel } from '../../../../Utils/Logger';
import { ILogger, NGFLogLevel } from '../contracts/ILogger';

export class LoggerFacade implements ILogger {
  private currentLevel: NGFLogLevel = NGFLogLevel.DEBUG;

  setLevel(level: NGFLogLevel): void {
    this.currentLevel = level;
    logger.setLevel(this.toLegacyLevel(level));
  }

  getLevel(): NGFLogLevel {
    return this.currentLevel;
  }

  debug(tag: string, message: string): void {
    logger.debug(tag, message);
  }

  info(tag: string, message: string): void {
    logger.info(tag, message);
  }

  warn(tag: string, message: string): void {
    logger.warn(tag, message);
  }

  error(tag: string, message: string): void {
    logger.error(tag, message);
  }

  lifecycle(tag: string, message: string): void {
    logger.lifecycle(tag, message);
  }

  stateChange(tag: string, fromState: string, toState: string, reason: string): void {
    logger.stateChange(tag, fromState, toState, reason);
  }

  private toLegacyLevel(level: NGFLogLevel): LogLevel {
    switch (level) {
      case NGFLogLevel.DEBUG:
        return LogLevel.DEBUG;
      case NGFLogLevel.INFO:
        return LogLevel.INFO;
      case NGFLogLevel.WARN:
        return LogLevel.WARN;
      case NGFLogLevel.ERROR:
        return LogLevel.ERROR;
      case NGFLogLevel.LIFECYCLE:
        return LogLevel.INFO;
      default:
        return LogLevel.DEBUG;
    }
  }
}

export const ngfLoggerFacade = new LoggerFacade();
