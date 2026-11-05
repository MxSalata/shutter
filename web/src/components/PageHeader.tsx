import { Group, Stack, Text, Title } from '@mantine/core';
import type { Icon } from '@tabler/icons-react';
import { useEffect, type ReactNode } from 'react';
import { APP_NAME } from '@/theme';
import { TRIAL } from '@/env/mode';
import { hueVar, type Hue } from '@/lib/hues';
import { TechDetail } from './TechDetail';

/** The browser tab's title for a page: "Cases · Shutter", or "Cases · Shutter (trial)" in the trial. */
export const documentTitle = (page: string) => `${page} · ${APP_NAME}${TRIAL ? ' (trial)' : ''}`;

/**
 * A page's header: its section's icon in the section's identity hue (a detail page takes its parent section's), the
 * h1 and the page's status badges, the actions at the right, then the lead (one plain sentence of at most 20 words, in
 * the text colour), an optional row of facts and links (`meta`: the case's line, the IRIS row) and an optional
 * technical detail (kind `explain` unless said: the long expert paragraph most pages carried). It sets the tab's title.
 * `subtitle` is today's dimmed paragraph, kept for one release so the pages can move to `lead` one at a time.
 */
export function PageHeader({
  title,
  icon: I,
  hue,
  status,
  lead,
  leadMaw = '68ch',
  details,
  detailsLabel = 'Technical detail',
  detailsKind = 'explain',
  meta,
  actions,
  tour,
  subtitle,
  docTitle,
}: {
  title: ReactNode;
  /** The page's navigation icon. */
  icon?: Icon;
  /** The section's identity hue for the icon. */
  hue?: Hue;
  /** The page's status badges, beside the title. */
  status?: ReactNode;
  lead?: ReactNode;
  /** The lead's measure: 68ch keeps a long lead readable on a wide screen; `none` lets a short one stay on one line. */
  leadMaw?: string;
  /** The second layer under the lead, in a TechDetail. */
  details?: ReactNode;
  detailsLabel?: ReactNode;
  detailsKind?: 'data' | 'explain';
  /** Facts and links under the lead, in sm. */
  meta?: ReactNode;
  actions?: ReactNode;
  /** The guide's name for the page's introduction (`data-tour`). */
  tour?: string;
  /** @deprecated Use `lead` (and `details` for the long text). */
  subtitle?: ReactNode;
  /** The page's name in the tab's title, when the title is not plain text. */
  docTitle?: string;
}) {
  const page = docTitle ?? (typeof title === 'string' ? title : undefined);
  useEffect(() => {
    if (page) document.title = documentTitle(page);
  }, [page]);
  return (
    <Stack gap="xs" mb="lg" data-tour={tour}>
      <Group justify="space-between" align="flex-start" wrap="wrap" gap="sm">
        <Group gap="sm" wrap="nowrap" align="center" style={{ minWidth: 0, flex: '1 1 320px' }}>
          {I ? (
            <span
              className="identity-mark page-icon"
              style={{
                width: 36,
                height: 36,
                borderRadius: 8,
                ['--mark-hue' as string]: hue ? hueVar(hue) : undefined,
              }}
              aria-hidden
            >
              <I size={22} stroke={1.8} />
            </span>
          ) : null}
          <Group gap="sm" wrap="wrap" align="center" style={{ minWidth: 0 }}>
            <Title order={1}>{title}</Title>
            {status}
          </Group>
        </Group>
        {actions ? <Group gap="xs">{actions}</Group> : null}
      </Group>
      {lead ? (
        <Text size="lg" maw={leadMaw}>
          {lead}
        </Text>
      ) : null}
      {subtitle ? (
        <Text c="dimmed" size="sm">
          {subtitle}
        </Text>
      ) : null}
      {meta ? (
        <Group gap="md" wrap="wrap" fz="sm">
          {meta}
        </Group>
      ) : null}
      {details ? (
        <TechDetail label={detailsLabel} kind={detailsKind}>
          {details}
        </TechDetail>
      ) : null}
    </Stack>
  );
}
