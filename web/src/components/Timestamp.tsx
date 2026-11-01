import { Text, Tooltip, type TextProps } from '@mantine/core';
import { TRIAL } from '@/env/mode';
import { formatAge, formatLocal, formatUtc, formatZoned } from '@/lib/format';

/**
 * A time from the API, in the feed's time zone and named; the tooltip gives it in UTC, in the browser's own zone and
 * its age. With `age` the age is shown instead, except in the demo: its times are a recording's, so "3 days ago"
 * would count from the day it was recorded, and the demo shows that date and time, with no age anywhere.
 */
export function Timestamp({
  iso,
  age = false,
  ...props
}: { iso: string | undefined | null; age?: boolean } & TextProps) {
  if (!iso) return null;
  const label = [formatUtc(iso), `yours: ${formatLocal(iso)}`, ...(TRIAL ? [] : [formatAge(iso)])].join(
    ' · ',
  );
  return (
    <Tooltip label={label}>
      <Text component="time" dateTime={iso} size="sm" tabIndex={0} {...props}>
        {age && !TRIAL ? formatAge(iso) : formatZoned(iso)}
      </Text>
    </Tooltip>
  );
}
