/**
 * Database schema for RSS subscription module.
 * This module is independent from novel source tables.
 */

interface RssCreateTableSql {
  RSS_SOURCE: string;
  RSS_ITEM: string;
  RSS_READ_RECORD: string;
  RSS_STAR: string;
}

export const RSS_CREATE_TABLE_SQL: RssCreateTableSql = {
  RSS_SOURCE: `
    CREATE TABLE IF NOT EXISTS rss_subscription_source (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      url TEXT NOT NULL UNIQUE,
      sourceComment TEXT DEFAULT '',
      enabled INTEGER DEFAULT 1,
      autoUpdate INTEGER DEFAULT 1,
      updateIntervalMin INTEGER DEFAULT 180,
      variableComment TEXT DEFAULT '',
      jsLib TEXT DEFAULT '',
      enabledCookieJar INTEGER DEFAULT 1,
      concurrentRate TEXT DEFAULT '',
      header TEXT DEFAULT '',
      loginUrl TEXT DEFAULT '',
      loginUi TEXT DEFAULT '',
      loginCheckJs TEXT DEFAULT '',
      coverDecodeJs TEXT DEFAULT '',
      sortUrl TEXT DEFAULT '',
      singleUrl INTEGER DEFAULT 0,
      articleStyle INTEGER DEFAULT 0,
      ruleArticles TEXT DEFAULT '',
      ruleNextPage TEXT DEFAULT '',
      ruleTitle TEXT DEFAULT '',
      rulePubDate TEXT DEFAULT '',
      ruleDescription TEXT DEFAULT '',
      ruleImage TEXT DEFAULT '',
      ruleLink TEXT DEFAULT '',
      ruleContent TEXT DEFAULT '',
      contentWhitelist TEXT DEFAULT '',
      contentBlacklist TEXT DEFAULT '',
      shouldOverrideUrlLoading TEXT DEFAULT '',
      style TEXT DEFAULT '',
      enableJs INTEGER DEFAULT 1,
      loadWithBaseUrl INTEGER DEFAULT 1,
      injectJs TEXT DEFAULT '',
      lastUpdateTime INTEGER DEFAULT 0,
      customOrder INTEGER DEFAULT 0,
      etag TEXT DEFAULT '',
      lastModified TEXT DEFAULT '',
      lastCheckTime INTEGER DEFAULT 0,
      lastSuccessTime INTEGER DEFAULT 0,
      lastError TEXT DEFAULT '',
      iconUrl TEXT DEFAULT '',
      groupName TEXT DEFAULT '',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  RSS_ITEM: `
    CREATE TABLE IF NOT EXISTS rss_subscription_item (
      id TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      sourceName TEXT NOT NULL,
      title TEXT NOT NULL,
      link TEXT NOT NULL,
      description TEXT DEFAULT '',
      content TEXT DEFAULT '',
      author TEXT DEFAULT '',
      category TEXT DEFAULT '',
      guid TEXT DEFAULT '',
      pubDate INTEGER DEFAULT 0,
      isRead INTEGER DEFAULT 0,
      isStarred INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      UNIQUE(sourceId, link)
    )
  `,

  RSS_READ_RECORD: `
    CREATE TABLE IF NOT EXISTS rss_subscription_read_record (
      itemId TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      readTime INTEGER NOT NULL
    )
  `,

  RSS_STAR: `
    CREATE TABLE IF NOT EXISTS rss_subscription_star (
      itemId TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      starTime INTEGER NOT NULL
    )
  `
};

export const RSS_CREATE_INDEX_SQL: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_rss_source_enabled ON rss_subscription_source(enabled)',
  'CREATE INDEX IF NOT EXISTS idx_rss_source_order ON rss_subscription_source(customOrder)',
  'CREATE INDEX IF NOT EXISTS idx_rss_source_group ON rss_subscription_source(groupName)',
  'CREATE INDEX IF NOT EXISTS idx_rss_item_source ON rss_subscription_item(sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_rss_item_pub_date ON rss_subscription_item(pubDate)',
  'CREATE INDEX IF NOT EXISTS idx_rss_item_read ON rss_subscription_item(isRead)',
  'CREATE INDEX IF NOT EXISTS idx_rss_item_starred ON rss_subscription_item(isStarred)',
  'CREATE INDEX IF NOT EXISTS idx_rss_read_source ON rss_subscription_read_record(sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_rss_read_time ON rss_subscription_read_record(readTime)',
  'CREATE INDEX IF NOT EXISTS idx_rss_star_source ON rss_subscription_star(sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_rss_star_time ON rss_subscription_star(starTime)'
];

export interface RssSchemaMigrationSql {
  name: string;
  sql: string;
}

export const RSS_SOURCE_MIGRATION_SQL: RssSchemaMigrationSql[] = [
  { name: 'sourceComment', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN sourceComment TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'variableComment', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN variableComment TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'jsLib', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN jsLib TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'enabledCookieJar', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN enabledCookieJar INTEGER DEFAULT 1' } as RssSchemaMigrationSql,
  { name: 'concurrentRate', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN concurrentRate TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'header', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN header TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'loginUrl', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN loginUrl TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'loginUi', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN loginUi TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'loginCheckJs', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN loginCheckJs TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'coverDecodeJs', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN coverDecodeJs TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'sortUrl', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN sortUrl TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'singleUrl', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN singleUrl INTEGER DEFAULT 0' } as RssSchemaMigrationSql,
  { name: 'articleStyle', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN articleStyle INTEGER DEFAULT 0' } as RssSchemaMigrationSql,
  { name: 'ruleArticles', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleArticles TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleNextPage', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleNextPage TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleTitle', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleTitle TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'rulePubDate', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN rulePubDate TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleDescription', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleDescription TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleImage', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleImage TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleLink', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleLink TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'ruleContent', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN ruleContent TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'contentWhitelist', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN contentWhitelist TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'contentBlacklist', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN contentBlacklist TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'shouldOverrideUrlLoading', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN shouldOverrideUrlLoading TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'style', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN style TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'enableJs', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN enableJs INTEGER DEFAULT 1' } as RssSchemaMigrationSql,
  { name: 'loadWithBaseUrl', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN loadWithBaseUrl INTEGER DEFAULT 1' } as RssSchemaMigrationSql,
  { name: 'injectJs', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN injectJs TEXT DEFAULT \'\'' } as RssSchemaMigrationSql,
  { name: 'lastUpdateTime', sql: 'ALTER TABLE rss_subscription_source ADD COLUMN lastUpdateTime INTEGER DEFAULT 0' } as RssSchemaMigrationSql
];
