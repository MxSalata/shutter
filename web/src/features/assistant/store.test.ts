import { afterEach, describe, expect, it } from 'vitest';
import { SIGNED_OUT } from '@/api/hooks';
import { resetAssistantForTests, useAssistant } from './store';

afterEach(() => resetAssistantForTests());

describe('the Ask Shutter panel on a sign-out', () => {
  it("forgets the tab's questions, so the next person to sign in never sees them, and keeps the panel as it was", () => {
    useAssistant.getState().setOpen(true);
    useAssistant.getState().openForCase('C-000008');
    useAssistant
      .getState()
      .addAsked('cases', { questionId: 'PQ-000001', question: 'Which cases wait for me?' });
    expect(useAssistant.getState().threads.cases).toHaveLength(1);
    window.dispatchEvent(new Event(SIGNED_OUT));
    expect(useAssistant.getState().threads).toEqual({});
    expect(useAssistant.getState().autoAsk).toBeNull();
    expect(useAssistant.getState().open).toBe(true);
  });
});
