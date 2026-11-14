import { Badge, Group, Tooltip } from '@mantine/core';
import { evidenceSection } from '@/lib/evidenceRefs';
import { showEvidence } from './evidenceLinks';

/** A cited section's chip, in a word or two; the section's own title is on the Evidence tab it opens. */
const CHIPS: Record<string, string> = {
  message: 'HL7 message',
  validation: 'Schema validation',
  error: 'Connector error',
  operation: 'Failed operation',
  route: 'Route',
  ward_state: 'Encounter',
  receipt: 'Receipt',
  timeline: 'Timeline',
  later_event: 'Later events',
};

const CHIP_STYLE = {
  textTransform: 'none',
  cursor: 'pointer',
  height: 'auto',
  whiteSpace: 'normal',
} as const;

/**
 * Evidence as chips, one per section of the case's Evidence tab and one per catalogue entry: each opens what it names
 * on that tab (the section with what it recorded, or the line that names the entry), on this case and nowhere else.
 */
export function EvidenceChips({
  refs,
  entries = [],
  receiver,
}: {
  /** Evidence refs (`ward_state`, `receipt`, ...); one that is no section of the tab is left out. */
  refs: readonly string[];
  /** Catalogue entries (`E7`), each a chip that opens the Evidence tab's line about it. */
  entries?: readonly string[];
  /** The case's receiver, for the names of the sections it recorded. */
  receiver?: string;
}) {
  return (
    <Group gap={6} wrap="wrap">
      {entries.map((entry) => (
        <Tooltip key={entry} label={`Open catalogue entry ${entry} on the Evidence tab`}>
          <Badge
            size="sm"
            variant="outline"
            color="gray"
            component="button"
            type="button"
            aria-label={`Catalogue entry ${entry}`}
            onClick={() => showEvidence(`catalogue:${entry}`)}
            style={CHIP_STYLE}
          >
            {entry}
          </Badge>
        </Tooltip>
      ))}
      {refs.map((ref) => {
        const section = evidenceSection(ref, receiver);
        return section ? (
          <Tooltip key={ref} label={`Open ${section.title} on the Evidence tab`}>
            <Badge
              size="sm"
              variant="outline"
              color="gray"
              component="button"
              type="button"
              onClick={() => showEvidence(ref)}
              style={CHIP_STYLE}
            >
              {CHIPS[ref] ?? section.title}
            </Badge>
          </Tooltip>
        ) : null;
      })}
    </Group>
  );
}
