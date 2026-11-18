import { describe, expect, it } from 'vitest';
import type { SiteEntryItem, SiteProfile } from '@/api/types';
import { kindChangeRefusal, kindChanges, kindChangesRead, kindChangeWords } from './kindChanges';

/** A profile of receivers by name and kind (undefined: no kind answered). */
const profile = (receivers: [string, string?][]): SiteProfile =>
  ({ receivers: receivers.map(([name, category]) => ({ name, ...(category ? { category } : {}) })) }) as unknown as SiteProfile;

/** An active entry that reads the kind, with the scope given. */
const entry = (id: string, kinds: string[], scope: Record<string, string[]> = {}, extra: Partial<SiteEntryItem> = {}) =>
  ({
    id,
    state: 'active',
    kind: 'stop',
    title: `Entry ${id}`,
    sentence: '',
    content: { title: `Entry ${id}`, pattern: { event: ['merge'], receiver_category: kinds }, scope },
    activeVersion: 1,
    draftVersion: 0,
    revision: 1,
    needsReview: false,
    casesSent: 0,
    casesSent30: 0,
    ...extra,
  }) as unknown as SiteEntryItem;

describe("what a changed kind does to the site's own entries, as Shutter.Test.SiteEntryLifecycle holds the core to it", () => {
  const before = profile([['Downstream Out', 'current_state']]);
  const after = profile([['Downstream Out', 'history_of_record']]);

  it('lists nothing while no active entry reads the kind', () => {
    expect(kindChanges(before, after, [])).toEqual([]);
    const plain = entry('L1', []);
    plain.content!.pattern = { event: ['merge'] };
    expect(kindChanges(before, after, [plain])).toEqual([]);
    expect(kindChanges(before, after, [entry('L2', ['current_state'], {}, { state: 'suspended' })])).toEqual([]);
  });

  it('names the entry a receiver leaves, and the one it comes into', () => {
    const items = [entry('L1', ['current_state']), entry('L2', ['history_of_record'])];
    expect(kindChanges(before, after, items)).toEqual([
      { entry: 'L1', title: 'Entry L1', receiver: 'Downstream Out', from: 'current_state', to: 'history_of_record', change: 'leaves' },
      { entry: 'L2', title: 'Entry L2', receiver: 'Downstream Out', from: 'current_state', to: 'history_of_record', change: 'enters' },
    ]);
  });

  it('reads a receiver with no kind, or none in the profile, as current_state', () => {
    const items = [entry('L1', ['current_state'])];
    expect(kindChanges(profile([['Downstream Out']]), after, items)).toHaveLength(1);
    // A receiver added with a kind, and one removed that had one
    expect(kindChanges(profile([]), profile([['Bed Board', 'orders_results']]), items)[0]).toMatchObject({ receiver: 'Bed Board', change: 'leaves' });
    expect(kindChanges(profile([['Bed Board', 'orders_results']]), profile([]), items)[0]).toMatchObject({ receiver: 'Bed Board', change: 'enters' });
    expect(kindChanges(profile([['Downstream Out']]), profile([['Downstream Out', 'current_state']]), items)).toEqual([]);
  });

  it('leaves out a receiver outside the entry receiver scope, and a change between two kinds the pattern reads alike', () => {
    expect(kindChanges(before, after, [entry('L1', ['current_state'], { receiver: ['Ward Whiteboard'] })])).toEqual([]);
    expect(kindChanges(before, after, [entry('L1', ['current_state'], { receiver: ['Downstream Out'] })])).toHaveLength(1);
    expect(kindChanges(before, after, [entry('L1', ['current_state', 'history_of_record'])])).toEqual([]);
  });

  it('reads the pattern and the scope in force when a recheck widened them', () => {
    const widened = entry('L1', ['current_state'], {}, { effectivePattern: { event: ['merge'] } });
    expect(kindChanges(before, after, [widened])).toEqual([]);
    const scoped = entry('L1', ['current_state'], { receiver: ['Downstream Out'] }, { effectiveScope: { ward: ['WARD-B'] } });
    expect(kindChanges(before, profile([['Ward Whiteboard', 'history_of_record']]), [scoped])).toHaveLength(1);
  });

  it('lists an entry that cannot be read while any kind changes', () => {
    const unread = entry('L3', [], {}, { content: undefined, unreadable: 'its version cannot be read' });
    expect(kindChanges(before, after, [unread])).toEqual([{ entry: 'L3', title: '', receiver: '', from: '', to: '', change: 'unread' }]);
    expect(kindChanges(before, before, [unread])).toEqual([]);
  });

  it('says each in words, and refuses until every entry listed is named as read', () => {
    const changes = kindChanges(before, after, [entry('L1', ['current_state']), entry('L2', ['history_of_record'])]);
    expect(changes.map(kindChangeWords)).toEqual([
      'Downstream Out (current_state to history_of_record) leaves the pattern of L1 (Entry L1), which then no longer stops its cases',
      'Downstream Out (current_state to history_of_record) comes into the pattern of L2 (Entry L2), which then stops its cases too',
    ]);
    expect(kindChangesRead(changes)).toEqual(['L1', 'L2']);
    expect(kindChangeRefusal(changes, [])).toContain('kindChangesRead');
    expect(kindChangeRefusal(changes, ['L1'])).toContain('comes into the pattern of L2');
    expect(kindChangeRefusal(changes, ['L1'])).not.toContain('pattern of L1');
    expect(kindChangeRefusal(changes, ['L1', 'L2'])).toBe('');
    expect(kindChangeRefusal([{ entry: '', title: '', receiver: '', from: '', to: '', change: 'unread' }], ['L1'])).toContain(
      'an active site entry cannot be read',
    );
  });
});
