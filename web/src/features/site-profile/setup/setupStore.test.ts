import { beforeEach, describe, expect, it } from 'vitest';
import { SIGNED_OUT } from '@/api/hooks';
import type { SiteProfileView } from '@/api/types';
import { recordedSiteProfile } from '@/mocks/profile';
import { toPutBody, validateProfile } from '../profile';
import { QUESTIONS, questionById } from './fields';
import {
  baseReceiver,
  changesOf,
  inForce,
  isDirty,
  nextQuestion,
  progress,
  receiverOf,
  resetSetupForTests,
  reviewStop,
  statusOf,
  unansweredOf,
  useSetup,
} from './setupStore';

const view = recordedSiteProfile()!;
const state = () => useSetup.getState();
const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;

beforeEach(() => {
  resetSetupForTests();
  state().open(view);
});

describe("Set up the site's draft", () => {
  it('starts as the stored profile, every answer of a receiver in force answered', () => {
    expect(state().draft).toEqual(view.profile);
    expect(isDirty(state())).toBe(false);
    const [first] = state().rids;
    expect(inForce(state(), first)).toBe(true);
    expect(baseReceiver(state(), first)?.name).toBe('Downstream Out');
    expect(nextQuestion(state(), first)).toBeNull();
    expect(progress(state(), first)).toEqual({ answered: 7, total: 7 });
    for (const q of QUESTIONS) expect(statusOf(state(), first, q)).toBe('in_force');
  });

  it("marks a changed answer of a receiver in force as the person's, and as in force again when put back", () => {
    const [first] = state().rids;
    const tier = questionById('tier');
    state().setKey(first, 'tier', 3);
    expect(statusOf(state(), first, tier)).toBe('you');
    expect(changesOf(state()).map((c) => c.path)).toEqual(['tier']);
    state().setKey(first, 'tier', view.profile.receivers[0].tier);
    expect(statusOf(state(), first, tier)).toBe('in_force');
    expect(isDirty(state())).toBe(false);
  });

  it('adds a receiver with nothing answered, in a shape the gate blocks every write to', () => {
    const rid = state().addReceiver();
    expect(state().focus).toBe(rid);
    expect(inForce(state(), rid)).toBe(false);
    const r = receiverOf(state(), rid)!;
    expect(r).toEqual({
      name: '',
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    });
    expect(nextQuestion(state(), rid)?.id).toBe('name');
    expect(progress(state(), rid)).toEqual({ answered: 0, total: 7 });
  });

  it('walks the checklist in order, counts what is answered and what is left, and never writes a default', () => {
    const rid = state().addReceiver();
    state().setKey(rid, 'name', 'Bed Board');
    expect(nextQuestion(state(), rid)?.id).toBe('system');
    state().leave(rid, 'system');
    expect(statusOf(state(), rid, questionById('system'))).toBe('left');
    expect(receiverOf(state(), rid)).not.toHaveProperty('system');
    expect(nextQuestion(state(), rid)?.id).toBe('category');
    state().setKey(rid, 'category', 'current_state');
    state().setKey(rid, 'tier', 2);
    state().leave(rid, 'applies');
    state().leave(rid, 'resend_timestamp');
    state().setKey(rid, 'cancels', false);
    expect(nextQuestion(state(), rid)).toBeNull();
    expect(progress(state(), rid)).toEqual({ answered: 4, total: 7 });
    expect(unansweredOf(state(), rid).map((q) => q.id)).toEqual(['system', 'applies', 'resend_timestamp']);
    // What was left is absent from the entry, not defaulted
    expect(Object.keys(receiverOf(state(), rid)!).sort()).toEqual(
      ['cancels', 'category', 'features', 'name', 'tier'].sort(),
    );
    // An answer given after all takes the question off the left list
    state().setKey(rid, 'system', 'the ward whiteboard');
    expect(statusOf(state(), rid, questionById('system'))).toBe('you');
    expect(validateProfile(toPutBody(state().draft!, view.version))).toBe('expectedVersion: unknown field');
    expect(validateProfile(state().draft)).toBe('');
  });

  it('stops the review for a receiver being added with no name, kind or tier, and never for one in force', () => {
    expect(reviewStop(state())).toBeNull();
    const rid = state().addReceiver();
    expect(reviewStop(state())).toEqual({
      rid,
      question: 'name',
      message: 'Name the receiver being added before review',
    });
    state().setKey(rid, 'name', 'Bed Board');
    expect(reviewStop(state())?.message).toBe('Answer the kind of Bed Board before review');
    state().setKey(rid, 'category', 'orders_results');
    expect(reviewStop(state())?.message).toBe('Answer the tier of Bed Board before review');
    state().setKey(rid, 'tier', 3);
    expect(reviewStop(state())).toBeNull();
  });

  it('discards to the stored profile with nothing kept, and removes a receiver added here', () => {
    const rid = state().addReceiver();
    state().setKey(rid, 'name', 'Bed Board');
    state().leave(rid, 'system');
    state().removeAdded(rid);
    expect(state().draft).toEqual(view.profile);
    expect(state().focus).toBeNull();
    const again = state().addReceiver();
    state().setKey(again, 'name', 'Bed Board');
    state().discard();
    expect(state().draft).toEqual(view.profile);
    expect(state().prov).toEqual({});
    expect(state().left).toEqual({});
    expect(state().added).toEqual({});
    // A receiver in force is not removed from here
    const [first] = state().rids;
    state().removeAdded(first);
    expect(state().draft).toEqual(view.profile);
  });

  it('keeps the draft when the same version is read again, and says so when another version was saved', () => {
    const rid = state().addReceiver();
    state().setKey(rid, 'name', 'Bed Board');
    state().open(clone(view));
    expect(receiverOf(state(), rid)?.name).toBe('Bed Board');
    expect(state().moved).toBe(false);
    const newer: SiteProfileView = { ...clone(view), version: view.version + 1 };
    state().open(newer);
    expect(state().moved).toBe(true);
    expect(receiverOf(state(), rid)?.name).toBe('Bed Board');
    // With no changes, the newer version is simply the one the draft starts from
    state().discard();
    state().open(newer);
    expect(state().base?.version).toBe(view.version + 1);
    expect(state().moved).toBe(false);
  });

  it('hands the draft over as it was, takes a draft back by name, and starts again from a saved version', () => {
    const rid = state().addReceiver();
    state().setKey(rid, 'name', 'Bed Board');
    state().setKey(rid, 'category', 'current_state');
    state().setKey(rid, 'tier', 2);
    state().handOver();
    expect(state().handover).toEqual({ draft: state().draft, baseVersion: view.version, drafted: [] });
    expect(state().takeHandover()?.baseVersion).toBe(view.version);
    expect(state().handover).toBeNull();
    // The Site profile page changed the tier and added a receiver of its own
    const next = clone(state().draft!);
    next.receivers[next.receivers.length - 1].tier = 3;
    next.receivers.push({ name: 'Another', tier: 1 });
    state().adopt(next);
    expect(state().rids).toHaveLength(next.receivers.length);
    expect(state().rids[next.receivers.length - 2]).toBe(rid);
    expect(statusOf(state(), rid, questionById('tier'))).toBe('you');
    expect(inForce(state(), state().rids[0])).toBe(true);
    expect(inForce(state(), state().rids[next.receivers.length - 1])).toBe(false);
    const saved: SiteProfileView = {
      ...clone(view),
      version: view.version + 1,
      profile: next,
      source: 'api',
    };
    state().saved(saved);
    expect(isDirty(state())).toBe(false);
    expect(state().added).toEqual({});
    expect(state().rids.every((id) => inForce(state(), id))).toBe(true);
  });

  it('forgets the draft at a sign-out', () => {
    const rid = state().addReceiver();
    state().setKey(rid, 'name', 'Bed Board');
    state().handOver();
    window.dispatchEvent(new Event(SIGNED_OUT));
    expect(state().draft).toBeNull();
    expect(state().handover).toBeNull();
    expect(state().rids).toEqual([]);
  });
});
