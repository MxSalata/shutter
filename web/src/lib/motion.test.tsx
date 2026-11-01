import { act, render } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useStagedReveal } from './motion';

const reduced = vi.hoisted(() => ({ on: false }));
vi.mock('@mantine/hooks', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@mantine/hooks')>()),
  useReducedMotion: () => reduced.on,
}));

function Steps({ start, onDone }: { start: boolean; onDone: () => void }) {
  const { stepProps, done } = useStagedReveal(3, { start, onDone });
  return (
    <ol data-done={done}>
      {[0, 1, 2].map((i) => (
        <li key={i} className="lifecycle-step" {...stepProps(i)} />
      ))}
    </ol>
  );
}

const revealed = (c: HTMLElement) =>
  [...c.querySelectorAll('li')].map((li) => li.getAttribute('data-revealed') === 'true');

describe('the staged reveal of the replay after a trial approval', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    vi.useRealTimers();
    reduced.on = false;
  });

  it('reveals nothing before it starts, then one step every 400 ms, and says it is done once', () => {
    const onDone = vi.fn();
    const { container, rerender } = render(<Steps start={false} onDone={onDone} />);
    expect(revealed(container)).toEqual([false, false, false]);
    rerender(<Steps start onDone={onDone} />);
    expect(revealed(container)).toEqual([true, false, false]);
    act(() => vi.advanceTimersByTime(400));
    expect(revealed(container)).toEqual([true, true, false]);
    act(() => vi.advanceTimersByTime(400));
    expect(revealed(container)).toEqual([true, true, true]);
    act(() => vi.advanceTimersByTime(2000));
    expect(onDone).toHaveBeenCalledOnce();
  });

  it('shows the final state at once under reduced motion', () => {
    reduced.on = true;
    const onDone = vi.fn();
    const { container } = render(<Steps start onDone={onDone} />);
    expect(revealed(container)).toEqual([true, true, true]);
    expect(onDone).toHaveBeenCalledOnce();
  });
});
