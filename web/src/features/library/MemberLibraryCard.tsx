import { Badge, Group, Stack, Switch, Text, Tooltip } from '@mantine/core';
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
  canEdit,
  reading,
  busy,
  knowsTerm,
  changedInTrial,
  onChange,
}: {
  m: LibraryMember;
  /** The user may change which agents sit on the board. */
  canEdit: boolean;
  /** The public demo's role: it reads the board, so the settings are words and not switches. */
  reading: boolean;
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
          {reading ? (
            <Setting label="Enabled" value={m.enabled} />
          ) : (
            <SettingSwitch
              label="Enabled"
              name={`${m.name} enabled`}
              checked={m.enabled}
              disabled={!canEdit || busy}
              canEdit={canEdit}
              onChange={(v) => onChange(m, 'enabled', v)}
            />
          )}
          {line ? (
            <Text size="sm">{line}</Text>
          ) : reading ? (
            <Setting label="On the default board" value={m.inDefaultBoard} />
          ) : (
            <SettingSwitch
              label="On the default board"
              name={`${m.name} on the default board`}
              checked={m.inDefaultBoard}
              disabled={!canEdit || !m.enabled || busy}
              canEdit={canEdit}
              onChange={(v) => onChange(m, 'inDefaultBoard', v)}
            />
          )}
        </Group>
        {changedInTrial ? (
          <div>
            <Text size="sm">Changed in the trial only.</Text>
            <Text size="sm" c="dimmed">
              This card changes; the recorded runs stay as they were.
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

/** A setting a reader may not change, as a label and its value. */
function Setting({ label, value }: { label: string; value: boolean }) {
  return (
    <Group gap={6} wrap="nowrap">
      <Text size="sm">{label}</Text>
      <Text size="sm" fw={600}>
        {value ? 'Yes' : 'No'}
      </Text>
    </Group>
  );
}

/** A labelled switch whose name for assistive technology says whose it is ("Coordinator enabled"). */
function SettingSwitch({
  label,
  name,
  checked,
  disabled,
  canEdit,
  onChange,
}: {
  label: string;
  name: string;
  checked: boolean;
  disabled: boolean;
  canEdit: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <Tooltip label="Needs the approver role" disabled={canEdit}>
      <Group>
        <Switch
          label={label}
          aria-label={name}
          checked={checked}
          disabled={disabled}
          onChange={(e) => onChange(e.currentTarget.checked)}
        />
      </Group>
    </Tooltip>
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
