import { Box, Collapse, UnstyledButton } from '@mantine/core';
import { IconChevronDown } from '@tabler/icons-react';
import { useId, useState, type ReactNode } from 'react';
import { useDetail } from '@/stores/appearance';

/**
 * The second layer, one click away: a disclosure named for what it holds ("Reason codes and keys", "Where these
 * figures come from"), never "More". Its kind says what Technical does with it: `data` (codes, keys, versions,
 * digests, run statistics, tables, JSON) opens when the Detail switch is on Technical; `explain` (how to read a table,
 * why, provenance prose) stays closed in both modes. The reader's own toggle wins until the Detail switch changes.
 * The content stays mounted, so a text search still finds it; the controls inside it are reachable only when open.
 */
export function TechDetail({
  label,
  kind,
  children,
  defaultOpen,
  tour,
}: {
  /** What the disclosure holds, in words. */
  label: ReactNode;
  kind: 'data' | 'explain';
  children: ReactNode;
  /** Open at first whatever the Detail level, when the page says so (an address that names the detail). */
  defaultOpen?: boolean;
  /** The guide's name for it (`data-tour`). */
  tour?: string;
}) {
  const detail = useDetail();
  const byDetail = kind === 'data' && detail === 'technical';
  // The reader's own choice, remembered with the Detail level it was made under: a new level starts afresh
  const [own, setOwn] = useState<{ open: boolean; under: string } | null>(null);
  const opened = own && own.under === detail ? own.open : (defaultOpen ?? byDetail);
  const id = useId();
  return (
    <Box data-tour={tour}>
      <UnstyledButton
        className="tech-detail-toggle"
        aria-expanded={opened}
        aria-controls={id}
        onClick={() => setOwn({ open: !opened, under: detail })}
      >
        <IconChevronDown size={14} aria-hidden />
        {label}
      </UnstyledButton>
      <Collapse in={opened} transitionDuration={150}>
        <Box
          id={id}
          data-tech-detail={opened ? 'open' : 'closed'}
          pt={6}
          fz="sm"
          inert={!opened || undefined}
        >
          {children}
        </Box>
      </Collapse>
    </Box>
  );
}
