import { Accordion, Text } from '@mantine/core';
import type { IncidentDetail } from '@/api/types';
import { Digest } from '@/components/Digest';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { NotYet, Section } from '../../cases/case/Section';

export function IncidentPlanPanel({ inc }: { inc: IncidentDetail }) {
  return (
    <Section
      id="incident-plan"
      title="The plan"
      note="What an approval binds: the plan as recorded below, hashed as canonical JSON: every chain's kind, who decides it and its policy; each operation's case, key, payload digest, catalogue entry, outcome and the receiver version it goes at; the receiver's epoch; and the versions of the catalogue, the site profile and the gate's policy. If any of them moves, the digest moves and an earlier approval no longer applies."
    >
      {!inc.planDigest ? (
        <NotYet>No plan yet: it is made when the chains are formed and classified.</NotYet>
      ) : (
        <>
          <KeyValueList
            rows={[
              ['Plan digest', <Digest key="p" value={inc.planDigest} label="incident plan digest" />],
              ['Receiver epoch', inc.receiverEpoch === undefined ? '' : String(inc.receiverEpoch)],
              [
                'Catalogue',
                inc.catalogueVersion ? (
                  <Text key="c" size="sm" className="mono-wrap">
                    {inc.catalogueVersion}
                  </Text>
                ) : (
                  ''
                ),
              ],
              ['Site profile', inc.profileVersion ?? ''],
              ["Gate's policy", inc.policyVersion ?? ''],
            ]}
          />
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
        </>
      )}
    </Section>
  );
}
