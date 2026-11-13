import { Fieldset, UnstyledButton } from '@mantine/core';
import { IconChevronDown } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import './site-profile.css';

/**
 * The questionnaire's controls: Mantine's own. They used to be disabled for a reader who may not save; every reader now
 * changes the answers and reviews them, and only the Save is locked (`saveLocked`).
 */
export { Checkbox, NativeSelect, NumberInput, Radio, Switch, TextInput } from '@mantine/core';

/**
 * A fold of the questionnaire that holds a field (the runbook line, the history policy's override): the page's one
 * disclosure style, the chevron and the words of `TechDetail`, at the fields' own left edge. It keeps its own open
 * state, since a problem with the field inside has to open it, whatever the reader last chose.
 */
export function FoldToggle({
  open,
  onToggle,
  controls,
  children,
}: {
  open: boolean;
  onToggle: () => void;
  /** The id of what it opens, when that stays in the page while closed. */
  controls?: string;
  children: ReactNode;
}) {
  return (
    <div>
      <UnstyledButton
        className="tech-detail-toggle"
        aria-expanded={open}
        aria-controls={controls}
        onClick={onToggle}
      >
        <IconChevronDown size={14} aria-hidden />
        {children}
      </UnstyledButton>
    </div>
  );
}

/**
 * A named group of answers (a receiver, a tier, a team): its name on a rule, and no box. A box insets what it holds,
 * so a question inside one and a question outside it would not start and end at the same place.
 */
export function AnswerGroup({ legend, children }: { legend: string; children: ReactNode }) {
  return (
    <Fieldset legend={legend} variant="unstyled" className="answer-group">
      {children}
    </Fieldset>
  );
}
