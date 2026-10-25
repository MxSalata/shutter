import { Badge, Tooltip } from '@mantine/core';
import { humanize } from '@/lib/format';

/** Colours by meaning: blue while investigating, yellow when a person is needed, green verified, red blocked. */
export const STATE_COLOURS: Record<string, string> = {
  detected: 'blue',
  collecting: 'blue',
  investigating: 'blue',
  grouped: 'grape',
  proposed: 'cyan',
  gated: 'cyan',
  rehearsing: 'violet',
  awaiting_approval: 'yellow',
  approved: 'indigo',
  executing: 'indigo',
  verifying: 'teal',
  resolved: 'green',
  blocked: 'red',
  escalated: 'orange',
  failed: 'gray',
};

export const STATE_HINTS: Record<string, string> = {
  detected: 'The failure was seen; the case is open',
  collecting: 'Reading the message, the downstream system and the message store',
  investigating: 'The board is reviewing the evidence',
  grouped: 'Held by an incident: released in order with the other failures to the same receiver',
  proposed: 'A plan was proposed',
  gated: 'The gate checked the plan',
  rehearsing: "The downstream system's dry run of the exact action",
  awaiting_approval: 'A person must approve or reject the plan',
  approved: 'Approved; the receiver is read once more before dispatch',
  executing: 'The conditional write is being sent',
  verifying: "Reading the receiver's committed history and receipts",
  resolved: 'Verified at the receiver',
  blocked: 'Stopped: a check or a person said no; nothing more is sent',
  escalated: 'Handed to a person to decide',
  failed: 'The workflow itself failed',
};

export function StateBadge({ state, size = 'sm' }: { state: string; size?: 'xs' | 'sm' | 'md' | 'lg' }) {
  return (
    <Tooltip label={STATE_HINTS[state] ?? state}>
      <Badge
        color={STATE_COLOURS[state] ?? 'gray'}
        size={size}
        tabIndex={0}
        style={{ textTransform: 'none' }}
      >
        {humanize(state)}
      </Badge>
    </Tooltip>
  );
}

const DISPOSITION_COLOURS: Record<string, string> = {
  resend: 'indigo',
  reconcile: 'teal',
  superseded: 'gray',
  more_evidence: 'yellow',
  escalate: 'orange',
  handled_by_hand: 'grape',
  abandoned: 'gray',
};

export const DISPOSITION_HINTS: Record<string, string> = {
  resend: 'Send the same operation again, conditional on the receiver version, after rehearsal and approval',
  reconcile: 'It was applied already: record that, send nothing',
  superseded: 'A later event moved the encounter on: sending it now would undo that',
  more_evidence: 'The evidence does not decide it yet',
  escalate: 'A person must decide',
  handled_by_hand: 'The team corrected the systems by hand, and a person closed the case',
  abandoned:
    'An approver gave the case up after its workflow stopped moving; nothing more is sent, and it can be reinvestigated',
};

export function DispositionBadge({ disposition }: { disposition: string }) {
  if (!disposition) return null;
  return (
    <Tooltip label={DISPOSITION_HINTS[disposition] ?? disposition} multiline maw={320}>
      <Badge
        variant="outline"
        color={DISPOSITION_COLOURS[disposition] ?? 'gray'}
        tabIndex={0}
        style={{ textTransform: 'none' }}
      >
        {humanize(disposition)}
      </Badge>
    </Tooltip>
  );
}
