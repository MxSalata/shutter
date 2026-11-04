import { Button, Center, Paper, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconTestPipe } from '@tabler/icons-react';
import { Navigate, useLocation, useNavigate } from 'react-router';
import { useMe, useSignIn } from '@/api/hooks';
import { BrandMark } from '@/components/BrandMark';
import { ErrorAlert } from '@/components/ErrorAlert';
import { ENV, rememberTrialRole, trialUser, type TrialRole } from '@/env/mode';
import { TRIAL_ROLES } from './roles';
import { APP_NAME } from '@/theme';
import { LeaveTrialButton, LeaveTrialConfirm } from './LeaveTrial';

/**
 * The trial's sign-in page, reached only by signing out (the trial opens signed in): one card per role, each a
 * "Continue" that signs that fake user in, and no password field, so no one learns to type real credentials into a
 * fake form. The live sign-in page is LoginPage; trial pages never show it.
 */
export default function TrialSignIn() {
  const me = useMe();
  const signIn = useSignIn();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from || '/home';
  if (me.data) return <Navigate to={from} replace />;
  const choose = (role: TrialRole) =>
    signIn.mutate(trialUser(role), {
      onSuccess: () => {
        rememberTrialRole(role);
        navigate(from, { replace: true });
      },
    });
  return (
    <Center mih="100vh" p="md" style={{ background: 'var(--shutter-page)' }}>
      <Paper p="xl" maw={760} w="100%" shadow="sm" className="trial-sign-in">
        <Stack gap="md">
          <Stack gap={6} align="center">
            <BrandMark size={44} />
            <Text fw={700} fz="lg">
              {APP_NAME}
            </Text>
            <Title order={1} fz={24} ta="center">
              Choose who you are in the trial
            </Title>
            <Text ta="center">No password: these are the trial&apos;s own roles.</Text>
          </Stack>
          {signIn.error ? <ErrorAlert error={signIn.error} title="The trial could not sign you in" /> : null}
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            {TRIAL_ROLES.map((r) => (
              <Paper
                key={r.role}
                withBorder
                p="md"
                component="section"
                aria-labelledby={`trial-role-${r.role}`}
              >
                <Stack gap="xs" h="100%" justify="space-between">
                  <div>
                    <Title order={2} fz="md" id={`trial-role-${r.role}`}>
                      {r.name}
                    </Title>
                    <Text size="sm">{r.can}</Text>
                  </div>
                  <Button
                    color="grape"
                    className="guide-control"
                    leftSection={<IconTestPipe size={16} aria-hidden />}
                    loading={signIn.isPending && signIn.variables?.username === r.role}
                    onClick={() => choose(r.role)}
                    aria-label={`Continue as ${r.name.toLowerCase()}`}
                  >
                    Continue
                  </Button>
                </Stack>
              </Paper>
            ))}
          </SimpleGrid>
          {ENV.canLeave ? (
            <Center>
              <LeaveTrialButton />
            </Center>
          ) : null}
        </Stack>
      </Paper>
      <LeaveTrialConfirm />
    </Center>
  );
}
