/**
 * 统一内容跟踪模块数据库结构。
 */

interface SubscriptionCreateTableSql {
  SUBSCRIPTION_RULE: string;
  SUBSCRIPTION_EXECUTION: string;
  SUBSCRIPTION_CHECKPOINT: string;
}

export const SUBSCRIPTION_CREATE_TABLE_SQL: SubscriptionCreateTableSql = {
  SUBSCRIPTION_RULE: `
    CREATE TABLE IF NOT EXISTS subscription_rule (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      enabled INTEGER DEFAULT 1,
      targetType TEXT NOT NULL,
      contentType TEXT NOT NULL,
      targetId TEXT NOT NULL,
      targetTitle TEXT DEFAULT '',
      sourceId TEXT DEFAULT '',
      sourceName TEXT DEFAULT '',
      providerType TEXT DEFAULT 'none',
      checkIntervalMin INTEGER DEFAULT 180,
      conditionsJson TEXT DEFAULT '[]',
      actionsJson TEXT DEFAULT '[]',
      lastCheckTime INTEGER DEFAULT 0,
      lastSuccessTime INTEGER DEFAULT 0,
      lastError TEXT DEFAULT '',
      lastTriggeredScene TEXT DEFAULT '',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  SUBSCRIPTION_EXECUTION: `
    CREATE TABLE IF NOT EXISTS subscription_execution (
      id TEXT PRIMARY KEY,
      ruleId TEXT NOT NULL,
      status TEXT NOT NULL,
      triggerScene TEXT DEFAULT '',
      targetId TEXT NOT NULL,
      targetTitle TEXT DEFAULT '',
      contentType TEXT NOT NULL,
      checkedAt INTEGER NOT NULL,
      localCount INTEGER DEFAULT 0,
      remoteCount INTEGER DEFAULT 0,
      deltaCount INTEGER DEFAULT 0,
      downloadedCount INTEGER DEFAULT 0,
      message TEXT DEFAULT '',
      actionSummary TEXT DEFAULT '',
      createTime INTEGER NOT NULL
    )
  `,

  SUBSCRIPTION_CHECKPOINT: `
    CREATE TABLE IF NOT EXISTS subscription_checkpoint (
      ruleId TEXT NOT NULL,
      targetId TEXT NOT NULL,
      contentId TEXT NOT NULL,
      contentType TEXT NOT NULL,
      remoteFingerprint TEXT DEFAULT '',
      remoteCount INTEGER DEFAULT 0,
      localCount INTEGER DEFAULT 0,
      latestItemTitle TEXT DEFAULT '',
      lastSeenTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      PRIMARY KEY (ruleId, targetId, contentId)
    )
  `
};

export const SUBSCRIPTION_CREATE_INDEX_SQL: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_subscription_rule_enabled ON subscription_rule(enabled)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_rule_target ON subscription_rule(targetType, contentType, targetId)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_rule_provider ON subscription_rule(providerType)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_execution_rule ON subscription_execution(ruleId, checkedAt DESC)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_execution_status ON subscription_execution(status)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_checkpoint_rule ON subscription_checkpoint(ruleId)',
  'CREATE INDEX IF NOT EXISTS idx_subscription_checkpoint_target ON subscription_checkpoint(targetId, contentId)'
];
