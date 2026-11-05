import { describe, expect, it } from 'vitest';
import type { CaseDetail, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { caseOutcome } from '@/lib/status';
import { failureMapOf, receiverWords } from './failureMap';

type Id = keyof typeof fixtures.cases;
const detail = (id: Id) => fixtures.cases[id].detail as unknown as CaseDetail;
const snapshot = (id: Id) => fixtures.cases[id].snapshot as unknown as Snapshot;
/** The map of a recorded case, with its outcome as the page shows it from the case's own fields. */
const mapOf = (id: Id, more: { delivered?: boolean; code?: string } = {}) => {
  const c = detail(id);
  return failureMapOf(c, snapshot(id), caseOutcome({ state: c.state, disposition: c.disposition }), more);
};

describe('the map of an order, a result or a document that failed', () => {
  const ofOutcome = (failureOutcome: string, words = 'ERROR <Ens>ErrOutConnectExpired') => ({
    ...detail('C-000002'),
    failureKind: 'unmappable',
    failureOutcome,
    failureHttpStatus: undefined,
    failureText: `This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides. The source reported: ${words}`,
  });
  const map = (c: ReturnType<typeof ofOutcome>) =>
    failureMapOf(
      c as unknown as CaseDetail,
      snapshot('C-000002'),
      caseOutcome({ state: 'escalated', disposition: 'escalate' }),
    );

  it('says a connection that never opened was not delivered, and blames neither the message nor the mapping', () => {
    const m = map(ofOutcome('error'));
    expect(m.hop).toMatchObject({ label: 'Not delivered', tone: 'blocking', broken: true });
    expect(m.iris.trouble).toBe('');
  });

  it('never says "Not sent" for a receiver that refused it or took it and did not answer', () => {
    expect(map(ofOutcome('rejected')).hop.label).toBe('Refused');
    expect(map(ofOutcome('uncertain')).hop).toMatchObject({
      label: 'Answer lost: outcome unknown',
      tone: 'attention',
    });
  });

  it("keeps the mapping's words for an ADT message that really could not be mapped", () => {
    const c = {
      ...ofOutcome('error'),
      failureText:
        'The message could not be mapped to an operation for the downstream system: no visit number',
    };
    const m = map(c);
    expect(m.iris.trouble).toBe("Couldn't map the message to an operation");
    expect(m.hop.label).toBe('Not sent');
  });
});

describe('the map of where a case failed', () => {
  it("draws S2's transfer from PAS through IRIS's route to the bed manager, broken at the delivery with its answer", () => {
    const c = { ...detail('C-000002'), state: 'awaiting_approval' as const };
    const m = failureMapOf(c, snapshot('C-000002'), caseOutcome(c));
    expect(m.sender).toEqual({ name: 'PAS', gloss: 'patient administration system' });
    expect(m.message).toEqual({ plain: 'Transfer to WARD-B', code: 'ADT^A02' });
    expect(m.iris.items).toEqual(['ADT In', 'ADT to Downstream', 'Downstream Out']);
    expect(m.iris.trouble).toBe('');
    expect(m.receiver).toMatchObject({
      name: 'Bed-management system',
      item: 'Downstream Out',
      api: '/downstream/api',
    });
    expect(m.hop).toEqual({
      label: 'Not delivered',
      answer: 'HTTP 503 ward_unavailable',
      code: '',
      tone: 'blocking',
      broken: true,
    });
    expect(m.shutter.picked).toBe('Shutter picked up the failure');
    expect(m.shutter.outcome.label).toBe('Waiting for approval');
    expect(m.sentence).toBe(
      'PAS sent the transfer to WARD-B through IRIS to the bed-management system: not delivered, answered HTTP 503 ward_unavailable. Shutter picked up the failure; now waiting for approval.',
    );
    expect(m.steps).toEqual([
      'Sender: PAS, the patient administration system, sent the transfer to WARD-B.',
      'IRIS, the message engine.',
      'Receiver: the bed-management system, not delivered, answered HTTP 503 ward_unavailable.',
      'Shutter picked up the failure; now waiting for approval.',
    ]);
  });

  it('says the receiver holds the resend once it was delivered and verified there', () => {
    const c = detail('C-000002');
    const m = failureMapOf(
      c,
      snapshot('C-000002'),
      caseOutcome({ ...c, writes: 1, verification: 'verified' }),
      {
        delivered: true,
      },
    );
    expect(m.shutter.outcome.label).toBe('Delivered: verified at the receiver');
    expect(m.receiver.now).toBe("Has the transfer now: Shutter's resend, verified there");
    expect(m.sentence).toMatch(/now delivered: verified at the receiver\. The receiver has the transfer now/);
  });

  it("keeps S8's escalation in the attention tone, the delivery still broken", () => {
    const m = mapOf('C-000008');
    expect(m.hop.tone).toBe('blocking');
    expect(m.shutter.outcome).toMatchObject({ tone: 'attention', label: 'Escalated: a person decides' });
  });

  it('marks a refusal and its answer: S23a, refused 409 bed_occupied', () => {
    expect(mapOf('C-000058').hop).toMatchObject({
      label: 'Refused',
      answer: 'HTTP 409 bed_occupied',
      broken: true,
    });
  });

  it('marks a lost answer as unknown, in the attention tone: S3, HTTP 504', () => {
    expect(mapOf('C-000003').hop).toMatchObject({
      label: 'Answer lost: outcome unknown',
      answer: 'HTTP 504',
      tone: 'attention',
      broken: true,
    });
  });

  it("marks S25's message IRIS's schema could not read, and the reason code the gate blocked it on", () => {
    const m = mapOf('C-000064', { code: 'PARSE_FAILED' });
    expect(m.iris.trouble).toBe("Its schema couldn't read the message");
    expect(m.hop.label).toBe('Not delivered');
    expect(m.shutter).toMatchObject({ code: 'PARSE_FAILED' });
    expect(m.shutter.outcome.label).toBe('Blocked: nothing sent');
    expect(m.sentence).toContain("in IRIS, its schema couldn't read the message; not delivered");
  });

  it('draws a withheld merge as never sent, dashed and neutral, with its reason code for the engineer', () => {
    const m = mapOf('C-000012');
    expect(m.message.code).toBe('ADT^A40');
    expect(m.hop).toMatchObject({
      label: "Withheld by the site's policy: never sent",
      answer: '',
      code: 'merge',
      tone: 'neutral',
      broken: false,
    });
    expect(m.sentence).not.toContain('answered');
    expect(m.shutter.picked).toBe('Shutter withheld it and opened a case');
  });

  it("draws a forwarded case through the hospital's production and its route, not Shutter's own feed", () => {
    const m = mapOf('C-000052');
    expect(m.iris).toMatchObject({
      role: "The hospital's production",
      where: 'Hospital.Production in HOSPITAL',
      items: ['PAS In'],
    });
    expect(m.shutter.picked).toBe("Shutter picked up the failure from the hospital's production");
    expect(m.sentence).toMatch(/^PAS sent the transfer to WARD-B through the hospital's production in IRIS/);
  });

  it('names the incident a member case belongs to', () => {
    expect(mapOf('C-000037').shutter.picked).toBe('Shutter picked up the failure, in incident I-000001');
  });

  it("names S22's other receiver, the patient records system", () => {
    expect(mapOf('C-000055').receiver).toMatchObject({ name: 'Patient records system', item: 'Records Out' });
  });

  it('draws a held message as IRIS unable to read it, with nothing sent', () => {
    const c = {
      ...detail('C-000002'),
      failureKind: 'unreadable',
      failureHttpStatus: undefined,
      failureReasonCode: 'schema_unknown',
    };
    const m = failureMapOf(c, snapshot('C-000002'), caseOutcome(c));
    expect(m.iris.trouble).toBe("Couldn't read the message: its HL7 schema is not loaded here");
    expect(m.hop).toMatchObject({
      label: 'Held: nothing sent',
      answer: '',
      code: 'schema_unknown',
      broken: false,
    });
    expect(m.shutter.picked).toBe('Shutter picked up the held message');
  });

  it('shows what is known when the evidence is not read: no sender recorded, no route, the receiver by its item', () => {
    const c = { ...detail('C-000002'), sourceSystem: '', receiver: 'Records Out' };
    const m = failureMapOf(c, undefined, caseOutcome(c));
    expect(m.sender).toBeNull();
    expect(m.message.code).toBe('');
    expect(m.iris.items).toEqual([]);
    expect(m.receiver).toEqual({ name: 'Records Out', item: '', api: '', now: '' });
    expect(m.sentence).toMatch(/^The transfer to WARD-B went through IRIS to Records Out: not delivered/);
    expect(m.steps[0]).toBe('IRIS, the message engine.');
  });

  it('takes the receiver as the bed manager for a case recorded before cases named one', () => {
    const c = { ...detail('C-000002'), receiver: undefined };
    expect(failureMapOf(c, undefined, caseOutcome(c)).receiver.name).toBe('Downstream Out');
  });
});

describe("the receiver's description in words", () => {
  it('drops the article, the demo and the API path, and keeps the path apart', () => {
    expect(receiverWords('the demo bed-management system (/downstream/api)')).toEqual({
      name: 'Bed-management system',
      api: '/downstream/api',
    });
    expect(receiverWords('St Elsewhere ward board')).toEqual({ name: 'St Elsewhere ward board', api: '' });
    expect(receiverWords('')).toEqual({ name: '', api: '' });
  });
});
