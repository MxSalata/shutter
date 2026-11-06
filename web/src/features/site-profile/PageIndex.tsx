import { Anchor, Box, NativeSelect, Stack, Text } from '@mantine/core';
import { usePrefersReducedMotion } from '@/lib/motion';

/** The answers' sections, in page order: where "On this page" jumps to. */
const PAGE_INDEX: { id: string; label: string }[] = [
  { id: 'site-receivers', label: 'Receivers, 1 to 6' },
  { id: 'site-approvals', label: 'Approvals, 7' },
  { id: 'site-incident', label: 'Incidents, 8' },
  { id: 'site-escalation', label: 'Escalation, 9' },
  { id: 'site-feed', label: 'Feed, model, merges, 10 to 13' },
  { id: 'site-reminders', label: 'Reminders, 14' },
  { id: 'site-versions', label: 'Versions' },
];

/** The fixed header's height and a little air, so the section's heading lands in view and not under the header. */
function headerOffset(): number {
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--shutter-header-h'));
  return (Number.isFinite(h) ? h : 56) + 16;
}

/** Scrolls to a section of the answers and moves focus to its heading, so a keyboard user lands where the page went. */
function useJump() {
  const reduced = usePrefersReducedMotion();
  return (id: string) => {
    const el = document.getElementById(id);
    if (!el) return;
    window.scrollTo({
      top: el.getBoundingClientRect().top + window.scrollY - headerOffset(),
      behavior: reduced ? 'auto' : 'smooth',
    });
    el.querySelector<HTMLElement>('[tabindex="-1"]')?.focus({ preventScroll: true });
  };
}

/** "On this page" below the `xl` breakpoint (1408 px): a select that jumps to the section. */
export function PageIndexSelect() {
  const jump = useJump();
  return (
    <Box hiddenFrom="xl">
      <NativeSelect
        label="On this page"
        value=""
        onChange={(e) => {
          const id = e.currentTarget.value;
          if (id) jump(id);
        }}
        data={[
          { value: '', label: 'Jump to a section' },
          ...PAGE_INDEX.map((s) => ({ value: s.id, label: s.label })),
        ]}
        maw={360}
      />
    </Box>
  );
}

/** "On this page" from the `xl` breakpoint: a sticky column beside the questionnaire, a link to each section. */
export function PageIndexNav() {
  const jump = useJump();
  return (
    <Box
      visibleFrom="xl"
      component="nav"
      aria-label="On this page"
      w={200}
      style={{
        flex: 'none',
        alignSelf: 'flex-start',
        position: 'sticky',
        top: 'calc(var(--shutter-header-h, 56px) + 16px)',
      }}
    >
      <Stack gap={6}>
        <Text className="overline" component="p" m={0}>
          On this page
        </Text>
        {PAGE_INDEX.map((s) => (
          <Anchor key={s.id} component="button" type="button" size="sm" ta="left" onClick={() => jump(s.id)}>
            {s.label}
          </Anchor>
        ))}
      </Stack>
    </Box>
  );
}
