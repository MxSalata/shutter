import { describe, expect, it } from 'vitest';
import {
  formatDateTime,
  formatUsd,
  formatUtc,
  formatZoned,
  humanize,
  displayZone,
  keyLabel,
  setDisplayZone,
  shortDigest,
} from './format';

describe('shortDigest', () => {
  it('shortens a digest after its scheme', () => {
    expect(shortDigest('sha256:c5260589ac01aa5d4358690e22f78d6101f96b348ef4370540fefc3160bd32a9')).toBe(
      'sha256:c5260589ac01…',
    );
  });
  it('leaves an operation key whole, colons and all', () => {
    const key = 'PAS^HOSP^MRN1002^ENC-1002^transfer^2026-10-15T09:20:00Z';
    expect(shortDigest(key, 80)).toBe(key);
  });
});

describe('formatting', () => {
  it("shows times in the feed's zone, named, as the hospital knows them", () => {
    setDisplayZone('Europe/London');
    expect(formatZoned('2026-10-15T08:20:00Z')).toBe('15 Oct, 09:20:00 BST');
    expect(formatZoned('2026-11-15T09:20:00Z')).toBe('15 Nov, 09:20:00 GMT');
    expect(formatUtc('2026-10-15T08:20:00Z')).toBe('15 Oct, 08:20:00 UTC');
    setDisplayZone('UTC');
    expect(formatDateTime('2026-10-15T09:20:00Z')).toBe('15 Oct, 09:20:00');
    setDisplayZone('+01:00');
    expect(formatDateTime('2026-11-15T09:20:00Z')).toBe('15 Nov, 10:20:00');
    expect(displayZone()).toBe('+01:00');
    // Offsets the profile accepts beyond whole hours and past GMT+12 on the west side
    setDisplayZone('-03:30');
    expect(formatDateTime('2026-11-15T09:20:00Z')).toBe('15 Nov, 05:50:00');
    setDisplayZone('-14:00');
    expect(formatDateTime('2026-11-15T19:20:00Z')).toBe('15 Nov, 05:20:00');
    // A zone that isn't one reads as UTC, and says so
    setDisplayZone('Mars/Olympus');
    expect(formatDateTime('2026-10-15T09:20:00Z')).toBe('15 Oct, 09:20:00');
    expect(displayZone()).toBe('UTC');
    setDisplayZone('Europe/London');
    expect(displayZone()).toBe('Europe/London');
  });
  it('turns codes into words', () => {
    expect(humanize('awaiting_approval')).toBe('Awaiting approval');
  });
  it('names the readiness keys whose words alone would say too little', () => {
    expect(keyLabel('purge_task')).toBe('Message purge task');
    expect(keyLabel('message_days')).toBe('Messages kept (days)');
    expect(keyLabel('escalation_days')).toBe('Escalation texts kept (days)');
    expect(keyLabel('shutter_production')).toBe("Shutter's production");
    expect(keyLabel('production_state')).toBe('Production state');
  });
  it('prices below a cent with four decimals', () => {
    expect(formatUsd(0.00042)).toBe('$0.0004');
    expect(formatUsd(1.5)).toBe('$1.50');
  });
});
