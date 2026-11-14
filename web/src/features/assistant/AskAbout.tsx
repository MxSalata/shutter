import { ActionIcon, Tooltip } from '@mantine/core';
import { IconMessageQuestion } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { HINT_EVENTS } from '@/theme';
import { AskAboutRegion } from './AskAboutRegion';
import { ASSISTANT_PANEL_ID, askAboutButtonId, useAssistantWide } from './panel';
import { useAssistant, type PageFocus } from './store';

/** The button's words, in its tooltip and at the start of its name. */
export const ASK_ABOUT_LABEL = 'Ask Shutter about this';

/**
 * "Ask Shutter about this" for one of a page's questions: a button with the header's Ask Shutter icon, its words in its
 * tooltip and its name, and what it opens. From the wide breakpoint, where the panel sits beside the page and leaves the
 * form in view, it opens the panel on the question (`askAbout`); below it, where the panel would cover the form, it opens
 * the same question under the button, in the page. Pressed again, it closes what it opened. Nothing it opens writes to
 * the page's draft.
 */
export function useAskAbout(focus: PageFocus): { button: ReactNode; region: ReactNode } {
  const wide = useAssistantWide();
  const askAbout = useAssistant((s) => s.askAbout);
  const setPanel = useAssistant((s) => s.setOpen);
  const panelOn = useAssistant(
    (s) =>
      s.open &&
      s.focus?.page === focus.page &&
      s.focus.id === focus.id &&
      s.focus.question === focus.question,
  );
  const [shown, setShown] = useState(false);
  const inline = !wide && shown;
  const id = askAboutButtonId(focus.id);
  const regionId = `${id}-region`;
  const on = wide ? panelOn : inline;
  const button = (
    <Tooltip label={ASK_ABOUT_LABEL} events={HINT_EVENTS}>
      <ActionIcon
        id={id}
        variant={on ? 'filled' : 'light'}
        size={28}
        radius="xl"
        aria-label={`${ASK_ABOUT_LABEL}: ${focus.title}`}
        aria-expanded={on}
        aria-controls={on ? (wide ? ASSISTANT_PANEL_ID : regionId) : undefined}
        onClick={() => {
          if (!wide) setShown((s) => !s);
          else if (panelOn) setPanel(false);
          else askAbout(focus);
        }}
        className="ask-about"
        data-ask-about={focus.id}
      >
        <IconMessageQuestion size={16} aria-hidden />
      </ActionIcon>
    </Tooltip>
  );
  const region = inline ? <AskAboutRegion id={regionId} focus={focus} /> : null;
  return { button, region };
}
