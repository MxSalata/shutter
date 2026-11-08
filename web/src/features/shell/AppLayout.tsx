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
import { useSyncExternalStore, type CSSProperties, type ReactNode } from 'react';
import { useDisclosure } from '@mantine/hooks';
import {
  IconContrast,
  IconHome2,
  IconDeviceDesktop,
  IconExternalLink,
  IconLogout,
  IconMoon,
  IconPalette,
  IconSun,
  IconUserCircle,
} from '@tabler/icons-react';
import { Suspense } from 'react';
import {
  Link,
  NavLink as RouterNavLink,
  Outlet,
  ScrollRestoration,
  useLocation,
  useNavigate,
} from 'react-router';
import { useMe, useSignOut, useSiteProfile } from '@/api/hooks';
import { displayZone, setDisplayZone } from '@/lib/format';
import { APP_NAME } from '@/theme';
import { BrandMark } from '@/components/BrandMark';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DetailSwitch } from '@/components/DetailSwitch';
import { useAppearance, type ContrastSetting, type PaletteSetting } from '@/stores/appearance';
import { hueVar } from '@/lib/hues';
import { useResolvedContrast } from './useApplyAppearance';
import { PORTAL_PAGE, useNeedAPerson, usePortalPage, useSections } from './sections';
import { MAIN_ID, SkipLink } from './SkipLink';
import { ENV } from '@/env/mode';
import { LiveHelpMenu } from '@/features/guide/LiveHelpMenu';
import { LiveWelcome } from '@/trial/LiveWelcome';
import { trialChrome } from '@/trial/slot';
import { bannerForm } from '@/trial/visit';
import { LiveBanner } from './LiveBanner';

/**
 * The count beside Cases: how many cases need a person, from the same queries as the Cases page's tiles. Nothing at
 * 0 or while any of them is still loading, so it never shows a partial sum.
 */
export function NavCount() {
  const n = useNeedAPerson();
  if (!n) return null;
  return (
    <Badge
      size="sm"
      color="yellow"
      variant="light"
      className="nav-count"
      aria-label={`${n} ${n === 1 ? 'case needs' : 'cases need'} a person`}
    >
      {n}
    </Badge>
  );
}

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
            aria-label={`${t.value === 'auto' ? 'System theme' : t.label}${current === t.value ? ' (current theme)' : ''}`}
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
            aria-label={`${c.value === 'auto' ? 'System contrast' : c.label}${contrast === c.value ? ' (current contrast)' : ''}`}
            rightSection={contrast === c.value ? '●' : undefined}
          >
            {c.label}
          </Menu.Item>
        ))}
      </Menu.Dropdown>
    </Menu>
  );
}

/** The id of the user menu's trial-only line (the help menu has its own). */
const TRIAL_ONLY_USER_ID = 'trial-only-note-user';

/**
 * The user menu. In a trial page the user is the trial's own ("approver (trial user)"), with Switch trial role and
 * Leave trial beside Sign out; in the demo build, which has no live system, a line saying the copy is the trial only
 * stands where Leave trial would.
 */
