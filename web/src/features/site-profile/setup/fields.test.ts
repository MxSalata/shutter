import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { recordedSiteProfile } from '@/mocks/profile';
import { layer1WordCount } from '@/test/words';
import { validateProfile } from '../profile';
import {
  FIELD_TABLE,
  QUESTIONS,
  answerText,
  classOf,
  consequence,
  holdsAnswer,
  keyPaths,
  questionById,
  rowsFor,
  whyQuestion,
} from './fields';

const recorded = recordedSiteProfile()!.profile;
const seed = JSON.parse(
  readFileSync(join(__dirname, '../../../../../knowledge/site/profile.json'), 'utf8'),
) as SiteProfile;

/** A profile with every key the validator accepts, each with a value it passes. */
const EVERYTHING = {
  version: 3,
  receivers: [
    {
      name: 'Bed Board',
      system: 'the ward whiteboard',
      category: 'current_state',
      history_policy: 'current',
      demo: { namespace: 'DEMO' },
      tier: 2,
      applies: 'arrival_order',
      resend_timestamp: 'original',
      cancels: false,
      merges: false,
      api: { base: '/b', state: '/s', receipt: '/r', capabilities: '/c', operations: '/o' },
      features: { conditional_writes: true, receipts: true, history: true, dry_run: true },
      strict_answers: true,
      manual_check: { runbook: 'Look at the ward board' },
      watch: { namespace: 'HOSP', item: 'Bed Board' },
      runbook: 'Call the ward',
      call: 'The bed manager',
      approvers: ['A Person'],
      ack_level: 'application',
      duplicates: { behaviour: 'refuses', code: '207', phrase: 'Duplicate', refers_to: 'message' },
      engine_resend: true,
      hold: { minutes: 10 },
      mail: { to: ['team@example.nhs.uk'], on: ['open'] },
      resend_approval_minutes: 15,
      settle_minutes: 10,
      window_minutes: 5,
    },
  ],
  history_policy: 'current',
  authoritative_source: 'PAS',
  unconditional_resend: 'forbidden',
  merges: 'forbidden',
  policy: { '1': { single: 'approval', ordered: 'approval', interleaved: 'board' } },
  approvers: { role: 'Approvers', escalation: 'On call', close_needs_approver: false },
  incident: { threshold: 5, window_minutes: 10, quiet_seconds: 60, max_intake_seconds: 600 },
  model_content: { free_text: false },
  teams: [
    {
      id: 'integration',
      name: 'Integration',
      mailbox: 'team@example.nhs.uk',
      cc: ['lead@example.nhs.uk'],
      receivers: ['Bed Board'],
      sources: ['PAS'],
    },
  ],
  mail: { from: 'shutter@example.nhs.uk', allowed_domains: ['example.nhs.uk'] },
  feed: { time_zone: 'Europe/London', prevent_failures: false, source_skew_seconds: 300, prove_origin: true },
  further_messages: {
    in_patient_movement: 'show',
    a08_location: 'stop',
    admission_not_found: 'person',
    scan_seconds: 30,
  },
  recovery: { mode: 'shadow' },
  notifications: { shadow_delivery: 'disabled' },
  reminders: {
    enabled: false,
    team_hours: 4,
    officer_hours: 8,
    officer_name: 'The officer',
    officer_address: 'officer@example.nhs.uk',
    window_start: '08:00',
    window_end: '18:00',
    days: ['mon'],
    patient_detail: 'identifiers',
    sign_in_url: 'https://shutter.example.nhs.uk/',
  },
  failure_census: { enabled: false, max_window_hours: 24 },
};

