import { Button } from '@mantine/core';
import { IconMessageQuestion } from '@tabler/icons-react';
import { useAssistant } from './store';
import { ASK_HERE_EVENT, ASSISTANT_PANEL_ID, useAskInPage } from './panel';

export const ASSISTANT_BUTTON_ID = 'assistant-button';

/**
 * The header's "Ask Shutter" button, on every page: it opens and closes the panel, and says whether it is open. Its icon
 * and its word from a tablet up, the icon alone on a phone (styles.css `.header-help`, which the help button shares), named
 * by the same word in both. On a page that holds Ask Shutter in its own conversation (Set up the site) it goes there
 * instead, and no panel opens.
 */
export function HeaderAssistantButton() {
  const inPage = useAskInPage();
  const open = useAssistant((s) => s.open) && !inPage;
  const toggle = useAssistant((s) => s.toggle);
  return (
    <Button
      id={ASSISTANT_BUTTON_ID}
      variant={open ? 'light' : 'subtle'}
      color={open ? undefined : 'gray'}
      leftSection={<IconMessageQuestion size={18} aria-hidden />}
      aria-label="Ask Shutter"
      aria-expanded={inPage ? undefined : open}
      aria-controls={open ? ASSISTANT_PANEL_ID : undefined}
      onClick={inPage ? () => window.dispatchEvent(new Event(ASK_HERE_EVENT)) : toggle}
      className="header-help"
    >
      <span className="header-help-label">Ask Shutter</span>
    </Button>
  );
}
