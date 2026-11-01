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
import type { ReactNode } from 'react';
import { useDisclosure } from '@mantine/hooks';
import {
  IconBooks,
  IconBuildingHospital,
  IconChartBar,
  IconClipboardSearch,
  IconContrast,
  IconDeviceDesktop,
  IconFlask2,
  IconHeartbeat,
  IconListDetails,
  IconLogout,
  IconMoon,
  IconPalette,
  IconPlayerPlay,
  IconSettings,
  IconStack2,
  IconSun,
  IconUserCircle,
} from '@tabler/icons-react';
import { Suspense } from 'react';
import { Link, NavLink as RouterNavLink, Outlet, ScrollRestoration, useNavigate } from 'react-router';
import { useMe, useSignOut, useSiteProfile } from '@/api/hooks';
import { displayZone, setDisplayZone } from '@/lib/format';
import { APP_NAME } from '@/theme';
import { BrandMark } from '@/components/BrandMark';
import { PageSkeleton } from '@/components/PageSkeleton';
import { useAppearance, type ContrastSetting, type PaletteSetting } from '@/stores/appearance';
import { useResolvedContrast } from './useApplyAppearance';
import { MAIN_ID, SkipLink } from './SkipLink';
import { TRIAL } from '@/env/mode';
import { Guide } from '@/features/guide/Guide';
import { LiveBanner } from './LiveBanner';
import { HelpMenu } from '@/features/guide/HelpMenu';

/**
 * The navigation in three groups, by what a visit is for: running and following the recovery, configuring it, and
 * the evidence about the installation and the board. Short labels only; each page's introduction says what it is.
 */
const NAV = [
  {
    group: 'Operate',
    items: [
      { to: '/scenarios', label: 'Scenarios', icon: IconFlask2 },
      { to: '/cases', label: 'Cases', icon: IconListDetails },
      { to: '/incidents', label: 'Incidents', icon: IconStack2 },
      { to: '/reviews', label: 'Production review', icon: IconClipboardSearch },
    ],
  },
  {
    group: 'Configure',
    items: [
      { to: '/site-profile', label: 'Site profile', icon: IconBuildingHospital },
      { to: '/library', label: 'Agent library', icon: IconBooks },
      { to: '/settings', label: 'Settings and costs', icon: IconSettings },
    ],
  },
  {
    group: 'Evidence',
    items: [
      { to: '/evaluation', label: 'Evaluation', icon: IconChartBar },
      { to: '/health', label: 'Health', icon: IconHeartbeat },
    ],
  },
];

type ThemeChoice = 'light' | 'pastel' | 'dark' | 'auto';

/**
 * Light / Pastel / Dark / System (a way back to following the OS) and the independent contrast
 * axis. Pastel is the light scheme with the pastel palette; the other three reset the palette, so
 * System follows the OS between Light and Dark and exactly one entry is ever current.
 */
