const DAY_IN_MS = 24 * 60 * 60 * 1000;

export type AnalyticsDateRange = {
  startDate: Date;
  endDate: Date;
  startDateLabel: string;
  endDateLabel: string;
  dayCount: number;
};

export function parseDateOnlyAsUtc(value: string): Date {
  const [yearText, monthText, dayText] = value.split('-');
  const year = Number.parseInt(yearText ?? '', 10);
  const month = Number.parseInt(monthText ?? '', 10);
  const day = Number.parseInt(dayText ?? '', 10);

  return new Date(Date.UTC(year, month - 1, day));
}

export function startOfUtcDay(date: Date): Date {
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
}

export function addUtcDays(date: Date, days: number): Date {
  return new Date(startOfUtcDay(date).getTime() + days * DAY_IN_MS);
}

export function formatUtcDateOnly(date: Date): string {
  return startOfUtcDay(date).toISOString().slice(0, 10);
}

export function normalizeAnalyticsDateRange(input: {
  startDate?: string;
  endDate?: string;
  defaultDays?: number;
  maxDays?: number;
}): AnalyticsDateRange {
  const defaultDays = input.defaultDays ?? 30;
  const maxDays = input.maxDays ?? 180;
  const normalizedToday = startOfUtcDay(new Date());
  const endDate =
    input.endDate == null
      ? normalizedToday
      : startOfUtcDay(parseDateOnlyAsUtc(input.endDate));
  const startDate =
    input.startDate == null
      ? addUtcDays(endDate, -(defaultDays - 1))
      : startOfUtcDay(parseDateOnlyAsUtc(input.startDate));

  if (startDate.getTime() > endDate.getTime()) {
    throw new RangeError('ANALYTICS_INVALID_DATE_RANGE');
  }

  const dayCount =
    Math.floor((endDate.getTime() - startDate.getTime()) / DAY_IN_MS) + 1;
  if (dayCount > maxDays) {
    throw new RangeError('ANALYTICS_RANGE_TOO_LARGE');
  }

  return {
    startDate,
    endDate,
    startDateLabel: formatUtcDateOnly(startDate),
    endDateLabel: formatUtcDateOnly(endDate),
    dayCount,
  };
}

export function listUtcDaysInclusive(startDate: Date, endDate: Date) {
  const dates: Date[] = [];

  for (
    let cursor = startOfUtcDay(startDate);
    cursor.getTime() <= endDate.getTime();
    cursor = addUtcDays(cursor, 1)
  ) {
    dates.push(cursor);
  }

  return dates;
}

export function nextUtcDay(date: Date) {
  return addUtcDays(date, 1);
}
