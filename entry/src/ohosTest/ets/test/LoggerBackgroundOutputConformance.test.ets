import { describe, expect, it } from '@ohos/hypium';
import { logger, LogLevel } from '../../../main/ets/Utils/Logger';
import { LogEntry, logCollector } from '../../../main/ets/Framework/Debug/LogCollector';

function findFixtureEntries(tag: string): LogEntry[] {
  const allEntries: LogEntry[] = logCollector.getAllLogs();
  const fixtureEntries: LogEntry[] = [];
  for (let i = 0; i < allEntries.length; i++) {
    if (allEntries[i].tag === tag) {
      fixtureEntries.push(allEntries[i]);
    }
  }
  return fixtureEntries;
}

export default function loggerBackgroundOutputConformanceTest() {
  describe('LoggerBackgroundOutputConformance', () => {
    it('keepsWarnEvidenceWhileBackgroundOutputIsPaused', 0, () => {
      const pauseToken: string = 'LoggerBackgroundOutputConformance:reader';
      const tag: string = 'LoggerEvidenceFixture';
      logCollector.clearLogs();
      logger.setLevel(LogLevel.DEBUG);
      logger.pauseBackgroundOutput(pauseToken);
      try {
        logger.warn(tag, 'ordinary-warning');
        logger.warnForEvidence(tag, 'evidence-warning');
      } finally {
        logger.resumeBackgroundOutput(pauseToken);
      }

      const entries: LogEntry[] = findFixtureEntries(tag);
      expect(entries.length).assertEqual(1);
      expect(entries[0].tag).assertEqual(tag);
      expect(entries[0].message).assertEqual('evidence-warning');
      expect(entries[0].level).assertEqual(LogLevel.WARN);
      expect(entries[0].level < LogLevel.ERROR).assertTrue();
      logCollector.clearLogs();
    });

    it('keepsWarnEvidenceWhenNormalOutputIsDisabled', 0, () => {
      const tag: string = 'LoggerEvidenceLevelFixture';
      const pauseToken: string = 'LoggerBackgroundOutputConformance:disabled';
      logCollector.clearLogs();
      logger.setLevel(LogLevel.FATAL);
      logger.setHilogOutputLevel(LogLevel.OFF);
      logger.pauseBackgroundOutput(pauseToken);
      try {
        logger.warn(tag, 'ordinary-warning-must-remain-filtered');
        logger.warnForEvidence(tag, 'evidence-warning-must-remain-visible');
      } finally {
        logger.resumeBackgroundOutput(pauseToken);
        logger.setLevel(LogLevel.DEBUG);
        logger.setHilogOutputLevel(LogLevel.DEBUG);
      }

      const entries: LogEntry[] = findFixtureEntries(tag);
      expect(entries.length).assertEqual(1);
      expect(entries[0].message).assertEqual('evidence-warning-must-remain-visible');
      expect(entries[0].level).assertEqual(LogLevel.WARN);
      expect(entries[0].level < LogLevel.ERROR).assertTrue();
      logCollector.clearLogs();
    });
  });
}
