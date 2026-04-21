export enum SubscriptionIntervalUnit {
  MINUTE = 'minute',
  HOUR = 'hour',
  DAY = 'day',
  WEEK = 'week'
}

export interface SubscriptionIntervalDisplayValue {
  valueText: string;
  unit: SubscriptionIntervalUnit;
}

const DEFAULT_INTERVAL_MINUTES = 180;
const MINUTES_PER_HOUR = 60;
const MINUTES_PER_DAY = 24 * MINUTES_PER_HOUR;
const MINUTES_PER_WEEK = 7 * MINUTES_PER_DAY;

function normalizeIntervalMinutes(totalMinutes: number): number {
  if (!Number.isFinite(totalMinutes)) {
    return DEFAULT_INTERVAL_MINUTES;
  }
  const normalizedValue = Math.floor(totalMinutes);
  if (normalizedValue <= 0) {
    return DEFAULT_INTERVAL_MINUTES;
  }
  return normalizedValue;
}

export function getSubscriptionIntervalUnitMinutes(unit: SubscriptionIntervalUnit): number {
  if (unit === SubscriptionIntervalUnit.WEEK) {
    return MINUTES_PER_WEEK;
  }
  if (unit === SubscriptionIntervalUnit.DAY) {
    return MINUTES_PER_DAY;
  }
  if (unit === SubscriptionIntervalUnit.HOUR) {
    return MINUTES_PER_HOUR;
  }
  return 1;
}

export function getSubscriptionIntervalUnitLabel(unit: SubscriptionIntervalUnit): string {
  if (unit === SubscriptionIntervalUnit.WEEK) {
    return '周';
  }
  if (unit === SubscriptionIntervalUnit.DAY) {
    return '天';
  }
  if (unit === SubscriptionIntervalUnit.HOUR) {
    return '小时';
  }
  return '分钟';
}

export function splitSubscriptionIntervalMinutesForDisplay(totalMinutes: number): SubscriptionIntervalDisplayValue {
  const normalizedMinutes = normalizeIntervalMinutes(totalMinutes);
  if (normalizedMinutes % MINUTES_PER_WEEK === 0) {
    return {
      valueText: `${normalizedMinutes / MINUTES_PER_WEEK}`,
      unit: SubscriptionIntervalUnit.WEEK
    };
  }
  if (normalizedMinutes % MINUTES_PER_DAY === 0) {
    return {
      valueText: `${normalizedMinutes / MINUTES_PER_DAY}`,
      unit: SubscriptionIntervalUnit.DAY
    };
  }
  if (normalizedMinutes % MINUTES_PER_HOUR === 0) {
    return {
      valueText: `${normalizedMinutes / MINUTES_PER_HOUR}`,
      unit: SubscriptionIntervalUnit.HOUR
    };
  }
  return {
    valueText: `${normalizedMinutes}`,
    unit: SubscriptionIntervalUnit.MINUTE
  };
}

export function convertSubscriptionIntervalDisplayToMinutes(
  valueText: string,
  unit: SubscriptionIntervalUnit,
  defaultMinutes: number = DEFAULT_INTERVAL_MINUTES
): number {
  const trimmedText = valueText.trim();
  if (trimmedText.length <= 0) {
    return defaultMinutes;
  }
  const parsedValue = Number(trimmedText);
  if (Number.isNaN(parsedValue) || !Number.isFinite(parsedValue)) {
    return defaultMinutes;
  }
  const normalizedValue = Math.floor(parsedValue);
  if (normalizedValue <= 0) {
    return getSubscriptionIntervalUnitMinutes(unit);
  }
  return normalizedValue * getSubscriptionIntervalUnitMinutes(unit);
}

export function formatSubscriptionIntervalValue(totalMinutes: number): string {
  const display = splitSubscriptionIntervalMinutesForDisplay(totalMinutes);
  return `${display.valueText} ${getSubscriptionIntervalUnitLabel(display.unit)}`;
}

export function formatSubscriptionIntervalSchedule(totalMinutes: number): string {
  return `每 ${formatSubscriptionIntervalValue(totalMinutes)}检查`;
}
