import {
  Alert,
  Anchor,
  Button,
  Group,
  Modal,
  NativeSelect,
  NumberInput,
  Stack,
  Switch,
  Text,
} from '@mantine/core';
import { IconClipboardSearch } from '@tabler/icons-react';
import { useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { newIdempotencyKey } from '@/api/client';
import { useReviewTargets, useStartReview } from '@/api/hooks';
import type { ReviewTarget } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { byEnv } from '@/env/copy';
import { describeError, isApiError } from '@/lib/errors';
import { DialogTitle } from './DialogTitle';
import { targetKey, targetLabel } from './review';

/** What a 409 wrong_state carries besides its detail: the review of that production still running. */
interface Running {
  reviewId?: string;
  state?: string;
}

/** What asking the agent does, in the live system's words and the trial's (which calls no model). */
const AGENT_NOTE = byEnv({
  live: 'It reorders within a severity tier only. A live run spends model credit, as a scenario run does; an instance without a model provider replays a recorded run.',
  trial:
    'It reorders within a severity tier only. The trial replays a recorded review, so no model is called.',
});

function StartForm({ targets, onClose }: { targets: ReviewTarget[]; onClose: () => void }) {
  const navigate = useNavigate();
  const start = useStartReview();
  const [target, setTarget] = useState(() =>
    targets.find((t) => t.own) ? targetKey(targets.find((t) => t.own)!) : '',
  );
  const [days, setDays] = useState<number | string>(7);
  const [agent, setAgent] = useState(true);
  const chosen = targets.find((t) => targetKey(t) === target) ?? targets[0];
  const windowDays = Number(days);
  const windowOk = Number.isInteger(windowDays) && windowDays >= 1 && windowDays <= 90;
  const submit = () => {
    if (!chosen || !windowOk) return;
    start.mutate(
      {
        target: { namespace: chosen.namespace, production: chosen.production, windowDays, agent },
        idempotencyKey: newIdempotencyKey(),
      },
      { onSuccess: (r) => navigate(`/reviews/${encodeURIComponent(r.reviewId)}`) },
    );
  };
  const running =
    isApiError(start.error) && start.error.code === 'wrong_state'
      ? (start.error.body as Running | null)
      : null;
  return (
    <Stack gap="sm">
      <Text size="sm" c="dimmed">
        Shutter&apos;s own production, or a watched one its cases came from. The checks are deterministic; the
        agent only ranks and explains.
      </Text>
      <Group gap="sm" align="flex-end" wrap="wrap">
        <NativeSelect
          label="Production"
          value={chosen ? targetKey(chosen) : ''}
          onChange={(e) => setTarget(e.currentTarget.value)}
          data={targets.map((t) => ({ value: targetKey(t), label: targetLabel(t) }))}
          w={{ base: '100%', sm: 360 }}
        />
        <NumberInput
          label="Window (days)"
          value={days}
          onChange={setDays}
          min={1}
          max={90}
          allowDecimal={false}
          error={windowOk ? undefined : 'From 1 to 90 days'}
          w={140}
        />
      </Group>
      <Switch
        label="Ask the agent to rank and explain the findings"
        description={AGENT_NOTE}
        checked={agent}
        onChange={(e) => setAgent(e.currentTarget.checked)}
      />
      {chosen && chosen.productionState !== 'running' ? (
        <Text size="sm" c="dimmed">
          {chosen.production} is {chosen.productionState}: the review still reads its configuration.
        </Text>
      ) : null}
      {start.error ? (
        <Alert color="red" variant="light" role="alert" title="The review did not start">
          <Text size="sm">{describeError(start.error)}</Text>
          {running?.reviewId ? (
            <Anchor component={Link} to={`/reviews/${encodeURIComponent(running.reviewId)}`} size="sm">
              Follow review {running.reviewId}
            </Anchor>
          ) : null}
        </Alert>
      ) : null}
      <Group justify="flex-end">
        <Button variant="default" onClick={onClose}>
          Cancel
        </Button>
        <Button
          leftSection={<IconClipboardSearch size={16} />}
          onClick={submit}
          loading={start.isPending}
          disabled={!chosen || !windowOk}
        >
          Start the review
        </Button>
      </Group>
    </Stack>
  );
}

/** The productions to choose from, or why there are none to choose. */
function StartBody({ onClose }: { onClose: () => void }) {
  const targets = useReviewTargets();
  if (targets.isPending) return <PageSkeleton label="Loading the productions…" />;
  if (targets.isError)
    return (
      <ErrorAlert
        error={targets.error}
        title="The productions could not be read"
        onRetry={() => void targets.refetch()}
      />
    );
  if (targets.data.items.length === 0)
    return (
      <Text size="sm" c="dimmed">
        No production to review.
      </Text>
    );
  return <StartForm targets={targets.data.items} onClose={onClose} />;
}

/**
 * "Start a review": the button, and the form in a modal. The button carries the guide's try-it mark. In the trial it is
 * offered and replays a recorded review; the dialog says where the action takes effect, beside its title.
 */
export function StartReview() {
  const [opened, setOpened] = useState(false);
  return (
    <>
      <Button
        leftSection={<IconClipboardSearch size={16} />}
        onClick={() => setOpened(true)}
        data-tour-action="start-review"
      >
        Start a review
      </Button>
      <Modal
        opened={opened}
        onClose={() => setOpened(false)}
        title={<DialogTitle>Start a review</DialogTitle>}
      >
        {opened ? <StartBody onClose={() => setOpened(false)} /> : null}
      </Modal>
    </>
  );
}
