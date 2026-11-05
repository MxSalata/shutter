import { Button } from '@mantine/core';
import {
  IconArrowsLeftRight,
  IconCircleCheck,
  IconHourglass,
  IconTargetOff,
  IconUserExclamation,
} from '@tabler/icons-react';
import { showNextAction } from '@/lib/events';
import type { CaseAction } from './caseAction';

/**
 * The case's action at a glance, at the top right of the case (and, compact, in the sticky tab bar): in the attention
 * tone with the action's words when this user has to act ("Decide on the resend"), a quiet outline otherwise ("No action
 * needed", "Waiting for an approver"), never disabled. Pressing it opens the Outcome band if it is closed and takes the
 * reader to "What needs you now", its details open and its heading focused. Its accessible name says the state in a
 * sentence that holds the visible words. The compact copy shows the icon and a word ("Needs you", "No action"), the
 * icon alone on a phone, 44 px square. An action of comparing goes to the side by side instead.
 */
export function CaseActionButton({
  action,
  compact = false,
  onCompare,
}: {
  action: CaseAction;
  compact?: boolean;
  onCompare?: () => void;
}) {
  const I = action.needsYou
    ? IconUserExclamation
    : action.compare
      ? IconArrowsLeftRight
      : action.differs
        ? IconTargetOff
        : action.label === 'No action needed'
          ? IconCircleCheck
          : IconHourglass;
  return (
    <Button
      className={compact ? 'case-action case-action-compact' : 'case-action'}
      data-needs-you={action.needsYou || undefined}
      variant={action.needsYou ? 'light' : 'default'}
      color={action.needsYou ? 'yellow' : undefined}
      size={compact ? 'compact-sm' : 'sm'}
      leftSection={<I size={compact ? 16 : 18} aria-hidden />}
      aria-label={action.name}
      onClick={action.compare && onCompare ? onCompare : showNextAction}
      data-testid={compact ? 'case-action-compact' : 'case-action'}
    >
      {compact ? <span className="case-action-word">{action.short}</span> : action.label}
    </Button>
  );
}
