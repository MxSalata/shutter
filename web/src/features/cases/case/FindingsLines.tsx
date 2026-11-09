import { Stack, Text } from '@mantine/core';
import { asObject } from '@/lib/json';

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/**
 * The findings on an order or result case (CONTRACTS 1.51, the evidence's findings item): what the engine did with the
 * message, the receiver's own words by field, which OBX they name, and where a character above ASCII stands. Shown to the
 * person reading the case; none of it goes to a model, and the escalation email carries only the parts with no free text.
 */
export function FindingsLines({ d }: { d: Record<string, unknown> }) {
  const custody = asObject(d.custody) ?? {};
  const reply = asObject(d.reply) ?? {};
  const obx = asObject(d.obx) ?? {};
  const character = asObject(d.character) ?? {};
  const lines: { key: string; text: string }[] = [];
  if (str(custody.words)) lines.push({ key: 'custody', text: str(custody.words) });
  if (str(reply.quote) && ['words', 'code_only', 'unknown'].includes(str(reply.kind)))
    lines.push({
      key: 'reply',
      text: `${str(reply.kind) === 'unknown' ? "The receiver's words, which name nothing Shutter reads" : "The receiver's words"}: ${str(reply.quote)}`,
    });
  if (str(obx.sentence) && ['obx', 'no_match', 'schema'].includes(str(obx.kind)))
    lines.push({ key: 'obx', text: str(obx.sentence) });
  if (str(character.sentence) && ['characters', 'question'].includes(str(character.kind)))
    lines.push({ key: 'character', text: str(character.sentence) });
  if (!lines.length && str(d.why)) lines.push({ key: 'why', text: `No finding: ${str(d.why)}.` });
  if (!lines.length) return <Text size="md">No finding for this message.</Text>;
  return (
    <Stack gap={4} data-testid="findings">
      {lines.map((l) => (
        <Text key={l.key} size="md">
          {l.text}
        </Text>
      ))}
    </Stack>
  );
}
