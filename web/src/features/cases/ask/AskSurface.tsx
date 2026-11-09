import { Button } from '@mantine/core';
import { IconMessageQuestion } from '@tabler/icons-react';
import { forwardRef } from 'react';
import { ASSISTANT_PANEL_ID } from '@/features/assistant/panel';

/** The panel's id, which the button names in `aria-controls` while it is open. */
export const ASK_PANEL_ID = ASSISTANT_PANEL_ID;
const TITLE = 'Ask about this case';

/**
 * Opens and closes Ask about this case, the Ask Shutter panel with the case in it (features/assistant): opening it asks the
 * case's first suggested question for the reader. The guide points at it.
 */
export const AskButton = forwardRef<HTMLButtonElement, { open: boolean; onToggle: () => void }>(
  function AskButton({ open, onToggle }, ref) {
    return (
      <div data-tour="case-ask">
        <Button
          ref={ref}
          variant={open ? 'filled' : 'light'}
          leftSection={<IconMessageQuestion size={16} aria-hidden />}
          aria-expanded={open}
          aria-controls={open ? ASK_PANEL_ID : undefined}
          onClick={onToggle}
          data-tour-action="ask-open"
        >
          {TITLE}
        </Button>
      </div>
    );
  },
);
