import { Text, Tooltip, type TextProps } from '@mantine/core';
import { formatAge, formatLocal, formatUtc, formatZoned } from '@/lib/format';

/** A time from the API, in the feed's time zone and named; the tooltip gives it in UTC, in the browser's own zone and its age. */
export function Timestamp({
  iso,
  age = false,
  ...props
}: { iso: string | undefined | null; age?: boolean } & TextProps) {
  if (!iso) return null;
  const label = `${formatUtc(iso)} · yours: ${formatLocal(iso)} · ${formatAge(iso)}`;
  return (
    <Tooltip label={label}>
      <Text component="time" dateTime={iso} size="sm" tabIndex={0} {...props}>
        {age ? formatAge(iso) : formatZoned(iso)}
      </Text>
    </Tooltip>
  );
}
