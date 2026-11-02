import { Anchor, Button, Group, Stack, Table, Text, Textarea, VisuallyHidden } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { Link } from 'react-router';
import { useCan, usePrecedents, useRetirePrecedent } from '@/api/hooks';
import type { Precedent, PrecedentSummary, Snapshot } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { ConfirmModal } from '@/components/ConfirmModal';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import { describeError, isApiError } from '@/lib/errors';
import { formatDay, formatZoned } from '@/lib/format';
import { PRECEDENT_DECISIONS } from '@/lib/status';
import { precedentsOf, precedentWords, retiredBy } from './precedentWords';
import { NotYet, Section } from './Section';

/**
 * The precedents as the line says them: the summary GET /cases/{id}/precedents gave, once the page has read it (it is
 * the count as it stands now, and a retirement changes it), else the one the case's snapshot carries, collected with
 * its evidence. Null when neither has one: then nothing is said.
 */
function useLineSummary(caseId: string, snapshot: Snapshot | null | undefined): PrecedentSummary | null {
  // Never asks the API itself: it reads what "See them" has already read
  const now = usePrecedents(caseId, false).data?.summary;
  return (now ? precedentsOf({ precedents: now }) : null) ?? precedentsOf(snapshot?.summary);
}

/** The line itself, with the last case as a link; in the card it starts with the word, defined on its first use. */
function Line({
  summary,
  labelled = false,
  define = false,
}: {
  summary: PrecedentSummary;
  /** "Precedents: approved and verified ..." rather than the sentence alone, under a heading that names them. */
  labelled?: boolean;
  /** Wrap the word in its definition (its first use on the page). */
  define?: boolean;
}) {
  const w = precedentWords(summary);
  const lead = labelled ? `${w.lead.charAt(0).toLowerCase()}${w.lead.slice(1)}` : w.lead;
  return (
    <Text size="sm" maw="68ch" data-testid="precedents-line">
      {labelled ? (
        <>
          {define ? <Term term="precedent">Precedents</Term> : 'Precedents'}
          {': '}
        </>
      ) : null}
      {lead}
      {w.caseId ? (
        // In the text's own colour and underlined: on the tinted card the link colour falls short of 4.5:1 in dark
        <Anchor
          component={Link}
          to={`/cases/${encodeURIComponent(w.caseId)}`}
          inherit
          c="inherit"
          underline="always"
        >
          {w.caseId}
        </Anchor>
      ) : null}
      {w.tail}
    </Text>
  );
}

/**
 * The precedents under the approval buttons of "What needs you now", for a case that waits for an approval: what
 * approvers decided before on the same conditions at this receiver, never what to do. "See them" opens the list in the
 * Audit trail, where there is room for it.
 */
export function NextActionPrecedents({
  caseId,
  snapshot,
  onSee,
}: {
  caseId: string;
  snapshot: Snapshot | null | undefined;
  onSee?: () => void;
}) {
  const summary = useLineSummary(caseId, snapshot);
  if (!summary) return null;
  const none = summary.approved + summary.rejected === 0;
  return (
    <Stack gap={2} data-testid="next-action-precedents">
      <Line summary={summary} labelled define />
      {!none && onSee ? (
        <Group>
          {/* The default surface keeps its words at 4.5:1 on the tinted card, as Review the plan and decide does */}
          <Button size="compact-xs" variant="default" onClick={onSee}>
            See them<VisuallyHidden component="span"> in the audit trail</VisuallyHidden>
          </Button>
        </Group>
      ) : null}
    </Stack>
  );
}

/** "Retired by approver on 2 Nov: the receiver's contract changed". */
const retiredLine = (p: Precedent) =>
  `Retired${p.retiredBy ? ` by ${p.retiredBy}` : ''}${p.retiredAt ? ` on ${formatDay(p.retiredAt)}` : ''}${p.retiredReason ? `: ${p.retiredReason}` : ''}`;

