import { Button, Group, TextInput } from '@mantine/core';
import { IconChevronDown } from '@tabler/icons-react';
import { useState } from 'react';
import type { SiteReceiver } from '@/api/types';

/**
 * The site's one line on where to look at this receiver, shown on its stopped cases as a navigation hint, never as
 * evidence. Folded until asked for or already set. Clearing it removes it, since a blank line isn't one.
 */
export function RunbookField({
  r,
  i,
  err,
  update,
}: {
  r: SiteReceiver;
  i: number;
  err: (key: string) => string | undefined;
  update: (fn: (r: SiteReceiver) => void) => void;
}) {
  const value = r.manual_check?.runbook ?? '';
  const problem = err('manual_check.runbook');
  const [shown, setShown] = useState(!!value);
  const open = shown || !!problem;
  const id = `site-receivers-${i}-manual_check.runbook`;
  return (
    <>
      <Group>
        <Button
          variant="subtle"
          size="compact-sm"
          color="gray"
          onClick={() => setShown((s) => !s)}
          aria-expanded={open}
          leftSection={
            <IconChevronDown
              size={14}
              aria-hidden
              style={{ transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
            />
          }
        >
          Site runbook line
        </Button>
      </Group>
      {open ? (
        <TextInput
          id={id}
          label="Where to look at this receiver"
          description="Optional, plain text, 300 characters at most: no links, credentials or patient details. Shown on its stopped cases as a hint, not evidence."
          maxLength={300}
          value={value}
          onChange={(e) => {
            const v = e.currentTarget.value;
            update((x) => {
              if (v) x.manual_check = { runbook: v };
              else delete x.manual_check;
            });
          }}
          error={problem}
        />
      ) : null}
    </>
  );
}
