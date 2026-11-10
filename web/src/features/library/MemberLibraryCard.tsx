import { Badge, Group, Stack, Switch, Text } from '@mantine/core';
import type { LibraryMember } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { IdentityBadge } from '@/components/IdentityBadge';
import { MemberCard } from '@/components/MemberCard';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { memberIdentity } from '@/lib/hues';
import { boardLine, knowsWords, roleLabel } from './board';
import './library.css';

export type LibraryField = 'enabled' | 'inDefaultBoard';

/**
 * One member of the library as a card (DESIGN 2.5): its avatar and hue, the role, the question it asks, what it does,
 * what it knows, the two settings, and its code one click away. An article named by the member's heading, so a screen
 * reader can move from one member to the next. A member that is not enabled turns gray (its words say so; no fade).
 */
export function MemberLibraryCard({
  m,
  busy,
  knowsTerm,
  changedInTrial,
  onChange,
}: {
  m: LibraryMember;
  /** A change is being saved: every switch waits. */
  busy: boolean;
  /** Explain "Knows" here (once on the page, on its first use). */
  knowsTerm: boolean;
  /** This member was changed in this trial page, which resets with the page. */
  changedInTrial: boolean;
  onChange: (m: LibraryMember, field: LibraryField, value: boolean) => void;
}) {
  const identity = memberIdentity(m.code, m.name);
  const line = boardLine(m.role);
  return (
    <MemberCard
      component="article"
      titleId={`library-member-${m.code}`}
      member={m.code}
      name={m.name}
      muted={!m.enabled}
      className="library-member"
      badge={
        <>
          <IdentityBadge hue={m.enabled ? identity.hue : 'gray'}>{roleLabel(m.role)}</IdentityBadge>
          {m.enabled ? null : (
            <Badge color="gray" variant="outline" size="sm" style={{ textTransform: 'none' }}>
              Not enabled
            </Badge>
          )}
        </>
      }
    >
      {m.perspective ? (
        <Text component="blockquote" size="lg" fw={500} className="library-question">
          <span aria-hidden>“</span>
          {m.perspective}
          <span aria-hidden>”</span>
        </Text>
      ) : null}
      <Text size="sm">{m.description}</Text>
      <Text size="sm">
        {knowsTerm ? <Term term="knows">Knows</Term> : 'Knows'}: {knowsWords(m.knowledgeCollection)}
      </Text>
      <Stack gap="xs" className="library-settings">
        <Group gap="lg" wrap="wrap" align="center">
          <SettingSwitch
            label="Enabled"
            name={`${m.name} enabled`}
            checked={m.enabled}
            disabled={busy}
            onChange={(v) => onChange(m, 'enabled', v)}
          />
          {line ? (
            <Text size="sm">{line}</Text>
          ) : (
            <SettingSwitch
              label="On the default board"
              name={`${m.name} on the default board`}
              checked={m.inDefaultBoard}
              disabled={!m.enabled || busy}
              onChange={(v) => onChange(m, 'inDefaultBoard', v)}
            />
          )}
        </Group>
        {changedInTrial ? (
          <div>
            <Text size="sm">Changed in the trial only.</Text>
            <Text size="sm" c="dimmed">
              The recorded runs stay as they were.
            </Text>
          </div>
        ) : null}
        <TechDetail label="Technical detail" kind="data">
          <dl className="library-detail">
            <Fact label="Class">{`${m.agentClass} · v${m.configVersion}`}</Fact>
            <Fact label="Production item">{m.configItem}</Fact>
            <Fact label="Knowledge collection">{m.knowledgeCollection}</Fact>
            <Fact label="Terminal tool">{m.terminalTool}</Fact>
          </dl>
        </TechDetail>
      </Stack>
    </MemberCard>
  );
}

/** A labelled switch whose name for assistive technology says whose it is ("Coordinator enabled"). */
function SettingSwitch({
  label,
  name,
  checked,
  disabled,
  onChange,
}: {
  label: string;
  name: string;
  checked: boolean;
  disabled: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <Group>
      <Switch
        label={label}
        aria-label={name}
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.currentTarget.checked)}
      />
    </Group>
  );
}

/** One fact of a member's code, its label over the code. A fact the member does not have is left out. */
function Fact({ label, children }: { label: string; children: string }) {
  if (!children) return null;
  return (
    <div>
      <Text component="dt" size="sm" c="dimmed">
        {label}
      </Text>
      <dd className="library-fact">
        <CodeChip>{children}</CodeChip>
      </dd>
    </div>
  );
}
