import { Accordion, Group, Stack, Text } from '@mantine/core';
import type { IncidentDetail } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { Digest } from '@/components/Digest';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { NotYet, Section } from '@/components/Section';
import { TechDetail } from '@/components/TechDetail';
import { planSentence } from '../describe';

export function IncidentPlanPanel({ inc }: { inc: IncidentDetail }) {
  const catalogue = (inc.catalogueVersion ?? '').split(',').filter(Boolean);
  return (
    <Section id="incident-plan" title="The plan" note={inc.planDigest ? planSentence(inc.chains) : undefined}>
      {!inc.planDigest ? (
        <NotYet>No plan yet: it is made when the chains are formed and classified.</NotYet>
      ) : (
        <TechDetail label="Everything the approval is bound to" kind="data">
          <Stack gap="sm">
            <KeyValueList
              rows={[
                ['Plan digest', <Digest key="p" value={inc.planDigest} label="incident plan digest" />],
                ['Receiver epoch', inc.receiverEpoch === undefined ? '' : String(inc.receiverEpoch)],
                [
                  'Catalogue',
                  catalogue.length ? (
                    <Group key="c" gap={4}>
                      {catalogue.map((entry) => (
                        <CodeChip key={entry}>{entry}</CodeChip>
                      ))}
                    </Group>
                  ) : (
                    ''
                  ),
                ],
                ['Site profile', inc.profileVersion ?? ''],
                ["Gate's policy", inc.policyVersion ?? ''],
              ]}
            />
            <TechDetail label="What the digest covers" kind="explain">
              <Text size="sm" maw="68ch">
                The plan as recorded below, hashed as canonical JSON: every chain&apos;s kind, who decides it
                and its policy; each operation&apos;s case, key, payload digest, catalogue entry, outcome and
                the receiver version it goes at; the receiver&apos;s epoch; and the versions of the catalogue,
                the site profile and the gate&apos;s policy. If any of them moves, the digest moves and an
                earlier approval no longer applies.
              </Text>
            </TechDetail>
            {inc.plan ? (
              <Accordion variant="contained" chevronPosition="left">
                <Accordion.Item value="plan">
                  <Accordion.Control>
                    <Text size="sm">The plan as recorded</Text>
                  </Accordion.Control>
                  <Accordion.Panel>
                    <JsonBlock value={inc.plan} label="incident plan" />
                  </Accordion.Panel>
                </Accordion.Item>
              </Accordion>
            ) : null}
          </Stack>
        </TechDetail>
      )}
    </Section>
  );
}
