import { Text, Tooltip, type TextProps } from '@mantine/core';
import { formatAge, formatDateTime, formatLocal } from '@/lib/format';

/** A time from the API, in UTC; the tooltip gives it in the browser's own time zone and its age. */
export function Timestamp({
  iso,
  age = false,
  ...props
}: { iso: string | undefined | null; age?: boolean } & TextProps) {
  if (!iso) return null;
  const label = `${formatLocal(iso)} · ${formatAge(iso)}`;
  return (
    <Tooltip label={label}>
      <Text component="time" dateTime={iso} size="sm" tabIndex={0} {...props}>
        {age ? formatAge(iso) : `${formatDateTime(iso)} UTC`}
      </Text>
    </Tooltip>
  );
}
