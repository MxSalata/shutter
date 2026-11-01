import { describe, expect, it } from 'vitest';
import { TechDetail } from '@/components/TechDetail';
import { renderUi } from './render';
import { layer1Words } from './words';

function Page() {
  return (
    <div>
      <h1>Health</h1>
      <p>Ready to run cases.</p>
      <span className="mantine-VisuallyHidden-root">read by screen readers only</span>
      <TechDetail label="Reason codes" kind="data">
        <p>NOT_CONFIGURED and four more codes</p>
      </TechDetail>
    </div>
  );
}

describe('the first layer of a page', () => {
  it('counts the visible words outside closed disclosures, in Plain and in Technical', () => {
    const plain = renderUi(<Page />);
    expect(layer1Words(plain.container)).toEqual([
      'Health',
      'Ready',
      'to',
      'run',
      'cases.',
      'Reason',
      'codes',
    ]);
    plain.unmount();
    const technical = renderUi(<Page />, { detail: 'technical' });
    expect(layer1Words(technical.container)).toHaveLength(12);
  });
});