function AppearanceMenu() {
  const { colorScheme, setColorScheme } = useMantineColorScheme();
  const computed = useComputedColorScheme('light');
  const contrast = useAppearance((s) => s.contrast);
  const setContrast = useAppearance((s) => s.setContrast);
  const palette = useAppearance((s) => s.palette);
  const setPalette = useAppearance((s) => s.setPalette);
  const resolved = useResolvedContrast();
  const themes: { value: ThemeChoice; label: string; icon: ReactNode }[] = [
    { value: 'light', label: 'Light', icon: <IconSun size={16} /> },
    { value: 'pastel', label: 'Pastel', icon: <IconPalette size={16} /> },
    { value: 'dark', label: 'Dark', icon: <IconMoon size={16} /> },
    { value: 'auto', label: 'System', icon: <IconDeviceDesktop size={16} /> },
  ];
  const current: ThemeChoice = colorScheme === 'light' && palette === 'pastel' ? 'pastel' : colorScheme;
  const choose = (value: ThemeChoice) => {
    setColorScheme(value === 'pastel' ? 'light' : value);
    const next: PaletteSetting = value === 'pastel' ? 'pastel' : 'default';
    if (next !== palette) setPalette(next);
  };
  const contrasts: { value: ContrastSetting; label: string }[] = [
    { value: 'auto', label: 'System' },
    { value: 'normal', label: 'Normal' },
    { value: 'high', label: 'High' },
  ];
  return (
    <Menu shadow="md" width={220} position="bottom-end" withinPortal>
      <Menu.Target>
        <Tooltip label="Appearance">
          <ActionIcon variant="subtle" color="gray" size="lg" aria-label="Appearance">
            {resolved === 'high' ? (
              <IconContrast size={18} />
            ) : computed === 'dark' ? (
              <IconSun size={18} />
            ) : (
              <IconMoon size={18} />
            )}
          </ActionIcon>
        </Tooltip>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Label>Theme</Menu.Label>
        {themes.map((t) => (
          <Menu.Item
            key={t.value}
            leftSection={t.icon}
            onClick={() => choose(t.value)}
            // The menu focuses its first item on opening, and focus looks like the selection: start on the current one
            data-autofocus={current === t.value || undefined}
            aria-label={`${t.label}${current === t.value ? ' (current theme)' : ''}`}
            rightSection={current === t.value ? '●' : undefined}
          >
            {t.label}
          </Menu.Item>
        ))}
        <Menu.Divider />
        <Menu.Label>Contrast</Menu.Label>
        {contrasts.map((c) => (
          <Menu.Item
            key={c.value}
            leftSection={<IconContrast size={16} />}
            onClick={() => setContrast(c.value)}
            aria-label={`${c.label}${contrast === c.value ? ' (current contrast)' : ''}`}
            rightSection={contrast === c.value ? '●' : undefined}
          >
            {c.label}
          </Menu.Item>
        ))}
      </Menu.Dropdown>
    </Menu>
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
              <Badge key={r} size="sm" color="gray" variant="outline">
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
  // Times show in the feed's zone (the site profile's feed.time_zone); the page renders again if it changes
  // As the server reads the feed (SiteProfile.FeedTimeZone): a stored profile that doesn't answer the question keeps
  // UTC; until the profile has loaded, the questionnaire's default.
  const profile = useSiteProfile().data?.profile;
  setDisplayZone(profile ? profile.feed?.time_zone || 'UTC' : undefined);
  return (
    <AppShell
      header={{ height: 56 }}
      navbar={{ width: 230, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      padding="md"
      styles={{
        main: { background: 'var(--shutter-page)' },
        navbar: { background: 'var(--shutter-navbar)' },
        header: { background: 'var(--shutter-header)' },
      }}
    >
      <SkipLink />
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
            {TRIAL ? (
              <Tooltip
                label="Recorded runs: this page replays a real run's data and reaches no IRIS instance"
                multiline
                maw={280}
              >
                <Badge
                  size="sm"
                  variant="filled"
                  color="gray"
                  leftSection={<IconPlayerPlay size={12} aria-hidden />}
                  tabIndex={0}
                >
                  DEMO
                </Badge>
              </Tooltip>
            ) : null}
            <HelpMenu />
            <AppearanceMenu />
            <UserMenu />
          </Group>
        </Group>
      </AppShell.Header>
      <AppShell.Navbar p="xs" aria-label="Main">
        {NAV.map(({ group, items }) => (
          <div key={group} role="group" aria-labelledby={`nav-${group}`} className="nav-group">
            <Text id={`nav-${group}`} size="xs" fw={600} c="dimmed" tt="uppercase" px="sm" pt="sm" pb={4}>
              {group}
            </Text>
            {items.map((item) => (
              <NavLink
                key={item.to}
                component={RouterNavLink}
                to={item.to}
                label={item.label}
                leftSection={<item.icon size={18} stroke={1.6} className="nav-icon" />}
                onClick={close}
              />
            ))}
          </div>
        ))}
      </AppShell.Navbar>
      {/* The skip link's target: focusable by script only, so it is no tab stop of its own. */}
      <AppShell.Main id={MAIN_ID} tabIndex={-1} style={{ outline: 'none' }}>
        {/* A new page starts at its top; Back returns to where the previous one was left. */}
        <ScrollRestoration />
        <LiveBanner />
        <Suspense fallback={<PageSkeleton />}>
          <Outlet key={displayZone()} />
        </Suspense>
      </AppShell.Main>
      <Guide />
    </AppShell>
  );
}
