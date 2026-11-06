import {
  Alert,
  Anchor,
  Button,
  Checkbox,
  Code,
  CopyButton,
  Group,
  NativeSelect,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { IconPlugConnected } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useCan } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { TRIAL } from '@/env/mode';
import { isApiError } from '@/lib/errors';
import {
  credentialCommand,
  useApplyPlan,
  useNamespaces,
  useReadPlan,
  useRemove,
  useSendTest,
  usedOptions,
  type ApplyAnswer,
  type PlanAnswer,
  type PlanOptions,
  type RemoveAnswer,
  type TestAnswer,
  type WatchedNamespace,
} from './onboarding';
import { Lines, PlanSection } from './PlanSection';
import { RemoveModal } from './RemoveModal';

/** The options a plan can be read with, the helper's own, for the namespaces the defaults do not suit. */
function OptionsForm({ value, onChange }: { value: PlanOptions; onChange: (o: PlanOptions) => void }) {
  const field = (name: keyof PlanOptions, label: string, description: string) => (
    <TextInput
      label={label}
      description={description}
      value={String(value[name] ?? '')}
      onChange={(e) => onChange({ ...value, [name]: e.currentTarget.value })}
    />
  );
  return (
    <TechDetail label="Options" kind="explain">
      <Stack gap="sm">
        <Text size="sm">Every option is optional, and changing one means reading the plan again.</Text>
        <Checkbox
          label="Turn AlertOnError on for the receivers that have it off"
          checked={!!value.alert_on_error}
          onChange={(e) => onChange({ ...value, alert_on_error: e.currentTarget.checked })}
        />
        <SimpleGrid cols={{ base: 1, sm: 2 }}>
          {field(
            'receivers',
            'Receivers',
            'Item names, comma-separated, when not every HL7 operation is one',
          )}
          {field('production', 'Production', 'When several are defined and none runs')}
          {field('shutter_host', 'Shutter host', 'When Shutter is not on this host')}
          {field('shutter_port', 'Shutter port', "This instance's web port unless said")}
          {field(
            'ssl_config',
            'SSL configuration',
            'Needed for any other host: the sign-in would go in clear',
          )}
          {field('credential', 'Credential', 'ShutterIntake unless said')}
        </SimpleGrid>
      </Stack>
    </TechDetail>
  );
}

function CopyCommand({ command }: { command: string }) {
  return (
    <Group gap="xs" wrap="wrap">
      <Code>{command}</Code>
      <CopyButton value={command} timeout={1500}>
        {({ copied, copy }) => (
          <Button size="xs" variant="default" onClick={copy}>
            {copied ? 'Copied' : 'Copy'}
          </Button>
        )}
      </CopyButton>
    </Group>
  );
}

/**
 * What stays for a person after an apply. `profileHelp` is where help with filling in the drafted receivers goes, beside
 * the link to the site profile, for a screen that offers it.
 */
function NextSteps({
  ns,
  needsCredential,
  profileHelp,
}: {
  ns: string;
  needsCredential: boolean;
  profileHelp?: ReactNode;
}) {
  return (
    <Section id="namespace-next" title={`Next steps for ${ns}`}>
      <Stack gap="sm">
        {needsCredential ? (
          <Stack gap={4}>
            <Text size="sm">
              Give the forwarder its sign-in, in a terminal in Shutter&apos;s namespace, as a user who may
              manage security. It asks for the password with the echo off, and the password never passes
              through this app.
            </Text>
            <CopyCommand command={credentialCommand(ns)} />
          </Stack>
        ) : null}
        <Text size="sm">
          Then send a test failure from the table above: a case opens and nothing goes to a receiver.
        </Text>
        <Stack gap={4}>
          <Text size="sm">
            Review each drafted receiver in the{' '}
            <Anchor component={Link} to="/site-profile" underline="always">
              Site profile
            </Anchor>
            : its system, its category, its tier and its team. Until then nothing can be resent to it.
          </Text>
          {profileHelp}
        </Stack>
      </Stack>
    </Section>
  );
}

function TestResult({ answer }: { answer: TestAnswer }) {
  if (answer.ok)
    return (
      <Alert color="green" variant="light" role="status">
        <Text size="sm">
          A test case opened:{' '}
          {TRIAL ? (
            answer.case
          ) : (
            <Anchor component={Link} to={`/cases/${answer.case}`} underline="always">
              {answer.case}
            </Anchor>
          )}
          . Nothing went to a receiver.
        </Text>
      </Alert>
    );
  return (
    <Alert color="red" variant="light" role="alert">
      <Text size="sm">{answer.advice || answer.error}</Text>
    </Alert>
  );
}

