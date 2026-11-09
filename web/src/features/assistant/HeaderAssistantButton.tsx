import { Button } from '@mantine/core';
import { IconMessageQuestion } from '@tabler/icons-react';
import { useAssistant } from './store';
import { ASSISTANT_PANEL_ID } from './panel';

export const ASSISTANT_BUTTON_ID = 'assistant-button';

/**
 * The header's "Ask Shutter" button, on every page: it opens and closes the panel, and says whether it is open. Its icon
 * and its word from a tablet up, the icon alone on a phone (styles.css `.header-help`, which the help button shares), named
 * by the same word in both.
 */
export function HeaderAssistantButton() {
  const open = useAssistant((s) => s.open);
  const toggle = useAssistant((s) => s.toggle);
  return (
    <Button
      id={ASSISTANT_BUTTON_ID}
      variant={open ? 'light' : 'subtle'}
      color={open ? undefined : 'gray'}
      leftSection={<IconMessageQuestion size={18} aria-hidden />}
      aria-label="Ask Shutter"
      aria-expanded={open}
      aria-controls={open ? ASSISTANT_PANEL_ID : undefined}
      onClick={toggle}
      className="header-help"
    >
      <span className="header-help-label">Ask Shutter</span>
    </Button>
  );
}
