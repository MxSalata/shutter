import { MantineProvider } from '@mantine/core';
import { cleanup, render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { theme } from '@/theme';
import { ReceiverCards } from './ReceiverCards';

/** The entry of DESIGN 2.1, as a site writes it. */
const fhirEntry = (recovery?: boolean): SiteReceiver => ({
  name: 'FHIR Ward Out',
  system: 'the ward system (FHIR R4)',
  category: 'current_state',
  tier: 3,
  applies: 'arrival_order',
  resend_timestamp: 'original',
  cancels: false,
  merges: false,
  fhir: {
    base: '/fhir-facade/r4',
    ...(recovery === undefined ? {} : { recovery_enabled: recovery }),
    encounter_identifier: { system: 'urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49' },
    patient_identifier: { system: 'urn:shutter:demo:mrn', hl7_authority: 'HOSP' },
    marker: { system: 'urn:shutter:recovery' },
    location_map: [
      {
        ward: 'WARD-A',
        location: 'Location/ward-a',
        identifier: { system: 'urn:shutter:ward', value: 'WARD-A' },
      },
      {
        ward: 'WARD-B',
        location: 'Location/ward-b',
        identifier: { system: 'urn:shutter:ward', value: 'WARD-B' },
      },
    ],
  },
});

const downstream: SiteReceiver = {
  name: 'Downstream Out',
  category: 'current_state',
  tier: 2,
  api: { base: '/downstream/api', state: '/encounters/{encounter}', operations: '/operations' },
  features: { conditional_writes: true, receipts: true, history: true, dry_run: true },
};

function cardOf(receivers: SiteReceiver[], name: string) {
  const profile = { receivers, policy: {} } as unknown as SiteProfile;
  render(
    <MantineProvider theme={theme}>
      <ReceiverCards profile={profile} />
    </MantineProvider>,
  );
  return within(screen.getByRole('listitem', { name }));
}

/** The four words of the "Takes" line, read from declared features, and their long forms. */
const TAKES_WORDS = [/Takes:/, /conditional writes/i, /receipts/i, /dry runs?/i, /readable history/i];

describe('a FHIR receiver on the site profile page', () => {
  it('shows the server, its base, the one move, recovery, the ward map, and none of the Takes words', () => {
    const card = cardOf([downstream, fhirEntry(true)], 'FHIR Ward Out');
    expect(card.getByText('FHIR R4 server')).toBeInTheDocument();
    expect(card.getAllByText('/fhir-facade/r4').length).toBeGreaterThan(0);
    expect(card.getByText('One ward move on an existing Encounter.')).toBeInTheDocument();
    expect(card.getByText('Recovery on')).toBeInTheDocument();
    const map = within(card.getByRole('list', { name: 'Ward map' }));
    expect(map.getAllByRole('listitem').map((li) => li.textContent)).toEqual([
      'WARD-A: Location/ward-a',
      'WARD-B: Location/ward-b',
    ]);
    const text = card
      .getByRole('heading', { name: 'FHIR Ward Out' })
      .closest('[role="listitem"]')!.textContent;
    for (const word of TAKES_WORDS) expect(text).not.toMatch(word);
    // The receiver beside it still reads as it did
    const other = within(screen.getByRole('listitem', { name: 'Downstream Out' }));
    expect(other.getByText(/^Takes:/)).toHaveTextContent('conditional writes, receipts, history, dry runs');
    expect(other.queryByText('FHIR R4 server')).toBeNull();
  });

  it('says recovery is off when the entry says so, and when it does not say', () => {
    for (const recovery of [false, undefined]) {
      const card = cardOf([fhirEntry(recovery)], 'FHIR Ward Out');
      expect(card.getByText('Recovery off')).toBeInTheDocument();
      expect(card.queryByText('Recovery on')).toBeNull();
      cleanup();
    }
  });
});
