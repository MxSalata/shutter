import { Alert, Box, List, Paper, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { useReceiverCheck } from '@/api/hooks';
import type { ReceiverCheck } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { TechDetail } from '@/components/TechDetail';

const TITLE = 'What to check at the receiver';

function Part({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Box>
      <Title order={5} size="sm" mb={2}>
        {title}
      </Title>
      {children}
    </Box>
  );
}

function Pair({ label, value }: { label: string; value: string }) {
  return (
    <Box miw={0}>
      <Text size="xs" c="dimmed">
        {label}
      </Text>
      <Text size="sm" className="mono-wrap">
        {value}
      </Text>
    </Box>
  );
}

function Guide({ g }: { g: ReceiverCheck }) {
  const i = g.identity;
  const check = g.checks[0]!;
  return (
    <Stack gap="sm">
      <Text size="sm">{g.evidenceNote}</Text>
      <Alert color="yellow" icon={<IconAlertTriangle size={18} aria-hidden />} p="xs">
        <Text size="sm">{g.queueWarning}</Text>
      </Alert>
      <SimpleGrid
        cols={{ base: 2, sm: 4 }}
        spacing="xs"
        verticalSpacing={6}
        data-testid="receiver-check-identity"
      >
        <Pair label="Patient" value={i.patientId} />
        <Pair label="Authority" value={i.authority} />
        <Pair label="Encounter" value={i.encounterId} />
        <Pair label="Receiver" value={i.receiver} />
        <Pair label="Source" value={i.sourceSystem} />
        <Pair label="Message" value={`${i.messageType}, ${i.controlId}`} />
        <Pair label={i.timeLabel} value={i.time} />
        <Pair label="Message Viewer header" value={i.messageRef} />
        <Pair label="Evidence collected" value={i.collectedAt} />
      </SimpleGrid>
      <Part title="What this message asked the receiver to record">
        <Text size="sm">{g.messageRequest.summary}</Text>
        <List size="sm" spacing={0}>
          {g.messageRequest.fields.map((f) => (
            <List.Item key={f.label}>
              {f.label}: <span className="mono-wrap">{f.value}</span>
              {f.source === 'doubtful' ? ' (doubtful)' : ''}
            </List.Item>
          ))}
        </List>
        {g.messageRequest.note ? <Text size="sm">{g.messageRequest.note}</Text> : null}
      </Part>
      {g.receiverRead ? (
        <Text size="sm">
          Read from the receiver: {g.receiverRead.state}
          {g.receiverRead.ward ? `, ${g.receiverRead.ward}` : ''}
          {g.receiverRead.bed ? `, bed ${g.receiverRead.bed}` : ''}.
        </Text>
      ) : null}
      {g.laterMovement ? (
        <Text size="sm">
          Later movement, from {g.laterMovement.source}: {g.laterMovement.summary}
        </Text>
      ) : null}
      <Part title="Where to look">
        <Text size="sm">{check.where}</Text>
        {g.siteRunbook ? (
          <Text size="sm">
            <Text span fw={600} inherit>
              Site runbook: a navigation hint, not evidence.
            </Text>{' '}
            {g.siteRunbook}
          </Text>
        ) : null}
        <Text size="sm">Compare: {check.compare.join(', ')}.</Text>
      </Part>
      <Part title="What each answer would mean">
        <List size="sm" spacing={2}>
          {check.meanings.map((m) => (
            <List.Item key={m.answer}>
              <Text span fw={600} inherit>
                {m.label}:
              </Text>{' '}
              {m.text}
            </List.Item>
          ))}
        </List>
      </Part>
      <Part title="What remains unknown">
        <List size="sm" spacing={0}>
          {[...g.limitations, ...g.unknown].map((u) => (
            <List.Item key={u}>{u}</List.Item>
          ))}
        </List>
      </Part>
      <Text size="sm">{g.report}</Text>
    </Stack>
  );
}

function Card({ caseId }: { caseId: string }) {
  const check = useReceiverCheck(caseId);
  return (
    <Paper withBorder p="sm" role="region" aria-label={TITLE}>
      {check.isError ? (
        <ErrorAlert
          error={check.error}
          title="The checks could not be read"
          onRetry={() => void check.refetch()}
        />
      ) : check.data ? (
        <Guide g={check.data} />
      ) : check.isPending ? null : (
        <Text size="sm" c="dimmed">
          This case is no longer stopped.
        </Text>
      )}
    </Paper>
  );
}

/**
 * A stopped case's guide for the engineer, above its manual-handling action: read only, with no model and no receiver
 * call. Folded in both Detail levels, since the Summary tab holds to its word budget, and read from the server once opened.
 */
export function ReceiverCheckCard({ caseId }: { caseId: string }) {
  return (
    <TechDetail label={TITLE} kind="explain" lazy>
      <Card caseId={caseId} />
    </TechDetail>
  );
}
