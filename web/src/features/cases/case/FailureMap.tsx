import { Box, Text, VisuallyHidden } from '@mantine/core';
import { IconChevronRight, IconX } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { StatusBadge } from '@/components/StatusBadge';
import { TONE_ICONS } from '@/lib/tone';
import { useDetail } from '@/stores/appearance';
import type { FailureMap as Map } from './failureMapModel';

/**
 * One system on the path: its name, what it is where neither the name nor the header's sentence says, and the
 * engineer's names for it in Technical. The picture is one image to assistive technology, so it holds no terms to
 * open: the header defines them.
 */
function Node({
  role,
  title,
  sub,
  technical,
  children,
}: {
  role: 'sender' | 'iris' | 'receiver';
  title: string;
  sub?: string;
  technical?: string;
  children?: ReactNode;
}) {
  return (
    <div className="fm-node" data-role={role}>
      <Text fw={700} size="sm" lh={1.3}>
        {title}
      </Text>
      {sub ? (
        <Text size="xs" c="dimmed" lh={1.35}>
          {sub}
        </Text>
      ) : null}
      {technical ? (
        <Text size="xs" lh={1.35} className="mono-wrap" mt={2}>
          {technical}
        </Text>
      ) : null}
      {children}
    </div>
  );
}

/**
 * A hop between two systems: a line and an arrow; a failed delivery breaks the line in its tone with a cross, its words
 * and the receiver's answer under it. Across on a laptop, down on a phone (`.failure-map` is a size container).
 */
function Link({
  tone,
  broken = false,
  dashed = false,
  label,
  answer,
}: {
  tone?: Map['hop']['tone'];
  broken?: boolean;
  dashed?: boolean;
  label?: string;
  answer?: string;
}) {
  return (
    <div
      className="fm-link"
      data-tone={tone}
      data-broken={broken || undefined}
      data-dashed={dashed || undefined}
    >
      <span className="fm-line">
        <span className="fm-seg" />
        {broken ? (
          <span className="fm-break">
            <IconX size={12} stroke={3} aria-hidden />
          </span>
        ) : null}
        {broken ? <span className="fm-seg" /> : null}
        <IconChevronRight size={16} stroke={2.4} className="fm-arrow" aria-hidden />
      </span>
      {label || answer ? (
        <span className="fm-label">
          {label ? (
            <Text span size="xs" fw={700} display="block" lh={1.3} className="fm-label-words">
              {label}
            </Text>
          ) : null}
          {answer ? (
            <Text span size="xs" display="block" lh={1.3} className="fm-answer">
              {answer}
            </Text>
          ) : null}
        </span>
      ) : null}
    </div>
  );
}

/**
 * "Where it failed", under the case's header: the sending system, IRIS and the receiving system as boxes, the hop that
 * broke marked in its tone with the receiver's answer, and a line saying that Shutter picked the failure up and where it
 * stands, in the outcome's tone. Readable at a glance: Plain shows the systems and the words; Technical adds the
 * route's item names, the event's HL7 type and the reason code. The picture is one image to assistive technology,
 * named by a sentence that says it all, followed by the same facts as a list. It does not move.
 */
export function FailureMap({ map }: { map: Map }) {
  const technical = useDetail() === 'technical';
  const { sender, message, iris, receiver, hop, shutter } = map;
  const OutcomeIcon = shutter.outcome.icon ?? TONE_ICONS[shutter.outcome.tone];
  const irisTechnical = [iris.where, iris.items.join(' → ')].filter(Boolean).join(': ');
  const receiverTechnical = [receiver.item, receiver.api].filter(Boolean).join(' · ');
  return (
    <Box className="failure-map" mb="md" data-testid="failure-map">
      <Text className="overline" c="dimmed" mb={6} aria-hidden>
        Where it failed
      </Text>
      <div role="img" aria-label={`Where it failed: ${map.sentence}`} className="fm-picture">
        <div className="fm-flow">
          {sender ? (
            <>
              {/* The header's sentence defines a known system's short name a click away, so the box does not spell it out */}
              <Node role="sender" title={sender.name} sub={sender.gloss ? '' : 'The sending system'} />
              <Link label={message.plain} answer={technical ? message.code : ''} />
            </>
          ) : null}
          <Node role="iris" title="IRIS" sub={iris.role} technical={technical ? irisTechnical : ''}>
            {iris.trouble ? (
              <Text size="xs" fw={600} lh={1.35} mt={4} className="fm-trouble">
                {iris.trouble}
              </Text>
            ) : null}
          </Node>
          <Link
            tone={hop.tone}
            broken={hop.broken}
            dashed={!hop.broken}
            label={hop.label}
            answer={hop.answer || (technical ? hop.code : '')}
          />
          {/* A receiver named in words needs no caption; one known only by its production item keeps it */}
          <Node
            role="receiver"
            title={receiver.name}
            sub={receiver.item ? '' : 'The receiving system'}
            technical={technical ? receiverTechnical : ''}
          >
            {receiver.now ? (
              <Text size="xs" fw={600} lh={1.35} mt={4} className="fm-now">
                {receiver.now}
              </Text>
            ) : null}
          </Node>
        </div>
        <div className="fm-shutter" data-tone={shutter.outcome.tone}>
          <Text size="sm" fw={600}>
            {shutter.picked}
          </Text>
          <span className="fm-shutter-now">
            <Text span size="sm" c="dimmed">
              now
            </Text>
            <StatusBadge
              tone={shutter.outcome.tone}
              label={shutter.outcome.label}
              icon={OutcomeIcon}
              size="md"
            />
            {technical && shutter.code ? (
              <Text span size="xs" className="mono-wrap">
                {shutter.code}
              </Text>
            ) : null}
          </span>
        </div>
      </div>
      <VisuallyHidden>
        <ol>
          {map.steps.map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ol>
      </VisuallyHidden>
    </Box>
  );
}
