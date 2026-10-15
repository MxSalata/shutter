import {
  ActionIcon,
  AppShell,
  Badge,
  Burger,
  Group,
  Menu,
  NavLink,
  Text,
  Tooltip,
  UnstyledButton,
  useComputedColorScheme,
  useMantineColorScheme,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import {
  IconBooks,
  IconFlask2,
  IconHeartbeat,
  IconListDetails,
  IconLogout,
  IconMoon,
  IconSettings,
  IconSun,
  IconUserCircle,
} from '@tabler/icons-react';
import { Suspense } from 'react';
import { Link, NavLink as RouterNavLink, Outlet, ScrollRestoration, useNavigate } from 'react-router';
import { useMe, useSignOut } from '@/api/hooks';
import { APP_NAME } from '@/theme';
import { BrandMark } from '@/components/BrandMark';
import { PageSkeleton } from '@/components/PageSkeleton';

const NAV = [
  {
    to: '/scenarios',
    label: 'Scenarios',
    icon: IconFlask2,
    hint: 'Play a failure and watch Interlock handle it',
  },
  { to: '/cases', label: 'Cases', icon: IconListDetails, hint: 'Every failed message Interlock has opened' },
  { to: '/library', label: 'Agent library', icon: IconBooks, hint: 'The board members and the coordinator' },
  {
    to: '/settings',
    label: 'Settings and costs',
    icon: IconSettings,
    hint: 'Agent items, models, prices, costs',
  },
  { to: '/health', label: 'Health', icon: IconHeartbeat, hint: "The installation's readiness checks" },
];

function ColorSchemeToggle() {
  const { setColorScheme } = useMantineColorScheme();
  const computed = useComputedColorScheme('light');
  const next = computed === 'dark' ? 'light' : 'dark';
  return (
    <Tooltip label={`Switch to the ${next} theme`}>
      <ActionIcon
        variant="subtle"
        size="lg"
        aria-label={`Switch to the ${next} theme`}
        onClick={() => setColorScheme(next)}
      >
        {computed === 'dark' ? <IconSun size={18} /> : <IconMoon size={18} />}
      </ActionIcon>
    </Tooltip>
  );
}

function UserMenu() {
  const me = useMe().data;
  const signOut = useSignOut();
  const navigate = useNavigate();
  if (!me) return null;
  const roles = [me.operator ? 'operator' : null, me.approver ? 'approver' : null].filter(
    Boolean,
  ) as string[];
  return (
    <Menu position="bottom-end" width={240}>
      <Menu.Target>
        <UnstyledButton aria-label={`Signed in as ${me.username}`}>
          <Group gap={6} wrap="nowrap">
            <IconUserCircle size={20} stroke={1.6} />
            <Text size="sm" fw={500} visibleFrom="xs">
              {me.username}
            </Text>
          </Group>
        </UnstyledButton>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Label>Signed in as {me.username}</Menu.Label>
        <Group gap={4} px="sm" pb="xs">
          {roles.length ? (
            roles.map((r) => (
              <Badge key={r} size="sm" color={r === 'approver' ? 'grape' : 'indigo'}>
                {r}
              </Badge>
            ))
          ) : (
            <Text size="xs" c="dimmed">
              Read only: no operator or approver role
            </Text>
          )}
        </Group>
        <Menu.Divider />
        <Menu.Item
          leftSection={<IconLogout size={16} />}
          onClick={() =>
            signOut.mutate(undefined, { onSettled: () => navigate('/login', { replace: true }) })
          }
        >
          Sign out
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  );
}

export function AppLayout() {
  const [opened, { toggle, close }] = useDisclosure();
  return (
    <AppShell
      header={{ height: 56 }}
      navbar={{ width: 230, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" aria-label="Menu" />
            <UnstyledButton component={Link} to="/scenarios" aria-label={`${APP_NAME}: home`}>
              <Group gap={8} wrap="nowrap">
                <BrandMark size={28} />
                <Text fw={700} fz="lg" style={{ letterSpacing: -0.3 }}>
                  {APP_NAME}
                </Text>
              </Group>
            </UnstyledButton>
          </Group>
          <Group gap="xs" wrap="nowrap">
            <ColorSchemeToggle />
            <UserMenu />
          </Group>
        </Group>
      </AppShell.Header>
      <AppShell.Navbar p="xs" aria-label="Main">
        {NAV.map((item) => (
          <NavLink
            key={item.to}
            component={RouterNavLink}
            to={item.to}
            label={item.label}
            description={item.hint}
            leftSection={<item.icon size={18} stroke={1.6} />}
            onClick={close}
            styles={{ description: { lineHeight: 1.3 } }}
          />
        ))}
      </AppShell.Navbar>
      <AppShell.Main id="main">
        {/* A new page starts at its top; Back returns to where the previous one was left. */}
        <ScrollRestoration />
        <Suspense fallback={<PageSkeleton />}>
          <Outlet />
        </Suspense>
      </AppShell.Main>
    </AppShell>
  );
}
