import { Anchor, Stack, Text } from '@mantine/core';
import { IconClockPause, IconExternalLink, IconPlugConnectedX } from '@tabler/icons-react';
import { INSTALL_LINK, INSTALL_URL, liveUnavailableWords, type LiveUnavailable } from '@/lib/liveAgents';
import { useTechnical } from '@/stores/appearance';
import { CodeChip } from './CodeChip';
import { StatusNotice } from './StatusBadge';

/**
 * Live agents cannot run now, said plainly: the budget (the instance's, or the user's own share) is used up, or the
 * model provider refuses the key, and until when; what still works; and, on a demo, where to install Shutter with an
 * API key of one's own. A calm neutral notice, never an error: nothing is wrong with what the reader did. In Technical
 * a line adds the code and the server's sentence.
 *
 * `variant` `notice` is the tinted box (the live banner, the board's dialog, the Ask panel's refusal); `inline` is the
 * same words with no box, inside something that is already a card (a stat tile, a question's turn). `compact` leaves
 * out the line of what still works. `role` is `note` by default, so a notice on every page is not announced each time
 * it appears; a refusal of what the reader just pressed passes `status`.
 */
export function LiveUnavailableNotice({
  state,
  variant = 'notice',
  compact = false,
  role,
  className,
}: {
  state: LiveUnavailable;
  variant?: 'notice' | 'inline';
  compact?: boolean;
  role?: 'note' | 'status';
  className?: string;
}) {
  const technical = useTechnical();
  const words = liveUnavailableWords(state);
  const body = (
    <Stack gap={4} data-testid="live-unavailable" data-reason={state.reason}>
      <Text size="sm" data-testid="live-unavailable-lead">
        {words.lead}
      </Text>
      {compact ? null : <Text size="sm">{words.still}</Text>}
      {/* The link is underlined: it sits inside a sentence (axe's link-in-text-block) */}
      {words.install ? (
        <Text size="sm">
          {words.install}{' '}
          <Anchor href={INSTALL_URL} target="_blank" rel="noreferrer" underline="always" inherit>
            {INSTALL_LINK}
            <IconExternalLink size={12} aria-hidden style={{ verticalAlign: 'middle', marginLeft: 2 }} />
          </Anchor>
        </Text>
      ) : null}
      {technical ? (
        <Text size="xs" c="dimmed" data-testid="live-unavailable-code">
          <CodeChip>{state.code}</CodeChip>
          {state.detail ? ` ${state.detail}` : null}
        </Text>
      ) : null}
    </Stack>
  );
  if (variant === 'inline')
    return (
      <div role={role} className={className}>
        {body}
      </div>
    );
  return (
    <StatusNotice
      tone="neutral"
      icon={state.reason === 'service' ? IconPlugConnectedX : IconClockPause}
      role={role ?? 'note'}
      className={className}
    >
      {body}
    </StatusNotice>
  );
}