describe('the field table', () => {
  it('holds every key the validator accepts in exactly one class', () => {
    expect(validateProfile(EVERYTHING)).toBe('');
    const paths = new Set([...keyPaths(EVERYTHING), ...keyPaths(recorded), ...keyPaths(seed)]);
    expect(paths.size).toBeGreaterThan(70);
    for (const path of paths) expect([path, rowsFor(path).length]).toEqual([path, 1]);
  });

  it('lets a model draft three keys and no other', () => {
    expect(FIELD_TABLE.filter(([, cls]) => cls === 'A').map(([path]) => path)).toEqual([
      'receivers[].system',
      'receivers[].category',
      'receivers[].tier',
    ]);
  });

  it("keeps every policy, capability and site-wide switch a person's", () => {
    for (const path of [
      'recovery.mode',
      'notifications.shadow_delivery',
      'policy.2.single',
      'policy.3.interleaved',
      'merges',
      'unconditional_resend',
      'authoritative_source',
      'feed.time_zone',
      'model_content.free_text',
      'further_messages.a08_location',
      'approvers.close_needs_approver',
      'approvers.role',
      'incident.threshold',
      'teams[0].mailbox',
      'mail.allowed_domains[0]',
      'reminders.enabled',
      'receivers[0].name',
      'receivers[1].cancels',
      'receivers[1].merges',
      'receivers[0].applies',
      'receivers[0].resend_timestamp',
      'receivers[0].api.operations',
      'receivers[0].features.dry_run',
      'receivers[0].strict_answers',
      'receivers[0].engine_resend',
      'receivers[0].ack_level',
      'receivers[0].history_policy',
      'receivers[0].manual_check.runbook',
    ])
      expect([path, classOf(path)]).toEqual([path, 'P']);
  });

  it('keeps as stored what the page never sets, and does not know a key outside the table', () => {
    for (const path of ['version', 'history_policy', 'failure_census.enabled', 'receivers[0].demo.namespace'])
      expect([path, classOf(path)]).toEqual([path, 'kept']);
    expect(classOf('receivers[0].fhir.recovery_enabled')).toBe('kept');
    expect(classOf('receivers[0].made_up')).toBe('unknown');
    expect(classOf('made_up.mode')).toBe('unknown');
    // A key that only starts like a row is not that row
    expect(classOf('mergesAllowed')).toBe('unknown');
  });
});

describe('the checklist', () => {
  const blank = { name: '' } as unknown as SiteReceiver;
  const full: SiteReceiver = {
    name: 'Bed Board',
    system: 'the ward whiteboard',
    category: 'history_of_record',
    tier: 3,
    applies: 'event_time',
    resend_timestamp: 'fresh',
    cancels: true,
    merges: false,
  };

  it("asks seven questions, the form's wording where it has one, with kind and tier required", () => {
    expect(QUESTIONS.map((q) => q.id)).toEqual([
      'name',
      'system',
      'category',
      'tier',
      'applies',
      'resend_timestamp',
      'takes',
    ]);
    expect(QUESTIONS.filter((q) => q.required).map((q) => q.id)).toEqual(['name', 'category', 'tier']);
    expect(QUESTIONS.filter((q) => q.who === 'A').map((q) => q.id)).toEqual(['system', 'category', 'tier']);
    expect(questionById('category').text).toBe('What kind of system is it?');
    expect(questionById('takes').text).toBe('Does it accept cancels (A11, A12, A13) and merges (A40)?');
  });

  it('reads a blank entry as unanswered throughout, and a full one as answered', () => {
    for (const q of QUESTIONS) {
      expect([q.id, holdsAnswer(q, blank)]).toEqual([q.id, false]);
      expect([q.id, holdsAnswer(q, full)]).toEqual([q.id, true]);
      expect(answerText(q, blank)).toBe('');
      expect(consequence(q, blank, recorded)).toBe(q.unanswered);
    }
    expect(answerText(questionById('category'), full)).toBe('History of record');
    expect(answerText(questionById('tier'), full)).toBe('Tier 3, clinical safety');
    expect(answerText(questionById('takes'), full)).toBe('Accepts cancels: yes. Takes merges: no.');
  });

  it("says what an answer does in the page's own words, read as the server reads the draft", () => {
    expect(consequence(questionById('category'), full, recorded)).toBe(
      'A PAS, an electronic patient record, a clinical data warehouse. Overtaken failure: asks a person to correct by hand.',
    );
    const policy = { ...recorded, policy: { '3': { single: 'automatic', ordered: 'per_chain' } } };
    expect(consequence(questionById('tier'), full, policy as SiteProfile)).toBe(
      'Who releases a write at tier 3: single failures, automatic; ordered chains, an approval per chain; interleaved chains, one approval.',
    );
    // An entry with no kind of its own takes an older profile's site-wide answer
    const older = { ...recorded, history_policy: 'correct' };
    const noKind = { name: 'Old', tier: 2, category: 'current_state' } as SiteReceiver;
    expect(consequence(questionById('category'), noKind, older)).toContain('closes, no write');
  });

  it('writes each explanation in two sentences of at most 40 words, and asks to explain, not to recommend', () => {
    for (const q of QUESTIONS) {
      const p = document.createElement('p');
      p.textContent = q.written;
      expect([q.id, layer1WordCount(p) <= 40]).toEqual([q.id, true]);
      expect([q.id, q.written.split(/(?<=[.?!])\s+/).length]).toEqual([q.id, 2]);
      expect(whyQuestion(q, 'Bed Board')).toMatch(/Explain; do not recommend one\.$/);
    }
  });
});