function UserMenu() {
  const me = useMe().data;
  const signOut = useSignOut();
  const navigate = useNavigate();
  const chrome = trialChrome();
  if (!me) return null;
  const roles = [me.operator ? 'operator' : null, me.approver ? 'approver' : null].filter(
    Boolean,
  ) as string[];
  const name = chrome ? `${me.username} (trial user)` : me.username;
  return (
    <Menu position="bottom-end" width={260}>
      <Menu.Target>
        <UnstyledButton aria-label={`Signed in as ${name}`}>
          <Group gap={6} wrap="nowrap">
            <IconUserCircle size={20} stroke={1.6} />
            <Text size="sm" fw={500} visibleFrom="xs">
              {name}
            </Text>
          </Group>
        </UnstyledButton>
      </Menu.Target>
      <Menu.Dropdown aria-describedby={chrome && !ENV.canLeave ? TRIAL_ONLY_USER_ID : undefined}>
        <Menu.Label>Signed in as {name}</Menu.Label>
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
        {chrome ? (
          <>
            <Menu.Divider />
            <chrome.TrialRoleItems />
            <Menu.Divider />
            {ENV.canLeave ? <chrome.LeaveTrialItem /> : <chrome.TrialOnlyNote id={TRIAL_ONLY_USER_ID} />}
          </>
        ) : null}
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

/** The way to the demo's page inside IRIS: leaves the app, so it opens a new tab and says so. */
function PortalNavLink({ onClick }: { onClick: () => void }) {
  const shown = usePortalPage();
  if (!shown) return null;
  const I = PORTAL_PAGE.icon;
  return (
    <div className="nav-group">
      <NavLink
        component="a"
        href={PORTAL_PAGE.href}
        target="_blank"
        rel="noreferrer"
        label={PORTAL_PAGE.label}
        aria-label={`${PORTAL_PAGE.label} (opens in a new tab)`}
        className="nav-link"
        style={{ '--nav-icon': hueVar(PORTAL_PAGE.hue) } as CSSProperties}
        leftSection={<I size={18} stroke={1.6} className="nav-icon" aria-hidden />}
        rightSection={<IconExternalLink size={14} aria-hidden />}
        onClick={onClick}
      />
    </div>
  );
}

/** Whether a navigation entry is the current page's section: its page, or a page under it (a case under Cases). */
const isActive = (pathname: string, to: string) => pathname === to || pathname.startsWith(`${to}/`);

/**
 * The frame of every signed-in page: the header (in a trial page, the trial's banner above its row), the navigation
 * and the page. A trial page adds its chrome from the chunk only trial pages load (src/trial/chrome.tsx), and the
 * guide, which runs only there; a live page offers the trial instead, once, in LiveWelcome.
 */
export function AppLayout() {
  const [opened, { toggle, close }] = useDisclosure();
  const { pathname } = useLocation();
  const chrome = trialChrome();
  const banner = useSyncExternalStore(bannerForm.subscribe, bannerForm.get);
  // Times show in the feed's zone (the site profile's feed.time_zone); the page renders again if it changes
  // As the server reads the feed (SiteProfile.FeedTimeZone): a stored profile that doesn't answer the question keeps
  // UTC; until the profile has loaded, the questionnaire's default.
  const profile = useSiteProfile().data?.profile;
  setDisplayZone(profile ? profile.feed?.time_zone || 'UTC' : undefined);
  // The engineer's group (the API reference) joins the navigation while the Detail switch is on Technical
  const sections = useSections();
  // 56 px live; a trial page's banner adds 40 px, 32 px once it is one line, and 36 px on a phone (styles.css keeps
  // --shutter-header-h, which sticky parts and scrolled-to sections clear, the same, in rem as AppShell turns these)
  const header = chrome ? { base: 92, sm: banner === 'compact' ? 88 : 96 } : 56;
  return (
    <AppShell
      header={{ height: header }}
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
        {chrome ? <chrome.TrialBanner /> : null}
        <Group h={56} px="md" justify="space-between" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" aria-label="Menu" />
            <UnstyledButton component={Link} to="/home" aria-label={`${APP_NAME}: home`}>
              <Group gap={8} wrap="nowrap">
                <BrandMark size={28} />
                {/* On a phone in the trial the pill stands beside the mark and the name gives way, so the row fits */}
                <Text
                  fw={700}
                  fz="lg"
                  style={{ letterSpacing: -0.3 }}
                  visibleFrom={chrome ? 'xs' : undefined}
                >
                  {APP_NAME}
                </Text>
              </Group>
            </UnstyledButton>
            {chrome ? <chrome.TrialPill /> : null}
          </Group>
          <Group gap="xs" wrap="nowrap">
            {chrome ? <chrome.TrialHelpMenu /> : <LiveHelpMenu />}
            <DetailSwitch />
            <AppearanceMenu />
            <UserMenu />
          </Group>
        </Group>
      </AppShell.Header>
      <AppShell.Navbar p="xs" aria-label="Main">
        <NavLink
          component={RouterNavLink}
          to="/home"
          label="Home"
          active={isActive(pathname, '/home')}
          className="nav-link"
          style={{ '--nav-icon': hueVar('cyan') } as CSSProperties}
          leftSection={<IconHome2 size={18} stroke={1.6} className="nav-icon" aria-hidden />}
          onClick={close}
        />
        {sections.map(({ group, items }) => (
          <div key={group} role="group" aria-labelledby={`nav-${group}`} className="nav-group">
            <Text id={`nav-${group}`} className="nav-group-label" tt="uppercase" px="sm" pt="sm" pb={4}>
              {group}
            </Text>
            {items.map((item) => (
              <NavLink
                key={item.to}
                component={RouterNavLink}
                to={item.to}
                label={item.label}
                active={isActive(pathname, item.to)}
                className="nav-link"
                style={{ '--nav-icon': hueVar(item.hue) } as CSSProperties}
                leftSection={<item.icon size={18} stroke={1.6} className="nav-icon" aria-hidden />}
                rightSection={item.count ? <NavCount /> : undefined}
                onClick={close}
              />
            ))}
          </div>
        ))}
        <PortalNavLink onClick={close} />
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
      {chrome ? (
        <>
          <chrome.Guide />
          <chrome.LeaveTrialConfirm />
        </>
      ) : (
        <LiveWelcome />
      )}
    </AppShell>
  );
}
