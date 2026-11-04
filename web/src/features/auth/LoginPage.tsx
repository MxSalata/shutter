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
import { useState, type FormEvent } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router';
import { useHealth, useMe, useSignIn } from '@/api/hooks';
import { BrandMark } from '@/components/BrandMark';
import { TechDetail } from '@/components/TechDetail';
import { describeError, isApiError } from '@/lib/errors';
import { APP_NAME } from '@/theme';
import { ProofPanel } from './ProofPanel';
import { TrialCard } from './TrialCard';

/**
 * The live sign-in page, in two halves: what Shutter is for and the proof for it (`ProofPanel`), and the password form
 * with the way into the trial under it (`TrialCard`). Trial pages never show it: the trial opens signed in, and its own
 * sign-in page (src/trial/TrialSignIn.tsx) offers roles with no password. So nothing here names a trial user.
 */
export default function LoginPage() {
  const me = useMe();
  const health = useHealth();
  const signIn = useSignIn();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from || '/scenarios';
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  if (me.data) return <Navigate to={from} replace />;

  // A demo install (the server's flag) or the contest's own instance: the proof describes its recordings. A hospital's
  // own install shows the headline and the purpose alone.
  const demo = health.data?.demo === true;

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
    <Center mih="100vh" p="md" style={{ background: 'var(--shutter-page)' }}>
      <Grid gutter="lg" maw={1080} w="100%" align="flex-start">
        <Grid.Col span={{ base: 12, md: 7 }}>
          <ProofPanel figures={demo} />
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 5 }}>
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
                  <Title order={1}>Sign in</Title>
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
                    data-autofocus
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
                  {/* The demo users and their password only on a demo instance (the server's flag). */}
                  {demo ? (
                    <>
                      <Text size="sm">
                        On the online demo, sign in as <b>demo</b> / <code>shutter</code>.
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
      </Grid>
    </Center>
  );
}