function WatchedRow({
  w,
  canApply,
  onPlan,
  onTest,
  testing,
  onRemove,
}: {
  w: WatchedNamespace;
  canApply: boolean;
  onPlan: () => void;
  onTest: () => void;
  testing: boolean;
  onRemove: () => void;
}) {
  return (
    <StackTable.Tr>
      <StackTable.Th scope="row">{w.namespace}</StackTable.Th>
      <StackTable.Td data-label="Production">
        {w.production ? `${w.production}, ${w.production_state}` : 'Not read'}
      </StackTable.Td>
      <StackTable.Td data-label="State">
        {w.ok ? (
          <StatusBadge tone="positive" label={w.onboarded ? 'Watched' : 'Named by a case'} />
        ) : (
          <Stack gap={4}>
            <StatusBadge tone="attention" label={`${w.problems.length} to look at`} />
            {w.problems.map((p) => (
              <Text size="sm" key={p}>
                {p}
              </Text>
            ))}
          </Stack>
        )}
      </StackTable.Td>
      <StackTable.Td data-label="Actions">
        <Group gap="xs" wrap="wrap">
          <Button size="xs" variant="default" onClick={onPlan}>
            Plan
          </Button>
          {w.onboarded ? (
            <Button size="xs" variant="default" onClick={onTest} loading={testing}>
              Send a test failure
            </Button>
          ) : null}
          {w.onboarded && canApply ? (
            <Button size="xs" variant="default" onClick={onRemove}>
              Take off…
            </Button>
          ) : null}
        </Group>
      </StackTable.Td>
    </StackTable.Tr>
  );
}

/**
 * Which of the instance's namespaces report their failures to Shutter, and how to add one, for someone who does not
 * write SQL. It does what `Shutter.Setup_OnboardPlan`, `_OnboardApply`, `_OnboardTest` and `_OnboardRemove` do, through
 * the same helpers (CONTRACTS 11.1): the plan comes first, nothing changes until a person applies it, and what is applied
 * is what they read. In the trial every answer is a replay of a recording.
 */
