import {
  Alert,
  Button,
  Center,
  Divider,
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
import { describeError, isApiError } from '@/lib/errors';
import { APP_NAME, APP_TAGLINE } from '@/theme';
import { BrandMark } from '@/components/BrandMark';
import { DEMO, DEMO_USER } from '@/demo';

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

  const submit = (e: FormEvent) => {
    e.preventDefault();
    signIn.mutate(
      { username: username.trim(), password },
      { onSuccess: () => navigate(from, { replace: true }) },
    );
  };
  const error = signIn.error;
  const message =
    error && isApiError(error) && (error.isUnauthorized || error.isForbidden)
      ? 'The user name or the password is wrong.'
      : error
        ? describeError(error)
        : '';

  return (
    <Center mih="100vh" p="md" style={{ background: 'var(--shutter-page)' }}>
      <Paper p="xl" w={380} shadow="sm">
        <form onSubmit={submit}>
          <Stack gap="md">
            <Stack gap={6} align="center">
              <BrandMark size={44} />
              <Title order={1} fz={24}>
                {APP_NAME}
              </Title>
              <Text size="sm" c="dimmed" ta="center">
                {APP_TAGLINE}
              </Text>
              {/* What it is for, in a line, before anyone signs in */}
              <Text size="sm" ta="center">
                For HL7 ADT feeds on InterSystems IRIS for Health: when a patient movement fails to reach a
                downstream system, Shutter investigates why and writes a fix only when its gate passes and a
                person, or the site&apos;s written policy, releases it.
              </Text>
            </Stack>
            {message ? (
              <Alert color="red" variant="light" role="alert">
                {message}
              </Alert>
            ) : null}
            {/* The demo leads with its own sign-in: a judge opening it needs no password, and the form is second. */}
            {DEMO ? (
              <>
                <Button
                  variant="filled"
                  fullWidth
                  loading={signIn.isPending}
                  onClick={() =>
                    signIn.mutate(DEMO_USER, { onSuccess: () => navigate(from, { replace: true }) })
                  }
                >
                  {DEMO_USER.username === 'demo'
                    ? 'Try the demo (live hospital, read-only)'
                    : 'Try the demo (recorded runs)'}
                </Button>
                <Divider label="or sign in as a demo user" labelPosition="center" />
              </>
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
            <Button type="submit" variant={DEMO ? 'default' : 'filled'} loading={signIn.isPending} fullWidth>
              Sign in
            </Button>
            {/* The demo users and their password only on a demo instance (the server's flag) or the recorded demo. */}
            {DEMO || health.data?.demo === true ? (
              <Text size="xs" c="dimmed">
                The demo installs two users: <b>operator</b> runs scenarios, reads cases, escalates them and
                marks them handled; <b>approver</b> can also approve or reject plans and change the site
                profile and the agent library. Their password is the installer&apos;s (<code>shutter</code>{' '}
                unless it was changed).
              </Text>
            ) : null}
          </Stack>
        </form>
      </Paper>
    </Center>
  );
}
