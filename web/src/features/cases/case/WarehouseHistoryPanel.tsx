import { Alert, Button, Stack, Text } from '@mantine/core';
import { useReadWarehouseHistory, useWarehouseHistory } from '@/api/hooks';
import type { WarehouseRead, WarehouseRow } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StackTable } from '@/components/StackTable';
import { Timestamp } from '@/components/Timestamp';
import { Section } from './Section';

const REFUSED: Record<string, string> = {
  row_count_mismatch:
    'This batch holds fewer or more rows than its manifest says, so it may be half published.',
  identity_mismatch: 'The answer held a row for another patient, so none of it is shown.',
  row_invalid: 'A row in the answer does not follow the table specification, so none of it is shown.',
  sequence_regressed: 'This batch is older than the last one read, so the export may have been restored.',
  schema_version: 'This batch follows another version of the table specification.',
  wrong_dataset: 'The answer was for another dataset.',
  manifest_incomplete: 'The batch manifest is incomplete.',
  watermark_inconsistent: 'The batch manifest claims a watermark it does not give.',
  watermark_in_future: 'The batch manifest gives a watermark still to come.',
};

/** Exactly what the row says, with nothing worked out: a time not known stays not known. */
function Rows({ rows }: { rows: WarehouseRow[] }) {
  return (
    <StackTable verticalSpacing="xs" fz="sm" className="stack-table">
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Event time</StackTable.Th>
          <StackTable.Th>Event</StackTable.Th>
          <StackTable.Th>Ward</StackTable.Th>
          <StackTable.Th>Bed</StackTable.Th>
          <StackTable.Th>Encounter, as exported</StackTable.Th>
          <StackTable.Th>Status</StackTable.Th>
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {rows.map((r) => (
          <StackTable.Tr key={r.source_event_id}>
            <StackTable.Td data-label="Event time">
              {r.event_time ? <Timestamp iso={r.event_time} /> : 'Not known'}
            </StackTable.Td>
            <StackTable.Td data-label="Event">{r.event_kind}</StackTable.Td>
            <StackTable.Td data-label="Ward">{r.ward ?? 'Not given'}</StackTable.Td>
            <StackTable.Td data-label="Bed">{r.bed ?? 'Not given'}</StackTable.Td>
            <StackTable.Td data-label="Encounter, as exported">{r.encounter_id ?? 'Not given'}</StackTable.Td>
            <StackTable.Td data-label="Status">{r.record_status}</StackTable.Td>
          </StackTable.Tr>
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
}

function Provenance({ read }: { read: WarehouseRead }) {
  return (
    <Stack gap={2}>
      <Text size="sm">
        Source complete through:{' '}
        {read.sourceWatermark ? <Timestamp iso={read.sourceWatermark} span /> : 'unknown'}. Read at:{' '}
        <Timestamp iso={read.readAt} span />.
      </Text>
      {read.batch ? (
        <Text size="sm" c="dimmed">
          {read.sourceSystem} for {read.receiverReference}, batch {read.batch}
          {read.ageMinutes === null ? '' : `, ${read.ageMinutes} minutes behind by its watermark`}.
        </Text>
      ) : null}
    </Stack>
  );
}

function Outcome({ read }: { read: WarehouseRead }) {
  switch (read.status) {
    case 'no_batch':
      return <Text size="sm">No batch of this dataset has been published yet.</Text>;
    case 'no_identity':
      return (
        <Text size="sm">This case names no patient and assigning authority, so nothing was looked up.</Text>
      );
    case 'no_rows':
      return (
        <Text size="sm">
          No matching rows were returned from this batch. This does not establish that the patient or movement
          is absent at the receiver.
        </Text>
      );
    case 'withheld':
      return (
        <Text size="sm">
          {read.freshness === 'unknown'
            ? 'The age of this batch is unknown, so its rows are not shown.'
            : "This batch is older than this site's limit, so its rows are not shown."}
        </Text>
      );
    case 'invalid':
      return (
        <Alert color="yellow" variant="light" title="This read was refused">
          {REFUSED[read.category] ?? 'The answer does not follow the table specification.'} Ask whoever
          publishes this dataset.
        </Alert>
      );
    case 'unavailable':
      return (
        <Text size="sm">
          Warehouse history could not be read just now. The investigation is not affected: it does not use
          this.
        </Text>
      );
    default:
      return (
        <Stack gap="xs">
          {read.freshness === 'older' ? (
            <Text size="sm">
              These rows are older than this site&apos;s limit. They are shown because it chose that.
            </Text>
          ) : null}
          {read.freshness === 'unknown' ? (
            <Text size="sm">
              The age of these rows is unknown. They are shown because this site chose that.
            </Text>
          ) : null}
          <Rows rows={read.rows} />
          {read.truncated ? (
            <Text size="sm">The newest 200 rows. There are more, so this is not the whole history.</Text>
          ) : null}
        </Stack>
      );
  }
}

/**
 * Warehouse history (docs/warehouse-history.md): what a site's export said about this patient, for a person to read
 * beside the evidence. It is apart from the evidence, and nothing that decides a case reads it. With the feature off, or
 * on a server without the route, the panel is not there at all.
 */
export function WarehouseHistoryPanel({ caseId, canRead }: { caseId: string; canRead: boolean }) {
  const history = useWarehouseHistory(caseId);
  const reading = useReadWarehouseHistory(caseId);
  if (!history.data?.enabled) return null;
  const read = history.data.read;
  return (
    <Section
      id="warehouse-history"
      title="Warehouse history: historical context only"
      note="This may be hours behind. It is not used to authorise or verify a resend."
    >
      <Stack gap="sm">
        {read ? <Provenance read={read} /> : null}
        {read?.generationChanged ? (
          <Text size="sm">The export was rebuilt since the last read of this dataset.</Text>
        ) : null}
        {read ? <Outcome read={read} /> : null}
        {reading.error ? <ErrorAlert error={reading.error} /> : null}
        {canRead ? (
          <div>
            <Button variant="default" size="xs" loading={reading.isPending} onClick={() => reading.mutate()}>
              {read ? 'Read again' : 'Read warehouse history'}
            </Button>
          </div>
        ) : null}
        <ApiSource endpoint={`GET /api/shutter/cases/${caseId}/warehouse-history`} data={history.data} />
      </Stack>
    </Section>
  );
}
