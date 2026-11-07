import { Alert, Button, Group, List, Stack, Text } from '@mantine/core';
import { useState } from 'react';
import { ApiSource } from '@/components/ApiSource';
import { ConfirmModal } from '@/components/ConfirmModal';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import type { PlanAnswer } from './onboarding';

export function Lines({ title, lines }: { title: string; lines: string[] }) {
  if (!lines.length) return null;
  return (
    <Stack gap={4}>
      <Text fw={600} size="sm">
        {title}
      </Text>
      <List size="sm" spacing={4}>
        {lines.map((l) => (
          <List.Item key={l}>{l}</List.Item>
        ))}
      </List>
    </Stack>
  );
}

/**
 * A namespace's plan, in the helper's own sentences: what would change, in the order it would run, what to look at and
 * what stays for a person. Nothing has changed yet, and it says so. The apply is offered only when there is something
 * to do, the namespace could be read and this user may change the instance, and it asks once more.
 */
export function PlanSection({
  answer,
  canApply,
  applying,
  moved,
  onApply,
}: {
  answer: PlanAnswer;
  canApply: boolean;
  applying: boolean;
  /** The plan shown replaced the one the person applied: an apply was refused for it. */
  moved: boolean;
  onApply: () => void;
}) {
  const { plan } = answer;
  const [confirming, setConfirming] = useState(false);
  const steps = plan.actions.length;
  return (
    <Section
      id="namespace-plan"
      title={`The plan for ${plan.namespace}`}
      note={plan.production ? `${plan.production}, ${plan.production_state}.` : undefined}
    >
      <Stack gap="md">
        {moved ? (
          <Alert color="yellow" variant="light" role="status">
            This namespace or the site profile changed since you read it, so nothing was changed. This is the
            new plan.
          </Alert>
        ) : null}
        {plan.error ? (
          <Alert color="red" variant="light" role="alert">
            {plan.error.includes('<PROTECT>') ? (
              <Text size="sm" mb={4}>
                This user may not read {plan.namespace}. Sign in as a user who can reach %SYS and every
                namespace involved.
              </Text>
            ) : null}
            {plan.error}
          </Alert>
        ) : (
          <Text size="sm">
            {steps
              ? 'Nothing has changed yet. This is what applying the plan would do, in this order.'
              : `Nothing to change: ${plan.namespace} is wired as the plan wants.`}
          </Text>
        )}
        {steps ? (
          <List type="ordered" size="sm" spacing={4}>
            {plan.actions.map((a) => (
              <List.Item key={a.says}>{a.says}</List.Item>
            ))}
          </List>
        ) : null}
        <Lines title="Look at these first" lines={plan.warnings} />
        <Lines title="Left for a person" lines={plan.todo} />
        {plan.operations.length ? (
          <Stack gap={4}>
            <Text fw={600} size="sm">
              What a Completed message proves at each receiver
            </Text>
            <StackTable aria-label="Receivers in this namespace" className="stack-table">
              <StackTable.Thead>
                <StackTable.Tr>
                  <StackTable.Th>Item</StackTable.Th>
                  <StackTable.Th>Reported as</StackTable.Th>
                  <StackTable.Th>Completed proves</StackTable.Th>
                </StackTable.Tr>
              </StackTable.Thead>
              <StackTable.Tbody>
                {plan.operations.map((o) => (
                  <StackTable.Tr key={o.name}>
                    <StackTable.Th scope="row">{o.name}</StackTable.Th>
                    <StackTable.Td data-label="Reported as">{o.reported_as}</StackTable.Td>
                    <StackTable.Td data-label="Completed proves">{o.proves}</StackTable.Td>
                  </StackTable.Tr>
                ))}
              </StackTable.Tbody>
            </StackTable>
          </Stack>
        ) : null}
        {steps && !plan.error ? (
          canApply ? (
            <Group>
              <Button onClick={() => setConfirming(true)} loading={applying}>
                Apply this plan…
              </Button>
            </Group>
          ) : (
            <Text size="sm" c="dimmed">
              Applying this plan changes the instance&apos;s configuration, so it needs a user holding
              %Admin_Manage.
            </Text>
          )
        ) : null}
        <ApiSource
          endpoint={`POST /api/shutter/settings/namespaces/${plan.namespace}/plan`}
          data={answer}
          label="The plan, as the API sends it"
        />
      </Stack>
      <ConfirmModal
        title={`Apply this plan to ${plan.namespace}`}
        opened={confirming}
        onClose={() => setConfirming(false)}
      >
        <Stack gap="md">
          <Text size="sm">
            {steps === 1 ? 'The 1 step above runs' : `The ${steps} steps above run`}. A running production is
            updated, not stopped. You can take the namespace off again afterwards.
          </Text>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setConfirming(false)}>
              Cancel
            </Button>
            <Button
              onClick={() => {
                setConfirming(false);
                onApply();
              }}
            >
              Apply the plan
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </Section>
  );
}
