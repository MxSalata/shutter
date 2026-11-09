import { Stack, Text } from '@mantine/core';
import type { AccessReport, AccessRow } from '@/api/types';
import { useAccess } from '@/api/hooks';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { TechDetail } from '@/components/TechDetail';
import {
  ACCESS_COLUMNS,
  compareLine,
  JUDGES_SENTENCE,
  needsWords,
  roleLabel,
  rowWords,
  yourColumnSentence,
} from './access';

/** One cell: whether a role, or the signed-in user, may do the row; "Not recorded" while the roles' columns are not. */
function Cell({ value, unknown = false }: { value: boolean; unknown?: boolean }) {
  if (unknown)
    return (
      <Text span size="sm" c="dimmed">
        Not recorded
      </Text>
    );
  return value ? (
    <Text span size="sm" fw={600}>
      Yes
    </Text>
  ) : (
    <Text span size="sm" c="dimmed">
      No
    </Text>
  );
}

function Row({ row, unknown }: { row: AccessRow; unknown: boolean }) {
  const words = rowWords(row.id);
  if (!row.available)
    return (
      <StackTable.Tr>
        <StackTable.Th scope="row" className="stack-row-head">
          {words}
        </StackTable.Th>
        <StackTable.Td data-label="On this instance" colSpan={ACCESS_COLUMNS.length + 1}>
          <Text span size="sm" c="dimmed">
            Not on this instance
          </Text>
        </StackTable.Td>
      </StackTable.Tr>
    );
  return (
    <StackTable.Tr>
      <StackTable.Th scope="row" className="stack-row-head">
        {words}
      </StackTable.Th>
      {ACCESS_COLUMNS.map((c) => (
        <StackTable.Td key={c.role} data-label={c.label} ta="center">
          <Cell value={!!row.roles[c.role]} unknown={unknown} />
        </StackTable.Td>
      ))}
      <StackTable.Td data-label="You" ta="center" className="access-you">
        <Cell value={row.you} />
      </StackTable.Td>
    </StackTable.Tr>
  );
}

/** The roles the table does not give a column (the trace role) and what each has, for the second layer. */
function OtherRoles({ report }: { report: AccessReport }) {
  const shown = new Set(ACCESS_COLUMNS.map((c) => c.role));
  const others = report.roles.filter((r) => !shown.has(r.role));
  if (others.length === 0) return null;
  return (
    <Stack gap={2}>
      {others.map((r) => {
        const has = report.rows
          .filter((row) => row.available && row.roles[r.role])
          .map((row) => rowWords(row.id));
        return (
          <Text key={r.role} size="sm">
            <CodeChip>{r.role}</CodeChip>
            {r.installed
              ? has.length
                ? `: ${has.join('; ')}.`
                : ': none of these rows.'
              : ': not installed on this instance.'}
          </Text>
        );
      })}
    </Stack>
  );
}

function AccessTable({ report }: { report: AccessReport }) {
  const unknown = report.read === 'none';
  return (
    <Stack gap="sm">
      <Text size="sm" c="dimmed">
        What each sign-in may do, beside yours. Read only: nothing here changes who you are.
      </Text>
      <StackTable aria-label="Your access" className="stack-table access-table">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>What</StackTable.Th>
            {ACCESS_COLUMNS.map((c) => (
              <StackTable.Th key={c.role} ta="center" title={c.role}>
                {c.label}
              </StackTable.Th>
            ))}
            <StackTable.Th ta="center" className="access-you">
              You
            </StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {report.rows.map((row) => (
            <Row key={row.id} row={row} unknown={unknown} />
          ))}
        </StackTable.Tbody>
      </StackTable>
      <Text size="sm" data-testid="access-you">
        {yourColumnSentence(report)}
      </Text>
      {report.demo ? (
        <Text size="sm" data-testid="access-judges">
          {JUDGES_SENTENCE}
        </Text>
      ) : null}
      <TechDetail label="The roles and resources behind each column" kind="data">
        <Stack gap="xs">
          <Text size="sm">
            The columns are the roles Shutter installs:{' '}
            {ACCESS_COLUMNS.map((c, i) => (
              <span key={c.role}>
                {i > 0 ? ', ' : ''}
                {c.label} is <CodeChip>{c.role}</CodeChip>
              </span>
            ))}
            . Each column is read from the role&apos;s resources, its granted roles&apos; included
            {report.read === 'recorded' && report.recordedAt
              ? `, as recorded at ${report.recordedAt.replace('T', ' ').replace(/Z$/, ' UTC')}`
              : report.read === 'now'
                ? ', read now'
                : ''}
            . Your column is read from the resources your sign-in holds, as the rest of the app reads them.
            {report.portalHardened
              ? ' The Management Portal is hardened for the public demo: its pages need the resource Shutter_Portal as well, so the portal rows read so.'
              : ''}
          </Text>
          <OtherRoles report={report} />
          <Stack gap={2}>
            {report.rows.map((row) => (
              <Text key={row.id} size="sm">
                {rowWords(row.id)}: <CodeChip>{needsWords(row.needs)}</CodeChip>
                {row.available ? '' : ' (not on this instance)'}
              </Text>
            ))}
          </Stack>
          <Text size="sm" c="dimmed">
            Roles installed here:{' '}
            {report.roles
              .filter((r) => r.installed)
              .map((r) => roleLabel(r.role))
              .join(', ') || 'none recorded'}
            .
          </Text>
        </Stack>
      </TechDetail>
    </Stack>
  );
}

/**
 * "Your access" (CONTRACTS 5, `GET /access`): what each sign-in to Shutter may do, beside what the signed-in user may. A
 * comparison to read, never a switch: nothing here changes who the user is or what they hold, and the reply names roles,
 * never anyone. The page's first layer keeps one line, which says which role the user's column matches; the table opens
 * from it (and on Technical), as the cases' table does in Costs.
 */
export function AccessSection() {
  const access = useAccess();
  return (
    <Section id="access" title="Your access">
      {access.isPending ? (
        <Text size="sm" c="dimmed">
          Reading your access…
        </Text>
      ) : null}
      {access.isError ? (
        <ErrorAlert
          error={access.error}
          title="Your access could not be read"
          onRetry={() => void access.refetch()}
        />
      ) : null}
      {access.data ? (
        <TechDetail label={compareLine(access.data)} kind="data">
          <AccessTable report={access.data} />
        </TechDetail>
      ) : null}
    </Section>
  );
}
