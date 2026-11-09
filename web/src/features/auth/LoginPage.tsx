import {
  Alert,
  Button,
  Center,
  Grid,
  Group,
  Paper,
  PasswordInput,
  Stack,
  Text,
  TextInput,
  Title,
} from '@mantine/core';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router';
import { useHealth, useMe, useSignIn } from '@/api/hooks';
import { BrandMark } from '@/components/BrandMark';
import { TechDetail } from '@/components/TechDetail';
import { describeError, isApiError } from '@/lib/errors';
import { instanceLine } from '@/lib/instance';
import { PROOF } from '@/lib/proof';
import { APP_NAME } from '@/theme';
import { ProofPanel } from './ProofPanel';
import { TrialCard } from './TrialCard';

/**
 * The live sign-in page, in two halves: what Shutter is for and the proof for it (`ProofPanel`), and the password form
 * with the way into the trial under it (`TrialCard`). Trial pages never show it: the trial opens signed in, and its own
 * sign-in page (src/trial/TrialSignIn.tsx) offers roles with no password. So nothing here names a trial user.
 *
 * Under the heading, a demo install says it is a real IRIS for Health instance, and the public demo (its live hospital
 * on, as its health answer says) adds its build, its production of made-up patients, the player's cadence and the hourly
 * reset (`instanceLine`). It is plain words, on a laptop and on a phone alike.
 */
export default function LoginPage() {
  const me = useMe();
  const health = useHealth();
  const signIn = useSignIn();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from || '/home';
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  // Focus starts on User name (data-autofocus works only inside a focus trap, and this page has none), without
  // scrolling: a phone shows the proof above the form
  const userName = useRef<HTMLInputElement>(null);
  useEffect(() => userName.current?.focus({ preventScroll: true }), []);

  if (me.data) return <Navigate to={from} replace />;

  // A demo install (the server's flag) or the contest's own instance: the proof describes its recordings. A hospital's
  // own install shows the headline and the purpose alone.
  const demo = health.data?.demo === true;
  // What stands behind the page, said only as far as the instance's own health answer says it (lib/instance.ts)
  const instance = instanceLine(health.data, PROOF.recordedOn);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    signIn.mutate(
      { username: username.trim(), password },
      { onSuccess: () => navigate(from, { replace: true }) },
    );
  };
  const error = signIn.error;
  // POST /session answers 401 for a wrong password (CONTRACTS 5.1). A 403 comes from outside the API (the web
  // application's own roles, a gateway), so its reason is shown as the server gave it.
  const message =
    error && isApiError(error) && error.isUnauthorized
      ? 'The user name or the password is wrong.'
      : error
        ? describeError(error)
        : '';

  return (
    <Center
      component="main"
      id="main-content"
      mih="100vh"
      p="md"
      style={{ background: 'var(--shutter-page)' }}
    >
      <Grid gutter="lg" maw={1080} w="100%" align="flex-start">
        {/* The form first in the reading order, so its h1 and User name come before the proof; it still shows second */}
        <Grid.Col span={{ base: 12, md: 5 }} order={2}>
          <Stack gap="md">
            <Paper p={{ base: 'lg', md: 'xl' }} withBorder radius="md" shadow="xs">
              <form onSubmit={submit}>
                <Stack gap="md">
                  <Group gap="xs" visibleFrom="md" data-viewport="laptop">
                    <BrandMark size={36} />
                    <Text fw={700} fz="lg">
                      {APP_NAME}
                    </Text>
                  </Group>
                  <Stack gap={4}>
                    <Title order={1}>Sign in</Title>
                    {instance ? (
                      <Text size="sm" c="dimmed" m={0} data-testid="sign-in-instance">
                        {instance}
                      </Text>
                    ) : null}
                  </Stack>
                  {message ? (
                    <Alert color="red" variant="light" role="alert">
                      {message}
                    </Alert>
                  ) : null}
                  <TextInput
                    label="User name"
                    autoComplete="username"
                    value={username}
                    onChange={(e) => setUsername(e.currentTarget.value)}
                    required
                    ref={userName}
                  />
                  <PasswordInput
                    label="Password"
                    autoComplete="current-password"
                    value={password}
                    onChange={(e) => setPassword(e.currentTarget.value)}
                    required
                  />
                  <Button type="submit" loading={signIn.isPending} fullWidth>
                    Sign in
                  </Button>
                  {/* The demo users and their password only on a demo instance (the server's flag). An install's own
                      users come first: the online demo's user has no password on an install unless it was given one. */}
                  {demo ? (
                    <>
                      <Text size="sm">
                        Your own install: <b>approver</b> or <b>operator</b> / <code>shutter</code>.
                      </Text>
                      <Text size="sm">
                        Online demo: <b>demo</b> / <code>shutter</code>.
                      </Text>
                      <TechDetail label="Demo users" kind="explain">
                        The demo installs two users: <b>operator</b> runs scenarios, reads cases, escalates
                        them and marks them handled; <b>approver</b> can also approve or reject plans and
                        change the site profile and the agent library. Their password is the installer&apos;s
                        (<code>shutter</code> unless it was changed). They are for your own instance: the
                        online demo keeps them private.
                      </TechDetail>
                    </>
                  ) : null}
                </Stack>
              </form>
            </Paper>
            <TrialCard />
          </Stack>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 7 }} order={1}>
          <ProofPanel figures={demo} />
        </Grid.Col>
      </Grid>
    </Center>
  );
}
