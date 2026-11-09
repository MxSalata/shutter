import { Text } from '@mantine/core';
import type { CaseDetail } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { approvalChange, type ApprovalEvidence } from './approvalChange';

/** The approve dialog's two rows: what the evidence read at the receiver, with its time, and what the write makes it. */
export function ApprovalChangeRows({
  c,
  snapshot,
}: {
  c: Pick<CaseDetail, 'event' | 'ward'>;
  snapshot: ApprovalEvidence;
}) {
  const { held, readAt, after } = approvalChange(c, snapshot);
  return (
    <KeyValueList
      rows={[
        [
          'Held when read',
          <Text key="h" size="sm">
            {held}
            {readAt ? (
              <>
                {' ('}
                <Timestamp iso={readAt} />
                {')'}
              </>
            ) : null}
          </Text>,
        ],
        ['After', after],
      ]}
    />
  );
}
