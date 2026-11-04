import { Button, Group } from '@mantine/core';
import { IconChevronDown } from '@tabler/icons-react';

/** A toggle for the rest of a card, the finding in full or the run, named for the card it sits in. */
export function MoreToggle({
  open,
  onToggle,
  controls,
  describedBy,
  label,
}: {
  open: boolean;
  onToggle: () => void;
  controls: string;
  describedBy: string;
  label: string;
}) {
  return (
    <Group>
      <Button
        size="compact-xs"
        variant="subtle"
        onClick={onToggle}
        aria-expanded={open}
        aria-controls={controls}
        aria-describedby={describedBy}
        leftSection={
          <IconChevronDown
            size={14}
            aria-hidden
            style={{ transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
          />
        }
      >
        {open ? `Hide ${label}` : `Show ${label}`}
      </Button>
    </Group>
  );
}