export default function NamespacesPage() {
  const can = useCan();
  const list = useNamespaces(can.configure);
  const read = useReadPlan();
  const apply = useApplyPlan();
  const test = useSendTest();
  const remove = useRemove();
  const [chosen, setChosen] = useState('');
  const [options, setOptions] = useState<PlanOptions>({});
  const [answer, setAnswer] = useState<PlanAnswer | null>(null);
  const [planned, setPlanned] = useState<PlanOptions>({});
  const [moved, setMoved] = useState(false);
  const [applied, setApplied] = useState<{
    ns: string;
    answer: ApplyAnswer;
    needsCredential: boolean;
  } | null>(null);
  const [tested, setTested] = useState<{ ns: string; answer: TestAnswer } | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [removed, setRemoved] = useState<{ ns: string; answer: RemoveAnswer } | null>(null);

  const available = list.data?.available ?? [];
  const watched = (list.data?.watched ?? []).filter((w) => !w.removed);
  const picked = chosen || available[0]?.namespace || '';

  const readPlan = (ns: string) => {
    const sent = usedOptions(options);
    setAnswer(null);
    setMoved(false);
    setApplied(null);
    setRemoved(null);
    read.mutate(
      { ns, options: sent },
      {
        onSuccess: (a) => {
          setAnswer(a);
          setPlanned(sent);
        },
      },
    );
  };

  // A plan is the answer to its options, so another option takes it away
  const changeOptions = (o: PlanOptions) => {
    setOptions(o);
    setAnswer(null);
    setMoved(false);
  };

  const applyPlan = () => {
    if (!answer) return;
    const ns = answer.plan.namespace;
    apply.mutate(
      { ns, options: planned, digest: answer.digest },
      {
        onSuccess: (a) => {
          setApplied({ ns, answer: a, needsCredential: !answer.plan.wired.credential });
          setAnswer(null);
        },
        onError: (e) => {
          if (isApiError(e) && e.code === 'plan_changed') {
            setAnswer(e.body as PlanAnswer);
            setMoved(true);
          }
        },
      },
    );
  };

  const applyRefused = apply.isError && !(isApiError(apply.error) && apply.error.code === 'plan_changed');

  return (
    <>
      <PageHeader
        title="Watched namespaces"
        icon={IconPlugConnected}
        hue="cyan"
        lead="Which namespaces report their failures to Shutter. A plan shows what would change, and nothing changes until you apply it."
        details="The same helpers as the SQL procedures Shutter.Setup_OnboardPlan, _OnboardApply, _OnboardTest and _OnboardRemove (docs/INSTALL.md, section 9). An apply brings back the plan's digest, and is refused if the plan has moved since."
        meta={
          <Anchor component={Link} to="/settings" size="sm" underline="always">
            Settings and costs
          </Anchor>
        }
      />
      <Stack gap="md">
        {TRIAL ? (
          <Alert color="blue" variant="light">
            <Text size="sm">
              Replayed from a recording of a stock instance
              {list.data?.recordedAt ? `, made on ${list.data.recordedAt.slice(0, 10)}` : ''}. Nothing here
              reaches a production. The recording has the terminal step for the sign-in done, since it
              can&apos;t be tried here.
            </Text>
          </Alert>
        ) : null}
        {!can.configure ? (
          <Text size="sm">
            An approver who may change the site reads the plans and onboards namespaces here.
          </Text>
        ) : null}
        {can.configure && list.isPending ? <PageSkeleton label="Reading the namespaces…" /> : null}
        {list.isError ? (
          <ErrorAlert
            error={list.error}
            title="The namespaces could not be read"
            onRetry={() => void list.refetch()}
          />
        ) : null}
        {list.data ? (
          <>
            <Section id="namespaces-watched" title="Watched now">
              {watched.length ? (
                <StackTable aria-label="Watched namespaces" className="stack-table">
                  <StackTable.Thead>
                    <StackTable.Tr>
                      <StackTable.Th>Namespace</StackTable.Th>
                      <StackTable.Th>Production</StackTable.Th>
                      <StackTable.Th>State</StackTable.Th>
                      <StackTable.Th>Actions</StackTable.Th>
                    </StackTable.Tr>
                  </StackTable.Thead>
                  <StackTable.Tbody>
                    {watched.map((w) => (
                      <WatchedRow
                        key={w.namespace}
                        w={w}
                        canApply={list.data.canApply}
                        onPlan={() => readPlan(w.namespace)}
                        onTest={() =>
                          test.mutate(w.namespace, {
                            onSuccess: (a) => setTested({ ns: w.namespace, answer: a }),
                          })
                        }
                        testing={test.isPending && test.variables === w.namespace}
                        onRemove={() => setRemoving(w.namespace)}
                      />
                    ))}
                  </StackTable.Tbody>
                </StackTable>
              ) : (
                <Text size="sm">None yet. Read a plan below to add one.</Text>
              )}
              {tested ? (
                <Stack gap={4} mt="sm">
                  <TestResult answer={tested.answer} />
                </Stack>
              ) : null}
              {test.isError ? <ErrorAlert error={test.error} title="The test could not be sent" /> : null}
            </Section>

            <Section
              id="namespaces-add"
              title="Add a namespace"
              note="Namespaces with Interoperability enabled, other than Shutter's own."
            >
              <Stack gap="sm">
                {available.length ? (
                  <Group align="flex-end" wrap="wrap">
                    <NativeSelect
                      label="Namespace"
                      data={available.map((a) => a.namespace)}
                      value={picked}
                      onChange={(e) => {
                        setChosen(e.currentTarget.value);
                        setAnswer(null);
                        setMoved(false);
                      }}
                    />
                    <Button onClick={() => readPlan(picked)} loading={read.isPending}>
                      Read the plan
                    </Button>
                  </Group>
                ) : (
                  <Text size="sm">No other namespace has Interoperability enabled.</Text>
                )}
                {TRIAL ? null : <OptionsForm value={options} onChange={changeOptions} />}
              </Stack>
            </Section>

            {read.isError ? <ErrorAlert error={read.error} title="The plan could not be read" /> : null}
            {answer ? (
              <PlanSection
                key={answer.digest}
                answer={answer}
                canApply={list.data.canApply}
                applying={apply.isPending}
                moved={moved}
                onApply={applyPlan}
              />
            ) : null}
            {applyRefused ? <ErrorAlert error={apply.error} title="The plan was not applied" /> : null}

            {applied ? (
              <>
                <Section id="namespace-applied" title={`What changed in ${applied.ns}`}>
                  <Stack gap="sm">
                    {applied.answer.error ? (
                      <Alert color="red" variant="light" role="alert">
                        {applied.answer.error}
                      </Alert>
                    ) : null}
                    {applied.answer.unchanged ? <Text size="sm">{applied.answer.unchanged}</Text> : null}
                    <Lines title="Changed" lines={applied.answer.changed} />
                    <Lines title="Look at these" lines={applied.answer.warnings} />
                  </Stack>
                </Section>
                {applied.answer.ok ? (
                  <NextSteps ns={applied.ns} needsCredential={applied.needsCredential} />
                ) : null}
              </>
            ) : null}

            {removed ? (
              <Section id="namespace-removed" title={`Taken off ${removed.ns}`}>
                <Stack gap="sm">
                  {removed.answer.error ? (
                    <Alert color="red" variant="light" role="alert">
                      {removed.answer.error}
                    </Alert>
                  ) : null}
                  <Lines title="Taken off" lines={removed.answer.removed} />
                  <Lines title="Stays" lines={removed.answer.kept} />
                </Stack>
              </Section>
            ) : null}
            {remove.isError ? (
              <ErrorAlert error={remove.error} title="The namespace was not taken off" />
            ) : null}
          </>
        ) : null}
      </Stack>
      {removing !== null ? (
        <RemoveModal
          ns={removing}
          onClose={() => setRemoving(null)}
          onRemove={(unmap, credential) => {
            const ns = removing;
            setRemoving(null);
            setAnswer(null);
            setApplied(null);
            remove.mutate({ ns, unmap, credential }, { onSuccess: (a) => setRemoved({ ns, answer: a }) });
          }}
        />
      ) : null}
    </>
  );
}