/** Retiring one: a reason is required; it stays on record and counts for nothing from then on. */
function RetireDialog({
  caseId,
  precedent,
  onClose,
}: {
  caseId: string;
  precedent: Precedent | null;
  onClose: () => void;
}) {
  const retire = useRetirePrecedent(caseId);
  const [reason, setReason] = useState('');
  // The dialog is made afresh for each precedent (its key), and keeps showing it while it closes
  const [shown] = useState(precedent);
  const error = retire.error;
  const code = isApiError(error) ? error.code : '';
  const already = code === 'already_retired' && isApiError(error) ? retiredBy(error.detail) : null;
  const submit = () => {
    if (!shown) return;
    retire.mutate(
      { id: shown.id, reason: reason.trim() },
      {
        onSuccess: () => {
          onClose();
          notifications.show({
            color: 'gray',
            title: 'Precedent retired',
            message: 'It stays on record and counts for nothing from now on.',
          });
        },
      },
    );
  };
  return (
    <ConfirmModal opened={!!precedent} onClose={onClose} title="Retire a precedent">
      {shown ? (
        <Stack gap="sm">
          <Text size="sm">
            {`${PRECEDENT_DECISIONS[shown.decision]?.label ?? shown.decision} by ${shown.approver} on ${formatDay(shown.createdAt)}, case ${shown.caseId}. A retired precedent stays on record and counts for nothing from now on.`}
          </Text>
          <Textarea
            label="Why retire it"
            description="Recorded on the precedent with your name"
            required
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
            maxLength={500}
            data-autofocus
          />
          {error ? (
            <Text size="sm" c="red" role="alert">
              {code === 'already_retired'
                ? already
                  ? `Already retired by ${already.by} on ${formatZoned(already.at)}.`
                  : `Already retired: ${describeError(error)}`
                : code === 'not_found'
                  ? 'This precedent is no longer on record.'
                  : describeError(error)}
            </Text>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              {code === 'already_retired' ? 'Done' : 'Cancel'}
            </Button>
            <Button
              onClick={submit}
              loading={retire.isPending}
              disabled={!reason.trim() || code === 'already_retired' || code === 'not_found'}
            >
              Retire it
            </Button>
          </Group>
        </Stack>
      ) : null}
    </ConfirmModal>
  );
}

/**
 * Every precedent of these conditions at this receiver, newest first: its date, the decision, who decided, the case,
 * the policy it was decided under and whether it still counts. A retired one is struck through and says who retired it,
 * when and why. An approver can retire an active one.
 */
function PrecedentsTable({ caseId, rows }: { caseId: string; rows: Precedent[] }) {
  const can = useCan();
  const [retiring, setRetiring] = useState<Precedent | null>(null);
  // Each opening of the dialog is a new one: its reason empty and no earlier answer shown
  const [round, setRound] = useState(0);
  const retire = (p: Precedent) => {
    setRetiring(p);
    setRound((n) => n + 1);
  };
  if (!rows.length) return <NotYet>No precedent is recorded for these conditions at this receiver.</NotYet>;
  return (
    <>
      <Table.ScrollContainer minWidth={720} className="stack-scroll">
        <StackTable verticalSpacing="xs" fz="sm" className="stack-table precedents-table">
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th>Date</StackTable.Th>
              <StackTable.Th>Decision</StackTable.Th>
              <StackTable.Th>Approver</StackTable.Th>
              <StackTable.Th>Case</StackTable.Th>
              <StackTable.Th>Policy version</StackTable.Th>
              <StackTable.Th>Active</StackTable.Th>
              {can.approve ? (
                <StackTable.Th>
                  <VisuallyHidden>Retire</VisuallyHidden>
                </StackTable.Th>
              ) : null}
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {rows.map((p) => {
              const retired = !p.active;
              const struck = retired ? { textDecoration: 'line-through' } : undefined;
              const decision = PRECEDENT_DECISIONS[p.decision];
              return (
                <StackTable.Tr key={String(p.id)} data-retired={retired || undefined}>
                  <StackTable.Td data-label="Date" className="precedent-fact" style={struck}>
                    <Timestamp iso={p.createdAt} />
                  </StackTable.Td>
                  <StackTable.Td data-label="Decision">
                    {decision ? (
                      <StatusBadge {...decision} variant={retired ? 'outline' : undefined} />
                    ) : (
                      p.decision
                    )}
                  </StackTable.Td>
                  <StackTable.Td data-label="Approver" style={struck}>
                    {p.approver}
                  </StackTable.Td>
                  <StackTable.Td data-label="Case" className="precedent-fact" style={struck}>
                    {p.caseId === caseId ? (
                      `${p.caseId} (this case)`
                    ) : (
                      <Anchor component={Link} to={`/cases/${encodeURIComponent(p.caseId)}`} size="sm">
                        {p.caseId}
                      </Anchor>
                    )}
                  </StackTable.Td>
                  <StackTable.Td data-label="Policy version" className="precedent-fact" style={struck}>
                    {p.policyVersion ? <CodeChip>{p.policyVersion}</CodeChip> : 'not recorded'}
                    {p.siteProfileVersion !== undefined && p.siteProfileVersion !== '' ? (
                      <Text size="xs" c="dimmed">{`site profile version ${p.siteProfileVersion}`}</Text>
                    ) : null}
                  </StackTable.Td>
                  <StackTable.Td data-label="Active">{retired ? retiredLine(p) : 'Active'}</StackTable.Td>
                  {can.approve ? (
                    <StackTable.Td data-label="Retire">
                      {retired ? null : (
                        <Button size="compact-xs" variant="default" onClick={() => retire(p)}>
                          Retire
                          <VisuallyHidden component="span">{` the precedent from ${p.caseId}, ${formatDay(p.createdAt)}`}</VisuallyHidden>
                        </Button>
                      )}
                    </StackTable.Td>
                  ) : null}
                </StackTable.Tr>
              );
            })}
          </StackTable.Tbody>
        </StackTable>
      </Table.ScrollContainer>
      {round ? (
        <RetireDialog key={round} caseId={caseId} precedent={retiring} onClose={() => setRetiring(null)} />
      ) : null}
    </>
  );
}

/** What "See them" holds: the rows as the API gives them now, read only once it opens. */
function PrecedentsList({ caseId }: { caseId: string }) {
  const list = usePrecedents(caseId, true);
  if (list.isPending)
    return (
      <Text size="sm" c="dimmed" role="status">
        Reading the precedents…
      </Text>
    );
  if (list.isError)
    return (
      <ErrorAlert
        error={list.error}
        title="The precedents could not be read"
        onRetry={() => void list.refetch()}
      />
    );
  if (!list.data) return <NotYet>This server does not list precedents.</NotYet>;
  return (
    <Stack gap="sm">
      <PrecedentsTable caseId={caseId} rows={list.data.precedents ?? []} />
      <ApiSource endpoint={`GET /api/shutter/cases/${caseId}/precedents`} data={list.data} />
    </Stack>
  );
}

/**
 * The Audit trail's precedents, for every case: the line, and "See them", the list as it stands now. A precedent says
 * what happened before; it informs the approver and never releases anything (CONTRACTS 6.4), so nothing here offers to
 * approve.
 */
export function PrecedentsSection({
  caseId,
  snapshot,
  define = true,
  open,
}: {
  caseId: string;
  snapshot: Snapshot | null | undefined;
  /** Wrap the word in its definition: its first use on the page, unless "What needs you now" already used it. */
  define?: boolean;
  /** Open "See them" from the start, when the reader came here from "What needs you now". */
  open?: boolean;
}) {
  const summary = useLineSummary(caseId, snapshot);
  if (!summary) return null;
  const none = summary.approved + summary.rejected === 0;
  return (
    <Section
      id="precedents"
      title={define ? <Term term="precedent">Precedents</Term> : 'Precedents'}
      note="What approvers decided before on the same evidence at this receiver. It informs a decision and never releases anything."
    >
      <Line summary={summary} />
      <TechDetail
        kind="data"
        lazy
        label={none ? 'See the record' : 'See them'}
        defaultOpen={open || undefined}
      >
        <PrecedentsList caseId={caseId} />
      </TechDetail>
    </Section>
  );
}
