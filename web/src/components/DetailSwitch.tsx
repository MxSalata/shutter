import { ActionIcon, Box, Menu, SegmentedControl, Tooltip, VisuallyHidden } from '@mantine/core';
import { IconCheck, IconCode } from '@tabler/icons-react';
import { useState } from 'react';
import type { DetailLevel } from '@/env/mode';
import { useAppearance, useDetail } from '@/stores/appearance';

const WORDS: Record<DetailLevel, string> = { plain: 'Plain', technical: 'Technical' };
const SAID: Record<DetailLevel, string> = { plain: 'Plain words', technical: 'Technical detail on' };

/**
 * The header's Detail switch, "Plain | Technical", on every page, live and in the trial: Technical opens every
 * disclosure of data, shows the codes beside the words and UTC beside local times; Plain is the default. From a tablet
 * up it is a two-segment control (the group label "Detail" read by screen readers only); on a phone an icon button
 * named "Detail: Plain" or "Detail: Technical" with a menu of both. A change is announced politely.
 */
export function DetailSwitch() {
  const detail = useDetail();
  const setDetail = useAppearance((s) => s.setDetail);
  const [said, setSaid] = useState('');
  const choose = (d: DetailLevel) => {
    if (d === detail) return;
    setDetail(d);
    setSaid(SAID[d]);
  };
  return (
    <>
      <Box visibleFrom="sm">
        <SegmentedControl
          aria-label="Detail"
          size="xs"
          value={detail}
          onChange={(v) => choose(v as DetailLevel)}
          data={[
            { value: 'plain', label: WORDS.plain },
            { value: 'technical', label: WORDS.technical },
          ]}
        />
      </Box>
      <Box hiddenFrom="sm">
        <Menu position="bottom-end" withinPortal>
          <Menu.Target>
            <Tooltip label={`Detail: ${WORDS[detail]}`}>
              <ActionIcon variant="subtle" size="lg" aria-label={`Detail: ${WORDS[detail]}`}>
                <IconCode size={18} aria-hidden />
              </ActionIcon>
            </Tooltip>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Label>Detail</Menu.Label>
            {(['plain', 'technical'] as const).map((d) => (
              <Menu.Item
                key={d}
                onClick={() => choose(d)}
                leftSection={
                  d === detail ? <IconCheck size={14} aria-hidden /> : <span style={{ width: 14 }} />
                }
                aria-label={`${d === 'plain' ? 'Plain words' : 'Technical'}${d === detail ? ' (current)' : ''}`}
              >
                {d === 'plain' ? 'Plain words' : 'Technical'}
              </Menu.Item>
            ))}
          </Menu.Dropdown>
        </Menu>
      </Box>
      {/* A polite announcement of the change; not a status region, which the pages keep for loading */}
      <VisuallyHidden aria-live="polite">{said}</VisuallyHidden>
    </>
  );
}
