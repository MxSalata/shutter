import { Button, Menu, Tooltip } from '@mantine/core';
import { act, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderUi } from './render';

/** Lets Floating UI place what is open, and Mantine's transitions end. */
const placed = () =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 300));
  });

describe('floating parts in jsdom (setup.ts)', () => {
  it('opens a tooltip at once, and keeps an open menu visible once it is placed', async () => {
    renderUi(
      <>
        <Tooltip label="The hint" opened>
          <Button>Hinted</Button>
        </Tooltip>
        <Menu>
          <Menu.Target>
            <Button>Open</Button>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Item>First item</Menu.Item>
          </Menu.Dropdown>
        </Menu>
      </>,
    );
    const started = performance.now();
    await placed();
    // Without the setup's measurements this one tick took 50 to 70 s on the development machine
    expect(performance.now() - started).toBeLessThan(5_000);
    expect(screen.getByText('The hint')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: 'Open' }));
    await placed();
    expect(screen.getByRole('menuitem', { name: 'First item' })).toBeVisible();
  });
});
