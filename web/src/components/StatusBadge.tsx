import { Alert, Badge, Tooltip, type BadgeProps } from '@mantine/core';
import type { Icon } from '@tabler/icons-react';
import { TONE_COLOURS, TONE_ICONS, type Status, type Tone } from '@/lib/tone';
import { HINT_EVENTS } from '@/theme';

const ICON_SIZES = { xs: 10, sm: 12, md: 14, lg: 16, xl: 18 } as const;

/**
 * A status in one of the five tones, with its icon and its words; the hint, when there is one, is a tooltip the
 * keyboard and a tap reach too. The icon is decorative: the label says everything.
 */
export function StatusBadge({
  tone,
  label,
  hint,
  icon,
  size = 'sm',
  variant,
  w,
}: Omit<Status, 'icon'> & {
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl';
  variant?: BadgeProps['variant'];
  w?: BadgeProps['w'];
  icon?: Icon | null;
}) {
  const I = icon === null ? null : (icon ?? TONE_ICONS[tone]);
  const badge = (
    <Badge
      color={TONE_COLOURS[tone]}
      variant={variant}
      size={size}
      w={w}
      data-tone={tone}
      leftSection={I ? <I size={ICON_SIZES[size]} stroke={2} aria-hidden /> : undefined}
      tabIndex={hint ? 0 : undefined}
      style={{ textTransform: 'none' }}
    >
      {label}
    </Badge>
  );
  if (!hint) return badge;
  return (
    <Tooltip label={hint} multiline maw={320} events={HINT_EVENTS}>
      {badge}
    </Tooltip>
  );
}

/**
 * A status given as a notice: a tinted box with the tone's icon, its title and a few lines; with `onClose`, a close
 * button named `closeLabel`.
 */
export function StatusNotice({
  tone,
  title,
  icon,
  role,
  onClose,
  closeLabel = 'Close',
  className,
  children,
}: {
  tone: Tone;
  title?: React.ReactNode;
  icon?: Icon;
  role?: string;
  onClose?: () => void;
  closeLabel?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const I = icon ?? TONE_ICONS[tone];
  return (
    <Alert
      color={TONE_COLOURS[tone]}
      title={title}
      icon={<I size={18} aria-hidden />}
      role={role}
      data-tone={tone}
      className={className}
      withCloseButton={!!onClose}
      onClose={onClose}
      closeButtonLabel={closeLabel}
    >
      {children}
    </Alert>
  );
}
