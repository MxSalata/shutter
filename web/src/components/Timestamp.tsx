import { Text, Tooltip, type TextProps } from '@mantine/core';
import { TRIAL } from '@/env/mode';
import {
  formatAge,
  formatLocal,
  formatUtc,
  formatUtcTime,
  formatZoned,
  formatZonedTime,
  isToday,
} from '@/lib/format';
import { useDetail } from '@/stores/appearance';

/**
 * A time from the API, in the feed's time zone and named; the tooltip gives it in UTC, in the browser's own zone and
 * its age. With `age` the age is shown instead, except in the trial: its times are a recording's, so "3 days ago"
 * would count from the day it was recorded, and the trial shows that date and time, with no age anywhere. With
 * `short` a time of today shows without its date ("09:20:00 BST") and any other day with it ("15 Oct, 09:20:00 BST").
 * With Detail on Technical the UTC time sits beside the local one ("15 Oct, 09:20:00 BST, 08:20:00Z").
 */
export function Timestamp({
  iso,
  age = false,
  short = false,
  ...props
}: { iso: string | undefined | null; age?: boolean; short?: boolean } & TextProps) {
  const technical = useDetail() === 'technical';
  if (!iso) return null;
  const label = [formatUtc(iso), `yours: ${formatLocal(iso)}`, ...(TRIAL ? [] : [formatAge(iso)])].join(
    ' · ',
  );
  const local = short && isToday(iso) ? formatZonedTime(iso) : formatZoned(iso);
  const shown = age && !TRIAL ? formatAge(iso) : technical ? `${local}, ${formatUtcTime(iso)}` : local;
  return (
    <Tooltip label={label}>
      <Text component="time" dateTime={iso} size="sm" tabIndex={0} {...props}>
        {shown}
      </Text>
    </Tooltip>
  );
}
