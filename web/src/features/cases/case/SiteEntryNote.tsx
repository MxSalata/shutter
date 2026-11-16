import { Stack, Text } from '@mantine/core';
import { IconHandStop } from '@tabler/icons-react';
import { useSiteEntries } from '@/api/hooks';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { withoutItWords, type SiteMatch } from '@/lib/siteEntry';

/**
 * One of the site's own scenarios matched this case (CONTRACTS 6.8): which, its version and who approved it, what the
 * site asks the person to do, the instructions of every other site entry that matched too, and what the case would
 * have done without it. Read from the case's evidence; the approver comes from the site's entries when they can be read.
 */
export function SiteEntryNote({ match }: { match: SiteMatch }) {
  const entries = useSiteEntries();
  const entry = entries.data?.items.find((e) => e.id === match.id);
  // The approver of the version the case matched, only when that version is known and is the one still in force: an
  // unversioned match is never given the approver of whatever version is in force now.
  const approver =
    entry && match.version && entry.activeVersion === match.version ? entry.approvedBy : undefined;
  return (
    <Stack gap={6} data-testid="site-entry-note" className="ask-readonly" p="sm" maw="75ch">
      <StatusBadge
        tone="info"
        label={`Our own scenario ${match.id}`}
        hint="One of this site's own scenarios matched this case. It can only send a case to a person: Shutter sends and closes nothing by itself."
        icon={IconHandStop}
      />
      <Text size="sm">
        <Text span inherit fw={600}>
          {match.title || match.id}
        </Text>
        {match.version ? `, version ${match.version}` : ''}
        {approver ? (
          <>
            {`, approved by ${approver}`}
            {entry?.approvedAt ? (
              <>
                {' on '}
                <Timestamp iso={entry.approvedAt} />
              </>
            ) : null}
          </>
        ) : null}
        {'. A person decides; Shutter sends nothing and closes nothing by itself.'}
      </Text>
      {match.instructions ? (
        <Text size="sm" data-testid="site-entry-instructions">
          <Text span inherit fw={600}>
            {'What this site asks you to do: '}
          </Text>
          {match.instructions}
        </Text>
      ) : null}
      {match.also.map((other) => (
        <Text size="sm" key={other.id} data-testid="site-entry-also">
          <Text span inherit fw={600}>
            {`${other.id}, ${other.title || 'another of our scenarios'}, matched too: `}
          </Text>
          {other.instructions || 'it gives no instructions.'}
        </Text>
      ))}
      <Text size="sm" c="dimmed" data-testid="site-entry-without">
        {withoutItWords(match.displaced)}
      </Text>
    </Stack>
  );
}
